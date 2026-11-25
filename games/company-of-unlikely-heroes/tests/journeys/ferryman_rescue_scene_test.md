# Ferryman stock rescue regression

From the repository root, run with a graphical Godot 4 display and a new,
empty directory for each capture command:

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/ferryman_reactions_test.gd
godot --path games/company-of-unlikely-heroes --script res://tests/journeys/ferryman_rescue_scene_test.gd -- --output="$PWD/.lore/local/ferryman-rescue-capture"
godot --path games/company-of-unlikely-heroes --script res://tests/expedition/ferryman_adventure_scene_test.gd -- --output="$PWD/.lore/local/ferryman-adventure-capture"
godot --path games/company-of-unlikely-heroes --script res://tests/presentation/ferryman_impact_geometry_scene_test.gd -- --output="$PWD/.lore/local/ferryman-impact-capture"
```

The standalone capture opens the unmodified stock rescue and commits legal UI
commands. Its victory route is Healer move `0,3`, wait, Knight move `2,1`,
Knight push crate, Wizard move `1,1`, Wizard pull Harpooner, wait, Wizard
blast, wait. Both actors are visible at opening; the capture skips placeholder
art if either actor fails to bind. It checks committed movement and the
victory event's actual subject and destination, including the terminal clip.

The commission capture copies the stock catalog to its output directory and
removes the rescue report's destination flag, making the unchanged rescue
eligible as a road mission. It finds a board seed offering that report,
creates an isolated guild, recruits Knight, Healer and Wizard, and selects the
rescue through the commission UI. It observes the retained final-action board
at normal real-time playback speed through its natural closure, without seeking
or disabling the board process. It checks that the entire safe-bank clip plays,
not just that it was queued.
The rule-emitted reaction test uses controlled positions and real potion,
Harpoon, movement and Wizard Blast resolutions. It checks flinch, lethal down,
knockdown and subsequent recovery, a Boot Toffee blocked move and Pocket
Paramedic's zero-damage knockdown. It also checks custom art identity fallback.
Neither test invents recovery from death.

The impact geometry regression stages the stock rescue through Knight move
`2,1`, Knight push crate, Wizard move `1,1`, then Knight Advance and Wizard
pull Harpooner. It compares rendered pixels against a civilian-hidden
reference at projectile flight, impact, later travel and rest. The rules
resolve the hit at C3 before the Ferryman moves to D3. The reaction regression
also covers real same-round Jelly Knees, Harpooner hit and recovery or death,
so an already-prone actor cannot replay an upright-start reaction.

Images are disposable diagnostic evidence, not runtime approval or evidence
of player enjoyment.
