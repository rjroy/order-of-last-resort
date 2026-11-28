"""Rebuild report PNGs from retained native artwork; never modify inputs."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
GAME = HERE.parents[2]


def mirror_paper_edge(rgb, width, height, px, py, period):
    """Reflect only the blank outer strip; a wider reflection can duplicate ink."""
    stride = width * 3
    if len(rgb) != stride * height:
        raise ValueError("Expected exactly one 8-bit RGB crop")

    def reflect(distance):
        offset = distance % (2 * period)
        return min(offset, 2 * period - 1 - offset)

    left = [3 * reflect(i) for i in range(px - 1, -1, -1)]
    right = [3 * (width - 1 - reflect(i)) for i in range(px)]
    rows = []
    for y in range(height):
        row = rgb[y * stride:(y + 1) * stride]
        rows.append(b"".join(row[x:x + 3] for x in left) + row +
                    b"".join(row[x:x + 3] for x in right))
    top = [rows[reflect(i)] for i in range(py - 1, -1, -1)]
    bottom = [rows[-1 - reflect(i)] for i in range(py)]
    return b"".join(top + rows + bottom)


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
        input_rgb = None
        finish = finishes.get(report)
        if finish:
            px, py = finish.get("mirror_padding", [0, 0])
            width, height = finish["size"]
            if min(px, py) < 0 or min(width, height) < 1:
                parser.error(f"Invalid finish for {report}: {finish}")
            period = finish.get("paper_edge_period")
            if period is not None:
                if type(period) is not int or not 0 < period <= min(w, h) or not (px or py):
                    parser.error(f"Invalid paper edge period for {report}: {finish}")
                crop_rgb = subprocess.check_output(command + ["-colorspace", "sRGB", "-depth", "8", "RGB:-"])
                input_rgb = mirror_paper_edge(crop_rgb, w, h, px, py, period)
                command = ["magick", "-size", f"{w + 2 * px}x{h + 2 * py}", "-depth", "8", "RGB:-"]
            elif px or py:
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
        ], input=input_rgb, check=True)


if __name__ == "__main__":
    main()
