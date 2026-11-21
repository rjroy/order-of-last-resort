---
title: "Experiment 006: Commission routes"
date: 2026-11-21
status: mechanically verified, player evidence pending
tags: [game-design, experiment]
---

# Experiment 006: Commission routes

## Inputs and provenance

[005: Encounter catalog](../005-encounter-catalog/record.md) verified fixed outings against code at `c68fbe4`. The player picked an outing, recruited and ordered a company, then chose temporary upgrades between missions on a fixed route. In 006 the player chooses a destination and company, then also chooses the missions on the way there. This tests a choice between missions, not a new combat rule or whether the catalog is fun.

Ronald chose to create and lead a named guild, take commissions from a three-offer board, and end each run at a special destination. He selected lengths of 5, 5, and 10, no commission payouts yet, reports that describe the immediate mission and hint at the next kind, and recruitment and ordering before reports. The agent proposed four combat kinds (Skirmish, Formation, Ambush, and Rival Band), a clue guaranteed to match exactly one of the next two offers (which Ronald endorsed), taking the debrief upgrade before the next reveal, and going straight from the penultimate mission to the finale after the upgrade rather than offering a false choice.

Authorization is recorded in `mind-garage-370`; the starting repository checkpoint is `2567432`. Ronald is the [sole intended player](../../../../shared/audience/player-brief.md); repeat visits are not independent player samples.

## Authorized campaign flow

1. Name the guild on first launch. The guild board offers three distinct commissions with named special destinations: two five-mission commissions and one ten-mission commission, each counting the finale.
2. Accept a commission, then recruit and order the company before seeing any route reports.
3. At each fork, choose between two scout reports. Each describes its immediate mission and gives one believable clue about the *type* of mission beyond it, not the exact mission. The chosen report's clue matches exactly one option at the next fork. At the last fork both routes lead to the already named destination instead.
4. After each nonfinal victory, pick a temporary hero upgrade **before** seeing the next fork or deploying to the finale. The selected report's clue stays visible on the upgrade screen. Wounds, orders, and upgrades carry within the commission. After the finale, return to the guild board without a payout or permanent power gain.
5. Relaunch restores the guild name and seeded board, not the company or mid-adventure progress. The original fixed routes remain available under **Practice outings** or with `--fixed-outings`.

## Comparison before play

**Question:** Does one credible onward clue make Ronald consider or select a different temporary upgrade before the next fork is revealed? The clue should support preparing for one plausible next mission, not tell him which route or upgrade to take. A generally strong upgrade, current wounds, or prior knowledge of the catalog could matter more than the clue.

Use 005 as context, not as the control for the clue. For a focused comparison, show the same reward options and pre-reveal company state with and without the selected report's onward clue, keeping the destination and immediate mission information the same. Use matched decision snapshots and record exposure order; do not reveal the next fork until Ronald has chosen and explained what he is preparing for. This is a proposed comparison, not authorization to build another game mode.

Support for the hypothesis is a changed pick or a newly credible alternative that Ronald can tie to the clue before reveal. Investigate if the clue is ignored, misunderstood, or only confirms an already obvious pick. Ask separately whether the choice was enjoyable, whether Ronald wants another commission, and whether he actually returns voluntarily. Record real sessions with consent; a requested comparison run is not voluntary replay.

## Build and evidence

Launch from the repository root with `godot --path games/company-of-unlikely-heroes`. Authored reports are in `games/company-of-unlikely-heroes/content/commissions.json`.

**Mechanical results (Godot 4.7.2):**

- Route checks reproduced three distinct special destinations with lengths 5/5/10. The model enumerated both branches through the 5- and 10-mission routes for board seeds `11` and `9182`, checking that the previous clue matched exactly one report at every subsequent fork. Board checks also used `1` and `123456`. The controlled adventure checks used reward seed `444`; the authored opening used board/reward seeds `101`/`42`.
- Scene tests used board seed `147258`. They verified recruitment before report reveal, the chosen clue visible while selecting an upgrade and before the next reports appear, and carried HP, orders, and upgrades. Controlled battles won via the normal UI completed both a 5- and a 10-mission commission. In each, both last-fork cards named that commission's shared finale; after the upgrade, play went straight there, with no extra fork and no completion payout. These wins used one-HP opponents, not a balance test of the authored encounters.
- The profile check used seeds `147258` and `369121` to verify persistence across processes and board renewal: only the guild name and board seed persist, not mid-adventure progress. The fixed-outing regression used the repository's `tests/fixed_outing_routes.json` and reward seed `12345` to replay the five outings added in 005 through the legacy entry path.

The targeted checks below exited `0`. To reproduce from the repository root with Godot 4.7.2:

```sh
set -e
game=games/company-of-unlikely-heroes
for suite in commission_routes_test commission_scene_test commission_finale_scene_test \
    guild_profile_test fixed_outing_victory_test
do
    godot --headless --path "$game" --script "res://tests/$suite.gd"
done
```

**Human play and decision:** Unmeasured. The next proposed check is one matched reward decision with Ronald to see whether the clue changes what he prepares for. Enjoyment, desire to continue, and voluntary replay remain unmeasured; no keep/revert decision yet.
