# Captain model

`captain`, xmy.9, for Barnaby’s Order of Last Resort. The approved reference is [Sheet 02](../../concepts/non-hero-cast/02-shield-wall-and-captain.png), SHA-256 `5815d7caae1b7b15d8bdab9b8ccdddb3dfb7dbc2a1000c5d08542dfa9728d21c`. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Editable source](captain-candidate.blend), SHA-256 `9b0b921dd1d914965832df32dc6f1960c5acaa467008da37d05ff8476f7d1f9b`, was made in Blender 5.2.2 LTS, `d13f752e3b9c`. It faces −Y, +Z up, with its origin at the ground anchor. The neutral body including the feather but excluding the baton spans 1.803 × 0.555 × 2.049 m. There are 23 bones, 167 mesh objects and 22 procedural materials. The high gold coat facing, long tails, quill and broad tricorne separate him from the grunt without relying only on the navy coat.

In the Action Editor, select `Captain_Rig` and choose an action prefixed `Captain |`. The saved frame is Ready F1. Neutral T uses the actual bind. The rig has editable FK keys at 24 fps, a bone for each coat tail and four separately keyed fingers on the gesturing hand. `Baton_Detachable` is mounted to `implement`.

| Action | Frames | Reason |
|---|---:|---|
| Neutral T / Ready | 1 / 1–33 | True bind and officious low carry. |
| Command | 1–28 | Open-hand flourish held from F12. Cue for the stock adjacent Grunt damage bonus (+1), not an active buff. Stock starting positions are diagonal, not in bonus range. |
| Back Away | 1–27 | Palm toward the threat, hips and feet retreat without facing travel. Use for the tagged tactical retreat, which requires an adjacent threat and usable space, and cannot repeat on the next round. |
| Advance | 1–27 | Distinct forward gait for ordinary `move`. |
| Fallback Strike | 1–25 | F11 baton strike, then recoils. Stock range 1, damage 1. Used when no eligible retreat is chosen and the strike is legal. |
| Hit / Defeat | 1–17 / 1–29 | Abrupt recoil; collapses into his own coat tails. |

## Reopen and review

From the repository root:

```bash
actor=captain
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/$actor"
out="$PWD/.lore/local/non-hero-xmy-7-10/review/$actor"
mkdir -p "$out"
export TMPDIR="$out" PYTHONDONTWRITEBYTECODE=1
for mode in check poses motion; do
  timeout 150 blender -b "$model/$actor-candidate.blend" -t 2 --python-exit-code 1 \
    --python "$model/review.py" -- "$mode" "$out/$mode" || break
done
ffmpeg -v error -threads 2 -framerate 12 -i "$out/motion/frame-%03d.png" \
  -vf 'scale=448:448,format=yuv420p' -c:v libx264 -threads 2 "$out/motion.mp4"
```

The reviewer uses the existing production camera and ink lighting without saving. It checks the bind, mesh edges, carried prop mount, fixed root, Ready return and floor/frame clearance. At 186 authored frame samples, soles stayed at least 3.6 mm above ground and the body and baton at least 42 px inside the 320 px capture by sampled vertices. This does not establish coat or prop clearance for arbitrary poses.

[Pose sheet](../../../../../../local/non-hero-xmy-7-10/final/captain/pose-sheet.png) · [Motion](../../../../../../local/non-hero-xmy-7-10/final/captain/motion-preview.mp4) · [Historical tactical comparison](../../../../../../local/non-hero-xmy-7-10/final/tactical-comparison.png). The hat, long coat and backward lean distinguish the Captain from the short-helmeted Grunt at 26.56 px/m; the palm is easier to read in motion than in the small still. In Godot, compare the retreat and ordinary advance on the stock board and verify that Command only appears where the adjacency rule applies.
