# Enthusiastic Caster and Daft Dodger reward art

16 distinct artwork candidates for `mind-garage-tkt.7`. Production was released after the connected study was reviewed. The PNGs in `assets/guild-book/upgrades/` are packaged candidates, not player-accepted artwork. `delivery.sha256` identifies the exact versions for review. This package does not change runtime code, reward content, or approval state.

## Source

[Subject inventory](subjects.md) records the catalog labels, effects, and visual briefs. The connected study's `actual-raster-sizes.png` (`4f1a7e3eef007bc22ad5a9a0ee4a8a664a0a16d1cf129e6cd3dfdbdd60124ed2`) and `reward-plate.png` (`792c55afb81cd52c758bc2c643472d3c73ac3e24fa8c8f05343ca3d029518deb`), staged in `.lore/local/company-of-unlikely-heroes/storybook-nonbattle/study/`, established the target size, warm paper, restrained pigments and dark ink. The reward plate and the corresponding approved cast concept image were supplied to each sheet generation. Accepted Blender model pose sheets were checked against the concepts for costume and stance; they were not supplied to the generator.

The unchanged native sheets below were generated on 2026-11-21 with the built-in `experimental_image_generate` tool using `openai/gpt-image-2`. They were copied byte-for-byte from `.lore/local/company-of-unlikely-heroes/storybook-nonbattle/upgrades-wizard-rogue/` and decode as opaque sRGB PNGs, 1774 × 887. See `source.sha256` for exact identities.

| Source | Generation job | Art direction |
| --- | --- | --- |
| `wizard-a.png` | `image_201b99f330011itYz0E642dLpW` | Spare Robes, More Powder, Padded Landing, Demolition Practice |
| `wizard-b.png` | `image_201b9cff1001yyicFHoClGdsJS` | Duck!, Braced Casting, Parting Gift, Conductive Personality |
| `rogue-a.png` | `image_201ba035d0010lnqBxsMkO5A2m` | Thick Coat, Cheap Shot, Exit Strategy, Borrowed Courage |
| `rogue-b.png` | `image_201ba3746001ImPf0t6jojG3oI` | Pass the Buck, Pocket Sand, original Long Finger, Body Double |
| `rogue-long-finger-correction.png` | `image_201bb39a4001CsfG8eOL8qCJMN` | Edited the lower-left `rogue-b.png` quadrant (887 × 444 at +0+443), preserving two tiles and the extended gauntlet but replacing the mistakenly depicted Rogue with a separate armored guard. Generated from that crop and the reward plate. |

Each sheet prompt requested an unmarked 2 × 2 grid of independent events on the same paper, each safely inside its own cell. [crops.tsv](crops.tsv) contains the selected sheet, inspected crop, fit box, paper color and label for each ID. The titles are added on contact sheets only, never in the runtime PNGs.

## Rebuild and review

Run from the game directory:

```bash
src=assets-source/guild-book/upgrades-wizard-rogue
review=../../.lore/local/company-of-unlikely-heroes/storybook-nonbattle/upgrades-wizard-rogue
bash "$src/prepare.sh" "$review/repro" "$review"
(cd "$src" && sha256sum -c source.sha256)
(cd "$review/repro" && sha256sum -c "$OLDPWD/$src/delivery.sha256")
```

The recipe uses ImageMagick 7.1.2-34 (Lanczos crop/fit, feathered inset, opaque RGB sRGB PNG) and Fontconfig 2.18.3 for the contact-sheet font (resolved to Liberation Sans on the review machine). Runtime does not require either tool, any review file, or any generated sheet. The 16 exports total about 804 KiB. No texture-size budget or import-settings change was requested.

Both the native 318 × 154 contact sheet and 159 × 77 stress test were inspected. The four classes of silhouette used here (gear, single character, impact, and transfer) remain distinct even at the smaller size. The faint second zap in Conductive Personality and the foot scuff in Parting Gift are the first cues to check in the game. Two clean recipe runs matched byte for byte; all 16 exact filenames also matched the live Wizard and Rogue catalog. Godot layout and final visual acceptance are separate from these asset checks.
