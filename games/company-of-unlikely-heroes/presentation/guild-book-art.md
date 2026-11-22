# Guild book illustration inventory

The guild book uses packaged PNGs under `res://assets/guild-book/`, not
scratch files or generated-at-runtime images. The identifier is the filename
without `.png`. Missing art must remain visibly absent rather than substituting
an unrelated illustration. Candidate artwork is provisional until specifically
approved; the presence of a file is not evidence of approval.

## Portraits

`classes/`: `bard`, `wizard`, `healer`, `rogue`, `knight`, `necromancer`,
`alchemist`, `blacksmith`. A portrait identity is a presentation opt-in, not
the character's mechanical base class. In particular the stock Bard, Rogue,
and Necromancer use Wizard mechanics and the Alchemist uses Healer mechanics.
Do not infer their portraits from those base classes or assign them to custom
characters merely because they share one. Blacksmith artwork does not add a
recruit or change the roster.

## Destinations

`destinations/`: `bridge_is_out`, `company_rescue`, `cowardly_captain`,
`dont_wake_the_giant`, `great_sheep_escape`, `hold_the_line`, `last_wagon`,
`mirror_company`, `odd_couple`, `unfortunate_ritual`, `unwelcome_guest`,
`wrong_side_of_the_door`. This is the union of the nine commission destinations
and the seven fixed-practice finales, four of which overlap. Each destination
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

`upgrades/` uses the 48 upgrade definition IDs in `content/rewards.json`.
Repeated copies use the same file. Guild perks are not adventure upgrades.
