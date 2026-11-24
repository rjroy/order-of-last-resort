# village_approach surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/village_approach/native.png`

Native SHA-256: `dc225bc539d4ab37a24e6364262c0883fccdc0b7ecd6caf92a1bdecc40b9be7f`

Runtime PNG SHA-256: `73b96c1f52c45339c5686939b38659410023415d6117d2edccedf0ef45aa4de4`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register_sides.py games/company-of-unlikely-heroes/assets-source/storybook-surrounds/village_approach.json .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/village_approach/native.png "$out/village_approach.png"
cmp "$out/village_approach.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/village_approach.png
```
