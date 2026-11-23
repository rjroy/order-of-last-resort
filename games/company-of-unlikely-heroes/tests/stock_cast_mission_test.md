# Stock cast graphical checkpoint

From the repository root, with a graphical Godot display:

```sh
godot --path games/company-of-unlikely-heroes \
  --script res://tests/stock_cast_mission_test.gd -- \
  --mission=goblin_mob --actor=goblin \
  --output="$PWD/.lore/local/stock-cast-goblin"
```

Choose a new or empty output directory each time. Exit 0 means this particular
case passed; exit 1 means a failure. This case is intentionally red until the
Goblin's runtime binding and `jab` cue are integrated. Its opening and
committed-action PNGs are still written on failure. The normal main scene
launches the unmodified stock mission and its default party. The empty commands
are legal automatic rounds committed through the real battle UI.

Each `support/stock_cast_case_<character>.json` is an independently stageable
actor case; the shared `stock_cast_cases.gd` loader accepts any subset. Stage
the Goblin case with the reusable driver and triggers without staging future
actors. A case names its stock mission, expected cast key, opening population,
and event triggers. `automatic_rounds` commits standing orders without repeating
identical empty route data. `rounds` uses steps with `command` and `orders`.
`route_ref` references a shared route in `stock_cast_routes.json`. Optional
`--variant=<id>` chooses only that actor's alternate checkpoint.
For a mission without a default party supply a stock `party` in the case.
The fixture passes the selected mission through the main scene's public
`--mission` option. It passes `--party` for a case-declared party or an inventory
fallback; otherwise it exercises the authored default without a party flag.
The opening assertion checks party order in either path. Routes for later outing missions do not reproduce prior-mission
rewards. No content or rules are replaced.

To check the graphical fixture and stock events before a cast exists, append
`--events-only`. This mode still launches the main scene, commits the routes,
checks each required event and writes screenshots, but **does not test cast
bindings, placeholder differences or playback cues**. Its success is not a cast
pass. Use a separate empty output directory for each invocation.

The driver enumerates matching character IDs rather than assuming placement
IDs, logs newly discovered figures, checks visible figures at their first ready
checkpoint, including reserves after they enter, and checks the target role only.
An empty opening is valid for an explicitly configured reserve case. It verifies the bound cast key
and compares the rendered board with the requested role stripped of its cast
binding. It records committed event screenshots even when the cue is missing,
checks each matching committed event has the expected actor-specific cue,
and samples matching live queue entries. A terminal screen is captured when a
route reaches one.

The following clip names match the current candidate bake recipes, not approved
assets or existing production bindings. Cast keys are the stock character IDs.
Archer's candidate recipe became available during this work. Each default uses
its configured party, or its stock mission default party when none is specified.
The listed variants use their configured party and legal commands.

| Character | Mission | Required clips |
| --- | --- | --- |
| goblin | goblin_mob | move, jab |
| archer | hold_the_line | reserve_arrival, draw_and_release |
| frontier_war_drummer | hold_the_line | reserve_arrival, war_drum_pulse |
| frontier_sheep | great_sheep_escape | flee_step, pen_settle, penned |
| frontier_shepherd | great_sheep_escape | pursuit_step, scatter_wave |
| frontier_wagon | last_wagon | advance, stall, destroyed |
| frontier_wagon_raider | last_wagon | intercept, wagon_strike |
| shieldbearer | shield_wall | guard |
| grunt | cowardly_captain | close_strike |
| captain | cowardly_captain | command, back_away |
| bomber | explosive_situation | close_strike; `chain` variant: detonate_on_defeat |
| hookhand | harpoon_squad | hook_pull |
| bruiser | harpoon_squad | heavy_strike |
| enemy_healer | unfortunate_healer | bonk; `field_dressing` variant: field_dressing |
| duelist | duelists | lunge; `retaliate` variant: retaliate |
| bandit_damage | last_one_standing | melee; `bonus` variant: harder_strike |
| bandit_guard | last_one_standing | melee; `brace` variant: brace |
| bandit_swift | last_one_standing | melee; `quick_step` variant: quick_step |
| ogre | odd_couple | heavy_strike; `swap` variant: swap_reaction |
| trickster | odd_couple | melee_feint; `swap` variant: switch_places |
| rival_knight | mirror_company | shield_push |
| rival_wizard | mirror_company | nearest_blast |
| rival_healer | mirror_company | ally_heal |
| village_troll | unwelcome_guest | curious_follow; `living_exit` variant: leaves_square_alive |

The stock Shieldbearer's behavior is `hold`; its listed `shield_bash` is not
selected by its autonomous behavior in the stock encounter. The formation
provides `adjacent_guard`; exercising bash would require a different behavior
or controlled fixture, not this stock route. The Captain's `rally` is the
Captain-owned `adjacent_damage_bonus` trait event during a Grunt's
`grunt_strike`, not a Captain attack. `back_away` requires the actual
`last_retreat_round` state set by the Captain's tactical retreat. The Enemy
Healer variant requires positive `frontier_heal` output. The Troll's walk is
induced by a legal Knight move; the stationary route is not presented as
movement. The separate exit variant requires a living objective subject outside
the square at the committed victory.

Guard's brace requires the actual `ally_death_guard` reduction event, not just
the announcement of a bonus. Swift's quick step requires a genuine two-cell
move after an earlier sibling movement bonus, including a bonus earlier in the
same round. Bomber chain requires one bomber's blast to damage a second bomber
which then detonates in the same committed event stream. These are not synthetic
arrangements.

The matrix is not a full animation inventory: generic hit, defeat, equipment
release and other reactions are not automatically exercised just because a
model offers those takes. Add a separate committed-effect route before claiming
coverage of any such take. The existing `--events-only` results never establish
that a cue is bound or rendered.

Trigger matching uses the actual event's actor field, not the enclosing action's
actor. `source_id` is accepted for action events without `unit_id`; an action
trigger also verifies the resolved ability and action owner. Event-time
positions are tracked through forced moves and swaps. A sheep entering the pen
requires its actual objective move across the pen boundary; the later
`pen_held` checkpoint checks an actual wait while the same sheep is in the pen
and remains there, with no later movement that round. It is a state assertion,
then checks `penned` at most once per sheep after that state is reached; it does
not repeatedly interpret every wait as a new settle. Wagon destruction requires the objective
subject and zero HP, not an unrelated defeat or timeout. After playback drains,
the fixture checks the actual hold selector and compares the subject's cell to
the same figure explicitly rendered at Ready. This also works when a defeated
wagon's lifecycle fallback uses the same `destroyed` clip as its wreck hold.
Each configured trigger
must occur at least once; each observed cue-bearing subject must have its own
matching cue. Different triggers may occur for the same subject in one round.

## Archer's detached arrow

With the stock Archer atlas installed, run the normal **Hold the Line** route
with the flight checkpoint. Choose a new or empty output directory.

```sh
godot --path games/company-of-unlikely-heroes \
  --script res://tests/archer_projectile_scene_test.gd -- \
  --mission=hold_the_line --actor=archer \
  --output="$PWD/.lore/local/stock-cast-archer-flight"
```

In addition to the stock reserve arrival and shot, this checks the native
detached arrow at midflight on the real board: the authored hand origin,
point-first orientation, tip at the resolved target, and visible pixels from
the detached atlas. It saves a `round-*-arrow-midflight.png` capture.

## Stock opening inventory

For each mission, launch separately with `--mission=<id> --inventory
--output=<empty directory>`, omitting `--actor`. The driver checks every
catalog encounter placement, its ID and stock cell, whether reserves remain
off-board, and active figure or obstacle presence on the real board. It logs
every placement and captures the complete shared opening. Missions without a
default party use an explicit stock Knight/Healer/Wizard party via `--party`.
Inventory is not an authored-cast check.

For example, `bridge_patrol` has no default party and previously used a private
battle-entry shortcut. Exercise its public launch path with:

```sh
godot --path games/company-of-unlikely-heroes \
  --script res://tests/stock_cast_mission_test.gd -- \
  --mission=bridge_patrol --inventory \
  --output="$PWD/.lore/local/stock-cast-bridge-inventory"
```

After all actors are integrated, add `--all-integrated` to inventory to require
the registered cast binding for every opening and reserve character, plus
visible non-placeholder ready art for each active role. Reserve rendering and
performances still require their actor-specific runs. This opt-in mode is
expected to fail during incremental integration and does not affect normal
actor-selective tests. The Fierce variant checks the actual damage-bonus event
without inventing a bonus animation, then checks `harder_strike` on a later
committed attack with a fallen sibling.

Limits: cases cover only the named appearances and triggers, not
all poses, roles, outcomes, or pixel-perfect appearance. Additional
cases need routes that actually exercise their requested action and, where
needed, terminal states. Playback sampling currently uses the clip midpoint;
case-specific contact frames and terminal assertions need additional case
metadata before claiming those beats are verified. The generic fallback image
comparison is a whole-board comparison, so binding checks are also required.
Screenshot inspection remains necessary for visual acceptance.
