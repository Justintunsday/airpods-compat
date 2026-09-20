#!/usr/bin/env bash
# DSC analysis helper - runs on macOS (or any host where `ipsw extract --dyld` works).
# Usage: bash analysis/run.sh "27.0" [build]
set -uo pipefail

VERSION="${1:-27.0}"
BUILD="${2:-}"
OUT="${OUT:-out}"
DEVICE="${DEVICE:-iPhone17,3}"

mkdir -p "$OUT"

tag="$(echo "$VERSION" | tr '.' '_')"
dir="ipsw_$tag"
mkdir -p "$dir"

# Run a command with a wall-clock timeout (macOS has no coreutils `timeout`).
run_to() {
  local t="$1"; shift
  local s rc
  s="$(date +%s)"
  echo "--> [timeout ${t}s] $*"
  perl -e 'alarm shift; exec @ARGV' "$t" "$@" && rc=0 || rc=$?
  echo "    rc=$rc elapsed=$(( $(date +%s) - s ))s : $*"
  return 0
}

echo "==> downloading DSC for iOS $VERSION (device $DEVICE)"
args=(download ipsw --device "$DEVICE" --version "$VERSION" --dyld --dyld-arch arm64e --confirm -o "$dir")
if [[ -n "$BUILD" ]]; then
  args+=(--build "$BUILD")
fi
run_to 2400 ipsw "${args[@]}"

DSCS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DSCS+=("$line")
done < <(find "$dir" -type f -name 'dyld_shared_cache_arm64e')

if [[ ${#DSCS[@]} -eq 0 ]]; then
  echo "!! no dyld_shared_cache_arm64e found under $dir"
  find "$dir" -maxdepth 3 -type f | head -50
  exit 1
fi

for dsc in "${DSCS[@]}"; do
  b="$OUT/$tag"
  mkdir -p "$b"
  echo "==> analyzing $dsc -> $b"
  ls -la "$(dirname "$dsc")" >"$b/dsc_files.txt" 2>&1 || true

  run_to 120 ipsw dyld str "$dsc" \
    "AirPods 5" \
    "AirPods 5 (Wireless Charging)" \
    "B868" \
    "A3531" \
    "A3532" \
    "A3439" \
    >"$b/str_hits.txt" 2>&1

  # targeted per-image queries only (full-cache dumps are too slow/large)
  : >"$b/objc_relevant.txt"
  for img in UARP MobileBluetooth HeadphoneConfigs; do
    echo "### $img" >>"$b/objc_relevant.txt"
    run_to 300 ipsw dyld objc class "$dsc" --image "$img" >>"$b/objc_relevant.txt" 2>&1
    run_to 120 ipsw dyld image "$dsc" "$img" >"$b/image_$img.txt" 2>&1
  done
done

echo "==> done"
find "$OUT" -type f | sort
