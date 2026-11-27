---
name: combat-balance-report
description: Generate a readable snapshot of stock combat abilities and starting health, including permanent guild unlocks. Use when asked for a combat balance report or a comparison with a saved report.
---

# Combat Balance Report

Produce a readable Markdown reference for the current stock game, not a tuning proposal or a tool. Include all permanent guild unlocks, whether or not a particular guild owns or equips them. Exclude per-adventure upgrades and rewards entirely. Do not change game content or player saves.

## Establish the snapshot

1. Read `AGENTS.md`, the game guide, `games/company-of-unlikely-heroes/content/README.md`, and the current stock manifest `games/company-of-unlikely-heroes/content/catalog.json`. Follow its parts, rather than treating every JSON file on disk as shipped content. Include stock missions, their actors, objects, reserves and objectives, the recruitment roster, and permanent guild progression and training.
2. Resolve effective character profiles using the whole-field class/character merge in `content/catalog.gd`. Follow kits, permanent ability grants, alternative loadouts, behaviors, statuses, traits and the relevant handlers in `rules/` to determine what actually happens. Check encounter placement HP overrides and summon construction. Include rules-driven effects and meaningful conditions, not just labels or descriptions. Use the current checkout including uncommitted changes; record the date, commit ID and whether the checkout is dirty.
3. Inventory each reportable ability ID used by a stock hero, opponent, summon or other stock actor, including permanently unlocked alternatives. Record its source and users, including shared or borrowed uses. Distinguish an actual ability from a standing order that selects or uses one, and from a passive technique or trait. Exclude definitions only reachable through per-adventure upgrades, even when included in the stock manifest. Do not rely on a player profile, test fixtures, or old commit history.
4. If the user supplies a prior saved snapshot, compare it with this one and identify meaningful changes in abilities, effects, starting HP and permanent techniques. Name the prior snapshot and distinguish additions, removals and changes. If none is supplied, say this is the first snapshot and make no historical claims. Do not search old commits for a baseline.

## Write the report

Use plain names and short phrases. Cite source paths in a compact sources section so a reader can trace the facts; use IDs only when needed to disambiguate. State any unresolved uncertainty rather than inventing a value. Do not claim a mechanic is balanced or enjoyable solely from the numbers.

### Abilities

Use Markdown tables grouped by actor or another readable grouping, with exactly one row per distinct reportable ability. Use columns **Ability**, **Users**, **Strength**, **Effect**, and **Side effects / conditions**. List all users of a borrowed or shared ability on its single row rather than repeating it. If a shared ability has materially different effective results by user, show the differences concisely in that row. Fitted forms may appear as conditional effects in their base ability row; distinct named campaign abilities get separate rows.

- Bold the numerical strength, including units and relevant qualifiers: for example, **2 damage**, **1 HP healed**, or **1 tile**. Identify damage, healing, protection, movement or control in the effect column. Use a clear nonnumeric strength such as **No direct damage** when appropriate; do not invent a numeric rating.
- Summarize the important target, range, timing, limits, secondary effects and friendly-fire risks concisely. Describe conditional or random results as conditional or random, not guaranteed. Pure movement and control abilities may be compact, but must not disappear.
- Distinguish listed values from effective values only when they differ, and explain the cause briefly. Account for applicable permanent passives and conditional combat modifiers without presenting them as unconditional base strength.
- Cover permanent passive techniques and consequential actor traits separately in a concise section, explaining how they modify actions or combat. Summarize standing orders separately as ways of choosing or executing abilities, not duplicate ability rows. Include permanently unlocked orders and note relevant equipment compatibility.

### Starting health

Present heroes first, then opponents and other characters, then damageable objects and objectives. Give each stock definition's starting and maximum HP, noting mission and placement where starting HP differs, including zero-HP placements or reserves. Identify objective subjects in the appropriate group. Give summon starting HP and any corpse-dependent formula separately, including rounding. Do not imply carried wounds or per-adventure changes are starting values.

### What this means

Use one shared section to explain what damage values mean in terms of HP, using a concrete example from this snapshot. Explain healing and damage reduction or other qualifications only as needed to interpret that example. Do not repeat this explanation for every ability or turn the section into balance advice.

Include a short comparison section only when a prior snapshot was supplied, and a sources and limitations section. Keep the report approachable rather than packing every internal field into the tables.

## Save and return

Before saving, reconcile the exact in-scope ability IDs and their source/use relationships against the actual table rows, including every permanent ability grant and its recipient. Add missing rows or users, remove duplicates and outing-only rows, and resolve mismatches. Counts or mentions elsewhere in the report do not establish coverage. Keep row labels human-readable; IDs need not appear in the table.

Save every report as a new Markdown snapshot under `.lore/local/combat-balance-report/`, using a timestamp and a collision-safe suffix if necessary. Never overwrite an earlier snapshot. Ensure `.lore/local/` is ignored before writing: follow the lore-development `shared/frontmatter-schema.md` local-storage instructions and its `scripts/ensure_local.py` helper, resolving the installed plugin path rather than assuming a machine-specific location. Use the schema's common frontmatter fields for the snapshot. Return a Markdown link to the saved report and mention any material gaps. Do not modify tracked files, generate code, or run tuning exercises as part of producing the report.
