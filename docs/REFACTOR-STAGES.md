# Architecture refactor stages

Baseline: `a30615d`, based on the packaged `934caa7` build in
[run 39253816288](https://github.com/Justintunsday/airpods-compat/actions/runs/39253816288).
The original branch and its commits remain untouched. Recover with that branch
and the known rootless package SHA-256 in IOS16-RESOURCE-COMPAT.md.

1. Central pure-C compatibility, configuration migration and process policies;
   exhaustive unrelated-PID regression tests. The actual legacy default is
   AirPods 3 (0x2013), despite the older README saying Pro 2. Preserve code behavior.
2. Separate registration, identity, Settings, feature-content, runtime checks and
   resource adapters. Use explicit resource-client filters. Preserve old iOS 16
   glyph construction, telemetry and synchronous lookup scopes.
3. Companion diagnostics, verified preference-file access, configuration export,
   and iOS 16 compatible UI. Runtime observations are process-local, not proof
   of successful system hook installation.
4. CI, package validation, evidence collection, architecture and device matrix.
   Physical-device results must identify the tested commit and environment.

Each stage is committed after its available automated checks. iOS compilation
and simulator tests run on macOS GitHub Actions; this Windows host has no Xcode.

Stage 1: both C executables passed locally using Zig/Clang with warnings as errors.
Stage 2: both C suites, registry agreement and five repository integration
contracts passed. The iOS 18 adapter intentionally scopes five read-only queries;
it does not wrap loadAccessorySettings or enable capability booleans. Its full
ANC/settings effect is unverified. Resource filters now explicitly include only
the previously accepted Apple clients, rather than every MediaPlayer consumer.
Third-party coverage is therefore a documented opt-in limitation.
