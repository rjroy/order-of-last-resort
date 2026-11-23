# Graphical screen-polish captures

Run these from the repository root with Godot 4 and a working graphical display.
Both scripts render a live scene at 1280×820, write PNGs and a disposable
profile, and fail nonzero if a required state or capture is unavailable. Use
new, empty output directories; do not point them at an existing guild profile.
Run the editor import once in a fresh checkout before capture:

```sh
godot --headless --editor --path games/company-of-unlikely-heroes --import
godot --path games/company-of-unlikely-heroes \
  --script res://tools/capture_guild_book.gd -- \
  --output="$PWD/.lore/local/guild-book-review/polish-after"
godot --path games/company-of-unlikely-heroes \
  --script res://tools/capture_polish_gaps.gd -- \
  --output="$PWD/.lore/local/release-polish/after/gaps"
```

The ordinary capture's output path must be below `.lore/local/guild-book-review`;
the supplement accepts paths below `.lore/local`. Both reject symbolic-link
components. Copy the PNGs to a shared comparison directory if desired; do not
copy the disposable profiles into another run. The first ordinary board and
the long-name commission screenshot use the game's random board. Subsequent
stock outings use board seed 6; the ordinary driver also fixes its reward RNG.

## Coverage

* `capture_guild_book.gd`: creation, commissions, selected commission, empty
  recruitment, full/reordered deployment, field reports, battle entry, a
  deliberately induced defeat and return, four ordinary road debriefs with
  reward selection, played victory and return. The defeat is not ordinary
  play: the driver explicitly sets party HP to zero.
* `capture_polish_gaps.gd`: corrupt-profile recovery, invalid mission launch,
  empty-name disabled validation, long name on creation and commissions,
  empty/full recruitment, battle move targeting, staged move forecast,
  committed resolution, forfeit confirmation and result. It creates a corrupt
  disposable profile, deletes it, creates a guild, then renews its board with
  seed 6 before deployment. The long name is injected into the field; battle
  action selection emits the existing test driver's menu signal. Other
  navigation uses the existing capture driver's input helpers.

The scripts assert state transitions and PNG writes, not visual quality.
Inspect every image for clipping, missing content, and other presentation
regressions; a zero exit is not a visual approval. A missing or changed
interaction must fail rather than silently omit a capture.
