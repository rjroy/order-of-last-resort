# Shieldbearer model

`shieldbearer`, xmy.7, for Barnaby’s Order of Last Resort. The approved reference is [Sheet 02](../../concepts/non-hero-cast/02-shield-wall-and-captain.png), SHA-256 `5815d7caae1b7b15d8bdab9b8ccdddb3dfb7dbc2a1000c5d08542dfa9728d21c`. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

[Editable source](shieldbearer-candidate.blend), SHA-256 `cf0967f444f5a1caf40b4e19b5c05b5ac76a2b209e0d814cffbfdcebbafaf515`, was made in Blender 5.2.2 LTS, `d13f752e3b9c`. It faces −Y, +Z up, with its origin at the ground anchor. The neutral body spans 1.935 × 0.576 × 1.903 m excluding the shield. There are 19 bones, 296 mesh objects and 26 procedural materials. The face stays visible beside the long red tower shield in Ready. The plates, dark scarf, stepped wood and sight slit come from the approved sheet.

In the Action Editor, select `Shieldbearer_Rig` and choose an action prefixed `Shieldbearer |`. The saved frame is Ready F1; the neutral T uses actual bind transforms. The torso and split hems have blended weights; plate and boot elements mostly follow their owning bones. The carried kit is grouped under `Tower_Shield_Detachable`, mounted to `implement`. The actions have baked editable FK keys at 24 fps, not a live IK control setup.

| Action | Frames | Reason |
|---|---:|---|
| Neutral T | 1 | Unposed source, shield hidden in the review still. |
| Ready | 1–33 | Planted with the shield slightly open. |
| Guard | 1–28 | Braces from F7 to show `adjacent_guard`; not a separate ability. Stock `shield_wall` Shieldbearers hold and prevent up to 1 damage each to an adjacent Archer. |
| Shield Bash | 1–26 | Compact ram, impact marker F9. The stock ability deals 1 damage at range 1; the animation implies no shove. Shield Wall's stock Hold behavior does not autonomously choose it. |
| Advance | 1–27 | Shield-heavy step for movement reuse, not an override of stock Hold. |
| Hit / Defeat | 1–17 / 1–29 | Recoil and reset; terminal knee buckle with the shield still held. |

## Reopen and review

From the repository root:

```bash
actor=shieldbearer
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

The reviewer imports the existing production cast camera and ink lighting without changing shared code or saving the model. It checks rig and prop mounts, mesh edges, floor clearance, common-camera framing, fixed root and Ready endpoints. At 160 authored frame samples, soles stayed at least 3.6 mm above ground, the shield at least 7.3 mm above ground, and body and kit at least 47 px inside the 320 px capture by sampled vertices. This is not a full collision or arbitrary-retargeting test.

[Pose sheet](../../../../../../local/non-hero-xmy-7-10/final/shieldbearer/pose-sheet.png) · [Motion](../../../../../../local/non-hero-xmy-7-10/final/shieldbearer/motion-preview.mp4) · [Shared tactical comparison](../../../../../../local/non-hero-xmy-7-10/final/tactical-comparison.png). The comparison uses 65 × 54 px cells and 26.56 px/m; compare Ready and Guard flanking the Archer in successive rows. The shield remains clear at this size; the sight slit and guard nuance are subtler. Test the protected and unprotected Archer beside the two Shieldbearers in the actual mission after visual approval.
