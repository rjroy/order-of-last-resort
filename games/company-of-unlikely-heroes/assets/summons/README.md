# Necromancer summons

Ronald accepted these two temporary models for the playtest after reviewing renders from their saved Blender files. They were built for the Company in Blender 5.2.2 LTS from the approved [First Greetings concept](../../../../.lore/work/games/company-of-unlikely-heroes/art/concepts/necromancer/first-greetings.png). Both are static greeting poses, with feet at Z=0 and forward along −Y.

| Editable master | Distinguishing feature | Accepted file SHA-256 |
|---|---|---|
| [Skeleton](source/skeleton.blend) | Wide wave and blue neckerchief | `a50ba7b7d5ace4f0e3bdf15c44118dc869076b95fcf3665c3753cebd86f85f1f` |
| [Zombie](source/zombie.blend) | Cloudy-eyed gardener offering a daisy tied to a rock | `46df5e2444ac3b96fa875aa9d5546d1c8c9dfa52e3adfa610abcaaa1d57a6b4f` |

Open either file directly in Blender. The `source/.gdignore` keeps Godot from importing the editable studio scenes as gameplay assets.

## Board textures

The sprites below are playtest derivatives, not new model revisions. Both use the same orthographic camera, 20° from the front and 22° above it, with a warm key, cool fill, and soft rim. The script hides the review stage, renders the authored pose and materials against transparency, and adds a narrow ink edge to help separate pale bones from the stone tiles. It never saves to either master.

| Runtime PNG | Canvas (px) | Foot pivot (px from upper left) |
|---|---:|---:|
| [Skeleton](skeleton.png) | 192 × 236 | `(68, 233)` |
| [Zombie](zombie.png) | 99 × 207 | `(52, 204)` |

[`bridge_art.gd`](../../presentation/battle/bridge_art.gd) draws these sprites for `skeleton` and `zombie` art keys, at one board unit per three texture pixels before the usual standing or prone transform. The foot pivots are deliberately not the canvas centers: the skeleton's wave and the zombie's outstretched hand shift their visible bounds. Facing, ground shadow, HP and board overlays remain under the board's existing drawing rules. Source runs decode the packaged PNGs directly, without a prior editor import. A Godot export with a restricted resource list needs to include both texture paths.

## Regenerate offline

Verified with Blender 5.2.2 LTS (`d13f752e3b9c`, Cycles CPU) and ImageMagick 7.1.2-34. From the repository root:

```sh
assets="$PWD/games/company-of-unlikely-heroes/assets/summons"
output="$PWD/.lore/local/company-summon-textures/reproduced"
for kind in skeleton zombie; do
  blender --background --disable-autoexec --threads 6 "$assets/source/$kind.blend" \
    --python-exit-code 1 --python "$assets/render_board_texture.py" -- "$output" || exit 1
  cmp "$output/$kind.png" "$assets/$kind.png" || exit 1
done
sha256sum "$assets"/source/*.blend "$output"/*.png
```

The recipe matched both runtime PNGs byte for byte on the tested setup. The approved master checksums and modification times did not change. Recheck the draw pivots if the crop values printed by the recipe change.

## Board check

Godot 4.7.2 Compatibility rendered the actual board script in a scratch project with no prior import or `.godot` cache. The fixture supplied both art keys on stone, bridge, and safe tiles beside a knight and a raider. It compared each summon against the enemy fallback with the same stats: the figures differed, their HP bars matched, and the selected tile kept its bracket. Visual inspection of the 468, 355, and 270 px board heights found that the wave and blue neckerchief distinguish the skeleton, while the stoop and apron distinguish the zombie. At the smallest size, the daisy reads as an offering gesture rather than a detailed flower.

Local evidence, not a runtime input: `.lore/local/company-summon-textures/runtime-cold/board-{468,355,270}.png` and `capture.log`. To recreate the visual check, pass `skeleton` and `zombie` units with `cell`, `hp`, and `max_hp` to `BridgeArt.set_render_state()` on a seven-column, five-row board, with `facing: -1` on mirrored examples and `selected`, `targets`, or `impact` in the overlay. This check did not exercise the gameplay that spawns summons or verify an exported build.
