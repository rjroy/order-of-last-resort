# The Bad Bard

`bard-blockout.blend` is the accepted, self-contained Blender 5.2.2 LTS Bard model for *Barnaby’s Order of Last Resort*. Ronald approved the [two-song concept](../../concepts/bard/bard-two-songs.png), then accepted the model after reviewing its [pose sheet](../../../../../../local/company-of-unlikely-heroes/bard-blockout/contact-sheet.png) and [loop comparison](../../../../../../local/company-of-unlikely-heroes/bard-blockout/two-songs.webp) on 2026-11-21. Accepted `.blend` SHA-256: `5685e66c4f43a73a8267afcb6d16c369e64d3d6460cc80631642f3e796874966`. Godot integration remains separate.

The Bard is a veteran wedding fiddler: a broad belly, receding grey curls, a swept moustache, worn oxblood tails, a teal waistcoat and an ochre neckcloth. Three old requests sit in a stitched leather wallet. Both songs are standing orders. The rig plays to the room, not to a selected target; the difference is the knee and quick bow changes versus planted feet, lifted chest and a sustained sung note.

## Replay and edit

The file opens on frame 1 of **Ready Count-In** with `Bard_Rig` selected. Open the **Dope Sheet → Action Editor** and choose an action by its `Bard |` name. For full-scene playback, set the timeline end to the action’s end below. Use frame 1 for switching takes.

| Action | Frames at 24 fps |
| --- | --- |
| `Bard \| Neutral T` | **1** actual rest. Hide both prop collections for a clean turnaround. |
| `Bard \| Ready Count-In` | **1** listening; **9** pickup; **13** count-in flick; **22–25** settled. |
| `Bard \| Inspiring Melody` | **8** hair meets strings; **13** first high knee and reversal; **17–29** answering strokes; **34** second high knee; **41–46** release; **49** return to frame 1. |
| `Bard \| Healing Sonnet` | **8** fills the chest; **11–38** sustained draw, with **25** a clear sung pose; **43–55** breath and reset; **61** return to frame 1. |

Frames 25, 49 and 61 are closing keys equal to frame 1; omit the duplicate closing frame when baking a loop. The loops last 1, 2 and 2.5 seconds respectively. The songs share the ready stance but have independent actions, with no NLA or external dependencies.

Enable viewport overlays to see the bones. The arm and leg solutions are keyed in FK; there are no live IK controls. The sleeves and breeches deform across the elbows and knees. The rest is editable mesh or curve geometry attached to bones. `Fingers`, `Face` and `Attachment` are hidden bone collections you can reveal to adjust a grip, jaw, mouth or mount. The props have separate root empties: `Fiddle_L_Detachable` follows `fiddle_mount.L` on the chest, and `Bow_R_Detachable` follows `bow_mount.R` on the right hand. In Object Mode, select either root and use **Clear Parent → Keep Transformation** to detach the whole assembly. Do not unparent its constituent parts.

## Reopen and review

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/bard"
out="$PWD/.lore/local/company-of-unlikely-heroes/bard-blockout"
blender --background "$model/bard-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_bard.py" -- "$out/renders"
blender --background "$model/bard-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_bard.py" -- "$out/renders" --render-only --mode motion
bash "$model/make_review_previews.sh" "$out"
```

Use `--check-only` after Blender’s `--` for verification without renders. The review scripts do not save the Blender file. ImageMagick, Fontconfig and FFmpeg with animated WebP support compose the sheet and silent comparison; they are not model dependencies.

- [Pose sheet](../../../../../../local/company-of-unlikely-heroes/bard-blockout/contact-sheet.png)
- [Silent loop comparison](../../../../../../local/company-of-unlikely-heroes/bard-blockout/two-songs.webp)

Scale and facing match the [Healer](../healer/README.md) and [Wizard](../wizard/README.md): metres, forward −Y, up +Z, wearer’s right −X. The tactical camera matches their rotation and 2.47 m orthographic scale and is recentered for the Bard. Neutral T uses a separate front view. The 65 × 54 samples isolate the actor, not an in-game board. The high knee and bow motion are the strongest small-scale cues; mouth and finger detail need the larger diagnostic view.

## Verification and limits

Candidate SHA-256: `5685e66c4f43a73a8267afcb6d16c369e64d3d6460cc80631642f3e796874966`. The reopened file has 44 bones and 396 editable body, clothing and accessory mesh/curve objects excluding the fiddle, bow and review set. Neutral bounds without the props are 2.253 × 0.670 × 2.039 m (width × depth × height).

Half-frame checks passed for matched loop endpoints, both mount offsets, hair/string alignment during playing, and the boot anchors when planted. The Melody boot rises to 25.9 cm above the review floor, and each of its six alternating bow strokes travels more than 11 cm. The Sonnet holds a continuous 42.0 cm draw. Clearance checks at integer frames passed for the main fiddle shell and bow stick against selected head, jaw, nose and waistcoat surfaces, and for the stick against the fiddle shell. The chinrest is staged at the collarbone, within 11–27 mm of the nearest head/jaw surface; it does not clamp onto the jaw as he lifts his chin to sing.

This is an editable model and timing study, not production skinning, a whole-body collision or cloth simulation, an exact violin technique reference, or a target/reaction study. There is no audio, runtime export or Godot integration. If the model is accepted, the next useful test is an unlabeled side-by-side board comparison: can Ronald distinguish the two songs from the Bard’s behavior alone, before the opponent’s reaction gives it away?
