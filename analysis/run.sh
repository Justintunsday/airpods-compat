#!/usr/bin/env bash
# DSC analysis helper - runs on macOS (or any host where `ipsw extract --dyld` works).
# Usage: bash analysis/run.sh "27.0,26.6.2" [build]
set -euo pipefail

VERSIONS="${1:-27.0}"
BUILD="${2:-}"
OUT="${OUT:-out}"
DEVICE="${DEVICE:-iPhone17,3}"

mkdir -p "$OUT"

IFS=',' read -ra VERS <<<"$VERSIONS"
for v in "${VERS[@]}"; do
  tag="$(echo "$v" | tr '.' '_')"
  dir="ipsw_$tag"
  mkdir -p "$dir"

  echo "==> downloading DSC for iOS $v (device $DEVICE)"
  args=(download ipsw --device "$DEVICE" --version "$v" --dyld --dyld-arch arm64e --confirm -o "$dir")
  if [[ -n "$BUILD" ]]; then
    args+=(--build "$BUILD")
  fi
  ipsw "${args[@]}"

  DSCS=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && DSCS+=("$line")
  done < <(find "$dir" -type f -name 'dyld_shared_cache_arm64e')
  if [[ ${#DSCS[@]} -eq 0 ]]; then
    echo "!! no dyld_shared_cache_arm64e found under $dir" >&2
    find "$dir" -maxdepth 3 -type f | head -50 >&2
    continue
  fi

  for dsc in "${DSCS[@]}"; do
    b="$OUT/$tag"
    mkdir -p "$b"
    echo "==> analyzing $dsc -> $b"

    ipsw dyld info "$dsc" >"$b/info.txt" 2>&1 || true
    ipsw dyld image "$dsc" >"$b/images.txt" 2>&1 || true
    ipsw dyld objc class "$dsc" >"$b/objc_classes.txt" 2>&1 || true
    ipsw dyld objc sel "$dsc" >"$b/objc_selectors.txt" 2>&1 || true
    ipsw dyld swift "$dsc" >"$b/swift.txt" 2>&1 || true

    ipsw dyld str "$dsc" \
      "AirPods 5" \
      "AirPods 5 (Wireless Charging)" \
      "B868" \
      "AirPods 4" \
      >"$b/str_hits.txt" 2>&1 || true

    ipsw dyld symaddr "$dsc" --all 'UARPSupportedAccessoryA3.*' >"$b/sym_uarp_a3.txt" 2>&1 || true
    ipsw dyld symaddr "$dsc" --all 'B868.*' >"$b/sym_b868.txt" 2>&1 || true
    ipsw dyld symaddr "$dsc" --all '.*FeatureProviding.*' >"$b/sym_featureproviding.txt" 2>&1 || true

    grep -i -E 'UARP|AirPods|B868|Headphone|MobileBluetooth' "$b/objc_classes.txt" >"$b/objc_filtered.txt" 2>/dev/null || true
    grep -i -E 'B868|AirPods|UARP|Headphone' "$b/swift.txt" >"$b/swift_filtered.txt" 2>/dev/null || true
  done
done

echo "==> done; artifacts in $OUT"
find "$OUT" -type f | sort
