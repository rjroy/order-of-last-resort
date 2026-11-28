---
name: combat-balance-report
description: Generate deterministic stock combat fact tables or compare saved reports.
---

# Combat Balance Report

Generate the four scripted HP and ability/effect tables, not a tuning proposal.
Use the current checkout, including uncommitted changes. Do not change game
content, player saves, or tuning.

1. Read `AGENTS.md`, the game guide, and
   `games/company-of-unlikely-heroes/tools/combat_balance/README.md`.
2. Ensure `.lore/local/` is ignored. Create an existing parent directory under
   `.lore/local/`, then run the documented `report.py` command with a new,
   collision-safe output directory. The script exports the loaded stock catalog
   and writes four TSV tables and an offline HTML view. Never overwrite a report.
3. Return a link to `index.html` and identify material limitations. The tables
   include permanent guild grants but exclude expedition-only upgrades and
   rewards, including House Lights. Fitted forms and uninterpreted effects are
   not fully computed; consult the cited tool documentation and rules when
   interpreting them. Base values are not guaranteed outcomes.
4. If a prior report was supplied, compare its four TSV files with the new ones,
   identify meaningful changes and name the baseline. Do not invent a baseline
   or infer balance or enjoyment from the values.

Reports and exports are generated evidence only and belong under ignored
`.lore/local/`; they are not required runtime inputs or tracked source.
