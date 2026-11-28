---
title: "Experiment 007: Road fights"
date: 2026-11-27
status: draft
tags: [game-design, experiment, road-fights, playtest]
related: [.lore/work/games/company-of-unlikely-heroes/experiments/005-encounter-catalog/record.md, .lore/work/games/company-of-unlikely-heroes/notes/company-of-unlikely-heroes-mission-proposals.md]
---

# Experiment 007: Road fights

## Session handoff: ready for human playtest

The user identified the interruption as a bad OpenCode system prompt, not a
game harness problem, and asked work on road missions to continue. No game
harness change is needed. The actual play path is the documented standalone
Godot launch below; no separate external playtest CLI is assumed.

- Both mission bundles are registered in the default catalog:
  `games/company-of-unlikely-heroes/content/missions/road_playtest_batch.json`
  and `games/company-of-unlikely-heroes/content/missions/road_playtest_followups.json`.
- All ten launches passed the standalone scene check with their authored
  default parties: the requested mission and authored opening were correct, a
  round committed, and Restart restored the opening.
- With Godot 4.7.2, the road playtest catalog, commission catalog, six road
  rule suites, and hook overlay scene checks passed. Logs are retained as local
  evidence under `/tmp/opencode/road-final.obDgy7`; they are not runtime inputs.
- These checks do not establish a win, balance, clarity, enjoyment, or desire
  to replay. Human play notes below remain blank until a player supplies them.
- The Longbow bodyguard diverges from the shortlist proposal: it pursues
  normally and does not actively step aside to clear a shot. Keep this visible
  in the record and assess it during play rather than claiming the proposal was
  implemented.

## Question

Does one clearly reported tactical wrinkle change the player's command, target, positioning, or timing decision during an otherwise familiar defeat-all fight? Which wrinkles are understandable and worth replaying? This is an exploratory batch, not evidence of balance, enjoyment, or commission readiness. Do not tune tiers, variants, commission selection, or art in this pass.

The current `olr-6r4` note says most roads should remain defeat-all fights with one readable wrinkle, with occasional alternate objectives kept distinct. This batch tests the ten named road-fight concepts in that note; the older proposal set of specialized objectives is context, not this batch. Finales remain outside scope (`olr-yfl`).

## Launch

Run from the repository root. Each mission uses its authored default party; close the game window to continue to the next mission. Restart a mission from its in-game restart control to retry it.

```sh
game=games/company-of-unlikely-heroes
for mission in \
    no_room_to_swing last_crate_on_the_road longbows_blind_spot \
    friars_last_favor wrong_twin hired_hammer borrowed_armor \
    empty_helmets very_long_spear big_windup
do
godot --path "$game" -- "--mission=$mission"
done
```

The loop lists the complete ten-mission batch. Each direct launch uses its
authored default party. Use the in-game Restart control to retry, then close the
window to continue. Record any launch/setup error rather than silently
substituting another mission.

For a short automated check of each real standalone launch, authored party,
opening state, committed round, and restart, run once per ID from the repository
root (the test itself documents this invocation at
`games/company-of-unlikely-heroes/tests/presentation/road_standalone_launch_test.gd:3-4`):

```sh
game=games/company-of-unlikely-heroes
for mission in \
    no_room_to_swing last_crate_on_the_road longbows_blind_spot \
    friars_last_favor wrong_twin hired_hammer borrowed_armor \
    empty_helmets very_long_spear big_windup
do
    godot --headless --path "$game" \
      --script res://tests/presentation/road_standalone_launch_test.gd \
      -- "--mission=$mission"
done
```

## Missions and verification

The five original encounters are authored in
`games/company-of-unlikely-heroes/content/missions/road_playtest_batch.json`;
the five follow-ups are in
`games/company-of-unlikely-heroes/content/missions/road_playtest_followups.json`.
Both bundles are registered. Automated verification passed with Godot 4.7.2
(logs in `/tmp/opencode/road-final.obDgy7`):

- All ten standalone launch tests: authored opening/default party, round
  commitment, and restart restoration.
- `road_playtest_catalog_test.gd` and `commission_catalog_test.gd`.
- Six road rule scripts: `road_playtest_bell_test.gd`,
  `road_playtest_combat_test.gd`, `road_playtest_delayed_defense_test.gd`,
  `road_playtest_ranged_test.gd`, `road_playtest_response_test.gd`, and
  `road_playtest_strikes_test.gd`.
- `hook_overlay_scene_test.gd`.

The launch-test process reports the existing audio-only shutdown warning about
ObjectDB instances/resources still in use. The same warning was reproducible on
the baseline; no other errors were observed. It does not change the PASS
results, but is recorded rather than hidden.

| Mission ID | Reported wrinkle / question | Technical/play status |
|---|---|---|
| `no_room_to_swing` | Giant's adjacent sweep hits crew as well as heroes. Can the player bait or avoid the sweep? | Standalone opening/round/restart PASS; human play not yet recorded |
| `last_crate_on_the_road` | Crate obstructs the shot and route; preserve cover or break it to open a path? | Standalone opening/round/restart PASS; human play not yet recorded |
| `longbows_blind_spot` | Longbow cannot attack adjacent targets; can the party close through its bodyguard? | Standalone opening/round/restart PASS; guard pursues normally and does not step aside to clear a shot as proposed; human play not yet recorded |
| `friars_last_favor` | Friar heals surviving enemies when defeated; does this change kill order? | Standalone opening/round/restart PASS; human play not yet recorded |
| `wrong_twin` | One twin hits harder while full-health, the other while wounded; does that alter attack order? | Standalone opening/round/restart PASS; human play not yet recorded |
| `hired_hammer` | Pursuer targets whoever last damaged her; can a ranged hit redirect pressure? | Standalone opening/round/restart PASS; human play not yet recorded |
| `borrowed_armor` | Borrowed shield blocks the first hit on its wearer; can the party exploit the exposed shieldbearer? | Standalone opening/round/restart PASS; human play not yet recorded |
| `empty_helmets` | One fallen ally can return if its body tile is clear; contesting the tile versus exposure. | Standalone opening/round/restart PASS; human play not yet recorded |
| `very_long_spear` | Line attack catches the second tile, including allies; can the party avoid stacking or line up enemies? | Standalone opening/round/restart PASS; human play not yet recorded |
| `big_windup` | Persistent marked tile is struck next round; can forecast support dodging or baiting? | Standalone opening/round/restart PASS; human play not yet recorded |

Treat automated checks as technical evidence only. They are not wins, balance
results, or human playtest feedback. Do not infer enjoyment or record a player
observation until someone has actually played and reported it.

## Player notes

Record a separate row per mission, including failed or blocked launches:

| Mission ID | Launched / completed? | What decision did the wrinkle change (if any)? | Was the wrinkle clear before acting? | Enjoyment (0–10) | Would you replay it? Why? | Notes / exact observed behavior |
|---|---|---|---|---:|---|---|
| | | | | | | |

After play, summarize what was tried and what remained blocked. A changed decision supports the tactical hypothesis; a clear but irrelevant wrinkle, confusion, mandatory hero, or no desire to replay is evidence against or a reason to revise it. Keep automated catalog/rule checks separate from human observations. One player's response is useful evidence from that player, not a representative sample.

## Boundaries and provenance

The mission concepts and their risks are proposals, not approved specifications. Earlier work cautions against opaque mechanics, hard party locks, passive survival, solved puzzles, and redundant escort objectives ([proposal notes](../../notes/company-of-unlikely-heroes-mission-proposals.md)). Experiment 005 also distinguishes mechanical checks from balance or enjoyment evidence ([record](../005-encounter-catalog/record.md)). This index records a playtest handoff; it does not authorize commission rollout or settle keep/revise decisions.
