#!/usr/bin/env python3
"""Extract the two approved, text-free petition illustrations at native size."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


HERE = Path(__file__).resolve().parent
GAME = HERE.parents[2]
REPO = GAME.parents[1]


def execute(*args: str) -> None:
    subprocess.run(("magick", *args), check=True)


def export_plate(recipe: dict, plate: dict, output: Path) -> None:
    source = REPO / recipe["concept_directory"] / plate["source"]
    if hashlib.sha256(source.read_bytes()).hexdigest() != plate["sha256"]:
        raise ValueError(f"Approved concept checksum did not match: {source}")
    x, y, width, height = plate["crop"]
    source_width, source_height = recipe["image_size"]
    if min(x, y) < 0 or min(width, height) <= 0 or x + width > source_width or y + height > source_height:
        raise ValueError(f"Invalid crop for {source}")
    feather = plate["edge_feather"]
    if not 0 < feather < min(width, height) / 2:
        raise ValueError(f"Invalid feather for {source}")
    # Soften only the outside edge of the painting's paper, not the figure or wash.
    alpha = f"pow(clamp(min(min(i,w-1-i),min(j,h-1-j))/{feather}),1.3)"
    execute(
        str(source), "-crop", f"{width}x{height}+{x}+{y}", "+repage",
        "-colorspace", "sRGB", "-alpha", "off",
        "(", "-size", f"{width}x{height}", "xc:black", "-colorspace", "Gray", "-fx", alpha, ")",
        "-compose", "CopyOpacity", "-composite", "-strip",
        "-define", "png:exclude-chunks=date,time", f"PNG32:{output / plate['output']}",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default=GAME / "assets/guild-book/petitions", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    recipe = json.loads((HERE / "recipe.json").read_text(encoding="utf-8"))
    for plate in recipe["plates"]:
        export_plate(recipe, plate, args.output)


if __name__ == "__main__":
    main()
