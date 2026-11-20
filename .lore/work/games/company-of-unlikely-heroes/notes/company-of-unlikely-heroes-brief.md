# The Company of Unlikely Heroes

**Game concept brief — exploratory, not a final design specification**

## One-sentence pitch

Every hero has a terrible flaw. Build a party where those flaws become strengths, then lead your unlikely company through short tactical adventures to restore a disgraced adventuring guild.

## The promise

The player should be able to say: **“This party should not work, but I made it work—and it works in a way no other party does.”**

This is a **character-driven tactical roguelite** built around surprising synergies, expressive party construction, and a fantasy world with personality. The design should reward discovering what a particular company can do, rather than converging on the most powerful lineup.

The game should have an authored reason to continue beyond mechanical mastery, and an ending that arrives before its combinations or stories become repetitive.

## Premise and tone

An adventuring guild has fallen from prominence. Its former legends are gone and its reputation is ruined. The only recruits willing to join are the heroes other guilds rejected: capable, eccentric adventurers whose impressive talents come with serious complications.

The player's job is not to **fix** these people. It is to find situations, companions, and tactics that make their unusual capabilities valuable.

**Tone:** Affectionate, witty fantasy adventure with genuine stakes. The cast can be funny without becoming a one-joke parade of incompetents. Their limitations should create mechanical possibilities and reveal character, not simply make them objects of ridicule.

**Long-term mystery:** What really happened to the legendary company that preceded this one, and why did the guild collapse? The answer should recontextualize some aspect of the guild or its heroes. The precise story is deliberately undecided.

## Primary design pillars

1. **Party identity over optimization.** A party should have a recognizable way of operating. Refining a favorite combination should remain rewarding without requiring the player to abandon its identity.
2. **Flaws as interacting rules.** Character drawbacks should create opportunities for interesting interactions, not function only as numerical penalties or occasional random mishaps.
3. **Understandable tactical consequences.** Players should be able to anticipate, test, and learn interactions. Surprises should feel discoverable in hindsight, not arbitrary.
4. **Authored personality and revelation.** Tactical play supplies the moment-to-moment enjoyment; character and guild discoveries supply changing context and motivation.
5. **Meaningful short adventures.** Each run should have a satisfying arc and distinct decisions. Repetition must not be justified merely by unlocking more content.

## Illustrative heroes (examples, not an approved roster)

| Hero | Apparent drawback | Possible tactical opportunity |
|---|---|---|
| **The Cowardly Knight** | Retreats or reacts poorly when directly threatened | Exceptionally strong protection when shielding an ally; withdrawal can reposition or bait enemies |
| **The Inaccurate Wizard** | Powerful spells do not hit their intended targets | Can exploit redirection, area effects, or deliberately manipulated targeting |
| **The Burdened Healer** | Healing transfers pain or harm to another party member | Creates tradeoffs involving damage absorption, sacrifice, and recovery |

**Illustrative synergy:** The wizard's errant projectile is redirected by the knight's defensive ability toward an advantageous target. The result is not simply “wizard damage + knight defense,” but a third behavior neither hero could produce alone.

These examples need mechanical scrutiny. In particular, **unpredictable targeting can feel unfair** if the player cannot understand or influence it. A worthwhile implementation might make the wizard's targeting deterministic but unusual.

A good synergy changes decisions and positioning, not merely a damage multiplier. Strong combinations should entail situational tradeoffs so that unusual party concepts remain viable.

## Candidate core loop

1. **Recruit / assemble:** Choose a party of approximately three from a roster of flawed adventurers. Consider relationships, capabilities, and a strategy worth testing.
2. **Prepare:** Select limited equipment, abilities, or expedition provisions that accentuate the company's identity.
3. **Undertake an expedition:** Navigate a short chain of tactical encounters, choices, and discoveries, with opportunities to adapt the plan.
4. **React and refine:** Observe what worked, what broke down, and what new interactions emerged. Improve the company without flattening its character.
5. **Return to the guild:** Resolve an outcome, advance guild-level discoveries, meet or deepen relationships, and decide what company to try next.

**Candidate cadence:** 20–40 minutes per expedition; a bounded authored campaign of roughly 10–15 hours. These are hypotheses to test, not fixed requirements.

## Tactical gameplay: questions to resolve

The original seed proposes **short tactical expeditions with positioning-based combat**. It does *not* establish whether combat is grid-based, turn-based, simultaneous, card-driven, or something else. Choose a format based on how clearly and enjoyably it exposes the hero interactions.

Investigate:

- What is the simplest tactical model that makes three distinct party abilities interact meaningfully?
- How much player control is appropriate over a hero's flaw? Can the player plan around it rather than be randomly punished?
- Can encounters challenge different party identities without hard-countering experimentation?
- How does failure feel? Losing a run should be consequential, but trying an interesting party should not mean 30 minutes of helplessness.
- Do skills and equipment deepen a party's character, or just increase its numbers?

**Avoid:** A complex taxonomy of classes, stats, statuses, and gear before proving that flawed-hero interactions are fun.

## Roguelite structure and progression

Roguelite runs provide an opportunity to test combinations under changing constraints. The guild provides continuity and narrative development.

A potential distinction:

- **Within a run:** Temporary items, encounter choices, and tactical adaptations influence how this specific company plays.
- **Between runs:** The guild develops, characters and relationships are better understood, and new authored possibilities become available.

Persistent progression should primarily expand **interesting choices and understanding** rather than provide mandatory numeric upgrades that render early challenges trivial. Failed expeditions may still reveal something valuable, but must not be reduced to resource farming.

Whether individual heroes persist across runs, retire, die, recover, or reappear is **open**. This choice has major implications for attachment, run stakes, and story continuity and should be decided deliberately.

## Character and narrative design

Characterization needs to be expressed through play. A hero's personality and flaw should influence both their tactical role and the situations in which they shine.

Use **authored character/party moments** selectively: encounters, rivalries, relationships, and guild revelations can become available through meaningful party composition or choices. Do not mistake a large pool of cosmetic dialogue permutations for narrative emergence.

A player who tries a new company should find a substantively different experience. A player who returns to a favorite company should have reasons to refine it rather than be forced to rebuild from scratch.

Narrative delivery should avoid repetitive rereading. Previously seen scenes should be skippable or concisely summarized where practical.

## Feedback: recognize the company the player built

The world should acknowledge the *specific approach* of a party. For example, a rescued client might be impressed by a clever defensive solution, alarmed by destructive magic, or become fond of a hero who unexpectedly saved them.

This is not a morality meter or a universal score. Feedback should help the player understand what their company is becoming and encourage iteration. Mechanically, the post-expedition report might highlight distinctive interactions or memorable actions rather than merely total damage and win rate.

## Major design risks

| Risk | Why it matters | First mitigation to test |
|---|---|---|
| **Obvious optimal combinations** | Party-building becomes a solved puzzle | Give combinations different strengths, costs, and tactical contexts rather than a single power ranking |
| **Frustrating flaws** | Players feel punished for experimentation | Make drawbacks legible, influenceable, and tactically consequential |
| **Shallow emergent narrative** | Reactions become predictable conditional scripts | Use authored revelations and distinct situational outcomes, not endless cosmetic variants |
| **Repetitive expeditions** | The same encounters are replayed to reach minor new dialogue | Make runs short, reveal substantial new possibilities, and offer a finite campaign |
| **Scope explosion** | Every new hero multiplies interactions and story combinations | Prototype a tiny roster and a small set of encounter primitives first |
| **Character identity erased by upgrades** | Optimization undermines the central appeal | Preserve defining flaws; let upgrades develop them rather than remove them |

## Smallest useful playable prototype

**Objective:** Determine whether assembling and playing a flawed-hero party is intrinsically enjoyable, before investing in a guild campaign or procedural content.

Build a tightly bounded tactical test with:

- **Three heroes:** knight, wizard, healer (or replacements with clearer systemic potential).
- **One arena and two or three encounter setups** that require different decisions.
- **One signature flaw and one meaningful strength per hero.**
- **A small set of environmental/positioning rules** that lets abilities alter one another's results.
- **Clear combat previews and post-action feedback** so players understand cause and effect.
- **At least one genuine decision** where exploiting a flaw is better than avoiding it.

Then add **one alternate hero** to test whether swapping a single party member creates a meaningfully different strategy. This is a more useful test of party authorship than immediately adding twenty heroes.

### Prototype success signals

- The player can describe the company's identity in their own words.
- The player intentionally engineers a synergy and enjoys watching it resolve.
- A different party member changes tactical decisions rather than only numbers.
- The player wants to try another configuration for curiosity, not to grind unlocks.
- The player can see why an encounter went wrong and propose a meaningful adjustment.

### Prototype failure signals

- Flaws are random annoyances best bypassed or upgraded away.
- Effective play consists of repeating a single ability combo regardless of situation.
- Interaction rules require so much explanation that discovery becomes work.
- Changing heroes barely changes the play experience.

## What this game is not trying to be

- An infinite run generator or retention treadmill.
- A competitive leaderboard or efficiency challenge.
- A sprawling RPG with every imaginable class, item, and status effect.
- A pure visual novel with tactical sections attached.
- A game that demands a community-approved meta to be enjoyable.

## Open decisions for the next design agent

1. What tactical format makes the *interaction of flaws* most readable and delightful?
2. Are flaws deterministic rules, conditional behaviors, player-directed risks, or a mix?
3. What does a **non-combat** expression of party identity look like, if any?
4. How do runs start and end, and how are stakes maintained without destroying attachment to heroes?
5. How is recruitment constrained to produce interesting company-building choices?
6. How does the guild story progress without forcing repeat runs through familiar material?
7. How can authored character moments coexist with systemic play without an impossible combinatorial writing burden?
8. What is the minimum additional hero or encounter needed to prove the concept has depth beyond a single clever interaction?

## Instructions to the next agent

Treat this as a **seed brief**, not an implementation specification. Preserve the central promise—*flawed people forming a uniquely effective company*—while freely challenging individual examples, proposed run lengths, progression structures, and combat formats.

**Next deliverable requested:** Explore two or three substantially different tactical implementations of the core idea. For each, show one concrete encounter, the player's decisions, an interaction between heroes, and what makes a second run meaningfully different. Evaluate their feasibility and prototype cost. Recommend a single thin vertical slice that can disprove the concept quickly. **Do not start implementation or produce a large feature backlog yet.**

## Player-preference context

This idea was selected from three roguelite seeds based on the player's documented preferences. Especially important: the player enjoys building systems with personality (Lorcana decks, Borderlands builds), authored surprises, meaningful feedback on creations, and multiple viable approaches. They lose interest when strategies converge on a prescribed meta, procedural reactions reveal a shallow repertoire, or repeated play no longer uncovers anything new.

The north star from the player's broader profile is:

> Give me something enjoyable to do, somewhere interesting to be, and something worth discovering.

For more background, provide the agent with `player-preference-profile.md` alongside this brief when available.
