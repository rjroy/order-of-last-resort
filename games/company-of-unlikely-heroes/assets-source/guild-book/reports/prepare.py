"""Rebuild report PNGs from retained native artwork; never modify inputs."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
GAME = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="empty directory for prepared PNGs")
    args = parser.parse_args()
    manifest = json.loads((HERE / "registration.json").read_text())
    authored = json.loads((GAME / "content/expedition/commissions.json").read_text())["mission_reports"]
    cuts = manifest["cuts"]
    finishes = manifest.get("finishes", {})
    stale = set(cuts) - set(authored)
    if stale:
        parser.error(f"Registered crops have no authored report: {sorted(stale)}")
    if uncut := set(finishes) - set(cuts):
        parser.error(f"Registered finishes have no crop: {sorted(uncut)}")
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
        command = ["magick", str(source), "-crop", f"{w}x{h}+{x}+{y}", "+repage"]
        finish = finishes.get(report)
        if finish:
            px, py = finish.get("mirror_padding", [0, 0])
            width, height = finish["size"]
            if min(px, py) < 0 or min(width, height) < 1:
                parser.error(f"Invalid finish for {report}: {finish}")
            if px or py:
                viewport = f"{w + 2 * px}x{h + 2 * py}-{px}-{py}"
                command.extend([
                    "-virtual-pixel", "Mirror", "-filter", "point",
                    "-set", "option:distort:viewport", viewport, "-distort", "SRT", "0", "+repage",
                ])
            command.extend([
                "-colorspace", "sRGB", "-filter", "Lanczos",
                "-resize", f"{width}x{height}", "-depth", "8",
            ])
        else:
            command.extend(["-colorspace", "sRGB"])
        subprocess.run(command + [
            "-alpha", "off", "-strip",
            "-define", "png:color-type=2", f"PNG24:{args.output / (report + '.png')}",
        ], check=True)


if __name__ == "__main__":
    main()
