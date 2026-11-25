#!/usr/bin/env python3
"""Export the exact inspected vignette crops from the preserved native sheets."""

import argparse
import json
from pathlib import Path
import subprocess


SOURCE = Path(__file__).resolve().parent
GAME = SOURCE.parents[2]


def magick(*args):
    return subprocess.check_output(["magick", *map(str, args)], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Directory for candidate PNGs")
    parser.add_argument("--contact-sheet", type=Path, help="Optional local review PNG")
    args = parser.parse_args()
    recipe = json.loads((SOURCE / "crops.json").read_text())
    rewards = json.loads((GAME / "content/expedition/rewards.json").read_text())["upgrades"]
    expected = {key for key in rewards if key.startswith(("bard_", "necromancer_"))}
    reviewed = recipe["crops"]
    if set(reviewed) != expected:
        raise ValueError(f"Upgrade coverage mismatch: {set(reviewed) ^ expected}")
    width, height = recipe["size"]

    args.output.mkdir(parents=True, exist_ok=True)
    signatures = set()
    review = []
    for key, (sheet, x, y, w, h) in reviewed.items():
        source = SOURCE / sheet
        sw, sh = map(int, magick("identify", "-format", "%w %h", source).split())
        if not (0 <= x < x + w <= sw and 0 <= y < y + h <= sh):
            raise ValueError(f"{key}: crop falls outside {source.name}")
        if abs(width * h - height * w) > max(width, height):
            raise ValueError(f"{key}: crop aspect ratio does not match output")

        output = args.output / f"{key}.png"
        magick(
            source, "-crop", f"{w}x{h}+{x}+{y}", "+repage",
            "-colorspace", "sRGB", "-alpha", "off",
            "-filter", "Lanczos", "-resize", f"{width}x{height}!", "-strip",
            "-define", "png:exclude-chunk=date,time", f"PNG24:{output}",
        )
        fmt, ow, oh, space, unique, signature = magick(
            "identify", "-format", "%m %w %h %[colorspace] %k %#", output
        ).split()
        if (fmt, int(ow), int(oh), space) != ("PNG", width, height, "sRGB"):
            raise ValueError(f"{output}: incorrect output format, size, or color space")
        if int(unique) < 16 or signature in signatures:
            raise ValueError(f"{output}: empty or duplicate image")
        signatures.add(signature)
        if args.contact_sheet:
            review.extend(["-label", rewards[key]["label"], output])

    if args.contact_sheet:
        args.contact_sheet.parent.mkdir(parents=True, exist_ok=True)
        magick(
            "montage", "-background", "#ece0c6", "-fill", "#362e24",
            "-font", "Adwaita-Sans", "-pointsize", 13, *review,
            "-tile", "3x", "-geometry", f"{width}x{height}+9+8", args.contact_sheet,
        )
    print(f"Verified {len(signatures)} unique RGB PNGs at {width} x {height}.")


if __name__ == "__main__":
    main()
