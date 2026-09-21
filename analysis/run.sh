#!/usr/bin/env bash
# DSC analysis helper - runs on macOS (or any host where `ipsw extract --dyld` works).
# Usage: bash analysis/run.sh "27.0" [build] [device]
set -uo pipefail

VERSION="${1:-27.0}"
BUILD="${2:-}"
DEVICE="${3:-${DEVICE:-iPhone17,3}}"
OUT="${OUT:-out}"

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
  return $rc
}

echo "==> fetching DSC for iOS $VERSION ($DEVICE)"
args=(download ipsw --device "$DEVICE" --version "$VERSION" --dyld --dyld-arch arm64e --confirm -o "$dir")
if [[ -n "$BUILD" ]]; then
  args+=(--build "$BUILD")
fi
run_to 2400 ipsw "${args[@]}"

# iOS 15 and earlier have no cryptex: remote DSC extraction is unsupported, so
# fall back to downloading the full IPSW and extracting locally.
if ! find "$dir" -type f -name 'dyld_shared_cache_arm64e' | grep -q .; then
  echo "==> remote DSC unsupported for iOS $VERSION, falling back to full IPSW"
  run_to 3600 ipsw download ipsw --device "$DEVICE" --version "$VERSION" --confirm -o "$dir"
  IPSW="$(find "$dir" -maxdepth 2 -type f -name '*.ipsw' | head -1)"
  if [[ -n "$IPSW" ]]; then
    run_to 2400 ipsw extract --dyld --dyld-arch arm64e --output "$dir" "$IPSW"
  fi
fi

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

  # note: `symaddr --all` / full-cache `objc` dumps build a symbol cache and
  # take 30min+ on a split cache, so stay targeted here.

  IMAGES=(
    "/System/Library/PrivateFrameworks/CoreUARP.framework/CoreUARP"
    "/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth"
    "/System/Library/PrivateFrameworks/HeadphoneManager.framework/HeadphoneManager"
    "/System/Library/PrivateFrameworks/HeadphoneSettingsUI.framework/HeadphoneSettingsUI"
    "/System/Library/PrivateFrameworks/HeadphoneConfigs.framework/HeadphoneConfigs"
    "/System/Library/PrivateFrameworks/MobileBluetooth.framework/MobileBluetooth"
    "/System/Library/PreferenceBundles/BluetoothSettings.bundle/BluetoothSettings"
    "/Applications/Preferences.app/Preferences"
    "/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager"
    "/System/Library/PrivateFrameworks/HeadphoneProxService.framework/HeadphoneProxService"
    "/System/Library/PrivateFrameworks/HearingAid.framework/HearingAid"
    "/usr/libexec/headphonesd"
    "/usr/libexec/HearingAidUIServer"
  )
  mkdir -p "$b/dylibs"
  for img in "${IMAGES[@]}"; do
    name="$(basename "$img")"
    run_to 600 ipsw dyld macho "$dsc" "$img" --objc --symbols --strings --extract --output "$b/dylibs" >>"$b/macho_$name.txt" 2>&1
    run_to 120 ipsw dyld image "$dsc" "$img" >"$b/image_$name.txt" 2>&1
  done

  # --- Swift dispatch tracing ---
  # positive control: xref on allFeatureContents() must show the call inside
  # HeadphoneDevice.featureContent; then xref the getter itself per consumer
  # image (full --all scans take 30min+ on a split cache, so stay targeted).
  case "$VERSION" in
    27.0)   XREF_FACTORY="0x2027139b0"; XREF_GETTER="0x2027144c0" ;;
    26.6.2) XREF_FACTORY="0x1dcbbfdcc"; XREF_GETTER="0x1dcbc0744" ;;
    *)      XREF_FACTORY="";            XREF_GETTER="" ;;
  esac
  if [[ -n "$XREF_FACTORY" ]]; then
    : >"$b/xref.txt"
    {
      echo "### positive control: xref factory $XREF_FACTORY (HeadphoneManager)"
    } >>"$b/xref.txt"
    run_to 900 ipsw dyld xref "$dsc" "$XREF_FACTORY" \
      --image /System/Library/PrivateFrameworks/HeadphoneManager.framework/HeadphoneManager \
      >>"$b/xref.txt" 2>&1
    for img in \
      /System/Library/PrivateFrameworks/HeadphoneSettingsUI.framework/HeadphoneSettingsUI \
      /System/Library/PrivateFrameworks/HeadphoneConfigs.framework/HeadphoneConfigs \
      /System/Library/PreferenceBundles/BluetoothSettings.bundle/BluetoothSettings ; do
      {
        echo "### xref getter $XREF_GETTER in $img"
      } >>"$b/xref.txt"
      run_to 900 ipsw dyld xref "$dsc" "$XREF_GETTER" --image "$img" >>"$b/xref.txt" 2>&1
    done
  fi
done

echo "==> done"
find "$OUT" -type f | sort
