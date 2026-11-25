# Hobby Smith: equipped skills and reactions

[motion.blend](motion.blend) is an appendable Blender 5.2.2 library. It contains six editable Actions and one prop collection, not a duplicate performer. It fits `HobbySmith_Rig` from the [approved source](../README.md) at `5952801`. Source SHA-256: `a9d1113d0fb555accd4e0817890e3050d147bf45e2bf448a0fbe8f3b6e0da361`. Library SHA-256: `eabc37bbbcc11f999e5a342d125bdc1400426840d597ad73fa1aa2faff207db2`.

The Bonk and Acid petition plates guide the crooked staff and stoppered green vial. The actual drawings are renders of the Smith, not painted-over Healer or Mixologist drawings. The approved character and original four takes are unchanged. **These new motions are candidates for visual review.** Rebuilding them or packaging them in the game does not record acceptance.

| Clip | Cue at 24 fps | Duration |
| --- | --- | ---: |
| `bonk` | Raise the ash crook and knock outward at F15 (583 ms). Both boots stay planted. | 1208 ms |
| `acid` | Wind back with the green bottle. F16 is the last held drawing. Release at F18 (708 ms) and finish empty-handed. | 1417 ms |
| `acid_flask` | Only the bottle, in its evaluated F18 orientation. Its grip origin leaves `[92.713, -143.020]` atlas pixels from the actor's ground anchor. Runtime supplies flight. | 42 ms drawing |
| `hit` | A sharp backward flinch at F3 (83 ms); neither tool leaves the hand. | 750 ms |
| `down` | Catch the fall on a bent knee at F16 (625 ms). Settle into an alert crouch, head up. | 1125 ms |
| `recover` | Start on the identical Down hold, lift the head, push up, finish rising at F22 (875 ms) and return to Ready. | 1167 ms |
| `defeat` | Roll onto the back, land at F16 and relax the head at F24. The unsupported horizontal hold differs from the living crouch. | 1125 ms |

Quick Release removes a **wearer's** fitting, then the wearer moves. It has no Smith-only strike or throw. When the Smith himself moves, use the registered `pursue` drawing with gross travel removed. No seated Pull, unshielded Knight, or separate equipped idle variants are part of this set.

## Use the native library

Open a copy of the donor. Append the Actions and collection `Smith supplementary hand kit` from the library. Pick the relevant `Hobby Smith | …` Action on the rig. The crook and vial each have an unparented empty root at the grip. Copy `Fitting_Detachable`'s parent, parent type, parent bone, parent inverse and basis onto each root. Only the crook is visible during Bonk; only the vial is visible during Acid until release. Hide both original tool assemblies for these equipped skills; show them for Hit, Down, Recover and Defeat. The stock renderer applies these bindings automatically in memory.

[build_actions.py](build_actions.py) authors the poses in the donor's metre coordinates, bakes wrist and ankle targets to quaternion FK channels, and marks each event in the Action. It reuses the donor recipe's pose solver, not another actor's take. Each bone rotation can be edited. The defeat rolls about the pelvis and registers its evaluated mesh floor at every authored frame. [takes.json](takes.json) supplies the sampled source frames and exclusive stop for the stock cast packer.

## Rebuild and inspect

From the repository root with Blender 5.2.2 LTS, Python 3, ImageMagick 7 and Fontconfig:

```sh
model="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/hobby-smith"
supp="$model/supplementary"
donor="$model/hobby-smith-candidate.blend"
cast="games/company-of-unlikely-heroes/tools/cast"
mkdir -p .lore/local/smith-supplementary
out="$(mktemp -d "$PWD/.lore/local/smith-supplementary/review.XXXXXXXX")"
export TMPDIR="$out" MAGICK_TEMPORARY_PATH="$out" MAGICK_THREAD_LIMIT=1

# Independent regeneration. Never overwrite the approved model or pinned library.
blender -b "$donor" -t 4 --python-exit-code 1 -P "$supp/build_actions.py" -- "$out/rebuilt.blend"
blender -b "$donor" -t 4 --python-exit-code 1 -P "$supp/verify_actions.py" -- "$out/rebuilt.blend"

# This production route reopens the exact model and the pinned library.
python "$cast/bake_subset.py" "$out/atlas" blacksmith --threads 4
python "$cast/verify_cast.py" --assets "$out/atlas" blacksmith
python "$supp/proof.py" "$out/atlas" "$out/proof"
```

The six Actions export 45 samples including the isolated projectile. A separate regeneration produced byte-identical outlined PNGs for all 45 samples and identical timing/registration metadata. Blender container serialization itself is not a stable content fingerprint. The open-file check measures boot planting, native seams, the hand socket and evaluated floor. The closest point on the crouched trouser knee is 1.37 mm below the nominal plane (0.054 board pixels); other takes stay above it. The last Down drawing exactly matches the first Recover drawing. The final recovery returns to Ready.

[Board-size drawings](../../../../../../../local/smith-supplementary/motion-review/board-size.png) and [silent timing preview](../../../../../../../local/smith-supplementary/motion-review/motion.gif) show the new acting at the atlas display scale of 0.375, with review pauses between takes. The bottle is small by design; its green bulb and the Smith's extended arm carry the release. Flight, reaction effects, facing and target selection belong to in-game playback, not these source proofs.
