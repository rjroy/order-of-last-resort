#!/usr/bin/env bash
set -euo pipefail

out=${1:?absolute output folder}
poses="$out/final-poses"
frames="$out/final-motion"
export MAGICK_THREAD_LIMIT=2
font=$(fc-match 'Liberation Serif' -f '%{file}\n')
paper='#eee0c6'
card='#f5ebd8'
ink='#3e2d21'
quiet='#76583e'

plate() {
    local image=$1 label=$2
    local -a crop=()
    case "$image" in
        neutral|back) ;;
        *) crop=(-crop 436x322+52+127 +repage) ;;
    esac
    magick "$poses/$image.png" "${crop[@]}" -background "$card" -alpha remove -alpha off -resize 300x300 \
        -gravity center -extent 300x300 -gravity south -splice 0x29 -font "$font" -fill "$ink" -pointsize 20 \
        -annotate +0+5 "$label" "$poses/card-$image.png"
}

plate neutral 'T rest'
plate back 'Mantle and satchel'
plate ready 'Ready'
plate jab 'Close jab'
plate aim 'Cast: anticipation'
plate release 'Cast: release'
plate pursue 'Pursue'
plate hit 'Hit'
plate defeat 'Defeat'

montage=("$poses/card-neutral.png" "$poses/card-ready.png" "$poses/card-jab.png"
    "$poses/card-back.png" "$poses/card-aim.png" "$poses/card-release.png"
    "$poses/card-pursue.png" "$poses/card-hit.png" "$poses/card-defeat.png")
magick montage "${montage[@]}" -background "$paper" -geometry +6+6 -tile 3x3 "$poses/pose-grid.png"
magick "$poses/pose-grid.png" -background "$paper" -gravity north -splice 0x62 \
    -font "$font" -pointsize 29 -fill "$ink" -annotate +0+11 'Harpooner  •  Model and action review' \
    -pointsize 14 -fill "$quiet" -annotate +0+42 'Rendered from the editable Blender candidate  /  Barnaby’s Order of Last Resort' \
    "$out/pose-sheet.png"

# Preserve the 26.55 px/m sample size. Grid and labels are review overlays.
mini_cards=()
mini_names=(ready jab aim release pursue defeat)
mini_labels=('Ready' 'Close jab' 'Anticipation' 'Ranged release' 'Pursue' 'Defeat')
for i in "${!mini_names[@]}"; do
    name=${mini_names[i]}
    dest="$poses/tactical-$name.png"
    magick -size 102x76 "xc:$card" -fill none -stroke '#b5a080' -strokewidth 1 \
        -draw 'polygon 0,68 33,40 65,68 33,96' \
        \( "$poses/mini-$name.png" -filter Lanczos -resize 102x76 \) -compose Over -composite \
        -gravity south -background "$paper" -splice 0x20 -font "$font" -pointsize 13 \
        -fill "$ink" -stroke none -annotate +0+3 "${mini_labels[i]}" "$dest"
    mini_cards+=("$dest")
done
magick montage "${mini_cards[@]}" -background "$paper" -geometry +4+5 -tile 6x1 "$poses/tactical-grid.png"
magick "$poses/tactical-grid.png" -background "$paper" -gravity north -splice 0x54 -font "$font" \
    -pointsize 20 -fill "$ink" -annotate +0+6 'Harpooner at tactical size' \
    -pointsize 13 -fill "$quiet" -annotate +0+33 '26.55 px per metre  /  isolated Blender proof, not in-game playback' \
    "$out/tactical-scale.png"

# Align all acting columns at the same camera, scale and anchor; hold end poses.
ffmpeg -hide_banner -loglevel error -y -filter_threads 2 -filter_complex_threads 2 \
    -framerate 12 -i "$frames/jab/%03d.png" \
    -framerate 12 -i "$frames/release/%03d.png" \
    -framerate 12 -i "$frames/pursue/%03d.png" \
    -framerate 12 -i "$frames/hit/%03d.png" \
    -framerate 12 -i "$frames/defeat/%03d.png" \
    -filter_complex "
      [0:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[j];
      [1:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[r];
      [2:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[p];
      [3:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[h];
      [4:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[d];
      color=c=0xf5ebd8:s=300x300:r=12[blank];
      [j][r][p][h][d][blank]xstack=inputs=6:layout=0_0|300_0|600_0|0_300|300_300|600_300:fill=0xf5ebd8:shortest=1[a];
      color=c=0xf5ebd8:s=900x600:r=12[base];
      [base][a]overlay=shortest=1,
      drawtext=fontfile=$font:text='Close jab':x=90:y=35:fontsize=22:fontcolor=0x3e2d21,
      drawtext=fontfile=$font:text='Ranged cast':x=386:y=35:fontsize=22:fontcolor=0x3e2d21,
      drawtext=fontfile=$font:text='Pursue':x=703:y=35:fontsize=22:fontcolor=0x3e2d21,
      drawtext=fontfile=$font:text='Hit':x=103:y=335:fontsize=22:fontcolor=0x3e2d21,
      drawtext=fontfile=$font:text='Defeat':x=404:y=335:fontsize=22:fontcolor=0x3e2d21,
      drawtext=fontfile=$font:text='HARPOONER':x=667:y=411:fontsize=25:fontcolor=0x3e2d21,
      drawtext=fontfile=$font:text='Model review':x=695:y=449:fontsize=18:fontcolor=0x76583e,
      format=yuv420p[v]" \
    -map '[v]' -t 2.17 -c:v libx264 -threads 3 -crf 18 -movflags +faststart "$out/motion-preview.mp4"
