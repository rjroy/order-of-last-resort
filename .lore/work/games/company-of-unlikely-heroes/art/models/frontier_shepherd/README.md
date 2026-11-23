# Opposing Shepherd | model (.24)

`frontier_shepherd.blend` is the editable Blender 5.2.2 master. SHA-256: `8e88d1378b5cf2529ee13c3f4eea8a9777aba51e67c4c69f46eedb9adb5566fd`. Approved reference: [Sheet 07](../../concepts/non-hero-cast/07-great-sheep-escape.png), SHA-256 `7a4087d325f9adf2a13016d38651274148364349e4769f9774e3c3c73bd009c6`. No external model dependencies. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

`Shepherd_Rig` controls the gait, trunk, head and arms. `Shepherd | Ready`, `Shepherd | Pursuit step`, and `Shepherd | Scatter wave` correspond to holding, moving toward the target, and using the stock zero-damage wave on an adjacent civilian. The free hand rises twice and returns while the crook stays planted. The split apron follows the stepping hips. The wool cap, gray plaits, brass bells and stave identify a field worker, not a staff attacker. Fine finger spacing is visible on the sheet; at tactical size the high free-arm silhouette carries the wave.

16 manifold mesh parts, 5,105 faces, 11 bones. Rest dimensions 1.058 × 0.473 × 1.764 m, facing -Y, Z up. The crook has a separate named mesh weighted to the grip-side forearm. The rig’s ready action is active at frame 1.

To reproduce this actor's native frame study from the repository root:

```sh
d="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
e="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/shepherd-native-review"
mkdir -p "$e"
blender -b -t 4 "$d/frontier_shepherd/frontier_shepherd.blend" --python-exit-code 1 \
  -P "$d/../model-tools/field/review_field.py" -- "$e"
```

The shared composer can build the pair comparison once the Sheep source is also available. Native studies are not Godot evidence.
