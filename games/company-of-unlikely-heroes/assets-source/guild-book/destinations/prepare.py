#!/usr/bin/env python3
"""Validate destination art or render the manifest's reviewed crops into an empty directory."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


PROPERTIES = "PNG 960x500 sRGB 8 True"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def magick(*args: str) -> str:
    return subprocess.check_output(["magick", *args], text=True).strip()


def verify(output: Path, expected: dict) -> None:
    properties = magick("identify", "-format", "%m %wx%h %[colorspace] %z %[opaque]", str(output))
    if properties != PROPERTIES:
        raise ValueError(f"{output}: {properties}, expected {PROPERTIES}")
    magick(str(output), "null:")
    if digest(output) != expected["sha256"]:
        raise ValueError(f"{output}: candidate checksum differs")


def render(native: Path, rectangle: str, output: Path) -> None:
    magick(str(native), "-crop", rectangle, "+repage", "-filter", "Lanczos",
           "-resize", "960x500!", "-alpha", "off", "-colorspace", "sRGB", "-depth", "8",
           "-strip", "-define", "png:exclude-chunks=date,time", "PNG24:" + str(output))


def main() -> None:
    source = Path(__file__).resolve().parent
    package = source.parent.parent.parent / "assets" / "guild-book" / "destinations"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render-to", type=Path, help="stage rebuilt textures in a separate directory")
    args = parser.parse_args()
    manifest = json.loads((source / "manifest.json").read_text())
    textures = manifest["destinations"]
    target = args.render_to.resolve() if args.render_to else package
    if args.render_to:
        target.mkdir(parents=True, exist_ok=True)
        if any((target / f"{mission}.png").exists() for mission in textures):
            parser.error("render destination must not contain any of the packaged textures")
    for master in manifest["masters"].values():
        native = source / master["file"]
        if digest(native) != master["sha256"]:
            raise ValueError(f"{native}: native checksum differs")
        client_dimensions = magick("identify", "-format", "%wx%h", str(native))
        if client_dimensions != master["pixels"]:
            raise ValueError(f"{native}: native dimensions differ")
    for mission, crop in textures.items():
        output = target / f"{mission}.png"
        if args.render_to:
            native = source / manifest["masters"][crop["master"]]["file"]
            render(native, crop["rectangle"], output)
        verify(output, crop)
    if not args.render_to and {path.stem for path in package.glob("*.png")} != set(textures):
        raise ValueError(f"{package}: packaged IDs differ from manifest")
    print(f"Decoded and checked {len(textures)} textures and {len(manifest['masters'])} native hashes.")


if __name__ == "__main__":
    main()
