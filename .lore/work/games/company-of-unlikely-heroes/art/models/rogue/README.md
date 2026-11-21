# Rogue: the alibi

`rogue-blockout.blend` is the accepted editable Blender 5.2.2 LTS Rogue for *Barnaby’s Order of Last Resort*. Ronald approved the [alibi concept](../../concepts/rogue/rogue-alibi-study.png) and accepted the model after reviewing its [pose sheet](../../../../../../local/company-of-unlikely-heroes/rogue-blockout/contact-sheet.png) and [motion preview](../../../../../../local/company-of-unlikely-heroes/rogue-blockout/three-beats.webp). Accepted `.blend` SHA-256: `99d4607ab9e9792c51e15ae90d11d412973e98e3e17f481b5c976fbac02cfbb1`. The keys and ticket punch are usher’s tools, not weapons. Runtime integration remains separate.

Confusing Dodge is a crossing step and pivot within the stance; the board rules, not this animation, choose the swap partner and handle relocation. For Wasn’t Me, the hand to the chest and open usher’s palm play to the marked opponent. The palm does not select the other character or aim an attack.

## Play and edit

The file opens on frame 1 of **Ready / Retreat** with `Rogue_Rig` selected. In **Dope Sheet → Action Editor**, choose the exact action name from the dropdown, return to frame 1, and set the timeline end to the listed last frame. Turn viewport overlays on to see the rig in Pose Mode. The actions do not use NLA strips.

| Action | Frames at 24 fps |
| --- | --- |
| `Rogue \| Neutral T` | **1** matches the actual armature rest with both arms out. |
| `Rogue \| Ready / Retreat` | **1** ready; **5** checks the threat; **9** steps back; **13–17** rear shoe planted; **26** ready restored; **29** close. |
| `Rogue \| Confusing Dodge` | **4** load; **7** crossing step; **10** low pivot with rose lining exposed; **12** cross-plant; **15** unwind; **19** trailing shoe sets; **34** ready restored; **37** close. |
| `Rogue \| Wasn't Me` | **5–9** collects the heels and opens the arm; **14–36** holds the alibi; **25** is the review frame; **50** ready restored; **53** close. |

The three closing frames match the shared Ready pose. When baking loops, omit the duplicate close. The half-frame FK keys were baked from planted-foot and hand positions; no live IK is needed or provided. Sleeves, waistcoat, fingers and breeches deform on the rig. Most smaller details are editable mesh or curves attached to bones. The armature’s `cape_flash` and `cape_usher` custom properties control two cape shape keys in addition to the neutral drape. To tune a take, edit those properties’ keyframes in the action; edit the mesh shape keys to change the actual folds. `Fingers`, `Secondary` and `Attachment` group the detail bones. To detach wearable hardware, select `Keys_L_Detachable` or `Punch_R_Detachable` in Object Mode and choose **Clear Parent → Keep Transformation**; leave the parts parented to their root.

## Reopen and review

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/rogue"
out="$PWD/.lore/local/company-of-unlikely-heroes/rogue-blockout"
blender --background "$model/rogue-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_rogue.py" -- "$out/renders"
blender --background "$model/rogue-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_rogue.py" -- "$out/motion" --render-only --motion
bash "$model/make_review_previews.sh" "$out"
```

Use `--check-only` for checks without rendering. The review script never saves the source. ImageMagick, Fontconfig and FFmpeg with animated WebP support assemble the sheet and optional comparison; they are not model dependencies.

- [Pose sheet and actual 65 × 54 px samples](../../../../../../local/company-of-unlikely-heroes/rogue-blockout/contact-sheet.png)
- [Silent three-action comparison](../../../../../../local/company-of-unlikely-heroes/rogue-blockout/three-beats.webp)

The model matches the [Knight](../knight/README.md), [Healer](../healer/README.md), [Wizard](../wizard/README.md) and [Bard](../bard/README.md): metres, −Y forward, +Z up, wearer’s right at −X. All acting views use the cast’s tactical camera rotation and 2.47 m orthographic scale, recentered for this actor. The T rest uses a straight-on camera. The native samples isolate the figure, not a Godot board.

## Verification and limits

Candidate SHA-256: `99d4607ab9e9792c51e15ae90d11d412973e98e3e17f481b5c976fbac02cfbb1`. The reopened source has 40 bones and 221 editable mesh or curve objects excluding the review floor. Neutral bounds including the cap and tools are 1.929 × 0.594 × 2.002 m (width × depth × height). All shader nodes, models, and actions are internal to the `.blend`.

In 235 half-frame samples, the common start/end poses matched, both tools stayed on their mounts, and planted ankle positions drifted by at most 0.0004 mm. Detaching either root with transforms kept did not move any constituent piece. The soles stay 4.07 mm clear of the review floor when planted; their surfaces do not intersect one another. The cape and its fold do not intersect the tested bare forearms, palm shells or fingers; the closest sampled palm vertex is 18.5 mm from the cape. The rigid hardware clears its own side’s breeches, bare forearm and hand. These surface tests exclude intended cloth overlap at the shoulder and leather hangers at the belt, and are not a whole-body collision or cloth simulation.

At Dodge frame 10, the lifted ankle passes 7.8 cm across the stance ankle, and the pelvis is 9.9 cm below the loading pose. The root does not move; the hips travel up to 20.2 cm horizontally from Ready. Alibi holds the whole rig still at frames 14–36 (about 0.92 seconds between those frames), with heels close and turned-out toes. At 65 × 54, the crossing silhouette, flash of lining and held palm carry the contrast. The curls, keys, ticket punch and wry expression need the larger view. No target, mark or redirection effect, production retargeting, runtime export or Godot integration is included. If the model is accepted, the next useful test is an unlabeled board comparison with an opponent and a second character: can Ronald read the feint and tell whom the alibi addresses without mistaking the open palm for victim selection?
