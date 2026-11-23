# Enemy Healer: model

For `mind-garage-xmy.12`, stock mission `unfortunate_healer`. The approved reference is [Frontier Specialists, sheet 03](../../concepts/non-hero-cast/03-frontier-specialists.png), SHA-256 `cbcd65041a721c851820c88abc30ababc9a92da1c47379987963f15c4d9adb26`. The accepted editable master is [enemy_healer-pigment.blend](enemy_healer-pigment.blend), SHA-256 `3ec1be65fce33a6ea42e11944a347a8b0df93f07127a21022f333a1dc1ef7dee`. The [superseded original](superseded/enemy_healer.blend), SHA-256 `c87c9c43e1a722d97f9551511db995be91f6dc593291029f1581d9f581de1591`, was retained for comparison only. The revision adds source-bound pigment without changing geometry or actions. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

A balding bonesetter in rolled sleeves, not a robed spellcaster. The left arm offers a short, loose dressing to the ally. The right swings the wooden club down for Bonk. The roll is an acting prop, not a visual counter for the two stock charges.

## Editing and review

Blender 5.2.2 LTS, metric, Z up, front toward -Y, 24 fps. Select the named armature and switch actions in the Action Editor. `Neutral` is the T-pose; the file opens at `Ready`. Props and costume pieces are separately editable bone-parented meshes. The root stays at the actor origin. Nonterminal actions return to Ready, while the terminal performance holds. The source is the native file, not an external build script.

Actions: `Neutral`, `Ready`, `Hit`, `Defeat`, `Move`, `Field dressing`, `Bonk`.

Run from the repository root. Both scripts leave the source unchanged. Images and logs belong in disposable local evidence, not this directory.

```bash
actor=enemy_healer
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/$actor"
out="$PWD/.lore/local/company-of-unlikely-heroes/specialist-native-recheck/$actor"
mkdir -p "$out/tmp"
TMPDIR="$out/tmp" OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=1 timeout 480 \
  blender --background "$model/$actor-pigment.blend" -t 2 --python-exit-code 1 \
  -P "$model/review.py" -- "$out" && python "$model/compose.py" "$out"
```

This native-material study is separate from the approved common finish. It renders 320 px transparent Cycles frames using the cast Euler angles `(1.150829196, 0, -0.435386419)`. The composer needs ImageMagick 7 and Liberation Sans. Open `pose-sheet.png` for the larger action study, `motion.gif` for the sampled signature timing, and `tactical.png` for a neutral-ground proof at approximately 39.3 pixels per metre. These are not in-game captures. Individual frames remain alongside the sheets. Append `--check-only` after `"$out"` to run geometry, animation and framing checks without rendering or composing.

Reopen checks: 16 bones, 85 mesh pieces, neutral bounds including held kit 2.212 × 0.557 × 1.949 m. All 141 integer frames fit the camera and stay above the ground plane. All mesh edges have two incident faces; intersecting fitted garment layers are intentional. No linked libraries or texture files. At small size, the white dressing and the direction of the reach carry the heal more clearly than the pocket detail.
