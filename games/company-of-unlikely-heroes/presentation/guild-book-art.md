# Guild book illustration inventory

The guild book uses packaged PNGs under `res://assets/guild-book/`, not
scratch files or generated-at-runtime images. The identifier is the filename
without `.png`. Missing art must remain visibly absent rather than substituting
an unrelated illustration. Candidate artwork is provisional until specifically
approved; the presence of a file is not evidence of approval.

## Portraits

`classes/`: `bard`, `wizard`, `healer`, `rogue`, `knight`, `necromancer`,
`alchemist`, `blacksmith`. A portrait identity is a presentation opt-in, not
the character's mechanical kit or battle art. The Mixologist uses her guild
portrait here and a separate Blender-rendered sprite sheet in battle.
Do not infer portraits from shared defaults or assign them to custom characters
merely because they share those defaults. Blacksmith artwork does not add a recruit
or change the roster.

## Destinations

`destinations/`: `bridge_is_out`, `company_rescue`, `cowardly_captain`,
`dont_wake_the_giant`, `great_sheep_escape`, `hold_the_line`, `last_wagon`,
`mirror_company`, `odd_couple`, `unfortunate_ritual`, `unwelcome_guest`,
`wrong_side_of_the_door`. Nine are commission destinations; the remaining
three paintings are retained from retired practice finales. Each destination
uses the same file wherever it recurs.

## Field reports

`reports/` uses the immediate disclosed mission ID, not route state. The 20
authored report IDs are `bridge_is_out`, `bridge_patrol`, `company_rescue`,
`cowardly_captain`, `dont_wake_the_giant`, `duelists`, `explosive_situation`,
`goblin_mob`, `great_sheep_escape`, `harpoon_squad`, `hold_the_line`,
`last_one_standing`, `last_wagon`, `mirror_company`, `odd_couple`,
`shield_wall`, `unfortunate_healer`, `unfortunate_ritual`,
`unwelcome_guest`, and `wrong_side_of_the_door`. Eleven are transit candidates;
nine are destination reports. No predictive illustration is required. Any
future onward-clue artwork must use only the already disclosed broad kind, never
an undisclosed future mission or the other branch.

## Rewards

`upgrades/` uses upgrade definition IDs from `content/rewards.json`. Repeated
copies of an illustrated reward use the same file. Guild perks are not adventure
upgrades.

## Guild petitions

All 26 stock petitions have dedicated action plates in `petitions/`. Filenames
match petition IDs except `recruit_bard`, which uses `bard.png`, and
`teach_healer_blast`, which uses `healer_blast.png`. The
[source and crop recipes](../assets-source/guild-book/petitions/README.md)
record the approved images. Those two legacy filenames are reserved for their
explicit petition IDs, not implicit matches from other petitions. The preview
lays out the plate, copy, and purchase
control separately. If a petition has no plate, its opted-in recipient portrait
is shown when available; otherwise the preview has no illustration. Register
headings retain their class portraits. The summon, battle, and reward art
catalogs are unaffected.
