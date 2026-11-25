"""Show every supplemental drawing at the shipped scale, from a packed cast atlas."""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run(*args):
    subprocess.run(["magick", *map(str, args)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, help="cast atlas + manifest directory")
    parser.add_argument("output", type=Path, help="new evidence directory")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((args.assets / "manifest.json").read_text())
    clips = manifest["actors"]["blacksmith"]["clips"]
    scale = manifest["display_scale"]
    names = list(json.loads((HERE / "takes.json").read_text()))
    font = subprocess.check_output(["fc-match", "-f", "%{file}", "sans"], text=True)
    proof = ["-size", "1080x820", "xc:#ddd1bc", "-font", font, "-pointsize", "13", "-fill", "#352b28"]
    with tempfile.TemporaryDirectory(dir=args.output) as tmp:
        animation = []
        for i, name in enumerate(names):
            clip = clips[name]
            path = args.assets / Path(clip["path"]).name
            y = 116 * i
            proof += ["-annotate", f"+5+{y + 18}", name]
            for j, frame in enumerate(clip["frames"]):
                x, t, w, h = frame["rect"]
                ax, ay = [round(value * scale) for value in clip["anchor"]]
                # Ground is fixed, even as horizontal and vertical extents change.
                # The projectile is shown by itself, registered to its grip point.
                px = 120 + j * 110 - ax
                py = y + (60 if name == "acid_flask" else 92) - ay
                crop = [
                    "(",
                    path,
                    "-crop",
                    f"{w}x{h}+{x}+{t}",
                    "+repage",
                    "-resize",
                    f"{100 * scale:g}%",
                    ")",
                ]
                proof += [
                    *crop,
                    "-geometry",
                    f"{px:+d}{py:+d}",
                    "-composite",
                    "-annotate",
                    f"+{110 + j * 110}+{y + 110}",
                    str(frame["source_frame"]),
                ]
                if name == "acid_flask":
                    continue
                sprite = Path(tmp) / f"{i}-{j}.png"
                run(
                    "-size",
                    "210x134",
                    "xc:#ddd1bc",
                    "-font",
                    font,
                    "-pointsize",
                    13,
                    "-fill",
                    "#352b28",
                    "-annotate",
                    "+8+17",
                    name,
                    *crop,
                    "-geometry",
                    f"{103 - ax:+d}{104 - ay:+d}",
                    "-composite",
                    sprite,
                )
                animation += ["-delay", f"{frame['duration_ms']}x1000", sprite]
            if animation and name != "acid_flask":
                animation += ["-delay", "375x1000", sprite]
        run(*proof, args.output / "board-size.png")
        run(*animation, "-loop", 0, args.output / "motion.gif")


if __name__ == "__main__":
    main()
