# Necromancer: Keeper of the Bell

`necromancer-blockout.blend` is the accepted editable Necromancer hero for *Barnaby’s Order of Last Resort*. Ronald approved [Keeper of the Bell](../../concepts/necromancer/keeper-of-the-bell.png) and accepted the model after reviewing its [pose sheet](../../../../../../local/company-of-unlikely-heroes/necromancer-blockout/contact-sheet.png) and [silent action comparison](../../../../../../local/company-of-unlikely-heroes/necromancer-blockout/action-comparison.mp4). Accepted `.blend` SHA-256: `a6d8c25de84a45c1cdbc9ef9c8284f0e7bb4448e9be85a1e0be7edb664f309a8`. The skeleton and zombie are separate models; Godot integration is deferred.

Summon Skeleton sends the bell away from his chest in a high wrist ring, then holds the other hand open. Raise Dead reverses that emphasis: the bell stays close while he settles onto one knee and offers a hand low to a fallen opponent. The previews use no glow, sound, target marks, or summons.

## Play and edit

The scene opens on Ready at frame 1. In **Dope Sheet → Action Editor**, select `Necromancer_Rig` and choose a take. Set the timeline end for that take. Turn on viewport overlays to see the bones. The actions use no NLA tracks.

| Action | Keys and beats at 24 fps |
| --- | --- |
| `Necromancer \| Neutral T` | **1** matches the actual armature rest, arms horizontal. The review removes the detachable bell from this view only. |
| `Necromancer \| Ready` | **1** collected; **13** small breath; **25** ready. |
| `Necromancer \| Summon Skeleton` | **7** gathers; **13** wrist strike; **16** return stroke; **20** smaller ring; **24–27** open invitation; **43** ready; **45** close. |
| `Necromancer \| Raise Dead` | **8** tuck the bell; **18** rear toe lands; **26–41** knee down and palm-up offer (**34** review); **49** rear toe still planted; **59** heel home; **67** ready; **69** close. |

The moving takes share the first and last Ready pose. Omit the duplicate closing frame if baking a loop. The planted positions were solved and baked to half-frame FK keys. No live IK or cloth simulation is required. The knee bends through thigh/shin weights; fingers have base and tip bones, the stole and split skirt have separate cloth bones, and `clapper.R` drives the hollow bell’s hinged clapper. The rig’s `skirt_clearance` property blends an extra skirt fold into the kneel.

To remove the prop, select `Handbell_R_Detachable` in Object Mode and choose **Object → Parent → Clear and Keep Transformation**. Its pieces and clapper stay under that root. The clapper driver remains linked to the rig; mute the driver for a fully independent prop. The dress, face, trim, and procedural materials are editable native parts; no external meshes or textures are required.

## Reopen and review

From the repository root, run:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/necromancer"
out="$PWD/.lore/local/company-of-unlikely-heroes/necromancer-blockout"
blender --background "$model/necromancer-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_necromancer.py" -- "$out/renders"
blender --background "$model/necromancer-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_necromancer.py" -- "$out/motion" --render-only --motion
bash "$model/make_review_previews.sh" "$out"
```

The review script never saves the model; use `--check-only` for verification without rendering. The sheet can be made without the second Blender command if no motion directory exists. ImageMagick, Fontconfig with Noto fonts, and FFmpeg with `libx264` assemble the review files; they are not model dependencies.

- [Pose sheet with true-size 65 × 54 samples](../../../../../../local/company-of-unlikely-heroes/necromancer-blockout/contact-sheet.png)
- [Silent side-by-side action comparison](../../../../../../local/company-of-unlikely-heroes/necromancer-blockout/action-comparison.mp4)
- [Portrait](../../../../../../local/company-of-unlikely-heroes/necromancer-blockout/renders/portrait.png) and [side view of the kneel](../../../../../../local/company-of-unlikely-heroes/necromancer-blockout/renders/kneel-side.png)

## Verification and limits

The model follows the earlier cast: metres, −Y forward, +Z up, wearer’s right at −X. The Blender 5.2.2 LTS Cycles previews use the shared tactical rotation and 2.47 m orthographic scale, recentered on the hero. The T rest uses a straight-on review view. The 65 × 54 samples are direct renders without a board or stage ground.

Candidate `.blend` SHA-256: `a6d8c25de84a45c1cdbc9ef9c8284f0e7bb4448e9be85a1e0be7edb664f309a8`. The source has 47 bones and 463 editable mesh or curve objects, not counting the review floor. Rest bounds including the bell are 1.965 × 0.633 × 1.972 m (width × depth × height).

The reopened action check evaluates 275 half-frame samples. It tests the held feet, rear toe, knee, and bell attachment; the right knee’s trouser surface sits 2.81 mm above the review ground during the held offer. No intersections were found in the tested bell, face, hand, skirt, stole, and trouser pairs. At the two review poses the bell wrist is 1.559 m high at the ring and 0.869 m during the kneel; the open hand drops from 1.250 m to 0.651 m. The checks use the saved native actions, not the construction script.

The isolated renders show the difference between the high ring and the low offer. The clapper, embroidery, and facial expression are close-view details. Checks sample contact and selected surface clearances, not a full cloth or body collision simulation. There is one authored direction per take, with no target tracking or alternate facings. If Ronald accepts the model, the next useful test is an unlabeled board comparison with one empty adjacent tile and one occupied by a fallen opponent: can he read which one the Necromancer is addressing without sound or effects?
