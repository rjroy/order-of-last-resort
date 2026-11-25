"""Compare staged role atlases to stock and to the approved registered captures."""

import argparse
import json
import struct
import subprocess
from pathlib import Path

SHA = "024912f109deb844faad9a13a267abc80ea79a0b1fe92dc5330a24595d3d3fb9"


def load(directory, role):
    return json.loads((directory / "manifest.json").read_text())["actors"][role]


def rgba(path):
    width, height = struct.unpack(">II", path.read_bytes()[16:24])
    data = subprocess.check_output(["magick", str(path), "-depth", "8", "rgba:-"])
    assert len(data) == width * height * 4, path
    return width, height, data


def rect(image, box):
    width, height, data = image
    x, y, w, h = box
    assert 0 <= x < x + w <= width and 0 <= y < y + h <= height, (box, width, height)
    return b"".join(data[4 * (r * width + x):4 * (r * width + x + w)] for r in range(y, y + h))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("role", choices=("healer", "bard", "alchemist"))
    parser.add_argument("stock", type=Path, help="original stock PNG and manifest")
    parser.add_argument("stage", type=Path, help="staged PNG and manifest")
    parser.add_argument("renders", type=Path, help="verified review_actions.py render directory")
    args = parser.parse_args()
    role = args.role
    base, staged = (load(directory, role) for directory in (args.stock, args.stage))
    original, result = (rgba(directory / f"{role}.png") for directory in (args.stock, args.stage))
    assert rect(result, (0, 0, original[0], original[1])) == original[2], "stock pixels changed"
    assert all(staged["clips"][k] == v for k, v in base["clips"].items()), "stock metadata changed"
    assert (base["source"], base["sha256"]) == (staged["source"], staged["sha256"])
    proof = json.loads((args.renders / "proof.json").read_text())
    assert proof["candidate_sha256"] == SHA
    added = {k: take for k, take in proof["takes"].items() if take["role"] == role}
    assert set(staged["clips"]) == base["clips"].keys() | added.keys()
    assert any(s["sha256"] == SHA for s in staged["supplements"])
    report = {}
    for key, take in added.items():
        clip = staged["clips"][key]
        frames = clip["frames"]
        assert not clip["loop"] and not clip.get("release"), key
        assert clip["path"] == f"res://assets/cast/{role}.png"
        assert [f["source_frame"] for f in frames] == take["frames"], key
        total = 0
        for frame in frames:
            at = frame["source_frame"]
            assert total == round((at - 1) * 1000 / 24)
            total += frame["duration_ms"]
            x, y, w, h = frame["rect"]
            assert y >= original[1], "new rectangle intrudes on stock shelf"
            ox, oy = (a - b for a, b in zip(proof["anchor"], clip["anchor"]))
            reference = rgba(args.renders / f"{key}-{at:02}.png")
            assert rect(result, [x, y, w, h]) == rect(reference, [ox, oy, w, h]), (key, at)
        assert total == round(take["stages"][-1][0] * 1000 / 24), key
        report[key] = {"drawings": len(frames), "duration_ms": total, "impact_frame": take["beat"]}
    print(json.dumps({"role": role, "stock_rects_and_pixels": "identical", "approved_drawings": report}))


if __name__ == "__main__":
    main()
