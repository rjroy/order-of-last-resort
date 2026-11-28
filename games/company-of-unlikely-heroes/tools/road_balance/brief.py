#!/usr/bin/env python3
"""Summarize road probe results without exposing their per-round records."""

import argparse
from collections import Counter
import json
from pathlib import Path
import sys


def identity(case):
    return (case["mission"], case["variant"], tuple(case["roster"]),
            case["policy"], case["wounded"])


def index_report(report):
    cases = {}
    for case in report["cases"]:
        key = identity(case)
        if key in cases:
            raise ValueError(f"duplicate case identity: {key}")
        if case["result"]["status"] not in ("victory", "defeat", "round_limit"):
            raise ValueError(f"unknown outcome for {key}")
        if case["result"]["status"] == "victory":
            carry_and_opening(case)
        cases[key] = case
    return cases


def carry_and_opening(case):
    carry = case["result"]["metrics"]["carryover_hp"]
    opening = {unit["id"]: unit for unit in case["opening"] if unit["id"] in carry}
    if not carry or set(opening) != set(carry) or len(carry) != len(case["roster"]):
        raise ValueError(f"carryover/opening hero mismatch: {identity(case)}")
    for hero, hp in carry.items():
        unit = opening[hero]
        if not all(isinstance(x, (int, float)) and not isinstance(x, bool)
                   for x in (hp, unit["hp"], unit["max_hp"])):
            raise ValueError(f"non-numeric HP: {identity(case)}")
        if not 0 < hp <= unit["max_hp"] or not 0 < unit["hp"] <= unit["max_hp"]:
            raise ValueError(f"invalid HP: {identity(case)}")
    return carry, opening


def summarize(report, baseline=None):
    cases = index_report(report)
    old = index_report(baseline) if baseline is not None else None
    if old is not None and set(cases) != set(old):
        raise ValueError(f"case identities differ: {len(set(cases) - set(old))} result-only, "
                         f"{len(set(old) - set(cases))} baseline-only")

    fresh = Counter()
    wounded = Counter()
    outcomes = Counter()
    for case in cases.values():
        status = case["result"]["status"]
        outcomes[status] += 1
        if status != "victory":
            continue
        carry, opening = carry_and_opening(case)
        if not case["wounded"]:
            fresh["wounded" if any(hp < opening[h]["max_hp"]
                                   for h, hp in carry.items()) else "full"] += 1
        else:
            changes = [hp - opening[h]["hp"] for h, hp in carry.items()]
            up, down = any(x > 0 for x in changes), any(x < 0 for x in changes)
            wounded["mixed" if up and down else "improved" if up else
                    "worse" if down else "same"] += 1

    lines = [
        "# Road balance brief",
        f"- Carryover on wins: fresh {fresh['wounded']} wounded / {fresh['full']} full; "
        f"already-wounded {wounded['improved']} improved / {wounded['same']} same / "
        f"{wounded['worse']} worse / {wounded['mixed']} mixed.",
        f"- Outcomes ({len(cases)} cases): {outcomes['victory']} wins, "
        f"{outcomes['defeat']} defeats, {outcomes['round_limit']} round-limit (indeterminate).",
    ]
    if old is not None:
        changed_outcome = sum(cases[k]["result"]["status"] != old[k]["result"]["status"]
                              for k in cases)
        both_wins = [k for k in cases if cases[k]["result"]["status"] == "victory"
                     and old[k]["result"]["status"] == "victory"]
        changed_carry = sum(carry_and_opening(cases[k])[0] != carry_and_opening(old[k])[0]
                            for k in both_wins)
        lines.append(f"- Comparison: {len(cases)} matched; {changed_outcome} outcome changes; "
                     f"{changed_carry} carryover changes among {len(both_wins)} wins in both.")
    lines.append("- Carryover is projected, victory-only; mixed means some heroes improved "
                 "and others worsened. Rules probes are not human play.")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()
    try:
        with args.result.open(encoding="utf-8") as source:
            result = json.load(source)
        baseline = None
        if args.baseline:
            with args.baseline.open(encoding="utf-8") as source:
                baseline = json.load(source)
        print(summarize(result, baseline), end="")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"brief: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
