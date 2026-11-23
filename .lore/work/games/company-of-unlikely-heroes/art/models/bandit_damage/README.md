# Fierce Bandit: editable model

`bandit_damage`, `mind-garage-xmy.19`. Ronald approved [concept sheet 06](../../concepts/non-hero-cast/06-last-one-standing.png) for modeling. Its SHA-256 is `f71417d10728115de4c5a7d0c7793224e92bc2e2a347edc3469eedd2cbef4843`. The exact local approval input and the maintained concept copy matched byte for byte. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Fierce Bandit source](bandit_damage.blend) · SHA-256 `24a4ad58905757af3206ecf6738a761143bf7661db21fd29c8a05ce85b9c602e`. Blender 5.2.2 LTS, 24 bones, 115 mesh and 85 curve objects. Neutral body bounds without gear: 1.975 × 0.592 × 2.046 m. Facing −Y, +Z up, wearer’s right at −X. The chest and pelvis deform the doublet together; the other pieces attach to rig segments. The axe is editable separately in the mounted gear collection, with both hands reaching for the same haft. The mantle, hair and two skirt ends have separate bones.

The broad axe, torn mantle and asymmetrical forward lean identify Fierce. `Melee` loads at F6, contacts at F10, and recovers to Ready at F24. `Harder Strike` loads at F8, contacts at F12, carries the weight farther forward and lower through F17, and recovers by F31. This is an alternate performance of the existing adjacent attack after a sibling falls, not a new ability or a larger strike range.

| Action prefix: `Fierce Bandit \|` | Source frames at 24 fps |
| --- | --- |
| Neutral T | 1 |
| Ready | 1–33 |
| Move | 1–20 |
| Melee | 1–24 |
| Harder Strike | 1–31 |
| Hit | 1–17 |
| Defeat | 1–25 (held from F20) |

[Pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/damage/pose-sheet.png) · [Motion preview](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/damage/motion-preview.mp4) · [Three-sibling tactical proof](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/tactical-siblings.png).

## Reopen and review the siblings

The `.blend` files are the masters. They open on Ready; select the actor’s rig and choose its named action in **Dope Sheet → Action Editor**. Change the playback end to the selected action’s end as needed. Actions contain half-frame FK keys and named markers at the acting beats. Movement is in place by design; board displacement belongs to Godot.

From the repository root, run the shared read-only review recipe. The proof uses a neutral-lit studio and a reverse view, plus a separate cast-camera set with fixed registration. The 12 fps MP4 samples each actor’s actual animated takes and labels the cuts. The tactical sample scales the same camera to 26.55 px/m, with a flat-color row to test silhouette without costume color. It is not in-game evidence.

```bash
models="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
tool="$models/../model-tools/bandits"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/review"
export PYTHONDONTWRITEBYTECODE=1
for mode in check proof motion; do
  blender -b "$models/bandit_damage/bandit_damage.blend" -t 4 --python-exit-code 1 \
    --python "$tool/review_bandits.py" -- "$mode" "$out/damage" || exit 1
done
```

Once all siblings are present, review each similarly and run `python "$tool/compose_bandit_review.py" "$out"` for the group proof. The Blender-only authoring scripts `build.py` and `perform.py` are shared by the three models. If reconstructing, call the builder with the desired runtime ID and a new absolute destination; the builder refuses to replace a file. The checked `.blend` hash identifies the accepted version, not a promise of byte-identical saves.

```bash
mkdir -p "$out"
blender -b -t 4 --factory-startup --python-exit-code 1 \
  --python "$tool/build.py" -- bandit_damage "$out/reconstructed-bandit_damage.blend"
```

The read-only check sampled 294 half-frames across all six acting takes. It checked the T-rest, armature and mounts, source mesh topology, fixed root, Ready returns, and held Defeat. Across those samples the boot soles cleared the floor by at least 12.0 mm and the second axe-hand mount stayed within 0.001 mm of its intended position on the haft. Reconstruction from the packaged scripts reproduced the measured checks for all three siblings. The pose sheets and tactical proof decoded, the three videos fully decoded, and selected decoded frames were inspected. The proofs distinguish the siblings by axe and stoop, buckler and hood, or braid and long stride. At small size, the knife and fine tailoring do not resolve reliably, and the Guard’s inward buckler motion is clearer in the clip than in one frame. These checks cover the authored takes, not arbitrary retargeted poses or every possible mesh intersection. No runtime publish, cue mapping, or stock mission validation was attempted.
