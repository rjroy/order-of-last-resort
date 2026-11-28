---
name: road-playtest
description: Run or reuse a scripted road playtest, deterministic baseline, or carryover scorecard. Use for factual results of the road rules probe, not static ability inventory or human balance analysis.
---

# Road Playtest

Use this for a factual scripted scorecard, not a judgment about why results
occurred, tuning, balance, or fun. For a static stock ability inventory, use
[combat-balance-report](../combat-balance-report/SKILL.md). Human play and
balance analysis are separate work.

## Run or reuse

Read the [tool guide](../../../games/company-of-unlikely-heroes/tools/road_balance/README.md)
for the suite, policies, inputs, and limits. Reuse an applicable retained
baseline rather than rerunning it; inspect its provenance and setup first.
Do not edit source or saves, or rerun a baseline, unless requested. When a new
run is requested, use one run per actual distinct setup: opening positions and
HP, party, orders, settings, mission, variant, policy and wounded state.
There is no need to repeat an identical deterministic case.

From the repository root, after the Godot 4.7.2 project import, replace the
placeholder with a new ignored directory whose parent exists:

```sh
python3 games/company-of-unlikely-heroes/tools/road_balance/baseline.py --suite catalog --out <new ignored directory>
```

Use `--suite pilot` for the smaller pilot. To normalize an existing report
with actual damage telemetry instead, replace `--suite catalog` with
`--input path/to/raw.json`. Legacy reports without `damage_dealt` and
`damage_received` cannot provide those figures: do not approximate them.
The output path must not already exist; preserve prior reports.

## Read and report

For humans, open `cases.html` to filter and sort the scorecard. For agents,
select only matching rows from `cases.tsv`; for example, with `report_dir` set
to the report path:

```sh
awk -F '\t' 'NR == 1 { print; next } $1 == "bridge_patrol" && $4 == "forecast_first" { print; exit }' "$report_dir/cases.tsv"
```

Adjust the case filter as needed. Do not dump `raw.json` or per-round summaries
into model context for routine scoring; those are retained machine evidence.
For an existing TSV without an HTML view, use the renderer command in the tool
guide; it does not run Godot or read the raw report.

State the tested setup and policy, outcomes, rounds, falls, and HP lost by
enemies and heroes. Damage is classified by recipient side, includes friendly
fire, and excludes objects and civilians. For per-hero starting and ending
wounds, subtract `opening_hp` and `ending_hp` from each hero's opening maximum
HP. On victory, ending HP is **projected next-road carryover before rewards**;
on other outcomes it is terminal HP, not carryover. A round limit is
inconclusive, not a defeat or proof of impossibility. These isolated scripted
runs are not evidence of human enjoyment.
