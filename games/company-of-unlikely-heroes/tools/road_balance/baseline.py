#!/usr/bin/env python3
"""Run or normalize a road rules baseline into bounded, readable artifacts."""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from cases_html import write_html


PROJECT = Path(__file__).resolve().parents[2]
ROOT = PROJECT.parents[1]
FIELDS = [
    "mission", "variant", "roster", "policy", "wounded", "setup",
    "damage_dealt", "damage_received", "starting_wounds", "ending_wounds",
    "fallen", "rounds", "result", "opening_hp", "ending_hp", "ending_kind", "tier",
]


def compact(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def rows_for(report):
    rows = []
    identities = set()
    for case in report["cases"]:
        setup = {"opening": case["opening"], "orders": case["orders"]}
        if "settings" in case:
            setup["settings"] = case["settings"]
        identity = (case["mission"], case["variant"], tuple(case["roster"]),
                    case["policy"], case["wounded"], compact(setup))
        if identity in identities:
            raise ValueError(f"duplicate case identity: {identity}")
        identities.add(identity)
        result = case["result"]
        status = result["status"]
        if status not in ("victory", "defeat", "round_limit"):
            raise ValueError(f"unknown result: {status}")
        metrics = result["metrics"]
        for field in ("damage_dealt", "damage_received"):
            value = metrics[field]
            if not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0:
                raise ValueError(f"invalid {field}")
        roster = case["roster"]
        opening = {unit["id"]: unit for unit in case["opening"] if unit["id"] in roster}
        if len(opening) != len(roster) or len(set(roster)) != len(roster):
            raise ValueError("opening hero IDs do not match roster")
        final = metrics["carryover_hp"] if status == "victory" else metrics["ending_hp"]
        if set(final) != set(roster):
            raise ValueError("ending hero IDs do not match roster")
        for hero, unit in opening.items():
            if not all(isinstance(x, (int, float)) and not isinstance(x, bool)
                       for x in (unit["hp"], unit["max_hp"], final[hero])):
                raise ValueError("non-numeric hero HP")
            if not 0 < unit["hp"] <= unit["max_hp"] or not 0 <= final[hero] <= unit["max_hp"]:
                raise ValueError("invalid hero HP")
            if status == "victory" and final[hero] == 0:
                raise ValueError("victory carryover must be positive")
        rows.append({
            "mission": case["mission"], "variant": case["variant"],
            "roster": compact(roster), "policy": case["policy"],
            "wounded": str(case["wounded"]).lower(), "setup": compact(setup),
            "damage_dealt": metrics["damage_dealt"],
            "damage_received": metrics["damage_received"],
            "starting_wounds": sum(unit["max_hp"] - unit["hp"] for unit in opening.values()),
            "ending_wounds": sum(opening[hero]["max_hp"] - final[hero] for hero in roster),
            "fallen": compact(metrics["fallen_heroes"]), "rounds": len(result["rounds"]),
            "result": status,
            "opening_hp": compact({hero: [opening[hero]["hp"], opening[hero]["max_hp"]]
                                   for hero in roster}),
            "ending_hp": compact(final),
            "ending_kind": "projected_carryover" if status == "victory" else "terminal_hp",
            "tier": case.get("tier") if case.get("tier") is not None else "",
        })
    if not rows:
        raise ValueError("report has no cases")
    return rows


def source_digest():
    # A conservative snapshot of the runner, rules, and stock content, not Git history.
    paths = [PROJECT / "project.godot"]
    for directory in ("content", "rules", "tools/road_balance"):
        paths.extend(path for path in (PROJECT / directory).rglob("*")
                     if path.is_file() and path.suffix in (".gd", ".json", ".godot", ".py"))
    digest = hashlib.sha256()
    for path in sorted(paths):
        name = path.relative_to(PROJECT).as_posix().encode()
        data = path.read_bytes()
        digest.update(len(name).to_bytes(8, "big"))
        digest.update(name)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def provenance(mode, source):
    def git(*args):
        return subprocess.run(["git", "-C", str(ROOT), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    try:
        head = git("rev-parse", "HEAD")
        dirty = bool(git("status", "--porcelain", "--untracked-files=normal"))
    except (OSError, subprocess.CalledProcessError):
        head, dirty = "unavailable", "unknown"
    return {
        "mode": mode, "input": source, "checkout_head": head, "checkout_dirty": dirty,
        "snapshot_sha256": source_digest(),
        "snapshot_scope": "project.godot and .gd/.json/.godot/.py files under content, rules, tools/road_balance",
        "note": "Snapshot is the adapter checkout, not proof of the input's origin." if mode == "input"
                else "Dirty checkout is not reproducible from HEAD alone.",
    }


def run_godot(suite, output):
    godot = shutil.which("godot")
    if not godot:
        raise ValueError("godot executable not found on PATH")
    command = [godot, "--headless", "--path", str(PROJECT), "--script",
               "res://tools/road_balance/road_balance_cli.gd", "--",
               f"--suite={suite}", f"--report={output / 'raw.json'}"]
    with tempfile.TemporaryDirectory(prefix="olr-road-xdg-") as temporary:
        env = os.environ.copy()
        for name, subdir in (("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                             ("XDG_CACHE_HOME", "cache")):
            env[name] = str(Path(temporary) / subdir)
        with (output / "run.log").open("x", encoding="utf-8") as log:
            log.write("Command: " + compact(command) + "\n")
            log.flush()
            completed = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        if completed.returncode:
            raise ValueError(f"Godot exited {completed.returncode}; see {output / 'run.log'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--suite", choices=("catalog", "pilot"))
    source.add_argument("--input", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        output = args.out.parent.resolve(strict=True) / args.out.name
        output.mkdir()
        if args.input:
            input_path = args.input.resolve(strict=True)
            shutil.copyfile(input_path, output / "raw.json")
            (output / "run.log").write_text("Offline normalization; Godot was not run.\n",
                                            encoding="utf-8")
        else:
            run_godot(args.suite, output)
        with (output / "raw.json").open(encoding="utf-8") as stream:
            report = json.load(stream)
        if args.suite and report["suite"] != args.suite:
            raise ValueError("Godot produced a different suite")
        rows = rows_for(report)
        metadata = provenance("suite" if args.suite else "input",
                              args.suite if args.suite else str(input_path))
        metadata["raw_sha256"] = hashlib.sha256((output / "raw.json").read_bytes()).hexdigest()
        with (output / "cases.tsv").open("x", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=FIELDS, delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        write_html(output / "cases.tsv", output / "cases.html")
        (output / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n",
                                                encoding="utf-8")
        print(f"Wrote {len(rows)} cases to {output}")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"baseline: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
