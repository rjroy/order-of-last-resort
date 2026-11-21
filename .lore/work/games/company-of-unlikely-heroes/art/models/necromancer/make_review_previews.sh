#!/usr/bin/env bash
# Lay out the renders without changing any source or rescaling the native samples.
set -euo pipefail
out=${1:?"usage: $0 OUTPUT_DIR"}
regular=$(fc-match 'Noto Sans:style=Regular' -f '%{file}')
heading=$(fc-match 'Noto Serif:style=Bold' -f '%{file}')
serif=$(fc-match 'Noto Serif:style=Regular' -f '%{file}')
r="$out/renders"
m="$out/motion"
paper='#f4eadb'
ink='#322831'
muted='#62574e'
accent='#8c4c27'
line='#cab497'

magick -size 1516x802 "xc:$paper" \
  -fill "$line" -stroke none -draw \
    'rectangle 54,175 1461,176 rectangle 54,622 1461,623 rectangle 506,650 507,754' \
  -font "$regular" -pointsize 14 -kerning 2.5 -fill "$accent" \
    -annotate +54+49 "BARNABY'S ORDER OF LAST RESORT  /  CAST MODEL STUDY" \
    -annotate +1072+49 "MODEL CANDIDATE  /  06" \
  -font "$heading" -pointsize 62 -kerning 0 -fill "$ink" \
    -annotate +51+115 "The Necromancer" \
  -font "$serif" -pointsize 24 -fill "$muted" \
    -annotate +55+151 "Keeper of the Bell" \
  -font "$regular" -pointsize 14 \
    -annotate +1072+78 "Blender · 2.47 m orthographic scale" \
    -annotate +1072+101 "Tactical camera locked for all acting views" \
  \( -size 329x318 'xc:#41444d' \( "$r/neutral.png" -resize 329x318! \) -compose over -composite \) \
    -geometry +54+202 -composite \
  \( "$r/ready.png" -resize 329x318! \) -geometry +413+202 -composite \
  \( "$r/ring.png" -resize 329x318! \) -geometry +772+202 -composite \
  \( "$r/raise.png" -resize 329x318! \) -geometry +1131+202 -composite \
  -font "$heading" -pointsize 25 -fill "$ink" \
    -annotate +54+562 "01  Neutral T" \
    -annotate +413+562 "02  Ready" \
    -annotate +772+562 "03  Summon Skeleton" \
    -annotate +1131+562 "04  Raise Dead" \
  -font "$regular" -pointsize 14 -fill "$muted" \
    -annotate +54+588 "Frame 1 · armature rest, bell off" \
    -annotate +413+588 "Frame 1 · bell at his side" \
    -annotate +772+588 "Frame 13 · ring out, palm open" \
    -annotate +1131+588 "Frame 34 · bell in, palm low" \
  -font "$regular" -pointsize 14 -kerning 2.5 -fill "$accent" \
    -annotate +54+681 "AT 65 × 54" \
  -font "$serif" -pointsize 18 -kerning 0 -fill "$muted" \
    -annotate +54+712 "Actual pixels. Figure only, not a board test." \
  \( -size 65x54 'xc:#c7b49c' "$r/ready-native.png" -compose over -composite \) -geometry +588+652 -composite \
  \( -size 65x54 'xc:#c7b49c' "$r/ring-native.png" -compose over -composite \) -geometry +907+652 -composite \
  \( -size 65x54 'xc:#c7b49c' "$r/raise-native.png" -compose over -composite \) -geometry +1226+652 -composite \
  -font "$regular" -pointsize 13 -fill "$muted" \
    -annotate +588+731 "Ready · 1" \
    -annotate +907+731 "Wrist stroke · 13" \
    -annotate +1226+731 "Low offer · 34" \
  "$out/contact-sheet.png"

if [[ -d "$m" ]]; then
  clips="$out/film"
  mkdir -p -- "$clips"
  for ((i=0;i<35;i++)); do
    printf -v suffix '%02d' "$i"
    printf -v ring '%02d' "$((i<23 ? i : 22))"
    magick -size 602x310 "xc:$paper" \
      "$m/ring-$ring.png" -geometry +14+14 -composite \
      "$m/raise-$suffix.png" -geometry +308+14 -composite \
      -font "$heading" -pointsize 17 -fill "$ink" \
        -annotate +14+284 "Summon Skeleton" \
        -annotate +308+284 "Raise Dead" \
      -font "$regular" -pointsize 12 -fill "$muted" \
        -annotate +14+300 "Ring out; the other hand welcomes" \
        -annotate +308+300 "Tuck the bell; offer a hand from one knee" \
      "$clips/$suffix.png"
  done
  ffmpeg -hide_banner -loglevel error -y -framerate 12 -start_number 0 -i "$clips/%02d.png" \
    -frames:v 35 -an -c:v libx264 -movflags +faststart -pix_fmt yuv420p -crf 18 "$out/action-comparison.mp4"
fi
