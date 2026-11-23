# Wagon Raider | The Last Wagon

`mind-garage-xmy.25`. The editable source is [frontier_wagon_raider-candidate.blend](frontier_wagon_raider-candidate.blend), SHA-256 `c6f8b8e6d098c21dc0f22e6cd11549b8d6ce69a8aa98d96325527aba552bce68`. Built in Blender 5.2.2 LTS against the top row of the [approved Last Wagon concept](../../concepts/non-hero-cast/08-last-wagon.png), exact SHA-256 `7f57ebb14852b0dd1a832c3783abd31d937a3d2babb1e23aac0e2ebb75a913c6`. No external textures or linked libraries. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The stock `frontier_wagon_hunt` runs the same character in two placements. He moves toward and strikes the adjacent wagon with a short tool, not a pole. The reach comes from a wide intercept step, forward-leaning bare shoulders and an angled two-handed swing at wheel height. A tied violet bandana, large leather gauntlets and a single cream knee wrap keep him apart from the high armored shoulders of the Bruiser, the Harpooner's spear, and the Goblin's small jab.

## Edit the rig

Select `WagonRaider_Rig`, then choose an action in the Action Editor. The file opens in Ready at frame 1. Metres, Z up, rig-local −Y forward, turned 11° in the cast view. The 23-bone rig has named trunk, limb, cloth and weapon controls. Separate rigid pieces make the gauntlets, straps, wraps, facing and kit editable. The `Wedge_Stave_Detachable` object groups the stave and head on `wedge_socket`. In the animated actions the hands track fixed grip points around the stave. The T bind puts arms out and leaves the tool on its separate socket.

| Native action, prefix `WagonRaider \| ` | Source frames at 24 fps | Art cue |
|---|---|---|
| Neutral T | 1 | Rig bind |
| Ready | 1–33 | Watch and settle; matching endpoints |
| Intercept | 1–29 | Lift at 10, cut off the wheel line at 14, return to guard |
| Wagon Strike | 1–32 | Low coil at 10, wheel-height impact at 16, follow-through at 20 |
| Hit | 1–21 | Short recoil at 4, returns to guard |
| Defeat | 1–37 | Gives ground, folds onto a knee and stays down |

The authoring script resolves both boot and both hand positions against fixed-length two-bone chains, then writes editable FK keys on each active frame. Actions do not require live scripts or constraints to play. Neither the intercept nor the strike changes the ground registration. Runtime owns tile travel and attack spacing and aligns strike feedback with native F16.

Reopening the saved source confirmed six native actions, 154 meshes, 24 materials and a Ready world extent of 1.042 × 0.800 × 1.721 m. Both grips stayed within 0.001 mm of their target points at every integer frame of the five played actions. At Intercept frame 10 the raised sole clears the ground by 13 cm; both soles return within 1 cm at the plant. The wedge is 33 cm off the ground at its lowest edge at strike frame 16.

To regenerate this actor's checks and poses from the repository root:

```sh
m="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
p="$m/../model-tools/wagon"
o="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/raider-review"
r="$m/frontier_wagon_raider/frontier_wagon_raider-candidate.blend"
mkdir -p "$o"
blender -b -t 4 "$r" --python-exit-code 1 -P "$p/check_models.py"
blender -b -t 4 "$r" --python-exit-code 1 -P "$p/review_models.py" -- "$o/poses" poses
blender -b -t 4 "$r" --python-exit-code 1 -P "$p/review_models.py" -- "$o/motion" motion
```

The paired Wagon and Raider composite can be regenerated after both sources are available. The model review uses the cast camera and ink renderer; it is not a Godot capture.
