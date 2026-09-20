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

  run_to 300 ipsw dyld str "$dsc" \
    "AirPods 5" \
    "AirPods 5 (Wireless Charging)" \
    "B868" \
    "A3531" \
    "A3532" \
    "A3439" \
    >"$b/str_hits.txt" 2>&1

  # note: `symaddr --all` builds a full a2s symbol cache and takes 30min+ on a
  # split cache - string search above already surfaces the Swift/ObjC symbol
  # names we need, so keep this step fast.

  # targeted per-image queries only (full-cache dumps are too slow/large)
  IMAGES=(
    "/System/Library/PrivateFrameworks/CoreUARP.framework/CoreUARP"
    "/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth"
    "/System/Library/PrivateFrameworks/HeadphoneManager.framework/HeadphoneManager"
    "/System/Library/PrivateFrameworks/HeadphoneSettingsUI.framework/HeadphoneSettingsUI"
  )
  for img in "${IMAGES[@]}"; do
    name="$(basename "$img")"
    run_to 600 ipsw dyld macho "$dsc" "$img" --objc --symbols --strings >>"$b/macho_$name.txt" 2>&1
    run_to 120 ipsw dyld image "$dsc" "$img" >"$b/image_$name.txt" 2>&1
  done

  # disassemble the constant-returning helpers we need for the port
  dis() { # dis <dump-file> <symbol-grep> <out-file> [label]
    local dump="$1" pat="$2" out="$3"
    local addr
    addr="$(grep -F -- "$pat" "$dump" | grep -v 'vpMV\|TW$\|Tj$\|Tq$\|AAMc\|AAWP\|CMo\|CMn\|CMu\|CN$\|CMa\|CMF\|CMm' | head -1 | awk '{print $1}' | tr -d ':')"
    [[ -n "$addr" ]] || return 0
    {
      echo "### $pat @ $addr"
      run_to 90 ipsw dyld disass "$dsc" --vaddr "$addr"
    } >>"$out" 2>&1
  }

  : >"$b/disass_uarp.txt"
  for sym in \
    "UARPSupportedAccessoryA3440 productID" \
    "UARPSupportedAccessoryA3441 productID" \
    "UARPSupportedAccessoryA3529 productID" \
    "UARPSupportedAccessoryA3529USB productID" \
    "UARPSupportedAccessoryA3530USB productID" \
    "UARPSupportedAccessoryA3532 productID" \
    "UARPSupportedAccessoryA3533 productID" \
    "UARPSupportedAccessoryA3532 appleModelNumber" \
    "UARPSupportedAccessoryA3533 appleModelNumber" \
    "UARPSupportedAccessoryAirPodsBud productID"; do
    dis "$b/macho_CoreUARP.txt" "+[${sym}]" "$b/disass_uarp.txt"
  done

  : >"$b/disass_swift.txt"
  dis "$b/macho_HeadphoneManager.txt" "_s16HeadphoneManager18B868FeatureContentC9productIDs6UInt32Vvg" "$b/disass_swift.txt"
  dis "$b/macho_HeadphoneManager.txt" "_s16HeadphoneManager18B868FeatureContentC2id15headphoneDeviceACSgs6UInt32V_AA0aH0CtcfC" "$b/disass_swift.txt"
  dis "$b/macho_HeadphoneManager.txt" "_s16HeadphoneManager0A6DeviceC18allFeatureContents9productID6deviceSayAA0aE11ContentType_pSgGSo09CBProductH0V_ACtFZ" "$b/disass_swift.txt"

  : >"$b/disass_cb.txt"
  dis "$b/macho_CoreBluetooth.txt" "_CBProductIDToNSLocalizedProductNameString" "$b/disass_cb.txt"
done

echo "==> done"
find "$OUT" -type f | sort
