# frontier_treasure_board surround

Native source: `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_treasure_board/native.png`

Native SHA-256: `e35f43f4b34fd5a4a186db5cec600a23f9991b5ecab88cfcbd7670eca38a797c`

Runtime PNG SHA-256: `963368eeaa68c24db37d1b7227242a07123a1d50543336ee2285df03f4811c0a`

From the repository root, with Python, NumPy and ImageMagick as in the [recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register.py .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_treasure_board/native.png "$out/frontier_treasure_board.png"
cmp "$out/frontier_treasure_board.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/frontier_treasure_board.png
```
