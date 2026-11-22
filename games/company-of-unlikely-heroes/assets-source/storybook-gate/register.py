"""Regenerate the accepted 1280x820 Gate surround from its native painting."""

import argparse
from pathlib import Path
import subprocess

import numpy as np

HERE = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1280, 820
Y, X = np.mgrid[:HEIGHT, :WIDTH].astype(float) + 0.5


def magick(*args, data=None):
    return subprocess.run(["magick", *map(str, args)], input=data, check=True, capture_output=True).stdout


def decode(path):
    width, height = map(int, magick("identify", "-format", "%w %h", path).split())
    rgb = magick(path, "-colorspace", "sRGB", "-alpha", "off", "-depth", "8", "rgb:-")
    return np.frombuffer(rgb, np.uint8).reshape(height, width, 3)


def encode(path, image):
    mode = {3: "rgb", 4: "rgba"}[image.shape[-1]]
    magick("-size", f"{WIDTH}x{HEIGHT}", "-depth", "8", f"{mode}:-", "-set", "colorspace",
           "sRGB", "-define", "png:exclude-chunks=date,time",
           f"PNG{32 if mode == 'rgba' else 24}:{path}", data=image.tobytes())


def sample(image, x, y):
    """Bilinear pixel-center sampling, with edge clamp for the approved ground."""
    h, w, _ = image.shape
    x = (x - 0.5).clip(0, w - 1)
    y = (y - 0.5).clip(0, h - 1)
    left, top = x.astype(int), y.astype(int)
    right, bottom = (left + 1).clip(max=w - 1), (top + 1).clip(max=h - 1)
    u, v = (x - left)[..., None], (y - top)[..., None]
    return (1 - v) * ((1 - u) * image[top, left] + u * image[top, right]) + v * (
        (1 - u) * image[bottom, left] + u * image[bottom, right])


def smooth(value, width):
    t = (value / width).clip(0, 1)
    return t * t * (3 - 2 * t)


def monotone_map(values, output_positions, source_positions):
    """A monotone cubic map so landmark adjustments cannot crease the ground."""
    knots = np.asarray(output_positions, dtype=float)
    targets = np.asarray(source_positions, dtype=float)
    widths = np.diff(knots)
    slopes = np.diff(targets) / widths
    left_w = 2 * widths[1:] + widths[:-1]
    right_w = widths[1:] + 2 * widths[:-1]
    interior = (left_w + right_w) / (left_w / slopes[:-1] + right_w / slopes[1:])
    tangent = np.r_[slopes[0], interior, slopes[-1]]
    i = (np.searchsorted(knots, values) - 1).clip(0, len(widths) - 1)
    t = (values - knots[i]) / widths[i]
    p = t * t * (3 - 2 * t)
    return ((1 - p) * targets[i] + p * targets[i + 1] +
            widths[i] * t * (1 - t) * ((1 - t) * tangent[i] - t * tangent[i + 1]))


def round8(image):
    return np.clip(np.rint(image), 0, 255).astype(np.uint8)


def layer_mask():
    # Edge coordinates are those recovered from the viewport layout and BridgeArt.
    # Outward feather, never across the walkable footprint.
    ax = np.maximum(smooth(185.538462 - X, 30), smooth(X - 1094.461538, 30))
    ay = np.maximum(smooth(126.987179 - Y, 23), smooth(Y - 668.012821, 28))
    surround = 1 - (1 - ax) * (1 - ay)
    # The wall joins the distant parapet but lies inside the D column otherwise.
    # The existing ground and opening are untouched from y343 through y452.
    wall_x = np.minimum(smooth(X - 575.076923, 7), smooth(704.923077 - X, 7))
    upper_wall = smooth(343 - Y, 7)
    lower_wall = smooth(Y - 452, 7) * (1 - smooth(Y - 678, 13))
    wall = wall_x * np.maximum(upper_wall, lower_wall)
    return np.maximum(surround, wall)


def walkable():
    on_board = (X > 185.538462) & (X < 1094.461538) & (Y > 126.987179) & (Y < 668.012821)
    in_d = (X > 575.076923) & (X < 704.923077)
    d3 = (Y > 343.397436) & (Y < 451.602564)
    return on_board & (~in_d | d3)


def render(source, output):
    original = decode(source)
    assert original.shape == (1003, 1568, 3), f"These anchors expect the inspected source, got {original.shape}"
    # Warp measured landmarks rather than skewing the stable board or moving cells.
    x = monotone_map(X, [0, 185.5, 640, 1094.5, 1280], [0, 242, 789, 1358, 1568])
    y = monotone_map(Y, [0, 126, 334, 458, 650, 820], [0, 210, 454, 549, 839, 1003])
    painted = sample(original, x, y)
    alpha = layer_mask()
    a8 = round8(alpha * 255)
    assert np.count_nonzero(a8[walkable()]) == 0
    assert a8[42, 640] == 255 and a8[398, 640] == 0 and a8[485, 640] == 255
    rgba = np.dstack((round8(painted), a8))
    encode(output, rgba)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New PNG output path")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output already exists")
    render(HERE / "gate-scenery-native.png", args.output)
