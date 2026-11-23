# Guild petition illustrations

`bard.png` shows the Bad Bard playing his fiddle. `healer_blast.png` shows the Unimpressed Healer trying Blast. Both are art-only derivatives of Ronald's approved guild-unlock screen concepts. The source PNGs are under [the game’s concept archive](../../../../../.lore/work/games/company-of-unlikely-heroes/art/concepts/guild-unlock-board/). `recipe.json` pins the native paths, source checksums, and exact `(x, y, width, height)` crop on each 1567 × 1004 original.

The crop keeps the original watercolor and warm paper at native resolution. An 11-pixel alpha feather blends only the outside of each art plate into the live page. No headings, captions, border, pin, or buttons are in the export. Godot loads these two packaged PNGs and the 24 numbered plates below from `assets/guild-book/petitions`; it does not read the archived concept screens.

To reproduce into an empty inspection directory with Python 3 and ImageMagick 7 (prepared with 7.1.2-34):

```sh
recipe=games/company-of-unlikely-heroes/assets-source/guild-book/petitions/prepare.py
dest=.lore/local/guild-petitions/repro
python3 "$recipe" "$dest"
for plate in bard healer_blast; do
  cmp "games/company-of-unlikely-heroes/assets/guild-book/petitions/$plate.png" "$dest/$plate.png"
done
```

The source concepts are approved. The production crops and live page remain candidates for visual review at display size.

## Approved numbered petition plates

Ronald approved the exact 24 numbered review images, including Rescue Line, on
2026-11-22. The approved bytes are packaged under
`assets/guild-book/petitions/<id>.png`. Approval of the artwork did not itself
approve runtime integration or acceptance. The plates now appear in selected
petition previews; live visual acceptance remains separate. The two earlier
plates above were not changed.

`approved-crops.tsv` records each ID, review label, native master, exact crop,
and reviewed SHA-256. `masters.sha256` fingerprints the six preserved,
unmodified 1254 × 1254 generation outputs. Each crop is an opaque 627 × 627
native-resolution quadrant without resizing, feathering, or color conversion.
The reviewed PNGs were copied verbatim, rather than re-encoded.

All six sheets were generated on 2026-11-22 using the built-in
`experimental_image_generate`, served by `openai/gpt-image-2` after the
configured variant was unavailable, with no explicit model override. Reference
HEAD was `561aceaae5e47afebe877be30274eb7088a89d16`; the petition catalog
was read from the working tree. The existing Bard and Healer Blast plates
were style references, followed by class portraits:

| Master | Job ID | Class portrait inputs, in order |
|---|---|---|
| `founders-a.png` | `image_205695a7a001AFu5sdkKmVT1Tv` | Knight, Healer |
| `founders-b.png` | `image_205699950001dUU5UWvjje6crl` | Healer, Wizard, Rogue |
| `minstrels-a.png` | `image_205694da4001z09u27AIutr5xN` | Bard, Knight, Dodger |
| `minstrels-b.png` | `image_205694db5001T4pgUsewVVmvLQ` | Dodger, Healer, Mixologist, Knight |
| `necromancer.png` | `image_20569464d001oMspVdQCT7bWHJ` | Necromancer, Knight |
| `mixologist.png` | `image_2056986c3001Q8V0xPoNIAgnaV` | Mixologist, Wizard |

For example, from this directory, reproduce the first quadrant with
ImageMagick 7.1.2-34:

```sh
magick masters/founders-a.png -crop 627x627+0+0 +repage /tmp/opencode/knight_rescue_line.png
```

Use the master and crop columns for the other plates. Encoding may affect PNG
byte hashes; compare decoded pixels to the packaged image if a re-encoded crop
differs. Verify preserved masters with `sha256sum -c masters.sha256` and compare
packaged PNG hashes with `review_sha256` in the mapping.
