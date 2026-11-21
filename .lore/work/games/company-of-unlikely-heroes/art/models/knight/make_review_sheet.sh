#!/usr/bin/env bash
# Compose inspection renders made by review_knight.py. Run from any directory.
set -euo pipefail
renders="${1:?Pass the directory containing the Blender review renders}"
output="${2:-"$renders/knight-preview.png"}"

magick -size 1690x900 xc:'#18231f' \
  -fill '#304039' -draw 'rectangle 36,134 1654,137 rectangle 36,749 1654,750' \
  -font Noto-Serif-Display-Condensed-Medium -pointsize 53 -fill '#f5e7c7' \
  -annotate +36+109 'The Knight at the guild steps' \
  -font Noto-Sans-Regular -pointsize 15 -fill '#d0aa68' -kerning 3 \
  -annotate +39+42 'BARNABY’S ORDER OF LAST RESORT' \
  -font Noto-Sans-Regular -pointsize 17 -fill '#bdc8b9' -kerning 0 \
  -gravity northeast -annotate +37+50 'BLENDER BLOCKOUT  /  POSE & SILHOUETTE STUDY' \
  -gravity northwest \
  \( "$renders/rest.png" -resize 400x493^ -gravity center -extent 400x493 -gravity northwest \) -geometry +36+156 -composite \
  \( "$renders/wary.png" -resize 400x493^ -gravity center -extent 400x493 -gravity northwest \) -geometry +442+156 -composite \
  \( "$renders/guard.png" -resize 400x493^ -gravity center -extent 400x493 -gravity northwest \) -geometry +848+156 -composite \
  \( "$renders/settle.png" -resize 400x493^ -gravity center -extent 400x493 -gravity northwest \) -geometry +1254+156 -composite \
  -font Noto-Sans-Regular -pointsize 15 -fill '#d0aa68' -kerning 1 \
  -annotate +36+680 '00 / REST' -annotate +442+680 '08 / WARY' \
  -annotate +848+680 '39 / GUARD' -annotate +1254+680 '65 / SETTLE' \
  -font Noto-Serif-Display-Condensed-Medium -pointsize 25 -fill '#f5e7c7' -kerning 0 \
  -annotate +36+719 'Neutral, shield hidden' -annotate +442+719 'Peers past a low shield' \
  -annotate +848+719 'Front boot planted; shield up' -annotate +1254+719 'Eases back without stepping' \
  -font Noto-Sans-Regular -pointsize 14 -fill '#d0aa68' -kerning 1 \
  -annotate +36+788 'SMALL-SCALE SILHOUETTE' \
  -font Noto-Sans-Regular -pointsize 14 -fill '#bdc8b9' -kerning 0 \
  -annotate +36+813 '65 × 54 px samples at native size; not a board mockup.' \
  \( "$renders/rest.png" -resize 65x54 -gravity center -background '#415650' -extent 65x54 -gravity northwest \) -geometry +594+770 -composite \
  \( "$renders/wary.png" -resize 65x54 -gravity center -background '#415650' -extent 65x54 -gravity northwest \) -geometry +903+770 -composite \
  \( "$renders/guard.png" -resize 65x54 -gravity center -background '#415650' -extent 65x54 -gravity northwest \) -geometry +1207+770 -composite \
  \( "$renders/settle.png" -resize 65x54 -gravity center -background '#415650' -extent 65x54 -gravity northwest \) -geometry +1510+770 -composite \
  -font Noto-Sans-Regular -pointsize 13 -fill '#bdc8b9' \
  -annotate +594+850 '00  REST' -annotate +903+850 '08  WARY' \
  -annotate +1207+850 '39  GUARD' -annotate +1510+850 '65  SETTLE' \
  -strip "$output"
