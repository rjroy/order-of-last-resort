extends SceneTree

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_threat_order_rules_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	defs.behaviors.test_knight_threat = {
		"handler": "threat",
		"params": {"ability": "knight_push", "move_ability": "move",
			"pursue_range": 5, "fallback_teams": ["enemies"], "taunt_status": "taunt"},
	}
	defs.orders.test_knight_threat = {"label": "Test threat"}
	var habits: Dictionary = Catalog.profile(defs, "knight").habits.duplicate()
	habits.test_knight_threat = "test_knight_threat"
	defs.characters.knight.habits = habits
	defs.characters.knight.default_order = "test_knight_threat"
	defs.characters.test_enemy = defs.characters.grunt.duplicate(true)
	defs.characters.test_enemy.behavior = "hold"
	var healer_habits: Dictionary = Catalog.profile(defs, "healer").habits.duplicate()
	healer_habits.order_hold = "hold"
	defs.characters.healer.habits = healer_habits
	defs.characters.healer.default_order = "order_hold"
	defs.encounters.smith_threat_fixture = {
		"board": "road", "seed": 7, "party_slots": [[0, 0], [2, 2], [0, 3]],
		"placements": [
			{"id": "near_foe", "character": "test_enemy", "at": [2, 3]},
			{"id": "pull_foe", "character": "test_enemy", "at": [4, 2]},
		],
	}
	defs.missions.smith_threat_fixture = defs.missions.shield_wall.duplicate(true)
	defs.missions.smith_threat_fixture.encounter = "smith_threat_fixture"
	defs.missions.smith_threat_fixture.erase("default_party")
	var errors: PackedStringArray = Catalog.validate(defs)
	_check(errors.is_empty(), "Custom threat catalog validates: " + str(errors))
	if errors.is_empty():
		_test_round(defs)
	if failures.is_empty():
		print("PASS: fitted Knight custom threat order")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _test_round(defs: Dictionary) -> void:
	var rules := Rules.new()
	var state: Dictionary = Rules.open_mission(defs, "smith_threat_fixture", ["blacksmith", "knight", "healer"])
	if state.is_empty():
		_check(false, "Validated custom fixture opens")
		return
	state.orders.blacksmith = "order_hold"
	_unit(state, "knight").fitted_by = "blacksmith"
	var choices: Array = rules.targets(state, "knight", "knight_push")
	_check(choices.any(func(choice: Dictionary): return choice.id == "pull_foe")
		and not choices.any(func(choice: Dictionary): return choice.id == "near_foe"),
		"Fitted Push offers ranged foe, not adjacent ordinary-Push foe")
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(state == before and plan.get("valid", false), "Forecast is valid and leaves opening unchanged")
	var result: Dictionary = plan.get("result", {})
	_check(_unit(result, "pull_foe").position == Vector2i(3, 2),
		"Standing threat chooses legal Pull and moves ranged foe one tile closer")
	_check(_unit(result, "near_foe").position == Vector2i(2, 3),
		"Standing threat does not choose the adjacent base-Push foe")
	_check(not _unit(result, "knight").has("fitted_by"), "Successful Pull spends the fitting")
	_check(not plan.get("events", []).any(func(event: Dictionary):
		return event.get("type") == "wait" and event.get("unit_id") == "knight" \
			and event.get("ability_id") == "knight_push"),
		"Standing threat does not waste Knight's turn on an invalid base target")
	var committed: Dictionary = rules.commit_round(state, plan)
	_check(committed == result and state == before, "Commit matches forecast without mutating its source")


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
