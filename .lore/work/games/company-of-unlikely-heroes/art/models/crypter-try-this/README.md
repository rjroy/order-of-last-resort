# Friendly Crypter: Try This performance candidates

**Editable source takes approved.** This package covers the Crypter and the existing Skeleton and Zombie only. It uses the accepted cast designs and approved fitted actions, not a new concept. The exact reviewed Blender sources are preserved here. Full-role board atlases are staged separately; this package does not publish them or change gameplay. Other characters in the review are read-only stock context, not new work.

## Review the five beats

View the [tactical sheet](../../../../../../local/company-of-unlikely-heroes/crypter-try-this/tactical-sheet.png) and [silent motion](../../../../../../local/company-of-unlikely-heroes/crypter-try-this/tactical-motion.mp4) at 100%. Frames use the stock cast's three-quarter projection (104.92 source px/m), manifest scale (0.375), foot registration, facing convention, and the smallest five-row board fit (315 px over 468 logical px; about 65 × 54 px per tile and 26.5 screen px/m). Grid, highlights and beat captions are offline review aids. This is a pose and timing study, not live forecast or commit playback.

| Ability | Reuse or new | Read and handoff |
|---|---|---|
| Recall Skeleton | New Crypter `Try This \| recall` and Skeleton `Try This \| recall_tuck`; stock Skeleton Ready at rest. | The low bell stays still while the free hand reaches then curls in. Keep exactly one Skeleton art instance keyed to the existing `target_id`. Cut from `from_position` to `position` at the inward beat; no travel through intervening cells and no emergence. The tuck opens into normal Ready, not Wave or Don't Go. Keep the same identity, HP, status marks, stored order and initiative. An ordinary summon fallback still uses its stock high ring and new-actor semantics. |
| Play Dead | New Crypter `Try This \| hush` and Zombie `Try This \| play_dead`; reuse the original opponent’s terminal corpse pose, not its falling performance. | A low hand lowers instead of the stock kneeling, palm-up Raise. The Zombie folds down deliberately and stays down; at the terminal marker exchange the temporary Zombie picture (`summon_id`) for the original dead opponent (`target_id`) on the same cell. Use the source opponent's terminal static body (Goblin is the stock example here). If the only defeat clip is a blast, skip it entirely and use that actor's existing inert corpse fallback. Never fire a death tag, hit flash, blast, flower release, wake, HP change cue or second corpse. The original consumes normally if raised again. |
| Dinner Bell | Reuse stock owner `grave_bell`, checked against atlas and `training_poses.py`. | One chime, then exactly the actual forced move result for the recorded target. Review shows one open step toward the Crypter. Don't reuse Grave Bell's movement-block presentation, or play a response for a blocked result. No new minion clip. |
| Stay Close to That One | New Crypter `Try This \| stay_close`; reuse both minions' Ready, normal movement and legal greetings on their own turns. | One open-hand indication of the selected living hero, not the stock hostile point, attack or greeting. The summons stay put during the Crypter's gesture. On later ordered turns use ordinary displacement and adjacent stop, and let only an actual greeting event select a greeting performance. |
| Inspiring Melody, in tune | Reuse stock Crypter `melody`, checked against atlas and `learner_poses.py`. | The Crypter plays a short bell phrase with their own handbell; no donor Bard, fiddle, or laughter. Mark only the actual Inspired recipient when the phrase resolves, including self if selected. No minion response. Dinner Bell is one accent; Melody articulates several. |

The sheet compares stock raises and nomination precisely because the same tools must not imply an ordinary summon, resurrection, or hostile designation. At this scale the large arm path and paired staging carry more information than individual fingers. The changed recipient cue is essential to telling borrowed in-tune Melody apart from the same owner's ordinary borrowed performance.

## Sources and recipe

The approved [Crypter](necromancer-try-this.blend), [Skeleton](skeleton-try-this.blend) and [Zombie](zombie-try-this.blend) `.blend` files are exact copies of the reviewed sources. Actions are on `Necromancer_Rig`, `Skeleton_Rig` and `Zombie_Rig` in the Action Editor. Each opens at the stock Ready pose. The accepted original models remain untouched and are pinned in `tools/cast/masters.json`; the approved scene copies are pinned in `tools/cast/supplements/{necromancer,skeleton,zombie}.json`. Stock comparison frames are cropped directly from the current manifest and packaged atlas PNGs. The fitting design is documented in [Hobby Smith design](../../../notes/hobby-smith-design.md); `rules/fitted_summons.gd` supplies the current event identity/position contract.

For the production board atlases, bake the approved sources, not a regeneration of the takes. Starting at the repository root:

```bash
set -e
game="$PWD/games/company-of-unlikely-heroes"
src="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/crypter-try-this"
scratch="$PWD/.lore/local/company-of-unlikely-heroes"
out="$(mktemp -d "$scratch/crypter-cast-repro.XXXXXX")"
mkdir "$out/tmp"
TMPDIR="$out/tmp" timeout 420 python3 "$game/tools/cast/bake_subset.py" \
    "$out/stage" necromancer skeleton zombie --threads 4
python3 "$game/tools/cast/verify_cast.py" --assets "$out/stage" necromancer skeleton zombie
python3 "$src/verify_production.py" "$out/stage"
```

`stage` contains all stock and approved addition clips for each role in `necromancer.png`, `skeleton.png` and `zombie.png`, with their entries in a local partial `manifest.json`. The source uses metres, +Z up and −Y forward. The board bake uses the stock three-quarter projection and registration (320 × 320 capture, [160, 248] origin before cropping). Playback can bind these frames without posing or resaving the approved source. Times below are rounded offsets from the named clip's F1 at 24 fps:

| Actor / clip | Key frame (offset) | Playback contract |
|---|---:|---|
| `necromancer/recall` | 17 (667 ms) | Transfer the existing Skeleton to its resolve cell; use `skeleton/recall_tuck` from its F1 at the new cell. F17 of the tuck returns exactly to stock Ready. |
| `necromancer/hush` | 11 (417 ms) | Cue `zombie/play_dead` at F1. Hold the original Zombie at its resolve cell until the recipient's terminal F26 handoff (1,042 ms after Zombie F1), then show the original corpse on that cell. |
| `necromancer/stay_close` | 15 (583 ms) | Indicate the resolved friendly rally target. Do not play a minion greeting on this marker. |
| `necromancer/grave_bell` | 12 (458 ms) | Existing owner ring for Dinner Bell. |
| `necromancer/melody` | 13 (500 ms) | Existing owner phrase for borrowed in-tune Melody. |

The staged delivery is in `.lore/local/company-of-unlikely-heroes/crypter-try-this/production/`. The shared verifier and the family verifier both passed: 142 stock frames keep their original metadata and decoded RGBA pixels, and 60 new samples match their clip timing and padding. Each of the five new cue/terminal frames also matched its registered pixel crop from the separately reopened approved source.

To reproduce the offline approval sheet from a fresh scratch folder, use the commands below. Regenerated `.blend` bytes may differ from the approved files even when pose output is identical. Blender 5.2.2 LTS, ImageMagick, Fontconfig, Python 3 and FFmpeg are used; no display, network, plugins or installs are needed.

```bash
set -e
src="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/crypter-try-this"
scratch="$PWD/.lore/local/company-of-unlikely-heroes"
out="$(mktemp -d "$scratch/crypter-try-this-repro.XXXXXX")"
mkdir "$out/frames"
for role in necromancer skeleton zombie; do
    timeout 180 blender --background -t 4 --python-exit-code 1 \
        --python "$src/build.py" -- "$role" "$out/$role-candidate.blend" >"$out/build-$role.log" 2>&1
    timeout 180 blender --background -t 4 --python-exit-code 1 \
        --python "$src/review.py" -- "$role" "$out/$role-candidate.blend" "$out/frames" >"$out/review-$role.log" 2>&1
done
timeout 90 python "$src/package_review.py" "$out"
```

`score.py` is the editable choreography script. `build.py` saves keyed FK takes on copies, no live IK, NLA or geometry edits. `review.py` reopens the exact copies, compares all original native poses at whole frames and bone rest/object attachment inventories, checks candidate markers and planted feet/terminal lowering, and renders read-only with the project's stock bake camera, ink light and contour pass. `package_review.py` checks the composited poses for framing and decodes the silent film. The pose checks are targeted, not exhaustive cloth or joint collision testing.

Reopen results: 432 protected native poses match across three rigs. An independent rebuild produced byte-identical final sheet and film. In Play Dead the Zombie's evaluated silhouette lowers from 1.804 m to 0.587 m and keeps ground contact through the sampled half-frames. The tucked daisy remains in the hand through the last frame. At board size the Recall reach and return read more clearly than the wrist mechanics, and the final corpse exchange reads as an intentional cut, not a continuous anatomical transformation. The Stay Close gesture is subtle on its own; preserve the actual friendly hero target cue in any separately approved playback.
