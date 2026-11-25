# Standalone mission victory routes

Run from the repository root:

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/journeys/standalone_victory_test.gd
```

`../fixtures/standalone_victory_routes.json` contains independently playable victories for
the 15 frontier missions. Each starts through the public `--mission` and
`--party` launch options with a fresh company and default loadouts. There are no
carried wounds, orders or rewards and no injected content. Each committed round
is checked against its forecast through the game scene.

Each mission object contains a `party` array of three distinct hero IDs in
deployment order and a nonempty `rounds` array. Each element is one committed
round, for example:

```json
{
  "party": ["healer", "knight", "bard"],
  "rounds": [
    {
      "orders": {"bard": "order_healing_sonnet", "healer": "order_aggressive"},
      "command": {"actor": "healer", "ability": "move", "target": "1,0"}
    },
    {}
  ]
}
```

This is an excerpt, not a complete victory. `orders` and `command` are optional;
an empty object commits standing orders. Omit `target` for abilities that do not
require a selectable target. IDs must be selectable in the actual scene,
including cell target IDs. Routes must finish on a committed victory.

These are deterministic regression recipes, not balance or enjoyment tests.
Changes to the authored encounters, hero kits, or rules can invalidate a route;
rerun the scene regression after editing one. The Gate route is adapted from
`storybook_gate_outcome_scene_test.gd`, and the Odd Couple opening uses the
stock cast swap route.

The separate `village_outing_scene_test` checks openings and independent wins
for Goblin Mob, Harpoon Squad and Unwelcome Guest. It uses the shared bounded
forecast-driven scene player instead of static command recipes.
