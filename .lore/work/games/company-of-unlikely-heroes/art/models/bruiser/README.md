# Bruiser | editable model

Ronald approved the lower-left Bruiser in [River and Village, sheet 01](../../concepts/non-hero-cast/01-river-and-village.png), SHA-256 `f3a93be9d71479a142b88c46597558e460ae9a729735b87fb8a54591c48af767`. The designer owns that shared original. This actor models the short-maul fighter in `harpoon_squad`, `unfortunate_healer` and `hold_the_line`; he pursues and strikes adjacent targets, not a ranged or special-effect attack. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Editable Bruiser](bruiser-candidate.blend) · [pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bruiser/pose-sheet.png) · [motion with tactical-size inset](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bruiser/motion-preview.mp4)

**Accepted model SHA-256:** `190e66a530052a883dd7d52db7ea01d0629585cb4a7f0115631423807bf9ddc4`.

## Construction and performance

The fighter's shoulders are wider than his close-cropped head. His open, rusty red jerkin hangs in separate ragged panels over trousers and buckled boots. Flanged iron shoulder plates contrast with the bare upper arms and linen-wrapped forearms. He carries one short, squared iron maul with both hands across the waist. Human proportions, two-handed carry and paired pauldrons keep the design apart from a large creature or a raider silhouette; no adjacent cast comparison is claimed here. After the first render, the scalp was conformed to the squared skull, the coat acquired overlapping skirt and collar details, and the final pose tucked the chin and lowered the maul.

Blender 5.2.2 LTS; metres, +Z up, −Y forward. Self-contained 17-bone armature `Bruiser_Rig`, 307 editable meshes and 18 materials. Bare T body bounds 2.272 × 0.605 × 1.885 m, including extended arms. Garment deformation blends hips and ribcage. Other detail and limbs follow rigid bone groups; clothing is not simulated. `Maul_Detachable` groups the tool geometry on the separate `maul` control. Two-handed contact and ankle targets were solved into editable FK action keys. The bind leaves the arms level; the review hides the independent maul in that view. The saved model opens at Ready. Select the rig and choose an action in the Action Editor. Timing at 24 fps:

| Action (prefix `Bruiser \| `) | Beats |
|---|---|
| Neutral T | F1, actual bind. |
| Ready | F1–37, stooped, open stance with a small breath. Loop ends match. |
| Trudge | F1–29, leading boot lifts at F8, trailing boot at F22. In-place travel; mission owns displacement. |
| Heavy Strike | F1–42. Loads near the shoulder at F9, checks the weight at F15, folds through the blow at F18 and stays low F21–25 before recovering. Action markers: `Weight lands` F18 and `Follow through` F21. Source for `bruiser_strike`. |
| Hit | F1–17, checks backward, holds briefly and returns to Ready. |
| Down | F1–29, buckles, folds behind the maul, holds F21–29. |

## Review and checks

From repository root:

```bash
m="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/bruiser"
o="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/bruiser"
blend="$m/bruiser-candidate.blend"
mkdir -p "$o"
export PYTHONDONTWRITEBYTECODE=1
sha256sum "$blend" > "$o/model.sha256"
timeout 90 blender -b -t 4 "$blend" --python-exit-code 1 -P "$m/check_bruiser.py"
timeout 150 blender -b -t 5 "$blend" --python-exit-code 1 -P "$m/review_bruiser.py" -- "$o/poses"
timeout 180 blender -b -t 5 "$blend" --python-exit-code 1 -P "$m/review_bruiser.py" -- "$o/motion" motion
python "$m/compose_review.py" "$o"
sha256sum -c "$o/model.sha256"
```

The authoritative input is the saved master. `build_bruiser.py` is its construction script; to make a separate study, supply a new absolute `.blend` path. The reviewer applies the cast ink shader in memory, with the fixed tactical camera angle, 2.48 m square framing and deterministic CPU Cycles renders. The overview adds side and back views. The 1170 × 711 sheet includes unenlarged silhouettes at 26 px/m. The 540 × 420 silent MP4 samples at 12 fps for 5.75 seconds and includes a second, tactical-size drawing. These are isolated views, not a Godot mission test.

Reopen checks covered all 154 acting frames: fixed root, soles at least 9.99 mm above ground, both designed grip centers within 0.001 mm of their moving handle targets, the true T bind, matching Ready returns and the held down pose. The leading ankle rose 15 cm; the maul face dropped from 1.987 m at F15 to 0.469 m at F21. The small views show the tool moving from above the head to outside the near boot, without an invented impact effect. Individual rivets, stubble and the hand lock require the larger views. Tests verify rigid registration, not collision-free arbitrary retargeting.
