"""Check source hashes, encoded sprites, registration and authored release timing."""

import argparse
import hashlib
import json
import math
import struct
import subprocess
from pathlib import Path
from takes import RELEASES, TAKES
from recipe import action_name, capture_config, load_fragment, load_registered


def main():
    game = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=game / "assets/cast")
    parser.add_argument("--recipe", type=Path, help="optional single-actor staging fragment")
    parser.add_argument("actors", nargs="*", help="verify only these registered actors")
    args = parser.parse_args()
    dest = args.assets
    manifest = json.loads((dest / "manifest.json").read_text())
    registered_dir = Path(__file__).with_name("actors")
    selected = args.actors or sorted(
        set(manifest["actors"]) | {path.stem for path in registered_dir.glob("*.json")}
    )
    masters, takes_by_role, releases = load_registered(
        registered_dir,
        json.loads(Path(__file__).with_name("masters.json").read_text()),
        TAKES, RELEASES, selected,
    )
    masters, takes_by_role, releases = load_fragment(args.recipe, masters, takes_by_role, releases)
    root = game.parents[1] / manifest["source_root"]
    roles = args.actors or list(takes_by_role)
    if unknown := set(roles) - takes_by_role.keys():
        parser.error(f"unregistered actors: {', '.join(sorted(unknown))}")
    for role in roles:
        takes = takes_by_role[role]
        actor = manifest["actors"][role]
        master = masters[role]
        size, _ = capture_config(master)
        assert actor["source"] == "art/" + master["source"]
        assert actor["sha256"] == master["sha256"]
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
            assert len(clip["anchor"]) == 2 and all(map(math.isfinite, clip["anchor"]))
            frames = clip["frames"]
            assert clip["path"] == f"res://assets/cast/{role}.png"
            assert (
                clip["action"] == action_name(role, master, action) and clip["loop"] == loop
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
                assert w <= size and h <= size
                assert x >= 0 and y >= 0 and x + w <= width and y + h <= height
                rows = [
                    alpha[i * width + x : i * width + x + w] for i in range(y, y + h)
                ]
                assert any(any(row) for row in rows), (role, name, frame)
                assert not any(b for row in rows[:3] + rows[-3:] for b in row)
                assert not any(b for row in rows for b in row[:3] + row[-3:])
            assert elapsed == round((end - samples[0]) * 1000 / 24)
    for role, (actor_clip, prop_clip, _, source_frame, _) in releases.items():
        if role not in roles:
            continue
        clips = manifest["actors"][role]["clips"]
        throw = clips[actor_clip]
        release = throw["release"]
        before = [f["duration_ms"] for f in throw["frames"] if f["source_frame"] < source_frame]
        assert any(f["source_frame"] == source_frame for f in throw["frames"])
        assert release["time_ms"] == sum(before)
        assert release["clip"] == prop_clip
        assert len(release["offset"]) == 2 and all(map(math.isfinite, release["offset"]))
        assert clips[prop_clip]["frames"][0]["source_frame"] == source_frame
        if role == "harpooner":
            tip = clips[prop_clip]["tip"]
            assert len(tip) == 2 and all(map(math.isfinite, tip))
            assert tip == [160, 11.5]
    print(
        "Verified all authored samples, source hashes, timing, alpha padding and projectile releases."
    )


if __name__ == "__main__":
    main()
