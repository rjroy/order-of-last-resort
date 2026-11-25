"""Make one combined pose and motion review from the exact reopened Actions."""

import argparse
import json
from pathlib import Path
import re
import subprocess


HERE = Path(__file__).resolve().parent
ASSETS_REL = Path("games/company-of-unlikely-heroes/assets")
ROOT = next(path for path in HERE.parents if (path / ASSETS_REL).is_dir())
ASSETS = ROOT / ASSETS_REL
CAST = ASSETS / "cast"
PILOT = HERE.parents[1] / "pilots/ferryman-crossing/assets"
MANIFEST = json.loads((CAST / "manifest.json").read_text())
SCALE = MANIFEST["display_scale"] * 315 / (5 * 80 + 2 * 34)
PAPER, INK, MUTE = "#f3e9d4", "#26322b", "#5f624f"
ACCENT, RULE = "#38624d", "#c0ae8a"
SCENARIOS = {
    "keep_your_head_down": ("Healer", "Soft crook tap instead of a downward strike.",
        ("Bank the crook", "Cover tap", "Release"), 2, 2, "knight"),
    "fitted_pull": ("Bad Bard", "Lowers the bow; reels it in off the strings.",
        ("Reach low", "Reel inward", "Finish"), 3, 2, "goblin"),
    "send_off": ("Mixologist", "Both palms press away; the feet stay planted.",
        ("Gather", "Press outward", "Hold"), 2, 3, "goblin"),
    "hostile_dose": ("Mixologist", "One brisk tip replaces the two-handed offer.",
        ("Lift", "Tip at contact", "Withdraw"), 2, 2, "goblin"),
}


def run(*args, capture=False):
    return subprocess.run(list(map(str, args)), check=True, text=capture,
                          capture_output=capture).stdout


def magick(*args, capture=False):
    return run("magick", *args, capture=capture)


def font(family):
    return run("fc-match", "-f", "%{file}", family, capture=True)


def stock(actor, clip="ready", frame=1):
    shot = MANIFEST["actors"][actor]["clips"][clip]
    x, y, w, h = next(s["rect"] for s in shot["frames"] if s["source_frame"] == frame)
    return [CAST / f"{actor}.png", "-crop", f"{w}x{h}+{x}+{y}", "+repage"], shot["anchor"]


def candidate(renders, proof, key, frame):
    return [renders / f"{key}-{frame:02}.png"], proof["anchor"]


class Page:
    fonts = {}

    def __init__(self, w, h):
        self.commands = ["-size", f"{w}x{h}", f"xc:{PAPER}", "-gravity", "northwest"]
        if not Page.fonts:
            Page.fonts.update(sans=font("Noto Sans"), serif=font("Noto Serif Display"))

    def text(self, x, y, text, size=13, ink=INK, display=False):
        self.commands += ["-font", self.fonts["serif" if display else "sans"], "-fill", ink,
                          "-pointsize", size, "-annotate", f"+{x}+{y}", text]

    def box(self, x, y, w, h, fill, stroke="none"):
        self.commands += ["-fill", fill, "-stroke", stroke, "-draw",
                          f"rectangle {x},{y} {x+w},{y+h}", "-stroke", "none"]

    def image(self, args, x, y):
        self.commands += ["(", *args, ")", "-geometry", f"{x:+d}{y:+d}", "-compose", "Over", "-composite"]

    def sprite(self, source, anchor, x, y, scale=SCALE):
        self.image([*source, "-filter", "Triangle", "-resize", f"{100*scale:.8f}%"],
                   round(x-anchor[0]*scale), round(y-anchor[1]*scale))

    def save(self, path):
        magick(*self.commands, "-strip", path)


def still(renders, proof, path):
    p = Page(1184, 714)
    p.text(34, 22, "BARNABY’S ORDER OF LAST RESORT    /    FITTED ACTION STUDY", 14, ACCENT)
    p.text(31, 42, "Small gestures, clearer outcomes", 43, display=True)
    p.text(35, 103, "Four editable action candidates • Common board angle • No committed game effects", 14, MUTE)
    p.box(34, 140, 1115, 1, RULE)
    p.text(345, 151, "SHIPPED CONTROL", 12, MUTE)
    p.text(587, 151, "EDITABLE ACTION  /  BOARD SCALE", 12, ACCENT)
    p.text(973, 151, "KEY  /  1.8× DETAIL", 12, MUTE)
    for i, (key, take) in enumerate(proof["takes"].items()):
        y = 178 + 125 * i
        if i % 2 == 0:
            p.box(33, y-2, 1117, 114, "#eddfc3")
        wearer, note, labels, *_ = SCENARIOS[key]
        p.text(48, y+5, f"0{i+1}   /   {wearer.upper()}", 12, ACCENT)
        p.text(47, y+23, take["label"], 27, display=True)
        parts = note.split(";", 1) if ";" in note else (
            note[:note.rfind(" ", 0, 38)], note[note.rfind(" ", 0, 38)+1:],
        )
        for line, part in enumerate(parts):
            p.text(48, y+61+16*line, part.strip() + (";" if line == 0 and ";" in note else ""), 12, MUTE)
        clip, source_frame = take["control"]
        controls = [("ready", 1, "Ready"), (clip, source_frame, clip.replace("_", " ").title())]
        for j, (control, f, label) in enumerate(controls):
            x = 345+97*j
            p.box(x, y+4, 86, 95, "#e2d2b3", "#cdb895")
            p.sprite(*stock(take["role"], control, f), x+43, y+72)
            p.text(x+5, y+76, f"{label} · F{f}", 10, MUTE)
        for j, ((f, _), label) in enumerate(zip(take["stages"][1:4], labels)):
            x = 586+119*j
            p.box(x, y+4, 109, 95, "#d6deca" if j == 1 else "#eee3cb", "#a7b69c" if j == 1 else RULE)
            p.sprite(*candidate(renders, proof, key, f), x+54, y+72)
            p.text(x+6, y+76, f"F{f}  {label}", 11, ACCENT if j == 1 else MUTE)
        p.sprite(*candidate(renders, proof, key, take["beat"]), 1041, y+101, SCALE*1.8)
        p.box(34, y+111, 1115, 0, RULE)
    p.text(34, 681, "Board-scale figures use a 65 × 54 px tile reference. Fixed lighting. Each take returns to its own Ready pose.", 13, MUTE)
    p.save(path)


def progress(frame, beat):
    t = min(max((frame - beat) * 1000 / (24*180), 0), 1)
    return t*t*(3 - 2*t)


def motion_panel(p, renders, proof, key, take, x, y, frame, terrain):
    wearer, _, _, start, end, recipient = SCENARIOS[key]
    p.text(x, y, wearer.upper(), 11, ACCENT)
    p.text(x, y+13, take["label"], 24, display=True)
    p.image([terrain], x, y+50)
    for row in range(2):
        for col in range(7):
            p.box(x+65*col, y+50+54*row, 65, 54, "none", "#6a563666")
    p.box(x+65+2, y+104+2, 61, 50, "#57795327", "#48624d")
    p.box(x+5*65+2, y+104+2, 61, 50, "#b553332c", "#93492d")
    foot = lambda col: (x+33+65*col, y+146)
    shift = progress(frame, take["beat"])
    p.sprite(*stock("wizard"), *foot(0))
    p.sprite([PILOT / "crate.png"], (128, 216), *foot(4))
    p.sprite(*stock(recipient), *foot(start+(end-start)*shift))
    shown = max(f for f in take["frames"] if f <= frame)
    p.sprite(*candidate(renders, proof, key, shown), *foot(1))
    text = take["stages"][4 if frame >= take["stages"][-1][0] else 3 if frame >= take["stages"][3][0]
                            else 2 if frame >= take["beat"] else 1 if frame >= take["stages"][1][0] else 0][1]
    p.text(x, y+162, text, 12, ACCENT)


def motion(renders, proof, output):
    scratch = output / "motion-frames"
    scratch.mkdir(exist_ok=False)
    terrain = scratch / "tactical-ground.png"
    magick(ASSETS / "boards/frontier_field.png", "-crop", "1183x281+80+210", "+repage",
           "-resize", "455x108!", "-fill", "#ead9b2", "-colorize", "24", "-strip", terrain)
    frames = sorted({f for item in proof["takes"].values() for f in item["frames"]})
    inputs = []
    for f, following in zip(frames, frames[1:]+[frames[-1]+19]):
        page = Page(987, 536)
        page.text(30, 20, "FOUR FITTED ACTIONS", 13, ACCENT)
        page.text(30, 38, "Tactical motion review", 29, display=True)
        page.text(605, 54, f"F{f:02d}   /   Silent • 65 × 54 px cells", 13, MUTE)
        page.box(30, 86, 927, 1, RULE)
        for i, (key, take) in enumerate(proof["takes"].items()):
            motion_panel(page, renders, proof, key, take, 30+473*(i % 2), 100+196*(i//2), f, terrain)
        page.text(30, 507, "Illustrative cells and one-cell travel. No Godot footage or committed outcome effects.", 13, MUTE)
        image = scratch / f"{f:02}.png"
        page.save(image)
        delay = round((following-1)*100/24) - round((f-1)*100/24)
        inputs += ["-delay", delay, image]
    gif = output / "remaining-fitted-motion.gif"
    magick(*inputs, "-loop", "0", "-layers", "Optimize", gif)
    decoded = magick("identify", "-format", "%n ", gif, capture=True).split()
    assert len(decoded) == len(frames) and all(int(n) == len(frames) for n in decoded)


def check_renders(renders, proof):
    n = 0
    for key, take in proof["takes"].items():
        for frame in take["frames"]:
            path = renders / f"{key}-{frame:02}.png"
            size = proof["size"]
            assert magick("identify", "-format", "%wx%h", path, capture=True) == f"{size}x{size}"
            bounds = magick(path, "-alpha", "extract", "-threshold", "0", "-format", "%@", "info:", capture=True)
            w, h, x, y = map(int, re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", bounds).groups())
            assert min(w, h) > 15 and min(x, y) >= 3 and x+w <= size-3 and y+h <= size-3, path
            n += 1
    print(f"Decoded {n} registered poses with complete alpha bounds.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("renders", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    proof = json.loads((args.renders / "proof.json").read_text())
    assert set(proof["takes"]) == set(SCENARIOS)
    args.output.mkdir(parents=True, exist_ok=False)
    check_renders(args.renders, proof)
    png = args.output / "remaining-fitted-poses.png"
    still(args.renders, proof, png)
    magick("identify", png)
    motion(args.renders, proof, args.output)
