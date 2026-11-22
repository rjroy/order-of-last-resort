#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 1 || -e "$1" ]]; then
  printf 'Usage: %s NEW_OUTPUT_DIRECTORY\n' "$0" >&2
  exit 1
fi
source_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -- "$1"
cd "$1"

# Clip native quadrant margins, discard faint native alpha speckle, then trim.
# Resample in linear light; PNG32 writes straight-alpha, 8-bit sRGB textures.
art() {
  local crop=$1 geometry=$2
  magick "$source_dir/props-native.png" -crop "$crop" +repage \
    -channel A -level 7%,100% +channel \
    -bordercolor none -border 1 -fuzz 0 -trim +repage \
    -colorspace RGB -filter Lanczos -resize "$geometry!" -colorspace sRGB \
    miff:-
}
plate() {
  local crop=$1 geometry=$2 canvas=$3 position=$4 target=$5
  art "$crop" "$geometry" | magick -size "$canvas" xc:none - \
    -geometry "$position" -compose Over -composite "PNG32:$target"
}

plate 620x430+5+120 294x204 312x216 +9+7 gate-open.png
plate 620x430+620+120 198x169 312x216 +57+41 gate-leaf.png
magick gate-leaf.png gate-open.png -compose Over -composite PNG32:gate-shut.png
plate 620x230+5+820 216x81 240x102 +12+18 pressure-plate.png
plate 600x525+630+640 204x156 228x165 +12+6 exit-arch.png
