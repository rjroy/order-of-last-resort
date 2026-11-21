# Ferryman crossing layout guide

`layout-guide.png` is a **1536 × 1024** registration reference for the illustrated ground, not the illustration or a runtime asset. It is derived from `boards.bridge` in `games/company-of-unlikely-heroes/content/common.json` and `encounters.company_crossing` in `first_outing.json` beside it.

Run from the repository root with Python 3 and `rsvg-convert` (librsvg 2.63.3 used here):

```sh
python3 .lore/work/games/company-of-unlikely-heroes/art/pilots/ferryman-crossing/authoring/make_layout_guide.py
```

The script writes `.lore/local/company-of-unlikely-heroes/crossing-pilot/layout-guide.png` and prints the authored anchors. This PNG is regenerable, not a required checkout input. Use `--output PATH` to generate a separate copy.

## Fixed registration

Pixel origin is top left; coordinates increase right and down. With zero-based column `c` and row `r`, the **cell center** is

```text
P(c, r) = (272, 176) + c × (184, 18) + r × (−28, 146)
```

Moving east goes right and slightly down; moving toward the foreground (+row) goes down and slightly left. The basis is constant across the frame: high-angle, shallow-yaw orthographic three-quarter, with no vanishing point or horizon. A cell's ground corners are `P(c ± 0.5, r ± 0.5)`. The outer board corners, clockwise from the upper left, are `(194, 94)`, `(1482, 220)`, `(1342, 950)`, `(54, 824)`. Those boundaries are not drawn.

| Authored anchor | Cell | Pixel center |
|---|---|---|
| Party slot 1 | B2 | (428, 340) |
| Party slot 2 | A3 | (216, 468) |
| Party slot 3 | A2 | (244, 322) |
| Ferryman | B3 | (400, 486) |
| Movable crate | C3 | (584, 504) |
| Span | D3 | (768, 522) |
| Far-bank approach | E3 | (952, 540) |
| Harpooner | F2 | (1164, 412) |
| `safe_bank` | G3 | (1320, 576) |
| `near_landing` | C1 | (640, 212) |

The near bank is A–C, the far bank E–G. The single river channel runs through D from D1 `(824, 230)` to D5 `(712, 814)` and continues off both frame edges. Keep the D3 span separate. Its centerline crosses toward the far bank along `(184, 18)`, joining the near shore at **(676, 513)** and the far shore at **(860, 531)**. The four D3 ground corners, clockwise from the upper left, are `(690, 440)`, `(874, 458)`, `(846, 604)`, `(662, 586)`. The shores are straight across this join, with small natural bends outside it.

## What the guide shows

The two road approaches line up at row 3, stopping at their respective shores. The near approach puts uninterrupted terrain under the crate, ferryman and party; the far bank also leaves clear ground under the harpooner and at the exit. Keep these surfaces continuous in the illustration. Use quiet, muted scenic margins to give the banks depth without crowding the playable area or introducing a horizon. There are no objects, tile marks, cast shadows or bridge pixels in the guide. D3 stays exposed water even where a span will sit.
