# road surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/road/native.png`

Native SHA-256: `6323d830eec06a10331197835d4f4898776aa3acbc5dfde023bff35d8a320376`

Runtime PNG SHA-256: `47ffdaff5ab2f788c29be87610526799287afc6af5e49abd3b75e31c8f64224f`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register_sides.py games/company-of-unlikely-heroes/assets-source/storybook-surrounds/road.json .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/road/native.png "$out/road.png"
cmp "$out/road.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/road.png
```
