# Healer, Bad Bard and Mixologist: fitted motion

**Ronald approved all four source motions for game integration.** The [action library](remaining-fitted-actions.blend) contains four editable Blender Actions and no copied rigs, geometry, props, textures, or scenes. It adds poses to three accepted masters. The three masters remain byte-for-byte unchanged. Game playback, target feedback and the final mix are separate from source motion approval.

- [Combined tactical motion](../../../../../../local/company-of-unlikely-heroes/remaining-fitted/review-final/remaining-fitted-motion.gif)
- [Combined pose sheet](../../../../../../local/company-of-unlikely-heroes/remaining-fitted/review-final/remaining-fitted-poses.png)
- [Reopened action measurements](../../../../../../local/company-of-unlikely-heroes/remaining-fitted/verified-renders/proof.json)

The silent motion review uses the existing frontier ground, cast and pilot crate for context. Pawn travel is illustrative, at the stock 180 ms displacement timing. It is not Godot playback. Judge the tactical view first: the crook, bow sweep, double press, and tip should carry the actions before finger detail or outcome ink.

## Open and edit

Open a **copy** of the accepted [Healer](../healer/healer-blockout.blend), [Bard](../bard/bard-blockout.blend), or [Mixologist](../mixologist/mixologist-blockout.blend) master in Blender 5.2.2 LTS. Append its matching `Action` from `remaining-fitted-actions.blend`, assign it to the existing character rig in the Action Editor, and enable **Show Pose Markers**. All four use 24 fps and the master's coordinate space: metres, −Y forward, +Z up. They start at F1 and keep the root and boots planted. Keep a fake user on any unassigned appended take you want to save.

| Native Action | Registered clip ID | Key beat | Ready restored |
|---|---|---|---|
| `Healer \| Fitted \| Keep Your Head Down` | `healer/keep_your_head_down` | F13, 500 ms. Low crook tap, free hand lowers the target. | F28 |
| `Bard \| Fitted \| Pull` | `bard/fitted_pull` | F14, 542 ms. Reach at F9, then draw the bow hand in and back below the strings. | F29 |
| `Mixologist \| Fitted \| Send-Off` | `alchemist/send_off` | F13, 500 ms. Two offset palms extend; no cast bottle or recoil. | F28 |
| `Mixologist \| Fitted \| Hostile Dose` | `alchemist/hostile_dose` | F13, 500 ms. Amber vial rises, tips down in the grip, then withdraws. | F28 |

None of the takes adds actor translation. At contact, the cover crook is about 1.41 m high, below the ordinary Bonk contact of 1.52 m; it advances from the low set rather than dropping from head height. The Bard draws his right wrist 33 cm toward himself between F9 and F14. The Mixologist extends both wrists by roughly 19–21 cm between her F9 brace and the press. She tips the vial approximately 24° below horizontal and keeps it in the right hand through withdrawal. The bottle is small at game scale and no fluid is drawn. The quick one-handed extension and withdrawal matter more than spotting the bottle angle in a still.

## Presentation direction: all 14 conversions

Only the four motion IDs in the table above are new. Other performer clip IDs below already ship. Frame times are from action start at 24 fps. The stock Mixologist offer beat is 759.84 ms (48% of the 1,583 ms clip); keep it rather than retiming to a new sample. Sound names refer to the stock service unless labeled an audition. No sounds were generated or wired for this package.

| Wearer / equipped action | Fitted form | Performer clip, timing, sound, and recipient feedback |
|---|---|---|
| Healer / `healer_bonk` | Keep Your Head Down | **New** `healer/keep_your_head_down`, F13; try stock `dressing` at the tap, not the heavy `bonk` hit. Mark actual cover on the chosen ally and any Strong Swing recipients. No HP flash or taunt. |
| Healer / `healer_heal` | Doctor’s Orders | Reuse `healer/blast`, F12 / 458 ms. Its short outward palm and planted staff read better than the slower open `ally_heal`. Audition a short, dry air snap at the actual damage beat rather than the full 650 ms `blast` WAV. No mend, fake knockdown, or staff projectile. |
| Healer / `wizard_blast` (borrowed) | Mending Blast | Reuse `healer/blast` F12 / 458 ms toward another hero, or the visibly inward `healer/self_heal` F17 / 667 ms for self. Both use `heal` at the action beat. Mark actual HP gained, never hostile impact, knockdown or recoil. With no wounded hero, ordinary Blast remains an actual hostile-capable fallback with the stock `blast` sound. |
| Healer / `healer_field_dressing` | Unpick the Stitch | Reuse `healer/bonk`, F15 / 583 ms, with stock `bonk`. The clip already makes an adjacent staff contact. Show the resolved hit and no taunt. |
| Bard / `healing_sonnet` | Healing Sonnet, in tune | Reuse `bard/healing_sonnet`, F25 / 1,000 ms. Planted feet and long draw carry the Sonnet. Audition a resolved version of stock `sonnet`: keep its 390 ms length and try A–C♯–E in place of A–C–E♭. Mark the actual wounded hero healed, not a hostile hit. |
| Bard / `inspiring_melody` | Inspiring Melody, in tune | Reuse `bard/inspiring_melody` with stock `melody`; fitted beat **F13 / 500 ms**, the first high knee and bow reversal, instead of ordinary F25. Mark actual Inspiration, not laughter or a skipped turn. |
| Bard / `bard_take_the_stage` (reward) | Company Chorus | Reuse `bard/healing_sonnet`, F25 / 1,000 ms, as the ordinary reward does. Use the same retuned Sonnet motif plus the stock `stage` high A ending (520 ms total). Mark the soloist and each adjacent wounded hero who actually heals on that beat. No second song or enemy splash. |
| Bard / `knight_push` (borrowed) | Pull | **New** `bard/fitted_pull`, F14. Start the resolved one-cell slide on the inward draw. Audition a light inward rush from the early `magic_pull` layers, without its late recoil thud or a literal rope snap. No collision damage or own displacement. |
| Mixologist / `alchemist_acid` | Buffer Solution | Reuse `alchemist/acid` + `alchemist/acid_flask` for another recipient: launch 708 ms, arrival 1,008 ms. Play `dose` at arrival, not `potion` (the glass smash). For self, reuse close `alchemist/potion` with `dose` at its stock offer beat (~760 ms), never a returning flask. Mark only actual healing and any friendly Brittle Glass splash; a full-HP recipient can still react. |
| Mixologist / `alchemist_potion` | Bitter Medicine | **New** `alchemist/hostile_dose`, F13. Audition one dry glass tick and wet pat at contact, no flight, shatter, or impact off the caster. Signal actual damage and primary reaction, including at effective Long Ladle reach. No Brittle Glass splash. |
| Mixologist / `alchemist_etching_paste` | Sealing Paste | Reuse `alchemist/etching_paste` and `paste`, F13 / 500 ms. The planted low reach and retained vial sell application. Use for self or another friend, and mark only actual healing and friendly splash. Play the reaction only for the primary recipient. |
| Mixologist / `alchemist_plain_tonic` (reward) | Plain Solvent | Share `alchemist/hostile_dose` and the same tick/pat at F13. Show only the actual hit, no reaction, splash, or bottle write. |
| Mixologist / `alchemist_repeat_batch` (reward) | Counterbatch | No unique take. **Acid recipe:** `alchemist/acid` + `alchemist/acid_flask` at the same 708/1,008 ms beats, `dose` when healing, `potion` smash when damaging; self-heal uses `alchemist/potion`/`dose` at ~760 ms. **Potion recipe:** `alchemist/potion`/`dose` (~760 ms) to heal; new `alchemist/hostile_dose` with tick/pat (F13) to damage. **Paste recipe:** `alchemist/etching_paste`/`paste` F13, either polarity. Send the exact stored reaction to the different recipient, with actual splash only and no refill. |
| Mixologist / `wizard_pull` (borrowed) | Send-Off | **New** `alchemist/send_off`, F13. Play stock `shunt` instead of the inward `magic_pull`. Slide only the actual target away at the press, never the caster. Resisted: no shift. No collision hit, seated hold or recoil. |

Presentation should bind the committed form on the actual wearer. Recipe ID alone does not express the polarity of a converted dose, including an **ordinary Repeat Batch** that replays one. Use actual recipient events for HP, cover, Inspiration, displacement and reaction; an effect may be resisted or produce zero HP change. Keep stock ordinary fallbacks and stock ordinary Song Weaving echoes, with their separate beats. Keep previews silent.

Evidence: [runtime manifest](../../../../../../../games/company-of-unlikely-heroes/assets/cast/manifest.json), [stock action and learner beats](https://github.com/rjroy/order-of-last-resort/blob/6039f755da5ffc0c5fb2696c54833d74c5065299/games/company-of-unlikely-heroes/presentation/cast_playback.gd), [stock audio recipes and dispatch notes](../../../../../../../games/company-of-unlikely-heroes/assets/audio/scripted-combat-cues.md) and the accepted model records for [Healer](../healer/README.md), [Bard](../bard/README.md) and [Mixologist](../mixologist/README.md). The packaged `pull_upright` behavior is assembled from `alchemist/pull` drawings at load time and still retracts the hands, even without the seated finish. The fourth candidate keeps the stock amber bottle and grip, not a substitute prop.

## Reproduce and inspect

From the repository root with Blender 5.2.2 LTS, ImageMagick 7 and Fontconfig:

```sh
src="$PWD/.lore/work/games/company-of-unlikely-heroes/art/models/remaining-fitted"
out="$PWD/.lore/local/company-of-unlikely-heroes/remaining-fitted/reproduction"
mkdir -p "$out/tmp"
export TMPDIR="$out/tmp" MAGICK_TEMPORARY_PATH="$out/tmp" PYTHONDONTWRITEBYTECODE=1

blender -b -t 4 --factory-startup --python-exit-code 1 \
  --python "$src/build_actions.py" -- "$out/rebuilt.blend" --scratch "$out/build"
blender -b -t 6 --factory-startup --python-exit-code 1 \
  --python "$src/review_actions.py" -- "$src/remaining-fitted-actions.blend" "$out/renders"
python "$src/compose_review.py" "$out/renders" "$out/review"
```

Use a new reproduction directory for another run. `--check-only` on `review_actions.py` checks all poses without rendering. The render path uses the stock ink recipe with 12 CPU Cycles samples, 352 × 352 transparent captures at 104.918 px/m, and an origin at `[176,272]`; the consolidated images use the 65 × 54 cell stress size. These are pose tests, not whole-body collision simulation, a listening test, or live visual acceptance.

The exact candidate library SHA-256 is `024912f109deb844faad9a13a267abc80ea79a0b1fe92dc5330a24595d3d3fb9`. The three accepted input hashes are pinned in `build_actions.py`. Reopening checks all 222 half-frame samples and the crook and bow clearances against selected body and prop meshes. It also checks that the bottle stays full-size and in the hand through the tip. No new geometry, collision simulation, or review of final sound mix is implied.

## Stock atlas publication

`games/company-of-unlikely-heroes/tools/cast/supplements/{healer,bard,alchemist}.json` pins this library. Each role appends only its matching Actions to its own donor, then renders the same frames as the approved review. The stock cast recipe appends a separate shelf of drawings below each old PNG. It preserves the complete original top-left image, old frame rectangles, registrations and durations, including the stock projectile and pilot-strip reuse.

From the repository root, with `src`, `out`, `TMPDIR` and `MAGICK_TEMPORARY_PATH` set as above:

```sh
cast="games/company-of-unlikely-heroes/tools/cast"
assets="games/company-of-unlikely-heroes/assets/cast"
mkdir -p "$out/before"
git show "5952801:$assets/manifest.json" >"$out/before/manifest.json"
for role in healer bard alchemist; do
  git show "5952801:$assets/$role.png" >"$out/before/$role.png"
  python "$cast/bake_subset.py" "$out/stage/$role" "$role" --threads 4
  python "$cast/verify_cast.py" --assets "$out/stage/$role" "$role"
  python "$src/verify_publish.py" "$role" "$out/before" "$out/stage/$role" "$out/renders"
done
```

The independently staged set passed these checks: 16 cover drawings, 16 inward draws, 15 palm presses and 15 hostile dose drawings matched their registered review captures pixel for pixel. The three stock images and all prior clip metadata matched `5952801`. [Board-size contact sequences from the packed PNGs](../../../../../../local/group4-fitted-publish/packed-board-proof.png) show the crook lowering, the bow moving off the strings, and the two-handed press versus the one-handed amber tip. The small bottle reads most clearly in motion.
