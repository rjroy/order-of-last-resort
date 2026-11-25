# Harpooner stock rescue regression

From the repository root, with a graphical Godot 4 display and a **new, empty**
output directory:

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/harpooner_binding_test.gd
godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/harpooner_body_double_test.gd
godot --path games/company-of-unlikely-heroes --script res://tests/presentation/harpooner_corpse_playback_test.gd
godot --path games/company-of-unlikely-heroes --script res://tests/presentation/harpooner_projectile_tip_test.gd
godot --path games/company-of-unlikely-heroes --script res://tests/journeys/harpooner_rescue_scene_test.gd -- --output="$PWD/.lore/local/harpooner-rescue-capture"
```

The capture driver launches the normal main battle scene with the unmodified
`company_rescue` catalog and the stock Knight, Healer and Wizard. It restarts
the same opening for each sequence, stages legal commands through the battle
interface, commits each forecast, and advances the actual board playback.
Screenshots and any profile path stay in the specified disposable directory.
The Ferryman and Harpooner both use their authored cast identities. The visual
fallback comparison changes only the Harpooner; it leaves the Ferryman and
board state intact.

* Close: Knight move `2,1`; Wizard move `1,1`; Wizard Pull Harpooner;
  Knight Push Harpooner. The third round attacks the Ferryman at distance one.
* Pursue: Knight move `2,1`; Knight Push crate. The second round moves the Harpooner.
* Ranged and defeat: Wizard move `0,0`; Wizard move `1,0`; Wizard Pull
  Harpooner; Knight Push Harpooner three times. The third round attacks the
  Ferryman at distance two, reflected by the Knight's guard; the next two
  pushes hit, and the last defeats the Harpooner.

The `ready`, action, flight and rest images show the normal board, not a
separate sprite viewer. A successful test checks action-time geometry, clip
binding, the detached projectile, playback completion and the visual
difference from the old fallback. These are deterministic presentation checks,
not approval of the runtime appearance or evidence of player enjoyment.
The projectile tip registration belongs to the approved F11 detached prop and
is preserved by the cast packing recipe. The projectile regression checks that
its root starts at the hand and its tip, not the root, reaches the target.
