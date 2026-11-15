---
name: explore-mechanic
description: Explore a new game mechanic through six alternative versions, build minimal independently playable variants, screen them with automated diagnostics, and compare human playtest evidence. Use when introducing a mechanic or when asked to explore mechanic variants or find the fun. Not six scenarios using an unchanged mechanic.
---

# Explore a Mechanic

Make exploration part of introducing a mechanic. Do not commit to the first plausible design or confuse mechanical correctness with fun.

The default is **one mechanic, six alternative versions**. Six is a project exploration convention, not a research-backed optimum. A smaller surviving set must have recorded screening evidence; do not silently propose fewer alternatives to save effort.

## Scope and inputs

Read the repository's `AGENTS.md` and the shared foundations, resolving paths from the repository root:

- `.lore/work/notes/ai-game-design-experiment.md`
- `.lore/work/notes/ai-design-novel-fun.md`
- `.lore/work/notes/what-makes-games-fun.md`

Use the current experiment's scope and decisions. If they are not settled, establish the intended audience, development constraints, telemetry and consent approach, recruitment, comparison design, correctness checks, decision criteria, and stopping criteria before implementation. Ask only for decisions that block progress; reuse settled choices.

Read `.lore/work/intents/player-brief.md`. When no direction has been selected, use `discover-game-hook` before generating mechanic variants. Continue the selected experiment's `.lore/work/experiments/<experiment-id>/record.md`; use `.agents/skills/discover-game-hook/templates/experiment-record.md` if starting a record. Preserve its input snapshots, provenance, and replay manifest. For unlocks, test both anticipation and payoff; provide direct preview access so comparison does not require repeated grinding, and distinguish previews from naturally earned unlocks.

Invoking this skill to explore and build a mechanic authorizes that bounded work, subject to project approvals. Asking to define or discuss the skill does not authorize an experiment. Do not silently expand into a complete game, install dependencies, generate assets, or integrate into another experiment without the applicable authorization.

Track actionable work in Beads. Store hypotheses and evidence in the experiment's versioned records, not in a second task backlog. Keep experiments independently attributable and follow the Godot constraint in `AGENTS.md` without inventing a shared framework.

## 1. Frame one mechanic

State:

- What action the player takes, what changes in the game, and what feedback they receive.
- What decision or tension might make the action enjoyable for the intended players.
- The mechanic's originating proposal, claimed distinctive features, and human contributions.
- The boundaries of this exploration and what remains constant across versions.

If the user has not supplied a mechanic, propose one within the agreed scope. Do not claim originality merely because AI proposed it. Agency, mastery, connection, and absorption are possible explanations to investigate, not mandatory ingredients or proven recipes.

## 2. Propose six alternative versions

Give each version a stable ID, a neutral player-facing label, and a short specification:

| Field | Required content |
| --- | --- |
| Rule difference | How this version changes the mechanic's decisions, consequences, or feedback |
| Enjoyment hypothesis | Why that difference might improve the intended player's experience |
| Prediction | What observable results would support the hypothesis |
| Counterevidence | What results would weaken it |
| Risk | What could worsen or confuse interpretation |
| Diagnostic | The controlled checks appropriate to this version |

Explore meaningfully different alternatives, not six situations using the same rules. Numerical changes count when they test distinct player-experience hypotheses; six arbitrary tuning values do not.

Distinguish shared rules, mechanic alternatives, and tuning/constraint comparisons. Do not present action costs, range limits, deadlines, or caps alone as proof of mechanic diversity. A constraint-based alternative needs an explicit account of the worthwhile decision or possibility it enables, not merely an added penalty. If the task is to find a useful combination of constraints, label it as that experiment rather than implying six fundamentally different mechanics. Preserve user criticism and resulting decisions in the experiment record; do not rewrite the original proposals to hide the learning.

Keep unrelated presentation, content, goals, and session conditions consistent enough for useful comparison. Change a coherent design dimension where practical. When alternatives change several coupled rules, record the bundle and limit causal claims accordingly.

## 3. Build minimal playable variants

Implement the smallest faithful version of each alternative. Reduce surrounding scope, not the rule difference being tested. Share a test harness or implementation where useful, but avoid designing a general-purpose framework for hypothetical needs.

Each variant must be independently selectable and playable without completing another variant first. Provide:

- A direct launch command, link, or explicit selector entry.
- Brief controls and an accurate explanation of its rules and goal.
- Reset and replay controls, with state isolated between runs and variants.
- Comparable starting conditions and reproducible seeds where appropriate.
- A visible variant/build identifier so feedback can be attributed correctly.

Do not prime players with claims that one version is better. Keep explanations equally clear across variants. Use the project's UI/design specialist for interface judgment and the appropriate technical builder for implementation. Follow applicable implementation and verification workflows without duplicating them here.

## 4. Diagnose and screen

Write and run mechanic-appropriate tests with controlled, test-owned inputs. Check correctness and progression, including invalid states, crashes, deadlocks, completion, and reset isolation as applicable. Test variant selection and rule differences, not only shared infrastructure.

Use reproducible simulations or multiple strategies where helpful to investigate action consequences, apparent dominance, repetition, or sensitivity to starting conditions. Preserve commands, exit statuses, seeds, traces, and relevant results.

Repair implementation defects rather than presenting them as evidence against a design. A variant may be ruled out when reproducible evidence shows that its rules violate an agreed constraint or defeat its stated design premise. Record the evidence and interpretation limit. If a rule-level contradiction can be demonstrated before a playable build, retain that analysis instead of building a known-invalid version merely to reach six builds.

Weak bot performance, apparent strategy dominance, repetition, or an AI critique alone does not establish that a variant is unfun. Treat ambiguous findings as reasons to investigate or flag the variant for human play, not as automatic elimination criteria. AI personas are hypotheses, not independent player evidence.

Maintain a disposition for all six proposals: playable, excluded with evidence, or blocked. Blocked and unbuilt variants are not tested exclusions. If none survive, report that result and propose the next exploration rather than inventing a winner.

## 5. Offer individual human playtests

Verify every surviving variant's launch, controls, core interaction, reset, and replay through the available runtime checks. State any unverified manual steps explicitly. Deliver a compact variant index containing IDs, neutral rule summaries, launch instructions, build identifiers, and known limitations. Include excluded variants and their reasons separately.

Let the user test each survivor individually. Suggest comparable play segments and varied or randomized order when practical to reduce learning and order effects. Do not force players to finish all variants or collect unnecessary personal data.

Use a small post-play report:

- How much did you enjoy that run, from 0 to 10?
- Would you like another run?
- Optional: What most affected your answer?

Measure actual voluntary replay separately from stated desire. A requested comparison run is not voluntary replay. Add targeted questions only when they test a specific explanation.

Associate reports and necessary consent-based telemetry with experiment, variant, build, session, and relevant prior experience. Keep event definitions stable. Distinguish genuine exits from crashes and lost events. Do not silently add tracking or an external analytics service.

Call this comparative playtesting unless assignment, exposure, and sample design support a formal A/B or multivariant experiment. Do not claim statistical or causal certainty from informal sequential testing.

## 6. Compare and revise

Compare against a declared reference version or existing baseline, using measurements and decision criteria chosen before inspecting candidate results. A reference is a comparison anchor, not a presumed winner.

Keep enjoyment, desire to continue, and voluntary replay separate. Investigate disagreements between telemetry and reports. Account for player experience, learning, exposure order, uncertainty, and audience differences. Do not select a winner solely from an average score, retention, session length, strategy diversity, or simulation performance.

For each revision, retain:

1. Observation and supporting evidence.
2. Competing explanations where evidence is ambiguous.
3. Hypothesis and possible disconfirmation.
4. Prediction, including what might worsen.
5. Bounded intervention.
6. Baseline/candidate comparison, uncertainty, and conflicting signals.
7. Keep, revert, or investigate decision with reasons.

Preserve failed variants, excluded proposals, builds, seeds, and test conditions. Record human-supplied diagnoses and selected changes. Changes to criteria start a documented new comparison; do not rewrite earlier success criteria after seeing results.

Stop at the agreed boundary. The outcome may be a preferred candidate, multiple promising versions, insufficient evidence, or no viable version. Do not force a ranking or automatically start another six-way round. If human playtests are pending, hand off the verified playable set and leave enjoyment conclusions open.

## Completion and handoff

Provide:

- The mechanic framing and six-version hypothesis matrix.
- The disposition of every proposal, with screening evidence for exclusions.
- Individually playable survivors and verified launch/reset instructions.
- Automated test evidence and any verification gaps.
- A playtest comparison record, or clear instructions if human testing is pending.
- Separate game and method findings: player enjoyment and replay versus usefulness of AI diagnostics, predictions, and revisions, including human interventions.
- A bounded recommendation and remaining uncertainties.

A working prototype is not proof of fun. A successful variant is not proof of originality or general AI design capability. Claims that this method saves development effort require comparison of iteration cost and results.
