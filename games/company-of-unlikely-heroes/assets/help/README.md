# Help book screenshots

These PNGs are unretouched crops of the live game. The source is a 1280 × 820 Godot viewport running `main.tscn` from game revision `bf26c348e745c536cfa80b5b39bdecf26d3e4c76`. Captured with Godot 4.7.2 (`ed1daf0bf`), GL Compatibility on Linux. The capture uses the stock catalog and a fresh guild named The Lantern Company with board seed 677. The battle is a separate standalone launch of The Wrong Side of the Door.

| Image | Native size | Suggested caption |
| --- | --- | --- |
| [commission-selection.png](commission-selection.png) | 408 × 608 | Choose a commission by its destination and length. The mission count includes the finale. |
| [recruitment.png](recruitment.png) | 530 × 581 | Recruit three heroes. Use Earlier and Later to set where they start and who acts first. |
| [field-reports.png](field-reports.png) | 592 × 657 | Compare the immediate missions on Routes A and B. Farther ahead hints at a later mission type, not the exact encounter. |
| [battle-controls.png](battle-controls.png) | 616 × 96 | Select a hero, then click a legal target or choose an automatic footer ability to replace one standing order for the round. Open Forecast before you decide. |
| [battle-commit.png](battle-commit.png) | 382 × 60 | Clear command to restore the standing order for this round. Commit when you’re ready to play out the forecast. |
| [battle-board.png](battle-board.png) | 522 × 345 | The solid Knight is still at B2. The ghost at C2 shows the planned move to the pressure plate. |
| [battle-forecast.png](battle-forecast.png) | 438 × 320 | Read the forecast in order: the Knight moves onto the plate, then the gate opens. The live gate stays shut until the round is committed. |

The three taller crops were inspected in a 520 × 565 px box, which preserves their aspect ratios and keeps the card text and buttons readable. Use the battle crops separately rather than reducing the full-width control rail. Keep the instructions available as handbook text; the images are examples, not the only place to find the rules.

## Reproduce

From the repository root in a graphical desktop session:

```sh
(
  set -e
  mkdir -p -- .lore/local/help-book-capture
  base=$(mktemp -d "$PWD/.lore/local/help-book-capture/crops.XXXXXX")
  export XDG_DATA_HOME="$base/xdg-data"
  export XDG_CONFIG_HOME="$base/xdg-config"
  export XDG_CACHE_HOME="$base/xdg-cache"
  godot --headless --path games/company-of-unlikely-heroes --editor --import
  godot --fixed-fps 60 --path games/company-of-unlikely-heroes \
    --script res://tools/capture_help_book.gd -- --output="$base/frames"
  printf 'Frames: %s\nCrops: %s\n' "$base/frames" "$base/frames/crops"
)
```

The capture script uses viewport clicks to select the first commission, recruit the three founders and open field reports. In the standalone battle it commits the Knight’s move to B2, waits for playback, then stages the move to C2 and opens Forecast without committing it. It checks that the forecast predicts an open gate while the actual gate remains closed.

The isolated `profile.json`, five full frames and crop candidates stay under the ignored `.lore/local/` directory. Crop rectangles are in the script, in source pixels. It will not overwrite these source assets or read a normal guild save. Review any new crops at handbook size before replacing the PNGs.
