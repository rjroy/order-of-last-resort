# Guild book upgrades: Bard and Necromancer

The fifteen vignette briefs below come from `content/rewards.json`. The
illustrations show a prop or an action, not the hero portrait, label, rarity, or
the full rules. A repeated upgrade uses the same illustration.

| Upgrade ID | Label | Implemented change | Illustration cue |
| --- | --- | --- | --- |
| `bard_road_legs` | Road Legs | +1 maximum and current HP on deployment. | A pair of sturdy, recobbled traveling shoes mid-stride on a few worn cobbles. |
| `bard_sharper_notes` | Sharper Notes | Healing Sonnet deals +1 damage. | Close-up of the amber fiddle; a hard bow stroke sends a pointed sound stroke into a nicked practice shield. |
| `bard_buskers_hat` | Busker's Hat | If Melody has no eligible listener, heal self for 1; uses the action. | Upside-down, empty collection hat beside a tucked-in roll of restorative bandage, with fiddle and no crowd. |
| `bard_front_row_seats` | Front Row Seats | Chooses among the lowest-HP two opponents, including cutoff ties; hits the only opponent if one remains. | Exactly two crooked front-row stools each occupied by a nicked opponent helmet, both within a bow stroke. |
| `bard_laughing_fit` | Laughing Fit | The next hit on an enemy before its next activation, after it loses a turn to laughter, deals +2 damage. | An opponent doubled over laughing, shield slipping out of position. |
| `bard_heckler` | Heckler | An enemy surviving Sonnet attacks the Bard next if the Bard is a legal target. | A scuffed enemy snapping toward the mustached fiddler, an accusatory pointing hand tying the pair together. |
| `bard_house_lights` | House Lights | Take the Stage hits an eligible enemy plus its adjacent opponents with current Sonnet damage; available as action and order. | The fiddler beneath one footlight's fan of light, sound passing through a central helmet and its adjacent pair. |
| `necromancer_spare_ribs` | Spare Ribs | Skeletons start with +1 maximum and current HP. | The blue-neckerchief skeleton's rib cage being mended with a spare curved rib. |
| `necromancer_good_soil` | Good Soil | Zombies start with +1 HP after halving the corpse's maximum HP, rounded up. | Moss-aproned gardener rising robustly from a compact mound of dark, rooted garden loam. |
| `necromancer_heavy_bouquet` | Heavy Bouquet | Zombies' Offer Flower deals +1 damage. | An oversized, weighty gray rock with one familiar yellow daisy twined on, the weight bowing a rolled-sleeve palm. |
| `necromancer_broad_wave` | Broad Wave | Skeletons' Wave also hits diagonal neighbors, friend or foe. | The blue-neckerchief skeleton sweeps a bony hand in a broad arc that reaches off-axis neighbors. |
| `necromancer_long_stemmed` | Long-Stemmed | Offer Flower reaches one tile farther, including the zombies' approach range. | A daisy with an exaggerated stem tied to a much smaller stone, offered to a distant gauntlet across blank space. |
| `necromancer_warm_welcome` | Warm Welcome | Say Hello backs the recipient away up to two tiles; stops at an obstruction. | The smiling gardener greets a startled guard, who takes two retreating steps across stone pavers. |
| `necromancer_say_hello_to_that_one` | Say Hello to That One | Nominate one enemy for both undead to pursue; they still choose their own greetings. | An ochre-trimmed, blue-coated pointing arm sends skeleton and gardener after one rust-helmeted guard. |
| `necromancer_wake_reception` | Wake Reception | Once per mission a fallen raised zombie becomes a skeleton if the slot is empty; acts next round with current skeleton starting HP. | The blue-neckerchief skeleton rises from a fallen gardener's moss apron, with the familiar daisy-bound stone left behind. |

## Canon

The approved `bard-two-songs.png` supplies the Bard's amber fiddle and bow,
worn burgundy coat, and ochre neckerchief. `keeper-of-the-bell.png` supplies
the Necromancer's dark dress coat and gold-trimmed cream stole. The approved
summon designs are represented by the packaged `assets/cast/skeleton.png`
and `assets/cast/zombie.png`: the skeleton's blue neckerchief and the
gardener's patched moss apron, with a yellow daisy tied to a gray stone.

## Native artwork and crop provenance

Four RGB sRGB PNG sheets, each 1774 × 887, were generated with the built-in
`experimental_image_generate` tool (`openai/gpt-image-2`, 2026-11-21). The
sheets are byte-for-byte copies of the native files. Each holds the scenes
listed in `crops.json`; the fourth cell of `bard-actions.png` is unused.

| Native filename | SHA-256 |
| --- | --- |
| `bard-objects.png` | `01bac8fd5d8eb9420749a86b9e3c6dce099d1d1114bd9e3ddc269c6cec7fe410` |
| `bard-actions.png` | `3dc17a15b01096ad914c1f3dfdfae29c2d086864d2a6a685dbab378a11732386` |
| `undead-objects.png` | `14987b1c9604c1211788bd2a5ea85026da7df6b4f7b45a186d0b2628bf156752` |
| `undead-actions.png` | `589e26a74377a6f0d010708ad4640b484209638b501217124d9c9ef92b4a0317` |

All four jobs used the reviewed connected study's isolated `reward-plate.png`
as the style guide (SHA-256
`792c55afb81cd52c758bc2c643472d3c73ac3e24fa8c8f05343ca3d029518deb`).
The Bard jobs used `bard-two-songs.png`; the undead jobs used the
approved `first-greetings-zombie-revision.png`
(`fed436ee36ed767e9eecd232e55d74b8cf1f75ea6e994d3243b977164463f96f`);
the latter sheet also used `keeper-of-the-bell.png` for the pointing arm.
The brief above records the composition direction for each crop. Generated
pages contain no typography, rarity treatment, or interface. Backgrounds
are deliberately painted cream, not transparent.

Export and reproduce the contact sheet from the repository root with
Python 3 and ImageMagick (verified with 7.1.2-34 Q16-HDRI; contact sheet
also uses Adwaita Sans):

```sh
source_dir=games/company-of-unlikely-heroes/assets-source/guild-book/upgrades-bard-necromancer
review=.lore/local/company-of-unlikely-heroes/storybook-nonbattle/upgrades-bard-necromancer
python3 "$source_dir/export.py" "$review/review-crops" \
  --contact-sheet "$review/contact-sheet.png"
```

`crops.json` records the reviewed source filename and pixel rectangle
`[x, y, width, height]` for each content ID. Export crops first, then scales to
318 × 154 with Lanczos and encodes opaque RGB sRGB PNG. Native sheets alone
suffice for reproduction; the reference and scratch files are not conversion
or runtime dependencies.

The 15 packaged PNGs under `assets/guild-book/upgrades/` are provisional.
The contact sheet compares them with labels at their intended raster size;
review is still required in the actual guild book. Technical checks are
not artwork acceptance.
