# frontier_sheep_board surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_sheep_board/native.png`

Native SHA-256: `f9352932d20f529a334bc28330fdb3cb90be09780f8755f58cb4c9cbed0fbfb7`

Runtime PNG SHA-256: `6da5bd2eafa2c57098f63eab5bf3c4dd625a229ce6912a7b186d8ae5248f363d`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register.py .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_sheep_board/native.png "$out/frontier_sheep_board.png"
cmp "$out/frontier_sheep_board.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/frontier_sheep_board.png
```
