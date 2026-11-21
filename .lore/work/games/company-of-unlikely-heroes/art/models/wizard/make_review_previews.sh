#!/usr/bin/env bash
set -euo pipefail

out="${1:?usage: bash make_review_previews.sh /absolute/review-directory}"
renders="$out/renders"
work="$out/preview-assembly"
mkdir -p "$work"
serif="$(fc-match -f '%{file}' 'Noto Serif')"
sans="$(fc-match -f '%{file}' 'Noto Sans')"
bg='#242029'
paper='#f1e5cd'
accent='#e4ab77'
muted='#ccc0be'
line='#544650'

card() {
  local file="$1" tag="$2" title="$3"
  magick -size 231x311 "xc:$bg" \
    \( "$renders/$file.png" -resize '231x248!' \) -gravity northwest -composite \
    -font "$sans" -pointsize 11 -fill "$accent" -annotate +1+272 "$tag" \
    -font "$serif" -pointsize 20 -fill "$paper" -annotate +1+287 "$title" \
    "$work/$file-card.png"
}

card rest   '01   /   FRONT STUDY' 'Neutral T'
card ready  '01   /   COMMON START' 'Ready'
card blast  '14   /   BLAST' 'Plant and release'
card tug    '13   /   PULL' 'Draw in'
card slip   '19   /   PULL' 'Lose the footing'
card seated '24   /   PULL' 'Land seated'

# Resize every action at the same scale. No content-dependent crop or recenter.
for entry in 'ready:Ready' 'blast:Blast' 'tug:Tug' 'slip:Slip' 'seated:Seated'; do
  file="${entry%:*}"
  title="${entry#*:}"
  magick -size 65x77 "xc:$bg" \
    \( "$renders/$file.png" -resize '65x54' -gravity center -background '#c6b4a6' -extent 65x54 \) \
    -gravity northwest -composite \
    -font "$sans" -pointsize 11 -fill "$muted" -annotate +0+69 "$title" \
    "$work/$file-small.png"
done

magick -size 1528x548 "xc:$bg" \
  -font "$sans" -pointsize 12 -fill "$accent" -annotate +28+28 'MIND GARAGE   /   BARNABY’S ORDER OF LAST RESORT' \
  -font "$serif" -pointsize 46 -fill "$paper" -annotate +27+78 'The wizard' \
  -font "$sans" -pointsize 13 -fill "$muted" -gravity northeast -annotate +28+59 'MOTION BLOCKOUT   /   FIXED TACTICAL 3Q   /   24 FPS' \
  -gravity northwest -fill "$line" -draw 'line 28,97 1500,97 line 28,430 1500,430' \
  "$work/rest-card.png"   -geometry +28+114   -composite \
  "$work/ready-card.png"  -geometry +276+114  -composite \
  "$work/blast-card.png"  -geometry +524+114  -composite \
  "$work/tug-card.png"    -geometry +772+114  -composite \
  "$work/slip-card.png"   -geometry +1020+114 -composite \
  "$work/seated-card.png" -geometry +1268+114 -composite \
  -geometry +0+0 -font "$sans" -pointsize 12 -fill "$accent" -annotate +28+464 'TACTICAL SCALE CHECK' \
  -font "$serif" -pointsize 24 -fill "$paper" -annotate +28+495 '65 × 54 px' \
  -font "$sans" -pointsize 12 -fill "$muted" -annotate +28+515 'Native-size isolated samples, not a board.' \
  "$work/ready-small.png"  -geometry +321+449 -composite \
  "$work/blast-small.png"  -geometry +406+449 -composite \
  "$work/tug-small.png"    -geometry +491+449 -composite \
  "$work/slip-small.png"   -geometry +576+449 -composite \
  "$work/seated-small.png" -geometry +661+449 -composite \
  -geometry +0+0 -font "$sans" -pointsize 12 -fill "$accent" -annotate +848+475 'BLAST   /   STEP BACK TO READY' \
  -annotate +848+500 'PULL     /   STAYS DOWN AT END OF TAKE' \
  -depth 8 -strip "$out/contact-sheet.png"

if [[ -f "$renders/pull/019.png" && -f "$renders/blast/019.png" ]]; then
  for ((i=0; i<20; i++)); do
    printf -v f '%03d' "$i"
    magick -size 612x360 "xc:$bg" \
      "$renders/blast/$f.png" -geometry +12+38 -composite \
      "$renders/pull/$f.png" -geometry +312+38 -composite \
      -geometry +0+0 -font "$serif" -pointsize 19 -fill "$paper" \
      -annotate +12+27 'Blast' -annotate +312+27 'Pull' \
      -font "$sans" -pointsize 12 -fill "$muted" -gravity northeast \
      -annotate +13+17 "$(printf 'F%02d' "$((i*2+1))")" \
      "$work/motion-$f.png"
  done
  ffmpeg -nostdin -y -hide_banner -loglevel error -framerate 12 -start_number 0 \
    -i "$work/motion-%03d.png" -vf 'tpad=stop_mode=clone:stop_duration=0.65' \
    -c:v libwebp_anim -pix_fmt yuv420p -quality 84 -loop 0 "$out/blast-and-pull.webp"
fi
