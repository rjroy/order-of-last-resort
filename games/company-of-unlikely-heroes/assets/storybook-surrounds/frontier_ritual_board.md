# frontier_ritual_board surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_ritual_board/native.png`

Native SHA-256: `47a52bda3d96f475031ed7e1ae632684108d76d1799bb5a16fe08c396f40f192`

Runtime PNG SHA-256: `4375f972e517e7d8c0145b9985b91cd684d0f735dd636448d7409d70bdf5c5af`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register.py .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_ritual_board/native.png "$out/frontier_ritual_board.png"
cmp "$out/frontier_ritual_board.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/frontier_ritual_board.png
```
