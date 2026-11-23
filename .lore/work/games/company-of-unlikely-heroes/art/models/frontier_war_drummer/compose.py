"""Compose transparent Blender inspection frames without changing the model."""

import json, os, subprocess, sys
from pathlib import Path

out = Path(sys.argv[-1]).resolve()
data = json.loads((out / "validation.json").read_text())
actor = data["actor"]
title = actor.replace("frontier_", "").replace("_", " ").title()
poses = data["poses"]
motion = data["motion"]
paper, ink, font = "#eddfc9", "#3e302d", "Liberation-Sans"
env = {**os.environ, "MAGICK_THREAD_LIMIT": "1", "MAGICK_TEMPORARY_PATH": str(out)}


def run(args):
    subprocess.run(["magick", *map(str, args)], check=True, cwd=out, env=env)


def cell(file, size, label=None):
    args = [
        "(",
        file,
        "-resize",
        f"{size}x{size}",
        "-background",
        paper,
        "-alpha",
        "remove",
        "-alpha",
        "off",
    ]
    if label:
        args += [
            "-gravity",
            "south",
            "-font",
            font,
            "-pointsize",
            "15",
            "-fill",
            ink,
            "-annotate",
            "+0+2",
            label,
        ]
    return args + [")"]


ordinary = {"Neutral", "Ready", "Hit", "Defeat", "Move", "Reserve arrival"}
sig = [name for name in poses if name not in ordinary]
items = [("Neutral", poses["Neutral"]), ("Ready", poses["Ready"])]
for n in sig:
    if n == "War drum pulse":
        items.append(("Upstroke", "War_drum_pulse_09.png"))

    items.append((n, poses[n]))
items.extend((n, f) for n, f in poses.items() if n in ordinary - {"Neutral", "Ready"})

args = [a for n, f in items for a in cell(f, 240, n)]
run(
    [
        "montage",
        *args,
        "-tile",
        "4x",
        "-geometry",
        "+1+1",
        "-background",
        paper,
        "pose-sheet.png",
    ]
)
run(
    [
        "pose-sheet.png",
        "-gravity",
        "north",
        "-background",
        "#3f3540",
        "-splice",
        "0x36",
        "-fill",
        "#f6ead3",
        "-font",
        font,
        "-pointsize",
        "19",
        "-annotate",
        "+0+5",
        title + "  /  pose study",
        "pose-sheet.png",
    ]
)
# Shipped cast scale: (256 / 2.44) source px/metre, displayed at 0.375.
mini = round(data["camera_width"] * 256 / 2.44 * 0.375)
run([*[a for n, f in items for a in cell(f, mini)], "+append", "tactical.png"])
args = []
keys = []
for name in sig:
    frames = motion[name]
    for i, (fr, file) in enumerate(frames):
        wait = round((frames[i + 1][0] - fr) * 100 / 24) if i + 1 < len(frames) else 27
        args += ["(", "-delay", str(wait), *cell(file, 224, name)[1:]]
        if i in {0, len(frames) // 3, len(frames) // 2, len(frames) - 2}:
            keys += cell(file, 154)
run([*args, "-loop", "0", "motion.gif"])
run(
    [
        "montage",
        *keys,
        "-tile",
        "4x",
        "-geometry",
        "+1+1",
        "-background",
        paper,
        "motion-strip.png",
    ]
)
