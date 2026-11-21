# Ferryman’s Crossing | Art study

An isolated Godot 2D test of the illustrated crossing and Blender-rendered sprites. It uses the real 7 × 5 board, not the rescue mission or its rules. The Knight is at B2. The Healer stands one tile from her authored start, at A2, so she can reach toward him on screen. The crate starts at its authored C3 and slides one tile south to C4 or back.

## Run and inspect

From the repository root, with Godot 4.7.2:

```sh
pilot=.lore/work/games/company-of-unlikely-heroes/art/pilots/ferryman-crossing
godot --path "$pilot"
godot --headless --path "$pilot" --script res://smoke.gd
```

The project reads local source PNGs directly. No editor import, `.godot` cache, or `.lore/local` input is required.

- Click a tile to pick it. Once the board has focus, arrow keys pick neighboring valid tiles. Unbridged water does not accept clicks.
- **Replay guard** (`G`) and **Replay heal** (`H`) play the corresponding Blender strips once and select their actors. Watch the Knight's boots and shield, then the Healer's reach toward the Knight.
- **Move crate** (`M`) slides it one tile in its own lane. The contact shadow travels with it.
- **Bridge intact / absent** (`B`) switches the deck and stone sills together. D3 cannot be selected while the span is absent. The sills overlap C3 and E3 but do not affect those cells.
- **Threat** (`T`), **Selection** (`S`) and **Shadows** (`V`) independently hide or show those layers. A hidden selection mark does not erase the picked tile.
- **Play-size check** (`P`) shows the same layers and hit testing at **65 × 52 px per logical tile** in the 1280 × 820 reference frame. It scales the whole plate and actors together.

The standard view fits the full illustration at about 109 × 87 px per tile in that frame. The sprite frames display at roughly 95 px square in standard view and 57 px square in the play-size check. The poses themselves do not fill the whole frame rectangle.

## Capture and verify

From the repository root, with a graphical display and FFmpeg:

```sh
bash "$pilot/capture.sh"
```

The script saves a 12-second Godot capture and 1280 × 820 stills to `.lore/local/company-of-unlikely-heroes/crossing-pilot/` by default. Pass an output directory to override it. `registration-before.png` and `registration-after.png` show the same 35 projected cell centers over the source and registered display respectively. The stills also show the intact deck, guard, heal, absent deck, and play-size check.

The guide fixes the projection and the board fixes passability. In the supplied image the wet fringe occupies C4 and C5, while the painted edge of the west landing falls short of the D3 boundary. The display shader resamples the original plate horizontally using observed bank-edge landmarks, allowing the two landings to meet the removable deck. It does not alter the source PNG, cell projection, or hit testing. The bridge paint and shadows are transparent Godot layers, not pixels baked into the plate. Entities stack by screen-space foot depth after their independent ground shadows and the tactical marks.

The smoke checks compare the intact and absent selectable cells with the game's authored board, verify the actual sprite strips and frame timing, and exercise projected clicks, view toggles, and both crate positions. They do not judge art fit or animation readability; use the native-sized captures and interactive view for those.
