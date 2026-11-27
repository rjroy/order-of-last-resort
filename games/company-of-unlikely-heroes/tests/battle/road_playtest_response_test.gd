extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtest_response_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
class RuntimeCatalog:
	extends RefCounted
	var defs: Dictionary

var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_pursuit()
	_test_blocked_and_dead_damager()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: road playtest response traits")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": 10, "max_hp": 10, "statuses": {}}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _state(enabled: bool) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.abilities.test_shot = {"label": "Shot", "help": "One damage", "handler": "attack",
		"params": {"damage": 1}, "targeting": {"kind": "entity", "range": 4,
			"teams": ["enemies"], "capabilities": ["damageable"]}}
	defs.characters.wizard.abilities = ["move", "test_shot"]
	defs.characters.healer.abilities = ["move", "test_shot"]
	var state: Dictionary = rules.new_game(defs, "fixture")
	if state.is_empty():
		_check(false, "controlled fixture opens")
		return {}
	if enabled:
		defs.characters.harpooner.traits = [{"kind": "last_damager_pursuit"}]
	var catalog := RuntimeCatalog.new()
	catalog.defs = defs
	state.catalog = catalog
	state.objective.handler = "defeat_all"
	state.objective.team = "enemies"
	state.terrain = []
	state.obstacles = []
	state.orders = {}
	state.overrides = {}
	state.units = [
		_unit("near", "healer", Vector2i(4, 5)),
		_unit("far", "wizard", Vector2i(1, 4)),
		_unit("hammer", "harpooner", Vector2i(4, 4)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	return state


func _shot(state: Dictionary, actor := "far") -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, actor, "test_shot", "hammer")
	_check(plan.get("valid", false), "ranged hit is legal")
	_check(state == before and plan == rules.preview(state, actor, "test_shot", "hammer"),
		"shot forecast is pure and repeatable")
	if plan.get("valid", false):
		_check(rules.apply_plan(state, plan) == plan.result and state == before,
			"shot commit matches forecast")
		return plan.result
	return {}


func _round(state: Dictionary) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), "autonomous forecast is valid")
	_check(state == before and plan == rules.preview_round(state),
		"autonomous forecast is pure and repeatable")
	if plan.get("valid", false):
		_check(rules.commit_round(state, plan) == plan.result and state == before,
			"autonomous commit matches forecast")
		return plan.result
	return {}


func _test_pursuit() -> void:
	for enabled in [false, true]:
		var state := _state(enabled)
		if state.is_empty():
			continue
		var first := _shot(state, "near")
		if first.is_empty():
			continue
		var struck := _shot(first)
		if struck.is_empty():
			continue
		_check(_entity(struck, "hammer").hp == 8, "both shots cause actual HP loss")
		var result := _round(struck)
		if result.is_empty():
			continue
		if enabled:
			_check(_entity(result, "near").hp == 10 and _entity(result, "hammer").position != Vector2i(4, 4),
				"last damager draws opted-in hammer away from nearer attack target")
		else:
			_check(_entity(result, "near").hp == 8 and _entity(result, "hammer").position == Vector2i(4, 4),
				"ordinary threat still attacks the nearer hero after a ranged hit")


func _test_blocked_and_dead_damager() -> void:
	var state := _state(true)
	if state.is_empty():
		return
	_entity(state, "hammer").statuses.padding = {"source_id": "hammer", "amount": 1}
	var blocked := _shot(state)
	if not blocked.is_empty():
		_check(_entity(blocked, "hammer").hp == 10, "padding blocks the entire hit")
		var result := _round(blocked)
		if not result.is_empty():
			_check(_entity(result, "near").hp == 8,
				"fully blocked hit does not redirect pursuit")
	var struck := _shot(_state(true))
	if not struck.is_empty():
		_entity(struck, "far").hp = 0
		var result := _round(struck)
		if not result.is_empty():
			_check(_entity(result, "near").hp == 8,
				"dead last damager does not keep the hammer from attacking a living hero")
