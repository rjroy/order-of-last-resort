# Village Troubles: one party, three different jobs

**Baseline and origin.** The original outing pairs an untimed patrol with a timed rescue. The [combat encounters](../../notes/company-of-unlikely-heroes-combat-encounters.md) and [mission proposals](../../notes/company-of-unlikely-heroes-mission-proposals.md) were recorded in `24184ef`. Following review, Ronald selected all three shortlisted encounters for one additional guild outing. The resulting two-combat/one-objective slice tests those contrasts, not the eventual adventure cadence.

**Question for Ronald.** Can one party feel powerful against a crowd, clever against a coordinated enemy, and useful when killing the opponent would lose? A change of objective alone is not evidence: which standing order or direct command did you actually reconsider, and why?

| Mission | Prediction to check during play | What would count against it |
|---|---|---|
| Goblin Mob (tier 1) | Letting goblins crowd together can feel like setting up a payoff. | Five similar activations feel like cleanup, or the player only ever wants to spread the mob. |
| Harpoon Squad (tier 2) | The forecast makes it appealing to interrupt the pull or to allow it and disrupt the follow-up. | The player can't anticipate the landing, or sees two legal responses but only one worth trying. |
| The Unwelcome Guest (tier 2) | Carrying the same wounded party and its standing orders into a nonlethal job changes what the player wants it to do. | The Knight's immediate push feels like a foregone conclusion, or luring without displacement feels like guessing at pathfinding. |

**Reproduction.** Launch `godot --path games/company-of-unlikely-heroes`, choose **Village Troubles**, then recruit and order any three heroes. For isolated opening comparisons, append `-- --mission=goblin_mob`, `-- --mission=harpoon_squad`, or `-- --mission=unwelcome_guest`. The authored setups, default parties and seeds are in `content/village_troubles.json` under the game directory. Reopening a forecast is not a new seed.

**Mechanical evidence.** `three_mission_test.gd` exercises the Wave opening, two distinct responses to the hook/strike, full-health push and lure exits, and both troll death and party wipe despite a surviving summon. `village_outing_scene_test.gd` drives a Healer/Knight/Bard victory through guild selection, ordering, forecasts, commits, both mission transitions and return to guild. Run either from the project root with `godot --headless --path games/company-of-unlikely-heroes --script res://tests/<filename>`. A successful route demonstrates feasibility rather than balance across all parties.

**Decision:** ready for human play. No player verdict or voluntary replay result yet. After the first outing, ask which moment (if any) made Ronald want to try a different party. Record enjoyment separately from whether he chooses to run it again.
