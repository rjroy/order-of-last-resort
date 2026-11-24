# Storybook board surrounds

`frontier_line_board-native.png` is the exact approved Hold the Line source,
an unmodified 1566 × 1004 8-bit RGB PNG. SHA-256:
`24c89a8fb925939ba54606c2ac6561eb929955faaf338681d2d1c3eb3d16abdd`.
It was generated on 2026-11-23 with one native OpenAI `image_gen` call via
Codex CLI 0.172.0 and ChatGPT login; the model was not reported. The generation
referenced the Line board for terrain and the Field native for composition.
The native call was `call_9e80193c49f841a08db95cc533c61689`, thread
`01a20bd3-ccea-7a53-a578-b8256cee98bc`. The preserved pilot record is
`.lore/work/games/company-of-unlikely-heroes/art/pilots/hold-the-line-surround/README.md`.
The game does not read that record.

From the repository root, with Python 3.14.8, NumPy 2.5.4 and ImageMagick
7.1.2-34, reproduce the runtime derivative without overwriting any original:

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register.py \
  games/company-of-unlikely-heroes/assets-source/storybook-surrounds/frontier_line_board-native.png \
  "$out/frontier_line_board.png"
cmp "$out/frontier_line_board.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/frontier_line_board.png
```

The command reuses `storybook-field/register.py` to fit the source to the
1280 × 820 page and feather outward from the shared 7 × 5 aperture. It reopens
the output and verifies that all 491,228 pixel centers in that aperture have
zero alpha. The live scenery shader refits that aperture to the board. The
recipe accepts any source and new output path, so other approved board-specific
paintings can use it without a copy of the algorithm. A derivative is not
enabled merely by generating it: add an explicit trusted board-ID mapping only
after its source and integration are approved.
