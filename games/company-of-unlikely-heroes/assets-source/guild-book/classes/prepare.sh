#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if (( $# != 1 )); then
    printf 'Usage: bash prepare.sh OUTPUT_DIRECTORY\n' >&2
    exit 2
fi

ids=(knight healer wizard rogue bard necromancer alchemist blacksmith)
sources=()
shopt -s nullglob
for id in "${ids[@]}"; do
    if [[ "$id" == knight ]]; then
        sources+=("$source_dir/../study/connected-study.png")
        continue
    fi
    matches=("$source_dir/$id-native."*)
    if (( ${#matches[@]} != 1 )); then
        printf 'Expected one native source for %s; found %d\n' "$id" "${#matches[@]}" >&2
        exit 1
    fi
    sources+=("${matches[0]}")
done

mkdir -p -- "$1"
output_dir="$(cd -- "$1" && pwd)"
staging="$(mktemp -d "$output_dir/.portrait-build.XXXXXXXX")"
trap 'rm -rf -- "$staging"' EXIT

for i in "${!ids[@]}"; do
    output="$staging/${ids[i]}.png"
    crop=()
    if [[ "${ids[i]}" == knight ]]; then
        crop=(-crop '750x497+776+10' +repage)
    fi
    magick "${sources[i]}" "${crop[@]}" -auto-orient -colorspace sRGB \
        -filter Lanczos -resize '512x512^' -gravity center -extent 512x512 \
        -alpha off -strip -define png:exclude-chunk=date,time PNG24:"$output"
    test "$(magick identify -format '%m %wx%h %[colorspace]' "$output")" = 'PNG 512x512 sRGB'
done

for id in "${ids[@]}"; do
    mv -f -- "$staging/$id.png" "$output_dir/$id.png"
done
