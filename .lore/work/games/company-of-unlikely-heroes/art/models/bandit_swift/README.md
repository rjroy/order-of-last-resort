# Swift Bandit: editable model

`bandit_swift`, `mind-garage-xmy.21`. Ronald approved [concept sheet 06](../../concepts/non-hero-cast/06-last-one-standing.png) for modeling (SHA-256 `f71417d10728115de4c5a7d0c7793224e92bc2e2a347edc3469eedd2cbef4843`). Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Swift Bandit source](bandit_swift.blend) · SHA-256 `b476b5b64e6367a41accdfeca06ebf40011920f677189c0ff7a1e74ec3d53262`. Blender 5.2.2 LTS, 24 bones, 110 mesh and 56 curve objects. Neutral body bounds without gear: 1.825 × 0.740 × 2.152 m. Native cast axes: facing −Y, +Z up, wearer’s right at −X. Weighted waist with independently animated braid and sash ends, a separately mounted knife, and a splayed free hand for balance.

The upright braid and slim doublet distinguish Swift from the other siblings. The knife darts outward for the existing melee contact at F7. `Quick Step` shows a low coil at F3, a long airy passing stride at F6, and a fast plant at F9, while the knife stays by the waist. It describes the added movement already granted as siblings fall; it neither advances the model’s root nor adds an attack.

| Action prefix: `Swift Bandit \|` | Source frames at 24 fps |
| --- | --- |
| Neutral T | 1 |
| Ready | 1–33 |
| Move | 1–17 |
| Melee | 1–18 |
| Quick Step | 1–16 |
| Hit | 1–15 |
| Defeat | 1–25 (held from F20) |

[Pose sheet](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/swift/pose-sheet.png) · [Motion preview](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/swift/motion-preview.mp4) · [Three-sibling tactical proof](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/bandit-siblings/final/tactical-siblings.png).

The shared review tool reopens the native file and does not change it. From the repository root:

```sh
models="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
out="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/bandit-swift-review"
blender -b "$models/bandit_swift/bandit_swift.blend" -t 4 --python-exit-code 1 \
  --python "$models/../model-tools/bandits/review_bandits.py" -- check "$out"
```

The check sampled 242 half-frames, including sole clearance of at least 0.65 mm, Quick Step’s longer airborne stride, fixed root, Ready returns, and held Defeat. The studio and tactical proofs are not Godot evidence.
