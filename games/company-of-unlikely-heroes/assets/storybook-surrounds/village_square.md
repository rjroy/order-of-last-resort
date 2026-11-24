# Village Square surround

The Unwelcome Guest uses `village_square.png`, a registered derivative with
two localized corner corrections. The native surround painting and the
existing board painting remain unchanged. The runtime derivative has SHA-256
`83db52f0b19dde5ea57f70dca12d5b86b82ff02f35b51797f42014feb1320d02`.

## Sources

- Native surround:
  `.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/village_square/native.png`,
  SHA-256 `8312c3c17b625f7e918d5b7641143a57fa551cc2726b5a73ac622708f16a7365`.
  Its adjacent README records generation provenance.
- Existing ground: `games/company-of-unlikely-heroes/assets/boards/village_square.png`,
  SHA-256 `bba9c65ea75cece6e376cd56e15f4a02115d4373aee75bcb382b18548681911e`.
  Its provenance and registration are in `assets/boards/manifest.json`.

The recipe first uses the shared ring registration, then samples the existing
ground master to blend the upper-west wall and lower-east roof corners using
`village_square-corners.json`. It checks that the two regions are separate,
that no RGB changes occur outside them, that each changes visible pixels, and
that the saved alpha exactly matches the shared ring. The native painting,
ground master, screenshots and local evidence are not runtime inputs.

From the repository root, with Python, NumPy and ImageMagick as described in the
[recipe package](../../assets-source/storybook-surrounds/README.md):

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register_corners.py \
  games/company-of-unlikely-heroes/assets-source/storybook-surrounds/village_square-corners.json \
  .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/village_square/native.png \
  games/company-of-unlikely-heroes/assets/boards/village_square.png \
  "$out/village_square.png"
cmp "$out/village_square.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/village_square.png
```

The lossless Godot import disables alpha-border color fixup. The scenery is
selected only for the trusted built-in board; the live board and gameplay
remain independent of the painting.
