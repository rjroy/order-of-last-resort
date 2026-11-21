# Fixed outing victory routes

Run from the repository root:

```sh
godot --headless --path games/company-of-unlikely-heroes --script res://tests/fixed_outing_victory_test.gd
```

`fixed_outing_routes.json` contains the candidate winning commands for six
missions. The test discovers the two outings and mission order from the authored
catalog, checks that each mission appears exactly once, and starts each outing
through the guild. It uses only checked-in content and routes, not local search
output. The real-scene regression passed for both outings on this batch; rerun it after changes to content or runtime rules.

Each mission has an object in `fixed_outing_routes.json`. The first mission of
each outing has a `party` array of three distinct recruit IDs in deployment
order. Every mission has a nonempty `rounds` array. Each element is one
committed round:

Each round can specify `orders` and a `command`; an empty object commits standing orders. Omit `target` for abilities that do not require a selectable target. IDs must be selectable in the actual scene. The first two missions of each outing specify a `reward` hero whose offer is visible. Reward offers use seed 12345. The test checks each forecast against the committed outcome and carries rewards and state forward through the real scene.
