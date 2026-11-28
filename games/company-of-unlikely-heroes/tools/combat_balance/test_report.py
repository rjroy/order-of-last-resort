"""Black-box contract for the offline combat balance report.

The fixture owns its tuning.  `profiles` is what Catalog.profile returns after
merging each character over its class, not another set of raw characters.
"""

import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPORT = Path(__file__).with_name("report.py")
OUTPUTS = (
    "heroes_hp.tsv",
    "hero_abilities.tsv",
    "enemies_hp.tsv",
    "enemy_abilities.tsv",
    "index.html",
)


def fixture():
    hero = {
        "class": "medic",
        "label": "Twin",
        "team": "heroes",
        "max_hp": 17,
        "abilities": ["test_heal"],
    }
    enemy = {
        "class": "foe",
        "label": "Twin",
        "team": "enemies",
        "max_hp": 13,
        "abilities": ["test_strike"],
        "traits": [{"kind": "big_windup", "damage": 6}],
    }
    other = {
        "class": "foe",
        "label": "Twin",
        "team": "enemies",
        "max_hp": 13,
        "abilities": ["test_strike"],
    }
    return {
        "definitions": {
            "classes": {
                "medic": {"team": "heroes", "max_hp": 17, "abilities": ["test_heal"]},
                "foe": {"team": "enemies", "max_hp": 13, "abilities": ["test_strike"]},
            },
            "characters": {
                "test_medic": {"class": "medic", "label": "Twin"},
                "test_bruiser": {
                    "class": "foe",
                    "label": "Twin",
                    "traits": [{"kind": "big_windup", "damage": 6}],
                },
                "test_guard": {"class": "foe", "label": "Twin"},
            },
            "abilities": {
                "test_heal": {
                    "label": "Treatment",
                    "help": "Restore 99 HP.",
                    "handler": "heal",
                    "params": {"amount": 3, "allow_self": True},
                    "targeting": {"kind": "automatic", "range": 2, "teams": ["heroes"]},
                },
                "test_strike": {
                    "label": "Strike",
                    "help": "A strike.",
                    "handler": "attack",
                    "params": {"damage": 4},
                    "targeting": {"kind": "entity", "range": 1},
                },
            },
            "missions": {
                "test_mission": {
                    "title": "Test mission",
                    "encounter": "test_encounter",
                    "enemy_max_hp": {"test_placement": 21},
                }
            },
            "encounters": {
                "test_encounter": {
                    "board": "test_board",
                    "placements": [
                        {"id": "test_placement", "character": "test_bruiser", "at": [1, 1], "hp": 8}
                    ],
                }
            },
        },
        "profiles": {"test_medic": hero, "test_bruiser": enemy, "test_guard": other},
    }


def cells(row):
    return " | ".join(str(value) for value in row.values()).lower()


def rows_with(rows, *terms):
    return [row for row in rows if all(str(term).lower() in cells(row) for term in terms)]


class ReportContractTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_report(self, data, name):
        source = self.root / f"{name}.json"
        source.write_text(json.dumps(data), encoding="utf-8")
        output = self.root / name
        if not REPORT.is_file():
            self.fail(f"Behavioral report unavailable: {REPORT} does not exist")
        result = subprocess.run(
            [sys.executable, str(REPORT), "--input", str(source), "--out", str(output)],
            capture_output=True,
            text=True,
            check=False,
        )
        return result, output

    def read_table(self, directory, filename):
        path = directory / filename
        self.assertTrue(path.is_file(), f"Missing report output: {filename}")
        with path.open(encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream, delimiter="\t")
            self.assertTrue(reader.fieldnames, f"{filename} needs column headers")
            return list(reader)

    def test_factual_tables_and_deterministic_artifacts(self):
        first, out = self.run_report(fixture(), "first")
        self.assertEqual(first.returncode, 0, first.stderr)
        second, other = self.run_report(fixture(), "second")
        self.assertEqual(second.returncode, 0, second.stderr)
        for filename in OUTPUTS:
            self.assertTrue((out / filename).is_file(), f"Missing report output: {filename}")
            self.assertEqual((out / filename).read_bytes(), (other / filename).read_bytes(), filename)

        heroes = self.read_table(out, "heroes_hp.tsv")
        enemies = self.read_table(out, "enemies_hp.tsv")
        hero_abilities = self.read_table(out, "hero_abilities.tsv")
        enemy_abilities = self.read_table(out, "enemy_abilities.tsv")

        self.assertTrue(rows_with(heroes, "test_medic", "17"), "Inherited hero max HP missing")
        self.assertTrue(rows_with(enemies, "test_bruiser", "13"), "Default enemy max HP missing")
        self.assertTrue(rows_with(enemies, "test_guard", "13"), "Same-label enemy ID missing")
        self.assertTrue(
            rows_with(enemies, "test_bruiser", "test_mission", "test_placement", "21", "8"),
            "Mission max HP and placement starting HP must be attributed separately from defaults",
        )
        heal = rows_with(hero_abilities, "test_medic", "test_heal")
        self.assertTrue(heal, "Hero ability must identify both owner and source")
        self.assertTrue(rows_with(heal, "3"), "Heal amount must come from handler parameters")
        self.assertFalse(rows_with(heal, "99"), "Conflicting help text must not become a factual effect")
        self.assertTrue(
            rows_with(enemy_abilities, "test_bruiser", "test_strike", "4"),
            "Ordinary strike must remain visible for a Windup enemy",
        )
        self.assertTrue(
            rows_with(enemy_abilities, "test_bruiser", "windup", "6"),
            "Trait-derived Windup damage must be visible",
        )
        self.assertTrue(rows_with(enemy_abilities, "test_guard", "test_strike", "4"))

    def test_unknown_effect_is_explicit_or_fails_loudly(self):
        data = fixture()
        data["definitions"]["abilities"]["test_heal"]["handler"] = "unknown_test_handler"
        result, out = self.run_report(data, "unknown")
        if result.returncode:
            self.assertIn("unknown", (result.stdout + result.stderr).lower())
        else:
            abilities = self.read_table(out, "hero_abilities.tsv")
            self.assertTrue(
                rows_with(abilities, "test_medic", "test_heal", "unknown"),
                "An unsupported handler must not silently appear as a known effect",
            )

    def test_explicit_equal_hp_overrides_are_attributed(self):
        data = fixture()
        mission = data["definitions"]["missions"]["test_mission"]
        mission["enemy_max_hp"]["equal_max"] = 13
        placements = data["definitions"]["encounters"]["test_encounter"]["placements"]
        placements.extend([
            {"id": "equal_max", "character": "test_guard", "at": [2, 1]},
            {"id": "equal_start", "character": "test_guard", "at": [3, 1], "hp": 13},
            {"id": "implicit", "character": "test_guard", "at": [4, 1]},
        ])
        result, out = self.run_report(data, "equal_hp")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.read_table(out, "enemies_hp.tsv")
        for placement, note in [("equal_max", "maximum"), ("equal_start", "starting")]:
            row = next(row for row in rows if row["placement"] == placement)
            self.assertEqual((row["maximum_hp"], row["starting_hp"]), ("13", "13"))
            self.assertIn(note, row["notes"].lower())
            self.assertIn("explicit", row["notes"].lower())
        self.assertFalse(any(row["placement"] == "implicit" for row in rows))

    def test_conditional_follow_up_and_recoil_effects(self):
        data = fixture()
        abilities = {
            "wizard_through_shot": {"handler": "blast", "params": {"damage": 8}},
            "blacksmith_sweep": {"handler": "attack", "params": {"damage": 7}},
            "test_spear": {"handler": "attack", "params": {"damage": 6, "spear_followthrough": True}},
            "test_pull": {"handler": "pull", "params": {"recoil_damage": 3, "status": "knockdown"}},
        }
        data["definitions"]["abilities"].update(abilities)
        data["profiles"]["test_medic"]["abilities"].extend(abilities)
        result, out = self.run_report(data, "followups")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = {row["effect_id"]: row["base_effect"].lower()
                for row in self.read_table(out, "hero_abilities.tsv")}
        self.assertIn("8", rows["wizard_through_shot"])
        self.assertRegex(rows["wizard_through_shot"], r"1 damage")
        self.assertRegex(rows["wizard_through_shot"], r"behind")
        self.assertRegex(rows["wizard_through_shot"], r"row or column")
        self.assertRegex(rows["blacksmith_sweep"], r"(one other|second)")
        self.assertIn("eligible", rows["blacksmith_sweep"])
        self.assertIn("6", rows["test_spear"])
        self.assertRegex(rows["test_spear"], r"(behind|rear)")
        self.assertIn("object", rows["test_spear"])
        self.assertIn("3", rows["test_pull"])
        self.assertIn("knockdown", rows["test_pull"])
        self.assertRegex(rows["test_pull"], r"block|resist")

    def test_structured_effects_are_explained_not_just_dumped(self):
        data = fixture()
        abilities = {
            "blacksmith_sweep": {
                "label": "Sweep", "handler": "attack", "params": {"damage": 7},
                "targeting": {"kind": "none", "range": 1},
            },
            "test_potion": {
                "label": "Potion", "handler": "healing_potion", "params": {"amount": 11},
                "targeting": {"kind": "entity", "range": 1},
            },
            "test_padding": {
                "label": "Padding", "handler": "padding", "params": {"amount": 5},
                "targeting": {"kind": "automatic", "range": 3},
            },
            "test_aura": {
                "label": "Aura", "handler": "apply_status", "params": {"status": "test_reflect"},
                "targeting": {"kind": "none"},
            },
        }
        data["definitions"]["abilities"].update(abilities)
        data["definitions"]["classes"]["medic"]["abilities"].extend(abilities)
        data["profiles"]["test_medic"]["abilities"].extend(abilities)
        data["definitions"]["statuses"] = {
            "test_reflect": {
                "label": "Aura", "handler": "reflect", "expiry": "actor_turn_start",
                "params": {"range": 1, "max_reflect_damage_per_round": 9},
            }
        }
        result, out = self.run_report(data, "structured")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.read_table(out, "hero_abilities.tsv")
        # Inspect the interpreted effect, not raw JSON parameters or labels.
        for ability_id, number, role, condition in [
            ("blacksmith_sweep", "7", r"damag", r"adjacent|range"),
            ("test_potion", "11", r"heal", r"reaction"),
            ("test_padding", "5", r"protect|buffer|absorb", r"damag"),
            ("test_aura", "9", r"reflect|redirect|absorb", r"round|turn"),
        ]:
            with self.subTest(ability=ability_id):
                matched = rows_with(rows, "test_medic", ability_id)
                self.assertEqual(len(matched), 1, f"Expected one row for {ability_id}")
                effect = matched[0]["base_effect"].lower()
                self.assertIn(number, effect)
                self.assertRegex(effect, role)
                self.assertRegex(effect, condition)
                if ability_id == "test_padding":
                    self.assertNotRegex(effect, r"\bheal(?:ing|s)?\b")


if __name__ == "__main__":
    unittest.main()
