# Graphical screen-polish captures

Run these from the repository root with Godot 4 and a working graphical display.
The two scripts render live scenes at 1280×820 and fail nonzero if a required
state or capture is unavailable. Use new, empty output directories; do not
point them at an existing guild profile.
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

The full guild-book capture's output path must be below `.lore/local/guild-book-review`.
The supplement accepts paths below `.lore/local`.
Both reject symbolic-link components. Do not copy a disposable profile
into another run. Both scripts skip the Founders’ Drill after guild creation
to capture the commission board. The first full-run board and the long-name
commission screenshot use the game's random board. Subsequent stock outings
use board seed 6; the full driver also fixes its reward RNG.

## Coverage

* `capture_guild_book.gd`: creation, commissions, selected commission, empty
  recruitment, full/reordered deployment, field reports, battle entry, a
  deliberately induced defeat and return, four road victories with
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
The retired practice-only no-reward debrief is not part of commission flow.
Commission road victories with no reward continue without that page.

The scripts assert state transitions and PNG writes, not visual quality.
Inspect every image for clipping, missing content, and other presentation
regressions; a zero exit is not a visual approval. A missing or changed
interaction must fail rather than silently omit a capture.

## Build a local comparison

The builder requires these matching paths under both `before/` and `after/`
in `.lore/local/release-polish/`:

```text
ordinary/                              Full guild-book capture PNGs
gaps/                                  Supplemental capture PNGs
```

Copy the full-run PNGs from the required `guild-book-review` output directory
into `after/ordinary/`, and keep disposable profiles and catalogs out of the
comparison. If regenerating a missing baseline, use the corresponding
pre-polish revision, not the current implementation. Then run:

```sh
python3 games/company-of-unlikely-heroes/tools/build_polish_review.py \
  --output "$PWD/.lore/local/release-polish/review.html"
```

Open the resulting HTML locally. It groups all ten beads and their alternate
states, with before/after images and the exact approved concept. Images are
linked in place, never copied into runtime assets. The builder checks every
required PNG container and each approved concept's recorded SHA-256 before
writing anything. It fails if any final capture is missing or damaged, if a
concept differs, or if the output already exists. Choose a new output filename
for another run. The output must be under `.lore/local/`.

Use `--before`, `--after`, or `--concepts` to override input roots. For a
technical smoke test, mirror the baseline PNG directories into a separate
scratch `after` directory, pass that directory with `--after`, and add
`--technical-demo`. This labels the page **not a candidate**; it is not
evidence of an after-run. The approved concept describes direction, not
acceptance, and the generated page does not judge visual quality.
