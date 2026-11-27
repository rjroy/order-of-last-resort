extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtest_strikes_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_followthrough()
	_test_redirect_keeps_line()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: road playtest strikes")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": 10, "max_hp": 10, "statuses": {}}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _state() -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.abilities.spear = defs.abilities.enemy_attack.duplicate(true)
	defs.abilities.spear.params.spear_followthrough = true
	defs.abilities.spear.targeting.teams = ["heroes"]
	defs.classes.enemy.abilities.append("spear")
	defs.statuses.aura.params.range = 0
	var state: Dictionary = rules.new_game(defs, "fixture")
	if state.is_empty():
		_check(false, "test-owned spear fixture opens")
		return {}
	state.units = [
		_unit("spearman", "harpooner", Vector2i(4, 4)),
		_unit("front", "healer", Vector2i(5, 4)),
		_unit("front_companion", "knight", Vector2i(5, 4)),
		_unit("rear_hero", "wizard", Vector2i(6, 4)),
		_unit("rear_ally", "harpooner", Vector2i(6, 4)),
		_unit("off_line", "healer", Vector2i(5, 5)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	state.obstacles = []
	state.terrain = []
	state.orders = {}
	state.overrides = {}
	return state


func _attack(state: Dictionary, ability: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "spearman", ability, "front")
	_check(plan.get("valid", false), ability + ": chosen adjacent target is legal")
	_check(state == before and plan == rules.preview(state, "spearman", ability, "front"),
		ability + ": forecast is pure and repeatable")
	if plan.get("valid", false):
		_check(rules.apply_plan(state, plan) == plan.result and state == before,
			ability + ": commit matches forecast")
	return plan


func _damage_targets(plan: Dictionary) -> Array:
	var targets := []
	for event in plan.get("events", []):
		if event.get("type") == "damage" and event.get("source_id") == "spearman":
			targets.append(event.get("target_id"))
	return targets


func _test_followthrough() -> void:
	var state := _state()
	if state.is_empty():
		return
	var ordinary := _attack(state, "enemy_attack")
	if ordinary.get("valid", false):
		_check(_damage_targets(ordinary) == ["front"], "ordinary attacks do not follow through")
	var spear := _attack(state, "spear")
	if not spear.get("valid", false):
		return
	var targets := _damage_targets(spear)
	_check(targets.size() == 3 and targets[0] == "front" and "rear_hero" in targets
		and "rear_ally" in targets, "forecast reports the primary then both occupants behind it")
	for id in ["front", "rear_hero", "rear_ally"]:
		_check(_entity(spear.result, id).hp == 8, id + " takes the authored two damage")
	for id in ["front_companion", "off_line"]:
		_check(_entity(spear.result, id).hp == 10, id + " is not in the follow-through cell")


func _test_redirect_keeps_line() -> void:
	var state := _state()
	if state.is_empty():
		return
	# Reflection redirects the first blow away from the chosen front cell.
	_entity(state, "front").statuses.aura = {"source_id": "front"}
	var spear := _attack(state, "spear")
	if not spear.get("valid", false):
		return
	var targets := _damage_targets(spear)
	_check("front" not in targets and "spearman" in targets,
		"primary blow follows the normal reflection path")
	_check("rear_hero" in targets and "rear_ally" in targets,
		"reflection does not turn the intended follow-through line")
