---
name: discover-game-hook
description: Find a promising starting direction for a Mind Garage experiment using the player brief, tool constraints, several experience promises, adjacent-game research, and cheap probes. Use before choosing a game's hook or core mechanic, or when starting a fresh experiment. Hands a selected direction to explore-mechanic without automatically authorizing implementation.
---

# Discover a Game Hook

Find an experience worth investigating, not merely a slogan or an unusual rule. A hook can start prototyping or emerge from it. Do not make a finished USP a marketing-first gate.

## Inputs and record

Resolve paths from the repository root. Read:

- `AGENTS.md` for current constraints and authorization boundaries.
- `.lore/work/shared/audience/player-brief.md` for the intended player's preferences, not a fixed game recipe.
- `.lore/work/shared/research/game-hooks-and-player-promises.md` for source-backed distinctions and limits.
- The shared method and research foundations referenced by `AGENTS.md`.
- `.agents/skills/explore-mechanic/SKILL.md` for the downstream handoff.

Use `.agents/skills/discover-game-hook/templates/experiment-record.md` to start `.lore/work/games/<game-id>/experiments/<experiment-id>/record.md`. Choose a stable, unused ID; leave previous experiments intact. Fill only the sections relevant to the current stage. Unknowns and unrun tests must remain explicit, not invented results.

Snapshot the player brief and relevant procedure versions in the record: reference immutable commits when available; otherwise preserve input copies and content hashes. Record the prompt, important constraints, proposals, human decisions, and available agent/model identity. A fresh run may produce different ideas; reproducible procedure does not promise identical AI output.

Use Beads for actionable work. This record holds decisions and research evidence, not a duplicate task list. No game build, dependency installation, paid service, asset creation, or integration is authorized merely by requesting discovery.

## 1. Set the exploration envelope

Reuse settled decisions rather than asking them again. The current audience is Ronald alone and the engine is Godot; recheck current guidance in case it changes. Blender is optional. Distinguish user decisions from AI assumptions.

Identify the player experience being pursued and practical constraints. Leave nonblocking choices provisional. Verify tools and versions before relying on implementation capabilities; a version check is not proof of runtime or export support.

## 2. Offer distinct experience promises

Propose a small set, normally three, of meaningfully different directions. This is not the downstream six-variant mechanic exploration. Do not turn user examples explicitly marked as illustrations into proposals.

For each direction state:

- **Promise:** What the player might enjoy doing or feeling.
- **Anchor and hook:** The recognizable activity and its specific difference.
- **Candidate mechanic:** The action, decision, and visible consequence that could deliver it.
- **Run and unlock:** A bounded completion and a new possibility worth anticipating and using, where relevant to the player brief. It need not add power.
- **Risk and counterevidence:** Why it might disappoint and what would weaken the hypothesis.
- **Cheapest probe:** The smallest honest way to investigate the largest uncertainty.

Keep proposals specific enough to compare without designing full games. Explain tradeoffs and recommend a direction without claiming it is fun before play.

## 3. Check adjacent experiences

Research the closest relevant games using live sources, favoring official descriptions, developer accounts, or direct gameplay evidence. Record URLs, access date, what overlaps, and the proposed difference. Distinguish evidence from a developer's marketing claims.

Do not promise exhaustive novelty research or infer originality from AI authorship. If research is blocked, label comparisons provisional and report the gap rather than fabricating sources. No finding of a similar game automatically rules out a worthwhile variation.

## 4. Match probes to questions

Distinguish attention, comprehension, enjoyment, and voluntary replay. A pitch reaction or click cannot establish fun. Hypothetical interest cannot establish future play.

Use relevant past-play discussions for audience assumptions, representative descriptions or sketches for comprehension, and a tiny playable interaction when the uncertainty depends on play. Existing asset and implementation approvals still apply. Record predictions and decision criteria before observing results.

An optional probe should reduce uncertainty, not become a compulsory build before every decision. If no probe has run, say so. Ask Ronald which direction merits exploration; do not silently select a game on his behalf.

## 5. Hand off and stop

For the selected direction, pass `explore-mechanic`:

- Experiment ID and record path, input snapshot, and player brief.
- Player promise, hook, familiar frame, and adjacent-game findings.
- Candidate mechanic and the decision it lets the player make.
- Constraints, assumptions, open questions, and any probe evidence.
- Proposed comparison boundary and what would count against the idea.

The six alternatives are versions of this mechanic, not six unrelated game concepts. Revisit the promise if subsequent play reveals a better direction.

End discovery with a selected direction ready for agreed implementation, a pending user choice, or a justified decision to explore elsewhere. Do not auto-start a build, demand a winner, or automatically create another concept round.

## Repeat the method versus replay a build

For a fresh experiment, create a new record and input snapshot. Reuse procedure and tooling, not the prior game's conclusions as facts. Compare method outcomes such as human interventions, test usefulness, and effort only when recorded evidence supports it.

For replay, preserve exact build/source identity, Godot version, launch commands, dependencies, configuration, seeds, and save/progression state. Record instructions for independent variant selection and a clean reset. Use isolated experiment saves; never overwrite the player's existing progress to recreate a test.

Record exposure order and prior experience. Repeated sessions with Ronald are not independent participants, and resetting software cannot reset what he has learned.
