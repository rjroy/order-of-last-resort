extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtest_ranged_test.gd
# Test-owned ability: the restrictions are opt-in, not changes to all arrows.
var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_minimum_range()
	_test_crate_cover()
	_test_autonomous_selection()
	_test_pursuit_to_clear_lane()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: road playtest ranged mechanics")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": 10, "max_hp": 10, "statuses": {}}


func _state(shot_range := 4) -> Dictionary:
	var defs: Dictionary = preload("res://tests/fixtures/rules_catalog.gd").definitions()
	defs.missions.fixture.objective = {
		"handler": "defeat_all", "team": "enemies", "text": "Defeat the foe.",
		"victory_text": "Victory", "defeat_text": "Defeat", "victory_event": "Victory"}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Defeat"}]
	defs.abilities.longbow = {
		"label": "Longbow", "help": "Deal two damage.", "handler": "attack", "params": {"damage": 2},
		"targeting": {"kind": "entity", "range": shot_range, "min_range": 2,
			"straight_line_clear": true, "teams": ["heroes"]}}
	defs.abilities.ordinary_bow = defs.abilities.longbow.duplicate(true)
	defs.abilities.ordinary_bow.targeting.erase("min_range")
	defs.abilities.ordinary_bow.targeting.erase("straight_line_clear")
	defs.characters.bowman = {"class": "enemy", "label": "Bowman",
		"abilities": ["move", "longbow", "ordinary_bow"], "behavior": "longbow_threat"}
	defs.behaviors.longbow_threat = defs.behaviors.threat.duplicate(true)
	defs.behaviors.longbow_threat.params.ability = "longbow"
	var state: Dictionary = rules.new_game(defs, "fixture")
	if state.is_empty():
		_check(false, "controlled fixture opens")
		return {}
	state.units = [
		_unit("bowman", "bowman", Vector2i(2, 2)),
		_unit("near", "healer", Vector2i(3, 2)),
		_unit("far", "knight", Vector2i(5, 2)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	state.obstacles = []
	state.terrain = []
	state.orders = {}
	state.overrides = {}
	state.rng_state = 12345
	return state


func _entity(state: Dictionary, id: String) -> Dictionary:
	for entity in state.get("units", []) + state.get("obstacles", []):
		if entity.id == id:
			return entity
	return {}


func _ids(state: Dictionary, ability: String) -> Array:
	return rules.targets(state, "bowman", ability).map(func(choice: Dictionary) -> String:
		return choice.id)


func _action(state: Dictionary, ability: String, target: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "bowman", ability, target)
	_check(state == before and plan == rules.preview(state, "bowman", ability, target),
		ability + ": action forecast is pure and repeatable")
	if plan.get("valid", false):
		_check(rules.apply_plan(state, plan) == plan.result and state == before,
			ability + ": commit matches forecast")
	return plan


func _test_minimum_range() -> void:
	var state := _state()
	if state.is_empty():
		return
	var ids := _ids(state, "longbow")
	_check("near" not in ids and "far" in ids,
		"longbow excludes adjacent hero but offers a clear hero at distance three")
	_check(not _action(state, "longbow", "near").get("valid", false),
		"adjacent target cannot bypass the picker")
	var shot := _action(state, "longbow", "far")
	_check(shot.get("valid", false), "clear ranged longbow shot is valid")
	if shot.get("valid", false):
		_check(_entity(shot.result, "far").get("hp") == 8, "longbow deals its authored damage")
	_check("near" in _ids(state, "ordinary_bow")
		and _action(state, "ordinary_bow", "near").get("valid", false),
		"ordinary bow still attacks adjacent targets")
	_entity(state, "far").position = Vector2i(6, 2)
	_check("far" in _ids(state, "longbow"), "maximum range is inclusive")
	_entity(state, "far").position = Vector2i(7, 2)
	_check("far" not in _ids(state, "longbow"), "target beyond maximum range is excluded")


func _test_crate_cover() -> void:
	var state := _state()
	if state.is_empty():
		return
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(4, 2),
		"hp": 1, "max_hp": 1, "statuses": {}}]
	_check("far" not in _ids(state, "longbow"), "intact crate blocks the straight lane")
	_check(not _action(state, "longbow", "far").get("valid", false),
		"blocked target cannot bypass the picker")
	_check("far" in _ids(state, "ordinary_bow")
		and _action(state, "ordinary_bow", "far").get("valid", false),
		"ordinary attacks do not acquire the new cover rule")
	var off_lane := state.duplicate(true)
	_entity(off_lane, "crate").position = Vector2i(4, 3)
	_check("far" in _ids(off_lane, "longbow"), "a crate beside the lane does not block it")
	var strike: Dictionary = rules.preview(state, "near", "healer_bonk", "crate")
	_check(strike.get("valid", false), "adjacent hero can destroy the crate")
	if not strike.get("valid", false):
		return
	_check(rules.apply_plan(state, strike) == strike.result, "crate destruction commits as forecast")
	var broken: Dictionary = strike.result
	_check("far" in _ids(broken, "longbow"), "a destroyed crate no longer blocks the lane")
	var shot := _action(broken, "longbow", "far")
	_check(shot.get("valid", false), "longbow can shoot after cover is destroyed")
	if shot.get("valid", false):
		_check(_entity(shot.result, "far").get("hp") == 8, "uncovered target takes damage")


func _test_autonomous_selection() -> void:
	var state := _state()
	if state.is_empty():
		return
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and state == before and plan == rules.preview_round(state),
		"autonomous round forecast is valid, pure and repeatable")
	if not plan.get("valid", false):
		return
	_check(rules.commit_round(state, plan) == plan.result and state == before,
		"autonomous round commit agrees with forecast")
	_check(_entity(plan.result, "near").get("hp") == 10
		and _entity(plan.result, "far").get("hp") == 8,
		"bowman selects the legal distant hero instead of its adjacent blind spot")


func _test_pursuit_to_clear_lane() -> void:
	var state := _state(5)
	if state.is_empty():
		return
	state.units = [_unit("near", "healer", Vector2i(1, 1)),
		_unit("far", "knight", Vector2i(1, 3)),
		_unit("block_target", "wizard", Vector2i(1, 2)),
		_unit("bowman", "bowman", Vector2i(5, 2))]
	state.party = ["near", "far", "block_target"]
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(3, 2),
		"hp": 10, "max_hp": 10, "statuses": {}}]
	_check(_ids(state, "longbow").is_empty(), "no initial shot has a legal lane")
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and plan == rules.preview_round(state) and state == before,
		"blocked-lane forecast is valid, pure and repeatable")
	if not plan.get("valid", false):
		return
	_check(rules.commit_round(state, plan) == plan.result and state == before,
		"blocked-lane commit matches forecast")
	var position: Vector2i = _entity(plan.result, "bowman").position
	_check(position in [Vector2i(5, 1), Vector2i(5, 3)],
		"blocked bowman steps to an open firing lane instead of holding")
	if position in [Vector2i(5, 1), Vector2i(5, 3)]:
		_check(not _ids(plan.result, "longbow").is_empty(),
			"bowman's step actually opens a legal shot")
