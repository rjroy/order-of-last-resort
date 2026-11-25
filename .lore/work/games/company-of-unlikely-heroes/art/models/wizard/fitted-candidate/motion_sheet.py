"""Compose a small board-scale motion sheet from candidate renders and exact atlas frames."""

import argparse
import base64
from functools import lru_cache
from html import escape
import json
from pathlib import Path
import re
import subprocess


CAST = Path("games/company-of-unlikely-heroes/assets/cast")
ROOT = next(p for p in Path(__file__).resolve().parents if (p / CAST).is_dir())
INK = "#282725"
MINT = "#d7edbc"
SHIFT = "#c0e6d7"
PANEL = "#344544"
W, H = 1136, 1146


def magick(*args):
    return subprocess.run(["magick", *map(str, args)], check=True, capture_output=True).stdout


def text(value, x, y, size=12, color="#554a37", serif=False):
    font = "Noto Serif Display" if serif else "Noto Sans"
    return f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" fill="{color}">{escape(value)}</text>'


def line(x1, y1, x2, y2, color, width, attrs=""):
    return f'<path d="M{x1:g} {y1:g} L{x2:g} {y2:g}" fill="none" stroke="{color}" stroke-width="{width}" {attrs}/>'


def rect(x, y, w, h, fill, stroke="none", radius=0):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}"/>'


def foot(cell):
    return 49 + 96 * cell[0], 62 + 80 * cell[1]


def board(signed_cells):
    out = [rect(0, 0, 288, 160, PANEL, "#283a37", 4)]
    for y in (0, 80):
        for x in (0, 96, 192):
            tint = "#465852" if (x // 96 + y // 80) % 2 else "#40534e"
            out.append(rect(x + 1, y + 1, 94, 78, tint, "#50615a", 4))
    for cell, kind in signed_cells:
        x, y = (int(96 * cell[0]), int(80 * cell[1]))
        if kind == "landing":
            out.append(rect(x + 4, y + 4, 88, 72, "#435b55", "#879d80", 4))
    return out


def marker(cell, kind):
    x, y = foot(cell)
    color = "#e5c28c" if kind == "foe" else "#d6ddba"
    if kind == "landing":
        return f'<ellipse cx="{x}" cy="{y}" rx="16" ry="7" fill="none" stroke="#b4c5a3" stroke-dasharray="4 3"/>'
    glyph = (f"M{x - 5:g} {y - 23:g} L{x:g} {y - 29:g} {x + 5:g} {y - 23:g} {x:g} {y - 17:g} Z"
             if kind == "foe" else
             f"M{x - 5:g} {y - 24:g} Q{x:g} {y - 31:g} {x + 5:g} {y - 24:g} L{x + 7:g} {y - 17:g} H{x - 7:g} Z")
    return (f'<ellipse cx="{x}" cy="{y}" rx="14" ry="6" fill="{INK}"/>'
            f'<path d="{glyph}" fill="{color}" stroke="{INK}" stroke-width="2"/>'
            f'<circle cx="{x}" cy="{y-10}" r="2.6" fill="{color}"/>')


def feedback(cell, heal, progress=0):
    # Match bridge_art.gd's committed recipient marks and fade.
    x, y = foot(cell)
    color = MINT if heal else SHIFT
    reach = 4 + 8 * (1 - (1 - progress)**3)
    alpha = 1 - progress**2
    attrs = f'opacity="{alpha:g}"'
    shadow = f'opacity="{alpha * .75:g}"'
    out = []
    for side in (-1, 1):
        lower, upper = x + side * (24 + reach), x + side * (19 + reach)
        for (x1, y1, x2, y2) in ((lower + side * 9, y - 10, lower, y - 12),
                                 (upper + side * 5, y - 32, upper, y - 26)):
            out.extend([line(x1, y1, x2, y2, INK, 5, shadow), line(x1, y1, x2, y2, color, 2.3, attrs)])
        if heal:
            cross = x + side * (25 + reach)
            out.extend([line(cross - 4, y - 33, cross + 4, y - 33, color, 1.7, attrs),
                        line(cross, y - 37, cross, y - 29, color, 1.7, attrs)])
    return out


class SpriteSource:
    def __init__(self, renders):
        self.renders = renders
        self.capture = json.loads((renders / "review.json").read_text())
        manifest = json.loads((ROOT / CAST / "manifest.json").read_text())
        self.scale = manifest["display_scale"]
        self.clips = manifest["actors"]["wizard"]["clips"]

    @lru_cache
    def pixels(self, role, frame):
        if role in self.capture["takes"]:
            path = self.renders / f"{role}-{frame:02}.png"
            data = path.read_bytes()
            w = h = self.capture["capture_size"]
            assert magick("identify", "-format", "%wx%h", path).decode() == f"{w}x{h}"
            box = magick(path, "-alpha", "extract", "-threshold", "0", "-format", "%@", "info:")
            # Reject empty images or alpha touching the registered capture edge.
            aw, ah, ax, ay = map(int, re.findall(r"\d+", box.decode()))
            assert min(aw, ah) > 0 and min(ax, ay, w - ax - aw, h - ay - ah) >= 3, (path, box)
            x, y = self.capture["anchor"]
        else:
            clip = self.clips[role]
            sample = next(f for f in clip["frames"] if f["source_frame"] == frame)
            rx, ry, w, h = sample["rect"]
            x, y = clip["anchor"]
            data = magick(ROOT / CAST / "wizard.png", "-crop", f"{w}x{h}+{rx}+{ry}",
                          "+repage", "-strip", "PNG32:-")
        return base64.b64encode(data).decode(), x, y, w, h

    def paint(self, role, frame, cell):
        data, x, y, w, h = self.pixels(role, frame)
        fx, fy = foot(cell)
        return (f'<ellipse cx="{fx:g}" cy="{fy}" rx="22" ry="5" fill="#222824" opacity=".4"/>'
                f'<image x="{fx - x * self.scale:g}" y="{fy - y * self.scale:g}" '
                f'width="{w * self.scale:g}" height="{h * self.scale:g}" '
                f'xlink:href="data:image/png;base64,{data}"/>')


# Each panel is a board-sized sample, not a runtime screenshot. The only
# overlays drawn like the game are its existing heal/shift feedback glyphs.
LEFT, MID, RIGHT, UPPER_RIGHT, UPPER_MID = (0, 1), (1, 1), (2, 1), (2, 0), (1, 0)
ROWS = (
    ("Mending Blast", "ALLY  /  REUSE", "F17 · 667 ms",
     "Heal the actual wounded hero.", "No patient? Ordinary Blast.",
     "blast", LEFT,
     ((7, "Gather", (RIGHT,), ()), (17, "Restore HP", (RIGHT,), (RIGHT,)), (34, "Ready", (RIGHT,), ()))),
    ("Mending Blast", "SELF  /  NEW", "F17 · 667 ms",
     "Turn the palms inward.", "The caster is the recipient.",
     "mending_blast_self", MID,
     ((8, "Cup", (), ()), (17, "Restore own HP", (), (MID,)), (30, "Ready", (), ()))),
    ("Send-Off", "NEW NATIVE ACTION", "F13 · 500 ms",
     "Target moves one tile away.", "Caster stays at the same foot.",
     "send_off", LEFT,
     ((9, "Brace", (MID,), ()), (13, "Release", (MID,), (RIGHT,)), (18, "Target arrives", (RIGHT,), (RIGHT,)))),
    ("Ring of Salve", "REUSE RING OF SPARKS", "F12 · 458 ms",
     "Heal wounded neighbors only.", "No caster or enemy feedback.",
     "ring_sparks", MID,
     ((8, "Gather", (LEFT, RIGHT), ()), (12, "Restore both", (LEFT, RIGHT), (LEFT, RIGHT)),
      (26, "Ready", (LEFT, RIGHT), ()))),
    ("Clear Jump", "NEW NATIVE ACTION", "F8–17 · 292–667 ms",
     "Only the Wizard moves.", "No swap or opponent hit.",
     "clear_jump", LEFT,
     ((8, "Takeoff", (), ()), (12, "Airborne", (), ()), (17, "Land beside foe", (), ()))),
)


def panel(sprites, role, frame, wizard, recipients, marks):
    enemy = UPPER_RIGHT if role == "clear_jump" else UPPER_MID if role == "ring_sparks" else None
    landing = [(RIGHT, "landing")] if role in ("send_off", "clear_jump") else []
    out = board(landing)
    for cell, kind in landing:
        if wizard != cell and cell not in recipients:
            out.append(marker(cell, kind))
    if role == "send_off":
        if frame == 13:
            x, y = foot(MID)
            out += [line(x + 19, y - 8, x + 72, y - 8, SHIFT, 1.6, 'stroke-dasharray="3 4"'),
                    line(x + 72, y - 8, x + 66, y - 12, SHIFT, 1.6),
                    line(x + 72, y - 8, x + 66, y - 4, SHIFT, 1.6)]
        out += [marker(cell, "foe") for cell in recipients]
    else:
        out += [marker(cell, "ally") for cell in recipients]
    if enemy:
        out.append(marker(enemy, "foe"))
    if role == "clear_jump":
        start, y = foot(LEFT)
        stop, _ = foot(RIGHT)
        out.append(line(start + 21, y + 7, stop - 21, y + 7, "#8fa79a", 1.2, 'stroke-dasharray="2 4"'))
        wizard = (2 * max(0, min((frame - 8) / 9, 1)), 1)
    out.append(sprites.paint(role, frame, wizard))
    for cell in marks:
        progress = ((frame - 13) * 1000 / 24) / 280 if role == "send_off" else 0
        out.extend(feedback(cell, heal=role != "send_off", progress=progress))
    return "".join(out)


def compose(sprites):
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
           f'width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
           rect(0, 0, W, H, "#eae0c9"), rect(16, 15, W - 32, H - 30, "none", "#baa988", 3),
           text("BARNABY’S FIELD NOTES     /     CASTER     /     FITTED ACTIONS", 39, 38, 11, "#7d6546"),
           text("The Enthusiastic Caster", 38, 77, 36, "#372d25", serif=True),
           text("Board-scale motion study  ·  exact Wizard sprites  ·  no new spell effects", 40, 100, 13),
           line(38, 113, 1098, 113, "#b4a383", 1)]
    for row, (name, status, timing, note1, note2, role, wizard, beats) in enumerate(ROWS):
        top = 127 + row * 193
        out += [text(status, 40, top + 27, 10, "#7d6546"),
                text(name, 38, top + 54, 23, "#372d25", serif=True),
                text(timing, 40, top + 79, 12),
                text(note1, 40, top + 110, 11),
                text(note2, 40, top + 128, 11)]
        for col, (frame, moment, recipients, marks) in enumerate(beats):
            x = 206 + col * 302
            out += [f'<g transform="translate({x},{top})">',
                    panel(sprites, role, frame, wizard, recipients, marks),
                    '</g>', text(f"F{frame:02}  /  {moment}", x + 1, top + 176, 11)]
        out.append(line(38, top + 184, 1098, top + 184, "#bfb08f", 1))
    out += [text("Round token = ally; diamond = opponent. Paths and empty-cell stamps explain movement; mint crosses and pale strokes match existing board feedback.", 39, 1112, 11),
            text("Review only. Clear Jump’s shown travel window and fitted cue bindings are not implemented here.", 39, 1130, 11),
            "</svg>"]
    return "".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("renders", type=Path)
    parser.add_argument("sheet", type=Path, help="Output PNG path in the local evidence directory.")
    args = parser.parse_args()
    sprites = SpriteSource(args.renders)
    # Check every evidence sample, not just the subset on the sheet.
    for role, (_, frames, _, _) in sprites.capture["takes"].items():
        for frame in frames:
            sprites.pixels(role, frame)
    svg = args.sheet.with_suffix(".svg")
    svg.write_text(compose(sprites))
    magick("-background", "none", f"RSVG:{svg}", "-strip", args.sheet)
    assert magick("identify", "-format", "%wx%h", args.sheet).decode() == f"{W}x{H}"


if __name__ == "__main__":
    main()
