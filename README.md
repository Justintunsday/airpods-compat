# AirPods Compat Beta 1

AirPodsCompat is a jailbreak tweak that adds missing AirPods model registrations
and adapts headphone Settings, audio-route icons, and battery resources on older
iOS versions. A separate SwiftUI companion app provides configuration and device
diagnostics.

**Current prerelease: [Beta 1 — v0.0.1-beta.1](https://github.com/Justintunsday/airpods-compat/releases/tag/v0.0.1-beta.1).**
The Debian package version is `0.0.1~beta1`.

Beta 1 uses the restored legacy implementation from `a30615d`, with the same
runtime code and injection filters. It excludes the architecture-refactor
branch's new ANC Settings buttons and Control Center noise-control module.
See the [release notes](docs/RELEASE-BETA1.md) for the release scope and validation
record.

## Downloads

| Package | Jailbreak layout | Installation prefix |
| --- | --- | --- |
| [Rootless deb](https://github.com/Justintunsday/airpods-compat/releases/download/v0.0.1-beta.1/AirPodsCompat-Beta1-rootless-iphoneos-arm64.deb) | Dopamine/rootless; `iphoneos-arm64` | `/var/jb` |
| [Rootful deb](https://github.com/Justintunsday/airpods-compat/releases/download/v0.0.1-beta.1/AirPodsCompat-Beta1-rootful-iphoneos-arm.deb) | Rootful; `iphoneos-arm` | `/` |

[SHA-256 checksums](https://github.com/Justintunsday/airpods-compat/releases/download/v0.0.1-beta.1/SHA256SUMS)
and compiler logs are attached to the prerelease. The companion IPA is a separate
build and is not included in this jailbreak-only release.

## Installation

1. Download the package matching your jailbreak layout and verify its checksum.
2. Install it with Sileo/Zebra, or run `dpkg -i /absolute/path/package.deb`.
3. Restart the affected Settings/audio apps, Bluetooth, and SpringBoard, or
   perform a userspace restart using your jailbreak's tools.

Debian sorts `0.0.1~beta1` before `0.0.1`, so installing Beta 1 over the older
package can produce a downgrade warning. Keep the previous deb and preferences
for recovery.

The companion app requires a separately signed installation. On a non-jailbroken
device it provides diagnostics; it does not install the system compatibility
hooks. Shared configuration writes require access to the tweak's preference
file, and the app reports save failures when that access is unavailable.

## Compatibility and current evidence

| Environment or feature | Evidence |
| --- | --- |
| iPhone SE 2, iOS 16.1.1 / 20B101, Dopamine rootless, ElleKit 1.2 | The legacy baseline was restored and its package files checked. The new noise-control module was absent after restarting SpringBoard. |
| Beta 1 rootless and rootful packages | Both CI builds passed resource-policy and package validation, including architecture, paths, and arm64/arm64e slices. |
| Rootful installation on hardware | Not validated in the current test session. |
| AirPods 5 ANC/transparency | Actual listening-mode behavior and acoustic results remain unverified for this release. |
| iOS 18 and iOS 26 hardware | No current physical-device validation. |
| Independent charging-case battery | No verified Case power-source record; no case percentage is synthesized. |
| Icons in arbitrary applications | Coverage depends on the process and resource implementation used by each UI. |

The analysis workflow includes targets for iOS 15.6.1, 16.6.1, 17.7, 18.6.2,
26.6.2, and 27.0. These are binary-analysis targets, not a list of systems with
confirmed device functionality. Historical acceptance notes should be read
alongside the current Beta 1 limitations.

## How it works

- **Missing-model registration:** by default, only missing newer models in the
  `core` tier are registered. Older models and Beats entries require `Scope=all`.
- **Accessory class selection:** registration prefers the abstract
  `UARPSupportedAccessoryAirPodsBud`, `Case`, and `CaseUSB` base classes, with
  concrete classes as fallbacks.
- **Process responsibilities:** UARP registration runs in `bluetoothd`,
  `bluetoothuserd`, `bluetoothaudiod`, and `uarpd`. UI hooks handle names,
  Settings resources, and feature-content selection in their owning processes.
- **Registration crash guard:** each accessory daemon creates its own marker
  before registration and removes it after completion. A leftover marker makes
  that daemon skip registration on later launches. Investigate the failure before
  removing `.registration-in-progress.<process>` from the AirPodsCompat support
  directory.
- **Existing native entries:** model registration skips accessory classes already
  present in the OS. Registering a model does not establish support for all of
  its hardware features.

The support directory is `/Library/Application Support/AirPodsCompat/` on
rootful installations and `/var/jb/Library/Application Support/AirPodsCompat/`
on rootless installations.

Beta 1 retains the legacy resource filters for MediaPlayer, MediaControls,
SpringBoard, and MusicUIService. These framework filters can also load hooks in
applications that use those frameworks. An in-memory framework hook affects
only its host process; it does not change every application's icon database.
Ordinary audio playback does not require injecting every playback app.

## Model registry

The registry contains **33 accessory classes**, including AirPods 1–5, AirPods
Pro 1–3, AirPods Max 1–2, charging-case variants, and related Beats accessories.
These entries describe model identities and registration data, not 33 verified
sets of working features.

`tools/extract_airpods_models.py` extracts the model table from CoreUARP
binary analysis. Its generated data is stored in:

- `models/airpods.json` — source model table.
- `tweak/layout/Library/Application Support/AirPodsCompat/AirPodsCompatModels.plist`
  — installed tweak data.
- `app/Resources/Models.json` — companion-app data.

Alternate model relationships include A3532/A3531, A3440/A3439, A3064/A3063,
and A3048/A3047.

## Configuration

The tweak reads:

```text
/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist
```

This user-data path is not prefixed with `/var/jb`. Preferences are loaded when
an affected process starts, so restart those processes after changing them.

| Key | Values and default behavior |
| --- | --- |
| `Enabled` | Master switch; defaults to `true`. |
| `UARPEnabled` | Missing-model registration; defaults to `true`. |
| `Scope` | Defaults to the newer `core` models; `all` includes the full registry. |
| `BorrowProfile` | `airpods4anc` by default; also accepts `airpodspro2`, `airpodspro3`, or `off`. |
| `LegacyUIProfile` | AirPods 3 by default; accepts `airpods3`, `airpods4anc`, `airpodspro2`/`pro2`, `airpodspro3`, or `off`. |
| `LegacyIconProfile` | AirPods 3 by default; use `airpods3`, `pro2`/`airpodspro2`, or `off`. `airpods4anc` also uses the legacy AirPods 3 icon resources. |
| `DiagnosticsEnabled` | Diagnostic logging; defaults to `false`. |

### Legacy Settings on iOS 16/17

The legacy Settings path uses HeadphoneConfigs templates. AirPods 5 model-name
keys are mapped to readable names, while the default compatibility profile
borrows AirPods 3 layout resources.

On iOS 16, an unknown headphone header resource can be mapped to the native
AirPods 3 `B688` image. The displayed illustration can therefore look like
AirPods 3 while the name remains AirPods 5. This is presentation compatibility;
it does not establish ANC/transparency support.

### Feature-content borrowing on iOS 26

The legacy implementation targets
`HeadphoneDevice.allFeatureContents(productID:device:)` when the required
HeadphoneManager factory is available. For AirPods 5 IDs `0x2036`, `0x2030`,
`0x2037`, and `0x2032`, its default lookup target is AirPods 4 (ANC), `0x201b`,
using Apple's existing `B768FeatureContent` implementation.

Optional targets are AirPods Pro 2 (`B698`, `0x2014`) and AirPods Pro 3 (`B788`,
`0x2027`). The native AirPods 5 provider is `B868FeatureContent`; the legacy code
skips borrowing when its native-support check succeeds. Systems without the
required factory retain the older registration and UI paths.

This code path is preserved from the baseline. Its presence and binary-analysis
evidence do not establish working iOS 26 features on a physical device. Detailed
call-chain research is in [ANALYSIS.md](docs/ANALYSIS.md), sections 11.12–11.16.

## Companion diagnostics

The app can report audio routes through AVAudioSession, inspect available
BluetoothManager data, and decode nearby Apple pairing advertisements. AirPods 5
IDs are highlighted in the device probe. Nearby advertisements, paired devices,
and connected audio routes are shown as different observations.

The registration self-test uses the app's own process and can export its report.
Successful app-local registration or a detected framework does not prove that
system hooks are installed or that a headphone feature works.

## Building and testing

The [Beta 1 build](https://github.com/Justintunsday/airpods-compat/actions/runs/41265080385)
passed both package schemes. Its workflow checks that tweak runtime files match
baseline `a30615d`, then validates the release version, package contents,
installation prefix, binary architectures, and absence of the experimental
noise-control components.

With Theos and the required iOS SDK configured, build locally using:

```sh
# Rootless
make -C tweak package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# Rootful
make -C tweak package FINALPACKAGE=1 \
  THEOS_PACKAGE_ARCH=iphoneos-arm THEOS_PACKAGE_INSTALL_PREFIX=
```

Run the legacy resource-policy test with a C compiler:

```sh
clang -std=c11 -Wall -Wextra -Werror \
  tests/legacy_resource_policy.c -o /tmp/airpods-resource-policy
/tmp/airpods-resource-policy
```

The test covers target IDs, unrelated devices, vendor/transport guards, battery
part handling, and exact route-model matching. The separate app test workflow
uses simulator UARP stubs to test registry completeness, registration, and unique
accessory identifiers. Simulator tests are separate from hardware acceptance.

| Workflow | Output |
| --- | --- |
| `build-beta1.yml` | `beta1-rootless` and `beta1-rootful` artifacts: deb, checksum, compiler log, and release notes. |
| `build-tweak.yml` | Legacy combined `airpodscompat-deb` artifact. |
| `build-app.yml` | Separate unsigned companion IPA, `airpodscompat-app`. |
| `test-app.yml` | Companion simulator unit tests. |
| `dsc-analysis.yml` | Version-specific dyld shared-cache analysis artifacts. |

## Repository layout

```text
.github/workflows/   Package builds, app builds, tests, and binary analysis
analysis/            Shared-cache extraction and targeted inspection scripts
models/airpods.json  Source accessory registry
tools/               Model extraction, disassembly, and package validation
tweak/               Theos tweak, resource hooks, model data, and filters
app/                 SwiftUI companion, diagnostics, and simulator tests
docs/                Release notes and technical research
```

The binary-analysis workflow runs `bash analysis/run.sh <version> [build] [device]`,
extracts selected shared-cache images with `ipsw`, and inspects CoreUARP,
CoreBluetooth, and HeadphoneManager. iOS versions without the cryptex path use
the full-firmware fallback described in the script.

Further reading: [Beta 1 release notes](docs/RELEASE-BETA1.md),
[technical analysis](docs/ANALYSIS.md), and
[iOS 16 resource research](docs/IOS16-RESOURCE-COMPAT.md).
