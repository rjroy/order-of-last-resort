#!/usr/bin/env bash
set -euo pipefail

out=${1:?Hookhand review output directory}
poses="$out/poses"
control="$out/comparison"
frames="$out/frames"
export MAGICK_THREAD_LIMIT=2
font=$(fc-match 'Liberation Serif' -f '%{file}\n')
paper='#eee0c6'
card='#f5ebd8'
ink='#352c25'
muted='#6f5442'

pose_files=()
plate() {
    local name=$1 label=$2
    local p="$poses/review-$name.png"
    magick "$poses/$name.png" -background "$card" -alpha remove -alpha off -resize 300x300 \
        -gravity center -extent 300x300 -gravity south -splice 0x26 \
        -font "$font" -fill "$ink" -pointsize 20 -annotate +0+4 "$label" "$p"
    pose_files+=("$p")
}

plate neutral 'T-rest'
plate ready 'Ready'
plate back 'Long mantle and coil'
plate tension 'Line takes tension'
plate haul 'Haul'
plate approach 'Approach'
plate flinch 'Flinch'
plate down 'Down'
plate recover 'Recover'
magick montage "${pose_files[@]}" -background "$paper" -geometry +5+5 -tile 3x3 "$poses/review-grid.png"
magick "$poses/review-grid.png" -background "$paper" -gravity north -splice 0x59 \
    -font "$font" -pointsize 28 -fill "$ink" -annotate +0+9 'Hookhand · Model and action review' \
    -pointsize 14 -fill "$muted" -annotate +0+39 'Barnaby’s Order of Last Resort  /  rendered from the editable Blender candidate' \
    "$out/hookhand-pose-sheet.png"

# No upscaling. Both rows use the same camera, metres-to-pixels and floor origin.
small_files=()
mini() {
    local path=$1 label=$2
    local i=${#small_files[@]}
    local p="$poses/small-$i.png"
    magick -size 125x85 "xc:$card" -fill none -stroke '#b5a081' -strokewidth 1 \
        -draw 'polygon 10,69 42,42 74,69 42,96' \
        \( "$path" -filter Lanczos -resize 125x85 \) -compose Over -composite \
        -gravity south -background "$paper" -splice 0x20 -font "$font" -pointsize 13 \
        -fill "$ink" -stroke none -annotate +0+3 "$label" "$p"
    small_files+=("$p")
}

mini "$poses/small-hook-ready.png" 'Hookhand: ready'
mini "$control/small-harpooner-ready.png" 'Harpooner: ready'
mini "$poses/small-hook-tension.png" 'Hookhand: tension'
mini "$control/small-harpooner-jab.png" 'Harpooner: jab'
mini "$poses/small-hook-haul.png" 'Hookhand: haul'
mini "$control/small-harpooner-cast.png" 'Harpooner: cast'
magick montage "${small_files[@]}" -geometry +7+4 -tile 2x3 -background "$paper" "$poses/small-grid.png"
magick "$poses/small-grid.png" -background "$paper" -gravity north -splice 0x50 -font "$font" \
    -pointsize 20 -fill "$ink" -annotate +0+4 'Hookhand and Harpooner' \
    -pointsize 12 -fill "$muted" -annotate +0+31 '26.55 px/m  /  not in-game playback' \
    "$out/hookhand-vs-harpooner.png"

ffmpeg -hide_banner -loglevel error -y -filter_threads 2 -filter_complex_threads 2 \
    -framerate 12 -i "$frames/pull/%03d.png" \
    -framerate 12 -i "$frames/approach/%03d.png" \
    -framerate 12 -i "$frames/flinch/%03d.png" \
    -framerate 12 -i "$frames/down/%03d.png" \
    -framerate 12 -i "$frames/recover/%03d.png" \
    -filter_complex "
      [0:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[p];
      [1:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[w];
      [2:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[f];
      [3:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[d];
      [4:v]format=rgba,tpad=stop_duration=2:stop_mode=clone[r];
      color=c=0xf5ebd8:s=290x290:r=12[blank];
      [p][w][f][d][r][blank]xstack=inputs=6:layout=0_0|290_0|580_0|0_290|290_290|580_290:shortest=1[a];
      color=c=0xf5ebd8:s=870x580:r=12[base];
      [base][a]overlay=shortest=1,
      drawtext=fontfile=$font:text='Hook Pull':x=92:y=23:fontsize=23:fontcolor=0x352c25,
      drawtext=fontfile=$font:text='Approach':x=375:y=23:fontsize=23:fontcolor=0x352c25,
      drawtext=fontfile=$font:text='Flinch':x=685:y=23:fontsize=23:fontcolor=0x352c25,
      drawtext=fontfile=$font:text='Down':x=105:y=313:fontsize=23:fontcolor=0x352c25,
      drawtext=fontfile=$font:text='Recover':x=380:y=313:fontsize=23:fontcolor=0x352c25,
      drawtext=fontfile=$font:text='HOOKHAND':x=646:y=389:fontsize=25:fontcolor=0x352c25,
      drawtext=fontfile=$font:text='Model review':x=659:y=423:fontsize=18:fontcolor=0x6f5442,
      format=yuv420p[v]" \
    -map '[v]' -t 2.50 -c:v libx264 -threads 3 -crf 18 -movflags +faststart "$out/hookhand-motion.mp4"
