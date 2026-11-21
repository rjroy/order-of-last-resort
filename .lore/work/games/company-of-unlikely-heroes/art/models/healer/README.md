# Healer field-medic blockout

`healer-blockout.blend` is an editable Blender 5.2.2 LTS candidate for *Barnaby’s Order of Last Resort*. Ronald approved the [field-medic study](../../concepts/healer/field-medic-gameplay-study.png) for this blockout on 2026-11-21. The study sets the tone and identifies the working kit: a heavy offset satchel, crooked wooden staff, tied hair, an open field coat and wrapped arms. The 3D gestures are new. In particular, Bonk is a short downward knock with the blunt crook at an adjacent character’s head height, not the horizontal shove suggested by the concept.

## Pose, replay and edit

Ronald accepted this model blockout after reviewing the [pose sheet](../../../../../../local/company-of-unlikely-heroes/healer-blockout/contact-sheet.png) and three-action preview on 2026-11-21. Accepted `.blend` SHA-256: `3a0b8427c788a26b511a6f6262c6debeb3fbcea78fa2c44fd867b32e5010aaa5`. This is model acceptance, not a Godot integration or board-rendering decision.

The file opens on the common ready pose, frame 1, with `Camera_Tactical_3Q` active. Select `Healer_Rig`, switch an editor to **Dope Sheet → Action Editor**, and choose one action from its dropdown. Reset to frame 1 and play. The actions are separately saved at 24 fps; no NLA strip or external file is required.

| Action | Frames |
| --- | --- |
| `Healer \| Neutral T` | **1** matches actual armature rest. Hide `06 • Staff (detach at root)` for a clean turnaround. |
| `Healer \| Ally Heal` | **1** ready; **12–17** hand reaches outward and opens; **28** ready again; **32** end. |
| `Healer \| Self Heal` | **1** ready; **12–17** hand folds inward at the chest and the head follows; **28** ready again; **32** end. |
| `Healer \| Adjacent Bonk` | **1** ready; **10–11** raise and aim; **15** downward contact; **18** rebound; **29** ready again; **32** end. |

Turn on viewport overlays, then use Pose Mode. `Body and cloth` contains the root, pelvis, torso, head, satchel and split coat panels. `Arms and legs` includes shoulders, limb segments and boots. Reveal the `Fingers` bone collection to adjust the palms and grip. The `Attachment` collection contains `staff_mount.R`, a child of `hand.R`. In Object Mode select `Staff_R_Detachable` and choose **Clear Parent and Keep Transformation** to remove the whole staff. To reattach without guessing the grip offset, undo the detach or restore the original bone-parented Empty. Do not unparent its parts one by one.

The model follows the [Knight](../knight/README.md): metres, −Y forward, +Z up, and the wearer’s right at −X. The orthographic tactical camera uses the Knight’s rotation and 2.47 m scale, recentered for this actor and the crook arc. Without the staff, the neutral model is about 1.793 m wide × 0.523 m deep × 2.001 m high, including the hair knot.

## Reopen and inspect

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/healer"
out="$PWD/.lore/local/company-of-unlikely-heroes/healer-blockout"
blender --background "$model/healer-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_healer.py" -- "$out/renders" --motion --diagnostic
bash "$model/make_review_previews.sh" "$out"
```

Pass `--check-only` after Blender’s `--` for a read-only check without renders. The preview script uses ImageMagick, Fontconfig and FFmpeg with animated WebP support. They are not model dependencies. It produces `contact-sheet.png`, `three-beats.webp`, and `head-height-diagnostic.png`. Only the diagnostic includes a wire helmet-height marker, positioned at the measured contact. The sheet’s 65 × 54 px samples isolate the actor; they are not an in-game board test.

Reopening the saved file verified the T rest, the mount and detachment, and the same starting and ending pose in all three actions. At the 96 integer playback frames, both soles stayed 4 mm above the ground plane with less than 0.001 mm of boot-anchor displacement. During both heals the staff butt stayed at its ready contact point within 0.001 mm (rounded); at the hold the free palm was 57 cm from the chest reference for Ally Heal, versus 9 cm for Self Heal. The actual crook-pad point dropped 26.1 cm with 6.6 cm of horizontal travel to 1.519 m above the ground on frame 15, then rebounded 10.4 cm by frame 18. The staff base mesh did not intersect the selected sleeve, forearm, coat, vest, satchel, face or hair base meshes. This is not a cloth, grip, or whole-body collision simulation.

## Known limits

This is a pose and motion study. The bones carry editable rigid pieces with overlapping joint shapes, not a skinned production mesh. Locally solved arm and leg poses are baked to FK channels on each frame; there are no live IK controls. Larger retargeted poses need a new clearance pass. The coat and satchel are keyed; neither uses physics. Materials are provisional, procedural and self-contained. There is no target character, reaction, spell effect, runtime export or Godot integration. The next useful test, if authorized, is an unlabeled board-scale comparison with a nearby ally and opponent: can a player tell who was helped, who was knocked, and what changed?
