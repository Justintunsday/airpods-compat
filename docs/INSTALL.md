# Install, configure and recover

Use **rootless-iphoneos-arm64.deb** for Dopamine/ElleKit (/var/jb), or
**rootful-iphoneos-arm.deb** for a compatible rootful environment (/).
Verify SHA256SUMS from the same build artifact before installing. CI checks the
actual control architecture, install paths, both dylibs, filters, model data and
the arm64/arm64e executable slices. This is not evidence of jailbreak support on
every iOS release. An iOS 18/26 runtime hook requires a suitable injection environment.

Install with Sileo/Zebra or `dpkg -i /absolute/path/package.deb`, then restart the
affected processes or userspace when convenient. This package does not force a
userspace reboot in a maintainer script.

The unsigned IPA is separate and must be signed/installed by an appropriate
method. Minimum deployment target is iOS 16. The app performs no privileged
escalation. "Apply to shared configuration" succeeds only after actual atomic
write and readback to the common mobile preference path. Ordinary sandboxed
installations usually cannot do this. Export a plist instead, transfer it to the
device and run as mobile:

```
acprefs import /var/mobile/Media/AirPodsCompat-config.plist
acprefs show
```

On rootless installations the executable is `/var/jb/usr/bin/acprefs`. It accepts
only documented keys and types, preserves existing legacy choices, normalizes
old modern Pro profiles to AirPods 4 (ANC), and preserves `off`. It installs no
setuid helper, privileged App entitlement, XPC daemon or password store. Root may
also run it; a root-created preference file is returned to mobile ownership.

Preferences: `/var/mobile/Library/Preferences/com.justintunsday.airpodscompat.plist`
(never prefixed with /var/jb). Startup switches require restarting affected
processes. Diagnostic records are opt-in and contain process/module/build/state,
not Bluetooth addresses or battery percentages. Their cache location is
`/var/mobile/Library/Caches/com.justintunsday.airpodscompat/`. They are last
observations, not proof a process is still running or that a feature worked.

The default resource filter explicitly includes SpringBoard, MusicUIService,
Music, Podcasts and PosterBoard to retain prior accepted iOS 16 coverage.
`packaging/resource-filters/system-only.plist` removes the client processes for
experiments. No framework-wide or all-UIKit injection filter is shipped. See
SYSTEM-WIDE-COMPATIBILITY.md for the experiment and coverage limits.

Before device testing, retain the old deb, both dylibs/filters and existing
preferences. Reinstall the old deb and restore the saved preferences to roll back.
The baseline branch `codex/ios16-legacy-ui-20261019` remains unchanged. The
device-tested baseline package came from run 39253816288; its rootless SHA-256 is
`2965968114a0874e6c7fe6895d854c573591f9094b19aac8e41236c5c942d4c3`.

Registration guards remain per accessory daemon. A leftover
`.registration-in-progress.<process>` in the package support directory disables
that daemon's registration. Investigate the crash before removing its marker.
