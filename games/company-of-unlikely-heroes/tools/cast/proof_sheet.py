"""Make a labeled proof sheet from the delivered atlas rectangles, not source renders."""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

# Include held/empty hand transition and distinguish the actors' strongest gestures.
BEATS = {
    "potion": [13, 17, 23, 24, 36],
    "acid": [13, 16, 18, 21, 32],
    "guard": [39],
    "ally_heal": [17],
    "self_heal": [17],
    "bonk": [15],
    "blast": [14],
    "pull": [24],
    "swap": [10],
    "misdirect": [14],
    "retreat": [13],
    "inspiring_melody": [13],
    "healing_sonnet": [25],
    "raise_dead": [34],
    "summon_skeleton": [13],
    "wave": [15],
    "dont_go": [19],
    "say_hello": [19],
    "offer_flower": [14, 22, 26, 53],
    ("harpooner", "pursue"): [5, 9, 14],
    ("harpooner", "close_thrust"): [5, 8, 13],
    ("harpooner", "ranged_cast"): [8, 10, 11, 13, 23],
    ("harpooner", "hit"): [4],
    ("harpooner", "defeat"): [9, 22],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    game = Path(__file__).resolve().parents[2]
    parser.add_argument("output", type=Path)
    parser.add_argument("--assets", type=Path, default=game / "assets/cast")
    args = parser.parse_args()
    manifest = json.loads((args.assets / "manifest.json").read_text())
    font = subprocess.check_output(["fc-match", "-f", "%{file}", "sans"], text=True)
    with tempfile.TemporaryDirectory() as tmp:
        tiles = []
        for role, actor in manifest["actors"].items():
            for name, clip in actor["clips"].items():
                default = BEATS.get(name, [clip["frames"][0]["source_frame"]])
                for beat in BEATS.get((role, name), default):
                    frame = next(f for f in clip["frames"] if f["source_frame"] == beat)
                    x, y, w, h = frame["rect"]
                    path = args.assets / Path(clip["path"]).name
                    tile = Path(tmp) / f"{len(tiles)}.png"
                    tiles.append(tile)
                    subprocess.run(
                        [
                            "magick",
                            str(path),
                            "-crop",
                            f"{w}x{h}+{x}+{y}",
                            "+repage",
                            "-resize",
                            "60%",
                            "-background",
                            "#cabfac",
                            "-gravity",
                            "center",
                            "-extent",
                            "200x160",
                            "-font",
                            font,
                            "-pointsize",
                            "12",
                            "-gravity",
                            "south",
                            "-annotate",
                            "+0+0",
                            f"{role} / {name} {beat}",
                            str(tile),
                        ],
                        check=True,
                    )
        subprocess.run(
            [
                "magick",
                "montage",
                *map(str, tiles),
                "-tile",
                "5x",
                "-geometry",
                "+1+1",
                str(args.output),
            ],
            check=True,
        )


if __name__ == "__main__":
    main()
