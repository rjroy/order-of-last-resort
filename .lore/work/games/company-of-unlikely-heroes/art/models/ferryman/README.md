# Ferryman | company_rescue

**Model approved by Ronald, November 22, 2026.** He approved the Ferryman presented in the linked sheet and motion preview. The accepted file is the exact reviewed binary, renamed from `ferryman-candidate.blend` without resaving. The embedded status records the earlier candidate stage; this approval record supersedes it. The editable master is [ferryman.blend](ferryman.blend), SHA-256 `6094dbf00ae9b19aa514b35abc939c472513553e11f0b2d3449fd2394dff6eea`. Built in Blender 5.2.2 LTS from the [exact approved concept](../../concepts/ferryman/README.md), bottom row only. No external image textures or linked libraries. The approval covers the model, not its in-game appearance.

[Pose sheet with actual-size samples](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/ferryman/ferryman-pose-sheet.png) · [silent motion preview](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/ferryman/ferryman-motion.mp4)

The blade stays down like a walking aid. The free hand tests the way ahead, then crosses the apron as the Ferryman catches his breath. Revisions from the initial study opened the blade/boot gap, widened the coat tails, gave the leading boot a clearer lift, lowered the grip to land the blade and brought the free hand across the chest instead of above the shoulder.

## Editing and performances

Select `Ferryman_Rig` and choose an action in the Action Editor. Opens at Ready, frame 1. Metres, Z up, −Y forward. Ready bounds including oar: 1.158 m wide × 0.748 m deep × 1.793 m high. The 18-bone FK rig has a neutral T bind, separate clavicles, individually articulated arms and legs, and the `oar_socket` hand child. `Oar_R_Detachable` groups the solid paddle and blade grain. Mesh groups preserve separate hat courses, sleeves, cuff folds, face details, coat, apron, footwear and pouch. These are posed garments, not simulated fabric.

| Action (all prefixed `Ferryman \| `) | 24 fps source frames |
|---|---|
| Neutral T | 1, bind posture, prop visible |
| Ready | 1–33, light breath and lookout; endpoints match |
| Cautious Step | 1–39, tests footing at 13, draws trailing boot through at 31, returns to Ready |
| Safe Bank | 1–44, hand to chest at 15, shoulders settle by 34; holds relief |
| Flinch | 1–23, startled recoil at 5, returns to Ready |
| Down | 1–31, folds behind passive oar; holds low |
| Recover | 1–24, picks up exactly from Down and returns to Ready |

## Reproduce the review from the master

From repository root (Blender, ImageMagick, Fontconfig, Python and FFmpeg):

```bash
m="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/ferryman"
o="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/ferryman"
mkdir -p "$o"
blend="$m/ferryman.blend"
sha256sum "$blend" > "$o/integrity.sha256"
timeout 90 blender -b -t 6 "$blend" --python-exit-code 1 -P "$m/check_ferryman.py"
timeout 150 blender -b -t 6 "$blend" --python-exit-code 1 -P "$m/review_ferryman.py" -- "$o/poses"
timeout 150 blender -b -t 6 "$blend" --python-exit-code 1 -P "$m/review_ferryman.py" -- "$o/motion" motion
python "$m/compose_review.py" "$o"
sha256sum -c "$o/integrity.sha256"
```

Reopened checks confirmed the neutral bind, seven actions, 212 meshes, 18 materials, fixed socket-to-prop transform on every action frame, sampled action transitions, and a 2.8 cm shoulder drop during relief. In the test-footing pose the lifted sole clears the ground by 16.7 cm while the other is within 2 mm. At Ready and Safe Bank the blade tip sits 1.4 cm above the scene origin, within 3 mm of the boot soles. In the low recovery pose the soles are about 3 cm higher than the oar tip. This is an in-place performance, not a foot-lock or cloth simulation for arbitrary edits.

The read-only review uses the roster's tactical camera rotation and ink lighting, a 2.48 m square orthographic frame, close inspection and 65 × 54 px crops at roughly 26 px/m. The MP4 is 43 sampled drawings at 8 fps (5.375 seconds). The brim, low paddle, rounded coat and lifted boot survive reduction. The hand-on-chest motion and settling shoulders are clearer in the motion preview than in a single miniature; rope, stitching and facial details need the larger views. These model previews contain no backdrop, adjacent actor or in-game response.


## Runtime derivative

[Packed Ferryman atlas](../../../../../../../games/company-of-unlikely-heroes/assets/cast/ferryman.png) · [Proof cropped from the delivered PNG](../../../../../../local/company-of-unlikely-heroes/non-hero-cast/ferryman/bake/ferryman-atlas-proof.png)

The cast baker used the approved master, common 320 × 320 capture, 12-sample CPU Cycles ink lighting, two-pixel ink dilation, fixed ground anchor `[160,248]` and three clear pixels around every packed rectangle. All clips use the same world scale. The proof's lower row uses the cast's 0.375 display scale. The source-frame samples below use 24 fps; stops are exclusive. Only Ready loops.

| Clip | Action | Samples | Stop |
|---|---|---|---:|
| `ready` | Ready | 1, 8, 15, 23, 29 | 33 |
| `travel` | Cautious Step | 1, 4, 7, 10, 13, 18, 21, 24, 28, 31, 35, 39 | 40 |
| `safe_bank` | Safe Bank | 1, 5, 9, 12, 15, 20, 23, 28, 34, 39, 44 | 45 |
| `flinch` | Flinch | 1, 3, 5, 9, 13, 17, 23 | 24 |
| `down` | Down | 1, 5, 10, 14, 19, 23, 31 | 32 |
| `recover` | Recover | 1, 5, 8, 12, 15, 20, 24 | 25 |

Blender 5.2.2 LTS and ImageMagick 7.1.2-34 produced 49 timed drawings in 46 unique rectangles. The 1216 × 1477 RGBA atlas is 1,321,451 bytes, SHA-256 `51c0b113013683e2efac415e5211e278d5a73348bceded7d6586d5f70aac50c7`. Two independent bakes from the master produced identical PNG bytes and actor registration. The shipped verifier checked the actor's rectangles, alpha gutters, frame times and source identity on the encoded atlas. The prop, lifted boot and test-the-water hand read in the atlas proof; the final shoulder drop is subtle at the lower size. This is not mission or runtime acceptance.

Once the designer registers the actor in the shared registry and manifest, reproduce/check from the repository root without touching the shipped atlas:

```bash
m="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/ferryman"
g="$PWD/games/company-of-unlikely-heroes"
o="$(mktemp -d /tmp/opencode/ferryman-bake.XXXXXX)"
MAGICK_THREAD_LIMIT=1 timeout 240 blender -b -t 6 --python-exit-code 1 \
  -P "$g/tools/cast/bake_actor.py" -- ferryman "$o"
python - "$g" "$o" <<'PYTHON'
from pathlib import Path
import json, sys
game, out = map(Path, sys.argv[1:])
sys.path.insert(0, str(game / 'tools'))
from bake_cast import pack
role = 'ferryman'
master = json.loads((game / 'tools/cast/masters.json').read_text())[role]
entry = pack(role, out, out, master)
assert entry == json.loads((game / 'assets/cast/manifest.json').read_text())['actors'][role]
assert (out / 'ferryman.png').read_bytes() == (game / 'assets/cast/ferryman.png').read_bytes()
PYTHON
python "$g/tools/cast/verify_cast.py"
```
