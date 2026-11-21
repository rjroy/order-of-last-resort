#!/usr/bin/env bash
# Compose the read-only Blender review renders. The bottom row stays at 1:1.
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
paper='#f3ead8'
ink='#272b27'
muted='#575040'
olive='#536045'
line='#beaf96'
slate='#41443e'
stone='#786a5d'

magick -size 1536x820 "xc:$paper" \
  -stroke none -fill "$line" -draw 'rectangle 54,156 1481,157 rectangle 54,571 1481,572 rectangle 336,610 337,747 rectangle 54,778 1481,779' \
  -font "$regular" -pointsize 14 -kerning 2.5 -fill "$olive" \
    -annotate +54+54 "BARNABY'S ORDER OF LAST RESORT  /  SUMMON STUDY" \
    -annotate +1100+54 "EDITABLE MODEL  /  THROW REVISION" \
  -font "$heading" -pointsize 64 -kerning 0 -fill "$ink" -annotate +51+124 "The Zombie" \
  -font "$serif" -pointsize 24 -fill "$muted" -annotate +549+122 "He brought something from the garden." \
  -font "$regular" -pointsize 14 \
    -annotate +1100+89 "Same cast camera for all acting views." \
    -annotate +1100+115 "Joined prop in flight; no hit or target." \
  \( -size 273x252 "xc:$slate" \( "$r/neutral.png" -resize 273x252 \) -gravity center -compose over -composite +gravity \) \
    -geometry +54+198 -composite \
  \( -size 273x252 "xc:$slate" \( "$r/ready.png" -resize 273x252 \) -gravity center -compose over -composite +gravity \) \
    -geometry +342+198 -composite \
  \( -size 273x252 "xc:$slate" \( "$r/hello.png" -resize 273x252 \) -gravity center -compose over -composite +gravity \) \
    -geometry +630+198 -composite \
  \( -size 273x252 "xc:$slate" \( "$r/windup.png" -resize 273x252 \) -gravity center -compose over -composite +gravity \) \
    -geometry +918+198 -composite \
  \( -size 273x252 "xc:$slate" \( "$r/flight.png" -resize 273x252 \) -gravity center -compose over -composite +gravity \) \
    -geometry +1206+198 -composite \
  -font "$heading" -pointsize 24 -fill "$ink" \
    -annotate +54+497 "01  Neutral T" -annotate +342+497 "02  Ready" \
    -annotate +630+497 "03  Say Hello" -annotate +918+497 "04  Windup" -annotate +1206+497 "05  Thrown" \
  -font "$regular" -pointsize 14 -fill "$muted" \
    -annotate +54+528 "True rest, prop hidden" \
    -annotate +342+528 "F1  /  gift stays low" \
    -annotate +630+528 "F19  /  head first, no shove" \
    -annotate +918+528 "F14  /  hefts the gift back" \
    -annotate +1206+528 "F26  /  rock and daisy in flight" \
  -font "$regular" -pointsize 14 -kerning 2 -fill "$olive" \
    -annotate +54+640 "65 × 54 PX  /  1:1" \
  -font "$serif" -pointsize 18 -kerning 0 -fill "$muted" \
    -annotate +54+675 "Tactical samples, not enlarged." \
    -annotate +54+703 "The gift leaves at frame 22." \
  \( -size 65x54 "xc:$stone" "$r/ready-native.png" -compose over -composite \) -geometry +371+619 -composite \
  \( -size 65x54 "xc:$stone" "$r/hello-native.png" -compose over -composite \) -geometry +550+619 -composite \
  \( -size 65x54 "xc:$stone" "$r/windup-native.png" -compose over -composite \) -geometry +729+619 -composite \
  \( -size 65x54 "xc:$stone" "$r/release-native.png" -compose over -composite \) -geometry +908+619 -composite \
  \( -size 65x54 "xc:$stone" "$r/flight-native.png" -compose over -composite \) -geometry +1087+619 -composite \
  \( -size 65x54 "xc:$stone" "$r/follow-native.png" -compose over -composite \) -geometry +1266+619 -composite \
  -font "$regular" -pointsize 14 -fill "$ink" \
    -annotate +371+710 "Ready · F1" -annotate +550+710 "Hello · F19" \
    -annotate +729+710 "Windup · F14" -annotate +908+710 "Release · F22" \
    -annotate +1087+710 "In flight · F26" -annotate +1266+710 "Follow-through · F32" \
  "$out/contact-sheet-throw-v2.png"

if [[ "$with_motion" == --motion ]]; then
  m="$out/motion"
  clip=$(mktemp -d "$out/.zombie-film-XXXXXX")
  trap 'rm -r -- "$clip"' EXIT
  for ((i=1;i<=57;i++)); do
    printf -v index '%02d' "$i"
    printf -v hello '%02d' "$((i<=45 ? i : 45))"
    magick -size 640x344 "xc:$paper" -compose over \
      \( -size 300x272 "xc:$slate" "$m/hello-$hello.png" -composite \) -geometry +14+13 -composite \
      \( -size 300x272 "xc:$slate" "$m/offer-$index.png" -composite \) -geometry +326+13 -composite \
      -font "$heading" -pointsize 19 -fill "$ink" \
        -annotate +14+311 "Say Hello" -annotate +326+311 "Offer Flower" \
      -font "$regular" -pointsize 12 -fill "$muted" \
        -annotate +14+329 "A little too close" -annotate +326+329 "A friendly throw with a lot of momentum" \
      "$clip/$index.png"
  done
  ffmpeg -hide_banner -loglevel error -y -framerate 24 -start_number 1 -i "$clip/%02d.png" \
    -frames:v 57 -an -c:v libx264 -movflags +faststart -pix_fmt yuv420p -crf 18 "$out/action-comparison-throw-v2.mp4"
fi
