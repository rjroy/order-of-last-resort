# Storybook Gate source artwork and registration

These files preserve the native artwork and preparation steps for the [five accepted game textures](../../assets/storybook-gate/README.md). They are not required to launch the game. The two native PNGs are the source originals, not regenerable inspection captures.

| Original | Source and identity | SHA-256 |
| --- | --- | --- |
| `gate-scenery-native.png`, 1568 × 1003 | `experimental_image_generate`, OpenAI `gpt-image-2`, job `image_201184a490017OxL6LrItO1YY1`, 2026-11-21 | `6cbd109e456fa46a5d067ad44d9eccc88c444682f61f934121412aa22b379eef` |
| `props-native.png`, 1247 × 1261 | `experimental_image_generate`, OpenAI `gpt-image-2`, job `image_20117b079001IZz2CiaXdNTVOP`, 2026-11-21 | `83ab2be98e300e0ccc4e0b8a27af63c3d8c1ce307d4190cc17a1bcee0deb2da1` |

Both used the [framed Marked-Up Illustration](../../../../.lore/work/games/company-of-unlikely-heroes/art/concepts/storybook-ux/marked-up-illustration-framed.png) for visual direction (`18570ec484d5b61772c4b5a94b29ff349f1fb075155f4022a4ef44118dc0da46`). The scenery run also used a geometric layout guide and the [shipped Gate ground](../../assets/boards/frontier_gate_board.png) (`0cb6b59fb6b5c06a8b05a73571ef65882c2d518238971ffdc4f05672cfe5129f`) for camera and stone color. The prop run used the unplanned live round 2 capture for camera and scale. The guide and live capture are historical context, not prerequisites for preparing the texture files.

## Prepare a fresh copy

Use Python 3.14.8, NumPy 2.5.4, and ImageMagick 7.1.2-34, the versions used for verification. From this directory:

```sh
out=$(mktemp -d)
python register.py "$out/gate-scenery-surround-wall-rgba.png"
bash prepare.sh "$out/props"
```

`register.py` aligns the scene by measured landmarks using monotone cubic coordinate maps. It feathers the surround outside the playable area and masks both wall pieces to the blocked column. It asserts zero alpha throughout the walkable footprint. Its new output matched the accepted surround byte-for-byte.

`prepare.sh` extracts the native prop quadrants, removes faint alpha speckling, resamples in linear light, and registers each canvas. It puts the shut leaf below the same stone frame used for the open state. The four regenerated prop textures matched the accepted files pixel-for-pixel; PNG metadata may differ. The intermediate `gate-leaf.png` is reproducible and is not shipped. Neither recipe alters the native originals or writes to the game asset directory. Reproduction starts from the included native art; rerunning image generation is neither necessary nor claimed reproducible.
