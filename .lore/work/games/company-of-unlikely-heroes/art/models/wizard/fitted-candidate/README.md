# Enthusiastic Caster: fitted actions

**Editable source approved on 2026-11-24.** This package adds three actions on the existing Wizard rig. The approved file keeps the filename of the exact source shown for review. It does not replace the [original Wizard master](../README.md). The [approved class concept](../../../concepts/wizard/wizard-blast-and-recoil.png) still governs the character. No new concept imagery, geometry, costume, or detached prop was needed.

Open [`wizard-fitted-candidate.blend`](wizard-fitted-candidate.blend) in Blender 5.2.2 LTS. It opens on `Wizard | Send-Off`, F1. Select a take in the Action Editor and enable **Show Pose Markers**. Native positions are in metres, +Z up and −Y forward, with the same origin as the accepted rig. The ledger stays mounted, both casts keep their boots planted, and all three takes return exactly to the common Ready pose. There is no root-motion track or external library.

## Assets and beats

All beats are measured from F1 at 24 fps. An arrival tick in the sheet is a review sample, not another rules event.

| Form | Actor asset | Beat and actual recipient |
| --- | --- | --- |
| Mending Blast, toward another hero | Reuse the packaged Wizard `blast` clip, not the Healer or the rival Wizard. | F17 (667 ms). Use the nearest wounded, healable deployed friendly hero; show marks only where HP returns, including a possible second patient from Conductive Personality. With no patient, play ordinary Blast with its actual target and damage feedback. |
| Mending Blast, on self | New `Wizard \| Mending Blast · Self`. Cup at F8, turn the palms inward at F17, Ready at F30. | F17 (667 ms), same beat as the outward take. A wounded caster is a legal recipient, and faces no distinct target. Recipient ink belongs to the caster’s own position, plus any actual secondary patient. |
| Send-Off | New `Wizard \| Send-Off`. Brace at F9, drive the offset palms forward at F13, stay planted through F18, Ready at F28. | F13 (500 ms). A chosen pushable character or obstacle normally moves one open step away along the dominant board axis. Use the committed destination for shift feedback, including an extra tile from Ball Bearings if legal, and show no shift if resisted by Cork Soles. No recoil damage, collision damage, or caster movement. The ordinary Pull clip draws both hands toward the body at F13 and lands seated at F24, so it cannot stand in. |
| Ring of Salve | Reuse the packaged Wizard `ring_sparks` clip, whose planted two-hand sweep does not bake fire, sparks, or a strike. | F12 (458 ms). Mark each orthogonally adjacent wounded friendly character who actually regained HP. No marks on the caster, enemies, or obstacles. |
| Clear Jump | New `Wizard \| Clear Jump`. Load at F6, leave the ground at F8, peak at F12, front boot contacts at F17, rear boot at F19, Ready at F28. | F8–17 (292–667 ms) is the proposed travel window. Only the caster travels, to the chosen open cell beside the furthest living opponent. The opponent is a locator, not a moved, hit, or swap recipient. The packaged Wizard `dodge` is a planted tuck and turn for a swap, not a jump; no Dodger motion or sprites are used. |

## Board projection used for review

`rules.gd` writes the performed alternate ID and the original source ability into `resolved_action`. `rules/fitted_tactical.gd` emits regular `heal`, `push`, and `move` events with actual recipients and cells. `bridge_art.gd` paints feedback around action-time recipient cells: mint strokes and crosses for healing, pale strokes for a shift. Ordinary Blast has no traveling spell bolt, and Ring of Sparks has no painted radius effect; the renderer draws special flight only for clips with prop-release metadata. The two existing cast gestures therefore need different recipient routing, not replacement motion or new spell effects.

The sheet uses the stock 96 × 80 tile spacing, `[49,62]` cell foot, 0.375 sprite display scale, and the board renderer’s exact orthographic angle. Existing gestures use exact crops from `assets/cast/wizard.png`; new poses render from the exact approved source. Tokens, dashed travel lines and destination stamps only explain the selected cells; they are not new effects. Send-Off’s projection uses the stock 180 ms displacement and 280 ms feedback fade. Clear Jump is authored in place: to match the share of motion shown, hold at the source through F7 and translate during F8–17. The sheet does not verify runtime bindings or playback.

## Production recipe

The Wizard input is `games/company-of-unlikely-heroes/tools/cast/supplements/wizard.json`. It adds the three independent actions from the approved scene; stock clips still use the original Wizard asset. The render uses the review capture size and anchor, so the Jump’s height does not require reducing actor scale. The new clips are non-looping and have no release sprite.

Stage and verify the Wizard only, without writing to the runtime directory:

```sh
cast="$PWD/games/company-of-unlikely-heroes/tools/cast"
out="$PWD/.lore/local/company-of-unlikely-heroes/wizard-fitted"
mkdir -p "$out"
tmp=$(mktemp -d "$out/bake-tmp.XXXXXX")
TMPDIR="$tmp" MAGICK_TEMPORARY_PATH="$tmp" \
  python "$cast/bake_subset.py" "$out/production-stage" wizard --threads 4
python "$cast/verify_cast.py" --assets "$out/production-stage" wizard
```

Use a new or empty path for `production-stage`. The partial manifest only contains `actors.wizard`; combine that one entry with the runtime manifest at install, not the whole staged file.

The first production stage passed `verify_cast.py`. Its 1,536 × 2,894 atlas preserves the complete stock 1,536 × 1,767 RGBA region and all nine stock clip entries (71 drawings) exactly. The 33 appended drawings match the approved renders pixel for pixel at their original ground registration. See the [staging verification log](../../../../../../../local/company-of-unlikely-heroes/wizard-fitted/production-verification.log).

| Clip key | Source landmarks | Clip duration |
| --- | --- | --- |
| `mending_blast_self` | F8 cup, F17 heal (667 ms), F30 Ready | 1,292 ms |
| `send_off` | F9 brace, F13 release (500 ms), F18 follow-through, F28 Ready | 1,208 ms |
| `clear_jump` | F8 lift (292 ms), F12 apex (458 ms), F17 contact (667 ms), F19 rear boot (750 ms), F28 Ready | 1,208 ms |

## Reproduce the source and evidence

From the repository root:

```sh
p="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/wizard/fitted-candidate"
out="$PWD/.lore/local/company-of-unlikely-heroes/wizard-fitted"
mkdir -p "$out"
# Optional reconstruction. The recipe refuses to overwrite any existing file.
blender --background --factory-startup --threads 3 --python-exit-code 1 \
  --python "$p/build_actions.py" -- --output "$out/wizard-fitted-rebuilt.blend"
# Render the exact approved native source.
blender --background "$p/wizard-fitted-candidate.blend" --threads 3 \
  --python-exit-code 1 --python "$p/review_actions.py" -- "$out/renders"
python "$p/motion_sheet.py" "$out/renders" "$out/motion-sheet.png"
```

`review_actions.py` compares the candidate with the pinned accepted scene’s rig, asset inventory, and four original F-curve sets. Use `--check-only` after the output directory to skip renders. It samples the new actions’ Ready seams, root, ledger, foot plants, palm directions and airborne/contact beats. `motion_sheet.py` checks transparent bounds of all 33 rendered frames before composing the sheet with ImageMagick and Fontconfig fonts (Noto Sans and Noto Serif Display). The board ink capture is CPU Cycles, 12 samples, 104.918 px/m, with 352 × 352 transparent frames and a `[176,272]` origin. These checks and the [motion sheet](../../../../../../../local/company-of-unlikely-heroes/wizard-fitted/motion-sheet.png) are review evidence, not game playback or acceptance.

SHA-256 of the reviewed files:

- Approved fitted actions: `c00126258b0a893de3862d95e3c599446586d737ab025321f27e64853ff1e2c7`
- Original native master, unchanged: `5776143ed740e3cb924535ab267bad1e49a41753651c89223d812e36a65eaf24`
- Packaged Wizard atlas used for the two reused poses: `8a83fca0602f0a3c263408dc46f62d18fc970a525a5de35e2c160bae44044ea1`
- Board-scale motion sheet: `4a195628c99f686e3c2018ee4206b3695b255be29871322cc8974003378661c6`
