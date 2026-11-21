# Between-mission rewards

Design notes for `mind-garage-iot`. Ronald's starting pools below are examples for a single adventure, not a shared stat table or a final balance pass. The fantasy is that **this particular hero** comes home stronger from each mission and gains new ways to act during the outing. Temporary upgrades reset on returning to the guild. Persistent guild perks and the future mission map are separate discussions (`mind-garage-8cf`, `mind-garage-370`).

Each entry belongs to a character, has one rarity, and states the maximum times that character can acquire it in the outing. Tier totals below count possible acquisitions at cap, not distinct reward entries or draw weights.

### Knight

| Reward | Rarity | Cap | Effect per acquisition |
|---|---|---:|---|
| +1 HP | Common | 5 | +1 maximum HP. |
| +2 HP | Uncommon | 2 | +2 maximum HP. |
| +1 shield damage | Uncommon | 3 | Add 1 to reflected damage and to Shield Throw damage. |
| +5 HP | Rare | 1 | +5 maximum HP. |
| Dig In | Rare | 1 | While guarding, reverse a pull against the Knight: pull the opponent instead. |
| Shield Throw | Rare | 1 | Gain a range-3 attack for 3 damage. Retrieve the shield before guarding or throwing again. While it is away, Advance moves toward the shield. |
| +3 shield damage | Rare | 1 | Add 3 to reflected damage and to Shield Throw damage. |
| Wide Guard | Legendary | 1 | +1 guard range. |

At cap: **5 common / 5 uncommon / 4 rare / 1 legendary**. The HP entries together add up to +14 max HP.

### Healer

| Reward | Rarity | Cap | Effect per acquisition |
|---|---|---:|---|
| +1 HP | Common | 3 | +1 maximum HP. |
| +1 Bonk damage | Common | 2 | +1 Bonk damage. |
| +2 HP | Uncommon | 1 | +2 maximum HP. |
| +1 heal | Uncommon | 2 | +1 healing. Ronald flagged base healing as a possible tuning lever, not an agreed nerf. |
| +2 Bonk damage | Uncommon | 1 | +2 Bonk damage. |
| +2 heal | Rare | 1 | +2 healing. |
| Long Staff | Rare | 1 | +1 Bonk range. |
| Strong Swing | Rare | 1 | Bonk can hit all opponents in range. |
| Me or You | Legendary | 1 | If the Healer is hurt, the whole heal still goes to the Healer. Otherwise split the healing amount evenly among teammates. |

At cap: **5 common / 4 uncommon / 3 rare / 1 legendary**. The HP entries together add up to +5 max HP. Long Staff and Strong Swing can turn the same Bonk into a wider group attack.

### How the offer works

After a non-final mission victory, show one eligible reward from each deployed hero who has a nonempty loot table. The player takes **one reward total**, for the hero whose offer they choose. Heroes can finish an outing with different numbers of upgrades. Taking an entry uses one of its remaining acquisitions; at zero it stops appearing for that hero for the outing. Passing on an offer does not consume it. Do not infer rarity odds from the caps. Numerically uneven pools are intentional. Knight, Healer, Wizard, Rogue, Bard and Necromancer participate. The playable Alchemist mix-in has no table; the proposed Alchemist and Blacksmith pools below are deferred. On returning to the guild after victory or defeat, all upgrades and acquisition counts reset.

### Draft pools for the other classes

These are candidate rewards, not accepted balance or shipped abilities. Each cap is per entry per hero per outing. Ordinary targeting rules, including friendly fire and laughter immunity, still apply unless an entry explicitly changes them. Additional effects resolve in the forecast; they don't recursively trigger themselves.

#### Wizard — How close do I dare stand?

| Rarity | Reward (cap) | Effect per acquisition |
|---|---|---|
| Common | Spare Robes (×3) | +1 max HP. |
| Common | More Powder (×2) | +1 Blast damage, whoever or whatever it hits. |
| Uncommon | Padded Landing (×2) | −1 Pull recoil damage, minimum zero. The Wizard still falls over. |
| Uncommon | Demolition Practice (×2) | Blast deals +2 damage against obstacles. Turn the inconvenient nearest crate into a useful first shot. |
| Rare | Duck! (×1) | An ally hit by Blast takes the damage but stays on their feet. |
| Rare | Braced Casting (×1) | If Pull recoil ends against the edge of the board or an impassable tile directly behind the Wizard, stay standing. |
| Rare | Parting Gift (×1) | Blast also pushes its surviving primary target one tile away if that tile is open. |
| Legendary | Conductive Personality (×1) | After Blast hits, a half-damage bolt, rounded up, jumps from the impact tile to the nearest other damageable entity. Exclude the first target, **not** the Wizard. The second bolt deals damage only. |

#### Rogue — Be somewhere else when the bill comes due

| Rarity | Reward (cap) | Effect per acquisition |
|---|---|---|
| Common | Thick Coat (×2) | +1 max HP. |
| Common | Cheap Shot (×2) | A successful Wasn't Me redirect adds 1 damage to the actual victim. No bonus if the original attack proceeds normally. |
| Uncommon | Exit Strategy (×1) | Retreat may take a second step if it increases distance from the nearest opponent. Direct Move stays one tile. |
| Uncommon | Borrowed Courage (×2) | After swapping with an ally, reduce the next hit on that ally before the Rogue's next turn by 1. |
| Rare | Pass the Buck (×1) | Confusing Dodge transfers an unspent Wasn't Me mark from an enemy swap partner to another enemy adjacent to its landing tile, if one exists. Preview the recipient. |
| Rare | Pocket Sand (×1) | An enemy swapped by Confusing Dodge cannot move on its next turn. It can still attack. |
| Rare | Long Finger (×1) | If a marked attacker has no adjacent alternate victim, it can blame someone two tiles away instead. The Rogue still doesn't pick the scapegoat. |
| Legendary | Body Double (×1) | Until the Rogue's next turn after Dodge, the first attack aimed at the Rogue hits the living swap partner instead, wherever they landed. An ally makes just as convincing a double as an enemy. |

#### Bard — Choose the song; live with the audience

| Rarity | Reward (cap) | Effect per acquisition |
|---|---|---|
| Common | Road Legs (×2) | +1 max HP. |
| Common | Sharper Notes (×2) | +1 Healing Sonnet damage. |
| Uncommon | Busker's Hat (×2) | If Melody has no eligible listener, heal the Bard for 1. The dry performance still spends the action. |
| Uncommon | Front Row Seats (×1) | Sonnet draws only from the two living opponents with the fewest HP. Include ties at the cutoff. With one listener, it hits that one. |
| Rare | Laughing Fit (×1) | When a listener loses its turn laughing, it drops its guard: the next hit it takes before its next activation deals +2 damage. |
| Rare | Heckler (×1) | After surviving Sonnet, its listener directs its next attack toward the Bard if the Bard is a legal target. The song is now a risky rescue tool. |
| Legendary | House Lights (×1) | Gain a *Take the Stage* standing order and direct action: draw one random eligible opponent; it and every opponent adjacent to it hear Healing Sonnet for its current damage. This is a new performance, not a combo between songs. |

Song weaving remains a guild-upgrade discussion (`mind-garage-8cf`). No reward here extends laughter into the immune round.

#### Necromancer — Invest in the friends you bring along

| Rarity | Reward (cap) | Effect per acquisition |
|---|---|---|
| Common | Spare Ribs (×3) | Skeletons start with +1 HP. |
| Common | Good Soil (×2) | Zombies start with +1 HP after calculating half the corpse's maximum HP. |
| Uncommon | Heavy Bouquet (×2) | +1 Offer Flower damage. |
| Uncommon | Broad Wave (×1) | Wave also hits diagonal neighbors. Friends are not exempt. |
| Rare | Long-Stemmed (×1) | +1 Offer Flower range, including the range the zombie tries to reach. |
| Rare | Warm Welcome (×1) | Say Hello makes the recipient back away up to two tiles, stopping at the first obstruction. |
| Rare | Say Hello to That One (×1) | Gain a direct order: nominate one living opponent for both undead to pursue until it falls or is replaced. They still choose their own greetings. |
| Legendary | Wake Reception (×1) | Once per mission, when a raised zombie falls, its skeleton stands up in its place with the improved skeleton starting HP. Only triggers if the skeleton slot is empty; the new friend first acts next round. |

#### Alchemist (proposed potion-and-acid class) — Choose the dose, not the reaction

These apply to the proposed range-1 Healing Potion and range-3 Acid, not the playable splash-and-ward mix-in. Side-effect entries assume each use draws one forecastable reaction; its pool still needs designing.

| Rarity | Reward (cap) | Effect per acquisition |
|---|---|---|
| Common | Padded Apron (×2) | +1 max HP. |
| Common | Stronger Dose (×2) | +1 Healing Potion healing. |
| Uncommon | Concentrate (×2) | +1 Acid damage. |
| Uncommon | Long Ladle (×1) | +1 Healing Potion range. Pursuit still follows the nearest ally. |
| Rare | Spare Vial (×1) | Gain *Plain Tonic*: a separate range-1 heal for 1 with no reaction. Stronger Dose applies only to the regular potion. |
| Rare | Brittle Glass (×1) | Acid splashes 1 damage onto characters adjacent to its target, including allies. Only the primary target gets a reaction. |
| Legendary | Keep the Culture (×1) | After a potion or acid use, bottle its reaction. Gain *Repeat Batch*: repeat the last recipe with that exact reaction on a new legal recipient, then empty the bottle. Repeat Batch cannot refill itself. |

#### Blacksmith (proposed class) — Change what a teammate's kit can do

Provisional until *Try This* has authored reversals, a recipient rule and a duration. These assume it modifies one teammate at a time. The reward pool should not require designing a second reverse for every ability.

| Rarity | Reward (cap) | Effect per acquisition |
|---|---|---|
| Common | Leather Apron (×3) | +1 max HP. |
| Common | Heavier Hammer (×2) | +1 Back Off damage. |
| Uncommon | Follow Through (×1) | After a successful Back Off push, step into the vacated tile if open. |
| Uncommon | Reinforced Rivets (×2) | When a teammate receives Try This, reduce the next hit on them by 1 per stack while the modification is active. |
| Rare | Long Tongs (×1) | Add one tile to the range at which Try This can be applied. |
| Rare | Quick Release (×1) | Gain a direct command for the modified hero: remove the modification and immediately take their ordinary Move. This uses the company's direct command for the round. |
| Legendary | Double Shift (×1) | Keep two **different** teammates modified at once. Each modification keeps its usual duration; applying it again to the same hero never reverses a reversal. |

### First-playtest tuning

Rarity weights start at 60 common / 28 uncommon / 10 rare / 2 legendary. Draw a nonempty tier, then an eligible entry within it; remaining stack count does not multiply the odds. Max-HP rewards preserve missing HP rather than refilling the hero. Shield Throw leaves the shield at the impact tile; moving onto or next to it recovers it, and Advance prioritizes retrieval. A healthy Healer splits healing among the other living deployed heroes, with odd points assigned in party order; each share caps at that hero’s maximum and unused healing is lost. Summons do not take shares. Base kits remain unchanged until an upgrade is taken.
