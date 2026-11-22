"""Check source hashes, encoded sprites, registration and authored release timing."""

import hashlib
import json
import math
import struct
import subprocess
from pathlib import Path
from takes import RELEASES, TAKES


def main():
    game = Path(__file__).resolve().parents[2]
    dest = game / "assets/cast"
    masters = json.loads(Path(__file__).with_name("masters.json").read_text())
    manifest = json.loads((dest / "manifest.json").read_text())
    root = game.parents[1] / manifest["source_root"]
    for role, takes in TAKES.items():
        actor = manifest["actors"][role]
        source_actor = masters[role].get("source_actor", role.title())
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
                clip["action"] == f"{source_actor} | {action}" and clip["loop"] == loop
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
    for role, (actor_clip, prop_clip, _, source_frame, _) in RELEASES.items():
        clips = manifest["actors"][role]["clips"]
        throw = clips[actor_clip]
        release = throw["release"]
        before = [f["duration_ms"] for f in throw["frames"] if f["source_frame"] < source_frame]
        assert any(f["source_frame"] == source_frame for f in throw["frames"])
        assert release["time_ms"] == sum(before)
        assert release["clip"] == prop_clip
        assert len(release["offset"]) == 2 and all(map(math.isfinite, release["offset"]))
        assert clips[prop_clip]["frames"][0]["source_frame"] == source_frame
    print(
        "Verified all authored samples, source hashes, timing, alpha padding and projectile releases."
    )


if __name__ == "__main__":
    main()
