# Bomber: model

For `mind-garage-xmy.11`, stock mission `explosive_situation`. The approved reference is [Frontier Specialists, sheet 03](../../concepts/non-hero-cast/03-frontier-specialists.png), SHA-256 `cbcd65041a721c851820c88abc30ababc9a92da1c47379987963f15c4d9adb26`. The accepted editable master is [bomber-pigment.blend](bomber-pigment.blend), SHA-256 `d1e366646d96277503a120ead851c08fabb5f1c7abaa9fe9fd4a67282e10ee13`. The [superseded original](superseded/bomber.blend), SHA-256 `73c39e6efa0d98795cd2a3da88699d15a1e32d56fac5f0e6f1e26551098323b2`, was retained for comparison only. The revision adds source-bound pigment without changing geometry or actions. Ronald approved this exact model and its common finish on 2026-11-22. See the [accepted roster and reproduction commands](../../concepts/non-hero-cast/accepted-roster.md). Runtime appearance is a separate judgment.

The round stitched pack sits high behind the beret. A stub hammer stays in the right fist for the close strike. Only the terminal action reveals the fan of ochre shock shards. The stumble settles into a seated hold; the payload is not thrown.

## Editing and review

Blender 5.2.2 LTS, metric, Z up, front toward -Y, 24 fps. Select the named armature and switch actions in the Action Editor. `Neutral` is the T-pose; the file opens at `Ready`. Props and costume pieces are separately editable bone-parented meshes. The root stays at the actor origin. Nonterminal actions return to Ready, while the terminal performance holds. The source is the native file, not an external build script.

Actions: `Neutral`, `Ready`, `Hit`, `Move`, `Close strike`, `Detonate on defeat`.

Run from the repository root. Both scripts leave the source unchanged. Images and logs belong in disposable local evidence, not this directory.

```bash
actor=bomber
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/$actor"
out="$PWD/.lore/local/company-of-unlikely-heroes/specialist-native-recheck/$actor"
mkdir -p "$out/tmp"
TMPDIR="$out/tmp" OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=1 timeout 480 \
  blender --background "$model/$actor-pigment.blend" -t 2 --python-exit-code 1 \
  -P "$model/review.py" -- "$out" && python "$model/compose.py" "$out"
```

This native-material study is separate from the approved common finish. It renders 320 px transparent Cycles frames using the cast Euler angles `(1.150829196, 0, -0.435386419)`. The composer needs ImageMagick 7 and Liberation Sans. Open `pose-sheet.png` for the larger action study, `motion.gif` for the sampled signature timing, and `tactical.png` for a neutral-ground proof at approximately 39.3 pixels per metre. These are not in-game captures. Individual frames remain alongside the sheets. Append `--check-only` after `"$out"` to run geometry, animation and framing checks without rendering or composing.

Reopen checks: 17 bones, 161 mesh pieces, neutral bounds including held kit 1.871 × 0.85 × 1.744 m. All 111 integer frames fit the camera and stay above the ground plane. All mesh edges have two incident faces; intersecting fitted garment layers are intentional. No linked libraries or texture files. The burst reads better in motion than from the settled pose alone.
