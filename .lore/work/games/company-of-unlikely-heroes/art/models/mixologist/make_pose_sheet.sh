#!/usr/bin/env bash
# Compose read-only review images into one sheet. The figure panels are unretouched.
set -euo pipefail

out="$(realpath "${1:?Supply the review output directory}")"
render="$out/renders"
serif="$(fc-match -f '%{file}' 'Liberation Serif:style=Regular')"
display="$(fc-match -f '%{file}' 'Liberation Serif:style=Bold')"
body="$(fc-match -f '%{file}' 'Liberation Sans:style=Regular')"
heading="$(fc-match -f '%{file}' 'Liberation Sans:style=Bold')"
paper='#f3e8d2'
ink='#302a21'
accent='#715426'
quiet='#655d4e'
rule='#d5c5a2'

scratch="$(mktemp -d "$out/.sheet.XXXXXXXX")"
trap 'rm -f -- "$scratch/"*.png; rmdir -- "$scratch"' EXIT
for still in neutral ready handoff release; do
  test -s "$render/$still.png"
  magick -regard-warnings "$render/$still.png" -resize 300x312 "$scratch/$still.png"
done
for still in ready handoff release; do
  magick "$render/$still.png" -filter Lanczos -resize 65x54 \
    -background '#a89b86' -gravity center -extent 65x54 "$scratch/cell-$still.png"
done

magick -size 1376x703 "xc:$paper" \
  -font "$heading" -pointsize 12 -kerning 1.8 -fill "$accent" \
  -annotate +48+42 'BARNABY’S ORDER OF LAST RESORT  /  CAST MODEL STUDY' \
  -annotate +1029+46 'MODEL CANDIDATE' \
  -font "$display" -pointsize 58 -kerning -1 -fill "$ink" -annotate +46+106 'The Mixologist' \
  -font "$serif" -pointsize 23 -kerning 0 -fill "$quiet" \
  -annotate +48+137 'One hand for the throw. The other keeps the rest of the bottles in their rack.' \
  -font "$body" -pointsize 13 -fill "$quiet" \
  -annotate +1029+70 'Blender · 2.47 m cast camera' \
  -annotate +1029+91 'Same tactical view for all acting poses' \
  -stroke "$rule" -draw 'line 48,157 1328,157 line 48,571 1328,571' -stroke none \
  "$scratch/neutral.png" -geometry +48+178 -composite \
  "$scratch/ready.png" -geometry +375+178 -composite \
  "$scratch/handoff.png" -geometry +702+178 -composite \
  "$scratch/release.png" -geometry +1029+178 -composite \
  -font "$display" -pointsize 24 -fill "$ink" \
  -annotate +48+521 '01  Neutral T' -annotate +375+521 '02  Ready' \
  -annotate +702+521 '03  Healing Potion' -annotate +1029+521 '04  Acid Toss' \
  -font "$body" -pointsize 14 -fill "$quiet" \
  -annotate +48+545 'Frame 1 · actual armature rest' \
  -annotate +375+545 'Frame 1 · kit stowed at the hip' \
  -annotate +702+545 'Frame 17 · low two-handed offer' \
  -annotate +1029+545 'Frame 18 · released, rack braced' \
  -font "$heading" -pointsize 12 -kerning 1.8 -fill "$accent" \
  -annotate +48+612 'AT 65 × 54' \
  -font "$serif" -pointsize 17 -kerning 0 -fill "$quiet" \
  -annotate +48+637 'Actual pixel size. Isolated figure, not a board test.' \
  "$scratch/cell-ready.png" -geometry +625+591 -composite \
  "$scratch/cell-handoff.png" -geometry +850+591 -composite \
  "$scratch/cell-release.png" -geometry +1075+591 -composite \
  -font "$body" -pointsize 13 -fill "$quiet" \
  -annotate +625+666 'Ready' -annotate +850+666 'Offer' -annotate +1075+666 'Release' \
  -strip "$out/pose-sheet.png"
