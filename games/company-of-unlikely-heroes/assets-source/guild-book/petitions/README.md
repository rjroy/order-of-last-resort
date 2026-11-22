# Guild petition illustrations

`bard.png` shows the Bad Bard playing his fiddle. `healer_blast.png` shows the Unimpressed Healer trying Blast. Both are art-only derivatives of Ronald's approved guild-unlock screen concepts. The source PNGs are under [the game’s concept archive](../../../../../.lore/work/games/company-of-unlikely-heroes/art/concepts/guild-unlock-board/). `recipe.json` pins the native paths, source checksums, and exact `(x, y, width, height)` crop on each 1567 × 1004 original.

The crop keeps the original watercolor and warm paper at native resolution. An 11-pixel alpha feather blends only the outside of each art plate into the live page. No headings, captions, border, pin, or buttons are in the export. Godot loads the two packaged PNGs from `assets/guild-book/petitions`; it does not read the archived concept screens.

To reproduce into an empty inspection directory with Python 3 and ImageMagick 7 (prepared with 7.1.2-34):

```sh
recipe=games/company-of-unlikely-heroes/assets-source/guild-book/petitions/prepare.py
dest=.lore/local/guild-petitions/repro
python3 "$recipe" "$dest"
diff -qr -x '*.import' games/company-of-unlikely-heroes/assets/guild-book/petitions "$dest"
```

The source concepts are approved. The production crops and live page remain candidates for visual review at display size.
