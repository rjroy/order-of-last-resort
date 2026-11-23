"""Compose Bruiser proof and real-time sampled motion from read-only Blender renders."""

import subprocess, sys
from pathlib import Path

out = Path(sys.argv[1])
paper = "#e7dcc4"
ink = "#382f28"
red = "#824530"
line = "#b6a88e"
font = lambda query: subprocess.check_output(
    ["fc-match", "-f", "%{file}", query], text=True
)
serif = font("serif:style=Bold")
sans = font("sans-serif")


def label(x, y, tx, sz, face=sans, col=ink):
    return [
        "-font",
        face,
        "-pointsize",
        str(sz),
        "-fill",
        col,
        "-annotate",
        f"+{x}+{y}",
        tx,
    ]


def tile(path, size, x, y):
    return [
        "(",
        str(path),
        "-resize",
        f"{size}x{size}",
        ")",
        "-geometry",
        f"+{x}+{y}",
        "-composite",
    ]


items = [
    ("neutral", "Neutral T"),
    ("ready", "Ready"),
    ("trudge", "Trudge"),
    ("load", "Windup"),
    ("impact", "Weight lands"),
    ("follow", "Follow-through"),
    ("hit", "Hit"),
    ("down", "Down"),
    ("side", "Profile"),
    ("back", "Back"),
]
w = 1170
cmd = (
    ["magick", "-size", f"{w}x711", "xc:" + paper]
    + label(24, 43, "The Bruiser", 35, serif)
    + label(24, 67, "RIVER AND VILLAGE    /    MODEL AND MOVEMENT STUDY", 13, sans, red)
)
for i, (stem, caption) in enumerate(items):
    x = (i % 5) * 234
    y = 76 + (i // 5) * 255
    src = out / "poses" / f"{stem}.png"
    cmd += tile(src, 234, x, y) + label(x + 16, y + 237, caption, 15, serif)
cmd += (
    ["-stroke", line, "-strokewidth", "1", "-draw", "line 24,596 1146,596", "+stroke"]
    + label(24, 625, "TACTICAL SIZE", 13, serif)
    + label(24, 649, "26 px / metre", 12)
)
for i, (stem, caption) in enumerate(items):
    cmd += tile(out / "poses" / f"{stem}.png", 65, 183 + i * 96, 603) + label(
        183 + i * 96, 684, caption, 11
    )
subprocess.run(cmd + [str(out / "pose-sheet.png")], check=True)
frames = sorted((out / "motion").glob("m[0-9][0-9][0-9].png"))
assert len(frames) == 69
p = subprocess.Popen(
    [
        "ffmpeg",
        "-v",
        "error",
        "-y",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        "540x420",
        "-r",
        "12",
        "-i",
        "-",
        "-c:v",
        "libx264",
        "-crf",
        "17",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        str(out / "motion-preview.mp4"),
    ],
    stdin=subprocess.PIPE,
)
for i, f in enumerate(frames):
    cap = next(
        tx
        for limit, tx in [
            (9, "Ready"),
            (24, "Trudge"),
            (45, "Heavy strike"),
            (54, "Hit"),
            (69, "Down"),
        ]
        if i < limit
    )
    cmd = (
        ["magick", "-size", "540x420", "xc:" + paper]
        + tile(f, 370, 0, 10)
        + tile(f, 65, 415, 157)
        + label(377, 145, "TACTICAL SIZE", 13, serif)
        + label(28, 397, cap, 24, serif)
        + label(372, 395, "THE BRUISER", 13, sans, red)
    )
    p.stdin.write(subprocess.check_output(cmd + ["-depth", "8", "rgb:-"]))
p.stdin.close()
assert p.wait() == 0
