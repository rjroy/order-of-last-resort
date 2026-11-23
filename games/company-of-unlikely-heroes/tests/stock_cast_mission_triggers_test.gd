extends SceneTree
## Controlled checks for event-subject attribution and objective transitions.
const Triggers = preload("res://tests/support/stock_cast_triggers.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var sheep := {"id": "sheep", "character_id": "frontier_sheep", "position": Vector2i(0, 0), "hp": 1}
	var before := {"units": [sheep], "objective": {"pen": [Vector2i(1, 0)]}}
	var after := {"units": [sheep.merged({"position": Vector2i(1, 0)}, true)]}
	var entry := {"type": "sheep_entry", "actor_field": "unit_id"}
	var move := {"type": "move", "unit_id": "sheep", "position": Vector2i(1, 0)}
	_check(Triggers.matches(entry, move, before, after, {}, {"sheep": Vector2i(0, 0)}), "objective entry")
	_check(not Triggers.matches(entry, move, before, after, {"unit_id": "other"}, {"sheep": Vector2i(0, 0)}), "forced action is not objective entry")
	_check(not Triggers.matches(entry, move, before, after, {}, {"sheep": Vector2i(1, 0)}), "entry uses event-time position")
	var held := {"type": "sheep_held", "actor_field": "unit_id"}
	var wait := {"type": "wait", "unit_id": "sheep"}
	_check(Triggers.matches(held, wait, before, after, {}, {"sheep": Vector2i(1, 0)}), "held in pen")
	_check(not Triggers.matches(held, wait, before, after, {}, {"sheep": Vector2i(1, 0)}, [move]), "later movement prevents held checkpoint")
	var wagon := {"id": "wagon", "character_id": "frontier_wagon", "position": Vector2i.ZERO, "hp": 2}
	var wagon_before := {"units": [wagon], "objective": {"handler": "wagon", "subject": "wagon"}}
	var wagon_after := {"units": [wagon.merged({"hp": 0}, true)]}
	var destroy := {"type": "wagon_destroy", "actor_field": "target_id"}
	_check(Triggers.matches(destroy, {"type": "defeat", "target_id": "wagon"}, wagon_before, wagon_after), "destroyed wagon")
	_check(not Triggers.matches(destroy, {"type": "defeat", "target_id": "wagon"}, wagon_before, {"units": [wagon]}), "living wagon is not destroyed")
	var captain := {"id": "captain", "character_id": "captain"}
	var grunt := {"id": "grunt", "character_id": "grunt"}
	var bonus := {"type": "event", "event": "adjacent_damage_bonus", "actor_field": "unit_id",
		"action_ability": "grunt_strike", "action_character": "grunt"}
	var event := {"type": "adjacent_damage_bonus", "unit_id": "captain", "target_id": "grunt"}
	var state := {"units": [captain, grunt]}
	_check(Triggers.event_actor(bonus, event) == "captain" and Triggers.matches(bonus, event, state, state,
		{"unit_id": "grunt", "ability_id": "grunt_strike"}), "captain owns trait during grunt action")
	_check(not Triggers.matches(bonus, event, state, state,
		{"unit_id": "captain", "ability_id": "grunt_strike"}), "wrong action owner is rejected")
	var bomber_one := {"id": "one", "character_id": "bomber", "hp": 1}
	var bomber_two := {"id": "two", "character_id": "bomber", "hp": 1}
	var bomb_state := {"units": [bomber_one, bomber_two]}
	var blast := {"type": "death_blast", "unit_id": "one"}
	var chain := {"type": "chain_blast", "actor_field": "unit_id"}
	var later := [{"type": "damage", "source_id": "one", "target_id": "two", "amount": 1},
		{"type": "death_blast", "unit_id": "two"}]
	_check(Triggers.matches(chain, blast, bomb_state, bomb_state, {}, {}, later), "blast causes another bomber to detonate")
	_check(not Triggers.matches(chain, blast, bomb_state, bomb_state, {}, {}, later.slice(0, 1)), "damage alone is not a chain")
	var swift := {"id": "swift", "character_id": "bandit_swift", "hp": 1}
	var step := {"type": "swift_quick_step", "actor_field": "unit_id"}
	var movement := {"type": "move", "unit_id": "swift"}
	var two_cells := {"unit_id": "swift", "ability_id": "move", "source_cell": Vector2i.ZERO,
		"actor_cell": Vector2i(2, 0)}
	var movement_bonus := [{"type": "ally_death_bonus", "unit_id": "swift", "stat": "movement", "amount": 1}]
	_check(Triggers.matches(step, movement, {"units": [swift]}, {}, two_cells, {}, [], movement_bonus),
		"boosted two-cell movement follows a prior sibling bonus")
	_check(not Triggers.matches(step, movement, {"units": [swift]}, {}, two_cells), "ordinary movement is not boosted")
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: stock cast trigger semantics")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
