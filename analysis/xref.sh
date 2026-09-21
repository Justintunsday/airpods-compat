#!/usr/bin/env bash
# Manual Swift dispatch tracing - run only on a Mac with a complete split cache.
#
# WARNING: `ipsw dyld xref` is marked WIP upstream and did not finish on split
# caches in our tests (--all: 60min+; per-image: 17min+ before cancel).
# Keep this out of the default CI matrix.
#
# Usage: bash analysis/xref.sh 27.0
set -uo pipefail

VERSION="${1:-27.0}"
OUT="${OUT:-out}"
tag="$(echo "$VERSION" | tr '.' '_')"
dir="ipsw_$tag"
b="$OUT/$tag"
mkdir -p "$b"

case "$VERSION" in
  27.0)   FACTORY="0x2027139b0"; GETTER="0x2027144c0" ;;
  26.6.2) FACTORY="0x1dcbbfdcc"; GETTER="0x1dcbc0744" ;;
  *)      echo "no known addresses for $VERSION"; exit 1 ;;
esac

DSC="$(find "$dir" -type f -name 'dyld_shared_cache_arm64e' | head -1)"
if [[ -z "$DSC" ]]; then
  echo "no DSC under $dir - run analysis/run.sh $VERSION first"
  exit 1
fi

: >"$b/xref.txt"
{
  echo "### positive control: factory $FACTORY in HeadphoneManager"
} >>"$b/xref.txt"
timeout 900 ipsw dyld xref "$DSC" "$FACTORY" \
  --image /System/Library/PrivateFrameworks/HeadphoneManager.framework/HeadphoneManager \
  >>"$b/xref.txt" 2>&1 || echo "(timed out / failed)" >>"$b/xref.txt"

for img in \
  /System/Library/PrivateFrameworks/HeadphoneSettingsUI.framework/HeadphoneSettingsUI \
  /System/Library/PrivateFrameworks/HeadphoneConfigs.framework/HeadphoneConfigs \
  /System/Library/PreferenceBundles/BluetoothSettings.bundle/BluetoothSettings ; do
  {
    echo "### getter $GETTER in $img"
  } >>"$b/xref.txt"
  timeout 900 ipsw dyld xref "$DSC" "$GETTER" --image "$img" >>"$b/xref.txt" 2>&1 || echo "(timed out / failed)" >>"$b/xref.txt"
done

echo "wrote $b/xref.txt"
