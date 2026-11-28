extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtest_combat_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
class RuntimeCatalog:
	extends RefCounted
	var defs: Dictionary

var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_friar()
	_test_twins()
	if failures.is_empty():
		print("PASS: road playtest combat traits")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i, hp: int, maximum := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": hp, "max_hp": maximum, "statuses": {}}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _state(traits: Array) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	var state: Dictionary = rules.new_game(defs, "fixture")
	# Runtime-only traits let these tests exercise the combat hooks before
	# catalog validation learns the proposed schema.
	defs.characters.harpooner.traits = traits
	var runtime_catalog := RuntimeCatalog.new()
	runtime_catalog.defs = defs
	state.catalog = runtime_catalog
	state.terrain = []
	state.obstacles = []
	state.units = [
		_unit("healer", "healer", Vector2i(3, 4), 8),
		_unit("subject", "harpooner", Vector2i(4, 4), 10),
		_unit("civilian", "ferryman", Vector2i(10, 10), 10)
	]
	return state


func _forecast(state: Dictionary, actor: String, ability: String, target: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, actor, ability, target)
	_check(plan.get("valid", false), ability + ": hit is legal")
	_check(state == before and plan == rules.preview(state, actor, ability, target),
		ability + ": forecast is pure and repeatable")
	if plan.get("valid", false):
		_check(rules.apply_plan(state, plan) == plan.result and state == before,
			ability + ": commit matches forecast without mutating input")
	return plan


func _test_friar() -> void:
	var state := _state([{"kind": "death_heal", "amount": 2}])
	_entity(state, "subject").hp = 1
	state.units.append(_unit("wounded", "harpooner", Vector2i(8, 8), 5))
	state.units.append(_unit("nearly_full", "harpooner", Vector2i(8, 9), 9))
	state.units.append(_unit("full", "harpooner", Vector2i(9, 8), 10))
	state.units.append(_unit("corpse", "harpooner", Vector2i(9, 9), 0))
	var plan := _forecast(state, "healer", "healer_bonk", "subject")
	if not plan.get("valid", false):
		return
	var result: Dictionary = plan.result
	_check(_entity(result, "subject").hp == 0, "Friar stays dead")
	_check(_entity(result, "wounded").hp == 7, "Friar heals a surviving wounded enemy for two")
	_check(_entity(result, "nearly_full").hp == 10, "Friar healing is capped at maximum HP")
	_check(_entity(result, "full").hp == 10 and _entity(result, "corpse").hp == 0,
		"Friar does not over-heal full allies or revive corpses")
	_check(_entity(result, "healer").hp == 8, "Friar does not heal the opposing hero")


func _test_twins() -> void:
	for condition in ["full", "wounded"]:
		var state := _state([{"kind": "health_damage_bonus", "condition": condition, "damage": 3}])
		var full := _forecast(state, "subject", "enemy_attack", "healer")
		var injured := state.duplicate(true)
		_entity(injured, "subject").hp = 9
		var wounded := _forecast(injured, "subject", "enemy_attack", "healer")
		if not full.get("valid", false) or not wounded.get("valid", false):
			continue
		var full_damage: int = 8 - _entity(full.result, "healer").hp
		var wounded_damage: int = 8 - _entity(wounded.result, "healer").hp
		_check(full_damage == (5 if condition == "full" else 2),
			condition + " twin applies bonus only at full health when configured")
		_check(wounded_damage == (5 if condition == "wounded" else 2),
			condition + " twin applies bonus only while wounded when configured")
		_entity(injured, "subject").hp = 0
		var dead: Dictionary = rules.preview(injured, "subject", "enemy_attack", "healer")
		_check(not dead.get("valid", false), condition + " twin cannot attack while dead")
