# village_lane surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/village_lane/native.png`

Native SHA-256: `2fa08ae52287a947926b893e3aa05ad33461f7b07014dcb716df670355f9d00c`

Runtime PNG SHA-256: `05264eda8ad1be03451257c696f3d2bb98bf336e8195a3e7ea90abf029232604`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register.py .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/village_lane/native.png "$out/village_lane.png"
cmp "$out/village_lane.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/village_lane.png
```
