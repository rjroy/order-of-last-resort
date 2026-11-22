#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
    printf 'Usage: bash review.sh PORTRAIT_DIRECTORY REVIEW_PNG\n' >&2
    exit 2
fi
art="$1"
review="$2"
ids=(knight healer wizard rogue bard necromancer alchemist blacksmith)
names=('Anxious Knight' 'Unimpressed Healer' 'Enthusiastic Caster' 'Daft Dodger'
       'Bad Bard' 'Friendly Crypter' 'Mixologist' 'Hobby Smith')
font="$(fc-match -f '%{file}' sans)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p -- "$(dirname -- "$review")"

entries=()
for i in "${!ids[@]}"; do
    id="${ids[i]}"
    entry="$scratch/$id.png"
    magick \
        \( "$art/$id.png" -resize 180x180 \) \
        \( \( "$art/$id.png" -resize '112x116^' -gravity center -extent 112x116 \) \
           \( "$art/$id.png" -resize '44x44' \) \
           -background '#e5d5b8' -gravity center +append -extent 180x124 \) \
        \( -size 180x29 -background '#e5d5b8' -fill '#2f2319' -font "$font" \
           -pointsize 14 -gravity center "label:${names[i]}" \) \
        -background '#e5d5b8' -gravity center -append "$entry"
    entries+=("$entry")
done

magick montage "${entries[@]}" -tile 4x2 -geometry +8+8 -background '#c1a98a' "$review"
