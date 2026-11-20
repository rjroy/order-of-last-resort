# The Company of Unlikely Heroes

**Choose a company, not just a loadout.** Pick three recruits at the guild, fight a patrol, then take those same wounded heroes to rescue the last ferryman. This is a playtest build; its artwork and interface are provisional.

From the repository root, with Godot 4.7:

```sh
godot --path games/company-of-unlikely-heroes
```

### Your first outing

At the guild, pick **exactly three** recruits and arrange them in the order you want them to act. The order is fixed for the outing. The patrol fight has no round limit: defeat the opposition before it defeats your company. The second mission has a different objective: get the ferryman to the marked landing before the bridge fails. Clearing the bridge of enemies does not by itself win the rescue.

Give each hero a standing order. Each round you may queue **one** manual command instead: select a hero, action and target if needed, preview it, and read the ordered forecast. You can revise it, switch the hero you command, or clear it before committing the round. Everyone else follows their standing order. There is no full-manual or standing-only mode selector.

After winning the fight, inspect the debrief before continuing. Survivors carry their current HP forward. Downed heroes rejoin at **1 HP**; mission statuses clear. Failure ends the outing, as does a successful rescue. Return to the guild to start fresh. There are no mission upgrades, rewards or guild perks in this build.

| Hero | Offensive action | Utility |
|---|---|---|
| Knight | Push a neighboring unit or obstacle. The push hurts only on collision. | His shield covers everyone in range, even an enemy. An incoming attack reflects to the nearest enemy or obstacle. |
| Healer | A staff bonk damages an adjacent enemy or obstacle and draws an enemy’s attention. | Healing goes to the nearest eligible companion, even when someone farther away needs it more. |
| Wizard | The blast seeks the nearest thing, not the most convenient enemy. | Choose someone to pull. They land where the wizard stood; the wizard takes the recoil, including injury and knockdown. |
| Alchemist | A volatile splash hits the nearest thing, friend or foe, and can knock it down. | A ward redirects attacks. The alchemist can protect a wounded company, but cannot heal it or pull someone out of danger. |

The game collects no playtest telemetry. The question to take away: **Did you enjoy trusting two of these people while you took charge of the third?**

### Author a variation

The built-in catalog starts at `content/catalog.json`. Shared definitions, adventure content and fixed regressions are authored separately and loaded as one catalog. An adventure references an ordered mission list and an eligible roster. Its missions provide deployment slots rather than prescribing the player's heroes. Placement IDs identify individual NPCs and objects; multiple placements can use the same definition. Character fields override class defaults as whole fields. New mechanics need code; new combinations of existing handlers need only data.

### Play the checked-in regression

From the repository root, launch the permanent four-hero, two-crate variation:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=extra_knight
```

The Blast knight starts at A1, with crates at B1 and C3 and the exit at C1. The first forecast should hit the B1 crate. To run its automated real-boot regression (alongside the custom-catalog scene checks):

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/content_scene_test.gd
```

`extra_knight` and `ferryman` are **fixed regression scenarios**, not adventures in which the player is handed a predetermined company. Launch the original fixed rescue with `-- --mission=ferryman`. The `extra_knight` exit is `near_landing`; the original rescue uses `safe_bank`. Both fixtures use the same hybrid resolver as the adventure. See the [catalog guide](content/README.md) for the authoring rules.

### Recheck the build

From this directory, run the suites with `godot --headless --script res://tests/<name>.gd`:

| Suite | What it checks |
|---|---|
| `catalog_test` | Invalid definitions, independent worlds, and interaction capabilities |
| `catalog_bundle_test` | Authored parts load into one catalog; duplicate IDs and invalid deployment slots are rejected |
| `content_test` | Extra crate, alternate knight kit and habit, relocated escort destination |
| `content_scene_test` | Loading a custom catalog and the permanent extra-knight mission through the game controls |
| `rules_test` | Ability interactions and command rules |
| `rescues_test` | Fixed-start rescues, loss, and restart |
| `adventure_test` | Party selection and formation, deployment, combat and mission transitions |
| `adventure_scene_test` | Party selection and formation through the controls, debrief, wound carryover, and guild return |
| `scene_smoke` | Guild entry, battle controls, one-command forecasts, commit, and fixed-scenario restart |

In a graphical session, `godot --script res://tests/scene_smoke.gd -- --capture=/absolute/path.png` also saves the game viewport after the smoke run.

Run `godot --script res://tests/bridge_art_test.gd` from this game directory in a graphical session to check the **rendered** shore tint and exit flag. It compares the board before and after moving the objective; no reference screenshot is required.
