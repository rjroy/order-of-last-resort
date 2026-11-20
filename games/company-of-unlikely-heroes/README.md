# The Company of Unlikely Heroes

**Get the last ferryman onto the safe bank before the bridge fails.** You do not need to clear the bridge of enemies.

From the repository root, with Godot 4.7:

```sh
godot --path games/company-of-unlikely-heroes
```

### Your first round

Start in **Hybrid**. Use the three dropdowns beneath the bridge to set standing orders. In **Direct command**, choose a hero, action and (when needed) target, then click **Preview command** to queue it. Read **Round forecast** from the top down: earlier actions can change what later heroes will hit. You can replace or clear a command before clicking **Commit round**. The remaining heroes follow their standing orders.

Use **Direct** to command all three heroes, or **Standing** to let the three carry out their orders. Changing modes starts the same rescue from the beginning. **Restart** gives you a fresh attempt in the current mode.

| Hero | Offensive action | Utility |
|---|---|---|
| Knight | Push a neighboring unit or obstacle. The push hurts only on collision. | His shield covers everyone in range, even an enemy. An incoming attack reflects to the nearest enemy or obstacle. |
| Healer | A staff bonk damages an adjacent enemy or obstacle and draws an enemy’s attention. | Healing goes to the nearest eligible companion, even when someone farther away needs it more. |
| Wizard | The blast seeks the nearest thing, not the most convenient enemy. | Choose someone to pull. They land where the wizard stood; the wizard takes the recoil, including injury and knockdown. |

The game collects no playtest telemetry. The question to take away: **Did you enjoy trusting two of these people while you took charge of the third?**

### Author a variation

The default full catalog is `content/ferryman.json`. Missions refer to encounters, encounters place character and object definitions on boards, and boards name locations. Placement IDs identify individual instances; multiple placements can use the same definition. Character fields override class defaults as whole fields, so an overridden ability list or habits map replaces the class's list or map. Existing ability, behavior, objective and status handlers are implemented in code; JSON selects and configures them rather than defining new mechanics.

### Play the checked-in regression

From the repository root, launch the permanent four-hero, two-crate variation:

```sh
godot --path games/company-of-unlikely-heroes -- --mission=extra_knight
```

The Blast knight starts at A1, with crates at B1 and C3 and the exit at C1. The first forecast should hit the B1 crate. To run its automated real-boot regression (alongside the custom-catalog scene checks):

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/content_scene_test.gd
```

The `extra_knight` mission and its separate encounter in `content/ferryman.json` are a permanent example to copy when authoring variations. Its `objective.destination` names `near_landing` on the shared board; the default mission still uses `safe_bank`. Behaviors referenced by habits must use abilities available to that character, and `default_order` must be in its habits. Unit turns follow unit placement order. For equal-distance nearest-target ties involving both units and objects, eligible units come first, then objects; placement order breaks ties within each category. Keep placements distinct and on passable tiles. See [the catalog guide](content/README.md) for details.

### Recheck the build

From this directory, run the suites with `godot --headless --script res://tests/<name>.gd`:

| Suite | What it checks |
|---|---|
| `catalog_test` | Invalid definitions, independent worlds, and interaction capabilities |
| `content_test` | Extra crate, alternate knight kit and habit, relocated escort destination |
| `content_scene_test` | Loading a custom catalog and the permanent extra-knight mission through the game controls |
| `rules_test` | Ability interactions and command rules |
| `rescues_test` | Fixed-start rescues, loss, and restart |
| `scene_smoke` | Mode selection, chained commands, forecasts, commit, and restart |

In a graphical session, `godot --script res://tests/scene_smoke.gd -- --capture=/absolute/path.png` also saves the game viewport after the smoke run.

Run `godot --script res://tests/bridge_art_test.gd` from this game directory in a graphical session to check the **rendered** shore tint and exit flag. It compares the board before and after moving the objective; no reference screenshot is required.
