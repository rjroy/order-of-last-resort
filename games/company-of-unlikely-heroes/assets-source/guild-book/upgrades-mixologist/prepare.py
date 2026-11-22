#!/usr/bin/env python3
"""Export the seven Mixologist card vignettes from the preserved atlas."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


SOURCE = Path(__file__).resolve().parent
GAME = SOURCE.parents[2]


def magick(*args):
    return subprocess.check_output(["magick", *map(str, args)], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Directory for the seven PNGs")
    parser.add_argument("--contact-sheet", type=Path, help="Optional captioned 318 × 154 review")
    args = parser.parse_args()
    recipe = json.loads((SOURCE / "crops.json").read_text())
    atlas = SOURCE / recipe["source"]
    if hashlib.sha256(atlas.read_bytes()).hexdigest() != recipe["sha256"]:
        raise ValueError(f"Unexpected native atlas: {atlas}")

    rewards = json.loads((GAME / "content/rewards.json").read_text())["upgrades"]
    expected = {key for key, value in rewards.items() if value["hero_id"] == "alchemist"}
    crops = recipe["crops"]
    if set(crops) != expected:
        raise ValueError(f"Upgrade coverage mismatch: {set(crops) ^ expected}")
    source_w, source_h = map(int, magick("identify", "-format", "%w %h", atlas).split())
    width, height = recipe["size"]

    args.output.mkdir(parents=True, exist_ok=True)
    signatures = set()
    labels = []
    for key, (x, y, w, h) in crops.items():
        if not (0 <= x < x + w <= source_w and 0 <= y < y + h <= source_h):
            raise ValueError(f"{key}: crop outside native atlas")
        if abs(width * h - height * w) > max(width, height):
            raise ValueError(f"{key}: crop aspect ratio does not match output")
        output = args.output / f"{key}.png"
        magick(
            atlas, "-crop", f"{w}x{h}+{x}+{y}", "+repage",
            "-colorspace", "sRGB", "-alpha", "off",
            "-filter", "Lanczos", "-resize", f"{width}x{height}!", "-strip",
            "-define", "png:exclude-chunk=date,time", f"PNG24:{output}",
        )
        fmt, ow, oh, space, opaque, mode, colors, signature = magick(
            "identify", "-format", "%m %w %h %[colorspace] %[opaque] %[type] %k %#", output
        ).split()
        if (fmt, int(ow), int(oh), space, opaque, mode) != ("PNG", width, height, "sRGB", "True", "TrueColor"):
            raise ValueError(f"{output}: incorrect format, size, color space or channels")
        if int(colors) < 16 or signature in signatures:
            raise ValueError(f"{output}: blank or duplicate image")
        signatures.add(signature)
        labels.extend(["-label", rewards[key]["label"], output])

    if args.contact_sheet:
        args.contact_sheet.parent.mkdir(parents=True, exist_ok=True)
        magick(
            "montage", "-background", "#ece0c6", "-fill", "#362e24",
            "-font", "Adwaita-Sans", "-pointsize", 13, *labels,
            "-tile", "2x", "-geometry", f"{width}x{height}+9+8", args.contact_sheet,
        )
    print(f"Verified {len(signatures)} unique opaque sRGB PNGs at {width} × {height}.")


if __name__ == "__main__":
    main()
