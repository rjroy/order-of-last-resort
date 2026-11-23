# War Drummer: model

For `mind-garage-xmy.22`, stock mission `hold_the_line`. The approved reference is [Frontier Specialists, sheet 03](../../concepts/non-hero-cast/03-frontier-specialists.png), SHA-256 `cbcd65041a721c851820c88abc30ababc9a92da1c47379987963f15c4d9adb26`. The accepted editable master is [frontier_war_drummer-pigment.blend](frontier_war_drummer-pigment.blend), SHA-256 `bce0e78136d3284b9d213731355402f7711e6c2c85b4064b10936157f0fa492e`. The [superseded original](superseded/frontier_war_drummer.blend), SHA-256 `f9e226c347a1d802926505a1608034e776f86c3c6dffb9a302649ff78ef979bf`, was retained for comparison only. The revision adds source-bound pigment without changing geometry or actions. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

A side-slung stave drum tilts its near skin toward the tactical camera. One stick rises, then contacts this head while the other stays lifted. Reserve arrival is a short weight shift and settle. There is no pursuit or generic melee action: the stock unit has only War Drum.

## Editing and review

Blender 5.2.2 LTS, metric, Z up, front toward -Y, 24 fps. Select the named armature and switch actions in the Action Editor. `Neutral` is the T-pose; the file opens at `Ready`. Props and costume pieces are separately editable bone-parented meshes. The root stays at the actor origin. Nonterminal actions return to Ready, while the terminal performance holds. The source is the native file, not an external build script.

Actions: `Neutral`, `Ready`, `Hit`, `Defeat`, `Reserve arrival`, `War drum pulse`.

Run from the repository root. Both scripts leave the source unchanged. Images and logs belong in disposable local evidence, not this directory.

```bash
actor=frontier_war_drummer
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/$actor"
out="$PWD/.lore/local/company-of-unlikely-heroes/specialist-native-recheck/$actor"
mkdir -p "$out/tmp"
TMPDIR="$out/tmp" OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=1 timeout 480 \
  blender --background "$model/$actor-pigment.blend" -t 2 --python-exit-code 1 \
  -P "$model/review.py" -- "$out" && python "$model/compose.py" "$out"
```

This native-material study is separate from the approved common finish. It renders 320 px transparent Cycles frames using the cast Euler angles `(1.150829196, 0, -0.435386419)`. The composer needs ImageMagick 7 and Liberation Sans. Open `pose-sheet.png` for the larger action study, `motion.gif` for the sampled signature timing, and `tactical.png` for a neutral-ground proof at approximately 39.3 pixels per metre. These are not in-game captures. Individual frames remain alongside the sheets. Append `--check-only` after `"$out"` to run geometry, animation and framing checks without rendering or composing.

Reopen checks: 16 bones, 146 mesh pieces, neutral bounds including held kit 2.048 × 1.058 × 1.861 m. All 109 integer frames fit the camera and stay above the ground plane. All mesh edges have two incident faces; intersecting fitted garment layers are intentional. No linked libraries or texture files. Contact measures 1.3 mm of nominal felt compression approximately 99 mm from the center of the 299 mm-radius head at frame 14. The model does not invent a visible projectile or target effect.
