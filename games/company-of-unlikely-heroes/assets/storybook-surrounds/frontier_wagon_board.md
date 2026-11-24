# frontier_wagon_board surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_wagon_board/native.png`

Native SHA-256: `0cf80eeac28270e9a4e837b05dc5e0405df62d31a241fdd3f43d5b3f40669a49`

Runtime PNG SHA-256: `8fc57fea8b4ca8c9cf2aca860b98662eb22eb2762b27261a6798fb18e2376a88`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register_sides.py games/company-of-unlikely-heroes/assets-source/storybook-surrounds/frontier_wagon_board.json .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_wagon_board/native.png "$out/frontier_wagon_board.png"
cmp "$out/frontier_wagon_board.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/frontier_wagon_board.png
```
