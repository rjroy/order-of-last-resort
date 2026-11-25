# Hobby Smith outing reward illustrations

The seven reward illustrations were explicitly approved for runtime integration
on 2026-11-24. The unchanged native atlas is `hobby-smith-native.png`; its
SHA-256 is pinned in `crops.json`. The atlas arrived with the candidate assets;
its generation job and reference details are not recorded here.

The recipe assigns its seven illustrated cells in reading order to Leather
Apron, Heavier Hammer, Follow Through, Reinforced Rivets, Fine Adjustment,
Quick Release and Double Shift. The bottom-right cell is unused. `prepare.py`
checks the source hash and stock reward IDs, crops the specified rectangles and
exports unique opaque 318 × 154 sRGB PNGs. `delivery.sha256` pins the outputs.
The original Smith guild portrait is separate and unchanged.

Reproduce from the repository root with Python 3 and ImageMagick 7:

```sh
source=games/company-of-unlikely-heroes/assets-source/guild-book/upgrades-hobby-smith-candidate
out=.lore/local/smith-reward-repro
python3 "$source/prepare.py" "$out"
(cd "$out" && sha256sum -c "$OLDPWD/$source/delivery.sha256")
(cd games/company-of-unlikely-heroes/assets/guild-book/upgrades &&
  sha256sum -c "$OLDPWD/$source/delivery.sha256")
```
