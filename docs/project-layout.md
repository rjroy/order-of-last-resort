# Project layout

This repository is the standalone extraction of Barnaby's Order of Last Resort.
Paths are preserved because recipes, Godot resources, and regression tools refer
to them. The Godot project root remains
[`games/company-of-unlikely-heroes/`](../games/company-of-unlikely-heroes/);
`main.tscn` and `main.gd` intentionally remain at that root.

## Repository map

| Path | Purpose |
|---|---|
| `AGENTS.md` | Repository working agreements and links to the game guide and focused runbooks. |
| `MIGRATION.md`, `migration-commit-map.txt` | Extraction history and mapping from historical source commits. These are provenance, not a live tracker or runtime input. |
| `docs/` | Maintained project and workflow documentation. [`adding-a-playable-class.md`](adding-a-playable-class.md) is the end-to-end recruitable-hero runbook; use it rather than duplicating its detailed design, integration, approval, and verification procedure. |
| `.agents/` | Project-local agent skills and helper instructions. These guide work but are not game runtime resources. |
| `.beads/` | Repository-local issue-tracker data when present; unlike historical issue IDs in `.lore/`, this is operational tracker state. |
| `.git/` | Git's repository metadata and object database; do not edit it as project content. |
| `.lore/` | Durable research, production sources, provenance and historical records; see below. |
| `games/company-of-unlikely-heroes/` | The Godot game project, source, content, packaged assets, tests and production tools. |

### Game project

The following directories are the current organization for game code and data.
Keep the project entry scene and script at the project root. Root-level source
files that have already moved into these directories are not supported aliases;
use the current paths below.

| Path | Purpose |
|---|---|
| `rules/` | Turn resolution, action handlers, behavior/standing-order logic, and rule-level state. Keep game rules out of presentation code. |
| `guild/` | Guild profile, recruitment, purchases, progression, and loadout lifecycle. |
| `expedition/` | Commission and multi-mission run lifecycle, rewards, and persistence between missions. |
| `presentation/battle/` | Battle board, controls, forecast, and battle-facing interaction. |
| `presentation/cast/` | Character animation/cast lookup, cues, and playback. |
| `presentation/book/` | Guild book and commission/recruitment presentation. |
| `presentation/audio/` | Audio routing and sound playback. |
| `presentation/help/` | In-game help and instruction presentation. |
| `presentation/settings/` | User-facing options and settings presentation. |
| `content/heroes/` | Hero and character definitions, including their kits and orders. |
| `content/missions/` | Individual authored mission definitions. |
| `content/shared/` | Shared encounter and common content definitions. |
| `content/guild/` | Guild progression and training catalog data. |
| `content/expedition/` | Commission and expedition reward catalog data. |
| `content/practice/` | Practice/tutorial content, distinct from commission missions. |
| `tests/content/` | Catalog and authored-content contract checks. |
| `tests/battle/` | Battle rules and battle-scene regression checks. |
| `tests/expedition/` | Commission and multi-mission lifecycle checks. |
| `tests/guild/` | Guild profile, purchase, and loadout checks. |
| `tests/presentation/` | UI and presentation behavior checks. |
| `tests/journeys/` | Cross-screen and end-to-end player journey checks. |
| `tests/fixtures/` | Test-only fixture content; never silently substitute it for shipped content. |
| `tests/support/` | Shared test helpers and controlled scene drivers. |
| `tools/` | Authoring, baking, capture, and verification utilities. Tools may be active, archival, or evidence-specific; read their local README or command comments before running. |
| `assets/` | Packaged runtime assets and their import metadata. Some source/native assets are intentionally kept here for historical compatibility; do not assume everything here is disposable output. |
| `assets-source/` | Native source art, sound sources, recipes and provenance used to produce or review packaged assets. Accepted source and its provenance belong in source control. |

Some retained tools and test helpers do not fit the broad runtime layout (for
example, the cast-specific tool suite remains under `tools/cast/`, while its
recipe files are organized in `tools/cast/actors/`). Treat these as intentional
specialized placements, not evidence that the runtime source tree still uses
its former flat layout. Preserve established paths and sidecars unless an
approved task specifically changes them.

Godot `.uid` files are resource-ID sidecars for their matching scripts or
shaders: track them with the source and move/rename them together. Do not commit
the generated `.godot/` import cache. Imported asset metadata such as `.import`
files may be tracked intentionally; retain it with its packaged asset.

## Where a real change goes

For a stock hero, follow the complete procedure in
[`Adding a playable class`](adding-a-playable-class.md). In brief, the Hobby
Smith's shipped definition is
[`content/heroes/blacksmith.json`](../games/company-of-unlikely-heroes/content/heroes/blacksmith.json);
his default offense/utility kit and recruitment petition are in
[`content/guild/progression.json`](../games/company-of-unlikely-heroes/content/guild/progression.json),
his recruitment-roster entry is in
[`content/expedition/commissions.json`](../games/company-of-unlikely-heroes/content/expedition/commissions.json)
and outing reward definitions (when applicable) are in
[`content/expedition/rewards.json`](../games/company-of-unlikely-heroes/content/expedition/rewards.json).
His cast recipe is
[`tools/cast/actors/blacksmith.json`](../games/company-of-unlikely-heroes/tools/cast/actors/blacksmith.json);
the packaged atlas is in `assets/cast/`. When adding a stock hero, add its hero
definition file to the `parts` array in
[`content/catalog.json`](../games/company-of-unlikely-heroes/content/catalog.json)
using a path relative to `content/`; otherwise the default stock catalog will
not load it. Registration alone does not make a recruit available: add the
appropriate recruitment and roster data as described in the class runbook. The
separate `content/practice/catalog.json` is intentionally narrow: register
content there only if the practice catalog specifically needs it. Runtime cast
and sound integration lives in `presentation/cast/` and `presentation/audio/`.
Tests are now grouped under the applicable `tests/` subdirectory, with shared
helpers in `tests/support/`; use test-owned fixtures for algorithm checks. Do
not treat a candidate illustration, cleanup, or unreviewed render as approved
art.

For a stock mission, the authored definition belongs in
[`content/missions/`](../games/company-of-unlikely-heroes/content/missions/);
for example, [`wrong_side_of_the_door.json`](../games/company-of-unlikely-heroes/content/missions/wrong_side_of_the_door.json).
Add every new stock mission file's relative path to the `parts` array in
[`content/catalog.json`](../games/company-of-unlikely-heroes/content/catalog.json);
the stock manifest resolves each entry relative to `content/`. In this example,
the mission file itself defines the `frontier_gate` encounter and
`frontier_gate_board`, including its `gate_guard` goblin placement and named
plate, gate, and exit locations; none of those records come from
`content/shared/encounters.json`. Put definitions in `content/shared/` only
when they are genuinely shared by multiple content entries. The separate
`content/practice/catalog.json` is a deliberately narrower, curated catalog,
not a minimal list: it assembles 14 missions (including its own practice
encounter) and selected shared and hero definitions. Update it only when the
practice catalog should include the new content. Add tests under
`tests/content/` for catalog contracts and
`tests/battle/` for rule behavior as appropriate. Use owned fixture inputs for
algorithm tests and live authored data for catalog/launch integration checks.
The game guide's
[standalone mission section](../games/company-of-unlikely-heroes/README.md#launch-a-standalone-mission)
documents live launch commands and current examples.

Keep authored behavior and presentation separate: rules determine outcomes;
presentation displays committed outcomes. Tests should own their inputs for
algorithmic assertions rather than depend on mutable production balance values.
Record source origins, licenses/terms, review state, and reproduction steps for
assets and evidence. A render or candidate review is not approval to ship.

## `.lore/`: production, research, and history

`.lore/` has distinct durable and disposable roles:

| Path | Intent |
|---|---|
| `.lore/work/games/company-of-unlikely-heroes/` | Game-specific experiment records, decisions, plans, verification records, artwork/model work, claims, and approvals. Historical artifacts can mention old Mind Garage issue IDs; those do not make them live issues. Preserve their provenance and distinguish proposals from accepted work. |
| `.lore/work/shared/` | Research shared across projects. Useful context, not authorization to implement a feature. |
| `.lore/work/` historical pilots | Retired or exploratory pilot work remains historical evidence, not necessarily a current feature or active process. Check status and current implementation before relying on it. |
| `.lore/reference/` | Maintained descriptions of system understanding; verify claims against current source when correctness matters. |
| `.lore/learned/` | Operational learnings from prior work, useful for avoiding repeated failures. |
| `.lore/local/` | Ignored scratch: generated captures, logs, temporary review media, and disposable task evidence. Never make it a required runtime input or commit it as accepted source. |

Accepted native models, artwork, recipes and provenance are source-controlled
production material, even when they are not runtime assets. Conversely, a
generated capture or scratch output is evidence only. Preserve accepted
originals; do not replace them with candidates or cleanup output.

## Commands: live versus archived

The live player and standalone commands are in the
[game guide](../games/company-of-unlikely-heroes/README.md): import with
`godot --headless --editor --path games/company-of-unlikely-heroes --import`,
then launch with `godot --path games/company-of-unlikely-heroes` (or the
documented `--mission` options). The class runbook contains representative
current validation commands. Treat scripts in `tools/` as specialized
authoring, capture, or verification commands, and consult their own
documentation first.

Commands preserved in historical pilots, experiment records, capture logs, or
old notes may refer to former layouts, dependencies, or environments. They are
archival unless a current maintained guide or tool README confirms them; do not
run them blindly or describe them as the standard way to play.
