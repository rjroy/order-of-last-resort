# Company of Unlikely Heroes — Mission Proposals

## Purpose

Exploratory mission concepts for another design or implementation agent. These are **proposals, not approved specifications**. Preserve their distinct tactical objectives and test the identified risks before committing to implementation.

The guiding principle is: **The objective should be reliable; the heroes should be the source of complications.** If both the mission and the heroes behave unpredictably, players lose the ability to form meaningful strategies.

## Existing missions (context)

1. **Harpooners:** Defeat two short-ranged harpooners. A baseline combat-elimination objective.
2. **Ferryman Escort:** Escort a ferryman across a blocked bridge with an opponent guarding the exit. A baseline escort-and-obstacle objective.

The proposals below aim to test different tactical questions, preferably using existing hero abilities rather than accumulating mission-specific systems.

## Proposed missions

### 1. The Wrong Side of the Door

**Objective:** Get at least one hero through the exit.

**Setup:** A narrow corridor contains enemies and a locked gate. The gate opens when someone stands on a pressure plate, but closes when they leave.

**Interesting interaction:** The Rogue's *Confusing Dodge* could swap an enemy onto the plate; the Knight might push someone onto it. The player must coordinate characters who do not necessarily want to occupy the required positions.

**Risk:** Becomes a trivial positioning puzzle once solved.

**Test:** Does party composition meaningfully change the solution, or does one universal maneuver dominate?

### 2. Hold the Line

**Objective:** Survive six turns.

**Setup:** Enemies approach from two sides. The party need not eliminate them; reinforcements arrive after the survival window.

**Interesting interaction:** Knight pushes, Necromancer summons, and Rogue retreat can create or compromise a defensive formation.

**Risk:** Becomes a passive waiting exercise.

**Test:** Does enemy pressure escalate enough to require decisions every turn without turning the mission into an elimination fight?

### 3. The Unwelcome Guest

**Objective:** Remove an enemy from a designated area without killing them.

**Setup:** A stubborn troll occupies the village square. Villagers insist the troll must leave unharmed.

**Interesting interaction:** Pushes, pulls, fear, movement denial, and position swaps matter more than damage. This mission asks, “How do I make someone go somewhere they don't want to go?”

**Risk:** Becomes impossible or overly prescriptive for parties without the right displacement tools.

**Test:** Can several different party compositions achieve the goal through genuinely different approaches?

### 4. The Great Sheep Escape

**Objective:** Get three sheep into their pen.

**Setup:** Sheep wander away from nearby characters, including heroes. An opposing shepherd tries to drive them in the other direction.

**Interesting interaction:** Positioning and indirect manipulation replace ordinary attacks. A skeleton's enthusiastic wave might scatter an otherwise well-organized flock.

**Risk:** Uncontrolled sheep movement becomes frustrating rather than amusing.

**Test:** Can players predict sheep responses well enough to plan, recover from mistakes, and feel responsible for the outcome?

### 5. The Bridge Is Out

**Objective:** Reach the far side of a collapsing bridge.

**Setup:** Bridge sections disappear at predictable intervals. Heroes advance while navigating enemies and unstable terrain.

**Interesting interaction:** Rogue retreat, Alchemist ally-pursuit, and forced movement create unusual traversal and rescue situations.

**Risk:** Pathfinding and terrain timing overwhelm the interesting hero interactions.

**Test:** Are collapse rules clearly communicated, and do heroes' distinctive behaviors matter more than solving a movement algorithm?

### 6. Don't Wake the Giant

**Objective:** Retrieve a treasure without waking a sleeping giant.

**Setup:** Movement and abilities generate noise. The giant wakes once a noise threshold is exceeded.

**Interesting interaction:** Bard performances may be catastrophically loud; skeletons might distract the giant while others approach.

**Risk:** Stealth rules excessively restrict the player's ability to use their heroes.

**Test:** Are there multiple ways to manage or exploit noise, rather than one mandatory silent route?

### 7. The Unfortunate Ritual

**Objective:** Keep three ritual circles occupied simultaneously for two turns.

**Setup:** Enemies try to dislodge occupants. Any character—friend or foe—can activate a circle.

**Interesting interaction:** Rogue swaps, Knight pushes, and Necromancer summons create unusual ways to occupy and contest territory.

**Risk:** Becomes a rigid puzzle with one exact ability sequence.

**Test:** Can the player improvise when the original formation breaks, and can enemies be used constructively?

### 8. The Last Wagon

**Objective:** Protect a supply wagon until it reaches the village.

**Setup:** The wagon advances one tile per turn when no enemies are adjacent. Enemies prioritize attacking the wagon.

**Interesting interaction:** Knight displacement, Bard interruption, and Necromancer summons can maintain a moving defensive perimeter.

**Risk:** Feels too similar to the existing ferryman escort.

**Test:** Does the wagon's adjacency-based movement and enemy targeting create distinct decisions, or is this just another escort with different dressing?

## Comparison

| Mission | Primary challenge | Distinctive mechanic | Main design risk |
|---|---|---|---|
| The Wrong Side of the Door | Positioning | Pressure plate | One solved trick |
| Hold the Line | Survival | Turn limit | Passive waiting |
| The Unwelcome Guest | Nonlethal control | Forced movement | Mandatory party composition |
| The Great Sheep Escape | Herding | Reactive civilians | Opaque/random movement |
| The Bridge Is Out | Traversal | Changing terrain | Pathfinding dominates |
| Don't Wake the Giant | Stealth | Noise | Overly restrictive play |
| The Unfortunate Ritual | Area control | Simultaneous occupancy | Single prescribed solution |
| The Last Wagon | Defense | Moving objective | Redundant escort |

## Recommended prototype order

1. **The Unwelcome Guest:** Strongest immediate candidate. It fundamentally changes the objective from dealing damage or reaching an exit to nonlethal displacement, making existing positional abilities valuable in new ways. Validate that different hero rosters remain viable.
2. **The Unfortunate Ritual:** Tests multi-point area control and constructive use of enemies as occupants. Validate that it supports improvisation rather than one exact sequence.
3. **The Great Sheep Escape:** Strong thematic fit for the game's comedy and personality. Validate that reactive civilian movement is legible and enjoyable, not arbitrary.

These are design priorities, not an implementation schedule.

## Cross-cutting design risks and guardrails

- **Readable causality:** A player should understand why a sheep fled, a gate closed, a bridge collapsed, or a giant woke. Surprises should come from hero interactions, not hidden mission rules.
- **Avoid hard party locks:** Missions should not silently require one particular hero or ability unless explicitly framed as a roster-specific challenge. Test alternate solutions.
- **Avoid solved-once puzzles:** Positioning objectives need enough variation in enemy pressure, timing, or team behavior to remain interesting after the obvious trick is discovered. Do not add randomness solely to prevent solutions.
- **Avoid passive objectives:** Survive-X-turns and moving-defense missions need recurring meaningful decisions, not simply waiting for a counter.
- **Avoid redundant mission identities:** In particular, compare The Last Wagon against the existing ferryman escort. Keep it only if the mechanical experience is distinct.
- **Don't overbuild mission systems:** Prefer missions that reveal new uses for existing abilities. Introduce pressure plates, noise, terrain collapse, or herding rules only when they create enough tactical value to justify their complexity.
- **Preserve playful imperfection:** Hero flaws should produce exploitable tactical consequences rather than arbitrary punishment. The player should be able to build a plan around their peculiarities.

## Questions for the next agent

1. Which mission can be tested with the fewest new mechanics while proving a genuinely new tactical pleasure?
2. For each objective, what happens if the party has no dedicated pusher, swapper, or summoner?
3. Can players recover from a mistake, or does one unexpected hero action force a restart?
4. Does the mission create new decisions on a second attempt, or just repeat the same solution?
5. What is the smallest playable encounter that could disprove the idea's appeal?

**Do not assume** the above rules are finalized, that all heroes have been implemented, or that every proposal belongs in the shipped game. Prototype to discover which objectives make the unlikely heroes interesting to command.
