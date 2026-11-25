# Hobby Smith

**Approved editable Smith model.** Ronald approved rendering this exact file into the local game after reviewing the linked model and motion previews. SHA-256: `a9d1113d0fb555accd4e0817890e3050d147bf45e2bf448a0fbe8f3b6e0da361`. The filename is retained so reproduction commands still address the same bytes. Approval authorizes integration; it is not an in-game playback verdict.

Ronald confirmed the exact [guild-book native portrait](../../../../../../../games/company-of-unlikely-heroes/assets-source/guild-book/classes/blacksmith-native.png) as the approved likeness and directed us to proceed without generating a new concept. Its SHA-256 is `e35c28dfa10db7dd6dcc211893ee7ca210f46f364be3b348433f0e1aabf4d248`. The [portrait production record](../../../../../../../games/company-of-unlikely-heroes/assets-source/guild-book/classes/README.md) preserves the original generation job. The [class design](../../../notes/hobby-smith-design.md) supplies the two core actions; the [art direction](../../direction.md) and existing guild cast supply scale, facing and presentation.

## Model and actions

Open [hobby-smith-candidate.blend](hobby-smith-candidate.blend) in Blender 5.2.2 LTS. It opens on **Ready**, with the armature selected and the tactical camera active. In the **Dope Sheet → Action Editor**, pick an action and set the end frame to the one listed below. Turn overlays on to inspect the bones in Pose Mode. All takes are independent, with baked quaternion keys at half-frame intervals and no live IK controls.

| Action | Frames at 24 fps | What to review |
| --- | --- | --- |
| `Hobby Smith \| Neutral T` | 1 | True armature rest. Hide the detachable kit to inspect the bind silhouette. |
| `Hobby Smith \| Ready` | 1–25 | Subtle weight and breath movement, matching start and end. |
| `Hobby Smith \| Try This` | 1–33 | Frames 13–18 show a single crescent fitting held outward while the hammer stays low and both boots stay planted. This is a presentation gesture, not projectile or recipient contact. |
| `Hobby Smith \| Hammer Time` | 1–34 | Wind-up at 12, short downward strike at 17, settle through 19 and return to Ready. No shove. |
| `Hobby Smith \| Pursue Step` | 1–28 | The frontward step has two separate foot plants and ends in Ready translated 0.493 m along −Y. It is a travelling take, not an in-place loop or a board-distance specification. |

The Smith faces −Y, with +Z up and the anatomical right at −X. The 17-bone rig has separately editable hands, feet and an apron bone. Mesh weighting spans the moving elbows, knees and apron. `Hammer_Detachable` and `Fitting_Detachable` are bone-parented assembly roots. Select a root in Object Mode and use **Clear Parent and Keep Transformation** to detach it without separating its parts. The 159 model mesh objects and 24 material datablocks use no external textures, linked libraries or add-ons. The neutral figure, without the two tools, measures 1.940 × 0.623 × 2.175 m.

## Review this exact candidate

- [Pose sheet and 65 × 54 px tactical samples](../../../../../../local/hobby-smith-concept/verified/pose-sheet.png)
- [Silent Try This and Hammer Time comparison](../../../../../../local/hobby-smith-concept/verified/try-this-and-hammer-time.webp)
- [Portrait detail](../../../../../../local/hobby-smith-concept/verified/renders/portrait.png) and [rear strap construction](../../../../../../local/hobby-smith-concept/verified/renders/neutral-back.png)

At tactical scale, the two actions read by the outward arm and steady feet versus the high wind-up and lower crouched strike. The fitting’s rivets and expression are close-view details. The view is a Blender performance study, not an in-game check. It has no recipient, target, effect, runtime sprite export, or Godot integration.

## Reproduce and verify

From the repository root, using Blender **5.2.2 LTS** (`d13f752e3b9c`), Python 3, ImageMagick and Fontconfig. FFmpeg with `libwebp_anim` is only needed for the optional motion comparison. Use a fresh output directory for each run; the recipe does not overwrite an existing master.

```sh
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/hobby-smith"
scratch="$PWD/.lore/local/hobby-smith-concept"
mkdir -p "$scratch"
out="$(mktemp -d "$scratch/review.XXXXXXXX")"
master="$model/hobby-smith-candidate.blend"

# Optional: regenerate the editable source beside the original.
blender --background --threads 6 --python-exit-code 1 \
  --python "$model/build_smith.py" -- "$out/hobby-smith-rebuilt.blend"

# Reopen the exact master (or set master to the rebuilt file).
blender --background "$master" --threads 8 --python-exit-code 1 \
  --python "$model/review_smith.py" -- "$out/renders"

# Optional: add the two silent previews at 12 fps.
blender --background "$master" --threads 8 --python-exit-code 1 \
  --python "$model/review_smith.py" -- "$out/motion" --images-only --motion
python3 "$model/compose_review.py" "$out/renders" "$out/pose-sheet.png" --motion "$out/motion"
```

For checks without images, add `--check-only` after the output directory passed to `review_smith.py`. For a sheet without motion, omit the last two arguments to `compose_review.py`. Review lighting is Cycles with transparent output; the eight stills are 624 × 624 px, using the cast’s tactical rotation and a 2.47 m orthographic scale for acting views. The neutral T, back and portrait each have their own diagnostic camera. No review command writes to the master.

The reopened-file check verifies the T-pose, weights and topology, detachable roots, action ranges, Ready matching, planted ankle positions, boot clearance and camera framing. Across the sampled poses, both prop origins stay within 0.001 mm of their grip landmarks, planted ankles drift less than 0.004 mm, and the smallest camera margin is 2.4%. This does not establish full collision-free skinning or gameplay readability. The final views were inspected after correcting the hammer arc, apron clearance and rear strap lay in earlier blockouts.

| Verified item | SHA-256 |
| --- | --- |
| Exact model candidate | `a9d1113d0fb555accd4e0817890e3050d147bf45e2bf448a0fbe8f3b6e0da361` |
| Geometry and action-key fingerprint | `d9548dc517796d32a5723732a479d70ff64c5fec16af065aa342655293caf053` |
| Pose sheet | `24819001f41f0608ee4f86b00e7a6f2221c559dcac3aa7f87d5730e3387e9f8b` |
| Motion comparison | `0677a97fcf9a1ffa14f5d3dde092e3d4b8fc82693b37cdd66d31bbd62efc4754` |

An independent rebuild matched the geometry and action-key fingerprint and all check measurements. The fingerprint covers mesh coordinates, topology and action keys. It is not a promise of byte-identical `.blend` serialization across builds or Blender versions. The model and recipe are maintained sources; generated captures and logs stay in `.lore/local/`.

## Battle atlas

The [one-role bake recipe](../../../../../../../games/company-of-unlikely-heroes/tools/cast/actors/blacksmith.json) renders the exact approved model above and appends the SHA-pinned [supplementary Actions and hand kit](supplementary/motion.blend) in memory. It reads their frame selections from [supplementary/takes.json](supplementary/takes.json). Neither source is saved during the bake. The stock cast renderer supplies its 320 × 320 orthographic capture, `[160,248]` ground origin, warm contour ink, 104.918 px/m and 0.375 display scale. The atlas has no grid: the manifest stores per-frame rectangles in playback order and one anchor per clip. Godot owns tile placement and facing.

| Clip | Drawings at variable holds from 24 fps | Duration | Visible beat |
| --- | ---: | ---: | --- |
| `ready` | 6 (4 unique), loops | 1000 ms | Breath and weight shift; no feedback beat |
| `try_this` | 13, once | 1375 ms | F13, 500 ms: present the fitting. Hold through F18; no release. |
| `hammer_time` | 15, once | 1417 ms | F12 wind-up; F17, 667 ms: contact. |
| `pursue` | 11, once | 1167 ms | Foot plants F13 and F28, 500 and 1125 ms. |
| `bonk` | 8, once | 1208 ms | F15, 583 ms: crook contact. |
| `acid` | 9, once | 1417 ms | Last held drawing F16; F18, 708 ms: release. |
| `acid_flask` | 1 | 42 ms | F18 isolates the vial. Its launch offset is `[92.713, -143.020]` atlas pixels from the Smith's ground anchor. |
| `hit` | 6, once | 750 ms | F3, 83 ms: recoil. |
| `down` | 7, once | 1125 ms | F16, 625 ms: contact; F24 matches Recover's first drawing. |
| `recover` | 7, once | 1167 ms | F22, 875 ms: rise; F26 matches Ready. |
| `defeat` | 7, once | 1125 ms | F16, 625 ms: contact; F24 remains a separate fallen pose. |

For Pursue, the capture camera follows only the pelvis's native world Y travel. This removes the authored 0.493 m translation from the sheet and keeps the other weight shifts. The board moves the ground anchor exactly once. For Acid, the original hammer and fitting are hidden only for the hand-kit actions that replace them; the crook is visible only during Bonk. The vial is held through the last F16 drawing and absent from the actor at and after F18. The atlas contains no flight or impact effect. Apply facing and display scale to the launch offset, then fly the isolated vial to the committed recipient.

Rebuild from the repository root with Blender **5.2.2 LTS**, ImageMagick **7.1.2-34**, Python **3.14.8** and Fontconfig (the latter is only for the proof):

```sh
tools=games/company-of-unlikely-heroes/tools/cast
model=.lore/work/games/company-of-unlikely-heroes/art/models/hobby-smith
scratch="$PWD/.lore/local/cast-bake"
mkdir -p "$scratch/tmp"
stage="$(mktemp -d "$scratch/blacksmith.XXXXXXXX")"
TMPDIR="$scratch/tmp" MAGICK_TEMPORARY_PATH="$scratch/tmp" \
  python3 "$tools/bake_subset.py" "$stage" blacksmith --threads 6
python3 "$tools/verify_cast.py" --assets "$stage" blacksmith
python3 "$model/review_smith_atlas.py" "$stage" "$stage/board-proof.png"
```

Publish the atlas to `res://assets/cast/blacksmith.png` and the matching `.actors.blacksmith` entry together. The staged manifest is not a replacement for the shared runtime manifest. Regenerate the texture sidecar with Godot **4.7.2** as described in the [cast recipe guide](../../../../../../../games/company-of-unlikely-heroes/tools/cast/README.md).

The unified atlas is 1824 × 2076, SHA-256 `20ce9d428d443ca25f49cad3843d053c41a1010eb1f5977c3c5ff27d8d1a4f01`. A second build with the same tools reproduced the PNG and staging manifest byte for byte. All 45 primary drawings retain the exact crop pixels, timing and anchors of the original four-clip bake. The [proof at 65 × 54 cell size](../../../../../../local/cast-bake/blacksmith-full.mRNqzdd8/board-proof.png) shows the shipped cast for comparison, the fitting and hammer beats, the release handoff, and the living versus defeated poses. The standard verifier checks frame bounds, clear alpha padding and release timing for all 90 samples. Neither the proof nor the automated checks replaces visual acceptance in play.
