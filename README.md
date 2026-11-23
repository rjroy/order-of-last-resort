# Barnaby's Order of Last Resort

Found a guild, recruit an unlikely company, and lead them through tactical
commissions. This is a Godot playtest build with provisional artwork and UI.

## Play

From this repository's root, using Godot 4.7:

```sh
godot --headless --editor --path games/company-of-unlikely-heroes --import
godot --path games/company-of-unlikely-heroes
```

The [game guide](games/company-of-unlikely-heroes/README.md) covers controls,
standalone missions, saves, content authoring and regression suites. The game
and its production tools do not require a Mind Garage checkout. The original
directory names are retained because tools, art recipes, and historical
records refer to them.

## Verify and produce assets

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_scene_test.gd
python3 games/company-of-unlikely-heroes/tools/cast/test_packing.py
python3 games/company-of-unlikely-heroes/tools/cast/verify_cast.py
```

See the [game guide](games/company-of-unlikely-heroes/README.md#recheck-the-build)
for further checks, and the [actor atlas recipe](games/company-of-unlikely-heroes/tools/cast/README.md)
for Blender, ImageMagick, and asset production requirements. Some visual checks
need a graphical session. Scratch output belongs under `.lore/local/`, which
is ignored and is not a runtime input.

## History

This repository was extracted from Mind Garage at
`64e6289821b912f394e4eaa744ae76e0ce485a3f`. It retains the game's history,
art sources, experiment records and relevant shared procedures; unrelated
games and the original issue database are not included. See
[migration notes](MIGRATION.md) for scope and provenance.
