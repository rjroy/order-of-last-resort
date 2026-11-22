"""Register the Frontier Field painting and prove the 35-cell aperture."""

import argparse
import json
from pathlib import Path
import subprocess

import numpy as np

HERE = Path(__file__).resolve().parent
GAME = HERE.parents[1]
WIDTH, HEIGHT = 1280, 820
Y, X = np.mgrid[:HEIGHT, :WIDTH].astype(float) + 0.5
# Exact same camera, host and grid math as the approved Gate export.
SCALE = 633 / 468
HOST_LEFT, HOST_TOP = (WIDTH - 734 * SCALE) / 2, 81
LEFT, TOP = HOST_LEFT + 31 * SCALE, HOST_TOP + 34 * SCALE
CELL_W, CELL_H = 96 * SCALE, 80 * SCALE
RIGHT, BOTTOM = LEFT + 7 * CELL_W, TOP + 5 * CELL_H


def magick(*args, data=None):
    return subprocess.run(["magick", *map(str, args)], input=data,
                          check=True, capture_output=True).stdout


def decode(path, mode):
    w, h = map(int, magick("identify", "-format", "%w %h", path).split())
    flags = ["-alpha", "off"] if mode == "rgb" else []
    pixels = magick(path, "-colorspace", "sRGB", *flags, "-depth", "8", f"{mode}:-")
    return np.frombuffer(pixels, np.uint8).reshape(h, w, len(mode))


def encode(path, image):
    mode = {3: "rgb", 4: "rgba"}[image.shape[-1]]
    magick("-size", f"{WIDTH}x{HEIGHT}", "-depth", "8", f"{mode}:-",
           "-set", "colorspace", "sRGB", "-define", "png:exclude-chunks=date,time",
           f"PNG{8 * len(mode)}:{path}", data=image.tobytes())


def round8(pixels):
    return np.clip(np.rint(pixels), 0, 255).astype(np.uint8)


def sample(image, x, y):
    """Bilinear pixel-center sampling with the runtime's edge clamp."""
    h, w, _ = image.shape
    x, y = (x - 0.5).clip(0, w - 1), (y - 0.5).clip(0, h - 1)
    left, top = x.astype(int), y.astype(int)
    right, bottom = (left + 1).clip(max=w - 1), (top + 1).clip(max=h - 1)
    u, v = (x - left)[..., None], (y - top)[..., None]
    return ((1 - v) * ((1 - u) * image[top, left] + u * image[top, right])
            + v * ((1 - u) * image[bottom, left] + u * image[bottom, right]))


def smooth(t):
    t = t.clip(0, 1)
    return t * t * (3 - 2 * t)


def render(source, output):
    original = decode(source, "rgb")
    h, w, _ = original.shape
    painting = sample(original, X * w / WIDTH, Y * h / HEIGHT)

    # Feather only OUTWARD from the aperture; all pixels inside the exact
    # tactical footprint remain wholly unpainted by this layer.
    horizontal = np.maximum(smooth((LEFT - X) / 33), smooth((X - RIGHT) / 33))
    vertical = np.maximum(smooth((TOP - Y) / 27), smooth((Y - BOTTOM) / 32))
    alpha = round8((1 - (1 - horizontal) * (1 - vertical)) * 255)
    inside = (LEFT <= X) & (X < RIGHT) & (TOP <= Y) & (Y < BOTTOM)

    board = GAME / "assets/boards"
    reg = json.loads((board / "manifest.json").read_text())["boards"]["frontier_field"]["registration"]
    origin, column, row = map(np.asarray, (reg["a1_center_px"], reg["column_px"], reg["row_px"]))
    cols, rows = (X - LEFT) / CELL_W - .5, (Y - TOP) / CELL_H - .5
    ground_x = origin[0] + column[0] * cols + row[0] * rows
    ground_y = origin[1] + column[1] * cols + row[1] * rows
    ground = sample(decode(board / "frontier_field.png", "rgb"), ground_x, ground_y)

    rgba = np.dstack((round8(painting), alpha))
    encode(output / "frontier-field-surround-rgba.png", rgba)
    # Prove on the actual re-opened export, not just the pre-encode array.
    saved = decode(output / "frontier-field-surround-rgba.png", "rgba")
    assert np.array_equal(saved, rgba)
    a = saved[..., 3]
    assert np.all(a[inside] == 0)
    for cell_y in range(5):
        for cell_x in range(7):
            assert a[int(TOP + (cell_y + .5) * CELL_H), int(LEFT + (cell_x + .5) * CELL_W)] == 0
    assert np.any(a == 255) and np.any((0 < a) & (a < 255))
    amount = a[..., None] / 255
    composite = round8((1 - amount) * ground + amount * saved[..., :3])
    assert np.array_equal(composite[inside], round8(ground)[inside])
    encode(output / "registered-ground-composite.png", composite)
    print(f"Grid x {LEFT:.6f}–{RIGHT:.6f}, y {TOP:.6f}–{BOTTOM:.6f}")
    print(f"{inside.sum()} ground pixels unchanged; "
          f"{(a == 0).sum()} transparent, {((0 < a) & (a < 255)).sum()} feathered, "
          f"{(a == 255).sum()} opaque")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ["frontier-field-surround-rgba.png", "registered-ground-composite.png"]:
        if (args.output / name).exists():
            parser.error(f"refusing to overwrite: {args.output / name}")
    render(HERE / "frontier-field-native.png", args.output)
