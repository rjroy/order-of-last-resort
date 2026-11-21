#!/usr/bin/env bash
# Assemble the PNG renders of the saved model. Film frames are optional.
set -euo pipefail
out=${1:?"usage: $0 OUTPUT_DIR"}
regular=$(fc-match 'Noto Sans:style=Regular' -f '%{file}')
display=$(fc-match 'Noto Serif:style=Bold' -f '%{file}')
serif=$(fc-match 'Noto Serif:style=Regular' -f '%{file}')
r="$out/renders"
paper='#f5e9d4'
ink='#332b25'
muted='#655749'
brick='#843f3a'
rule='#cdb899'

# Paste the four native renders at their original 65 x 54; only the large
# panels are resized. All action panels use the same tactical camera.
magick -size 1516x764 "xc:$paper" \
  -fill "$rule" -stroke none -draw \
    'rectangle 54,174 1461,175 rectangle 54,621 1461,622' \
  -font "$regular" -pointsize 14 -kerning 2.2 -fill "$brick" \
    -annotate +54+49 "BARNABY'S ORDER OF LAST RESORT  /  CAST MODEL STUDY" \
    -annotate +1116+49 "MODEL CANDIDATE  /  05" \
  -font "$display" -pointsize 65 -kerning 0 -fill "$ink" \
    -annotate +51+117 "The Rogue" \
  -font "$serif" -pointsize 24 -fill "$muted" \
    -annotate +55+150 "An old theatre usher who never saw a thing." \
  -font "$regular" -pointsize 14 -fill "$muted" \
    -annotate +1116+78 "Blender · 2.47 m orthographic scale" \
    -annotate +1116+101 "Tactical view locked for all three actions" \
  \( "$r/neutral.png" -resize 329x318! \) -geometry +54+202 -composite \
  \( "$r/retreat.png" -resize 329x318! \) -geometry +413+202 -composite \
  \( "$r/dodge.png" -resize 329x318! \) -geometry +772+202 -composite \
  \( "$r/alibi.png" -resize 329x318! \) -geometry +1131+202 -composite \
  -font "$display" -pointsize 25 -fill "$ink" \
    -annotate +54+562 "01  Neutral T" \
    -annotate +413+562 "02  Ready / Retreat" \
    -annotate +772+562 "03  Confusing Dodge" \
    -annotate +1131+562 "04  Wasn't Me" \
  -font "$regular" -pointsize 14 -fill "$muted" \
    -annotate +54+588 "Frame 1 · actual armature rest" \
    -annotate +413+588 "Frame 13 · rear shoe plants" \
    -annotate +772+588 "Frame 10 · low cross; rose lining flashes" \
    -annotate +1131+588 "Frame 25 · heels close; both hands seen" \
  -font "$regular" -pointsize 14 -kerning 2.2 -fill "$brick" \
    -annotate +54+681 "AT 65 × 54" \
  -font "$serif" -pointsize 18 -kerning 0 -fill "$muted" \
    -annotate +54+710 "Actual pixels. Figure only, not a board test." \
  "$r/retreat-native.png" -geometry +555+646 -composite \
  "$r/dodge-native.png" -geometry +778+646 -composite \
  "$r/cross-plant-native.png" -geometry +1000+646 -composite \
  "$r/alibi-native.png" -geometry +1225+646 -composite \
  -font "$regular" -pointsize 13 -fill "$muted" \
    -annotate +555+724 "Retreat · 13" \
    -annotate +778+724 "Lining flash · 10" \
    -annotate +1000+724 "Cross-plant · 12" \
    -annotate +1225+724 "Alibi hold · 25" \
  "$out/contact-sheet.png"

m="$out/motion"
if [[ -f "$m/retreat-13.png" && -f "$m/dodge-17.png" && -f "$m/alibi-25.png" ]]; then
  dst="$out/motion-strip"
  mkdir -p -- "$dst"
  for ((i=0;i<26;i++)); do
    printf -v suffix '%02d' "$i"
    printf -v a '%02d' "$((i<14 ? i : 13))"
    printf -v b '%02d' "$((i<18 ? i : 17))"
    magick -size 804x284 "xc:$paper" \
      "$m/retreat-$a.png" -geometry +12+12 -composite \
      "$m/dodge-$b.png" -geometry +276+12 -composite \
      "$m/alibi-$suffix.png" -geometry +540+12 -composite \
      -font "$display" -pointsize 16 -fill "$ink" \
        -annotate +12+255 "Ready / Retreat" \
        -annotate +276+255 "Confusing Dodge" \
        -annotate +540+255 "Wasn't Me" \
      -font "$regular" -pointsize 11 -fill "$muted" \
        -annotate +12+272 "Short yielding step" \
        -annotate +276+272 "Cross, pivot, come back" \
        -annotate +540+272 "Open palm; hold the alibi" \
      "$dst/$suffix.png"
  done
  ffmpeg -hide_banner -loglevel error -y -framerate 12 -i "$dst/%02d.png" \
    -c:v libwebp_anim -quality 84 -loop 0 -an "$out/three-beats.webp"
fi
