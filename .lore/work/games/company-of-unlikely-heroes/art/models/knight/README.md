# Knight guard blockout

Editable Blender candidate for *Barnaby’s Order of Last Resort*. This is a character and motion study, not accepted production art or a Godot asset.

The approved [T-pose turnaround](../../concepts/knight/knight-t-pose-turnaround.png) governs the silhouette, clothes, armor and shield. The approved [guild steps guard study](../../concepts/knight/guild-steps-guard-study.png) governs the low readiness, shield turn and braced reaction. The wearer’s right shoulder carries the larger four-piece pauldron. The left carries the tapered shield with an ochre griffin, wrapped grip, open forearm strap and separate fasteners.

## Pose and edit

Open `knight-guard-blockout.blend` in Blender 5.2.2 LTS. The file opens at **39, Guard**, with `Camera_Tactical_3Q` active. Its angle and framing are fixed across the animated beats. `Camera_Neutral_Front` is for the turnaround comparison.

| Frame | Beat |
| ---: | --- |
| 0 | True T-pose, outside playback. Hide collection `05 • Shield (detach at root)` in the viewport for a clean arm silhouette. |
| 8 | Wary, with the shield carried low and turned out. |
| 25 | Lead foot in flight, shield turning in. |
| 31 | Left boot plants. |
| 39 | Guard, shield up. |
| 44 | Flinch without losing the plant. |
| 65 | Settle, still guarding. |
| 78 | End of the take, not a seamless loop. |

`Knight_Rig` uses 24 named bones. The armor and clothes are editable rigid pieces; there are no weighted meshes. The action `Knight | Wary, plant, cover, settle` contains baked FK transforms at 24 fps, with pose keys mostly every other frame. The shoulder plates and each tabard half can be adjusted separately. The rig faces −Y, with Z up and the wearer’s right at −X. The shield-free neutral bounding box is about 1.96 × 0.46 × 2.15 m.

`Shield_L_Detachable` is an Empty bone-parented to `shield_mount.L`, a child of `forearm.L`. In Object Mode choose **Clear Parent and Keep Transformation** on that Empty to detach the whole shield. Do not unparent the rim, handle, strap or paint individually. The coat, armor and oak wear use built-in shader nodes; the heraldry is editable geometry. There are no external files required to open or render the `.blend`.

## Inspect

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/knight"
out="$PWD/.lore/local/company-of-unlikely-heroes/knight-blockout"
blender --background "$model/knight-guard-blockout.blend" --threads 9 \
  --python-exit-code 1 --python "$model/review_knight.py" -- "$out"
bash "$model/make_review_sheet.sh" "$out"
```

`review_knight.py` asserts the rig and mount, neutral limb orientation, planted contact and clearance during the take. Pass `--check-only` after Blender’s `--` to verify without rendering. The sheet composer uses ImageMagick and Noto fonts; they are not model dependencies. It produces close poses and 65 × 54 px samples, not a gameplay board or a Godot render. At sample size, the silhouette and the turn of the shield read better than the eye line or lead-foot plant.

The reopened action had less than 0.5 mm of rear boot-anchor drift across frames 8–78 and less than 0.3 mm of lead boot-anchor drift from frame 31 to 78. Planted leather soles sit about 4 mm above Z=0; only the lead boot lifts during the step. A vertex sample of the left arm and armor shells was at least 58.7 mm behind the outer oak face at every playback frame. The upper shoulder lames showed no surface overlaps with the head or neck; the closest sampled gaps were 53 mm on the right and 32 mm on the left. These checks use the base meshes, not a full collision test of cloth, rim, strap or modifier thickness.

The pose fit is specific to this action. The pauldron lames overlap by design, and the tabard and shoulder clearances need a fresh check for a larger turn or deeper crouch. The strap and grip are modeled and mounted but do not use physical contact constraints; the grouped blockout fingers do not close fully around the grip. No sword, other characters, scene effects, runtime exports or integrations are included.
