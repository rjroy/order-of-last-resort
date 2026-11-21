# The Skeleton

Ronald accepted the editable `skeleton-blockout.blend` for *Barnaby’s Order of Last Resort* (`mind-garage-ddd.10`) after reviewing the [pose sheet](../../../../../../local/company-of-unlikely-heroes/skeleton-blockout/contact-sheet.png) and [motion comparison](../../../../../../local/company-of-unlikely-heroes/skeleton-blockout/action-comparison.mp4). Accepted model SHA-256: `c270d6bfa5ae9a419e1319b8305588df8132bc3c646dd4b753fb3aeca2646d03`. The original static summon and its board sprite remain unchanged; runtime integration is deferred.

## What carried over

Ronald approved [First Greetings](../../concepts/necromancer/first-greetings.png) on 2026-11-20, specifically asking to keep the Skeleton’s broad wave. The exact concept SHA-256 is `fed436ee36ed767e9eecd232e55d74b8cf1f75ea6e994d3243b977164463f96f`. The actual starting point was the [accepted static Skeleton](../../../../../../../games/company-of-unlikely-heroes/assets/summons/source/skeleton.blend), SHA-256 `a50ba7b7d5ace4f0e3bdf15c44118dc869076b95fcf3665c3753cebd86f85f1f`; the [summon source package](../../../../../../../games/company-of-unlikely-heroes/assets/summons/README.md) describes that version and its sprite recipe.

The candidate reuses all 268 character meshes and their topology, materials and detail modifiers: the connected skull with deep sockets, hinged jaw and uneven teeth, rib cage and pelvis, separate limb bones, hands and feet, and the indigo scarf and edging. The source had no rig or animation. Its broad greeting was built into the mesh positions, and some objects had their origin at ground level. The model repositions those pieces into an upright T, levels the shoulders and pelvis, straightens and length-normalizes limb segments, centers the feet and gives individual pieces useful local origins. The inherited off hand was much smaller and tightly curled. It was enlarged locally without moving the wrist; the other hand keeps its broad finger fan. No replacement anatomy or new clothing was modeled.

The new 55-bone rig uses rigid bone parenting so separate pieces keep their shape. The fingers have three joints each. The skull, lower jaw, toes, and the two scarf tails have separate controls. The wrap and knot follow the chest. Leg rotations are baked as quaternion FK at half-frame intervals to hold the feet in place; the rest of the performance remains on sparse editable keys. There is no live IK, cloth simulation, linked asset, or external texture dependency.

## Play and edit

The scene opens on Ready at frame 1. In **Dope Sheet → Action Editor**, select `Skeleton_Rig`, choose a take and set the timeline end to match. Turn on overlays to see the color-grouped joints. The takes share the same opening and closing Ready stance, but are independent actions with no NLA tracks. For a loop, omit the duplicate closing frame.

| Action | Beats at 24 fps |
| --- | --- |
| `Skeleton \| Neutral T` | **1** is the actual armature rest, not a posed approximation. |
| `Skeleton \| Ready & Greet` | **1** stands expectantly; **15–24** the elbow stays close while the hand flutters by the face; **33** returns to Ready; **45** closes. |
| `Skeleton \| Wave` | **8** winds up; **15** reaches wide; **20** sweeps across; **26** rebounds; **31** smaller follow-through; **53** closes. It is a greeting too large for nearby company, not a practiced attack. |
| `Skeleton \| Don't Go` | **8** notices someone leaving; **19–40** leans in and holds one open palm toward them; **50** relents; **65** closes. The hand asks them to stay rather than striking. |

## Reopen and review

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/skeleton"
out="$PWD/.lore/local/company-of-unlikely-heroes/skeleton-blockout"
blender --background --disable-autoexec --threads 8 "$model/skeleton-blockout.blend" \
  --python-exit-code 1 --python "$model/review_skeleton.py" -- "$out/renders"
bash "$model/make_review_previews.sh" "$out"

# Optional: include the silent comparison.
blender --background --disable-autoexec --threads 8 "$model/skeleton-blockout.blend" \
  --python-exit-code 1 --python "$model/review_skeleton.py" -- "$out/motion" --render-only --motion
bash "$model/make_review_previews.sh" "$out" --motion
```

`review_skeleton.py` never saves, and `--check-only` skips rendering. The `.blend` is the authoring source; these helpers reproduce its checks and previews, not the construction of the model. Blender 5.2.2 LTS (`d13f752e3b9c`, Cycles CPU) renders the images. The assembly uses ImageMagick and Fontconfig; the optional MP4 also uses FFmpeg with `libx264`.

- [Pose sheet](../../../../../../local/company-of-unlikely-heroes/skeleton-blockout/contact-sheet.png), including five unscaled 65 × 54 tactical samples
- [Silent motion comparison](../../../../../../local/company-of-unlikely-heroes/skeleton-blockout/action-comparison.mp4)
- [Close-up](../../../../../../local/company-of-unlikely-heroes/skeleton-blockout/renders/portrait.png), [side view of Don't Go](../../../../../../local/company-of-unlikely-heroes/skeleton-blockout/renders/profile.png), and [rear rest](../../../../../../local/company-of-unlikely-heroes/skeleton-blockout/renders/rear.png)

The candidate uses metres, +Z up, −Y forward and wearer’s right at −X. Acting renders share the cast’s three-quarter rotation and 2.47 m orthographic scale; the front and rear views diagnose the T rest. The tactical samples are rendered at their final dimensions (about 26 px per metre); they are silhouette checks on a flat ground tone, not Godot footage.

## Verification and limits

Candidate SHA-256: `c270d6bfa5ae9a419e1319b8305588df8132bc3c646dd4b753fb3aeca2646d03`. Neutral bounds are 2.162 × 0.426 × 1.913 m (width × depth × height). Separate inventory reads confirmed matching character mesh names, topology, face material assignments and modifier types with the prior model. The original source package, runtime sprites, and concept passed before/after SHA-256 and modification-time comparisons.

The reopened review checks the original mesh attachments on the new rig, true T rest, and action endpoints. Across 323 moving half-frame samples, each foot stayed planted with its lowest surface 0.52 mm above ground. At whole frames, the tested joint pairs stayed seated. The sampled arm and hand surfaces cleared the face, selected ribs, sternum and scarf tails. These are targeted checks, not an exhaustive collision simulation. The Wave fingertip traverses 1.35 m side to side; the Don't Go wrist reaches 0.56 m forward and holds position while the fingers and jaw soften.

The isolated poses and short takes show no target, hit reaction, or movement effect. At tactical size, the gesture must carry the distinction because fingers, teeth and scarf stitching lose detail. The next useful check after model approval is to compare these actions without captions beside nearby figures: does Wave feel broad enough to clip a bystander, and does the held palm of Don't Go read as a plea rather than a blow? This candidate does not establish that the game communicates damage or movement prevention.
