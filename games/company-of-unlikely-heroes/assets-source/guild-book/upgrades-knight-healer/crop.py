#!/usr/bin/env python3
"""Render the reviewed, explicit sheet crops into individual reward PNGs."""

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


SOURCE = Path(__file__).resolve().parent
GAME = SOURCE.parents[2]
FAMILIES = ("knight_", "healer_")


def image_size(path):
    size = subprocess.check_output(
        ["magick", "identify", "-format", "%w %h", str(path)], text=True
    )
    return tuple(map(int, size.split()))


def validate_manifest(manifest, expected_ids, sheet_sizes):
    if set(manifest["crops"]) != expected_ids:
        raise ValueError("crop IDs do not match the Knight and Healer reward inventory")
    out_w, out_h = manifest["size"]
    if any(type(value) is not int or value < 1 for value in (out_w, out_h)):
        raise ValueError("output dimensions must be positive integers")
    seen = set()
    for reward, crop in manifest["crops"].items():
        if not re.fullmatch(r"(knight|healer)_[a-z0-9_]+", reward):
            raise ValueError(f"invalid reward ID: {reward}")
        sheet, x, y, width, height = crop
        w, h = sheet_sizes[sheet]
        if any(type(value) is not int for value in (x, y, width, height)):
            raise ValueError(f"{reward}: crop coordinates must be integers")
        if min(x, y) < 0 or min(width, height) <= 0 or x + width > w or y + height > h:
            raise ValueError(f"{reward}: crop lies outside {sheet} ({w} × {h})")
        key = tuple(crop)
        if key in seen:
            raise ValueError(f"{reward}: crop coordinates reused")
        seen.add(key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=GAME / "assets/guild-book/upgrades")
    args = parser.parse_args()
    manifest = json.loads((SOURCE / "crops.json").read_text())
    definitions = json.loads((GAME / "content/expedition/rewards.json").read_text())["upgrades"]
    expected = {reward for reward in definitions if reward.startswith(FAMILIES)}
    sheets = {}
    for name, sha256 in manifest["sheets"].items():
        path = (SOURCE / name).resolve()
        if path.parent not in (SOURCE, SOURCE.parent / "study"):
            raise ValueError(f"sheet must be in the family or shared study directory: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha256:
            raise ValueError(f"source sheet hash mismatch: {name}")
        sheets[name] = image_size(path)
    validate_manifest(manifest, expected, sheets)

    args.out.mkdir(parents=True, exist_ok=True)
    out_w, out_h = manifest["size"]
    for reward, (sheet, x, y, width, height) in manifest["crops"].items():
        result = args.out / f"{reward}.png"
        subprocess.run(
            [
                "magick", str(SOURCE / sheet),
                "-crop", f"{width}x{height}+{x}+{y}", "+repage",
                "-colorspace", "sRGB", "-alpha", "off",
                "-filter", "Lanczos", "-resize", f"{out_w}x{out_h}^",
                "-gravity", "center", "-extent", f"{out_w}x{out_h}",
                "-strip", "-define", "png:exclude-chunks=date,time",
                f"PNG24:{result}",
            ],
            check=True,
        )
        if image_size(result) != (out_w, out_h):
            raise ValueError(f"{reward}: unexpected output dimensions")


if __name__ == "__main__":
    main()
