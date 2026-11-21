# One reward for the company

**Question.** When each hero brings a different offer back from a mission, does choosing only one make Ronald weigh what this particular company needs against the excitement of a rare drop?

**Baseline and intervention.** Previously the same guild outing carried only HP and standing orders between missions. Use those outings and rosters, with the [character-specific tables](../../notes/between-mission-rewards.md) added after non-final victories. Ronald supplied the Knight and Healer pools and the offer and reset rules. The other four playable pools were proposed in discussion and approved for this slice. The mission map, guild perks, and proposed Alchemist and Blacksmith are separate work.

**Replay.** Launch `godot --path games/company-of-unlikely-heroes` from the repository root. Pick **Village Troubles** and three eligible heroes for three-way offers after the first and second fights. The ordinary guild varies the reward seed; the checked-in tests supply their own seeds and rosters. Directly launched battles have no debrief reward. No previous session or generated file is required.

**What the checks establish.** The adventure, effect, and reset regressions exercise real choices and combat forecasts, capped entries leaving the pool, next-mission deployment, and returning with earned upgrades after both victory and defeat. These checks show that the choices work, not that the tier weights or individual rewards are satisfying.

**Playtest decision.** Ask which rejected offer was hardest to pass up and which accepted upgrade actually changed a command or standing order in the following mission. A player who always takes the highest rarity and a player who cannot tell what a reward changes are reporting different problems. Record enjoyment and voluntary replay separately. No human play result yet.
