---
title: "Experiment 005: Encounter catalog"
date: 2026-11-21
status: ready for playtesting
tags: [game-design, experiment]
---

# Experiment 005: Encounter catalog

## Inputs and authorization

- **Original proposals:** [Combat Encounters and Mission Cadence](../../notes/company-of-unlikely-heroes-combat-encounters.md) supplied the eight defeat-all encounters; [Mission Proposals](../../notes/company-of-unlikely-heroes-mission-proposals.md) supplied the seven specialized objectives. Both were recorded at `24184efc8946e9de5b8f4e688a4b0077d52cbe6a`. They are design inputs, not final rules, evidence of originality, or playtest findings.
- **Human decision:** Ronald authorized implementing the remaining predefined missions across multiple adventures, preserving the five existing encounters. The agent selected the fixed outing groupings and mission order below. `mind-garage-683.1` tracks this implementation; the broader mission-design issue, `mind-garage-683`, remains open. The original roughly 4:1 combat-to-objective pacing suggestion is not the sequence for this slice. This batch tests encounter variety, not the right long-term cadence.
- **Baseline:** `3b1be68c453af8c9ef1bbbbd093369e987412e25`. The first outing supplies the two-Harpooner patrol for simple defeat-all combat and Ferryman Escort for objective play and escort comparison. [Village Troubles](../003-village-troubles/record.md) supplies the existing three-mission run: Goblin Mob, Harpoon Squad, Unwelcome Guest. Keep the same player-picked company, deployment order, standing orders with one manual override per round, and existing wound and [reward carryover](../004-hero-rewards/record.md) as the comparison frame. The [game README](../../../../../../games/company-of-unlikely-heroes/README.md) records baseline launch and play instructions.

## Design questions before play

Can a new encounter change whom Ronald commands, which standing orders he trusts, or what he recruits for, without making one hero mandatory? The expected decisions below are predictions from the proposals, not prescribed solutions. Distinct pressures may prompt different choices, but more rounds spent chasing, waiting, or deciphering rules would not support that explanation.

| Fixed outing | Mission ID, in play order | Design question and expected party decision | Risk and what would count against it |
|---|---|---|---|
| **Border Watch** | `shield_wall` | Can the company open the formation? Spend the manual command on displacement or a flank to reach the Archer, or pressure an exposed Shieldbearer first. | Damage sponge: breaking the line barely changes the fight, or only one hero can make an opening. |
| | `wrong_side_of_the_door` | Can the company coordinate a plate holder and a runner? Leave a hero on the plate or put an enemy there while another hero reaches the exit. | Solved-once puzzle: the same opening works regardless of roster or opposition, or only one ability can open a path. |
| | `cowardly_captain` | Does the Captain's buff change target priority? Take down the Grunts first or commit someone to cutting off the retreating Captain. | Cleanup chase: once the Grunts fall, the Captain stays out of reach without presenting a meaningful interception choice. |
| **Powder Run** | `explosive_situation` | Can the party turn readable blast zones against the enemy? Separate vulnerable heroes from pull lanes or spend the command setting up a Bomber chain reaction. | Arbitrary damage: the forecast does not make the pull or blast legible, or there is no useful response before the explosion. |
| | `bridge_is_out` | Do timed collapses make hero habits matter? Use the override to get a lagging hero onto safe ground or spend it advancing while there is still a path. | Pathfinding quiz: one exact route works regardless of party, or failure hinges on an unannounced collapse. |
| | `last_wagon` | Is moving defense distinct from the ferryman rescue? Clear adjacent blockers to keep the wagon moving or intercept the next attacker before it reaches the wagon. | Redundant escort: wagon adjacency and enemy targeting do not change decisions from the ferryman run. |
| **Fairground Fracas** | `duelists` | Can a melee-heavy party work around retaliation? Use displacement or spacing to set up a safe attack instead of trading adjacent hits. | Roster lock: bringing ranged damage is the only practical answer. |
| | `great_sheep_escape` | Can the company steer the flock predictably? Assign a hero to pressure sheep toward the pen or cut off the shepherd before the flock scatters. | Opaque herding: Ronald cannot predict or recover from sheep movement even when he understands the goal. |
| | `odd_couple` | Can the party plan around the Trickster's swaps? Remove the Trickster first or position so a swap separates the Ogre from vulnerable heroes. | Planning erased: repeated swaps are unreadable or make careful positioning irrelevant. |
| **Night Duty** | `unfortunate_healer` | Can the company disrupt healing without always rushing the support unit? Separate the Bruisers, focus enough damage to finish one, or reach the Healer first. | Healing loop: viable damage and disruption make no lasting progress, or rushing the Healer is the only effective opening. |
| | `dont_wake_the_giant` | Does the noise budget leave room for hero abilities? Change a noisy standing order or save the override for an action that secures the treasure without waking the giant. | Rigid stealth: only one silent route works, or waking the giant comes from noise the player could not anticipate. |
| | `hold_the_line` | Does surviving reward active defense? Use displacement, a summon, or retreat to shore up the more threatened side instead of trying to clear the board. | Passive timer or disguised defeat-all: an idle party reliably survives, or survival effectively requires killing every attacker. |
| **Rival Claims** | `last_one_standing` | Do different survivor bonuses make kill order matter? Choose which Bandit to leave alive based on what this party can handle. | Cosmetic or opaque escalation: the bonus merely adds turns, cannot be anticipated, or never changes the preferred kill order. |
| | `unfortunate_ritual` | Can the company recover a broken three-circle formation? Hold a circle with an ally or summon, or use an enemy to keep a circle occupied while reclaiming another. | Scripted solution: one exact sequence or required hero works, with no practical recovery from displacement. |
| | `mirror_company` | Do recognizable rival abilities create counterplay? Break the Knight–Wizard setup with positioning or spend the opening reaching the rival Healer. | Initiative or stalemate: the opening turn decides the fight, or neither party can break repeated healing and displacement. |

## Comparison and evidence

For human playtesting, compare with the relevant baseline using the same company and deployment order where practical. Use a second roster or a changed command to probe apparent locks; compare Last Wagon directly with Ferryman Escort. Separate standalone openings from guild runs with carried wounds and upgrades.

Keep an encounter provisionally when its intended decision can be demonstrated and Ronald recognizes an alternative worth considering. Investigate a single mandatory tactic, an unreadable outcome, or a decision indistinguishable from its baseline before tuning difficulty. Ronald is the sole intended player. Keep real play notes with consent, and record enjoyment, desire to continue, and actual voluntary replay separately; a requested rerun is not voluntary.

### Mechanical and visual evidence

- **Source:** First checkpoint `b7112e7`; final code `c68fbe4`. The final rerun used a fresh `git archive` of the exact `c68fbe4` tree with Godot 4.7.2.
- **Mechanical:** `fixed_outing_victory_test` passed for Border Watch, Powder Run, Fairground Fracas, Night Duty, and Rival Claims. It replayed all 15 missions with carryover, starting at guild selection and taking each company through three victories, two reward selections, and return to the guild. The Hold the Line pressure, cornered-sheep recovery, area retaliation, and rival Knight taunt regressions also passed on the final tree.
- **Native visual review:** At 1280 × 820, the review covered the seventh guild outing, Rival Claims, and the Ritual's completion feedback. Standing-order selection was exercised with OS-level input. This is UI evidence, not a measure of enjoyment.
- **Replay question:** The Powder Run route spends five consecutive manual commands moving the Healer across the bridge. With one intended player, ask Ronald whether the crossing makes him want to try a different company or route, or whether it feels like repeating Move. Record his answer, enjoyment, and actual voluntary replay separately. None has been measured for this slice.

### Changes from review

- **The Shield Wall:** Corrected the formation so both Shieldbearers start adjacent to the Archer. **Last One Standing:** The Bandit Guard's armor cannot reduce an otherwise positive hit below 1 damage; that floor does not change the Shieldbearers' protection.
- **The Unfortunate Healer and Mirror Company:** Enemy heals are limited to two per healer per battle. **Hold the Line:** One Archer and one War Drummer are scheduled for round 4; a blocked entry waits for a later round. The survival goal is still round 6.
- **The Bridge Is Out:** The crossing deadline is the end of round 8, in addition to the span collapses at the ends of rounds 4 and 6.
- **The Wrong Side of the Door:** The alternate Rogue shortcut is intentional, not a route to remove.
- **Don't Wake the Giant:** The noise limit applies through the full round. Reaching the treasure early does not cancel noise from later actions that round.
- **The Great Sheep Escape and The Unfortunate Ritual:** A pressured sheep can step toward the pen if no free step takes it farther from the threat. Apart from a party wipe, the Ritual declares defeat only when there cannot be enough occupants even counting possible summons, not merely because a circle is currently empty.

### Regenerate mechanical evidence

From the repository root with Godot 4.7.2, extract the exact final source and run the reported regressions directly:

```sh
(
  set -e
  godot --version
  archive_dir=$(mktemp -d)
  git archive --output="$archive_dir/source.tar" c68fbe4
  tar -xf "$archive_dir/source.tar" -C "$archive_dir"
  cd "$archive_dir"
  for suite in fixed_outing_victory_test hold_line_pressure_test \
    sheep_corner_recovery_test area_retaliation_test rival_knight_taunt_test
  do
    godot --headless --path games/company-of-unlikely-heroes \
      --script "res://tests/$suite.gd"
  done
)
```

Repository-relative inputs: `games/company-of-unlikely-heroes/content/frontier_{outings,combats,objectives}.json` defines the candidate; `games/company-of-unlikely-heroes/tests/fixed_outing_routes.json` supplies the rosters, standing orders, commands, and reward choices. The route runner `games/company-of-unlikely-heroes/tests/fixed_outing_victory_test.gd` fixes the reward seed at `12345`; its companion `games/company-of-unlikely-heroes/tests/fixed_outing_victory_test.md` explains the fixture. No generated route or local capture is required.

**Provisional decision:** Keep the catalog for playtesting. The checks establish that the fixed outings work, not that their choices are enjoyable or worth replaying. Ronald's play evidence is pending.
