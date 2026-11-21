import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bake_cast import alpha_bounds


class AlphaBounds(unittest.TestCase):
    def test_faint_edges_across_rows_and_holes(self):
        pixels = bytearray(4 * 5 * 6)
        for x, y, alpha in [(3, 1, 255), (0, 3, 1), (4, 3, 1)]:
            pixels[(y * 5 + x) * 4 + 3] = alpha
        self.assertEqual(alpha_bounds(pixels, 5), (0, 1, 5, 4))

    def test_empty_is_not_a_sprite(self):
        with self.assertRaises(ValueError):
            alpha_bounds(bytes(64), 4)


if __name__ == "__main__":
    unittest.main()
