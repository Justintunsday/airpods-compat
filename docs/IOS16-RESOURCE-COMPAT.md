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
before installation. Hooks install only in SpringBoard on iOS 16. A thread-local
depth guard wraps the original asset initializer and unwinds in @finally. Only
productIdentifier reads inside that resource scope borrow a model. Reads outside
the scope, route selection and daemon identities retain their original values.

Battery glyph borrowing copies vendor, transport, category and parts into a
disposable resource model and invokes the saved original implementation directly.
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
