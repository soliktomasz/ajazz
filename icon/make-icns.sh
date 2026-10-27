#!/bin/bash
# Regenerate icon/AppIcon.icns from icon/make-icon.swift. build-app.sh copies the
# result into the bundle; rerun this only when the drawing changes.
set -euo pipefail
cd "$(dirname "$0")"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift make-icon.swift "$WORK/1024.png"
SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o AppIcon.icns
echo "wrote icon/AppIcon.icns"
