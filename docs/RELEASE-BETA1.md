# AirPods Compat Beta 1 — jailbreak prerelease

Tag: `v0.0.1-beta.1`  
Debian package version: `0.0.1~beta1`  
Baseline: `a30615d3c36e63c8ebe55e6400697c967d3ccae3`

Beta 1 labels the legacy jailbreak version restored to the test phone on
2026-11-01. Its tweak source, resources, model data and injection filters match
the baseline. Only package version metadata changes within `tweak/`. The added
release workflow verifies that boundary and builds both package schemes.

This release excludes the refactor branch's new ANC Settings buttons, its third
control dylib, its Control Center noise-control bundle and its CCSupport
recommendation. Existing native OS behavior remains as in the baseline.

## Downloads and installation

- `AirPodsCompat-Beta1-rootless-iphoneos-arm64.deb`: Dopamine/rootless; installs
  under `/var/jb`.
- `AirPodsCompat-Beta1-rootful-iphoneos-arm.deb`: rootful package layout; installs
  under `/`.
- `SHA256SUMS`: verify the downloaded deb before installation.
- Build logs: compiler output for each package scheme.

Install the matching deb using Sileo/Zebra or `dpkg -i /absolute/path/package.deb`,
then restart affected UI clients, Bluetooth and SpringBoard. A downgrade warning
when replacing `0.0.1` with `0.0.1~beta1` is expected under Debian prerelease
ordering. Retain the previous package and preferences for recovery.

## Evidence and limitations

The restored baseline was checked on iOS 16.1.1 / 20B101, Dopamine rootless and
ElleKit 1.2. Rollback verified package files and confirmed the new control module
was absent after restarting SpringBoard. Rootful builds are package-validated;
they have no current physical-device acceptance result.

The release workflow runs the existing exhaustive legacy resource-policy test,
checks that runtime source matches the baseline, and validates package version,
architecture, paths, required files, both arm64/arm64e slices and absence of the
experimental noise-control components. Compilation is not a device feature pass.

Actual AirPods 5 ANC/transparency remains unverified for this release. Earlier
historical ANC acceptance language does not establish a current acoustic test.
No separate charging-case power record was established, and no case percentage
is synthesized. iOS 18/26 physical behavior and universal application icon
coverage are not established by this Beta. The companion IPA is not part of
this jailbreak-only prerelease.
