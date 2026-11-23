"""Build registered actor atlases from accepted masters. Run with Python 3."""

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
RECIPE = HERE / "cast"
GAME = HERE.parent
sys.path.insert(0, str(RECIPE))
from recipe import capture_config, load_registered
from takes import RELEASES, TAKES
SIZE = 320
PADDING = 3
# Frame-local tip relative to the detached prop's root registration, in the
# approved Harpooner F11 projection. This is unaffected by atlas cropping.
PROJECTILE_TIPS = {("harpooner", "harpoon_projectile"): (153.519, -3.439)}


def alpha_bounds(rgba, width):
    """Half-open rectangle of nonzero alpha, including faint contour pixels."""
    alpha = rgba[3::4]
    rows = [alpha[i : i + width] for i in range(0, len(alpha), width)]
    occupied = [(y, row) for y, row in enumerate(rows) if row.strip(b"\0")]
    if not occupied:
        raise ValueError("empty silhouette")
    left = min(width - len(row.lstrip(b"\0")) for _, row in occupied)
    right = max(len(row.rstrip(b"\0")) for _, row in occupied)
    return left, occupied[0][0], right, occupied[-1][0] + 1


def crop(data, box, size=SIZE):
    x, y, r, b = box
    return b"".join(data[(i * size + x) * 4 : (i * size + r) * 4] for i in range(y, b))


def pack(role, work, dest, master):
    size, _ = capture_config(master)
    clips = json.loads((work / f"{role}.json").read_text())
    used = dict.fromkeys(f["file"] for clip in clips.values() for f in clip["frames"])
    pixels = {
        f: subprocess.check_output(["magick", str(work / f), "-depth", "8", "rgba:-"])
        for f in used
    }
    if any(len(buf) != size * size * 4 for buf in pixels.values()):
        raise ValueError(f"{role}: capture dimensions do not match recipe")
    boxes = {f: alpha_bounds(buf, size) for f, buf in pixels.items()}
    tiles = {}
    positions = {}
    to_place = []
    for name, clip in clips.items():
        # Same registration for each drawing in a take, independent of pose extent.
        group = [boxes[f["file"]] for f in clip["frames"]]
        x = min(b[0] for b in group) - PADDING
        y = min(b[1] for b in group) - PADDING
        r = max(b[2] for b in group) + PADDING
        b = max(b[3] for b in group) + PADDING
        if min(x, y) < 0 or max(r, b) > size:
            raise ValueError(
                f"{role}/{name}: insufficient capture margin {(x, y, r, b)}"
            )
        w, h = r - x, b - y
        clip["anchor"] = [round(a - o, 3) for a, o in zip(clip["anchor"], [x, y])]
        tip_offset = master.get("projectile_tip_offsets", {}).get(
            name, PROJECTILE_TIPS.get((role, name))
        )
        if tip_offset is not None:
            if len(tip_offset) != 2 or not all(math.isfinite(v) for v in tip_offset):
                raise ValueError(f"{role}/{name}: invalid projectile tip offset")
            clip["tip"] = [
                round(a + offset, 3)
                for a, offset in zip(clip["anchor"], tip_offset)
            ]
        clip["path"] = f"res://assets/cast/{role}.png"
        for frame in clip["frames"]:
            buf = crop(pixels[frame.pop("file")], (x, y, r, b), size)
            key = (w, h, hashlib.sha256(buf).digest())
            if key not in tiles:
                tiles[key] = buf
            to_place.append((frame, key))
    # Shelf pack sorted tall first; translucent edges have their own clear gutters.
    width = max(
        max(k[0] for k in tiles),
        math.ceil(math.sqrt(sum(w * h for w, h, _ in tiles)) / 16) * 16,
    )
    left = top = height = 0
    for key in sorted(tiles, key=lambda k: (-k[1], -k[0])):
        w, h, _ = key
        if left + w > width:
            left = 0
            top += height
            height = 0
        positions[key] = [left, top, w, h]
        left += w
        height = max(height, h)
    height += top
    atlas = bytearray(width * height * 4)
    for key, buf in tiles.items():
        x, y, w, h = positions[key]
        for i in range(h):
            p = ((y + i) * width + x) * 4
            atlas[p : p + w * 4] = buf[i * w * 4 : (i + 1) * w * 4]
    for frame, key in to_place:
        frame["rect"] = positions[key]
    path = dest / f"{role}.png"
    subprocess.run(
        [
            "magick",
            "-size",
            f"{width}x{height}",
            "-depth",
            "8",
            "rgba:-",
            "-strip",
            f"PNG32:{path}",
        ],
        input=atlas,
        check=True,
    )
    # Verify the delivered PNG, not only the pre-encoding buffer.
    if subprocess.check_output(["magick", str(path), "-depth", "8", "rgba:-"]) != atlas:
        raise ValueError(f"{role}: PNG round trip changed pixels")
    return {
        "source": "art/" + master["source"],
        "sha256": master["sha256"],
        "clips": clips,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--threads", type=int, default=6)
    parser.add_argument("--output", type=Path, default=GAME / "assets/cast")
    args = parser.parse_args()
    masters, _, _ = load_registered(
        RECIPE / "actors", json.loads((RECIPE / "masters.json").read_text()), TAKES, RELEASES
    )
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)

        def render(role):
            subprocess.run(
                [
                    "blender",
                    "-b",
                    "-t",
                    str(args.threads),
                    "--python-exit-code",
                    "1",
                    "-P",
                    str(RECIPE / "bake_actor.py"),
                    "--",
                    role,
                    str(work),
                ],
                check=True,
                env={**os.environ, "MAGICK_THREAD_LIMIT": "1"},
            )

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            list(pool.map(render, masters))
        publish(work, args.output, masters)


def publish(work, dest, masters):
    meta = {
        "version": 1,
        "display_scale": 0.375,
        "source_root": ".lore/work/games/company-of-unlikely-heroes",
        "pixels_per_metre": 256 / 2.44,
        "camera_euler_xyz": [1.150829196, 0, -0.435386419],
        "actors": {r: pack(r, work, dest, m) for r, m in masters.items()},
    }
    (dest / "manifest.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
