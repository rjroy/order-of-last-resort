import sys
import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bake_cast import alpha_bounds, append_shelves, crop, encode_atlas, pack
from verify_cast import verify_sources


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

    def test_append_shelves_preserves_stock_origin_and_clear_side_gutter(self):
        with tempfile.TemporaryDirectory() as tmp:
            stock, extra, combined = (Path(tmp) / f"{name}.png" for name in ("stock", "extra", "all"))
            stock_pixel = bytes((7, 14, 21, 128))
            extra_pixel = bytes((17, 34, 51, 255))
            encode_atlas(stock, 1, 2, stock_pixel * 2)
            encode_atlas(extra, 3, 1, extra_pixel * 3)
            self.assertEqual(append_shelves(combined, stock, extra), 2)
            raw = subprocess.check_output(["magick", str(combined), "-depth", "8", "rgba:-"])
            self.assertEqual(raw, (stock_pixel + bytes(8)) * 2 + extra_pixel * 3)

    def test_pack_records_appended_library_without_replacing_primary_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            art = work / "art"
            art.mkdir()
            (art / "master.blend").write_bytes(b"test model")
            (art / "actions.blend").write_bytes(b"test actions")
            master_sha = hashlib.sha256(b"test model").hexdigest()
            library_sha = hashlib.sha256(b"test actions").hexdigest()
            master = {
                "source": "master.blend", "sha256": master_sha,
                "motion_library": {"source": "actions.blend", "sha256": library_sha},
            }
            rgba = bytearray(320 * 320 * 4)
            i = (100 * 320 + 100) * 4
            rgba[i:i + 4] = b"\x01\x02\x03\xff"
            encode_atlas(work / "sample.png", 320, 320, rgba)
            (work / "actor.json").write_text(json.dumps({
                "ready": {"frames": [{"file": "sample.png", "source_frame": 1, "duration_ms": 42}],
                          "anchor": [100, 100], "loop": False, "action": "Ready"}
            }))
            actor = pack("actor", work, work, master)
            self.assertEqual((actor["source"], actor["sha256"]), ("art/master.blend", master_sha))
            self.assertEqual(actor["supplements"], [{"source": "art/actions.blend", "sha256": library_sha}])
            verify_sources(work, actor, master)
            with self.assertRaisesRegex(AssertionError, "supplemental provenance"):
                verify_sources(work, {**actor, "supplements": []}, master)
            (art / "actions.blend").write_bytes(b"changed actions")
            with self.assertRaisesRegex(AssertionError, r"actions\.blend"):
                verify_sources(work, actor, master)


if __name__ == "__main__":
    unittest.main()
