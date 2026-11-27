# Shield Wall

Accepted editable model for the Knight's deployed three-cell Shield Wall. Ronald first approved the **[petition concept](../../../../../../../games/company-of-unlikely-heroes/assets-source/guild-book/petitions/approved-2026-11-27/masters/shield-wall.png)** for modeling, then approved the model review and both board renders on 2026-11-27. Later that day, Ronald approved the column-facing comparison (SHA-256 `6106d04e19854efe51367133791063a2e27fe9e550666f86b150dec2534db6ea`): the griffon faces away from the Knight at placement. The east-facing reverse render is new; the model, row and west-facing column are unchanged.

## Source and delivery

`shield-wall.blend` is the editable master. It contains the Knight's original smoke-blue oak face, bound rim and ochre griffin, scaled for a freestanding barricade. A new carrier and two hinged, arched oak leaves have cross-ties, pintles and braced feet. No wearer or enemy shields are present. The four collections are static, not rigged for deployment. The original [Knight master](../knight/knight-guard-blockout.blend) remains separate and unchanged. The wall needs no linked libraries or external textures.

Coordinates: metres, Z up, front −Y, span +X. Ground origin is below the center of the shield. Evaluated bounds: `(-2.2300, -0.2940, 0.0040)` to `(2.2300, 0.5633, 2.0336)`; 209 meshes, 69 curves, 17 assigned materials. The model uses procedural grain and bevels. Stable consumer paths, relative to the repository root:

| Wall spans | Approved runtime sprite | PNG size | PNG ground pivot | Ground point in center tile |
| --- | --- | --- | --- | --- |
| West to east | `games/company-of-unlikely-heroes/assets/cast/props/shield-wall/row.png` | 692 × 239 | (352, 202) | (48, 62) |
| Column, Knight east, crest west | `games/company-of-unlikely-heroes/assets/cast/props/shield-wall/column.png` | 253 × 698 | (89, 413) | (40, 62) |
| Column, Knight west, crest east | `games/company-of-unlikely-heroes/assets/cast/props/shield-wall/crest-east.png` | 261 × 697 | (131, 414) | (48, 62) |

Use one sprite for the entire three-tile obstacle. For a column, select its face using the side the Knight placed it from, not a subsequent position. At board scale draw at `center cell top-left + ground point − PNG pivot / 3`, using one-third the source size. Tile steps are 96 px horizontally and 80 px vertically. The east-facing render turns the complete wall 180° relative to the camera and lights. The cross-ties and the rim of the far shield are visible, not a mirrored griffon. [registration.json](registration.json) records the exact crops, alpha bounds, pivots and draw scale.

## Read-only render recipe

Run from the repository root. This stages review and delivery images in a fresh ignored folder; it does **not** install sprites or save changes to the `.blend`. Blender 5.2.2 LTS (`d13f752e3b9c`), Cycles CPU, AgX/Medium High Contrast, 18 samples. `compose.py` uses Python 3.13.11, Pillow 12.1.0, NumPy 2.4.1 and `/usr/share/fonts/noto/{NotoSans,NotoSerif}-Regular.ttf`. Set `PYTHON` to an existing interpreter with these packages.

```sh
set -eu
m="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/shield-wall"
out=$(mktemp -d "$PWD/.lore/local/shield-wall-render.XXXXXX")
timeout 180 blender -b --disable-autoexec "$m/shield-wall.blend" -t 14 \
  --python-exit-code 1 -P "$m/render.py" -- "$out/views"
"${PYTHON:-python3}" "$m/compose.py" "$out/views" "$out/delivery"
(cd "$out/delivery" && sha256sum -c "$m/render-SHA256SUMS")
```

`build.py` records the construction recipe; it is not required to edit or render the accepted model. To rebuild a separate native file instead of modifying the accepted one:

```sh
timeout 90 blender -b --disable-autoexec "$m/../knight/knight-guard-blockout.blend" -t 10 \
  --python-exit-code 1 -P "$m/build.py" -- "$out/rebuilt.blend"
```

The builder checks the Knight master SHA-256 and refuses to overwrite an existing output. Blender serialization is not guaranteed byte-identical across builds. Two independent render runs from the accepted source produced identical decoded review, board proof and sprite pixels in the recorded environment. The review and grid proof regenerate as `review.png` and `board-size.png` respectively; the latter is the original row/west registration diagram, not an in-game capture. The same recipe also emits the approved `crest-east.png` (`13eb5f5ff47ad394392451cefc69127942ed5a3e6cf84ff62aaa8d9ca6aae48b`).

### Source identities (SHA-256)

- Accepted native model: `14c0c1ef0b9f76e7a7f7c4b576c5871583c5411a976d217133716b7dedbfbe01`.
- Original Knight master: `0bdf470f4472f2ee269337e458b605bf53be0f36f700e9ebbf8156147e10b45b`.
- Accepted petition concept: `4f28cbd0ab6d512688beb62eb971c7c18b7fd9bc2c26c6493fb2bb109499818c`.
- Exact accepted sprite and review identities: [render-SHA256SUMS](render-SHA256SUMS).
