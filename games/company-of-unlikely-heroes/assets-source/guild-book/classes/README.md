# Guild-book portrait candidates

Status: **candidate**, not player-accepted artwork. The connected study checkpoint released the set for production on 2026-11-21, but did not approve any production file. These illustrations do not change the roster or kit availability. In particular, the Mixologist and Hobby Smith designs are provisional; the Hobby Smith is not recruitable.

Eight opaque sRGB PNG outputs live in `assets/guild-book/classes`. They are 512 × 512 and meant to be center-cropped at 112 × 116 in recruitment or sampled square at 44 × 44 on a reward. The wash and paper tooth are deliberately part of the art; there is no baked lettering, card frame, or alpha mask. Every production crop retains a high-positioned face and at least one larger, class-specific shape. The 44 px examples are intentionally raw-scale: small stitching and heraldic lines are not expected to resolve.

## Sources

The Knight native is the connected study raster in `../study/connected-study.png`. The recipe first extracts the original 750 × 497 plate at offset +776+10. Its centered square keeps the worried expression and prominent griffin while clipping outer wash and a little of the cloak. The remaining seven `*-native.png` images are the unchanged square job outputs from the built-in image generator, which reported `openai/gpt-image-2`. `SHA256SUMS` identifies the exact preserved native and delivered PNG files. Image generation is not deterministic; only the preparation and review sheet reproduce from the archived natives.

References are in the repository's `.lore/work/games/company-of-unlikely-heroes/art/` and `notes/`. For 3D identity checks, use the corresponding `models/<class>/README.md` and its documented pose render command; the generation calls attached the indicated local renders. The in-game `assets/cast` sprite sheets were separately checked for identity and colors. The previously approved Crooked Storybook Fantasy north star and framed Marked-Up Illustration set the direction; for the seven new calls the Knight study plate served as the shared painted-ink reference, not a likeness template.

| ID | Job | Identity reference and pose |
|---|---|---|
| `knight` | Connected study, portrait plate | Guild Steps Guard Study, T-pose and inspected face render; worried upward glance, professional grip and ochre griffin shield. |
| `healer` | `image_201b9aaa80014ELeBMcIksV7f7` | Field Medic Gameplay Study and `ready.png`; skeptical up-glance while pulling a linen wrap snug, crooked staff and broad satchel strap. |
| `wizard` | `image_201b9cb7d001WFHFxcBIPbb92e` | Wizard Blast and Recoil and `ready.png`; orange ringlets under floppy purple hat, leans toward an errant spark. |
| `rogue` | `image_201b9ef9f001kIX2PfkI9O0W7k` | Rogue Alibi Study and `detail-face.png` / `alibi.png`; gray-curled usher with cap, keys, cape and hand over heart. |
| `bard` | `image_201ba1164001YVu7mDquflBrvb` | Bard Two Songs and `melody-detail.png`; receding gray fringe, swept moustache and scuffed oxblood coat, listens to his fiddle. |
| `necromancer` | `image_201ba34cc00119S4wpkCbA3OLA` | Keeper of the Bell and `portrait.png`; friendly older living sitter with white curls, cream stole, flower and handbell. First Greetings and the Skeleton and Zombie models established the distinction between the sitter and the two absent summons. |
| `alchemist` | `image_201ba54a6001v832zQfD1irjOy` | No approved likeness. Uses the north star and the study plate for style; older brewer in mustard head wrap and green collar studies a cloudy flask. |
| `blacksmith` | `image_201ba75ee001VOIzGpnHFrV7Jr` | No approved likeness. Uses the north star and the study plate for style; broad-shouldered smith with a soot-red shirt and a quiff squints along a riveted fitting, hammer at rest. |

## Reproduce and inspect

From the repository root, using ImageMagick 7 (verified with 7.1.2-34) and the system's Fontconfig for labels on the review sheet:

```sh
game=games/company-of-unlikely-heroes
source_dir="$game/assets-source/guild-book/classes"
mkdir -p .lore/local/guild-book-review
work="$(mktemp -d .lore/local/guild-book-review/repro.XXXXXXXX)"
bash "$source_dir/prepare.sh" "$work"
diff -qr -x '*.import' "$game/assets/guild-book/classes" "$work"
bash "$source_dir/review.sh" "$work" .lore/local/guild-book-review/classes.png
(cd "$game" && sha256sum -c assets-source/guild-book/classes/SHA256SUMS)
```

The review sheet shows 180 px comparisons and the two live display sizes. It is local inspection evidence, not game art. The original raster sources are excluded from Godot imports; the derivative PNGs are the only runtime inputs.
