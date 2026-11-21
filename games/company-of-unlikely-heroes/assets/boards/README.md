# Barnaby's Order: mission board paintings

These thirteen PNGs are the exact approved artwork: twelve new paintings and the unchanged Ferryman crossing pilot. They are both the native masters and the packaged color textures. There are no postprocessed copies, preview images, or image-generation inputs in this package. Artwork approval is separate from acceptance in the running game.

## Runtime and test contract

- Manifest: `res://assets/boards/manifest.json`, schema version `1`. `boards` is keyed by built-in board ID. Each entry's `file` is a PNG basename relative to the manifest. Tests can use `sha256`, `bytes`, `pixels`, and `board_dimensions` to check the package. `missions` records catalog coverage at approval; it is not the source of gameplay rules.
- Every PNG is full-bleed, opaque, 1536 × 1024, 8-bit sRGB. Sample as ordinary sRGB color artwork. All thirteen cover an authored 7 × 5 board.
- Select these plates only for matching built-in content. An unknown board, a custom catalog, or an unavailable plate should retain the procedural board. A reused ID or matching dimensions alone are not sufficient.
- Source coordinates start at the upper left. `registration.a1_center_px`, `column_px`, and `row_px` are source-space vectors `O`, `C`, and `R`. For zero-based cell coordinates `(c, r)`, its center is `O + c*C + r*R`; its corners are at `(c ± 0.5, r ± 0.5)`. The common fit is `(272,176) + c*(184,18) + r*(-28,146)`; the pressure gate is `(272,175) + c*(184,18) + r*(-35,146)`.
- The rectangular renderer uses 96 × 80 cells and a `(31,34)` gutter. In that renderer's unscaled map coordinates, sample the plate at `O + ((x - 31) / 96 - 0.5)*C + ((y - 34) / 80 - 0.5)*R`. Fit and center the map, art and grid together. Do not change hit cells or the cast foot anchor `(49,62)` to follow image details, and do not simply stretch the full image to the control.
- Render quiet dark outlines for all tiles over the ground and under the cast. Keep spans, props, figures, gate state, objectives, selection and threat marks separate. The Ferryman PNG contains no D3 deck; the new gorge contains no B2–F4 deck. The open gate threshold at D3 is permanent ground; the barrier is not painted. A dark grid stroke over deep water may need a separate, stronger nonpassable cue.
- A source checkout can decode these PNGs using `Image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))`, or use the imported textures where available. Any future Godot export must include this JSON manifest and all thirteen PNG textures, even when looked up by path instead of scene reference.

## Provenance and visual caveats

Catalog reference: `1f30963`, `games/company-of-unlikely-heroes/content/catalog.json` and its component files. Twelve masters were created on 2026-11-21 with OpenCode's built-in `experimental_image_generate` tool, reported model `openai/gpt-image-2`, and accepted together in the mission-board review. They use the archived [Ferryman crossing pilot](../../../../.lore/work/games/company-of-unlikely-heroes/art/pilots/ferryman-crossing/REVIEW.md) for camera, ink and watercolor. The runtime copy `bridge.png` is byte-identical to that approved pilot original. Both the pressure gate and the wide gorge also used layout guides derived from the catalog. Their checksums in the manifest identify those generation inputs for provenance; the packaged PNGs already contain all the artwork needed to render. Regeneration is not deterministic.

The pressure gate's painted cut has irregular lips. Check the D3 crossing in both states, and the edge of A1, at minimum play size. The new gorge exposes clear water when C2–C4 and E2–E4 lose their decks in the static review. The eastern lip nonetheless reaches into the always-nonpassable F5 margin. Check that F5 reads as a gap and that the bank-to-deck joins hold in Godot before accepting the running presentation. Any necessary local fit should leave the approved PNG unchanged. For the sheep pasture, keep the pen outline distinct against green.

The manifest and images are self-contained for loading. The historical pilot link above is documentation only. The package includes no dependencies on generated previews, reference guides, local staging, or Godot's import cache.

Verify from this directory with ImageMagick and Python 3:

```sh
python3 - <<'PY'
import hashlib
import json
import pathlib
import subprocess

here = pathlib.Path.cwd()
manifest = json.loads((here / "manifest.json").read_text())
assert manifest["version"] == 1
assert len(manifest["boards"]) == 13
for board_id, board in manifest["boards"].items():
    assert board["file"] == f"{board_id}.png"
    path = here / board["file"]
    payload = path.read_bytes()
    assert len(payload) == board["bytes"]
    assert hashlib.sha256(payload).hexdigest() == board["sha256"]
    properties = subprocess.check_output(
        ["magick", "identify", "-format", "%m %wx%h %[colorspace] %z %[opaque]", str(path)],
        text=True,
    )
    assert properties == "PNG 1536x1024 sRGB 8 True"
    subprocess.run(["magick", str(path), "null:"], check=True)
print("13 exact board masters decoded and verified")
PY
```
