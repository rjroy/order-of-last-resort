# Company content catalog

[`catalog.json`](catalog.json) is the built-in manifest. It assembles [`common.json`](common.json) shared definitions, [`first_outing.json`](first_outing.json) adventure content and [`fixed_fixtures.json`](fixed_fixtures.json) independent regression scenarios into one validated runtime catalog. A manifest contains only a nonempty `parts` array of paths relative to the manifest. Duplicate IDs in the same table across parts are errors, not overrides. For custom content, `--content=full-catalog.json` still accepts a complete catalog without a manifest. Each part and full catalog uses top-level tables that are dictionaries keyed by ID:

- **Adventures** list selectable character IDs in roster order, an ordered list of mission IDs, and a party size. The mission list determines the adventure's length.
- **Missions** name an encounter and may specify a positive integer `tier` for authored difficulty, independent of the number of missions in an adventure. The `escort` objective names a character *placement* as its `subject` and a board *location* as its `destination`; `defeat_all` requires no escort. `failures` is an ordered list of supported checks (`subject_dead`, `deadline`, and `party_wiped`). Every mission referenced by an adventure must include `party_wiped`: a wipe takes precedence over victory, and surviving summons do not count. Standalone missions may omit it. Objective copy and outcome events are authored here; `{subject}` is the lowercased display name, `{subject_label}` preserves its display case.
- **Encounters** specify a board, optional round deadline and ordered placements. An absent or zero deadline is untimed. Optional `party_slots` are ordered deployment coordinates, separate from NPC and object placements. A placement has a unique `id`, one `character` or `object` definition ID, and an `at` coordinate. An optional `hp` overrides starting HP from zero through that definition's maximum; use `0` for a starting corpse. An optional `seed` sets the opening random state (default `1`, allowed `1`–`2147483646`). Party order precedes placement order. Most nearest-target ties prefer the first eligible unit in deployment order, then objects in placement order.
- **Boards** specify dimensions, a `default_tile`, tile overrides and named locations. Optional `shore_cells` lists eligible cells for the safe-shore tint: only the orthogonally connected group containing the objective destination is highlighted. Omit it for no tint. It does not change tile artwork or rules. Coordinates are zero-based pairs of whole numbers. **Tiles** define passability, label, artwork key and optional `collapse_to`.
- **Characters** inherit their field values from **classes**; an override replaces the entire scalar, array or map, including `abilities` and `habits`. Keep each habit's behavior and the autonomous `behavior` compatible with the effective kit. `default_order` must be one of that character's habits. **Objects** and classes/characters list **capabilities** by ID, separate from their team and artwork.
- **Orders** provide player-facing labels. A character's `habits` map each order ID to a **behavior** ID. Labels are not executable IDs.
- **Events** are templates used by the rules. Use the supplied template names and placeholders when editing their text. Facts such as who was damaged and their coordinates are also available as event data. **Presentation** maps artwork/overlay keys to labels and optional colors.

## Supported rule handlers

The catalog selects code handlers, not arbitrary scripts. New mechanics need new rule code.

| Ability handler | Accepted `targeting.kind` | Parameters |
|---|---|---|
| `move` | `cell` | No parameters; if present, target `range` must be `1`. |
| `apply_status` | `none` | `status` |
| `push` | `entity` or `automatic` | `collision_damage` |
| `bonk`, `blast` | `entity` or `automatic` | `damage`, `status`, optional `source_suffix` |
| `heal` | `entity` or `automatic` | `amount`; optional `prefer_wounded_self` for automatic healing |
| `pull` | `entity` or `automatic` | `recoil_damage`, `status` |
| `attack` | `entity` or `automatic` | `damage`, optional `source_suffix` and `status` |
| `swap_furthest` | `automatic` | No parameters; swaps the actor with the furthest eligible other living character. |
| `misdirect` | `entity` | `status` referencing a status with the `misdirect` handler. |
| `summon` | `cell` or `entity` | `character` referencing a non-commandable character with the `minion` capability; lower `priority` acts first after its summoner. |
| `sweep` | `none` | `damage` and a required `targeting.range`; hurts all other damageable characters in range. |
| `stop_target` | `automatic` | `status` referencing a status with the `stop_move` handler. |
| `repel` | `automatic` | No parameters. The nearest other character takes a step away if the destination is open; select the dominant axis, with horizontal breaking ties. A blocked step does not choose another character or direction. |

Entity selection filters by `range` (Manhattan distance), `teams`, `objects` (include objects), and `capabilities` (all listed IDs are required). Without a range limit any distance is allowed. Automatic targeting selects the nearest eligible entity with ties broken deterministically. An automatic heal with `prefer_wounded_self: true` includes its wounded actor when it passes the other target filters; otherwise it targets the nearest eligible other entity, even at full health. Handlers also enforce the physical capabilities they need: `mobile` for movement and pull recoil; `pushable`/`pullable` for displacement; `damageable`/`healable` for damage/healing. `blocks_movement` is independent of whether an entity can be damaged or moved. `commandable` identifies units exposed to player commands; `protectable`, `recoverable` and `tauntable` govern applicable status effects.

`swap_furthest` is the exception to nearest automatic selection: it excludes objects and breaks equal Manhattan distances by lowest instance ID, regardless of unit order. `misdirect` selects an opposing character with at least one other living character orthogonally adjacent. The player selects that opponent, not the alternate victim. At its next attack, the marked character redirects to the adjacent living character with the lowest instance ID, excluding itself and the original attack target. This can be its ally. If no alternate remains, the original attack proceeds; either way the mark is consumed. An aura can subsequently redirect the attack. The mark event names a currently adjacent candidate, while the attack forecast and resolution identify the actual recipient.

With `summon`, **cell** targeting places the creature on a vacant adjacent tile at its authored maximum HP; **entity** targeting selects a defeated opponent that matches the filters and is on a vacant tile. This consumes that corpse and uses half of its maximum HP, rounded up, as both the current and maximum HP of the new creature. Summons and already-consumed bodies cannot be raised. Each summoner can have only one living summon of a given character ID. Summons are added to the board immediately and join initiative starting next round, immediately after their summoner, ordered by `priority` then instance ID. Profiles with the `minion` capability may not include abilities that use the `summon` handler.

| Behavior handler | Parameters and compatibility |
|---|---|
| `use_ability` | `ability` without an explicit target (`none` or `automatic`). |
| `hold` | No parameters. |
| `pursue` | `ability` with entity targeting that accepts `team`, plus `move_ability`. |
| `rescue` | `ability` with entity targeting and a `pull` handler. |
| `threat` | A damaging `ability` with entity targeting, `move_ability`, `pursue_range`, `fallback_teams`, and `taunt_status` with a `retarget` handler. |
| `escort` | `move_ability`. |
| `retreat` | `move_ability` and opposing `team`. Step away from the nearest living member of that team, with lowest instance ID breaking enemy-distance ties. Among equally distant legal steps, prefer the direction most aligned with the vector away from that enemy, then the fixed direction order. Hold if no step increases distance. |
| `greet` | `move_ability`, opposing `team`, `greeting_range`, and a nonempty list of `greetings` ability IDs from the effective kit. With an opponent within `greeting_range`, picks among legal greetings. An entity greeting picks its nearest legal target; automatic greetings use their own targeting rules. Otherwise, takes one step along the shortest path to a reachable tile within `greeting_range` of the nearest opponent where at least one greeting is legal on the current board. It waits if no such path exists. |

Every `move_ability` must refer to a `move` handler and belong to the effective kit. The supported status/expiry pairs are `reflect` / `actor_turn_start`, `skip_action` / `consume_action`, `retarget` or `stop_move` / `actor_turn_end`, and `misdirect` / `consume_attack`. These statuses belong to characters with turns. A crate can still take the damage from a status-inflicting attack, but does not acquire its turn-based status. `reflect` takes a `range` and can filter its redirect targets with `teams`, `objects` and `capabilities`; `retarget` can filter permitted sources with `teams`. `misdirect` takes no parameters and persists until the next attack. `stop_move` takes no parameters and blocks only the Move ability until the end of the affected character's next turn.

Catalogs with a `swap_furthest` ability must provide the `swap` event template. A `misdirect` ability needs `misdirect_mark`; a `misdirect` status needs `misdirect_redirect` and `misdirect_missing`. `summon` needs `summon` for cell targeting or `raise` for entity targeting. `sweep`, `repel` and `stop_target` need events of the same names. Catalogs without these handlers need not include their templates. Use the placeholders in the built-in templates when authoring replacements.

## Loading and snapshots

`Catalog.read_default()` loads editable definitions; `Catalog.read_source(path)` runs the same JSON and schema checks for custom files and returns either `{definitions}` or `{error}`. `Catalog.validate(defs)` accepts JSON-shaped data, including whole Godot floats produced by the JSON parser, and returns path-qualified errors. `Catalog.build(defs, mission_id, party_ids = [])` fails with `{}` for invalid data, invalid picks or an unknown mission. A supplied party fills slots in order, using character IDs as unit IDs; an empty party preserves fixed placements. A successful build keeps only definition IDs and encounter/runtime values on entities. Statuses are stored once in each entity's `statuses` dictionary.

The state holds a `catalog` reference with a detached, recursively read-only `defs` dictionary. Unit class and team and the encounter deadline come from those definitions, not mutable copies. The objective destination and `outcome` are the runtime authorities for the exit and result. Deep-copying state for forecasts shares the catalog reference while copying mutable units, terrain, orders, statuses and encounter random state. Greeting choices advance the random state only in the forecast result; committing that forecast keeps the same choices. Editing the original definitions or building a second mission does not modify an existing state.

Godot reads the manifest and its parts directly with `FileAccess`; no import step is needed when running from source. For a Godot export preset, include `content/*.json` under **Filters to export non-resource files/folders**. The project does not ship a platform export preset.
