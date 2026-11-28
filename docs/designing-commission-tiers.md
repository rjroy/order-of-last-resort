# Designing commission tiers

This is the `olr-8xe` design for which missions can appear at each commission
slot. Use [Designing balanced road missions](designing-road-missions.md) to
design the individual choices and [Designing balanced commission
finales](designing-commission-finales.md) for the named destination. Tier
assignment sets the intended pressure for a slot; it does not prove balance.

## Slot schedule

Both commission lengths count the finale as a mission. The board keeps two
five-mission offers and one ten-mission offer with three distinct destinations.

| Mission slots | Tier | 5-mission commission | 10-mission commission |
|---|---|---|---|
| 1–2 | T1 | Road | Road |
| 3–4 | T2 | Road | Road |
| 5 | T3 | Finale | Road |
| 6–7 | T4 | — | Road |
| 8–9 | T5 | — | Road |
| 10 | T6 | — | Finale |

The current destinations share one provisional pool eligible for both finale
slots, with no encounter retuning. T3 roads and T3 finales are separate pools.
Plan and balance the future T3 and T6 finale populations separately; this
design does not set a target count for distinct finales.

## Forks, clues, and coverage

- Each fork offers two missions from the current slot's tier, of two different
  kinds. The choice is about what kind of pressure to face, not whether to skip
  to a different tier.
- The onward clue promises a **kind** available in the **next** road slot's
  tier, even at a tier change. Exactly one option at the next fork matches the
  chosen clue. Both reports at the last fork lead to the named destination
  instead.
- Prefer unvisited **base missions** within the eligible kind. If those are
  exhausted, prefer a base other than the one just played when possible.
  Never break a clue or draw out of tier to avoid a repeat.

The minimum coverage gate is **at least two represented road kinds at each of
T1, T2, T3, T4, and T5**. This keeps every fork and promise possible without
requiring a repeat-free run. Stock has 32 road reports across T1–T5, plus nine
finales. It meets the minimum gate but does not guarantee a repeat-free run. The
historical
[road audit](../.lore/work/games/company-of-unlikely-heroes/notes/commission-tier-road-audit.md)
records a proposed pool, not proof that pressure rises at the intended pace.

Longer term, aim for **about 20 road options per tier at T1–T5**. Roughly 80
distinct road bases overall is a planning estimate, with some bases supplying
variants at more than one tier. Neither number is a validation threshold or a
finale target.

## Authoring and compatibility

Set `commission_settings.tiered` to `true` to opt the entire commission
catalog into the schedule. Stock opts in. Each reported road mission in a tiered
catalog must have a whole-number `missions.<id>.tier` from 1 through 5; this
field controls its route eligibility. To migrate a custom tiered catalog,
remove the retired `road_tier` from every report, assign each road mission its
intended tier, and ensure at least two road kinds are represented in every tier.
Reports still determine pool membership, and destination tiers do not filter
the destination pool. A custom
commission catalog with `tiered` absent or `false` keeps the same validation
requirements and seeded route selection as before, with no slot-tier filter.
Legacy selection is not a fallback for a tiered catalog.

Give a variant its own mission ID and report. Its authored `encounter` ID says
what opens on the board; it can point to an existing encounter. Use the exact
variant ID to deploy the battle. The optional `base_mission_id` identifies the
original mission for repeat checks. A mission without a base reference is its
own base.

For HP tuning, author `enemy_max_hp` as a map from enemy placement IDs in
that encounter to positive whole maximum HP values. The encounter can still
specify a lower starting `hp`. Keep the original mission and standalone opening
intact. Enemy HP does not scale with the heroes' wounds, recruits, or upgrades.

Stock reports look for art for the exact mission ID first, then use base art
only if both missions share the same encounter ID. A changed or new encounter
without exact art falls back to text for prototypes. `light_hook_pair` and
`crossfire_blast_lane` now have their own
[child-scout sketches](designing-road-missions.md#design-the-field-report-image-with-the-mission).
Don't hide a blank by borrowing a misleading picture: the Harpoon Squad sketch
shows a Bruiser the lighter Hook Pair doesn't have. Custom catalogs keep their
existing presentation behavior. Write each report for the variant actually
offered; the onward clue describes only the next mission's kind.

Ship stock variants in a part registered only in the
[default manifest](../games/company-of-unlikely-heroes/content/catalog.json),
not the practice manifest. The [catalog guide](../games/company-of-unlikely-heroes/content/README.md#authoring-commission-reports)
describes the report and deployment conventions.

## Balance against successive arrivals

Start with an unupgraded founding company and record rounds, direct commands
spent on progress versus recovery, remaining HP, and heroes fallen. Then play
successive legs through actual forks: survivors carry their wounds, fallen
heroes return at 1 HP, and rewards depend on what was offered and chosen. Test
plausible wounded arrivals with more than one legal company. An isolated win
with full health does not establish that the next road is fair after the
previous one, and a coverage check proves only that the route can be drawn.
