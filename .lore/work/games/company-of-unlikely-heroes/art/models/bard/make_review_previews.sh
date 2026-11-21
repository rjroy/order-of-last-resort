#!/usr/bin/env bash
# Compose the Bard candidate sheet and silent, loopable performance comparison.
set -euo pipefail

out="$(realpath "${1:?Supply the review output directory}")"
render="$out/renders"
face="$(fc-match -f '%{file}' 'Liberation Serif:style=Regular')"
display="$(fc-match -f '%{file}' 'Liberation Serif:style=Bold')"
body="$(fc-match -f '%{file}' 'Liberation Sans:style=Regular')"
small="$(fc-match -f '%{file}' 'Liberation Sans:style=Bold')"
paper='#f4e9d6'
ink='#372820'
wine='#743d3e'
quiet='#6f5e50'
rule='#d7c4a8'

for still in rest ready melody melody-answer sonnet sonnet-breath; do
  test -s "$render/$still.png"
done

tmp="$(mktemp -d "$out/.compose.XXXXXX")"
trap 'rm -f -- "$tmp/"*.png; rmdir -- "$tmp"' EXIT

cards=(rest ready melody sonnet)
for i in "${!cards[@]}"; do
  frame="${cards[$i]}"
  magick "$render/$frame.png" -resize 300x312! "$tmp/still-$i.png"
done
for i in ready melody melody-answer sonnet sonnet-breath; do
  magick "$render/$i.png" -filter Lanczos -resize 65x54 \
    -background '#a18e77' -gravity center -extent 65x54 "$tmp/cell-$i.png"
done

magick -size 1376x690 "xc:$paper" \
  -font "$small" -pointsize 12 -kerning 2 -fill "$wine" \
  -annotate +49+43 'BARNABY’S ORDER OF LAST RESORT  /  CAST MODEL STUDY' \
  -font "$display" -pointsize 57 -kerning -1 -fill "$ink" -annotate +47+106 'The Bad Bard' \
  -font "$face" -pointsize 23 -kerning 0 -fill "$quiet" \
  -annotate +49+138 'A wedding fiddler who knows exactly when you’re supposed to laugh.' \
  -font "$small" -pointsize 12 -kerning 1.5 -fill "$wine" \
  -annotate +1035+47 'MODEL CANDIDATE  /  04' \
  -font "$body" -pointsize 13 -kerning 0 -fill "$quiet" \
  -annotate +1035+70 'Blender • 2.47 m orthographic scale' \
  -annotate +1035+90 'Same tactical view for all acting poses' \
  -stroke "$rule" -draw 'line 48,158 1328,158 line 48,572 1328,572' -stroke none \
  "$tmp/still-0.png" -geometry +48+179 -composite \
  "$tmp/still-1.png" -geometry +375+179 -composite \
  "$tmp/still-2.png" -geometry +702+179 -composite \
  "$tmp/still-3.png" -geometry +1029+179 -composite \
  -font "$display" -pointsize 23 -fill "$ink" \
  -annotate +48+526 '01  Neutral T' -annotate +375+526 '02  Ready Count-In' \
  -annotate +702+526 '03  Inspiring Melody' -annotate +1029+526 '04  Healing Sonnet' \
  -font "$body" -pointsize 13 -fill "$quiet" \
  -annotate +48+548 'Frame 1 • actual rest, props hidden' \
  -annotate +375+548 'Frame 13 • listening for the entrance' \
  -annotate +702+548 'Frame 13 • high knee and short strokes' \
  -annotate +1029+548 'Frame 25 • both feet planted, singing' \
  -font "$small" -pointsize 13 -kerning 1.8 -fill "$wine" \
  -annotate +48+611 'AT 65 × 54' \
  -font "$face" -pointsize 17 -kerning 0 -fill "$quiet" \
  -annotate +48+635 'Actual pixel size. Isolated figure, not a board test.' \
  "$tmp/cell-ready.png" -geometry +499+591 -composite \
  "$tmp/cell-melody.png" -geometry +669+591 -composite \
  "$tmp/cell-melody-answer.png" -geometry +829+591 -composite \
  "$tmp/cell-sonnet.png" -geometry +1007+591 -composite \
  "$tmp/cell-sonnet-breath.png" -geometry +1174+591 -composite \
  -font "$body" -pointsize 12 -fill "$quiet" \
  -annotate +499+664 'Count-in' -annotate +669+664 'First lift' -annotate +829+664 'Second lift' \
  -annotate +1007+664 'Long draw' -annotate +1174+664 'Breath / return' \
  -strip "$out/contact-sheet.png"

if [[ "${2:-}" == "--stills-only" ]]; then
  exit 0
fi

# 10 s comparison repeats Melody and Sonnet at their own periods. Count-in
# repeats on its 1 s period. Do not pad phrase ends with duplicate rest frames.
inputs=()
for action in count-in melody sonnet; do
  test -s "$render/$action/000.png"
  inputs+=(-stream_loop -1 -framerate 12 -i "$render/$action/%03d.png")
done
ffmpeg -hide_banner -loglevel error -y -filter_complex_threads 2 "${inputs[@]}" \
  -filter_complex "
    [0:v]format=rgb24[a]; [1:v]format=rgb24[b]; [2:v]format=rgb24[c];
    [a][b][c]hstack=inputs=3,
    pad=912:364:24:42:color=0xf4e9d6,
    drawtext=fontfile='$display':text='Ready Count-In':fontsize=19:fontcolor=0x372820:x=24:y=12,
    drawtext=fontfile='$display':text='Inspiring Melody':fontsize=19:fontcolor=0x372820:x=312:y=12,
    drawtext=fontfile='$display':text='Healing Sonnet':fontsize=19:fontcolor=0x372820:x=600:y=12,
    format=yuv420p[preview]" \
  -map '[preview]' -t 10 -c:v libwebp_anim -loop 0 -quality 84 -preset picture \
  "$out/two-songs.webp"
