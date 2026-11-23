"""Controlled tests for stock-scene orchestration."""

import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import verify_stock_scenes as verify


class StockScenesTest(unittest.TestCase):
    def setUp(self):
        local = verify.ROOT / ".lore/local"
        local.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="stock-scene-test-", dir=local)
        self.root = Path(self.temporary.name)
        self.game = self.root / "game"
        self.write("game/content/catalog.json", {"parts": ["a.json", "b.json"]})
        self.write("game/content/a.json", {"missions": {"first": {}}, "characters": {"one": {}}})
        self.write("game/content/b.json", {"missions": {"second": {}}, "characters": {"two": {}}})
        self.write("game/tests/support/stock_cast_case_one.json",
                   {"mission": "first", "actor": "one", "case": {"variants": {"alternate": {}}}})
        self.write("game/tests/support/stock_cast_case_two.json",
                   {"mission": "second", "actor": "two", "case": {}})

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")

    def test_discovery_and_selection(self):
        missions, cases = verify.discover(self.game)
        self.assertEqual(missions, ["first", "second"])
        self.assertEqual(cases, [("first", "one", ["alternate"]), ("second", "two", [])])
        jobs = verify.plan(self.game, self.root / ".lore/local/run", missions, cases)
        self.assertEqual(len(jobs), 5)
        self.assertEqual(sum(bool(job["variant"]) for job in jobs), 1)
        for job in jobs:
            command = verify.command(self.game, "godot", job)
            self.assertEqual(command[1:3], ["--audio-driver", "Dummy"])
            self.assertNotIn("--headless", command)
        selected = verify.plan(self.game, self.root / ".lore/local/run", missions, cases,
                               selected_missions=["first"], selected_actors=["one"])
        self.assertEqual(len(selected), 3)
        with self.assertRaises(ValueError):
            verify.plan(self.game, self.root, missions, cases, selected_actors=["missing"])

    def test_invalid_duplicate_and_escape(self):
        self.write("game/content/b.json", {"missions": {"first": {}}})
        with self.assertRaisesRegex(ValueError, "duplicate"):
            verify.discover(self.game)
        self.write("game/content/catalog.json", {"parts": ["../escape.json"]})
        with self.assertRaisesRegex(ValueError, "escapes"):
            verify.discover(self.game)

    def test_output_rejects_existing_and_symlink(self):
        local = self.root / ".lore/local"
        local.mkdir(parents=True)
        self.assertEqual(verify.safe_output(self.root, local / "new"), local / "new")
        (local / "existing").mkdir()
        with self.assertRaisesRegex(ValueError, "already exists"):
            verify.safe_output(self.root, local / "existing")
        (local / "link").symlink_to(local / "existing", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            verify.safe_output(self.root, local / "link" / "new")
        with self.assertRaisesRegex(ValueError, "under"):
            verify.safe_output(self.root, self.root / "elsewhere")

    def test_process_logs_and_isolation(self):
        fake = self.root / "godot-fake"
        fake.write_text(
            "#!/usr/bin/env python3\n"
            "import os,pathlib,sys\n"
            "out=pathlib.Path(next(x.split('=',1)[1] for x in sys.argv if x.startswith('--output=')))\n"
            "assert pathlib.Path(os.environ['TMPDIR']).is_dir()\n"
            "assert pathlib.Path(os.environ['XDG_DATA_HOME']).is_dir()\n"
            "out.mkdir()\n"
            "(out/'inventory-opening.png').write_bytes(b'fixture')\n"
            "print('ERROR: deliberate error despite zero exit')\n", encoding="utf-8")
        fake.chmod(0o755)
        output = self.root / ".lore/local/run"
        jobs = verify.plan(self.game, output, ["first"], [])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(verify.execute(self.game, output, jobs, str(fake), 10, 0), 1)
        summary = json.loads((output / "summary.json").read_text())
        self.assertFalse(summary["passed"])
        self.assertIn("ERROR: deliberate", summary["runs"][0]["error_lines"][0])
        fake.write_text(fake.read_text().replace(
            "ERROR: deliberate error despite zero exit", "fixture pass"), encoding="utf-8")
        passing = self.root / ".lore/local/pass"
        good_jobs = verify.plan(self.game, passing, ["first"], [])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(verify.execute(self.game, passing, good_jobs, str(fake), 10, 0), 0)
        self.assertTrue(json.loads((passing / "summary.json").read_text())["passed"])


if __name__ == "__main__":
    unittest.main()
