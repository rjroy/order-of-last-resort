# Guild unlock design: audit of starting kits

Companion to [the two first-purchase paths](guild-unlock-first-paths.md), for `mind-garage-8cf`. The **current** column comes from the seven recruitable characters, their effective class/character habits, and the order → behavior → ability mappings in `games/company-of-unlikely-heroes/content/common.json`. The **recommendation** column is a proposal, not a change to the game. “Starting” means available on recruiting the class, whether it starts in the guild or is unlocked later. Hobby Smith is not a playable class yet. Summons are not recruits.

## The seven kits

Direct Move is always available separately. Offense and utility describe loadout slots, not damage types; the Crypter’s “offense” creates someone else who acts later. **Hold counts as positioning.** Some orders already combine positioning with action: Advance pursues and pushes; Pursue and bonk pursues and strikes. Don't split useful orders just to make the table symmetrical.

| Class / guild availability | Starting direct offense / utility | Current standing orders (default first) | Recommendation at recruitment |
|---|---|---|---|
| Anxious Knight / founding | Push / Reflecting aura | Guard; Advance | Keep both. The choice is between protecting this position and leaving it to pressure an opponent. Guard requires aura; Advance requires Push **and** Move. |
| Unimpressed Healer / founding | Bonk and taunt / Heal self or nearest ally | Support; Pursue and bonk | Keep both. Support requires Heal; Pursue and bonk requires Bonk **and** Move. A Blast loadout therefore retains Support, not a mysteriously renamed “Pursue and blast.” |
| Enthusiastic Caster / founding | Blast nearest / Pull and recoil | Hold position; Blast nearest | Keep both. Hold has no equipped-ability requirement. Automatic Blast requires Blast. Pull stays direct-only: the choice of target and the cost of recoil are the point. |
| Bad Bard / unlock | Healing Sonnet / Inspiring Melody | Hold; Inspiring Melody; Healing Sonnet | Keep all three. The privilege of choosing which song plays while commanding another hero is the reason to buy this recruit. Each song order requires that song. Weaving would reward switching songs, not grant access to the second song. |
| Daft Dodger / unlock | Wasn't Me / Confusing Dodge | Retreat from nearest enemy | Keep Retreat (requires Move). Add **Pass the Blame** as the starting action order: use Wasn't Me on the nearest legal opponent not already misdirected; hold if there isn't one. Preserve the ability’s normal scapegoat rules. Show the chosen opponent in Forecast; resolve equal distances by stable initiative order. No automatic board-wide swap. |
| Friendly Crypter / unlock | Summon Skeleton / Raise Dead | Hold | Keep Hold. Add **Make a Friend**: when there is no living skeleton of yours, summon one in a legal adjacent square; otherwise hold. Choose the legal square nearest a living opponent, break ties in a documented stable board order, and preview the square. If there is no opponent or no legal square, hold. Requires Summon Skeleton. Leave corpses alone: spending a particular corpse for a zombie remains the player's call. |
| Mixologist / unlock | Acid / Healing Potion | Follow closest ally; Make Rounds; Throw Samples; Hold | Start with **Follow**, **Make Rounds**, and **Hold**. Sell **Throw Samples** as an order unlock: the recruit can throw Acid directly from day one; the purchase lets her throw at the nearest legal hostile while someone else takes the direct command. Keep the forecasted bottle reaction unchanged. |

This yields two new starter behaviors, one existing order proposed as a purchase, and no loss of direct abilities. Keep existing base orders where they carry the class fantasy. There is no need for every class to have the same number of unlock cards.

## Dependencies the board actually needs

Distinguish three questions. **Can I buy it?** Check permanent guild ownership and points. **Can I equip or select it now?** Check recipient, slot and equipped abilities. **Will it act this round?** Check the live board and show the outcome in Forecast. A missing target or full summon cap is not a reason to lock or sell a card.

| Candidate card | Permanent prerequisite | Requirement for use | What the purchase does *not* grant |
|---|---|---|---|
| Recruit the Bad Bard | Fresh guild; no prior purchase | Select Bard for one of the three party slots | A fourth slot or Song Weaving |
| Bard: Song Weaving | Bard recruited | Switch songs to echo the previous round’s song | A second direct command or a programmable alternating order |
| Teach the Healer: Blast nearest | Healer and Caster available (both founders) | Equip Blast instead of Bonk | Automatic Blast, selectable targets, Wizard rewards, or loss of the Wizard’s own spell |
| Healer: Blast on standing orders | Healer Blast teaching purchased | Blast equipped | Access to Blast while Bonk is equipped |
| Mixologist: Throw Samples | Mixologist recruited | Acid equipped | A second throw or a reroll of the bottle |

One loadout check the first walkthrough didn't need: if future slot swaps invalidate **every** learned order, don't force a purchase or deploy an invalid party. Offer **Hold** as a free fallback and let the player accept it during recruitment. It is not a paid node. Restoring an ability restores eligibility for its learned orders without buying them again.

Keep adventure rewards in their existing lane. For example, the Bard’s current *House Lights* reward grants *Take the Stage* as an outing-only action and order (`content/rewards.json`). It should not appear as a permanent guild unlock just because it grants an order. A borrowed ability can use a shared mechanic without importing the donor’s standing orders or loot table.

## First checks with a player

1. **Healer equips Blast:** Before leaving recruitment, can the player predict which standing order disappears and why? Switching back to Bonk should bring it back without another purchase.
2. **Dodger beside two enemies:** Can the player predict who gets blamed while directly commanding the Knight? If automatic blame mostly repeats a wasted mark, revise the target rule before offering further Dodger orders.
3. **Crypter on a narrow board:** Is the forecasted skeleton square clear enough to keep the player from accidentally blocking an escort or exit? Compare Make a Friend with Hold plus deliberate placement before making it the default. Recommend Hold as the default meanwhile.
4. **New Mixologist:** Does choosing the patient or acid target still feel useful before buying Throw Samples? If buying automation feels like paying to recover the class fantasy, keep Throw Samples in the base kit and design a different order unlock.

These recommendations do not assign additional prices, settle weaving interruptions, or prescribe a visual tree. Next decision: accept or revise the two new starter orders and the Mixologist split before laying out the first unlock board.
