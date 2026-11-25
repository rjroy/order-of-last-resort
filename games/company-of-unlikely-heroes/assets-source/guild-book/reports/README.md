# Guild book field report artwork

Candidate set, 2026-11-21. The connected study established the visual direction; the complete 20-sketch set is pending exact player acceptance. See [Motifs](motifs.md) for each mission's two alternate descriptions and art brief. The sketches are keyed only to the immediate disclosed mission `id` in [`commissions.json`](../../../content/expedition/commissions.json). Eleven are transit sketches and nine cover the immediate reports authored for finales. No onward-kind or hidden-route images are supplied.

## Sources and registration

`registration.json` identifies the exact native generated source for each crop, job IDs, verified source SHA-256, and crop geometry `[source, x, y, width, height]` in native pixels. All source PNGs are 1536 × 1024 sRGB. The source for `bridge_is_out` is the shared [connected study](../study/connected-study.png); the decoded crop matches the inspected scout plate pixel-for-pixel. Its 750 × 497 crop was the style reference for the other sheets, generated with the built-in `experimental_image_generate` (OpenAI `gpt-image-2`) on 2026-11-21. The prompts called for four isolated independent quadrants, no lettering, exaggerated shapes and uneven wax marks on cheap warm paper; they use the subjects in [Motifs](motifs.md). Native files were originally staged under `.lore/local/guild-book-review/report-staging/` and copied unchanged, then verified by SHA-256. The retained sources in this directory, not the disposable staging copies, are used for reproduction. The `.gdignore` excludes these sheets from Godot import.

`sheet-corrections.png` replaces the initial Hookhand (ambiguous pull), ferryman (unneeded ferry placement), and troll (foot appeared inside square). Unmapped cells are not used.

The game uses [prepared PNGs](../../../assets/guild-book/reports), not any locally retained review image or generator service. The prepared files are opaque 8-bit sRGB, with paper saved as color pixels and no drawn borders, labels, or controls. There is no alpha or custom color conversion at runtime. The files are exported at source crop resolution and were inspected contained in 510 × 212 at 1280 × 820 (roughly 318 × 212 actual art). The historical 20-image contact sheet was disposable inspection evidence, not approval. The [guild book review tool](../README.md) regenerates a grouped sheet from the packaged images.

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
