# Company content catalog

[`catalog.json`](catalog.json) is the built-in manifest. It assembles [`common.json`](common.json) shared definitions, [`first_outing.json`](first_outing.json) adventure content and [`fixed_fixtures.json`](fixed_fixtures.json) independent regression scenarios into one validated runtime catalog. A manifest contains only a nonempty `parts` array of paths relative to the manifest. Duplicate IDs in the same table across parts are errors, not overrides. For custom content, `--content=full-catalog.json` still accepts a complete catalog without a manifest. Each part and full catalog uses top-level tables that are dictionaries keyed by ID:

- **Adventures** list selectable character IDs in roster order, an ordered list of mission IDs, and a party size. The mission list determines the adventure's length.
- **Missions** name an encounter and may specify a positive integer `tier` for authored difficulty, independent of the number of missions in an adventure. The `escort` objective names a character *placement* as its `subject` and a board *location* as its `destination`; `defeat_all` requires no escort. `failures` is an ordered list of supported checks (`subject_dead`, `deadline`, and `party_wiped`). Objective copy and outcome events are authored here; `{subject}` is the lowercased display name, `{subject_label}` preserves its display case.
- **Encounters** specify a board, optional round deadline and ordered placements. An absent or zero deadline is untimed. Optional `party_slots` are ordered deployment coordinates, separate from NPC and object placements. A placement has a unique `id`, one `character` or `object` definition ID, and an `at` coordinate. Party order precedes placement order within the same phase. At equal distance, units precede objects, with placement order breaking ties within each category. **Boards** specify dimensions, a `default_tile`, tile overrides and named locations. Optional `shore_cells` lists eligible cells for the safe-shore tint: only the orthogonally connected group containing the objective destination is highlighted. Omit it for no tint. It does not change tile artwork or rules. Coordinates are zero-based pairs of whole numbers. **Tiles** define passability, label, artwork key and optional `collapse_to`.
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

Entity selection filters by `range` (Manhattan distance), `teams`, `objects` (include objects), and `capabilities` (all listed IDs are required). Without a range limit any distance is allowed. Automatic targeting selects the nearest eligible entity with ties broken deterministically. An automatic heal with `prefer_wounded_self: true` includes its wounded actor when it passes the other target filters; otherwise it targets the nearest eligible other entity, even at full health. Handlers also enforce the physical capabilities they need: `mobile` for movement and pull recoil; `pushable`/`pullable` for displacement; `damageable`/`healable` for damage/healing. `blocks_movement` is independent of whether an entity can be damaged or moved. `commandable` identifies units exposed to player commands; `protectable`, `recoverable` and `tauntable` govern applicable status effects.

| Behavior handler | Parameters and compatibility |
|---|---|
| `use_ability` | `ability` without an explicit target (`none` or `automatic`). |
| `hold` | No parameters. |
| `pursue` | `ability` with entity targeting that accepts `team`, plus `move_ability`. |
| `rescue` | `ability` with entity targeting and a `pull` handler. |
| `threat` | A damaging `ability` with entity targeting, `move_ability`, `pursue_range`, `fallback_teams`, and `taunt_status` with a `retarget` handler. |
| `escort` | `move_ability`. |

Every `move_ability` must refer to a `move` handler and belong to the effective kit. The supported status/expiry pairs are `reflect` / `actor_turn_start`, `skip_action` / `consume_action`, and `retarget` / `actor_turn_end`. These statuses belong to characters with turns. A crate can still take the damage from a status-inflicting attack, but does not acquire its turn-based status. `reflect` takes a `range` and can filter its redirect targets with `teams`, `objects` and `capabilities`; `retarget` can filter permitted sources with `teams`.

## Loading and snapshots

`Catalog.read_default()` loads editable definitions; `Catalog.read_source(path)` runs the same JSON and schema checks for custom files and returns either `{definitions}` or `{error}`. `Catalog.validate(defs)` accepts JSON-shaped data, including whole Godot floats produced by the JSON parser, and returns path-qualified errors. `Catalog.build(defs, mission_id, party_ids = [])` fails with `{}` for invalid data, invalid picks or an unknown mission. A supplied party fills slots in order, using character IDs as unit IDs; an empty party preserves fixed placements. A successful build keeps only definition IDs and encounter/runtime values on entities. Statuses are stored once in each entity's `statuses` dictionary.

The state holds a `catalog` reference with a detached, recursively read-only `defs` dictionary. Unit class and team and the encounter deadline come from those definitions, not mutable copies. The objective destination and `outcome` are the runtime authorities for the exit and result. Deep-copying state for forecasts shares that catalog reference while copying mutable units, terrain, orders and statuses. Editing the original definitions or building a second mission does not modify an existing state.

Godot reads the manifest and its parts directly with `FileAccess`; no import step is needed when running from source. For a Godot export preset, include `content/*.json` under **Filters to export non-resource files/folders**. The project does not ship a platform export preset.
