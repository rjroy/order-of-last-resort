# Guild book destination paintings

These paintings show destinations from a traveler’s viewpoint. They are candidates for the non-battle storybook redesign, not player-approved final artwork or changes to the battle grounds. The connected study was reviewed before batch generation on 2026-11-21.

The game ships twelve distinct opaque 960 × 500, 8-bit sRGB PNGs under `assets/guild-book/destinations/`. Nine commission finales and seven practice finales share four destinations. Each destination has one exact texture, regardless of how the player reaches it. No source painting, crop tool, scratch path, or generator is needed to play.

## Origin and composition

OpenCode’s built-in `experimental_image_generate` used `openai/gpt-image-2`. `manifest.json` records the generation jobs, scene briefs, visual references, source dimensions and checksums, crop coordinates, and exact candidate checksums. The PNGs in `native/` are unchanged tool outputs. The `../study/connected-study.png` master is shared with the connected study rather than duplicated here. See the [study README](../study/README.md) for extraction and identity. References beginning with `assets/` or `assets-source/` in the manifest are game-root relative; native and study references are relative to this folder.

The paired masters use a horizontal split. The crop rectangles omit the panel seam and place the major forms in view at commission size (355 × 200) and practice size (250 × 100, centered cover). For `bridge_is_out`, the full native study’s destination quadrant is `750x497+10+10`; the gameplay crop `750x391+10+63` keeps the broken elevated bridge and part of the far-bank ruins. `company_rescue` instead uses the corrected low plank crossing and moored ferry. The abandoned top panel in `river-and-square.png` remains only as a correction input; its bridge read as a pier.

The crooked watch perch, fairground pennants and paired waystones distinguish three traveler views around the same ochre frontier clearing. These are illustrative suggestions at the edge of the field, not canon changes to its terrain or indicators of how to win. In the giant ravine the figure deliberately reads as near-indistinguishable from the rock. No treasure position is pictured.

## Verification and rebuild

From this directory with Python 3 and ImageMagick 7.1.2-34 (Q16-HDRI):

```sh
python3 prepare.py
python3 prepare.py --render-to /path/to/empty/staging-directory
```

The default checks source identity and packaged texture hashes, dimensions, format, opacity and decoding. The second command builds separate textures from the packaged masters and verifies exact checksums; it does not overwrite existing textures. The recipe uses explicit pixel crops and Lanczos resampling. Image generation itself is not deterministic.

Both crops were reviewed for all twelve candidates. To reconstruct a single card-size proof from a packaged texture, use `magick INPUT.png -thumbnail '355x200^' -gravity center -extent 355x200 PROOF.png`. Replace both dimensions with `250x100` for the practice crop.
