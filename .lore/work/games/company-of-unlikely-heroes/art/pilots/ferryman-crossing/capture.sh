#!/usr/bin/env bash
# Render the actual Godot consumer at 1280×820. Requires a graphical display and ffmpeg.
set -euo pipefail

pilot="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$pilot/../../../../../../.." && pwd)"
output="${1:-$repo/.lore/local/company-of-unlikely-heroes/crossing-pilot}"
mkdir -p -- "$output"
output="$(cd -- "$output" && pwd)"
scratch="$(mktemp -d -- "$output/.godot-movie.XXXXXX")"
trap 'rm -f -- "$scratch/crossing.avi"; rmdir -- "$scratch"' EXIT

capture=(godot --path "$pilot" --audio-driver Dummy --disable-vsync --fixed-fps 30)
"${capture[@]}" -- --showcase --registration-check --raw-plate --capture-dir="$output"
"${capture[@]}" -- --showcase --registration-check --capture-dir="$output"
"${capture[@]}" --write-movie "$scratch/crossing.avi" -- --showcase --capture-dir="$output"

ffmpeg -hide_banner -loglevel error -y -i "$scratch/crossing.avi" -map 0:v:0 \
    -c:v libx264 -crf 16 -preset fast -pix_fmt yuv420p -movflags +faststart \
    "$output/crossing-consumer.mp4"
printf 'Godot screenshots and movie: %s\n' "$output"
