# Guild book field report artwork

The original 20-sketch set (2026-11-21) is pending exact player acceptance; the connected study established its visual direction. The two additional road sketches, `light_hook_pair` and `crossfire_blast_lane`, received exact artwork approval before integration and in-game appearance approval after review on 2026-11-27. The two tier-five variant sketches and the 13 sketches for formerly standalone roads received exact artwork approval on 2026-11-27; in-game appearance review is separate. See [Motifs](motifs.md) for the art briefs. There are 28 transit plates and nine finale plates. Each sketch shows the immediate mission in [`commissions.json`](../../../content/expedition/commissions.json), never the onward kind or hidden route. Veteran Borrowed Armor uses the Borrowed Armor plate because it shares the same encounter and the motif still applies.

## Sources and registration

`registration.json` identifies the exact native generated source for each crop, job IDs, verified source SHA-256, crop geometry `[source, x, y, width, height]` in native pixels, and any subsequent resize or paper padding. All source PNGs are 1536 × 1024 sRGB. The source for `bridge_is_out` is the shared [connected study](../study/connected-study.png); the decoded crop matches the inspected scout plate pixel-for-pixel. Its 750 × 497 crop was the style reference for the other sheets, generated with the built-in `experimental_image_generate` (OpenAI `gpt-image-2`) on 2026-11-21. The prompts called for four isolated independent quadrants, no lettering, exaggerated shapes and uneven wax marks on cheap warm paper; they use the subjects in [Motifs](motifs.md). Native files were originally staged under `.lore/local/guild-book-review/report-staging/` and copied unchanged, then verified by SHA-256. The retained native sources, not the disposable staging copies, are used for reproduction. The `.gdignore` excludes this source directory from Godot import.

`sheet-corrections.png` replaces the initial Hookhand (ambiguous pull), ferryman (unneeded ferry placement), and troll (foot appeared inside square). Unmapped cells are not used.

The two additional standalone originals were generated using native OpenAI `image_gen` through ChatGPT-authenticated Codex CLI 0.172.0, with the packaged sheep and wagon reports as style references only. The tool did not report an image model. The originals were copied unchanged and verified by SHA-256. The approved asset hashes are `ae95581fd26176be782878c8b8a0987fe542567226dbdffc4a5624d85aec3e58` (Hook Pair) and `65695cb851e708bbef6f0b49cc5fc403814636b680d7d2390d5bf9e50ecb9497` (Crossfire). Each uses the full source and is reduced to 768 × 512. For Crossfire, the recipe mirrors 84 px of blank paper on either side and 56 px above and below before resizing, leaving the original pixels untouched inside the expanded canvas.

The game uses [prepared PNGs](../../../assets/guild-book/reports), not any locally retained review image or generator service. The prepared files are opaque 8-bit sRGB, with paper saved as color pixels and no drawn borders, labels, or controls. There is no alpha or custom color conversion at runtime. The original set was exported at source crop resolution and reviewed in the then-current contained layout. The later road assets were inspected at 404 × 238 and 267 × 168 center-cover before integration. The historical 20-image contact sheet was disposable inspection evidence, not approval. The [guild book review tool](../README.md) regenerates a grouped sheet from the packaged images.

### Tier-five variant approval and provenance

Both variants were generated in independent native OpenAI `image_gen` jobs via ChatGPT-authenticated Codex CLI 0.172.0. The image model wasn't reported. The accepted `light_hook_pair-native.png` and `crossfire_blast_lane-native.png` were supplied for style only. The retained sources are byte-identical to the generated originals. Before reducing each full canvas to 768 × 512, Split Fuse mirrors 48 px of blank paper on each side and 32 px above and below; Crossed Spears needs no padding.

On 2026-11-27, the player replied “approve” to the exact two candidates shown in the 404 × 238 contact sheet (SHA-256 `3c62af7ad7a538b47b7bf46a12c7e25120a3d3a559038953e2521b4979ccbd2b`). This approves those two sketches only. Each delivered file matches its approved candidate byte-for-byte; approved candidate and delivery therefore share the same SHA-256. At promotion, the stock recipe reproduced both files and all 22 prior plates byte-for-byte. In-game appearance is not yet accepted.

| Exact mission ID | Retained native SHA-256 | Approved candidate and delivered PNG SHA-256 |
|---|---|---|
| `crossfire_split_fuse` | `9351082ad8b1dc4956f627637db137672498c49fa5dd4aaa5de6c51d9131db40` | `aa3cd31cea300f012f17b2a8b89c60eb71fb51806d2611089af04cee152a46a3` |
| `very_long_spear_crossed_spears` | `a37f095d068842de36ebf21f94cfc767f2c2e0adef005cbff5b25a5d846bff20` | `efb9e3ed40f58325c88dc8f557260eed796e156419237f2377ffa62ae0132f6a` |

### Formerly standalone road approval and provenance

The player replied “just wite them up” on 2026-11-27 to the exact approval question for these 13 plates, shown in `.lore/local/guild-book-review/report-staging/standalone-road.ogMWSo/candidate/contact-404x238.png` (SHA-256 `69f731f657353ae08629cc3fb965243a07a82cf1b56e3eeab1f327e9a0ec4b54`). The prepared files below are byte-identical to the approved candidates. Their in-game appearance review is pending.

The four retained `road-standalone-sheet-*.png` originals were generated on 2026-11-27 in four native OpenAI `image_gen` jobs through ChatGPT-authenticated Codex CLI 0.172.0. The image model was not reported. Each job used the existing sheep, wagon and Odd Couple book sketches for paper and crayon style only. Native files were copied unchanged; their job IDs, SHA-256 hashes, quadrant crops and resizing instructions are in `registration.json`. The staging handoff retains the original tool output locations and prompts. Where a tight crop needs more paper, `paper_edge_period` limits mirroring to the outer ten pixels so it does not repeat crayon marks. The result is then reduced to 768 × 512. The recipe reproduced all 37 packaged plates and all prior plates were unchanged.

| Exact mission ID | Approved candidate and delivered PNG SHA-256 |
|---|---|
| `big_windup` | `5e6d60a0e56009344560fd62304655b34b00122718975951d3920f5f06bcbcac` |
| `big_windup_t3` | `9a4effff3ff180dcb8e5ce295f7308c925a89b273cc5f9bf96aa1ea4cfd842e0` |
| `big_windup_t4` | `afd306fb5aac984aeccb33ecce7ddf5bb1bda8f1f624d3381162ea0a55e6f396` |
| `big_windup_t5` | `53c3aca9b6408799e6f502ec5e45c77d76404ba0e931d844329772f4a38ec501` |
| `borrowed_armor` | `b3d52224186ad10b2e9ca146435473f56e8cbeb8a15a92518eeda25d54e079e0` |
| `empty_helmets` | `1617335f3c736effe4045c14371fd95c43d68e25ee59e6b38e8f4d415ec3d615` |
| `friars_last_favor` | `b4bbdeae54f19e3d67c4766be5110aced37189bfbe1fd0a7ec7f178f19bae15d` |
| `hired_hammer` | `b4fbf218809d2c4b7bb193c43619233e9c1e6117ce244613b35420ea7c03873c` |
| `last_crate_on_the_road` | `bd224f66435bcf3262b7b2025ad8a0b06a233fe6267564ddef75cbf648bbce07` |
| `longbows_blind_spot` | `d68bd8338bda7bc197f9eb7ab6781d8e713e8993e70438d1b1c8dcb8232e6803` |
| `no_room_to_swing` | `4e45ce21c06071519f6a4e4ba15ea6124eb5654a717ecdfa8545ce264c959fa3` |
| `very_long_spear` | `77564ef631afe3fefac85f6606f59ac89d25810f1edc75b057862726b98352c7` |
| `wrong_twin` | `4c3add1fb7d342f36d4cd255a87bd579c09cfcb40f8b864537bd01012e117775` |

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
