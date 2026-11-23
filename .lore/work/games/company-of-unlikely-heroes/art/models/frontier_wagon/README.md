# Supply Wagon | The Last Wagon

`mind-garage-xmy.26`. The editable source is [frontier_wagon-candidate.blend](frontier_wagon-candidate.blend), SHA-256 `24168deae79baf9324fb933fd714f443f38ede0f3e38d2c621cc0bbabfd425fb`. Built in Blender 5.2.2 LTS against the bottom row of the [approved Last Wagon concept](../../concepts/non-hero-cast/08-last-wagon.png), exact SHA-256 `7f57ebb14852b0dd1a832c3783abd31d937a3d2babb1e23aac0e2ebb75a913c6`. No external textures or linked libraries. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The stock objective advances one tile only when the route is open and no living enemy is adjacent. Adjacent enemies stall it; destroying it loses the mission. The body and load have weight, but there's no driver, hit effect, explosion, or invented gameplay. Four spoked wheels, a bow-sided oak bed and a short draw pole carry a strapped water cask, a latched field chest and tied grain sacks.

## Edit the rig

Select `Wagon_Rig`, then choose an action in the Action Editor. The file opens in Ready at frame 1. Metres, Z up, rig-local −Y forward, turned 36° to show the near side and front in the cast view. The 22 controls separate the origin, chassis, axles, wheel carriers, spin, cargo and fore port breakaway. Cargo stays in the bed; the cask, strap, marker and sacks each react in pose. The damaged state is editable geometry and pose, not hidden replacement parts or destructive modifiers. Wheels and bed stay separately poseable.

| Native action, prefix `Wagon \| ` | Source frames at 24 fps | Art cue |
|---|---|---|
| Neutral | 1 | Intact rest/bind |
| Ready | 1–25 | Broadside hold; correct end state for stall |
| Advance | 1–33 | Weight takes up, wheels turn, body and cargo ride an axle bump |
| Stall | 1–27 | Wheels stay locked; cask and sacks pitch forward and then settle |
| Destroyed | 1–42 | Near fore axle parts, wheel tips, jagged board breaks away, body slumps toward the damaged side |

The advance is in place so a future runtime can own one-tile travel. All four wheels cover 173° in the take, about 0.98 m of equivalent travel at the 0.325 m tire radius. Advance ends with the wheels turned; the runtime must decide phase handling when returning to Ready. The almost symmetric spokes keep that seam small, but it is not a phase-continuous loop. The stalled drawing preserves the intact silhouette. The tow eye, strap bounce and wheel spin are much easier to judge in motion than in one small still.

Reopening the saved source confirmed five native actions, 249 meshes, 22 materials, and a Ready world extent of 1.971 × 2.107 × 1.277 m. All four wheels remain fixed throughout Stall. The near fore wheel moves away independently in Destroyed, and the bottom of each tire finishes within 2.7 cm of the common ground plane.

## Reproduce the review

Local review files are regenerated in `.lore/local/company-of-unlikely-heroes/non-hero-cast/last-wagon-models/`: `raider-pose-sheet.png`, `wagon-pose-sheet.png`, `raider-motion.mp4`, `wagon-motion.mp4`, and `last-wagon-tactical-proof.png`. The group composite uses the approved Last Wagon board painting, its registered 7 × 5 grid, the shipped Knight, Healer and Wizard ready crops, and the two reopened candidates at the cast display scale (roughly 26 px/m, 65 × 54 px cells). It stages advance, stall and loss; only the opening copies stock placements. It is not a Godot capture and does not test cue wiring, depth order, contact, or motion synchronization in combat.

Run from repository root. The review reads the same orthographic projection, anchor `[160,248]` and Standard ink-light setup from the cast baker. Model pose views use nearer square orthographic frames (2.52 m for the Raider, 2.68 m for the wider Wagon), 416 × 416, 12-sample CPU Cycles. Motion source drawings use the shared 320 × 320 capture and 6 samples; the 24 fps review movies hold sampled drawings for their source time and add brief holds between takes. Tactical PNGs apply the cast baker's two-pixel ink dilation. No script resaves the candidates.

```bash
m="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models"
p="$m/../model-tools/wagon"
o="$PWD/.lore/local/company-of-unlikely-heroes/non-hero-cast/last-wagon-models"
mkdir -p "$o"
export PYTHONDONTWRITEBYTECODE=1 MAGICK_THREAD_LIMIT=1
r="$m/frontier_wagon_raider/frontier_wagon_raider-candidate.blend"
w="$m/frontier_wagon/frontier_wagon-candidate.blend"
sha256sum "$r" "$w" > "$o/models.sha256"
timeout 90 blender -b -t 4 "$r" --python-exit-code 1 -P "$p/check_models.py"
timeout 90 blender -b -t 4 "$w" --python-exit-code 1 -P "$p/check_models.py"
for mode in poses motion; do
  timeout 320 blender -b -t 4 "$r" --python-exit-code 1 -P "$p/review_models.py" -- "$o/raider/$mode" "$mode"
  timeout 320 blender -b -t 4 "$w" --python-exit-code 1 -P "$p/review_models.py" -- "$o/wagon/$mode" "$mode"
done
timeout 90 python "$p/compose_review.py" "$o"
sha256sum -c "$o/models.sha256"
```

[Wagon builder](build_wagon.py) and [Raider builder](../frontier_wagon_raider/build_raider.py) create separate editable sources under Blender 5.2.2. Each takes a new absolute `.blend` path after `--` and refuses to overwrite one that exists. The accepted binaries are the reviewed versions; rebuilding is not a bid to reproduce their exact hashes.
