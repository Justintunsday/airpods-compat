#!/usr/bin/env python3
"""Compare HeadphoneSettingsUI Swift feature conformances across iOS builds.

Usage:
  python tools/compare_feature_conformances.py \
    --old artifacts-consumers/sym_26_6_2_HeadphoneSettingsUI.txt \
    --new artifacts-consumers/sym_27_0_HeadphoneSettingsUI.txt

The input is `ipsw dyld info -n` output for HeadphoneSettingsUI. This inspects
protocol conformance descriptors (Mc), witness tables (WP), and per-model
extension getters without assuming a direct call to the feature factory.
"""
import argparse
import re
from pathlib import Path


FEATURE = re.compile(
    r"^_\$s16HeadphoneManager\d+(?P<model>B\w+FeatureContent)C"
    r"0A10SettingsUI(?P<extension>.+)$"
)
GETTER_NAMES = ("featureType", "platformName", "singularName", "marketingName")


def read_symbols(path):
    raw = Path(path).read_bytes()
    encoding = "utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
    result = {}
    for line in raw.decode(encoding, errors="replace").splitlines():
        match = FEATURE.search(line.split("\t")[-1].strip())
        if not match:
            continue
        model = match.group("model")
        tail = match.group("extension")
        if tail.endswith(("ADMc", "ADWP")):
            kind = "descriptor" if tail.endswith("ADMc") else "witness"
            # Swift substitutions abbreviate parts of protocol names; keep
            # this a semantic label rather than claiming to demangle them.
            if "SleepDetection" in tail:
                name = "SleepDetectionFeatureProviding"
            elif "NameProviding" in tail:
                name = "NameProviding"
            elif "UIContentProvider" in tail:
                name = "UIContentProvider"
            else:
                name = tail
            result.setdefault(model, set()).add(f"{kind}:{name}")
        elif tail.startswith("E") and tail.endswith("vg"):
            for name in GETTER_NAMES:
                if name in tail:
                    result.setdefault(model, set()).add(f"getter:{name}")
                    break
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", required=True)
    parser.add_argument("--new", required=True)
    args = parser.parse_args()
    old, new = read_symbols(args.old), read_symbols(args.new)
    for model in sorted(set(old) | set(new)):
        print(model)
        for label, values in (("old", old.get(model, set())),
                              ("new", new.get(model, set()))):
            print(f"  {label}: {', '.join(sorted(values)) or '(absent)'}")
        added = new.get(model, set()) - old.get(model, set())
        if added:
            print(f"  added: {', '.join(sorted(added))}")


if __name__ == "__main__":
    main()
