---
title: Hobby Smith verification
date: 2026-11-24
status: completed
tags: [hobby-smith, try-this, playback, verification]
related: [.lore/work/games/company-of-unlikely-heroes/notes/hobby-smith-design.md]
---

# Hobby Smith verification

`olr-12b.6` · [Approved design](hobby-smith-design.md) · [Local play instructions](../../../../../games/company-of-unlikely-heroes/README.md)

The saved machine evidence covers all **25 native forms and seven borrowed wielders** in the actual battle scene. Ronald approved the source model, supplemental sheet, petition and reward illustrations, and wearer motion libraries for integration (`olr-12b.5`, 05:46 comment). His earlier positive audition was for two source clips only. Neither approval is a human verdict on final in-game legibility or audibility. The automated evidence below does not supply that verdict.

## Evidence

- **Forecast and commit:** `olr-12b.1` and `.3` recorded the rules and initiative checks. The live visual driver staged each action through the game's controls in a controlled fixture, checked that the preview left the board unchanged and silent (no requests, zero Master PCM), and checked that Commit matched the forecast. These fixtures use the real battle scene, not all unmodified stock openings. The separate stock `hold_the_line` launch in the game guide was headlessly checked: the Smith fits the Knight, Pull takes the Bruiser G3 → F3, and clearing the command restores fitted Guard.
- **Actual draws:** `.lore/local/smith-live-visual.zBadWM/run.log` passes. Its `evidence/<case>.png` contains game viewport crops and its matching JSON records what the renderer actually drew at the markers, not just what the scheduler queued. For example, Pull shows the same Shieldbearer at the landing with shift feedback; Lend a Shield shows a detached shield in flight and guard feedback at the recipient; Recall shows the same skeleton's `recall_tuck` at its new cell; Play Dead shows the zombie pose and handoff to the original grunt corpse. The Rally marks the chosen ally without giving the skeleton an extra action. Ordinary Blast fallback actually damages the Smith instead of playing a heal.
- **Actual audio:** `.lore/local/smith-remaining30-live.EWPymA/{live.log,summary.csv,pcm-audit.csv}` records 23 native and seven borrowed cases on Wayland/PulseAudio at 44.1 kHz. All 30 previews made no requests; both preview WAVs per case were digitally silent. Every committed Master and matched wearer stem was nonzero; stem peaks were 333–3746 PCM16. The test bus routes the actual playing service voice by wearer, source ability, and phase, excluding unrelated actions and reactions. It is upstream of the physical device and routes just after `play()`, so the stem may miss a short onset and is not a sample-perfect isolated master.
- **Two earlier exceptions:** `.lore/local/smith-live-conversions.eFl46v/captures/` has zero-peak previews and committed **Master only** for `knight_push` (`fitted_empty_press`, peak 1159) and `alchemist_acid` (`dose`, peak 3753). Both have an identified wearer request, but the mixed audio includes other requests and there is no isolated wearer stem for either. Sound requests alone are not audio evidence: the earlier headless negative control `.lore/local/smith-final.jbSLBB/run.log` matched 32 converted impact beats and zero matching converted requests before fitted sound wiring.

## Native and borrowed matrix

Native case ID equals the source ability ID. The clip column is the clip actually drawn by the wearer at impact in `zBadWM`; a reused clip name does not mean the ordinary rules ran. The audio column identifies the committed cue and peak in the `EWPymA` **wearer stem**, except the two marked Master-only rows. The table does not use the five later Master peaks in place of stem values.

| Native source | Effective form | Wearer / drawn clip | Wearer cue / PCM16 peak |
|---|---|---|---|
| `knight_push` | `fitted_pull` | Knight / `fitted_pull` | `fitted_empty_press` / Master only |
| `knight_aura` | `clear_the_floor` | Knight / `clear_the_floor` | `fitted_floor_sweep` / 1720 |
| `healer_bonk` | `keep_your_head_down` | Healer / `keep_your_head_down` | `dressing` / 333 |
| `healer_heal` | `doctors_orders` | Healer / `blast` | `fitted_doctor_snap` / 1313 |
| `wizard_blast` | `mending_blast` | Caster / `blast` | `fitted_mend_outward` / 1130 |
| `wizard_pull` | `send_off` | Caster / `send_off` | `shunt` / 827 |
| `alchemist_acid` | `buffer_solution` | Mixologist / `acid` | `dose` / Master only |
| `alchemist_potion` | `bitter_medicine` | Mixologist / `hostile_dose` | `fitted_bitter` / 1360 |
| `rogue_wasnt_me` | `it_was_me` | Dodger / `it_was_me` | `bonk` / 1131 |
| `rogue_confusing_dodge` | `clear_jump` | Dodger / `clear_jump` | landing `step` / 3746 |
| `summon_skeleton` | `recall_skeleton` | Crypter / `recall` | `fitted_recall` / 1433 |
| `raise_dead` | `play_dead` | Crypter / `hush` | `fitted_hush` / 886 |
| `healing_sonnet` | `healing_sonnet_in_tune` | Bard / `healing_sonnet` | `fitted_sonnet` / 1608 |
| `inspiring_melody` | `inspiring_melody_in_tune` | Bard / `inspiring_melody` | `melody` / 1594 |
| `knight_rescue_line` | `safety_distance` | Knight / `safety_distance` | `fitted_stop_palm` / 1001 |
| `healer_field_dressing` | `unpick_the_stitch` | Healer / `bonk` | `bonk` / 1131 |
| `wizard_ring_sparks` | `ring_of_salve` | Caster / `ring_sparks` | `fitted_salve_ring` / 1206 |
| `rogue_tripwire` | `cut_the_wire` | Dodger / `cut_the_wire` | `fitted_wire_cut` / 1949 |
| `necro_grave_bell` | `dinner_bell` | Crypter / `grave_bell` | `fitted_dinner_bell` / 2065 |
| `alchemist_etching_paste` | `sealing_paste` | Mixologist / `etching_paste` | `paste` / 891 |
| `knight_shield_throw` | `lend_a_shield` | Knight / `lend_a_shield` | `fitted_shield_seat` / 1478 |
| `bard_take_the_stage` | `company_chorus` | Bard / `healing_sonnet` | `fitted_chorus` / 1608 |
| `necromancer_say_hello_to_that_one` | `stay_close_to_that_one` | Crypter / `stay_close` | `fitted_rally` / 719 |
| `alchemist_plain_tonic` | `plain_solvent` | Mixologist / `hostile_dose` | `fitted_bitter` / 1360 |
| `alchemist_repeat_batch` | `counterbatch` | Mixologist / `acid` | `dose` / 555 |

| Borrowed case ID | Source → effective form | Actual wearer / drawn clip | Wearer cue / PCM16 peak |
|---|---|---|---|
| `borrowed_knight_healer_bonk` | `healer_bonk` → `keep_your_head_down` | Knight / `keep_your_head_down` | `fitted_knight_cover` / 995 |
| `borrowed_healer_wizard_blast` | `wizard_blast` → `mending_blast` | Healer / `blast` | `heal` / 1593 |
| `borrowed_wizard_rogue_confusing_dodge` | `rogue_confusing_dodge` → `clear_jump` | Caster / `clear_jump` | landing `step` / 3746 |
| `borrowed_bard_knight_push` | `knight_push` → `fitted_pull` | Bard / `fitted_pull` | `fitted_bard_pull` / 876 |
| `borrowed_rogue_alchemist_potion` | `alchemist_potion` → `bitter_medicine` | Dodger / `bitter_medicine` | `fitted_bitter` / 1360 |
| `borrowed_necromancer_inspiring_melody` | `inspiring_melody` → `inspiring_melody_in_tune` | Crypter / `melody` | `fitted_crypter_melody` / 2123 |
| `borrowed_alchemist_wizard_pull` | `wizard_pull` → `send_off` | Mixologist / `send_off` | `shunt` / 827 |

**Five changed cases in the later `zBadWM` run:** each has a nonzero `evidence/<case>.wav` from Master, with an identified performer request. `knight_push`: `fitted_knight_pull` (peak 1219), replacing the earlier cue; `rogue_confusing_dodge`: `fitted_jump_cape` takeoff and `step` landing (3737); `borrowed_wizard_rogue_confusing_dodge`: `fitted_jump_caster` takeoff and `step` landing (3707); `rogue_wasnt_me`: `bonk` impact and `fitted_claim` on the later claim beat (1193); `knight_shield_throw`: `fitted_shield_seat` (1478). The earlier Clear Jump stems contain landing only; the later mixes do not isolate the new takeoffs or claim.

## Targeted follow-ups

- `.lore/local/smith-visual-targeted.HbPjMO/evidence/`: `variant_knight_bonk_shield_away` supersedes the earlier shield-away pose sample: unshielded protective clip at F13, with guard feedback and Cover on the Healer. `variant_counterbatch_damage` draws the hostile dose at F13 and the impact on the selected Raider. Both previews were silent. Earlier `zBadWM` also records `variant_blast_self`, `variant_blast_fallback`, and `variant_buffer_self`.
- `.lore/local/smith-supplementary-live.exUd3i/captures/`: genuine controlled rules commits fed the real board. Smith `bonk` shows recipient flinch at F15; `acid` shows the detached flask at F18 and a later recipient hit; `release` is the Knight wearer's movement with `smith_release` and `step` requests.
- `.lore/local/smith-lifecycle-live.G1GikG/captures/` supersedes the supplementary F1 lifecycle samples: Hit F5 → Ready, Down F16 → held F24, Recover F14 → Ready, and Defeat F16 → held F24. Both supplementary logs pass their fixture assertions but report a Godot resource diagnostic at shutdown.
- `.lore/local/smith-prone-proof.IO4WK3/` confirms exact prone Recall stance at the destination, followed by an upright tuck after recovery. The final `.lore/local/smith-prone-proof.htTO7f/{test.log,png/}` passes with eight post-draw frames: the returned original corpse shows no false `FALLEN` caption at the handoff or after a settled refresh; an unrelated ordinary corpse still shows `FALLEN`.

## Reproduce in the existing checkout

Run from the repository root with Godot 4.7. Play the stock example directly with `godot --path games/company-of-unlikely-heroes -- --mission=hold_the_line --party=blacksmith,knight,healer`. The [battle matrix](../../../../../games/company-of-unlikely-heroes/tests/smith_playback_scene_test.gd) accepts `--list`, `--case=ID`, or no filter for all 32. Headless tests check rules, picker, commit equality, and routing; they do not render the playback or prove audible output. The rules and forecast cross-checks recorded in `.1`, `.3` and `.6` are:

| Coverage | Tests under `res://tests/` |
|---|---|
| Knight Push, Guard, fit intake and action picker | `smith_knight_rules_test.gd`, `smith_command_picker_scene_test.gd` |
| Other tactical actions and pre-slot standing/direct resolution | `smith_tactical_conversions_test.gd`, `smith_tactical_orders_test.gd` |
| Doses, exact reaction and bottle replay | `smith_alchemy_conversions_test.gd`, `smith_converted_forecast_scene_test.gd` |
| Songs, summons, Inspiration and ordinary echoes | `smith_songs_summons_test.gd`, `smith_inspiration_lifecycle_test.gd`, `smith_undead_lifecycle_test.gd` |
| All seven purchased, equipped and deployed borrowed kits | `smith_borrowed_guild_conversions_test.gd` |
| Committed board, routing and choreography | `smith_committed_playback_test.gd`, `smith_committed_board_test.gd`, `smith_fitted_audio_dispatch_test.gd`, `smith_choreography_scene_test.gd` |

For example:

```bash
godot --headless --path games/company-of-unlikely-heroes \
  --script res://tests/smith_playback_scene_test.gd -- --case=borrowed_knight_healer_bonk
```

For graphical reproduction, use a normal visible window in the existing Wayland session, with `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` inherited. Do not use `--wid`, a hidden X11 parent, or Dummy audio. The current [sandbox guard](../../../../../games/company-of-unlikely-heroes/tests/support/capture_sandbox.gd) requires a **fresh** real directory beneath this checkout's ignored `.lore/local`, with explicit child paths so isolated music changes cannot touch a player's profile. If a tool-manager shim depends on your usual XDG config, set `GODOT_BIN` to the absolute Godot executable before running this recipe.

```bash
(
  set -eu
  game=games/company-of-unlikely-heroes
  godot_bin=${GODOT_BIN:-$(type -P godot)}
  new_capture() {
    sandbox=$(mktemp -d "$(pwd -P)/.lore/local/$1.XXXXXX")
    mkdir -p "$sandbox"/{data,config,cache,state,tmp,captures}
    export XDG_DATA_HOME="$sandbox/data" XDG_CONFIG_HOME="$sandbox/config"
    export XDG_CACHE_HOME="$sandbox/cache" XDG_STATE_HOME="$sandbox/state"
    export TMPDIR="$sandbox/tmp" SMITH_CAPTURE_SANDBOX="$sandbox"
    export OLR_VISUAL_SANDBOX="$sandbox" SMITH_CAPTURE_ROOT="$sandbox/captures"
    export SMITH_SUPPLEMENTARY_DIR="$sandbox/captures"
  }

  new_capture smith-import
  "$godot_bin" --headless --editor --path "$game" --import > "$sandbox/import.log" 2>&1

  new_capture smith-live-visual
  timeout 600s "$godot_bin" --display-driver wayland --audio-driver PulseAudio --path "$game" \
    --script res://tests/smith_live_visual_verification.gd -- \
    --output-dir="$sandbox/captures" > "$sandbox/run.log" 2>&1

  new_capture smith-live-audio
  timeout 600s "$godot_bin" --verbose --display-driver wayland --audio-driver PulseAudio --path "$game" \
    --script res://tests/smith_live_conversion_capture.gd -- \
    --all --expected-count=32 > "$sandbox/live.log" 2>&1

  new_capture smith-supplementary
  timeout 180s "$godot_bin" --verbose --display-driver wayland --audio-driver PulseAudio --path "$game" \
    --script res://tests/smith_supplementary_live_capture.gd > "$sandbox/live.log" 2>&1
)
```

To isolate the two targeted visual variants, add `--case=variant_knight_bonk_shield_away --case=variant_counterbatch_damage` after `--output-dir`; for lifecycle use `-- --lifecycle-only` on the supplementary command. For prone companions, add `new_capture smith-prone` inside the recipe, then run `SMITH_CHOREOGRAPHY_OUTPUT="$sandbox/captures" "$godot_bin" --display-driver wayland --path "$game" --script res://tests/smith_choreography_scene_test.gd -- --case=prone-companions`. Add `--exclude=knight_push --exclude=alchemist_acid` and change `--expected-count` to 30 to repeat the earlier audio selection, not its older cue bindings. Keep captured media, JSON and logs in the throwaway sandboxes, not Git; none is a runtime input.
