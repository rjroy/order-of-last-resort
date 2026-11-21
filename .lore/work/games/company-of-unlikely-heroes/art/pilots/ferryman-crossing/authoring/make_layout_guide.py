#!/usr/bin/env python3
"""Draw a terrain-registration guide, not a mission illustration."""

import argparse
import json
from pathlib import Path
import subprocess


SIZE = (1536, 1024)
ORIGIN = (272, 176)
COLUMN = (184, 18)
ROW = (-28, 146)
BANK_OVERSCAN = 4.6
GAME = "company-of-unlikely-heroes"
CONTENT = Path("games") / GAME / "content"
OUTPUT = Path(f".lore/local/{GAME}/crossing-pilot/layout-guide.png")


def project(column, row):
    return tuple(
        origin + column * dc + row * dr
        for origin, dc, dr in zip(ORIGIN, COLUMN, ROW)
    )


def svg_path(fill, steps, *, stroke="none", width=1, opacity=1):
    path = " ".join(
        f"{command} " + " ".join(
            f"{x:.2f},{y:.2f}" for x, y in (project(*pair) for pair in points)
        )
        for command, *points in steps
    )
    return (
        f'<path d="{path}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" '
        f'opacity="{opacity}" stroke-linecap="round"/>'
    )


def bank_edge(column, bridge_row, near):
    """Keep the bridge landings flush; curve the unoccupied shore gently."""
    direction = 1 if near else -1
    return [
        ("M", (column, bridge_row - BANK_OVERSCAN)),
        ("C", (column, bridge_row - 3.2), (column + .12 * direction, bridge_row - 2.8),
         (column + .09 * direction, bridge_row - 2.2)),
        ("C", (column + .05 * direction, bridge_row - 1.7),
         (column + .18 * direction, bridge_row - 1.35),
         (column + .09 * direction, bridge_row - .9)),
        ("Q", (column, bridge_row - .65), (column, bridge_row - .5)),
        ("L", (column, bridge_row + .5)),
        ("Q", (column, bridge_row + .66), (column + .04 * direction, bridge_row + .95)),
        ("C", (column + .08 * direction, bridge_row + 1.42),
         (column + .15 * direction, bridge_row + 1.65),
         (column + .10 * direction, bridge_row + 2.2)),
        ("C", (column + .04 * direction, bridge_row + 2.75),
         (column + .06 * direction, bridge_row + 3.1),
         (column, bridge_row + BANK_OVERSCAN)),
    ]


def bank_shape(edge, bridge_row, outside):
    return [("M", (outside, bridge_row - BANK_OVERSCAN)), ("L", *edge[0][1:]), *edge[1:],
            ("L", (outside, bridge_row + BANK_OVERSCAN)), ("Z",)]


def road_shape(shore, bridge_row, near):
    """Two broad road approaches that never paint over the river."""
    direction = -1 if near else 1

    def at(x, y):
        return shore + direction * x, bridge_row + y

    return [
        ("M", at(0, -.39)),
        ("C", at(.85, -.45), at(2.1, -.72), at(4.5, -.54)),
        ("L", at(4.5, .63)),
        ("C", at(2.12, .87), at(.75, .72), at(0, .39)),
        ("Z",),
    ]


def draw_guide(bridge, shore_cells):
    bridge_column, bridge_row = bridge
    left, right = bridge_column - .5, bridge_column + .5
    near_edge = bank_edge(left, bridge_row, near=True)
    far_edge = bank_edge(right, bridge_row, near=False)
    near_bank = bank_shape(near_edge, bridge_row,
                           min(c for c, _ in shore_cells) - 2)
    far_bank = bank_shape(far_edge, bridge_row,
                          max(c for c, _ in shore_cells) + 2)
    w, h = SIZE
    layers = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}">',
        '<defs>'
        '<linearGradient id="water" x2="0" y2="1">'
        '<stop stop-color="#65918f"/><stop offset="1" stop-color="#497b7e"/>'
        '</linearGradient>'
        '<linearGradient id="near" x2="0" y2="1">'
        '<stop stop-color="#87906e"/><stop offset=".4" stop-color="#aca98a"/>'
        '<stop offset=".72" stop-color="#a3a384"/><stop offset="1" stop-color="#788469"/>'
        '</linearGradient>'
        '<linearGradient id="far" x2="0" y2="1">'
        '<stop stop-color="#82906f"/><stop offset=".45" stop-color="#a4aa89"/>'
        '<stop offset=".75" stop-color="#a1a889"/><stop offset="1" stop-color="#748269"/>'
        '</linearGradient>'
        f'<clipPath id="near-bank">{svg_path("white", near_bank)}</clipPath>'
        f'<clipPath id="far-bank">{svg_path("white", far_bank)}</clipPath>'
        '</defs>',
        f'<rect width="{w}" height="{h}" fill="url(#water)"/>',
    ]
    for lane, tint, weight in [(-.28, "#95adaa", 13), (.25, "#8fa7a2", 19)]:
        c, r = bridge_column + lane, bridge_row
        layers.append(svg_path("none", [
            ("M", (c + .06, r - 3.8)),
            ("C", (c - .12, r - 1.9), (c + .14, r - .66), (c, r + .65)),
            ("S", (c + .13, r + 2.38), (c - .04, r + 3.8)),
        ], stroke=tint, width=weight, opacity=.25))
    for name, shape, edge, shore, near in (
        ("near", near_bank, near_edge, left, True),
        ("far", far_bank, far_edge, right, False),
    ):
        layers.extend([
            svg_path(f"url(#{name})", shape),
            f'<g clip-path="url(#{name}-bank)">',
            svg_path("none", edge, stroke="#c4ba93", width=31, opacity=.56),
            svg_path("#beb19a", road_shape(shore, bridge_row, near), opacity=.78),
            "</g>",
        ])
    return "\n".join([*layers, "</svg>"]).encode()


def read_layout(root):
    content = root / CONTENT
    common = json.loads((content / "common.json").read_text(encoding="utf-8"))
    outing = json.loads((content / "first_outing.json").read_text(encoding="utf-8"))
    encounter = outing["encounters"]["company_crossing"]
    if encounter["board"] != "bridge":
        raise ValueError("company_crossing no longer uses boards.bridge")
    board = common["boards"][encounter["board"]]
    shore = {tuple(at) for at in board["shore_cells"]}
    tiles = {tuple(tile["at"]): tile["type"] for tile in board["tiles"]}
    spans = [cell for cell, kind in tiles.items() if kind == "bridge"]
    if len(spans) != 1:
        raise ValueError("This single-span guide needs exactly one bridge cell")
    bridge = spans[0]
    c, _ = bridge
    channel = {(c, r) for r in range(board["height"])}
    expected_shore = {
        (column, row)
        for column in range(board["width"]) for row in range(board["height"])
    } - channel
    if (board["width"], board["height"]) != (7, 5) or shore != expected_shore:
        raise ValueError("Shore geometry has changed; update the pilot framing")
    if set(tiles) != channel or any(tiles[cell] != "gap" for cell in channel - {bridge}):
        raise ValueError("Expected one continuous channel except for the separable span")
    positions = {
        **{f"party_slot_{i}": tuple(at) for i, at in enumerate(encounter["party_slots"], 1)},
        **{p["id"]: tuple(p["at"]) for p in encounter["placements"]},
        **{name: tuple(at) for name, at in board["locations"].items()},
    }
    if not set(positions.values()) <= shore:
        raise ValueError("All actors, the crate and the location anchors must sit on painted shore")
    return bridge, shore, positions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Override the default local PNG path")
    args = parser.parse_args()
    root = next(path for path in Path(__file__).resolve().parents if (path / CONTENT).is_dir())
    bridge, shore, positions = read_layout(root)
    output = args.output or root / OUTPUT
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "--format=png", "--output", output],
                   input=draw_guide(bridge, shore), check=True)
    print(f"{output}: {SIZE[0]} × {SIZE[1]}")
    for name, cell in {"span": bridge, **positions}.items():
        print(f"{name}: {chr(65 + cell[0])}{cell[1] + 1} {project(*cell)}")


if __name__ == "__main__":
    main()
