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

Run the controlled tool checks with:

```sh
python3 games/company-of-unlikely-heroes/tools/review_guild_book.py --self-test
```
