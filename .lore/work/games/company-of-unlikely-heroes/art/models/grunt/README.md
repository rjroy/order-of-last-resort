# Grunt model

`grunt`, xmy.10, for Barnaby’s Order of Last Resort. The approved reference is [Sheet 02](../../concepts/non-hero-cast/02-shield-wall-and-captain.png), SHA-256 `5815d7caae1b7b15d8bdab9b8ccdddb3dfb7dbc2a1000c5d08542dfa9728d21c`. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Editable source](grunt-candidate.blend), SHA-256 `3dcf176a63e749f5ca8f5e9038765323a40afce0f31f4299ac55ebf529f706b9`, was made in Blender 5.2.2 LTS, `d13f752e3b9c`. It faces −Y, +Z up, with its origin at the ground anchor. The neutral body excluding the sword spans 1.829 × 0.542 × 1.861 m. There are 19 bones, 151 mesh objects and 23 procedural materials. The kettle brim, rolled sleeves and low-set short blade distinguish the Grunt from the Captain's raised brim, long coat, baton and open hand.

In the Action Editor, select `Grunt_Rig` and choose an action prefixed `Grunt |`. The saved frame is Ready F1; Neutral T uses the actual bind. The torso and split skirts have blended mesh weights; sleeves, fists, feet and sword are easy to edit separately. `Shortsword_Detachable` is mounted to `implement`. The editable FK keys are sampled at 24 fps.

| Action | Frames | Reason |
|---|---:|---|
| Neutral T / Ready | 1 / 1–33 | Actual bind; compact fighting wait. |
| Square Up | 1–22 | Brief look and set at F6, a cue for the original Captain adjacency bonus, not an action or self-buff. |
| Close Strike | 1–26 | Compact committed cut, impact marker F10. Stock `grunt_strike` deals 2 damage at range 1, with +1 from an adjacent living Captain. |
| Advance | 1–27 | Direct step, contrasting with the Captain's backward stance. |
| Hit / Defeat | 1–17 / 1–29 | Recoil and reset; terminal leg buckle with blade held low. |

## Reopen and review

From the repository root:

```bash
actor=grunt
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

The reviewer uses the existing production camera and ink light without saving. It checks the bind, mesh edges, sword socket, root, Ready return, and floor and frame clearance. At 154 authored frame samples, soles stayed at least 3.6 mm above ground and body and sword at least 46 px inside the 320 px capture by sampled vertices. This is not an arbitrary-pose or collision test.

[Pose sheet](../../../../../../local/non-hero-xmy-7-10/final/grunt/pose-sheet.png) · [Motion](../../../../../../local/non-hero-xmy-7-10/final/grunt/motion-preview.mp4) · [Shared tactical comparison](../../../../../../local/non-hero-xmy-7-10/final/tactical-comparison.png). The sword and kettle brim remain visible at 26.56 px/m, and the cut points outward unlike the Captain's backward lean. The Grunt’s glance toward the Captain is small at that size. After approval, check ordinary and augmented cuts in the actual mission, including when the Captain is diagonal or absent.
