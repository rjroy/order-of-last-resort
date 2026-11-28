# Road balance rules probe

## Deterministic baseline

After the project has been imported with Godot 4.7.2, run once per case:

```sh
python3 games/company-of-unlikely-heroes/tools/road_balance/baseline.py --suite catalog --out .lore/local/reports/road-balance/catalog-baseline
```

The output directory must not exist, and its parent must already exist. Use a
new path for every run. `--suite pilot` selects the smaller pilot instead.
The command launches one headless Godot process with isolated XDG directories.
It writes `cases.html`, one-row-per-case `cases.tsv`, `raw.json`, `run.log`,
and `provenance.json`. Open the HTML locally to sort and search cases; agents
can select specific TSV rows. Raw data is machine input, not a document to load
wholesale.
The setup column records opening units, positions, orders and effective settings.
The Tier column shows the authored mission `tier`; a blank means unassigned or
not recorded in an older report. It is not inferred from results.
Victory ending wounds use projected carryover; non-win wounds use terminal HP,
identified by `ending_kind`. Round limits are indeterminate.
`damage_dealt` is HP lost by enemies and `damage_received` is HP lost by heroes:
both are classified by recipient side, include friendly fire, and exclude objects
and civilians.

To normalize a previously generated raw report with damage telemetry, use
`baseline.py --input path/to/raw.json --out path/to/new-directory`. Legacy raw
reports without `damage_dealt` and `damage_received` fail rather than estimate.
Offline provenance describes the adapter checkout, not the original run.
On failure, the new directory and any logs remain for inspection; choose a
different new path for another attempt.

To create an HTML view of an existing TSV without Godot or raw JSON:

```sh
python3 games/company-of-unlikely-heroes/tools/road_balance/cases_html.py path/to/cases.tsv --out path/to/cases.html
```

The HTML destination must not exist. The view works offline and the TSV remains
its source. Historical briefs are untouched. For a separate short
carryover-first comparison without sending raw records to a model:

```sh
python3 games/company-of-unlikely-heroes/tools/road_balance/brief.py result.json --baseline baseline.json > brief.md
```

The baseline is optional. Comparisons require identical case identities; carryover
changes compare only cases won in both runs. Full details remain in the raw JSON.

From the repository root, with Godot 4.7.2:

```sh
godot --headless --editor --path games/company-of-unlikely-heroes --import
godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtester_test.gd
report_dir=$(mktemp -d /tmp/opencode/olr-road.XXXXXX)
godot --headless --path games/company-of-unlikely-heroes --script res://tools/road_balance/road_balance_cli.gd -- --suite=pilot --report="$report_dir/pilot.json"
godot --headless --path games/company-of-unlikely-heroes --script res://tools/road_balance/road_balance_cli.gd -- --suite=catalog --report="$report_dir/catalog.json"
```

The output path is required, must not already exist, and its parent must exist.
Use a fresh destination for every run; existing reports are refused.
The pilot runs the four authored Big Windup missions (tiers 2–5), plus bridge
patrol and explosive situation as references. The catalog suite screens the
union of commission road report IDs, the ten Experiment 007 standalone road
roots, and every authored mission whose `base_mission_id` names one of those
roots. It deduplicates and sorts mission IDs, includes linked commission
variants and Crossfire, and excludes unrelated missions and destinations. It
does not change catalog tuning.
Each uses Knight, Healer and Wizard, or Knight, Alchemist and Bard; each starts
fresh or with two HP removed from each hero (minimum one). These use legacy
standalone character defaults, not guild recruitment loadouts: Knight starts on
Guard, Healer on Support, Alchemist on Follow closest ally, and Wizard and Bard
on Hold (`order_cautious` and `order_hold` respectively). The no-Wizard cases run only forecast_first:
wizard_first has no Wizard and otherwise uses the same fallback policy.

The two policies enumerate legal direct commands on the actual before-action
board and forecast full rounds. forecast_first ranks health, defeats, victory
and a small proximity tie-break. wizard_first prefers a feasible hostile
Blast, then uses the same forecast ranking. These deliberately simple
heuristics are not a human player and the decision scores are only internal
ranking aids, not a pressure, fun, tier or balance score. They can miss plans,
including beneficial sacrifices or delayed tactical setup. Ties follow authored
iteration order. A round cap is indeterminate, not proof of unwinnability.

Every round retains the chosen draft and raw events plus the standing-order
forecast events and both decision scores. `standing_events` is a one-round
counterfactual from that round's actual starting state; it is not a separate
standing-orders-only run. Compare these forecasts when examining
marked tiles, dodges, bait, suppression and cleanup; activity can be movement or
a harmless mark rather than damage. `enemy_actions_by_round` counts distinct
enemy actors with a resolved action or windup mark/strike, excluding holds,
recovery and skipped turns. Check raw damage and marks separately. `ending_hp`
records final HP, including zero for fallen heroes, for every outcome.
Only a victory includes `carryover_hp`, a projection using one for fallen heroes,
not an applied commission transition. Fallen IDs remain separately recorded. Opening
positions, HP and orders are recorded per case. Positions are Godot's zero-based
coordinates rendered as strings in JSON.

These are isolated rules-level runs. They do not simulate a real succession of
commission legs, rewards, user interface decisions or human enjoyment.
