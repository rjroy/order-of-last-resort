#!/usr/bin/env bash
set -euo pipefail

out="${1:?usage: bash make_review_previews.sh /absolute/review-directory}"
renders="$out/renders"
work="$out/preview-assembly"
mkdir -p "$work"
serif="$(fc-match -f '%{file}' 'Noto Serif')"
sans="$(fc-match -f '%{file}' 'Noto Sans')"
bg='#20292a'
paper='#eee4ce'
accent='#e1af6d'
muted='#bfc7c2'
line='#4a5656'

card() {
  local file="$1" title="$2" sub="$3"
  magick -size 278x356 "xc:$bg" \
    \( "$renders/$file.png" -resize '278x299^' -gravity center -extent 278x299 \) \
    -gravity northwest -geometry +0+0 -compose over -composite \
    -font "$serif" -pointsize 21 -fill "$paper" -annotate +0+315 "$title" \
    -font "$sans" -pointsize 13 -fill "$muted" -annotate +1+334 "$sub" \
    "$work/$file-card.png"
}

card rest 'Neutral T' 'Front check  /  staff hidden'
card ready 'Ready' 'Frame 01  /  the common start'
card ally 'Ally heal' 'Frame 17  /  hand out'
card self 'Self heal' 'Frame 17  /  hand to chest'
card wind-up 'Raise the crook' 'Frame 10  /  load'
card knock 'Knock' 'Frame 15  /  head-height contact'
card rebound 'Rebound' 'Frame 18  /  lift off'

for entry in 'ready:Ready' 'ally:Ally' 'self:Self' 'knock:Knock'; do
  file="${entry%:*}"
  title="${entry#*:}"
  magick -size 95x81 "xc:$bg" \
    \( "$renders/$file.png" -resize '65x54^' -gravity center -extent 65x54 \) \
    -gravity northwest -geometry +0+0 -compose over -composite \
    -font "$sans" -pointsize 12 -fill "$muted" -annotate +0+62 "$title" \
    "$work/$file-small.png"
done
magick -size 278x356 "xc:$bg" -fill "$line" -draw 'line 0,0 277,0' \
  -font "$sans" -pointsize 14 -fill "$accent" -annotate +12+44 'TACTICAL SCALE CHECK' \
  -font "$serif" -pointsize 29 -fill "$paper" -annotate +12+85 '65 × 54 px' \
  -font "$sans" -pointsize 13 -fill "$muted" -annotate +12+111 'Cells shown as isolated samples.' \
  "$work/ready-small.png" -geometry +12+143 -composite \
  "$work/ally-small.png" -geometry +116+143 -composite \
  "$work/self-small.png" -geometry +12+226 -composite \
  "$work/knock-small.png" -geometry +116+226 -composite \
  "$work/board-card.png"

magick -size 1200x850 "xc:$bg" \
  -font "$sans" -pointsize 13 -fill "$accent" -annotate +22+26 'MIND GARAGE   /   BARNABY’S ORDER OF LAST RESORT' \
  -font "$serif" -pointsize 41 -fill "$paper" -annotate +21+68 'The field medic' \
  -font "$sans" -pointsize 13 -fill "$muted" -gravity northeast -annotate +23+54 'MOTION BLOCKOUT   /   FIXED 3Q   /   24 FPS' \
  -gravity northwest -fill "$line" -draw 'line 22,82 1177,82' \
  "$work/rest-card.png" -geometry +22+98 -composite \
  "$work/ready-card.png" -geometry +314+98 -composite \
  "$work/ally-card.png" -geometry +606+98 -composite \
  "$work/self-card.png" -geometry +898+98 -composite \
  "$work/wind-up-card.png" -geometry +22+476 -composite \
  "$work/knock-card.png" -geometry +314+476 -composite \
  "$work/rebound-card.png" -geometry +606+476 -composite \
  "$work/board-card.png" -geometry +898+476 -composite \
  -depth 8 -strip "$out/contact-sheet.png"

if [[ -f "$renders/proxy-knock.png" ]]; then
  magick -size 1136x477 "xc:$bg" \
    -font "$serif" -pointsize 27 -fill "$paper" -annotate +19+37 'Bonk contact at head height' \
    -font "$sans" -pointsize 13 -fill "$muted" -gravity northeast \
    -annotate +19+24 'TEAL WIRE = DIAGNOSTIC MARKER ONLY' -gravity northwest \
    "$renders/proxy-wind-up.png" -geometry +16+53 -composite \
    "$renders/proxy-knock.png" -geometry +388+53 -composite \
    "$renders/proxy-rebound.png" -geometry +760+53 -composite \
    -font "$sans" -pointsize 13 -fill "$paper" \
    -annotate +23+443 '10  /  RAISE' -annotate +395+443 '15  /  CONTACT' \
    -annotate +767+443 '18  /  REBOUND' -depth 8 -strip "$out/head-height-diagnostic.png"
fi

if [[ -f "$renders/adjacent-bonk/031.png" ]]; then
  for ((i=0; i<32; i++)); do
    printf -v f '%03d' "$i"
    magick -size 874x350 "xc:$bg" \
      "$renders/ally-heal/$f.png" -geometry +9+36 -composite \
      "$renders/self-heal/$f.png" -geometry +296+36 -composite \
      "$renders/adjacent-bonk/$f.png" -geometry +583+36 -composite \
      -font "$serif" -pointsize 18 -fill "$paper" \
      -annotate +13+26 'Ally heal' -annotate +300+26 'Self heal' -annotate +587+26 'Adjacent bonk' \
      -font "$sans" -pointsize 12 -fill "$muted" -gravity northeast -annotate +13+14 "$(printf 'F%02d' "$((i+1))")" \
      "$work/motion-$f.png"
  done
  ffmpeg -nostdin -y -hide_banner -loglevel error -framerate 24 -start_number 0 \
    -i "$work/motion-%03d.png" -vf 'tpad=stop_mode=clone:stop_duration=0.5' \
    -c:v libwebp_anim -pix_fmt yuv420p -quality 81 -loop 0 "$out/three-beats.webp"
fi
