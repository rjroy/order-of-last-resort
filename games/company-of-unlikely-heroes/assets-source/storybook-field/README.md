# Frontier Field native art and registration

`frontier-field-native.png` is the untouched 1567 × 1004 sRGB PNG from built-in `experimental_image_generate`, OpenAI `gpt-image-2`, job `image_2012f59640014Wr5yCxohEDcJN`, 2026-11-21. SHA-256: `dcb8affaf4cd3f3c39b688c567349d7f676ea4fc0b5e707bdb7ef8b522e73c74`.

The generation references were the [registered Frontier Field ground](../../assets/boards/frontier_field.png) (`eddc341a885ee3e3b4a0156f58096c37bf122c846d2ea7f83cc005eed63f29b7`) and the accepted Gate's live unplanned round 2 capture (`fb9fc0e74482a6c788e1a967b63c27cc95dc589e915fcd801427eadd806f77f7`). The brief asked for a golden roadside common with a quiet, uninterrupted 35-cell clearing, edge planting and a wagon road, without lettering, UI, grid, cast, or props. The historical Gate capture is not a preparation input.

From this directory, using Python 3.14.8, NumPy 2.5.4, and ImageMagick 7.1.2-34:

```sh
out=$(mktemp -d)
python register.py "$out"
cmp "$out/frontier-field-surround-rgba.png" ../../assets/storybook-field/frontier-field-surround-rgba.png
```

The recipe fits the native art to the 1280 × 820 page, feathers outside the grid, and checks the reopened texture has zero alpha across all 491,228 pixel centers within the 35-cell footprint. The second output, `registered-ground-composite.png`, is an inspection-only composite using the game board manifest. It does not ship. The regenerated surround was byte-identical to the [accepted runtime texture](../../assets/storybook-field/README.md). The recipe uses source paths relative to its installed location, never rewrites the originals, and does not rerun stochastic generation.
