"""Validate delivered decoded pixels. Optionally write a view-only contact strip:
python authoring/bake_sprites_check.py /tmp/opencode/ferryman-sprite-check.png
"""

import json
import subprocess
import sys
from pathlib import Path

PILOT = Path(__file__).resolve().parents[1]


def magick(*args):
    return subprocess.check_output(["magick", *map(str, args)])


def main():
    data = json.loads((PILOT / "assets/sprites.json").read_text())
    strips = []
    for name, s in data["sprites"].items():
        path = PILOT / s["texture"]
        frames = s["frames"]
        w, h = data["registration_size"]
        anchor = s["anchor"]
        assert 0 < anchor[0] < w and 0 < anchor[1] < h
        assert (
            magick("identify", "-format", "%wx%h", path).decode()
            == f"{w * len(frames)}x{h}"
        )
        alpha_bytes = []
        role_bounds = []
        for i, frame in enumerate(frames):
            x, y, fw, fh = frame["rect"]
            assert [x, y, fw, fh] == [i * w, 0, w, h] and frame["duration_ms"] > 0
            alpha = magick(
                path,
                "-crop",
                f"{w}x{h}+{x}+{y}",
                "+repage",
                "-alpha",
                "extract",
                "-depth",
                "8",
                "gray:-",
            )
            assert len(alpha) == w * h
            active = [idx for idx, a in enumerate(alpha) if a >= 64]
            xs = [j % w for j in active]
            ys = [j // w for j in active]
            bbox = min(xs), min(ys), max(xs), max(ys)
            assert (
                min(xs) > 2
                and min(ys) > 2
                and max(xs) < w - 3
                and max(ys) < h - 3
                and max(alpha) == 255
            )
            for row in range(h):
                assert alpha[row * w] == alpha[(row + 1) * w - 1] == 0
            assert not any(alpha[:w] + alpha[-w:])
            role_bounds.append(bbox)
            alpha_bytes.append(alpha)
        if len(frames) > 1:
            assert len(set(alpha_bytes)) > len(frames) // 2, (
                "No readable silhouette motion"
            )
        print(
            name,
            "frame bounds (inclusive, alpha >= 64):",
            role_bounds,
            "; display heights:",
            [round((b[3] - b[1] + 1) * data["display_scale"], 1) for b in role_bounds],
        )
        strips.append(path)
    if len(sys.argv) > 1:
        magick(
            *strips,
            "-background",
            "#c6b58f",
            "-gravity",
            "West",
            "-append",
            "-alpha",
            "remove",
            "-resize",
            "50%",
            sys.argv[1],
        )
        print("Wrote", sys.argv[1])


if __name__ == "__main__":
    main()
