# Guild book art review

This developer-only tool reads the packaged PNGs in `assets/guild-book`, the
authored catalog, and the presentation portrait labels. It does not copy or
approve artwork. ImageMagick 7 (`magick`) and an installed ImageMagick-listed
font are needed.

From the repository root, after packaging the artwork:

```sh
python3 games/company-of-unlikely-heroes/tools/review_guild_book.py \
  --output .lore/local/guild-book-review/overview --overview
```

Open the generated `index.md` for counts, missing or unexpected IDs, and links
to sheets grouped by type and, for upgrades, hero. Captions show both IDs and
authored names. The optional overview is a large image intended for zooming.
The output directory must be new or empty, and inside `.lore/local` or the
system temporary directory. Use a different directory for another run; generated
images are disposable and must not be committed. A coverage mismatch returns
exit status 1 but still writes the available sheets and index. Rendering errors
return status 2 and can leave a partial output directory.

For a graphical capture of the non-battle journey, use a fresh output directory:

```sh
godot --path games/company-of-unlikely-heroes --script res://tools/capture_guild_book.gd \
  -- --output="$PWD/.lore/local/guild-book-review/<new-directory>"
```

This requires a graphical renderer. The tool uses an isolated profile and plays
Village Troubles with a test driver; the commission defeat is controlled.
Captures document technical behavior and layout, not player enjoyment or
approval of the candidate artwork. For a human review, launch the game normally
and inspect the art in context as well as the generated sheets.

Run the controlled tool checks with:

```sh
python3 games/company-of-unlikely-heroes/tools/review_guild_book.py --self-test
```
