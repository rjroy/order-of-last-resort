"""Compare saved-action renders with packaged Knight drawings at small-board scale."""

import argparse
import json
import math
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[7]
CAST = ROOT / "games/company-of-unlikely-heroes/assets/cast"
MANIFEST = json.loads((CAST / "manifest.json").read_text())
SCALE = MANIFEST["display_scale"] * 315 / (5 * 80 + 2 * 34)
PAPER = "#f1e6cc"
INK = "#292d27"
MUTED = "#565747"
RULE = "#bab095"
ACCENT = "#365953"
TILE = "#dccba2"


def magick(*args, capture=False):
    return subprocess.run(["magick", *map(str, args)], check=True,
                          capture_output=capture, text=capture).stdout


def font(family):
    return subprocess.run(["fc-match", "-f", "%{file}", family], check=True,
                          capture_output=True, text=True).stdout


def atlas_pose(actor, clip, frame=None):
    drawing = MANIFEST["actors"][actor]["clips"][clip]
    selected = drawing["frames"][0] if frame is None else next(
        item for item in drawing["frames"] if item["source_frame"] == frame
    )
    x, y, w, h = selected["rect"]
    return [CAST / f"{actor}.png", "-crop", f"{w}x{h}+{x}+{y}", "+repage"], drawing["anchor"]


def alpha_bounds(path):
    w, h, x, y = map(int, magick(
        path, "-alpha", "extract", "-threshold", "0", "-format", "%@",
        "info:", capture=True,
    ).replace("+", "x").split("x"))
    return w, h, x, y


class Page:
    def __init__(self, width, height):
        self.commands = ["-size", f"{width}x{height}", f"xc:{PAPER}", "-gravity", "northwest"]
        self.sans = font("Noto Sans")
        self.serif = font("Noto Serif Display")

    def text(self, x, y, text, size=13, color=INK, display=False):
        self.commands += ["-font", self.serif if display else self.sans, "-fill", color,
                          "-pointsize", size, "-annotate", f"+{x}+{y}", text]

    def panel(self, x, y, w, h, fill, border=None):
        self.commands += ["-fill", fill, "-stroke", border or "none", "-draw",
                          f"rectangle {x},{y} {x+w},{y+h}", "-stroke", "none"]

    def sprite(self, drawing, anchor, x, y):
        # Each image shares a foot location, even across different crops.
        geometry = f"{x-round(anchor[0]*SCALE):+d}{y-round(anchor[1]*SCALE):+d}"
        self.commands += ["(", *drawing, "-filter", "Triangle", "-resize", f"{100*SCALE:.7f}%",
                          ")", "-geometry", geometry, "-compose", "Over", "-composite"]

    def write(self, path):
        magick(*self.commands, "-strip", path)


CAPTIONS = {
    "fitted_pull": ("Reach", "Reel", "Hold the brace"),
    "clear_the_floor": ("Gather", "Sweep wide", "Stay open"),
    "safety_distance": ("Raise palm", "Send away", "Hold palm out"),
    "lend_a_shield": ("Offer", "Release", "Hands empty"),
}


def still(proof, renders, path):
    page = Page(1100, 654)
    page.text(26, 18, "BARNABY’S ORDER OF LAST RESORT   /   ANIMATION STUDY", 13, ACCENT)
    page.text(24, 34, "The Knight, fitted", 48, display=True)
    page.text(717, 56, "65 × 54 px tiles  ·  fixed board camera", 14, MUTED)
    page.panel(26, 104, 1048, 1, RULE)
    page.text(270, 113, "SHIPPED REFERENCE", 12, MUTED)
    page.text(664, 113, "NEW CANDIDATE TAKE", 12, ACCENT)
    for row, (clip, take) in enumerate(proof["takes"].items()):
        y = 137 + row * 119
        page.text(26, y+5, f"0{row+1}", 12, ACCENT)
        page.text(26, y+22, take["label"], 27, display=True)
        control, ref_frames = take["control"]
        page.text(27, y+57, "vs. " + control.replace("_", " ").title(), 13, MUTED)
        for i, frame in enumerate(ref_frames):
            x = 270 + 106*i
            page.panel(x, y, 89, 91, "#e6d8b9")
            page.sprite(*atlas_pose("knight", control, frame), x+43, y+74)
            page.text(x+7, y+75, f"F{frame}", 11, MUTED)
        for i, frame in enumerate(take["proof"]):
            x = 664 + 137*i
            page.panel(x, y, 125, 91, "#dce1cd" if i == 1 else "#e7dcc3")
            page.sprite([renders / take["frames"][str(frame)]], proof["anchor"], x+61, y+73)
            page.text(x+7, y+74, f"F{frame}  {CAPTIONS[clip][i]}", 11, ACCENT if i == 1 else INK)
        if "release" in take:
            release = take["release"]
            # Draw the separate prop just beside the release shot, not in the hand.
            page.sprite([renders / release["prop"]], release["anchor"], 901, y+52)
        page.panel(26, y+108, 1048, 0, RULE)
    page.text(26, 620, "Silent Blender proof · Existing cast lighting and scale · No effects or runtime playback", 13, MUTED)
    page.write(path)


def progress(frame, key, frames):
    t = min(max((frame - key) / frames, 0), 1)
    return t*t*(3 - 2*t)


def motion_panel(page, clip, take, renders, sprite_anchor, x, y, frame):
    page.text(x, y, take["label"], 23, display=True)
    page.panel(x, y+38, 359, 103, "#e7dcc3", RULE)
    for col in range(5):
        page.panel(x+17+65*col, y+68, 65, 54, TILE, RULE)
    center = lambda col: round(x+50+65*col)
    floor = y+102
    ally = atlas_pose("healer", "ready")
    foe = atlas_pose("goblin", "ready")
    key = take["key_frame"]
    shift = progress(frame, key, 4.5)
    actor_col = {"fitted_pull": 1, "clear_the_floor": 2}.get(clip, 0)
    if clip == "fitted_pull":
        page.sprite(*foe, center(3-shift), floor)
    elif clip == "clear_the_floor":
        page.sprite(*ally, center(1-shift), floor)
        page.sprite(*foe, center(3+shift), floor)
    elif clip == "safety_distance":
        page.sprite(*ally, center(2+shift), floor)
    else:
        page.sprite(*ally, center(2), floor)
    shown = max(int(f) for f in take["frames"] if int(f) <= frame)
    page.sprite([renders / take["frames"][str(shown)]], sprite_anchor, center(actor_col), floor)
    if clip == "lend_a_shield" and frame >= key:
        release = take["release"]
        t = progress(frame, key, 5)
        origin = (center(actor_col)+release["offset"][0]*SCALE, floor+release["offset"][1]*SCALE)
        px = origin[0]*(1-t) + (center(2)+9)*t
        py = origin[1]*(1-t) + (floor-12)*t - 7*math.sin(math.pi*t)
        page.sprite([renders / release["prop"]], release["anchor"], round(px), round(py))


def motion(proof, renders, path):
    with tempfile.TemporaryDirectory(prefix="motion-", dir=path.parent) as scratch:
        inputs = []
        for frame in range(1, 34, 2):
            page = Page(788, 419)
            page.text(25, 18, "THE KNIGHT, FITTED   /   SMALL-BOARD MOTION STUDY", 13, ACCENT)
            page.text(25, 389, "Illustrative positions and travel  ·  Not game playback", 12, MUTED)
            for i, (clip, take) in enumerate(proof["takes"].items()):
                x, y = 25+(i % 2)*379, 55+(i//2)*162
                motion_panel(page, clip, take, renders, proof["anchor"], x, y, frame)
            image = Path(scratch) / f"{frame:02}.png"
            page.write(image)
            inputs.extend(("-delay", 56 if frame == 33 else 8+(frame % 3 == 0), image))
        magick(*inputs, "-loop", 0, "-layers", "Optimize", path)


def compose(renders, output):
    proof = json.loads((renders / "proof.json").read_text())
    for take in proof["takes"].values():
        filenames = [*take["frames"].values()]
        if "unshielded" in take:
            filenames.append(take["unshielded"])
        if "release" in take:
            filenames.append(take["release"]["prop"])
        for filename in filenames:
            path = renders / filename
            size = magick("identify", "-format", "%wx%h", path, capture=True)
            assert size == "320x320", (path, size)
            w, h, x, y = alpha_bounds(path)
            assert min(w, h) > 10 and x >= 3 and y >= 3 and x + w <= 317 and y + h <= 317, path
    still(proof, renders, output / "knight-fitted-board-proof.png")
    motion(proof, renders, output / "knight-fitted-board-motion.gif")
    print("Decoded all source renders, verified uncropped silhouettes and composed both board proofs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("renders", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    compose(args.renders, args.output)
