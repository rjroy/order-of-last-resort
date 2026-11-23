# Ordinary debrief capture

This captures the distinct **Mission cleared** page, not a reward-choice or
reward-claimed page. It plays the first `village_troubles` fixed-outing
mission using the existing forecast-based scene-test player. The tool copies
the checkout's stock catalog in memory, removes only its optional `upgrades`
section, validates it, and writes that disposable external catalog to the
output directory. The scene is launched with the supported
`--fixed-outings --content=<catalog>` options and an isolated profile path.
It does not synthesize a run, mission result, or victory.

From a checkout with Godot 4 and a working graphical display:

```sh
godot --headless --editor --path games/company-of-unlikely-heroes --import
godot --path games/company-of-unlikely-heroes \
  --script res://tools/capture_ordinary_debrief.gd -- \
  --output="$PWD/.lore/local/release-polish/after/ordinary-extra"
```

The absolute output directory must be new or empty, below `.lore/local`, and
have no symbolic-link path components. It receives the generated
`catalog-no-upgrades.json` and `ordinary-mission-cleared.png`. No previously
generated catalog or profile is needed. The player uses seed 12345, selects
Healer, Knight, and Bard, and commits real rounds. The tool requires a
committed victory, an intermediate ready phase with no reward or chosen
reward, and a visible debrief with carry report and continuation. It dismisses
the terminal replay overlay before saving the 1280×820 PNG; a zero exit checks
the captured state, not visual quality.

The baseline was produced from detached revision `dc973cf`, with this tool
overlaid into that worktree, by the same command with a fresh output directory.
It is retained at
`.lore/local/release-polish/before/ordinary-extra/ordinary-mission-cleared.png`.
The normal stock commission flow does not pause on a no-reward road victory;
this external fixed-outing case does not change or stand in for that behavior.
