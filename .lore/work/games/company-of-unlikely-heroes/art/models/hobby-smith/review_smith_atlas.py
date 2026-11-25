"""Check the Smith's delivered pixels and make a board-scale atlas proof."""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[7]
GAME = ROOT / "games/company-of-unlikely-heroes"
STOCK = GAME / "assets/cast"
SIZE = 320
ANCHOR = (160, 248)
MINIMUM_LAYOUT = 315 / (5 * 80 + 2 * 34)
CELL = (round(96 * MINIMUM_LAYOUT), round(80 * MINIMUM_LAYOUT))


def magick(*args, data=None):
    return subprocess.check_output(["magick", *map(str, args)], input=data)


class Asset:
    def __init__(self, directory, role):
        manifest = json.loads((directory / "manifest.json").read_text())
        self.clips = manifest["actors"][role]["clips"]
        self.scale = manifest["display_scale"]
        path = directory / f"{role}.png"
        self.width = int(magick("identify", "-format", "%w", path))
        self.rgba = magick(path, "-depth", 8, "rgba:-")

    def drawing(self, name, source):
        clip = self.clips[name]
        frame = next(f for f in clip["frames"] if f["source_frame"] == source)
        x, y, w, h = frame["rect"]
        return w, h, b"".join(
            self.rgba[((y + row) * self.width + x) * 4:((y + row) * self.width + x + w) * 4]
            for row in range(h)
        )

    def registered(self, name, source):
        w, h, pixels = self.drawing(name, source)
        x, y = (p - round(a) for p, a in zip(ANCHOR, self.clips[name]["anchor"]))
        assert 0 <= x <= SIZE - w and 0 <= y <= SIZE - h
        canvas = bytearray(SIZE * SIZE * 4)
        for row in range(h):
            start = ((y + row) * SIZE + x) * 4
            canvas[start:start + w * 4] = pixels[row * w * 4:(row + 1) * w * 4]
        return bytes(canvas)

    def stamp(self, name, source, *tail):
        displayed = round(SIZE * self.scale * MINIMUM_LAYOUT)
        return magick(
            "-size", f"{SIZE}x{SIZE}", "-depth", 8, "rgba:-", "-filter", "Triangle",
            "-resize", f"{displayed}x{displayed}", *tail, data=self.registered(name, source)
        )


def check_primary_unchanged(full, primary):
    assert full.scale == primary.scale
    count = 0
    for name, before in primary.clips.items():
        after = full.clips[name]
        assert {k: v for k, v in before.items() if k != "frames"} == {
            k: v for k, v in after.items() if k != "frames"
        }
        assert len(before["frames"]) == len(after["frames"])
        for old, new in zip(before["frames"], after["frames"]):
            assert old["source_frame"] == new["source_frame"]
            assert old["duration_ms"] == new["duration_ms"]
            source = old["source_frame"]
            assert full.drawing(name, source) == primary.drawing(name, source), (name, source)
            count += 1
    print(f"PASS: {count} primary samples retain exact cropped RGBA, timing, anchors and loops")


def check_smith(asset):
    ready = asset.registered("ready", 1)
    for name, start, stop in [("try_this", 1, 33), ("hammer_time", 1, 34), ("pursue", 1, 28)]:
        assert asset.registered(name, start) == ready, (name, "start")
        ending = asset.registered(name, stop)
        assert ending[3::4] == ready[3::4], (name, "alpha seam")
        if name == "pursue":
            # Identical alpha matters at the travel-to-Ready cut. Floating-point
            # evaluation of the shifted pose can perturb a few RGB samples.
            differing = {i // 4 for i, (a, b) in enumerate(zip(ending, ready)) if a != b}
            maximum = max(abs(a - b) for a, b in zip(ending, ready))
            assert len(differing) <= 10 and maximum <= 8, (name, "color seam")
            print(f"PASS: Pursue settles on exact Ready alpha, RGB differs at {len(differing)} pixels (max {maximum}/255)")
        else:
            assert ending == ready, (name, "color seam")
    print("PASS: Try This and Hammer Time join Ready with exact RGBA")
    idle = asset.stamp("ready", 1, "-depth", 8, "rgba:-")[3::4]
    for name, frame in [("try_this", 13), ("try_this", 18), ("hammer_time", 12),
                        ("hammer_time", 17), ("pursue", 6), ("pursue", 19)]:
        beat = asset.stamp(name, frame, "-depth", 8, "rgba:-")[3::4]
        changed = sum((a > 127) != (b > 127) for a, b in zip(idle, beat))
        assert changed > 20, (name, frame, changed)
        print(f"{name} F{frame:02d}: {changed} silhouette pixels changed vs Ready at {CELL[0]}×{CELL[1]}")
    if "recover" in asset.clips:
        assert asset.registered("down", 24) == asset.registered("recover", 1)
        assert asset.registered("recover", 26) == ready
        assert asset.registered("hit", 17) == ready
        assert asset.registered("defeat", 24) != asset.registered("down", 24)
        acid = asset.clips["acid"]
        assert acid["release"]["time_ms"] == 708 and acid["release"]["clip"] == "acid_flask"
        assert len(asset.clips["acid_flask"]["frames"]) == 1
        print("PASS: hit/recover return to Ready, down joins Recover and defeat stays separate")


def proof(asset, output):
    smith = lambda name, frame, label: (asset, name, frame, label)
    rows = [
        [
            (Asset(STOCK, name), "ready", 1, label)
            for name, label in [("knight", "Knight"), ("healer", "Healer"), ("wizard", "Caster")]
        ] + [smith("ready", 1, "Smith"), (Asset(STOCK, "alchemist"), "ready", 1, "Mixologist")],
        [smith("ready", frame, f"Ready {frame:02d}") for frame in (1, 5, 9, 13, 21)],
        [smith("try_this", frame, f"Fit {frame:02d}") for frame in (1, 6, 13, 18, 33)],
        [smith("hammer_time", frame, f"Hammer {frame:02d}") for frame in (1, 12, 15, 17, 34)],
        [smith("pursue", frame, f"Step {frame:02d}") for frame in (1, 6, 13, 19, 28)],
    ]
    if "recover" in asset.clips:
        rows += [
            [smith("bonk", f, f"Bonk {f:02d}") for f in (1, 9, 15, 18, 28)],
            [smith(n, f, label) for n, f, label in [
                ("acid", 10, "Acid 10"), ("acid", 16, "Held 16"), ("acid", 18, "Release 18"),
                ("acid", 21, "Empty 21"), ("acid_flask", 18, "Separate vial"),
            ]],
            [smith(n, f, label) for n, f, label in [
                ("hit", 5, "Hit 05"), ("down", 16, "Down 16"), ("down", 24, "Hold 24"),
                ("recover", 22, "Recover 22"), ("defeat", 24, "Defeat 24"),
            ]],
        ]
    font = subprocess.check_output(["fc-match", "-f", "%{file}", "sans"], text=True)
    tile_w, tile_h = CELL
    top = 17
    width = tile_w * len(rows[0])
    height = top + tile_h + 14
    displayed = round(SIZE * asset.scale * MINIMUM_LAYOUT)
    draw_scale = displayed / SIZE
    ink = "#584d37"
    background = GAME / "assets/boards/frontier_field.png"
    with tempfile.TemporaryDirectory(dir=output.parent) as cache:
        paths = []
        for ridx, row in enumerate(rows):
            layers = [
                background, "-crop", "650x196+480+380", "+repage",
                "-resize", f"{width}x{height}!", "-fill", "#d7c69858",
                "-draw", f"rectangle 0,0 {width - 1},{height - 1}",
            ]
            for col, (actor, name, frame, label) in enumerate(row):
                x = col * tile_w
                outline = "#8d6148" if ridx and col == 2 else "#62553d70"
                layers += [
                    "-fill", "none", "-stroke", outline, "-strokewidth", 1, "-draw",
                    f"rectangle {x},{top} {x + tile_w - 1},{top + tile_h - 1}",
                ]
                sprite = Path(cache) / f"{ridx}-{col}.png"
                actor.stamp(name, frame, f"PNG32:{sprite}")
                foot_x = x + round(49 * MINIMUM_LAYOUT)
                foot_y = top + round(62 * MINIMUM_LAYOUT)
                pos = (foot_x - round(ANCHOR[0] * draw_scale), foot_y - round(ANCHOR[1] * draw_scale))
                layers += [
                    sprite, "-geometry", f"{pos[0]:+d}{pos[1]:+d}", "-compose", "Over", "-composite",
                    "-fill", ink, "-stroke", "none", "-font", font, "-pointsize", 8,
                    "-annotate", f"+{x + 4}+{height - 3}", label,
                ]
            path = Path(cache) / f"row-{ridx}.png"
            magick(*layers, path)
            paths.append(path)
        magick(*paths, "-append", "-strip", output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("atlas", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--primary", type=Path, help="optional frozen four-clip staging directory")
    args = parser.parse_args()
    asset = Asset(args.atlas, "blacksmith")
    if args.primary:
        check_primary_unchanged(asset, Asset(args.primary, "blacksmith"))
    check_smith(asset)
    proof(asset, args.output)


if __name__ == "__main__":
    main()
