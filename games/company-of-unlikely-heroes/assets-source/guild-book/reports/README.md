# Guild book field report artwork

The original 20-sketch set (2026-11-21) is pending exact player acceptance; the connected study established its visual direction. The two additional road sketches, `light_hook_pair` and `crossfire_blast_lane`, received exact artwork approval before integration and in-game appearance approval after review on 2026-11-27. See [Motifs](motifs.md) for each mission's alternate descriptions and art brief. The sketches are keyed only to the immediate disclosed mission `id` in [`commissions.json`](../../../content/expedition/commissions.json). Thirteen are transit sketches and nine cover the immediate reports authored for finales. No onward-kind or hidden-route images are supplied.

## Sources and registration

`registration.json` identifies the exact native generated source for each crop, job IDs, verified source SHA-256, crop geometry `[source, x, y, width, height]` in native pixels, and any subsequent resize or paper padding. All source PNGs are 1536 × 1024 sRGB. The source for `bridge_is_out` is the shared [connected study](../study/connected-study.png); the decoded crop matches the inspected scout plate pixel-for-pixel. Its 750 × 497 crop was the style reference for the other sheets, generated with the built-in `experimental_image_generate` (OpenAI `gpt-image-2`) on 2026-11-21. The prompts called for four isolated independent quadrants, no lettering, exaggerated shapes and uneven wax marks on cheap warm paper; they use the subjects in [Motifs](motifs.md). Native files were originally staged under `.lore/local/guild-book-review/report-staging/` and copied unchanged, then verified by SHA-256. The retained native sources, not the disposable staging copies, are used for reproduction. The `.gdignore` excludes this source directory from Godot import.

`sheet-corrections.png` replaces the initial Hookhand (ambiguous pull), ferryman (unneeded ferry placement), and troll (foot appeared inside square). Unmapped cells are not used.

The two additional standalone originals were generated using native OpenAI `image_gen` through ChatGPT-authenticated Codex CLI 0.172.0, with the packaged sheep and wagon reports as style references only. The tool did not report an image model. The originals were copied unchanged and verified by SHA-256. The approved asset hashes are `ae95581fd26176be782878c8b8a0987fe542567226dbdffc4a5624d85aec3e58` (Hook Pair) and `65695cb851e708bbef6f0b49cc5fc403814636b680d7d2390d5bf9e50ecb9497` (Crossfire). Each uses the full source and is reduced to 768 × 512. For Crossfire, the recipe mirrors 84 px of blank paper on either side and 56 px above and below before resizing, leaving the original pixels untouched inside the expanded canvas.

The game uses [prepared PNGs](../../../assets/guild-book/reports), not any locally retained review image or generator service. The prepared files are opaque 8-bit sRGB, with paper saved as color pixels and no drawn borders, labels, or controls. There is no alpha or custom color conversion at runtime. The original set was exported at source crop resolution and reviewed in the then-current contained layout. The two new assets were reviewed at 404 × 238 and 267 × 168 center-cover. The historical 20-image contact sheet was disposable inspection evidence, not approval. The [guild book review tool](../README.md) regenerates a grouped sheet from the packaged images.

## Reproduce

From this directory with Python 3.14.8 and ImageMagick 7.1.2-34:

```sh
out=$(mktemp -d)
python prepare.py "$out"
for image in "$out"/*.png; do
    cmp "$image" "../../../assets/guild-book/reports/${image##*/}" || exit 1
done
```

This reproduces crop registration and exports from retained sources, not stochastic generation.
