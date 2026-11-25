"""Run from the repository root: python3 games/company-of-unlikely-heroes/tests/guild/guild_fixture_cleanup_test.py

Linux only: each Godot process receives a disposable HOME and XDG data directory.
Set GODOT to the Godot executable if it is not named "godot".
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]
CASES = (
    ("guild/guild_profile_test.gd", "guild_profile_", "PASS: guild profile"),
    ("journeys/guild_petitions_walkthrough_test.gd", "petition_walkthrough_", "PASS: guild first paths test completed"),
)


@unittest.skipUnless(sys.platform.startswith("linux"), "requires Linux XDG data paths")
class FixtureCleanupTest(unittest.TestCase):
    def setUp(self):
        self.godot = os.environ.get("GODOT", "godot")
        executable = shutil.which(self.godot)
        if executable:
            executable_dir = Path(executable).resolve().parent
            if any((executable_dir / marker).exists() for marker in ("_sc_", "._sc_")):
                self.skipTest("Portable Godot can bypass XDG isolation")

    def environment(self, root):
        env = {"PATH": os.environ.get("PATH", os.defpath)}
        for key, directory in {
            "HOME": root / "home",
            "XDG_DATA_HOME": root / "data",
            "XDG_CONFIG_HOME": root / "config",
            "XDG_CACHE_HOME": root / "cache",
        }.items():
            directory.mkdir()
            env[key] = str(directory)
        return env

    def run_fixture(self, env, script):
        return subprocess.run(
            [self.godot, "--headless", "--path", str(PROJECT),
             "--script", "res://tests/" + script],
            env=env, capture_output=True, text=True, timeout=180, check=False,
        )

    def test_disposable_profiles_and_backups_are_removed(self):
        for script, prefix, marker in CASES:
            with self.subTest(script=script), tempfile.TemporaryDirectory(
                prefix="guild-fixture-cleanup-"
            ) as temporary:
                root = Path(temporary)
                env = self.environment(root)
                data = root / "data"
                user_dir = data / "godot" / "app_userdata" / "Barnaby's Order of Last Resort"
                user_dir.mkdir(parents=True)
                env["TEST_EXPECTED_USER_DIR"] = str(user_dir)
                sentinel = user_dir / "unrelated.json.backup"
                sentinel_bytes = b"unrelated backup must survive\n"
                sentinel.write_bytes(sentinel_bytes)
                result = self.run_fixture(env, script)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertIn(marker, output)
                self.assertNotIn("SCRIPT ERROR", output)
                self.assertTrue(sentinel.is_file(), "Unrelated backup was removed")
                self.assertEqual(sentinel.read_bytes(), sentinel_bytes)
                leftovers = sorted(path.name for path in user_dir.glob(prefix + "*"))
                self.assertEqual(leftovers, [], "Fixture-owned files remain: " + str(leftovers))

    def test_refuses_unexpected_user_directory_before_fixture_writes(self):
        for script, prefix, _ in CASES:
            with self.subTest(script=script), tempfile.TemporaryDirectory(
                prefix="guild-fixture-guard-"
            ) as temporary:
                root = Path(temporary)
                env = self.environment(root)
                env["TEST_EXPECTED_USER_DIR"] = str(root / "intentionally-wrong")
                result = self.run_fixture(env, script)
                output = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0, output)
                self.assertIn("Refusing fixture with unexpected user data directory:", output)
                self.assertNotIn("SCRIPT ERROR", output)
                self.assertEqual(list((root / "data").rglob(prefix + "*")), [])


if __name__ == "__main__":
    unittest.main()
