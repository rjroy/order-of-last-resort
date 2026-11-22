"""Rebuild report PNGs from retained source sheets; never modify inputs."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
GAME = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="empty directory for the 20 PNGs")
    args = parser.parse_args()
    manifest = json.loads((HERE / "registration.json").read_text())
    authored = json.loads((GAME / "content/commissions.json").read_text())["mission_reports"]
    cuts = manifest["cuts"]
    if set(cuts) != set(authored):
        parser.error(f"Incomplete report mappings: {sorted(set(cuts) ^ set(authored))}")
    args.output.mkdir(parents=True, exist_ok=True)
    if any(args.output.iterdir()):
        parser.error(f"Output directory must be empty: {args.output}")

    sources = {}
    for name, expected in manifest["sources"].items():
        path = HERE / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected["sha256"]:
            parser.error(f"Source does not match recorded SHA-256: {path}")
        width, height = map(int, subprocess.check_output(
            ["magick", "identify", "-ping", "-format", "%w %h", str(path)],
            text=True,
        ).split())
        sources[name] = (path, width, height)

    for report, (name, x, y, w, h) in cuts.items():
        source, source_w, source_h = sources[name]
        if min(x, y) < 0 or min(w, h) < 1 or x + w > source_w or y + h > source_h:
            parser.error(f"Invalid crop for {report}: {x}, {y}, {w}, {h}")
        subprocess.run([
            "magick", str(source), "-crop", f"{w}x{h}+{x}+{y}", "+repage",
            "-colorspace", "sRGB", "-alpha", "off", "-strip",
            "-define", "png:color-type=2", f"PNG24:{args.output / (report + '.png')}",
        ], check=True)


if __name__ == "__main__":
    main()
