# Sheep | model (.23)

`frontier_sheep.blend` is the editable Blender 5.2.2 master for all three placements. Source SHA-256: `b99b310d4157a747b0a6f10bc25ce6e875ffc440bab852be2fbb8c290ca3dc91`. Approved concept: [Sheet 07](../../concepts/non-hero-cast/07-great-sheep-escape.png), SHA-256 `7a4087d325f9adf2a13016d38651274148364349e4769f9774e3c3c73bd009c6`. No external model dependencies. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The dark face and tapering cream locks distinguish the flock. Four upper/lower limb pairs, poll and individual ears move independently under `Sheep_Rig`. Actions use `Sheep | ` plus `Ready`, `Startle`, `Flee step`, `Pen settle`, or `Penned`. Startle anticipates a **committed** round-end flee, not the harmless wave. The bound is in place so a future consumer can translate the actor one cell. A sheep already in the east pen holds its tucked pose while the others move. `Pen settle` ends in `Penned`'s pose.

13 manifold mesh parts, 6,150 faces, 12 bones. Rest dimensions in rig space: 1.620 × 0.838 × 1.352 m. The locally +X-facing quadruped turns 44° toward -Y for the cast camera. Palette and layered wool are modeled; crop, paper and caption belong to review only.

## Reproduce both field models’ native studies

From repository root, run the following without changing either master:

```bash
d="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
e="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/sheep-field-review"
mkdir -p "$e"
for role in frontier_sheep frontier_shepherd; do
  timeout 240 blender -b -t 4 "$d/$role/$role.blend" --python-exit-code 1 -P "$d/../model-tools/field/review_field.py" -- "$e" || exit 1
done
python3 "$d/../model-tools/field/compose_field.py" "$e"
```

The review checks weights, bones' use via armature modifiers, manifold edges, exact action inventory and master hash stability, then samples actual saved actions using the shipped Cycles pigment and 320px cast projection. Inspect `frontier_sheep-poses.png`, `frontier_sheep-motion.gif`, `tactical-group.png` and `tactical-event-contrast.png` in the output directory. Group images are Blender-frame composites, not Godot evidence. Eye expression and ear lift are secondary at board scale; the tucked belly and airborne stride carry the read.
