# Guild unlocks: the first two purchases

Design walkthrough for `mind-garage-8cf`, not implemented game behavior. The earning rate is Ronald’s decision. Purchase prices and unlock contents below are proposals to test, not a tuned economy.

## What comes home

A road victory earns **1 guild point**. A destination victory earns **5**, not 1 plus 5. Completing the commission pays no additional bonus. Credit each won mission once; show points earned so far during the outing and settle them exactly once when the party returns. A loss or confirmed forfeit pays zero for that mission but never takes back earlier victories. Canceling Forfeit has no effect. This currency is separate from the temporary hero upgrade picked after a road victory.

| Commission outcome | Points brought home |
|---|---:|
| Lose or forfeit the first mission | 0 |
| Win two roads, lose or forfeit the third | 2 |
| Win four roads, lose the five-mission destination | 4 |
| Win the same five-mission commission | 4 + 5 = 9 |
| Win a ten-mission commission | 9 + 5 = 14 |

For the examples, put **two independent purchases at 4 points each** on the fresh guild’s board. Four is a useful test price: coming home short of the first destination can still buy something substantial. Two shorter two-road outings buy exactly as much. A successful five-mission return can buy both and leave one point. That last result is worth playtesting, not a reason to change the earning rate.

## Path A: the guild recruits a Bad Bard

1. A new guild has the Anxious Knight, Unimpressed Healer, and Enthusiastic Caster. They clear four roads, then lose at the destination. The return page says **“4 roads won: +4 · Destination lost: +0”**. Their temporary upgrades reset; the guild has 4 points.
2. At the guild, spend 4 on **Recruit the Bad Bard**. No prior purchase is required. Balance: 0. The card promises a fourth **choice** for the existing three places, not a fourth party slot.
3. Pick the next commission. Recruit Knight, **Bard**, and Caster instead of the original trio, then choose their acting order. The Bard arrives with both base songs, Hold, and the existing single-song standing orders. His selling point works on the first mission: leave him playing *Inspiring Melody* while directly commanding the Knight. No second purchase or lucky drop required.
4. **Song Weaving** is a future unlock, not a programmable repeating order. Ronald wants the preceding song to echo in the next round, with a benefit for switching rather than staying on one song. Proposed rule for playtesting: switching from Melody to Sonnet plays Sonnet and echoes Melody once; repeating Melody plays only Melody. Standing orders and direct commands both count. The suggested treatment of a skipped round (break the chain) and echoes (do not prime another echo or bypass immunity) remains to be tested. Forecast should distinguish the live song from the echo.

## Path B: the guild teaches the Healer Blast

1. On an independent fresh-guild run, the original trio completes a five-mission commission. Return: **“4 roads won: +4 · Destination won: +5”**. Balance: 9. Spend 4 on **Teach the Healer: Blast nearest**. Balance: 5. Nothing changes on her equipped loadout until the player chooses it.
2. At recruitment the Healer compares **Bonk** and **Blast nearest** in her offense slot. Equip Blast and leave **Heal** in utility. The picker explains: *Hits the nearest damageable target, including a friend or obstacle.* This is the Wizard’s actual Blast, not an enemy-only variant and not its own aimable spell. The Wizard keeps his copy.
3. **Support** remains available because it uses Heal. **Pursue and bonk** is unavailable because it requires Bonk. If it was the preferred starting order, show the incompatibility and let the player accept Support or put Bonk back before deployment. Do not silently give the Healer the Wizard’s automatic Blast order. A later **Healer: Blast on standing orders** purchase could require the teaching unlock and would still require Blast equipped for this outing.
4. On the road, the Healer can directly Blast when the enemy is nearest, or leave Support running when the Knight is nearest. A Healer heal upgrade still fits; **Long Staff** does not improve this loadout and should not appear. Equipping Blast does not import the Wizard’s reward pool. At guild return the temporary upgrades reset; Blast remains learned, Bonk remains available, and loadout changes at the guild are free.

## What these paths require of the UX

- **Guild board = ownership.** Show cost, recipient, exact benefit, and any missing permanent prerequisite. Distinguish *not yet learned* from *learned but not equipped*. A purchase changes the guild ledger and unlocks an option, never the current party by surprise.
- **Recruitment = preparation.** Pick three heroes, their acting order, one offense, one utility, and a compatible starting order. Show the consequences of a swap before departure. Move never takes an ability slot. One standing order runs at a time; any learned, compatible order can be selected during a mission.
- **Return = accounting.** Show road and destination earnings separately from the ending balance and from upgrades that expired. A loss should read as a failed commission with earned pay, not a victory and not a total wipe of guild progress.

**First playtest:** Give the player a four-point return with both cards available. Can they tell, before spending, that one unlock changes who they can bring and the other changes what one existing hero can do? After choosing, can they put the purchase to work in mission one without guessing about party size, friendly fire, or standing-order availability? If not, fix that handoff before designing a larger tree.

Out of scope for this pass: final prices, the rest of the class unlock order, legacy-save migration details, and destination unlock milestones. Neither example requires locking road missions.
