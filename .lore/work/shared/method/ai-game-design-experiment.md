# Experiment: AI-led development of a gripping game

## Research question

Can AI originate a central game mechanic and drive its refinement into something players enjoy and voluntarily return to, using automated validation, behavioral analytics, and player reports?

Human playtest feedback is part of the process, not a disqualification from AI-led design. The experiment concerns repeatable engagement rather than artistic significance or a primarily one-time experiential game. These categories can overlap; they are a scope distinction, not a universal classification.

Status: exploratory experiment brief. This proposes a method, not an established result or authorization to implement a particular game.

## Working hypothesis

Automated checks can reject broken designs, expose mechanical weaknesses, and shorten iteration. Human play is needed to establish whether the surviving designs are enjoyable. Combining those sources may let AI make productive design revisions without humans supplying the diagnosis or solution.

The research summaries in [[what-makes-games-fun]] suggest agency, mastery, and absorption as useful hypotheses to investigate, not a universal recipe. Enjoyment, desire to continue, and actual replay should remain separate measurements.

## Scope

Start with one small, replayable prototype centered on a mechanic proposed by AI. Record the originating proposal and human contributions so that AI-led design is distinguishable from AI implementation of a human design.

The prototype should be small enough to revise repeatedly. It does not need to invent a genre. Document what is claimed to be distinctive about the mechanic; do not claim originality merely because AI proposed it.

## Validation layers

### 1. Automated mechanical diagnostics

Use controlled scenarios, reproducible seeds, and multiple agent strategies where appropriate. Candidate checks include:

| Check | Evidence produced | Interpretation limit |
| --- | --- | --- |
| Sessions can progress and finish without invalid states or deadlocks | Failing seeds, state traces, completion results | A functioning game is not necessarily enjoyable |
| Alternative choices can affect outcomes | Controlled comparisons of action consequences | Consequences alone do not establish interesting agency |
| Compare strategy performance across starting conditions | Strategy results and uncertainty by scenario | Apparent dominance may reflect weak opponents or limited search |
| Compare agents with different capabilities | Performance under comparable conditions | Bot capability is not equivalent to human mastery |
| Detect repeated actions and policy collapse | Action sequences and strategy concentration | Repetition can be enjoyable and is not automatically a defect |

Select checks to fit the actual mechanic. Treat non-correctness checks as diagnostic signals, not universal pass/fail definitions of fun. AI-generated player personas or critiques are hypotheses, not independent player evidence.

### 2. Human-play telemetry

Record game version, experimental variant, session boundaries, relevant player experience, choices and available alternatives, outcomes, progression, failures, retries, and voluntary replay. Capture timing where it helps distinguish explanations.

Use stable event definitions so versions can be compared. Separate genuine exits from crashes or lost telemetry. Collect only necessary data with appropriate player consent.

Drop-off is a clue, not a diagnosis. Stopping may indicate frustration, boredom, interruption, or a satisfying endpoint.

### 3. Player reports

After an appropriate play segment, ask a small number of questions:

- How much did you enjoy that run, from 0 to 10?
- Would you like another run?
- Optional: What most affected your answer?

Use occasional targeted questions about agency, competence, absorption, or repetition when testing a specific explanation. Avoid interrupting every session with a questionnaire.

Reports are fallible, and telemetry is ambiguous. Investigate disagreements rather than automatically privileging either source. Associate reports with the relevant game version and session.

## AI-directed iteration protocol

For each revision, retain an experiment record containing:

1. **Observation:** What happened, supported by reports, telemetry, or automated results.
2. **Competing explanations:** More than one plausible cause where the evidence is ambiguous.
3. **Hypothesis:** The explanation being tested and the evidence that could contradict it.
4. **Prediction:** What should change, and what might worsen.
5. **Intervention:** A bounded mechanic or tuning change.
6. **Comparison:** Baseline and candidate results, including uncertainty and conflicting signals.
7. **Decision:** Keep, revert, or investigate further, with reasons.

Choose measurements and decision criteria before reviewing the candidate's results. Preserve versioned builds and test conditions. Account for learning, player experience, and exposure order when comparing versions; use randomized assignment when practical. Small samples support provisional decisions, not strong general claims.

Record human interventions, particularly when a human supplies a diagnosis, selects the design change, or rejects the AI's interpretation. These contributions matter to the capability question.

## Example experiment

**Observation:** Players report repetition, and exits cluster after the first upgrade.

**Competing explanations:** The upgrade makes one strategy obviously best; encounters lack variety; or the decision sequence is exhausting.

**Selected hypothesis:** The upgrade eliminates meaningful strategic alternatives.

**Automated investigation:** Compare strategy performance before and after the upgrade across controlled starting conditions.

**Intervention:** Revise upgrade trade-offs without simultaneously adding encounters or changing session length.

**Human comparison:** Examine enjoyment reports, perceived choice, strategy usage, and voluntary replay across versions. Check whether players understand the revised trade-offs.

**Interpretation:** More strategy diversity alone is not success. The revision should produce evidence consistent with improved player experience, without hiding contrary results.

## What the experiment should establish

Evaluate two outcomes separately:

### Game outcome

Does the prototype produce repeatable enjoyment for its intended players? Do revisions improve that experience relative to a baseline? Set practical thresholds only after selecting the game, audience, and feasible testing conditions.

### Method outcome

- Which automated diagnostics helped identify productive revisions?
- Which signals failed to predict enjoyment or encouraged misleading changes?
- Did the AI's predictions hold up in subsequent playtests?
- Could AI distinguish competing explanations and choose informative tests?
- Where did human diagnosis or design judgment remain necessary?

A disappointing game can still produce a useful experiment. Conversely, one successful game does not establish that the method works generally. Claims that automation accelerates development require a comparison of iteration cost and results, not merely a successful final build.

## Guardrails

- Do not equate retention, session length, or urge to continue with enjoyment.
- Do not equate simulation performance with human experience.
- Do not treat plausible retrospective explanations as validated causal accounts.
- Do not optimize a single enjoyment score while ignoring audience differences or contradictory evidence.
- Do not silently change success criteria after seeing results.
- Preserve failed experiments as well as improvements.

## Decisions for a project-specific plan

Before implementation, select the prototype and intended audience, development constraints, telemetry platform, playtest recruitment method, comparison design, and stopping criteria. Define executable correctness checks and experimental decision thresholds for that particular game.

## Context

- [[ai-design-novel-fun]]: original discussion of AI-assisted development and the limits of the retained evidence. The present question does not require AI to work without human playtest feedback.
- [[what-makes-games-fun]]: selective research starting point distinguishing psychological need satisfaction, absorption, and meaningful appreciation. Its findings do not establish automated rules for fun.
- This brief records an exploratory discussion and proposed experiment. No prototype or experiment results are asserted here.
