"""Register a surround and blend two localized corners from the existing ground."""

import argparse
import importlib.util
import json
from pathlib import Path
import tempfile

import numpy as np

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "storybook_field_registration", HERE.parent / "storybook-field" / "register.py"
)
field = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(field)


def profile(axis, knots):
    points = np.asarray(knots, dtype=float)
    if points.ndim != 2 or points.shape[1] != 2 or np.any(np.diff(points[:, 0]) <= 0):
        raise ValueError("profile knots must have strictly increasing coordinates")
    return np.interp(axis, points[:, 0], points[:, 1])


def register(settings, source, ground_path, output):
    if settings["version"] != 1 or settings["page_px"] != [field.WIDTH, field.HEIGHT]:
        raise ValueError("unsupported settings version or page size")
    native = field.decode(source, "rgb")
    ground = field.decode(ground_path, "rgb")
    h, w, _ = native.shape
    gh, gw, _ = ground.shape
    if settings["native_px"] != [w, h] or settings["ground_px"] != [gw, gh]:
        raise ValueError("source image dimensions do not match settings")
    corners = settings["corners"]
    if len(corners) != 2 or [p["side"] for p in corners] != ["west", "east"]:
        raise ValueError("expected one west and one east corner")

    # Reuse the accepted ring recipe as the alpha and unchanged-RGB oracle.
    with tempfile.TemporaryDirectory(prefix="storybook-ring-") as temp:
        base_path = Path(temp) / "base.png"
        field.register_surround(source, base_path)
        registered = field.decode(base_path, "rgba")
    X, Y = field.X, field.Y
    original = field.sample(native, X * w / field.WIDTH, Y * h / field.HEIGHT)
    if not np.array_equal(field.round8(original), registered[..., :3]):
        raise ValueError("shared ring RGB does not match native page sampling")
    rgb = original.copy()
    left, top, right, bottom = settings["reference_live_aperture_ltrb_px"]
    x = np.interp(X, [0, field.LEFT, field.RIGHT, field.WIDTH], [0, left, right, field.WIDTH])
    y = np.interp(Y, [0, field.TOP, field.BOTTOM, field.HEIGHT], [0, top, bottom, field.HEIGHT])
    origin, column, row = np.asarray(settings["ground_registration_px"])
    regions = []
    for patch in corners:
        weight = profile(x, patch["x_weight"]) * profile(y, patch["y_weight"])
        side = X < field.LEFT if patch["side"] == "west" else X >= field.RIGHT
        weight = np.where(side, weight, 0)
        if np.any((weight < 0) | (weight > 1)):
            raise ValueError("corner blend weights must be between zero and one")
        regions.append(weight != 0)
        sx, sy = profile(x, patch["ground_x_px"]), profile(y, patch["ground_y_px"])
        col, lin = 7 * (sx - left) / (right - left) - 0.5, 5 * (sy - top) / (bottom - top) - 0.5
        gx = origin[0] + column[0] * col + row[0] * lin
        gy = origin[1] + column[1] * col + row[1] * lin
        donor = field.sample(ground, gx, gy)
        rgb = rgb + weight[..., None] * (donor - rgb)

    rgb = field.round8(rgb)
    changed = np.any(rgb != registered[..., :3], axis=-1)
    if np.any(regions[0] & regions[1]) or np.any(changed & ~(regions[0] | regions[1])):
        raise ValueError("RGB changes must remain within the two separate corner regions")
    if any(not np.any(changed & region & (registered[..., 3] > 0)) for region in regions):
        raise ValueError("both corner regions must make a visible change")
    rgba = np.dstack((rgb, registered[..., 3]))
    field.encode(output, rgba)
    saved = field.decode(output, "rgba")
    if not np.array_equal(saved, rgba) or not np.array_equal(saved[..., 3], registered[..., 3]):
        raise ValueError("reopened output differs or no longer has the shared ring alpha")
    print(f"{np.count_nonzero(changed)} RGB pixels changed only in two corners; "
          "shared ring alpha is identical")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("settings", type=Path)
    parser.add_argument("native", type=Path)
    parser.add_argument("ground", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error(f"refusing to overwrite: {args.output}")
    for path in [args.settings, args.native, args.ground]:
        if not path.is_file():
            parser.error(f"missing input: {path}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    register(json.loads(args.settings.read_text()), args.native, args.ground, args.output)


if __name__ == "__main__":
    main()
