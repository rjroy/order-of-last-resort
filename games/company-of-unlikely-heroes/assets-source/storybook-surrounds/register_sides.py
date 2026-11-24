"""Register a side-only painting for the storybook scenery shader."""

import argparse
import importlib.util
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "storybook_field_registration", HERE.parent / "storybook-field" / "register.py"
)
field = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(field)


def interpolate_pairs(y, pairs):
    if not pairs:
        return np.zeros_like(y)
    points = np.asarray(pairs, dtype=float)
    if points.ndim != 2 or points.shape[1] != 2 or np.any(np.diff(points[:, 0]) <= 0):
        raise ValueError("offset knots must have strictly increasing y coordinates")
    return np.interp(y, points[:, 0], points[:, 1])


def register(source, output, settings):
    if settings["version"] != 1 or settings["reference_page_px"] != [field.WIDTH, field.HEIGHT]:
        raise ValueError("unsupported settings version or page size")
    width, height = field.WIDTH, field.HEIGHT
    live = settings["reference_live_aperture_ltrb_px"]
    authored = settings["authored_aperture_ltrb_px"]
    if not np.allclose(authored, [field.LEFT, field.TOP, field.RIGHT, field.BOTTOM], atol=1e-5):
        raise ValueError("authored aperture does not match the Field registration and scenery shader")
    x_live_knots = [0, live[0], live[2], width]
    y_live_knots = [0, live[1], live[3], height]
    x_art_knots = [0, authored[0], authored[2], width]
    y_art_knots = [0, authored[1], authored[3], height]
    for knots in [x_live_knots, y_live_knots, x_art_knots, y_art_knots]:
        if np.any(np.diff(knots) <= 0):
            raise ValueError("aperture knots must be strictly increasing")

    x = np.interp(field.X, x_art_knots, x_live_knots)
    y = np.interp(field.Y, y_art_knots, y_live_knots)
    original = field.decode(source, "rgb")
    if [original.shape[1], original.shape[0]] != settings["native_size_px"]:
        raise ValueError("native dimensions do not match settings")
    knots = settings["destination_y_knots_px"]
    if len(knots) < 2 or np.any(np.diff(knots) <= 0):
        raise ValueError("destination y knots must be strictly increasing")
    anchor = settings["outward_x_anchor_distance_px"]
    if anchor <= 0:
        raise ValueError("outward anchor distance must be positive")

    def sample(x_source, y_source):
        sx = np.interp(x_source, x_live_knots, x_art_knots) * original.shape[1] / width
        sy = np.interp(y_source, y_live_knots, y_art_knots) * original.shape[0] / height
        return field.sample(original, sx, sy)

    sides = []
    for name in ("west", "east"):
        side = settings[name]
        if len(side["source_y_px"]) != len(knots):
            raise ValueError(f"{name}: source y coordinates must match destination knots")
        sy = np.interp(y, knots, side["source_y_px"])
        sy += interpolate_pairs(y, side.get("source_y_offset_px_by_y"))
        offset = interpolate_pairs(y, side.get("outward_x_px_by_y"))
        sx = x - offset * x / anchor if name == "west" else x + offset * (width - x) / anchor
        art = sample(sx, sy)
        if "dry_patch" in side:
            patch = side["dry_patch"]
            start, end = patch["blend_y_px"]
            if end <= start:
                raise ValueError(f"{name}: dry patch blend must have positive height")
            weight = field.smooth((y - start) / (end - start))[..., None]
            art += weight * (sample(x + patch["source_x_offset_px"], y) - art)
        sides.append(art)

    art = np.where((x < width / 2)[..., None], sides[0], sides[1])
    west, east = settings["side_alpha"]["west"], settings["side_alpha"]["east"]
    if not west["full_x"] < west["clear_x"] <= live[0] < live[2] <= east["clear_x"] < east["full_x"]:
        raise ValueError("side alpha must feather outward from the live aperture")
    alpha = np.maximum(
        field.smooth((west["clear_x"] - x) / (west["clear_x"] - west["full_x"])),
        field.smooth((x - east["clear_x"]) / (east["full_x"] - east["clear_x"])),
    )
    rgba = np.dstack((field.round8(art * settings["rgb_gain"]), field.round8(alpha * 255)))
    field.encode(output, rgba)
    saved = field.decode(output, "rgba")
    if not np.array_equal(saved, rgba):
        raise ValueError("reopened PNG differs from registered pixels")
    center = (x >= west["clear_x"]) & (x <= east["clear_x"])
    if np.any(saved[..., 3][center] != 0) or not np.any(saved[..., 3] == 255):
        raise ValueError("export does not preserve the entire central strip and opaque wings")
    print(f"{center.sum()} full-height center pixels transparent; "
          f"{np.count_nonzero((saved[..., 3] > 0) & (saved[..., 3] < 255))} feathered")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("settings", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if not args.settings.is_file() or not args.source.is_file():
        parser.error("settings and native source must exist")
    if args.output.exists():
        parser.error(f"refusing to overwrite: {args.output}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    common = json.loads((HERE / "side_registration_common.json").read_text())
    board = json.loads(args.settings.read_text())
    if common.keys() & board.keys():
        parser.error("board settings must not override shared registration settings")
    register(args.source, args.output, common | board)


if __name__ == "__main__":
    main()
