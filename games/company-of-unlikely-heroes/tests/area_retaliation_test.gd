extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/area_retaliation_test.gd
const Catalog = preload("res://content/catalog.gd")
var rules = preload("res://rules.gd").new()
var failures: Array[String] = []
var defs: Dictionary


func _initialize() -> void:
	defs = Catalog.read_default()
	_test_area("skeleton", "wave")
	_test_area("healer", "healer_bonk", "first")
	_test_area("bard", "bard_take_the_stage")
	if failures.is_empty():
		print("PASS: area damage resolves before retaliation")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": hp, "max_hp": hp, "statuses": {}}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _test_area(character: String, ability: String, target := "") -> void:
	var state: Dictionary = rules.new_game(defs, "ferryman")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	var source := _unit("source", character, Vector2i(5, 5), 1)
	if character == "healer":
		source["upgrades"] = {"healer_strong_swing": 1}
	elif character == "bard":
		source["upgrades"] = {"bard_house_lights": 1}
	else:
		source["summoner_id"] = "necromancer"
	var second_position := Vector2i(3, 5) if character == "bard" else Vector2i(6, 5)
	state.units = [
		source,
		_unit("first", "duelist", Vector2i(4, 5), 20),
		_unit("second", "duelist", second_position, 20),
		_unit("necromancer", "necromancer", Vector2i(1, 1), 10),
		_unit("civilian", "ferryman", Vector2i(10, 10), 10)
	]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	state.rng_state = 12345
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "source", ability, target)
	_check(plan.get("valid", false), ability + ": authored action is legal")
	_check(state == before and plan == rules.preview(state, "source", ability, target),
		ability + ": forecast is pure and repeatable")
	if not plan.get("valid", false):
		return
	_check(rules.apply_plan(state, plan) == plan.result and state == before,
		ability + ": commit matches forecast without mutating input")
	var hits := {}
	var retaliation_indices := []
	var damage_to_source := 0
	for index in range(plan.events.size()):
		var event: Dictionary = plan.events[index]
		if event.get("type") == "damage" and event.get("source_id") == "source" \
				and event.get("target_id") in ["first", "second"]:
			var id: String = event.target_id
			if not hits.has(id):
				hits[id] = []
			hits[id].append(index)
		if event.get("type") == "retaliate" and event.get("target_id") == "source":
			retaliation_indices.append(index)
		if event.get("type") == "damage" and event.get("target_id") == "source":
			damage_to_source += 1
	for id in ["first", "second"]:
		_check(hits.get(id, []).size() == 1 and _entity(plan.result, id).get("hp", 20) < 20,
			ability + ": " + id + " receives exactly one intended hit")
		if hits.has(id) and not retaliation_indices.is_empty():
			_check(hits[id][0] < retaliation_indices[0],
				ability + ": " + id + " is hit before retaliation")
	if character == "bard" and hits.has("first") and hits.has("second"):
		_check(hits.first[0] < hits.second[0],
			ability + ": fixed seed selects the adjacent first duelist as listener")
	_check(retaliation_indices.size() == 1,
		ability + ": only one duelist retaliates; the other cannot counter a defeated source")
	_check(damage_to_source == 1 and _entity(plan.result, "source").get("hp", -1) == 0,
		ability + ": the 1 HP source is defeated exactly once")
