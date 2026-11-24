# Storybook board surrounds

`frontier_line_board-native.png` is the exact Hold the Line source the user directed us to integrate,
an unmodified 1566 × 1004 8-bit RGB PNG. SHA-256:
`24c89a8fb925939ba54606c2ac6561eb929955faaf338681d2d1c3eb3d16abdd`.
The
[pilot record](../../../../.lore/work/games/company-of-unlikely-heroes/art/pilots/hold-the-line-surround/README.md)
records its generation and distinguishes integration authorization from human acceptance of the in-game appearance.

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

## The Bridge Is Out

The native source is
`.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_bridge_board/native.png`.
It is the unmodified 1567 × 1004 8-bit RGB PNG, SHA-256
`933adca861bc98fae656b344cc7c5cc9bc3e30a82a8f2159eea1041a109cfd92`.
See the
[surround source index](../../../../.lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/README.md)
for the ten native sources and their provenance. Neither the capture nor
`.lore/local` is an input to registration or gameplay.

From the repository root, with the same Python, NumPy and ImageMagick versions
above, reproduce the runtime image:

```sh
out=$(mktemp -d)
PYTHONDONTWRITEBYTECODE=1 python games/company-of-unlikely-heroes/assets-source/storybook-surrounds/register_sides.py \
  games/company-of-unlikely-heroes/assets-source/storybook-surrounds/frontier_bridge_board.json \
  .lore/work/games/company-of-unlikely-heroes/art/pilots/map-edge-surrounds/frontier_bridge_board/native.png \
  "$out/frontier_bridge_board.png"
cmp "$out/frontier_bridge_board.png" games/company-of-unlikely-heroes/assets/storybook-surrounds/frontier_bridge_board.png
```

`register_sides.py` samples the native image directly, using the reference
live-to-authored aperture transform from `side_registration_common.json` and
the board's independent west and east warps from its JSON. It feathers only the wings, leaving the whole central
strip transparent through the header and footer, and verifies the reopened
RGBA export. The runtime shader performs the aperture refit once for the
actual viewport. The same side-only recipe serves The Last Ferryman, The Last
Wagon, Trouble on the Road, and The Goblin Mob with per-board settings. See
the [runtime board records](../../assets/storybook-surrounds/) for the
integrated boards and their derivative recipes.

### Side-only settings coordinates

Settings use reference live-page pixels on the 1280 × 820 page, not native
PNG pixels. The shared JSON gives the reference live and authored apertures.
For each output texel, the recipe maps from authored to reference live
coordinates, applies the board-specific warp there, then maps the sample
position back to authored coordinates before sampling the native art. The
runtime shader applies its own refit for the actual viewport; do not refit an
export a second time.

For each wing, `source_y_px` is paired **by position** with the shared
`destination_y_knots_px`: each destination y samples the corresponding source
y, interpolating between knots. A larger source y samples farther down the
painting, so its features appear higher on screen. The optional
`source_y_offset_px_by_y` adds interpolated signed offsets to those sample
rows. Optional `outward_x_px_by_y` supplies positive outward sample
displacements, tapered to zero at the outer frame using the shared anchor
distance. A `dry_patch`, when used, samples the original painting at
`source_x_offset_px` from the unwarped reference x and blends it over
`blend_y_px`; it does not sample the already warped wing. All optional
coordinates and offsets use the same reference live-page pixel units.
