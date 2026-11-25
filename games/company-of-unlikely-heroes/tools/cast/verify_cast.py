"""Check source hashes, encoded sprites, registration and authored release timing."""

import argparse
import hashlib
import json
import math
import struct
import subprocess
from pathlib import Path
from takes import RELEASES, TAKES
from recipe import action_name, capture_config, load_fragment, load_registered, load_supplement, manifest_supplements


def verify_layer(role, clips, master, takes, release, alpha, width, height):
    size, _ = capture_config(master)
    for name, (action, samples, end, loop) in takes.items():
        clip = clips[name]
        assert len(clip["anchor"]) == 2 and all(map(math.isfinite, clip["anchor"]))
        tip_offset = master.get("projectile_tip_offsets", {}).get(name)
        if tip_offset is not None:
            assert len(tip_offset) == 2 and all(map(math.isfinite, tip_offset))
            assert clip["tip"] == [round(a + b, 3) for a, b in zip(clip["anchor"], tip_offset)]
        frames = clip["frames"]
        assert clip["path"] == f"res://assets/cast/{role}.png"
        assert clip["action"] == action_name(role, master, action) and clip["loop"] == loop
        assert [f["source_frame"] for f in frames] == samples
        elapsed = 0
        for frame in frames:
            assert elapsed == round((frame["source_frame"] - samples[0]) * 1000 / 24)
            assert frame["duration_ms"] > 0.0
            elapsed += frame["duration_ms"]
            x, y, w, h = frame["rect"]
            assert 0 <= x and 0 <= y and x + w <= width and y + h <= height
            assert w <= size and h <= size
            rows = [alpha[i * width + x:i * width + x + w] for i in range(y, y + h)]
            assert any(map(any, rows)), (role, name, frame)
            assert not any(b for row in rows[:3] + rows[-3:] for b in row)
            assert not any(b for row in rows for b in row[:3] + row[-3:])
        assert elapsed == round((end - samples[0]) * 1000 / 24)
    if release:
        verify_release(role, clips, release)


def verify_release(role, clips, release_spec):
    actor_clip, prop_clip, _, source_frame, _ = release_spec
    throw = clips[actor_clip]
    release = throw["release"]
    before = [f["duration_ms"] for f in throw["frames"] if f["source_frame"] < source_frame]
    assert any(f["source_frame"] == source_frame for f in throw["frames"])
    assert release["time_ms"] == sum(before)
    assert release["clip"] == prop_clip
    assert len(release["offset"]) == 2 and all(map(math.isfinite, release["offset"]))
    assert clips[prop_clip]["frames"][0]["source_frame"] == source_frame
    if role == "harpooner":
        assert clips[prop_clip]["tip"] == [160, 11.5]


def verify_stock_pixels(role, packaged, stock, clips, baseline):
    assert all(clips[name] == clip for name, clip in baseline["clips"].items()), role
    w, h = struct.unpack(">II", stock.read_bytes()[16:24])
    available_w, available_h = struct.unpack(">II", packaged.read_bytes()[16:24])
    assert w <= available_w and h <= available_h
    raw = subprocess.check_output(["magick", str(stock), "-depth", "8", "rgba:-"])
    current = subprocess.check_output(
        ["magick", str(packaged), "-crop", f"{w}x{h}+0+0", "+repage", "-depth", "8", "rgba:-"]
    )
    assert current == raw, (role, "stock sheet differs")
    return sum(len(clip["frames"]) for clip in baseline["clips"].values())


def verify_sources(root, actor, master, shelf_sources=()):
    assert actor["source"] == "art/" + master["source"]
    assert actor["sha256"] == master["sha256"]
    supplements = manifest_supplements(master, shelf_sources)
    assert actor.get("supplements", []) == supplements, (actor["source"], "supplemental provenance differs")
    for source in (actor, *supplements):
        path = root / source["source"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == source["sha256"], path


def main():
    game = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=game / "assets/cast")
    parser.add_argument("--recipe", type=Path, help="optional single-actor staging fragment")
    parser.add_argument("--stock", type=Path, help="verify exact shipped atlas pixels and clip entries")
    parser.add_argument("actors", nargs="*", help="verify only these registered actors")
    args = parser.parse_args()
    dest = args.assets
    manifest = json.loads((dest / "manifest.json").read_text())
    baseline = json.loads((args.stock / "manifest.json").read_text()) if args.stock else None
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
        supplement = load_supplement(role, master, takes)
        shelf_sources = ()
        if supplement:
            capture, extra, release, libraries = supplement
            shelf_sources = libraries or [capture]
        verify_sources(root, actor, master, shelf_sources)
        png = dest / f"{role}.png"
        width, height = struct.unpack(">II", png.read_bytes()[16:24])
        alpha = subprocess.check_output(
            ["magick", str(png), "-alpha", "extract", "-depth", "8", "gray:-"]
        )
        assert len(alpha) == width * height
        clips = actor["clips"]
        verify_layer(role, clips, master, takes, releases.get(role), alpha, width, height)
        expected = set(takes)
        if supplement:
            expected.update(extra)
            verify_layer(role, clips, capture, extra, release, alpha, width, height)
        assert set(clips) == expected, (role, "missing or unexpected clips")
        if baseline:
            preserved = verify_stock_pixels(role, png, args.stock / f"{role}.png",
                                            clips, baseline["actors"][role])
            print(f"{role}: verified unchanged stock atlas RGBA and {preserved} sample entries")
    print(
        "Verified all authored samples, source hashes, timing, alpha padding and projectile releases."
    )


if __name__ == "__main__":
    main()
