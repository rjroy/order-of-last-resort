"""Check source hashes, encoded sprites, registration and authored release timing."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path
from takes import TAKES


def main():
    game = Path(__file__).resolve().parents[2]
    dest = game / "assets/cast"
    manifest = json.loads((dest / "manifest.json").read_text())
    root = game.parents[1] / manifest["source_root"]
    for role, takes in TAKES.items():
        actor = manifest["actors"][role]
        assert (
            hashlib.sha256((root / actor["source"]).read_bytes()).hexdigest()
            == actor["sha256"]
        )
        png = dest / f"{role}.png"
        width, height = struct.unpack(">II", png.read_bytes()[16:24])
        alpha = subprocess.check_output(
            ["magick", str(png), "-alpha", "extract", "-depth", "8", "gray:-"]
        )
        assert len(alpha) == width * height
        for name, (action, samples, end, loop) in takes.items():
            clip = actor["clips"][name]
            frames = clip["frames"]
            assert clip["path"] == f"res://assets/cast/{role}.png"
            assert (
                clip["action"] == role.title() + " | " + action and clip["loop"] == loop
            )
            assert [f["source_frame"] for f in frames] == samples
            elapsed = 0
            for frame in frames:
                assert (
                    elapsed == round((frame["source_frame"] - samples[0]) * 1000 / 24)
                    and frame["duration_ms"] > 0
                )
                elapsed += frame["duration_ms"]
                x, y, w, h = frame["rect"]
                assert x >= 0 and y >= 0 and x + w <= width and y + h <= height
                rows = [
                    alpha[i * width + x : i * width + x + w] for i in range(y, y + h)
                ]
                assert any(any(row) for row in rows), (role, name, frame)
                assert not any(b for row in rows[:3] + rows[-3:] for b in row)
                assert not any(b for row in rows for b in row[:3] + row[-3:])
            assert elapsed == round((end - samples[0]) * 1000 / 24)
    throw = manifest["actors"]["zombie"]["clips"]["offer_flower"]
    assert (
        throw["release"]["time_ms"]
        == sum(f["duration_ms"] for f in throw["frames"] if f["source_frame"] < 22)
        == 875
    )
    print(
        "Verified all authored samples, source hashes, timing, alpha padding and gift release."
    )


if __name__ == "__main__":
    main()
