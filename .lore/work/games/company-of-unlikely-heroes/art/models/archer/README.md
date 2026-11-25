# Archer model

`archer`, xmy.8, for Barnaby’s Order of Last Resort. The approved reference is [Sheet 02](../../concepts/non-hero-cast/02-shield-wall-and-captain.png), SHA-256 `5815d7caae1b7b15d8bdab9b8ccdddb3dfb7dbc2a1000c5d08542dfa9728d21c`. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Accepted corrected master](archer-candidate-clearance.blend), SHA-256 `a9ba0e6bc35d8d233c76aa8c97048b0b6fd1f0dc0cd003d8f0cdabaf4180f118`. The unchanged [superseded original](superseded/archer-candidate.blend), SHA-256 `860f336d875408cd233e438fdd2bef09f661c216ccac6350d4ac150afc29f784`, remains the comparison source. Both were made in Blender 5.2.2 LTS, `d13f752e3b9c`. The actor faces −Y, +Z up, with its origin at the ground anchor. The original neutral body including the quiver, but excluding bow and release arrow, spans 1.733 × 0.504 × 1.879 m. Both files contain 23 bones, 144 mesh objects and 22 procedural materials.

Feedback was that the bow clipped. Reviewing all 78 decoded drawings of the original video and testing the meshes confirmed that the stave and string crossed the sleeve, torso and wrist during carry and movement. The original draw put the string and fletching through parts of the head. The original defeat also swept the bow through the torso and leg. The accepted revision changes the gripping hand, carry and draw paths, projectile clearance, and the final bow drop. Body design, clothing, pigment, quiver, stock ability, and F17 release timing are unchanged.

In the Action Editor, select `Archer_Rig` and choose an action prefixed `Archer |`. The saved frame is Ready F1; Neutral T uses actual bind transforms. The editable FK keys are sampled at 24 fps. `Draw` on the rig drives the flex shape on the detachable bow; the two tips and nock move on their own rig channels to tension the string. `Arrow_Detachable` is a separate mount. The back quiver and its standing fan of arrows are part of the costume, not projectile parts.

| Action | Frames | Reason |
|---|---:|---|
| Neutral T / Ready | 1 / 1–33 | Neutral bind, then low carried bow. |
| Advance | 1–27 | In-place approach gait; board owns the tile motion. |
| Reserve Arrival | 1–27 | Quick arrival and settle for `hold_the_line`; no attack on arrival. |
| Draw and Release | 1–33 | F13 full draw, F17 release marker, F18 brief preview flight, clear after F18. Shows `archer_shot`: 2 damage, range 3. |
| Hit / Defeat | 1–17 / 1–29 | Opens the bow arm on recoil. On defeat the grip opens at F8 onward and the bow drops beside the kneeling actor on its own `implement` channel. |

The packaged take captures `Arrow_Detachable` separately at F17 and hides it from the actor drawing at F17 and later. Runtime owns the target and arrow travel; the brief Blender preview flight is not a prescribed board path. The bow and string stay with the actor. The aim, drawn string and snapback should read without an effect.

## Reopen and review

From the repository root:

```bash
actor=archer
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/$actor"
out="$PWD/.lore/local/non-hero-xmy-7-10/archer-clearance-review"
mkdir -p "$out"
export TMPDIR="$out" PYTHONDONTWRITEBYTECODE=1
blend="$model/archer-candidate-clearance.blend"
timeout 150 blender -b "$blend" -t 2 --python-exit-code 1 \
  --python "$model/check_archery_clearance.py" -- verify "$out/clearance.json"
for mode in check poses views motion-full; do
  timeout 250 blender -b "$blend" -t 2 --python-exit-code 1 \
    --python "$model/review.py" -- "$mode" "$out/$mode" || break
done
ffmpeg -v error -threads 2 -framerate 24 -i "$out/motion-full/frame-%03d.png" \
  -vf 'scale=448:448,format=yuv420p' -c:v libx264 -threads 2 "$out/motion.mp4"
```

The standard reviewer uses the current production registration camera and ink light without saving. The separate clearance check evaluates the meshes, including flexed bow and skinned string, against the evaluated body, wraps, sleeves, cuffs, face, quiver and legs. It also checks the arrow against the bow and verifies framing, ground clearance, and grasp or nock proximity. Intended grip contact is exempt only at the grip, and left-hand contact is exempt near the held nock. All 326 whole- and half-frame samples passed across six acting takes. The nearest prop to the edge was the dropped stave at 20.13 px inside the 320 px capture. The lowest prop was the settled bow grip at 3 mm above ground. The draw hand was no more than 11.1 mm from the nock from F8 through F17. This is a sampled geometry test, not a guarantee about arbitrary editing or retargeting.

[Corrected pose sheet](../../../../../../local/non-hero-xmy-7-10/archer-correction/final/archer/pose-sheet.png) · [Before and after](../../../../../../local/non-hero-xmy-7-10/archer-correction/final/archer/before-after.png) · [Both side views](../../../../../../local/non-hero-xmy-7-10/archer-correction/final/archer/side-views.png) · [Full motion at 24 fps](../../../../../../local/non-hero-xmy-7-10/archer-correction/final/archer/motion-preview.mp4).

At the fixed camera, the carried bow can still overlap the chest in projection. The side views and clearance check show separate geometry. The original shared tactical comparison is retained with the earlier MP4; neither is evidence of a runtime change. The stock Hold the Line graphical case checks reserve entry and shots. For the packaged arrow's launch and tip in both facings, run:

```sh
godot --path games/company-of-unlikely-heroes --script res://tests/presentation/archer_release_scene_test.gd -- \
  --output="$PWD/.lore/local/archer-release-check"
```

Use a new or empty output directory for each run.
