import sys
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bake_cast import alpha_bounds, crop, pack


class AlphaBounds(unittest.TestCase):
    def test_faint_edges_across_rows_and_holes(self):
        pixels = bytearray(4 * 5 * 6)
        for x, y, alpha in [(3, 1, 255), (0, 3, 1), (4, 3, 1)]:
            pixels[(y * 5 + x) * 4 + 3] = alpha
        self.assertEqual(alpha_bounds(pixels, 5), (0, 1, 5, 4))

    def test_empty_is_not_a_sprite(self):
        with self.assertRaises(ValueError):
            alpha_bounds(bytes(64), 4)

    def test_wider_canvas_crop_and_alpha_bounds(self):
        pixels = bytearray(4 * 6 * 6)
        pixels[(4 * 6 + 4) * 4: (4 * 6 + 4) * 4 + 4] = b"\x01\x02\x03\xff"
        box = alpha_bounds(pixels, 6)
        self.assertEqual(box, (4, 4, 5, 5))
        self.assertEqual(crop(pixels, box, 6), b"\x01\x02\x03\xff")

    def test_pack_expanded_capture_preserves_anchor(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            pixels = bytearray(512 * 512 * 4)
            pixels[(300 * 512 + 400) * 4: (300 * 512 + 400) * 4 + 4] = b"\x01\x02\x03\xff"
            subprocess.run(
                ["magick", "-size", "512x512", "-depth", "8", "rgba:-", f"PNG32:{work / 'sample.png'}"],
                input=pixels, check=True,
            )
            (work / "sample_actor.json").write_text(json.dumps({
                "ready": {"frames": [{"file": "sample.png", "source_frame": 1, "duration_ms": 1000}],
                          "anchor": [256, 344], "loop": True, "action": "Actor | Ready"}
            }))
            master = {"source": "models/test.blend", "sha256": "test",
                      "capture_size": 512, "capture_anchor": [256, 344]}
            actor = pack("sample_actor", work, work, master)
            clip = actor["clips"]["ready"]
            self.assertEqual(clip["anchor"], [-141, 47])
            self.assertEqual(clip["frames"][0]["rect"][2:], [7, 7])

    def test_recipe_tip_offset_survives_packing(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            pixels = bytearray(320 * 320 * 4)
            pixels[(100 * 320 + 100) * 4: (100 * 320 + 100) * 4 + 4] = b"\x01\x02\x03\xff"
            subprocess.run(
                ["magick", "-size", "320x320", "-depth", "8", "rgba:-", f"PNG32:{work / 'sample.png'}"],
                input=pixels, check=True,
            )
            (work / "actor.json").write_text(json.dumps({
                "arrow": {"frames": [{"file": "sample.png", "source_frame": 17, "duration_ms": 42}],
                          "anchor": [100, 100], "loop": False, "action": "Arrow"}
            }))
            master = {"source": "test.blend", "sha256": "test",
                      "projectile_tip_offsets": {"arrow": [-2.5, 1.25]}}
            clip = pack("actor", work, work, master)["clips"]["arrow"]
            self.assertEqual(clip["anchor"], [3, 3])
            self.assertEqual(clip["tip"], [0.5, 4.25])


if __name__ == "__main__":
    unittest.main()
