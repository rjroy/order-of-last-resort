# Fixed outing victory routes

Run from the repository root:

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/fixed_outing_victory_test.gd
```

`fixed_outing_routes.json` contains the candidate winning commands for all 15
missions. The test discovers the five outings and mission order from the authored
catalog, checks that each mission appears exactly once, and starts each outing
through the guild. It uses only checked-in content and routes, not local search
output. The real-scene regression passed for all five outings on the current
working tree; rerun it after changes to content or runtime rules.

Each mission has an object in `fixed_outing_routes.json`. The first mission of
each outing has a `party` array of three distinct recruit IDs in deployment
order. Every mission has a nonempty `rounds` array. Each element is one
committed round:

```json
{
  "party": ["healer", "knight", "bard"],
  "rounds": [
    {
      "orders": {"bard": "order_healing_sonnet", "healer": "order_aggressive"},
      "command": {"actor": "healer", "ability": "move", "target": "1,0"}
    },
    {"command": {"actor": "knight", "ability": "move", "target": "1,1"}},
    {"command": {"actor": "healer", "ability": "move", "target": "2,1"}},
    {"command": {"actor": "healer", "ability": "healer_heal"}}
  ],
  "reward": "healer"
}
```

This example shows the first four rounds of the `shield_wall` candidate; the
full route is in the fixture. `orders` and
`command` are optional; an empty object commits standing orders. Omit `target`
for abilities that do not require a selectable target. IDs must be selectable
in the actual scene, including cell target IDs shown in the target selector.
The first and second mission of each outing must specify a `reward` hero whose
offer is visible; the final mission has no debrief reward. Reward offers use
seed 12345, so derive later routes with the same seed, earlier reward choices,
party, and actual carried state. Check every forecast and committed outcome
through this test after changing routes; a solver's model-only path is not
evidence of a playable scene victory.

## Optional route discovery

The development-only search tool is `res://tools/fixed_outing_route_search.gd`.
It is not used by the regression. For a new search, create a JSON config at an
absolute path, for example:

```json
{
  "adventure": "border_watch",
  "party": ["healer", "knight", "bard"],
  "orders": {"healer": "order_aggressive", "bard": "order_healing_sonnet"},
  "rewards": ["healer", "bard"],
  "beam": 12,
  "depth": 15,
  "abilities": []
}
```

Run one outing at a time, with separate configs and output captures for
independent processes:

```sh
godot --headless --path games/company-of-unlikely-heroes \
  --script res://tools/fixed_outing_route_search.gd -- \
  --config=/absolute/path/config.json
```

The tool prints a mission-keyed candidate object. Copy reviewed routes into the
checked-in route file and run the real-scene regression. An empty `abilities`
array searches all available abilities; a nonempty array restricts direct
commands. The bounded search picks the first winning path for each mission, so
later failure may require different settings; failure does not prove no route
exists.
