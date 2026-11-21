#!/usr/bin/env bash
# Assemble the transparent renders without enlarging or shrinking the native samples.
set -euo pipefail
out=${1:?"usage: $0 OUTPUT_DIR [--motion]"}
with_motion=${2:-}
if [[ -n "$with_motion" && "$with_motion" != --motion ]]; then
  printf 'Unknown option: %s\n' "$with_motion" >&2
  exit 2
fi
regular=$(fc-match 'Noto Sans:style=Regular' -f '%{file}')
heading=$(fc-match 'Noto Serif:style=Bold' -f '%{file}')
serif=$(fc-match 'Noto Serif:style=Regular' -f '%{file}')
r="$out/renders"
paper='#f2e9d8'
ink='#292b31'
muted='#574c44'
blue='#315473'
line='#bfae96'
slate='#3d4149'
stone='#786a5d'

magick -size 1536x820 "xc:$paper" \
  -fill "$line" -stroke none -draw 'rectangle 54,162 1481,163 rectangle 54,606 1481,607 rectangle 366,632 367,760 rectangle 54,780 1481,781' \
  -font "$regular" -pointsize 14 -kerning 2.8 -fill "$blue" \
    -annotate +54+54 "BARNABY'S ORDER OF LAST RESORT  /  SUMMON STUDY" \
    -annotate +1089+54 "EDITABLE MODEL  /  CANDIDATE" \
  -font "$heading" -pointsize 64 -kerning 0 -fill "$ink" \
    -annotate +51+126 "The Skeleton" \
  -font "$serif" -pointsize 23 -fill "$muted" \
    -annotate +550+125 "Friendly to a fault." \
  -font "$regular" -pointsize 14 \
    -annotate +1089+90 "Locked cast camera for all acting views." \
    -annotate +1089+116 "No effects, contact marks, or retargeting." \
  \( -size 339x313 "xc:$slate" \( "$r/neutral.png" -resize 339x313 \) -gravity center -compose over -composite +gravity \) \
    -geometry +54+190 -composite \
  \( -size 339x313 "xc:$slate" \( "$r/greet.png" -resize 339x313 \) -gravity center -compose over -composite +gravity \) \
    -geometry +417+190 -composite \
  \( -size 339x313 "xc:$slate" \( "$r/wave.png" -resize 339x313 \) -gravity center -compose over -composite +gravity \) \
    -geometry +780+190 -composite \
  \( -size 339x313 "xc:$slate" \( "$r/dont-go.png" -resize 339x313 \) -gravity center -compose over -composite +gravity \) \
    -geometry +1143+190 -composite \
  -font "$heading" -pointsize 25 -fill "$ink" \
    -annotate +54+549 "01  Neutral T" \
    -annotate +417+549 "02  Ready & Greet" \
    -annotate +780+549 "03  Wave" \
    -annotate +1143+549 "04  Don't Go" \
  -font "$regular" -pointsize 14 -fill "$muted" \
    -annotate +54+578 "Straight-on armature rest" \
    -annotate +417+578 "F18 · a small, high hello" \
    -annotate +780+578 "F15 · the first wide sweep" \
    -annotate +1143+578 "F27 · a held, open-handed plea" \
  -font "$regular" -pointsize 14 -kerning 2 -fill "$blue" \
    -annotate +54+658 "65 × 54 PX  /  1:1" \
  -font "$serif" -pointsize 19 -kerning 0 -fill "$muted" \
    -annotate +54+690 "Tactical-size figures, not enlarged." \
    -annotate +54+716 "No board or neighboring units." \
  \( -size 65x54 "xc:$stone" "$r/ready-native.png" -compose over -composite \) -geometry +423+637 -composite \
  \( -size 65x54 "xc:$stone" "$r/greet-native.png" -compose over -composite \) -geometry +629+637 -composite \
  \( -size 65x54 "xc:$stone" "$r/wave-native.png" -compose over -composite \) -geometry +835+637 -composite \
  \( -size 65x54 "xc:$stone" "$r/wave-through-native.png" -compose over -composite \) -geometry +1041+637 -composite \
  \( -size 65x54 "xc:$stone" "$r/dont-go-native.png" -compose over -composite \) -geometry +1292+637 -composite \
  -font "$regular" -pointsize 14 -fill "$ink" \
    -annotate +423+727 "Ready · F1" \
    -annotate +629+727 "Greet · F18" \
    -annotate +835+727 "Wave out · F15" \
    -annotate +1041+727 "Wave across · F20" \
    -annotate +1292+727 "Don't Go · F27" \
  "$out/contact-sheet.png"

if [[ "$with_motion" == --motion ]]; then
  m="$out/motion"
  clip=$(mktemp -d "$out/.skeleton-film-XXXXXX")
  trap 'rm -r -- "$clip"' EXIT
  for ((i=0;i<33;i++)); do
    printf -v index '%02d' "$i"
    printf -v greet '%02d' "$((i<23 ? i : 22))"
    printf -v wave '%02d' "$((i<27 ? i : 26))"
    magick -size 806x302 "xc:$paper" -compose over \
      \( -size 252x232 "xc:$slate" "$m/greet-$greet.png" -composite \) -geometry +14+13 -composite \
      \( -size 252x232 "xc:$slate" "$m/wave-$wave.png" -composite \) -geometry +277+13 -composite \
      \( -size 252x232 "xc:$slate" "$m/dont-go-$index.png" -composite \) -geometry +540+13 -composite \
      -font "$heading" -pointsize 17 -fill "$ink" \
        -annotate +14+270 "Ready & Greet" -annotate +277+270 "Wave" -annotate +540+270 "Don't Go" \
      -font "$regular" -pointsize 12 -fill "$muted" \
        -annotate +14+287 "A quick hello" -annotate +277+287 "Too much hello" -annotate +540+287 "A reach and a hold" \
      "$clip/$index.png"
  done
  ffmpeg -hide_banner -loglevel error -y -framerate 12 -start_number 0 -i "$clip/%02d.png" \
    -frames:v 33 -an -c:v libx264 -movflags +faststart -pix_fmt yuv420p -crf 18 "$out/action-comparison.mp4"
fi
