#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $# -ne 2 ]]; then
	printf 'Usage: bash prepare.sh OUTPUT_DIRECTORY REVIEW_DIRECTORY\n' >&2
	exit 2
fi
mkdir -p -- "$1" "$2"
output=$(cd -- "$1" && pwd)
review=$(cd -- "$2" && pwd)
tmp=$(mktemp -d "$review/.build.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
font=$(fc-match -f '%{file}' 'DejaVu Sans')
[[ -f "$font" ]]

make_tile() {
	local png=$1 label=$2 width=$3 height=$4 destination=$5
	magick "$png" -filter Lanczos -resize "${width}x${height}" \
		\( -size "${width}x23" xc:'#eee1c8' -gravity center -font "$font" \
			-pointsize 12 -fill '#38291e' -annotate 0 "$label" \) \
		-append "PNG24:$destination"
}

full=() reduced=() sprites=()
while IFS=$'\t' read -r id sheet crop fit paper label; do
	path="$tmp/$id.png"
	magick "$source_dir/$sheet" -crop "$crop" +repage \
		-filter Lanczos -resize "$fit" -alpha set \
		\( +clone -alpha extract -shave 5x5 -bordercolor black -border 5 -blur 0x4 \) \
		-compose CopyAlpha -composite -compose Over \
		-background "$paper" -gravity center -extent 318x154 -alpha remove -alpha off \
		-colorspace sRGB -strip -define png:exclude-chunks=date,time "PNG24:$path"
	[[ $(magick identify -format '%wx%h:%[colorspace]:%[opaque]' "$path") == '318x154:sRGB:True' ]]
	make_tile "$path" "$label" 318 154 "$tmp/$id-full.png"
	make_tile "$path" "$label" 159 77 "$tmp/$id-reduced.png"
	full+=("$tmp/$id-full.png")
	reduced+=("$tmp/$id-reduced.png")
	sprites+=("$id")
done < "$source_dir/crops.tsv"

[[ ${#sprites[@]} == 16 ]]
magick montage "${full[@]}" -tile 4x4 -mode concatenate -geometry +0+0 "$review/contact-sheet-318x154.png"
magick montage "${reduced[@]}" -tile 4x4 -mode concatenate -geometry +0+0 "$review/contact-sheet-159x77.png"
for id in "${sprites[@]}"; do
	cp -f -- "$tmp/$id.png" "$output/$id.png"
done
