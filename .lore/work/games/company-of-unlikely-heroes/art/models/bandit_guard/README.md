# Guard Bandit: editable model

`bandit_guard`, `mind-garage-xmy.20`. Ronald approved [concept sheet 06](../../concepts/non-hero-cast/06-last-one-standing.png) for modeling (SHA-256 `f71417d10728115de4c5a7d0c7793224e92bc2e2a347edc3469eedd2cbef4843`). Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Guard Bandit source](bandit_guard.blend) · SHA-256 `a330ce3ea4ab07279a32bdedb227d3fb8c96755ca6a3e9cd9b13a5cafcf01803`. Blender 5.2.2 LTS, 24 bones, 124 mesh and 86 curve objects. Neutral body bounds without gear: 2.063 × 0.558 × 1.990 m. Native cast axes: facing −Y, +Z up, wearer’s right at −X. Weighted waist, separately mounted buckler and cudgel, thickened sheepskin collar and adjustable skirt ends.

A low hood and round sheepskin shoulders frame the buckler. The cudgel crosses open space to strike at F10; it is not a shield bash. In `Brace`, both boots stay planted as the buckler slides inward to protect the Guard’s own sternum at F8 and holds through F16. This reads as the existing capped reduction after a sibling falls, not as protecting a neighboring ally, striking, or creating a new status.

| Action prefix: `Guard Bandit \|` | Source frames at 24 fps |
| --- | --- |
| Neutral T | 1 |
| Ready | 1–33 |
| Move | 1–22 |
| Melee | 1–23 |
| Brace | 1–23 |
| Hit | 1–18 |
| Defeat | 1–25 (held from F20) |

[Pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/guard/pose-sheet.png) · [Motion preview](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/guard/motion-preview.mp4) · [Three-sibling tactical proof](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/tactical-siblings.png).

The shared review tool reopens the native file and does not change it. From the repository root:

```sh
models="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/bandit-guard-review"
blender -b "$models/bandit_guard/bandit_guard.blend" -t 4 --python-exit-code 1 \
  --python "$models/../model-tools/bandits/review_bandits.py" -- check "$out"
```

The check sampled 282 half-frames, including level floor clearance of at least 11.9 mm, unchanged foot anchors for Brace, fixed root, Ready returns, and held Defeat. The studio and tactical proofs are not Godot evidence.
