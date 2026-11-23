import unittest
import json
import tempfile
from pathlib import Path

from recipe import action_name, capture_config, load_fragment, load_registered, merge_fragment, release_prop_hidden, rig_name


class NativeNames(unittest.TestCase):
    def test_conventional_actor_and_source_override(self):
        self.assertEqual(rig_name("knight", {}), "Knight_Rig")
        self.assertEqual(action_name("knight", {}, "Ready"), "Knight | Ready")
        master = {"source_actor": "Mixologist"}
        self.assertEqual(rig_name("alchemist", master), "Mixologist_Rig")
        self.assertEqual(action_name("alchemist", master, "Ready"), "Mixologist | Ready")

    def test_explicit_empty_prefix_has_no_delimiter(self):
        master = {"source_actor": "Bomber", "rig_name": "bomber • armature",
                  "action_prefix": ""}
        self.assertEqual(rig_name("bomber", master), "bomber • armature")
        self.assertEqual(action_name("bomber", master, "Close strike"), "Close strike")

    def test_separate_underscored_rig_and_spaced_prefix(self):
        master = {"rig_name": "Rival_Knight_Rig", "action_prefix": "Rival Knight"}
        self.assertEqual(rig_name("rival_knight", master), "Rival_Knight_Rig")
        self.assertEqual(action_name("rival_knight", master, "Shield Push"),
                         "Rival Knight | Shield Push")


class Fragment(unittest.TestCase):
    def test_add_one_role_without_mutating_base(self):
        masters, takes, releases = {"old": {}}, {"old": {}}, {}
        fragment = {
            "role": "new", "master": {"source": "x.blend", "sha256": "abc"},
            "takes": {"ready": ["Ready", [1], 25, True]},
            "release": ["shot", "arrow", "Arrow", 17, "Release"],
        }
        m, t, r = merge_fragment(masters, takes, releases, fragment)
        self.assertEqual(m["new"], fragment["master"])
        self.assertEqual(t["new"], fragment["takes"])
        self.assertEqual(r["new"], fragment["release"])
        self.assertNotIn("new", masters)
        self.assertNotIn("new", takes)
        self.assertNotIn("new", releases)

    def test_existing_role_rejected(self):
        with self.assertRaises(ValueError):
            merge_fragment({"old": {}}, {}, {}, {
                "role": "old", "master": {}, "takes": {},
            })

    def test_invalid_role_rejected(self):
        with self.assertRaises(ValueError):
            merge_fragment({}, {}, {}, {"role": "../other", "master": {}, "takes": {}})

    def test_selected_registry_ignores_other_incomplete_fragments(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            fragment = {"role": "new", "master": {}, "takes": {"ready": ["Ready", [1], 2, True]}}
            (path / "new.json").write_text(json.dumps(fragment))
            (path / "future.json").write_text("{")
            masters, takes, releases = load_registered(path, {}, {}, {}, ["new"])
            self.assertIn("new", takes)
            masters2, takes2, _ = load_fragment(path / "new.json", masters, takes, releases)
            self.assertEqual(masters2, masters)
            self.assertEqual(takes2, takes)


class CaptureAndRelease(unittest.TestCase):
    def test_legacy_defaults_and_horizontal_override(self):
        self.assertEqual(capture_config({}), (320, [160, 248]))
        self.assertEqual(capture_config({"capture_anchor_x": 91}), (320, [91, 248]))

    def test_larger_canvas_preserves_registered_pixel_offsets(self):
        size, anchor = capture_config({"capture_size": 512, "capture_anchor": [256, 344]})
        self.assertEqual((size, anchor), (512, [256, 344]))
        # An existing source pixel and ground pivot shift by the same padding.
        self.assertEqual((90 + 96) - anchor[0], 90 - 160)
        self.assertEqual((100 + 96) - anchor[1], 100 - 248)

    def test_arrow_visible_only_in_authored_window(self):
        spec = {"draw_and_release": [7, 16]}
        self.assertTrue(release_prop_hidden(spec, "ready", 1))
        self.assertTrue(release_prop_hidden(spec, "draw_and_release", 6))
        self.assertFalse(release_prop_hidden(spec, "draw_and_release", 7))
        self.assertFalse(release_prop_hidden(spec, "draw_and_release", 16))
        self.assertTrue(release_prop_hidden(spec, "draw_and_release", 17))
        self.assertTrue(release_prop_hidden(spec, "defeat", 12))


if __name__ == "__main__":
    unittest.main()
