# Wizard: Blast and Pull recoil

`wizard-blockout.blend` is the accepted editable Blender 5.2.2 LTS Wizard model for *Barnaby’s Order of Last Resort*. Ronald approved the [concept](../../concepts/wizard/wizard-blast-and-recoil.png) and then accepted the model shown in the [rendered pose sheet](../../../../../../local/company-of-unlikely-heroes/wizard-blockout/contact-sheet.png) and [motion preview](../../../../../../local/company-of-unlikely-heroes/wizard-blockout/blast-and-pull.webp) on 2026-11-21. Accepted `.blend` SHA-256: `5776143ed740e3cb924535ab267bad1e49a41753651c89223d812e36a65eaf24`. Blast plants and releases; Pull draws inward before the Wizard slips and lands seated. This is roster model acceptance, not Godot integration.

## Play or edit

The file opens on frame 1 of `Wizard | Blast`, with `Wizard_Rig` selected. In the **Action Editor**, choose an action from the dropdown and start at frame 1. Action markers identify the beats; use **Show Pose Markers** if they are hidden. The separate Blast scene markers describe the default take only. Blast and Pull are independent 40-frame actions at 24 fps; no NLA track or external file is required.

| Action | Named beats |
| --- | --- |
| `Wizard \| Neutral T` | **1** actual armature rest |
| `Wizard \| Ready` | **1–12** common ready hold |
| `Wizard \| Blast` | **7** gather, **11** lead boot plants, **14** palm out, **17** release hold, **24** retract, **29** step back, **34** ready restored, **40** end |
| `Wizard \| Pull` | **8** take hold, **13** draw both hands in with feet still planted, **16** stance breaks, **19** both feet slip ahead, **24** seat lands, **33** settle, **40** end seated |

Enable viewport overlays to see the rig. Limb poses are baked to FK channels; there are no live IK controls. Each finger has two bones; reveal `Fingers`, `Face` or `Secondary` to adjust hand shape, expression, hat tip or hair. The angled crown is skinned; the rest is editable bone-parented blockout geometry. The split coat leaves and ledger have their own bones. To detach the entire ledger, select `Ledger_R_Detachable` in Object Mode and use **Clear Parent and Keep Transformation**. Do not unparent its parts individually. The review set is in its own collection.

## Reopen and inspect

From the repository root:

```bash
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/wizard"
out="$PWD/.lore/local/company-of-unlikely-heroes/wizard-blockout"
blender --background "$model/wizard-blockout.blend" --threads 12 \
  --python-exit-code 1 --python "$model/review_wizard.py" -- "$out/renders" --motion
bash "$model/make_review_previews.sh" "$out"
```

Use `--check-only` after Blender’s `--` for the read-only checks alone. The pose sheet uses the [Knight](../knight/README.md) and [Healer](../healer/README.md) conventions: metres, −Y forward, +Z up, wearer’s right at −X, and the same 2.47 m orthographic camera scale and angle for every acting frame. The frame is recentered for the Wizard’s motion; Neutral T uses a separate front camera. ImageMagick, Fontconfig and FFmpeg compose the review files and are not model dependencies.

- [Pose sheet](../../../../../../local/company-of-unlikely-heroes/wizard-blockout/contact-sheet.png)
- [Blast and Pull side-by-side motion](../../../../../../local/company-of-unlikely-heroes/wizard-blockout/blast-and-pull.webp)

Candidate SHA-256: `5776143ed740e3cb924535ab267bad1e49a41753651c89223d812e36a65eaf24`. Neutral bounds including hat and ledger: 1.999 × 0.557 × 2.122 m. The reopened file has 52 bones and 211 editable mesh/curve objects. Sampling all 92 playback frames verified the shared ready pose, Blast’s return, foot plants (less than 0.001 mm anchor drift), inward tug before the slip, and the lowered seat at frame 24. The lowest sampled pelvis geometry at landing was 6 mm above the review ground (rounded). These checks are not a cloth or whole-body collision simulation.

Pull ends on the ground; the jump to Ready on preview replay is a cut, not a recovery animation. The 65 × 54 px samples isolate the actor: the lunge and knockdown carry the contrast, while small grip and facial changes are less clear. This is a Blender pose and timing study, not gameplay proof. No target, magical effects, production skinning, runtime export or Godot integration is included. The next useful test, if authorized, is an unlabeled board comparison with the same target in both takes: can the player tell what the Wizard did before the target’s response makes it obvious?
