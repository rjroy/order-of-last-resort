#!/usr/bin/env python3
"""Reproduce the approved petition plates into a new, empty directory."""

import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 prepare.py <new-or-empty-output-directory>")
    source = Path(__file__).resolve().parent
    output = Path(sys.argv[1]).resolve()
    if output.is_relative_to(source) or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
        raise SystemExit("Output must be an empty directory outside the source package")
    output.mkdir(parents=True, exist_ok=True)
    for manifest in sorted((source / "masters").glob("*.json")):
        data = json.loads(manifest.read_text())
        master = source / data["master"]
        if hashlib.sha256(master.read_bytes()).hexdigest() != data["master_sha256"]:
            raise SystemExit(f"Master hash mismatch: {master}")
        for name, crop in data["crops"].items():
            target = output / f"{name}.png"
            if crop["geometry"] is None:
                shutil.copyfile(master, target)
            else:
                subprocess.run(["magick", str(master), "-crop", crop["geometry"], "+repage",
                                "-strip", "-alpha", "off", "-depth", "8", f"PNG24:{target}"],
                               check=True)


if __name__ == "__main__":
    main()
