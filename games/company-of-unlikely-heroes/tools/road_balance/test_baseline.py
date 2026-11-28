"""Offline contract checks for the scripted baseline report."""

import copy
import csv
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("baseline.py")
FIELDS = [
    "mission", "variant", "roster", "policy", "wounded", "setup",
    "damage_dealt", "damage_received", "starting_wounds", "ending_wounds",
    "fallen", "rounds", "result",
]


def case(status, position="[1, 1]"):
    metrics = {
        "damage_dealt": 3, "damage_received": 5,
        "ending_hp": {"a": 0, "b": 4}, "fallen_heroes": ["a"],
        "enemy_actions_by_round": [1],
    }
    if status == "victory":
        metrics["carryover_hp"] = {"a": 1, "b": 4}
    return {
        "mission": "fixture", "variant": "stock", "roster": ["a", "b"],
        "policy": "forecast_first", "wounded": True,
        "opening": [
            {"id": "a", "character_id": "a", "position": position, "hp": 3, "max_hp": 5},
            {"id": "b", "character_id": "b", "position": "[0, 1]", "hp": 5, "max_hp": 5},
            {"id": "enemy", "character_id": "enemy", "position": "[2, 1]", "hp": 3, "max_hp": 3},
        ],
        "orders": {"a": "guard"},
        "result": {"status": status, "metrics": metrics, "rounds": [
            {"draft": {}, "events": [], "standing_events": []}
        ]},
    }


class BaselineTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), f"missing report script: {SCRIPT}")

    def run_report(self, report):
        temp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        source, output = root / "raw.json", root / "report"
        source.write_text(json.dumps(report), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--input", str(source), "--out", str(output)],
            text=True, capture_output=True, timeout=30,
        )
        return result, output

    def test_scripted_scorecard(self):
        cases = [case("victory"), case("defeat", "[3, 1]"), case("round_limit", "[4, 1]")]
        result, output = self.run_report({"suite": "fixture", "round_limit": 1, "cases": cases})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        page = (output / "cases.html").read_text(encoding="utf-8")
        self.assertIn("<table>", page)
        self.assertEqual(page.count("<tr><td>"), 3)
        self.assertFalse((output / "brief.md").exists())
        with (output / "cases.tsv").open(encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, delimiter="\t")
            self.assertEqual(reader.fieldnames[:len(FIELDS)], FIELDS)
            rows = list(reader)
        self.assertEqual(len(rows), 3)
        rows = {row["result"]: row for row in rows}
        self.assertEqual(set(rows), {"victory", "defeat", "round_limit"})
        for row in rows.values():
            self.assertEqual((row["damage_dealt"], row["damage_received"]), ("3", "5"))
            self.assertEqual(row["rounds"], "1")
            self.assertTrue(row["setup"])
        self.assertEqual(len({row["setup"] for row in rows.values()}), 3)
        self.assertEqual(rows["victory"]["starting_wounds"], "2")
        self.assertEqual(rows["victory"]["ending_wounds"], "5")
        # Non-wins may report raw terminal wounds (6), or leave them blank;
        # neither may present the post-victory projection (5).
        for status in ("defeat", "round_limit"):
            self.assertIn(rows[status]["ending_wounds"], ("", "6"))

    def test_missing_telemetry_fails_loudly(self):
        legacy = case("victory")
        del legacy["result"]["metrics"]["damage_dealt"]
        result, output = self.run_report({"suite": "fixture", "round_limit": 1, "cases": [legacy]})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("damage", (result.stderr + result.stdout).lower())
        self.assertFalse((output / "cases.tsv").exists())

    def test_configured_tiers_are_appended_and_visible(self):
        first = case("victory")
        first["mission"] = "fixture_t5"
        first["tier"] = 2
        second = case("defeat", "[3, 1]")
        second["tier"] = 5
        unassigned = case("round_limit", "[4, 1]")
        unassigned["mission"] = "fixture_t3"
        result, output = self.run_report({
            "suite": "fixture", "round_limit": 1, "cases": [first, second, unassigned],
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with (output / "cases.tsv").open(encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, delimiter="\t")
            self.assertEqual(reader.fieldnames[:len(FIELDS)], FIELDS)
            self.assertEqual(reader.fieldnames[-1], "tier")
            rows = list(reader)
        self.assertEqual([row["tier"] for row in rows], ["2", "5", ""])
        page = (output / "cases.html").read_text(encoding="utf-8")
        heading = re.search(r'data-column="(\d+)" data-numeric="true">Tier</button>', page)
        self.assertIsNotNone(heading, "Tier must be a visible numeric sortable table heading")
        column = int(heading.group(1))
        table_rows = re.findall(r"<tr><td>.*?</tr>", page)
        self.assertEqual(len(table_rows), 3)
        cells = [re.findall(r"<td>(.*?)</td>", row) for row in table_rows]
        self.assertEqual([row[column] for row in cells], ["2", "5", ""])

    def test_existing_output_is_not_overwritten(self):
        # The command contract requires a new output directory.
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as temp:
            root = Path(temp)
            source = root / "raw.json"
            source.write_text(json.dumps({"cases": [copy.deepcopy(case("victory"))]}), encoding="utf-8")
            output = root / "existing"
            output.mkdir()
            sentinel = output / "sentinel"
            sentinel.write_text("keep", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--input", str(source), "--out", str(output)],
                text=True, capture_output=True, timeout=30,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_dangling_output_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as temp:
            root = Path(temp)
            source = root / "raw.json"
            source.write_text(json.dumps({
                "suite": "fixture", "round_limit": 1, "cases": [case("victory")]
            }), encoding="utf-8")
            destination = root / "absent-destination"
            output = root / "report"
            output.symlink_to(destination, target_is_directory=True)
            self.assertTrue(output.parent.is_dir())
            self.assertTrue(output.is_symlink())
            self.assertFalse(destination.exists())
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--input", str(source), "--out", str(output)],
                text=True, capture_output=True, timeout=30,
            )
            self.assertTrue(output.is_symlink(), "output symlink must remain in place")
            self.assertEqual(output.readlink(), destination)
            self.assertFalse(destination.exists(), "must not create the symlink destination")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_duplicate_exact_setup_is_rejected(self):
        original = case("victory")
        result, output = self.run_report({
            "suite": "fixture", "round_limit": 1,
            "cases": [original, copy.deepcopy(original)],
        })
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("duplicate", (result.stderr + result.stdout).lower())
        self.assertFalse((output / "cases.html").exists())
        self.assertFalse((output / "cases.tsv").exists())


if __name__ == "__main__":
    unittest.main()
