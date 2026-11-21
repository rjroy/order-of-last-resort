# Company of Unlikely Heroes — Combat Encounters and Mission Cadence

## Purpose

Expand the game's **ordinary defeat-the-enemies encounters** beyond the existing baseline fight against two short-ranged Harpooners. Combat is the bread and butter of the game; specialized objective missions should be occasional punctuation, roughly **one in every five encounters**.

These are **design proposals**, not settled implementation requirements. The aim is to create varied, satisfying fights using reusable enemy behaviors and combinations—not ten bespoke scripted puzzles.

## Guiding principles

- **Straightforward victory condition, interesting combat:** Most encounters can simply require defeating all opponents. Enemy composition, positioning, and terrain provide variation.
- **Let heroes be heroes:** Unconventional party behaviors already make fights surprising. Not every encounter needs to counter the player's composition. Sometimes a Wizard should obliterate a mob or a Knight should break a formation.
- **Make enemies interact:** Prefer enemy abilities that change the tactical value of other enemies, such as a Harpooner pulling a hero into a Bruiser's reach.
- **Make threats legible:** Telegraph dangerous combinations, retaliation, explosions, and changes in enemy strength.
- **Avoid tedious fights:** Beware healing stalemates, damage sponges, endless chases, lengthy enemy turns, and unavoidable displacement chains.
- **Preserve viable experimentation:** Different party configurations should find different solutions; don't require one hero or one prescribed tactic.

## Existing baseline

**Two Harpooners:** A simple defeat-all encounter with two short-ranged Harpooners. Retain it as a low-complexity reference point. Not every fight needs an elaborate gimmick.

## Proposed combat encounters

### 1. The Harpoon Squad

**Enemies:** 2 Harpooners + 1 melee Bruiser.

**Tactical identity:** Forced positioning and coordinated enemy attacks.

The Harpooners pull heroes into the Bruiser's melee range. This makes the existing enemy behavior more consequential without adding a special mission objective.

**Risk:** Repeated pulls into unavoidable attacks could feel unfair. Test whether the player has readable opportunities to interrupt, separate, or recover from the combination.

### 2. The Shield Wall

**Enemies:** 2 Shieldbearers + 1 Archer.

**Tactical identity:** Breaking defensive formations.

Durable, relatively harmless Shieldbearers protect an Archer behind them. Displacement or unusual repositioning can expose the ranged threat; for example, the Knight can disrupt the line, or the Rogue can swap behind it.

**Risk:** High defense could turn a short fight into a damage-sponge slog. Test whether breaking the formation is rewarding without being the only viable approach.

### 3. The Cowardly Captain

**Enemies:** 1 Captain + 2 Grunts.

**Tactical identity:** Target prioritization and pursuit.

The Captain buffs nearby allies but retreats from approaching heroes. Grunts pursue aggressively. The player weighs defeating the frontline against reaching the support unit.

**Risk:** Chasing a retreating Captain could become tedious. Ensure there are practical ways to corner, displace, or otherwise resolve the fight.

### 4. The Explosive Situation

**Enemies:** 2 Bombers + 1 Harpooner.

**Tactical identity:** Area denial and chain reactions.

Bombers carry unstable explosives that damage nearby characters when triggered. The Harpooner can pull heroes into danger. Conversely, pushing one Bomber into another might produce a satisfying chain reaction.

**Risk:** Untelegraphed explosions would feel arbitrary. Make trigger conditions, danger areas, and timing clear enough for tactical planning.

### 5. The Unfortunate Healer

**Enemies:** 1 Healer + 2 Bruisers.

**Tactical identity:** Sustained combat and target prioritization.

The Healer restores injured enemies but has little offensive capability. The player can target the Healer, separate the group, or outmaneuver the healing pattern.

**Risk:** Repeated healing can create stalemates. Consider a fragile Healer or limited healing, and test fight duration rather than assuming the design works.

### 6. The Duelists

**Enemies:** 2 Duelists.

**Tactical identity:** Timing and spacing.

Duelists retaliate against adjacent attackers but are vulnerable to ranged attacks and displacement. The Knight can push a Duelist away to protect an ally from retaliation.

**Risk:** Excessive retaliation could invalidate melee-heavy parties. The encounter needs counterplay beyond simply bringing ranged heroes.

### 7. The Goblin Mob

**Enemies:** 4–6 weak Goblins.

**Tactical identity:** Crowd control and managing multiple threats.

Goblins are individually weak but grow more dangerous when several surround one target. Area attacks, displacement, and even the Necromancer's indiscriminate skeleton can shine.

**Risk:** Numerous enemy activations could slow the game. Keep individual actions fast and Goblins easy to defeat; allow the player to enjoy powerful crowd-clearing combinations.

### 8. The Odd Couple

**Enemies:** 1 Ogre + 1 Goblin Trickster.

**Tactical identity:** Disrupted positioning.

The Ogre is slow, powerful, and predictable. The Trickster moves quickly and swaps positions with other characters, potentially putting the Ogre somewhere inconvenient for either side.

**Risk:** Excessive swaps can erase player planning. The Trickster's behavior should be understandable and exploitable.

### 9. The Mirror Company

**Enemies:** 1 Knight + 1 Wizard + 1 Healer.

**Tactical identity:** Fighting a rival adventuring company.

The opponents use recognizable versions of the party's own abilities. An enemy Knight might push a hero into the Wizard's range while the player uses displacement or threat redirection in return.

**Risk:** Symmetrical fights may drag or become too dependent on initiative. Test whether the rival party feels distinct and whether both sides can break stalemates.

### 10. The Last One Standing

**Enemies:** 3 Bandits.

**Tactical identity:** Kill order and an evolving encounter.

Each Bandit gains a different bonus when another Bandit dies. The final survivor becomes significantly more dangerous, forcing the player to reconsider elimination order.

**Risk:** Bonuses could be opaque, or the final enemy could become a damage sponge. Make transformations clear and ensure the resulting danger changes decisions rather than merely extending the fight.

## Reusable enemy archetypes

| Archetype | Tactical contribution |
|---|---|
| Harpooner | Pulls characters |
| Bruiser | Threatens adjacent targets |
| Shieldbearer | Protects allies |
| Archer | Ranged pressure |
| Captain | Strengthens nearby allies |
| Bomber | Creates explosive hazards |
| Healer | Restores allies |
| Duelist | Punishes adjacent attacks |
| Goblin | Strength in numbers |
| Trickster | Manipulates positioning |

Other encounter-specific roles include the Ogre (slow, powerful threat) and Bandits (gain bonuses when allies fall). These are candidate archetypes, not an exhaustive roster.

**Composition is the main source of variation:** Harpooner + Bruiser creates a different tactical problem from Harpooner + Bomber, even though the Harpooner's own behavior is unchanged. Favor interactions like these before adding many unique enemy systems.

## Mission cadence clarification

**Target rhythm:** Approximately **four conventional combat encounters for every one specialized objective mission** (about 80% / 20%). This is a pacing guideline, **not a rigid sequence**.

An illustrative five-encounter stretch:

1. Ordinary combat — simple or familiar composition.
2. Ordinary combat — new pairing or tactical pressure.
3. Ordinary combat — opportunity for the player's party to excel.
4. Ordinary combat — more demanding composition or terrain.
5. Specialized mission — an objective such as escort, displacement, area control, or herding.

Vary the ordering and intensity to maintain pacing. A specialized mission should feel like a change of pace, not a mandatory checkpoint after exactly four fights. Likewise, ordinary fights need not constantly introduce a novel mechanic. Some should simply be satisfying beatdowns.

### Relationship to existing specialized missions

The game currently has an escort mission involving a ferryman crossing a blocked bridge with an opponent guarding the exit. Additional specialized proposals—such as **The Unwelcome Guest**, **The Unfortunate Ritual**, and **The Great Sheep Escape**—belong in the occasional-objective pool, not the default combat rotation.

Specialized missions test familiar abilities under unfamiliar objectives. Ordinary combat gives players repeated opportunities to develop, express, and enjoy their party's identity.

## Recommended next prototypes

1. **The Harpoon Squad:** Tests synergistic enemy positioning using an existing archetype.
2. **The Shield Wall:** Tests formation disruption without relying on raw damage.
3. **The Goblin Mob:** Tests crowd control and the pleasure of a strong party clearing weaker enemies.
4. **The Unfortunate Healer:** Tests target priority and whether support units create decisions without stalemates.

Keep **Two Harpooners** as a baseline for comparing complexity, duration, and player enjoyment.

## Questions and validation for the next agent

- Does each composition produce meaningful decisions with several different hero parties?
- Are enemy combinations readable before their most punishing effects occur?
- Can players exploit enemy behavior, or do they merely endure it?
- Does a combat encounter conclude promptly once the player has solved its tactical problem?
- Do some encounters deliberately reward the player's existing build instead of countering it?
- Does the approximately 4:1 combat-to-specialized cadence create welcome variety, or does it need adjustment after playtesting?

**Preserve the central premise:** Ordinary combat is not filler between clever missions. It is the primary activity of *Company of Unlikely Heroes*, and should be fun in its own right.
