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

### Recheck the build

From this directory, run `godot --headless --script res://tests/rules_test.gd` for ability and command rules, then `godot --headless --script res://tests/rescues_test.gd` for fixed-start rescues, deadline loss and restart. In a graphical session, `godot --script res://tests/scene_smoke.gd` opens and exercises the actual scene. Add `-- --capture=/absolute/path.png` to save the game viewport after the smoke run.
