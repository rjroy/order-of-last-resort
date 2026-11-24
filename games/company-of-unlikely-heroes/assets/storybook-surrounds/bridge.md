# bridge surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/bridge/native.png`

Native SHA-256: `dbb799af8910f5cfd20eef8af529a52b2ab0b85964505adc3be47877051fc252`

Runtime PNG SHA-256: `a225808fdf6a5fc7d3f15fbbbe44d9b1f6ba8adcd1bfacb4844305bd044b0725`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register_sides.py games/company-of-unlikely-heroes/assets-source/storybook-surrounds/bridge.json .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/bridge/native.png "$out/bridge.png"
cmp "$out/bridge.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/bridge.png
```
