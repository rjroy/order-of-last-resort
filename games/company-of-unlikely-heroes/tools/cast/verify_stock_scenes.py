#!/usr/bin/env python3
"""Run stock opening inventories and actor/variant graphical regressions."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

GAME = Path(__file__).resolve().parents[2]
ROOT = GAME.parents[1]
SCRIPT = "res://tests/journeys/stock_cast_mission_test.gd"
SAFE_ID = re.compile(r"^[a-zA-Z0-9_-]+$")
ERROR_LINE = re.compile(r"(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|.*Parse Error:)")


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _json(path):
    with path.open(encoding="utf-8") as source:
        return json.load(source, object_pairs_hook=_unique_object)


def _id(value, context):
    if not isinstance(value, str) or not SAFE_ID.fullmatch(value):
        raise ValueError(f"invalid {context}: {value!r}")
    return value


def discover(game):
    """Use the same manifest-part merge as the stock catalog, not local history."""
    content = game / "content"
    manifest = _json(content / "catalog.json")
    if set(manifest) != {"parts"} or not isinstance(manifest["parts"], list) or not manifest["parts"]:
        raise ValueError("catalog.json must contain a nonempty parts array")
    tables = {}
    for part in manifest["parts"]:
        if not isinstance(part, str) or not part:
            raise ValueError(f"invalid catalog part: {part!r}")
        path = (content / part).resolve()
        if not path.is_relative_to(content.resolve()) or Path(part).is_absolute():
            raise ValueError(f"catalog part escapes content: {part}")
        for table, records in _json(path).items():
            if not isinstance(records, dict):
                raise ValueError(f"{part}: {table} must be a dictionary")
            previous = tables.setdefault(table, {})
            if overlap := previous.keys() & records.keys():
                raise ValueError(f"{part}: duplicate {table} IDs: {sorted(overlap)}")
            previous.update(records)
    missions = sorted(_id(name, "mission") for name in tables.get("missions", {}))
    if not missions:
        raise ValueError("stock catalog has no missions")
    cases = []
    seen = set()
    for path in sorted((game / "tests/fixtures").glob("stock_cast_case_*.json")):
        data = _json(path)
        mission, actor = _id(data.get("mission"), "case mission"), _id(data.get("actor"), "case actor")
        config = data.get("case")
        if mission not in missions or actor not in tables.get("characters", {}) or not isinstance(config, dict):
            raise ValueError(f"invalid stock case: {path}")
        if (mission, actor) in seen:
            raise ValueError(f"duplicate stock case: {mission}/{actor}")
        seen.add((mission, actor))
        variants = config.get("variants", {})
        if not isinstance(variants, dict) or any(not isinstance(v, dict) for v in variants.values()):
            raise ValueError(f"invalid variants in {path}")
        cases.append((mission, actor, sorted(_id(name, "variant") for name in variants)))
    if not cases:
        raise ValueError("no checked-in stock actor cases found")
    return missions, cases


def safe_output(root, requested):
    """Accept only a new path below .lore/local, rejecting every symlink component."""
    local = root / ".lore/local"
    output = Path(os.path.abspath(requested))
    if not output.is_relative_to(local) or output == local:
        raise ValueError(f"output must be a new directory under {local}")
    path = root
    for component in output.relative_to(root).parts:
        path = path / component
        if path.is_symlink():
            raise ValueError(f"output path contains a symlink: {path}")
    if output.exists():
        raise ValueError(f"output already exists: {output}")
    return output


def plan(game, output, missions, cases, selected_missions=(), selected_actors=()):
    chosen_missions = set(selected_missions) if selected_missions else set(missions)
    unknown = chosen_missions - set(missions)
    if unknown:
        raise ValueError(f"unknown missions: {sorted(unknown)}")
    known_actors = {actor for _, actor, _ in cases}
    unknown = set(selected_actors) - known_actors
    if unknown:
        raise ValueError(f"unknown actors: {sorted(unknown)}")
    actor_set = set(selected_actors)
    selected = [(m, a, variants) for m, a, variants in cases
                if m in chosen_missions and (not actor_set or a in actor_set)]
    if actor_set and not selected:
        raise ValueError("actor/mission selection contains no cases")
    jobs = []
    for mission in sorted(chosen_missions):
        dest = output / "inventory" / mission
        jobs.append({"mission": mission, "actor": "", "variant": "", "output": str(dest),
                     "args": [f"--mission={mission}", "--inventory", "--all-integrated"]})
    for mission, actor, variants in selected:
        for variant in ["", *variants]:
            dest = output / "cases" / mission / (actor + ("--" + variant if variant else ""))
            args = [f"--mission={mission}", f"--actor={actor}"]
            if variant:
                args.append(f"--variant={variant}")
            jobs.append({"mission": mission, "actor": actor, "variant": variant,
                         "output": str(dest), "args": args})
    return jobs


def command(game, godot, job):
    return [godot, "--audio-driver", "Dummy", "--path", str(game), "--script", SCRIPT, "--",
            *job["args"], f"--output={job['output']}"]


def execute(game, output, jobs, godot, timeout, min_free):
    output.mkdir(parents=True, exist_ok=False)
    for name in ("data", "cache", "config", "tmp", "logs"):
        (output / name).mkdir()
    env = dict(os.environ, XDG_DATA_HOME=str(output / "data"),
               XDG_CACHE_HOME=str(output / "cache"), XDG_CONFIG_HOME=str(output / "config"),
               TMPDIR=str(output / "tmp"))
    records = []
    stopped = ""
    for index, job in enumerate(jobs):
        if shutil.disk_usage(output).free < min_free:
            stopped = f"less than {min_free} bytes remain on the evidence filesystem"
            break
        dest = Path(job["output"])
        dest.parent.mkdir(parents=True, exist_ok=True)
        log = output / "logs" / f"{index:03}.log"
        cmd = command(game, godot, job)
        record = {**job, "command": cmd, "log": str(log.relative_to(output))}
        print(f"[{index + 1}/{len(jobs)}] {job['mission']} {job['actor']} {job['variant']}", flush=True)
        with log.open("w", encoding="utf-8") as stream:
            try:
                process = subprocess.run(cmd, stdout=stream, stderr=subprocess.STDOUT,
                                         env=env, timeout=timeout, check=False)
                record["exit"] = process.returncode
            except (OSError, subprocess.TimeoutExpired) as exc:
                stream.write(f"\nFAIL: {exc}\n")
                record["exit"] = None
        text = log.read_text(encoding="utf-8", errors="replace")
        record["error_lines"] = [line for line in text.splitlines() if ERROR_LINE.match(line)]
        images = list(dest.glob("*.png")) if dest.is_dir() else []
        record["captures"] = len(images)
        record["passed"] = record["exit"] == 0 and not record["error_lines"] \
            and bool(images) and all(image.stat().st_size > 0 for image in images)
        if not job["actor"]:
            record["passed"] = record["passed"] and (dest / "inventory-opening.png").is_file()
        else:
            record["passed"] = record["passed"] and bool(list(dest.glob("*ready.png"))) \
                and bool(list(dest.glob("*committed-event.png")))
        records.append(record)
    # Godot also writes process logs under its isolated user data directory.
    user_errors = []
    for log in (output / "data").rglob("*.log"):
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            if ERROR_LINE.match(line):
                user_errors.append({"log": str(log.relative_to(output)), "line": line})
    passed = len(records) == len(jobs) and all(record["passed"] for record in records) \
        and not user_errors and not stopped
    summary = {"passed": passed, "planned": len(jobs), "completed": len(records),
               "stopped": stopped, "user_data_errors": user_errors, "runs": records}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'}: {output / 'summary.json'}")
    return 0 if passed else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new directory under .lore/local")
    parser.add_argument("--dry-run", action="store_true", help="print plan without creating files or launching Godot")
    parser.add_argument("--mission", action="append", default=[], help="limit to a stock mission; repeatable")
    parser.add_argument("--actor", action="append", default=[], help="limit actor cases; inventories remain enabled")
    parser.add_argument("--godot", default="godot", help="Godot executable")
    parser.add_argument("--timeout", type=int, default=120, help="per-run seconds")
    parser.add_argument("--min-free-gib", type=float, default=2.0, help="disk-space floor")
    args = parser.parse_args(argv)
    if args.timeout < 1 or args.min_free_gib < 0:
        parser.error("timeout must be positive and disk-space floor nonnegative")
    try:
        output = safe_output(ROOT, args.output)
        missions, cases = discover(GAME)
        jobs = plan(GAME, output, missions, cases, args.mission, args.actor)
        if args.dry_run:
            print(json.dumps({"stock_missions": len(missions), "stock_actor_cases": len(cases),
                              "selected_runs": len(jobs),
                              "jobs": [{**job, "command": command(GAME, args.godot, job)} for job in jobs]}, indent=2))
            return 0
        if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
            raise ValueError("a graphical DISPLAY or WAYLAND_DISPLAY is required")
        if shutil.which(args.godot) is None:
            raise ValueError(f"Godot executable not found: {args.godot}")
        return execute(GAME, output, jobs, args.godot, args.timeout, int(args.min_free_gib * 1024 ** 3))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
