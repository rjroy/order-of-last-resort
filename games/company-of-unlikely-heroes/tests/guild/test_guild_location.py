"""Run from the repository root: python3 games/company-of-unlikely-heroes/tests/guild/test_guild_location.py

Requires Godot 4 on PATH as `godot` (or set GODOT to its executable).
Every Godot process uses disposable HOME and XDG directories, never player saves.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT", "godot")
OLD = "The Company of Unlikely Heroes"
TITLE = "Barnaby's Order of Last Resort"
NESTED = "company_of_unlikely_heroes"
STANDARD = "guild_profile_v1.json"
CUSTOM = "custom_guild_profile_v1.json"


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux XDG save paths required")
class GuildLocationTest(unittest.TestCase):
    def setUp(self):
        executable = shutil.which(GODOT)
        if executable:
            executable_dir = Path(executable).resolve().parent
            if any((executable_dir / marker).exists() for marker in ("_sc_", "._sc_")):
                self.skipTest("Portable Godot can bypass XDG isolation")
        self.temp = tempfile.TemporaryDirectory(prefix="guild-location-")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        # Do not inherit Godot or XDG overrides that might redirect saves outside
        # the test-owned tree. PATH is needed to find Godot and its helpers.
        self.env = {"PATH": os.environ.get("PATH", os.defpath)}
        for key, directory in {
            "HOME": base / "home",
            "XDG_DATA_HOME": base / "data",
            "XDG_CONFIG_HOME": base / "config",
            "XDG_CACHE_HOME": base / "cache",
        }.items():
            directory.mkdir()
            self.env[key] = str(directory)
        self.old = base / "data" / "godot" / "app_userdata" / OLD / NESTED
        self.new_root = base / "data" / "godot" / "app_userdata" / TITLE
        self.env["TEST_EXPECTED_USER_DIR"] = str(self.new_root)
        self.old.mkdir(parents=True)
        # A fresh checkout has no Godot import cache.
        self.run_godot("--editor", "--quit")

    def run_godot(self, *args):
        try:
            return subprocess.run(
                [GODOT, "--headless", "--path", str(PROJECT), *args],
                env=self.env, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, check=True, timeout=180,
            ).stdout
        except subprocess.CalledProcessError as error:
            self.fail(f"Godot exited with {error.returncode}:\n{error.stdout}")
        except subprocess.TimeoutExpired as error:
            self.fail(f"Godot timed out:\n{error.stdout}")

    def fixture(self, path, name, seed):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"version": 1, "name": name, "board_seed": str(seed)}))

    def launch(self, *args):
        output = self.run_godot(
            "--script", "res://tests/support/guild_location_probe.gd", "--", *args
        )
        for line in output.splitlines():
            if line.startswith("GUILD_LOCATION_PROBE="):
                return json.loads(line.partition("=")[2])
        self.fail("Game probe did not report its result:\n" + output)

    def assert_profile(self, result, name, seed):
        self.assertEqual(Path(result["user_dir"]), self.new_root)
        self.assertEqual(result["screen"], "commissions", result)
        self.assertEqual(result["profile"].get("name"), name, result)
        self.assertEqual(result["profile"].get("board_seed"), seed, result)

    def test_fresh_guilds_use_title_root(self):
        for args, filename, name in [
            ((), STANDARD, "Fresh standard"),
            (("--content=res://content/catalog.json",), CUSTOM, "Fresh custom"),
        ]:
            with self.subTest(filename=filename):
                result = self.launch(*args, "--probe-create=" + name)
                self.assertEqual(result["initial_screen"], "guild_creation", result)
                self.assertEqual(Path(result["user_dir"]), self.new_root)
                self.assertEqual(Path(result["path"]), self.new_root / filename)
                self.assertEqual(result["screen"], "battle" if filename == STANDARD else "commissions", result)
                self.assertEqual(result["profile"].get("name"), name, result)
                self.assertTrue((self.new_root / filename).is_file())
                saved = json.loads((self.new_root / filename).read_text())
                self.assertEqual(saved.get("name"), name)
                reloaded = self.launch(*args)
                self.assertEqual(reloaded["profile"], result["profile"])

    def test_old_profiles_and_explicit_override(self):
        self.fixture(self.old / STANDARD, "Standard legacy", 101)
        self.fixture(self.old / CUSTOM, "Custom legacy", 202)
        custom = "--content=res://content/catalog.json"

        standard = self.launch()
        self.assert_profile(standard, "Standard legacy", 101)
        custom_result = self.launch(custom)
        self.assert_profile(custom_result, "Custom legacy", 202)
        self.assertNotEqual(standard["path"], custom_result["path"])

        # Persist progress in the new location, then restore stale legacy files
        # even if the migration moved them. Neither may replace newer progress.
        self.assert_profile(self.launch("--probe-renew"), "Standard legacy", 987654)
        self.assert_profile(self.launch(custom, "--probe-renew"), "Custom legacy", 987654)
        self.fixture(self.old / STANDARD, "Standard legacy", 101)
        self.fixture(self.old / CUSTOM, "Custom legacy", 202)
        self.assert_profile(self.launch(), "Standard legacy", 987654)
        self.assert_profile(self.launch(custom), "Custom legacy", 987654)

        override = Path(self.temp.name) / "override" / "guild.json"
        self.fixture(override, "Override guild", 303)
        overridden = self.launch("--probe-profile=" + str(override))
        self.assert_profile(overridden, "Override guild", 303)
        self.assertEqual(Path(overridden["path"]), override)
        self.assert_profile(self.launch("--probe-profile=" + str(override), "--probe-renew"),
                            "Override guild", 987654)
        self.assert_profile(self.launch(), "Standard legacy", 987654)
        self.assert_profile(self.launch(custom), "Custom legacy", 987654)
        self.assert_profile(self.launch(custom, "--probe-profile=" + str(override)),
                            "Override guild", 987654)

    def test_configured_profile_does_not_import_legacy(self):
        self.fixture(self.old / STANDARD, "Standard legacy", 101)
        self.fixture(self.old / CUSTOM, "Custom legacy", 202)
        override = Path(self.temp.name) / "override" / "guild.json"
        self.fixture(override, "Override guild", 303)
        before = {p: p.read_bytes() for p in (self.old / STANDARD, self.old / CUSTOM)}
        for args in [(), ("--content=res://content/catalog.json",)]:
            result = self.launch(*args, "--probe-profile=" + str(override))
            self.assert_profile(result, "Override guild", 303)
            self.assertEqual(Path(result["path"]), override)
        for path, contents in before.items():
            self.assertEqual(path.read_bytes(), contents)
        self.assertFalse((self.new_root / STANDARD).exists())
        self.assertFalse((self.new_root / CUSTOM).exists())

    def test_held_migration_lock_and_published_winner(self):
        for args, filename in [
            ((), STANDARD),
            (("--content=res://content/catalog.json",), CUSTOM),
        ]:
            with self.subTest(filename=filename):
                legacy = self.old / filename
                destination = self.new_root / filename
                lock = Path(str(destination) + ".migration-lock")
                self.fixture(legacy, "Legacy guild", 101)
                old_contents = legacy.read_bytes()
                lock.parent.mkdir(parents=True, exist_ok=True)
                lock.mkdir()

                blocked = self.launch(*args)
                self.assertEqual(Path(blocked["user_dir"]), self.new_root)
                self.assertNotIn(blocked["screen"], ("commissions", "guild_creation"), blocked)
                self.assertFalse(destination.exists())
                self.assertTrue(lock.is_dir())
                self.assertEqual(legacy.read_bytes(), old_contents)

                # A concurrent winner may publish while holding the lock.
                self.fixture(destination, "Winning guild", 202)
                winner_bytes = destination.read_bytes()
                winner = self.launch(*args)
                self.assert_profile(winner, "Winning guild", 202)
                self.assertEqual(destination.read_bytes(), winner_bytes)
                self.assertTrue(lock.is_dir())

                # Without a winner, a later launch can retry after release.
                destination.unlink()
                lock.rmdir()
                retried = self.launch(*args)
                self.assert_profile(retried, "Legacy guild", 101)
                self.assertTrue(destination.is_file())

    def test_inaccessible_legacy_parent_is_not_missing(self):
        legacy = self.old / STANDARD
        destination = self.new_root / STANDARD
        self.fixture(legacy, "Inaccessible guild", 101)
        original = legacy.read_bytes()
        permissions = self.old.stat().st_mode & 0o7777
        try:
            self.old.chmod(0)
            if os.access(self.old, os.X_OK):
                self.skipTest("Current privileges bypass directory permissions")
            result = self.launch()
            self.assertEqual(Path(result["user_dir"]), self.new_root)
            self.assertEqual(result["screen"], "profile_error", result)
            self.assertFalse(destination.exists())
        finally:
            self.old.chmod(permissions)
        self.assertEqual(legacy.read_bytes(), original)

        # An actually absent profile must still open normal guild creation.
        legacy.unlink()
        missing = self.launch()
        self.assertEqual(Path(missing["user_dir"]), self.new_root)
        self.assertEqual(missing["screen"], "guild_creation", missing)
        self.assertFalse(destination.exists())

    def test_renew_waits_for_publication_lock(self):
        for args, filename in [
            ((), STANDARD),
            (("--content=res://content/catalog.json",), CUSTOM),
        ]:
            with self.subTest(filename=filename):
                destination = self.new_root / filename
                lock = Path(str(destination) + ".migration-lock")
                self.fixture(destination, "Existing guild", 101)
                original = destination.read_bytes()
                lock.mkdir()
                blocked = self.launch(*args, "--probe-renew")
                self.assertEqual(Path(blocked["path"]), destination)
                self.assertEqual(blocked["screen"], "commissions", blocked)
                self.assertIn("error", blocked["profile"], blocked)
                self.assertEqual(destination.read_bytes(), original)
                self.assertTrue(lock.is_dir())
                lock.rmdir()
                self.assert_profile(self.launch(*args), "Existing guild", 101)
                self.assert_profile(self.launch(*args, "--probe-renew"),
                                    "Existing guild", 987654)
                self.assert_profile(self.launch(*args), "Existing guild", 987654)

    def test_migration_finds_hidden_legacy_entry(self):
        # Linux marks dot-prefixed entries hidden. Exercise the migration
        # discovery routine directly because the game defaults are not hidden.
        filename = ".hidden-guild.json"
        legacy = self.old / filename
        destination = self.new_root / filename
        self.fixture(legacy, "Hidden guild", 101)
        original = legacy.read_bytes()
        result = self.launch("--probe-migrate=user://" + filename)
        self.assertEqual(result["migration"], {})
        self.assertTrue(destination.is_file())
        self.assertEqual(destination.read_bytes(), original)
        self.assertEqual(legacy.read_bytes(), original)

    def test_interrupted_replacement_does_not_restore_older_legacy(self):
        for args, filename in [
            ((), STANDARD),
            (("--content=res://content/catalog.json",), CUSTOM),
        ]:
            with self.subTest(filename=filename):
                legacy = self.old / filename
                destination = self.new_root / filename
                backup = Path(str(destination) + ".backup")
                self.fixture(legacy, "Legacy guild", 101)
                self.assert_profile(self.launch(*args), "Legacy guild", 101)
                self.assert_profile(self.launch(*args, "--probe-renew"),
                                    "Legacy guild", 987654)
                self.assert_profile(self.launch(*args), "Legacy guild", 987654)

                # Another successful update must preserve the previous
                # committed bytes in the real backup before replacement.
                committed = destination.read_bytes()
                self.assert_profile(self.launch(*args, "--probe-renew"),
                                    "Legacy guild", 987654)
                self.assertTrue(backup.is_file())
                self.assertEqual(backup.read_bytes(), committed)

                # Model interruption after canonical deletion on platforms
                # without atomic replacement, retaining that real backup.
                destination.unlink()
                self.fixture(legacy, "Legacy guild", 101)

                result = self.launch(*args)
                self.assertEqual(Path(result["user_dir"]), self.new_root)
                if result["screen"] == "commissions":
                    self.assert_profile(result, "Legacy guild", 987654)
                    self.assertTrue(destination.is_file())
                else:
                    self.assertEqual(result["screen"], "profile_error", result)
                    self.assertTrue(backup.is_file())
                    self.assertEqual(backup.read_bytes(), committed)
                    if destination.exists():
                        saved = json.loads(destination.read_text())
                        self.assertEqual(saved.get("name"), "Legacy guild")
                        self.assertEqual(int(saved["board_seed"]), 987654)


if __name__ == "__main__":
    unittest.main()
