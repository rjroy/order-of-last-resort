# Guild book upgrade illustrations: Mixologist

Seven packaged candidates for the Mixologist's adventure upgrades. The art
shows a prop or an action; the guild book supplies the label, rules, and rarity.
Repeated copies use the same illustration. Neither packaging nor technical
checks constitute artwork approval.

| Upgrade ID | Catalog effect | Illustration cue |
| --- | --- | --- |
| `alchemist_padded_apron` | +1 maximum HP without changing missing HP. | Tawny work apron with a quilted bib and thick padded hem. |
| `alchemist_stronger_dose` | Healing Potion restores 1 more HP. | Round amber flask pours a generous dose onto a bandage. |
| `alchemist_concentrate` | Acid deals 1 more damage to its target. | One dark green drop pits one iron plate; no splash. |
| `alchemist_long_ladle` | Healing Potion reaches one tile farther; Follow still stops beside the closest ally. | A long wooden handle carries an amber ladleful to a distant glove. |
| `alchemist_spare_vial` | Adds Plain Tonic, a range-1 heal for 1 with no reaction. Potion upgrades do not affect it. | One slim, plain, corked vial tucked into a dark leather belt. |
| `alchemist_brittle_glass` | Acid splashes 1 damage onto adjacent characters, including friends; only the selected target gets a reaction. | A shattered faceted flask splashes across the gap between two shielded boots. |
| `alchemist_keep_the_culture` | Bottles the last Potion or Acid reaction; Repeat Batch applies that recipe and reaction to another legal recipient and empties the bottle. No carryover between missions. | A stoppered jar contains a plum-and-ochre swirl, cradled in one hand. |

## Native art and crop provenance

`mixologist-native.png` is the unchanged 1254 × 1254 RGB sRGB atlas generated
on 2026-11-21 using `experimental_image_generate` (`openai/gpt-image-2`, job
`image_201eda17c001vnFfR85JMdHyCD`). The native staging path was
`.lore/local/company-of-unlikely-heroes/storybook-nonbattle/upgrades-mixologist/mixologist-native.png`.
The staging and packaged atlas match byte for byte; its SHA-256 is in
`crops.json`. The two-column, four-row atlas has seven illustrated cells and a
blank lower-right cell. The cue table records the art direction for each cell.

Generation used the following three references:

- The connected study's isolated `reward-plate.png`, to match warm cream
  paper, ink and muted pigments (`792c55afb81cd52c758bc2c643472d3c73ac3e24fa8c8f05343ca3d029518deb`).
- `assets/guild-book/upgrades/bard_sharper_notes.png`, for the set's sparse
  landscape staging (`d2b28a679a11785d2ae3823b36be7621e56579093a032e191d6d374e0dd4fef1`).
- The Mixologist's `art/concepts/mixologist/mixologist-concept.png`, for the
  cuffs, apron, amber healing flask, and faceted acid glass
  (`d154bed99a0a5652824bc6bcacf212051950d370e40a43e76bed9e329793be76`).

References are not conversion dependencies. `crops.json` records the
inspected rectangles as `[x, y, width, height]`; the recipe crops before
Lanczos resampling and writes opaque 318 × 154 RGB PNGs in sRGB. The visible
cream is page color, not transparency. There is no baked lettering or UI
furniture. Godot 4.7.2 generated the adjacent `.png.import` files; their
texture parameters match existing lossless 2D guild-book upgrades.

## Rebuild and review

From the repository root, use Python 3 and ImageMagick 7 (verified with
Python 3.14.8 and ImageMagick 7.1.2-34 Q16-HDRI). The optional contact sheet
uses Adwaita Sans.

```sh
game=games/company-of-unlikely-heroes
source_dir="$game/assets-source/guild-book/upgrades-mixologist"
review=.lore/local/company-of-unlikely-heroes/storybook-nonbattle/upgrades-mixologist
python3 "$source_dir/prepare.py" "$review/repro" \
  --contact-sheet "$review/contact-sheet.png"
(cd "$review/repro" && sha256sum -c "$OLDPWD/$source_dir/delivery.sha256")
(cd "$game/assets/guild-book/upgrades" && sha256sum -c "$OLDPWD/$source_dir/delivery.sha256")
godot --headless --path "$game" --script res://tests/presentation/guild_book_art_test.gd
```

Two recipe runs produced identical bytes. All seven native-size crops and a
159 × 77 stress view were visually inspected: isolated silhouettes, no
neighboring art, and a clear difference between the single acid drop and
the shattered-flask splash. The small vapor detail in Concentrate recedes at
half-size, but the drop and pit remain. The stock artwork inventory reported
55 of 55 upgrade illustrations with no unexpected PNGs, and the Godot
resolver test passed. The crops are presentation candidates; visual review
in the actual reward page and player acceptance remain separate.
