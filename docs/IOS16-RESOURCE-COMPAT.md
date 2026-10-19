# iOS 16 resource compatibility investigation

## Scope and evidence

Investigated on iOS 16.1.1 (20B101), with ElleKit 1.2. The previously installed
tweak had been removed before the baseline. Existing Settings naming, header
image and listening-mode implementation is retained. No device names, addresses
or device identifiers are needed to reproduce the findings below.

### Audio output data flow

| Stage / process | Interface and ABI | Observed evidence | Decision |
| --- | --- | --- | --- |
| bluetoothd | CoreBluetooth / Bluetooth IPC | Earlier supplied daemon evidence reports ppPI 0x2036; serialization boundary remains unconfirmed | Remove failed BTDeviceGetDeviceId, dictionary and setter rewrites; do not change daemon PID |
| SpringBoard / MediaRemote | MRAVConcreteOutputDevice modelID → NSString; deviceType/deviceSubtype → integer | Actual connected device: modelID `BTHeadphones76,8246`, type 2, subtype 2 | Identity survives IPC as decimal Apple vendor/product pair |
| SpringBoard / MediaPlayer | MPAVOutputDeviceRoute productIdentifier → object; routeSubtype → q; outputDevices → NSArray | Same model string, routeSubtype 11, isAirpodsRoute false | The prior `name` KVC probe threw before reading later fields; nil logs were inconclusive |
| SpringBoard / MediaControls | -[MRUOutputDeviceAsset outputDeviceAssetTypeForOutputDeviceRoute:] → integer | Factory baseline: type 6. Static iOS 16 code at 0x1a8d7b0e8 tests isAirpodsRoute, then routeSubtype | Hooking MRAVOutputDevice.isAirPods did not address this classifier |
| SpringBoard / MediaControls | -initWithOutputDeviceRoute: → object; -icon → UIImage | Scoped model substitution to `BTHeadphones76,8211`: native type 8 and UIImage; original identifier restored afterward | Borrow only during synchronous asset construction; retain native composite icon construction |

Static reference: iOS 16 MRUOutputDeviceAsset init at 0x1a8d7abac; icon at
0x1a8d7b098 delegates to image. No HeadphoneConfigs layout dictionary is treated
as an image, and no Assets.car name is assumed loadable through UIImage.

### Batteries data flow (independent)

| Stage / process | Interface and ABI | Observed evidence | Decision |
| --- | --- | --- | --- |
| Power sources → SpringBoard | _BCPowerSourceController connectedDevices → NSArray | Actual live BCBatteryDevice: PID 8246, vendor 1, transport 3, parts 1, accessoryCategory 2 | No evidence requires a daemon change |
| SpringBoard / BatteryCenterUI | BCBatteryDevice batteryWidgetGlyphName: → @, out BOOL pointer (`o^B`) | Real PID returns `headphones`, image flag false | Independent model-to-resource lookup |
| SpringBoard / BatteryCenterUI | batteryDeviceWithIdentifier:vendor:productIdentifier:parts:matchIdentifier: → @, args @ q q Q @ | Disposable PID 8211 model with original vendor/transport/category/parts returns `B688.left`, image flag true; batteryWidgetGlyph returns UIImage | Use original glyph implementation on disposable resource model, leaving live device and charge data untouched |
| Widget presentation | BCUIBatteryAvocadoViewController loaded in SpringBoard | Runtime confirms class and power-source controller in this process | No speculative extension injection; displayed-widget call tracing still required for final UI acceptance |

## Implementation and fallback

`tweak/LegacyResourcePolicy.h` contains exact Apple model-string and PID
allowlists. It rejects names, non-Apple vendor strings, suffix matches, unrelated
PIDs and battery transports/vendors. C tests exhaust all 16-bit unrelated PIDs.

`tweak/LegacyResources.h` validates every new selector's argument and return ABI
before installation. Route hooks install in iOS 16 UI clients; battery hooks only
install in SpringBoard. A thread-local
depth guard wraps the original asset initializer and unwinds in @finally. Only
productIdentifier reads inside that resource scope borrow a model. Reads outside
the scope, route selection and daemon identities retain their original values.

Battery glyph borrowing copies vendor, transport and category into a disposable
resource model and invokes the saved original implementation directly. Explicit
parts are preserved. A Single resource (parts 0) selects combined earbuds for a
known earbud PID, or a case image only for a known case PID. Live parts never change.
Nil/generic results fall back to the live model's original glyph and flag. No
battery levels, connected-device arrays or coalescing rules are changed.

Preferences live at
`/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist`:

| Key | Default | Purpose |
| --- | --- | --- |
| Enabled | true | Existing master switch |
| LegacyRouteResourcesEnabled | true | New control-center asset scope |
| LegacyBatteryResourcesEnabled | true | New battery resource borrowing |
| DiagnosticsEnabled | false | Existing diagnostic messages; method dumps and MRU probes removed |
| LegacyUIProfile / LegacyIconProfile | Existing defaults | Existing Settings compatibility |

Changes to startup preferences require restarting the affected UI process. User
preferences must not use the jailbreak installation prefix. Installation assets
continue to use rootless paths. Existing UARP registration is unchanged; this
patch adds no UARP, authentication or Bluetooth protocol substitution.

## Validation record

The baseline and isolated live comparisons above are observed results, not proof
that the final packaged tweak renders correctly. CI, packaged runtime execution,
visual checks and regression status are recorded below after deployment.

## MediaPlayer factory and app coverage

The first package fixed MRU asset classification, but output lists still showed
generic icons. A separate observed factory,
`+[MPAVRoutingController _symbolNameForRoute:]`, returned `speaker.bluetooth.fill`.
Scoped borrowing changed it to `airpods.gen3`. Four class methods now enter the
same resource scope: `_symbolNameForRoute:`, `_symbolNameForRoutes:`,
`_symbolImageForRoute:`, `_symbolImageForRoutes:`. Their observed ABI is
`@24@0:8@16`. Multi-route composition remains native.

App-owned output presentation needs compatibility inside its UI process. The
final package separates `AirPodsCompatResources.dylib` from the existing tweak.
Its filter matches loaded MediaPlayer/MediaControls bundles, SpringBoard and
MusicUIService. A runtime guard additionally requires an app/extension with
UIApplication (or SpringBoard), and iOS 16. The existing Settings/CoreBluetooth/
UARP module is not injected into other apps. This is not an all-UIKit filter.
Apps loading the frameworks only after ElleKit's initial filter evaluation and
custom icon paths remain outside verified coverage.

Filter implementation inspected:
https://github.com/tealbathingsuit/ellekit/blob/main/injector/injector.c
(`tweak_needinject`, CFBundleGetBundleWithIdentifier).

## Packaged validation and acceptance

Built source: `934caa7`, branch `codex/ios16-legacy-ui-20261019`.
CI: https://github.com/Justintunsday/airpods-compat/actions/runs/39253816288

Both rootless/rootful builds and C policy tests passed in that run. Tests compile
with `-Wall -Wextra -Werror`, cover all 16-bit unrelated PIDs, vendor/transport
guards, exact route models and resource-part fallbacks. Only rootless deployed.

Rootless SHA-256:
`2965968114a0874e6c7fe6895d854c573591f9094b19aac8e41236c5c942d4c3`.
Device-side hash matched; dpkg reported successful installation.

Final SpringBoard runtime resolved the symbol factory to
`AirPodsCompatResources.dylib`, returned `airpods.gen3`, and retained real model
`BTHeadphones76,8246` outside lookup. Battery glyphs included B688.left/B688.right
with the native image-resource flag and UIImage. Phone glyph stayed iphone.gen1.
Synthetic factory comparisons are not screen evidence; screen acceptance below
comes from the user's explicit follow-up confirmations.

Prior working debs and the prior installed main dylib were backed up on-device.
The user had uninstalled the tweak before the baseline; no initial installed
dylib or existing preference file was available to back up.

| Acceptance item | Status | Evidence / limit |
| --- | --- | --- |
| AirPods 5 name | PASS | User confirmed other Settings behavior normal |
| Settings header image | PASS | User regression confirmation; existing mapping retained |
| ANC / transparency | PASS | User regression confirmation |
| Preferences stability | PASS | No new Preferences reports in observation window; not a stress test |
| Control Center output icon | PASS | User confirmed after MediaPlayer factory patch |
| Music / expanded output UI | PASS | User confirmed corrected |
| PosterBoard player and Podcasts | PASS | User confirmed both after framework-filtered package |
| Earbud and Single battery glyphs | PASS | Native glyph evidence; user confirmed generic entry changed |
| True separate charging-case telemetry | FAIL | No Case power-source record observed |
| Audio playback | PASS | User reported remaining behavior normal |
| bluetoothd stability | PASS | Same daemon process throughout; no new daemon crash observed |
| Real identity outside resource scope | PASS | Route model and live battery PID retained; daemon rewrites removed |
| Rootless deb build / install | PASS | CI, matching SHA-256, successful dpkg installation |
| Other physical headphones/speakers | UNVERIFIED | No second connected device; policy exclusions and phone glyph checked |
| Disable-switch restart regression | UNVERIFIED | Startup switches implemented; live off/on test not performed |

### Remaining charging-case limitation

Opening/closing the case changed published records. An observed snapshot from
IOPSCopyPowerSourcesByType(0) contained Internal, Single, Left and Right. Single
and Left were both 84%, Right 97%, and all accessory records retained PID 8246.
There was no `Part Identifier = Case`. BCBatteryDevice accordingly used parts
0, 1 and 2. Later only a left-earbud record remained. The user had interpreted
the generic Single entry as the case, but that physical correspondence is not
established by these records.

Existing sharingd SFBLEDevice advertisement fields contained one SFBatteryInfo
entry (type 4, level approximately 0.84–0.86). This does not establish a case
measurement. Earlier CBDevice decoder probes observed no calls. Inspection found
the older SFBLEScanner / SDProximityPairingAgent power-source pipeline, but the
decode-to-Case boundary remains unconfirmed; no speculative hook was installed.

Single now uses a combined AirPods resource. It is not relabeled as Case, no
charge values are synthesized, and left/right telemetry is not merged. True
separate case support still requires upstream decoding/publication evidence.
