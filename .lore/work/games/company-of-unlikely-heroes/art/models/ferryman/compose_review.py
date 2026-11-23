"""Compose saved renders with ImageMagick and FFmpeg; no runtime assets."""

import sys, subprocess
from pathlib import Path

out = Path(sys.argv[1])
paper = "#ebdfc8"
ink = "#332e28"
labels = [
    ("neutral", "Neutral bind"),
    ("ready", "Ready"),
    ("travel", "Test the footing"),
    ("arrival", "Safe bank"),
    ("flinch", "Flinch"),
    ("down", "Fold to the ground"),
    ("side", "Profile"),
    ("back", "Back"),
]


def font(query):
    return subprocess.check_output(["fc-match", "--format=%{file}", query], text=True)


serif = font("serif:style=Bold")
sans = font("sans-serif")


def label(x, y, text, size, bold=False):
    return [
        "-fill",
        ink,
        "-font",
        serif if bold else sans,
        "-pointsize",
        str(size),
        "-annotate",
        f"+{x}+{y}",
        text,
    ]


cmd = (
    ["magick", "-size", "1152x768", "xc:" + paper]
    + label(25, 47, "The Ferryman", 34, True)
    + label(26, 69, "COMPANY RESCUE   /   EDITABLE MODEL STUDY", 13)
)
for i, (name, title) in enumerate(labels):
    x = i % 4 * 288
    y = i // 4 * 294 + 78
    path = str(out / "poses" / f"{name}.png")
    cmd += [
        "(",
        path,
        "-resize",
        "274x274",
        ")",
        "-geometry",
        f"+{x + 7}+{y}",
        "-composite",
    ] + label(x + 18, y + 279, title, 17, True)
    xx = 240 + i * 110
    cmd += [
        "(",
        path,
        "-resize",
        "65x65",
        "-crop",
        "65x54+0+5",
        "+repage",
        ")",
        "-geometry",
        f"+{xx}+682",
        "-composite",
    ] + label(xx + 2, 748, name.title(), 12)
cmd += (
    label(25, 707, "TACTICAL SCALE", 15, True)
    + label(25, 733, "65 × 54 px per sample", 13)
    + [str(out / "ferryman-pose-sheet.png")]
)
subprocess.run(cmd, check=True)
frames = sorted((out / "motion").glob("m[0-9][0-9][0-9].png"))
assert len(frames) == 43
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
        "384x424",
        "-r",
        "8",
        "-i",
        "-",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-crf",
        "18",
        "-movflags",
        "+faststart",
        str(out / "ferryman-motion.mp4"),
    ],
    stdin=subprocess.PIPE,
)
for i, frame in enumerate(frames):
    pix = subprocess.check_output(
        [
            "magick",
            "-size",
            "384x424",
            "xc:" + paper,
            "(",
            str(frame),
            "-resize",
            "384x384",
            ")",
            "-geometry",
            "+0+0",
            "-composite",
        ]
        + label(
            20,
            407,
            "READY" if i < 11 else "CAUTIOUS STEP" if i < 24 else "SAFE BANK",
            16,
            True,
        )
        + ["-depth", "8", "rgb:-"]
    )
    p.stdin.write(pix)
p.stdin.close()
assert p.wait() == 0
