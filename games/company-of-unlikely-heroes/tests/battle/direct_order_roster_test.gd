extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/direct_order_roster_test.gd
var rules = preload("res://rules/rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(
		preload("res://content/catalog.gd").read_default())
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.encounters.test_escort.deadline = 100
	# Controlled equipped kits and standing habits, independent of guild persistence.
	defs.characters.rogue.abilities.append("rogue_tripwire")
	defs.characters.rogue.habits["order_rogue_tripwire"] = "guild_rogue_tripwire"
	defs.characters.necromancer.abilities.append("necro_grave_bell")
	defs.characters.necromancer.habits["order_necro_bell"] = "guild_necro_bell"
	defs.abilities.healing_sonnet.params.damage = 3
	_dodge()
	_tripwire()
	_bell()
	_melody()
	_stage()
	if failures.is_empty():
		print("PASS: direct order roster")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp := 20, upgrades := {}) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos, "hp": hp,
		"max_hp": 20, "statuses": {}, "upgrades": upgrades.duplicate(true)}


func _state(actor: String, order: String, units: Array) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [_unit("actor", actor, Vector2i(1, 3))] + units + [
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	state.orders = {"actor": order, "ally": "order_cautious"}
	state.overrides = {}
	state.rng_state = 12345
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return state


func _find(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _round(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), label + ": valid forecast")
	_check(state == before and plan == rules.preview_round(state), label + ": stable, read-only forecast")
	if plan.get("valid", false):
		_check(rules.commit_round(state, plan) == plan.result, label + ": commit matches forecast")
	return plan


func _discover(state: Dictionary, ability: String, included: Array, excluded: Array) -> void:
	var before: Dictionary = rules.state_before_action(state, "actor")
	var form: Dictionary = rules.command_ability(before, "actor", ability)
	_check(form.get("targeting", {}).get("kind") == "entity", ability + ": direct form selects an entity")
	var ids := []
	for choice in rules.targets(before, "actor", ability):
		ids.append(choice.get("id"))
	for id in included:
		_check(id in ids, ability + ": offers " + id)
	for id in excluded:
		_check(id not in ids, ability + ": excludes " + id)


func _direct(state: Dictionary, ability: String, target: String) -> Dictionary:
	var before: Dictionary = rules.state_before_action(state, "actor")
	var action: Dictionary = rules.preview(before, "actor", ability, target, true)
	_check(action.get("valid", false), ability + ": chosen target is actionable")
	var staged: Dictionary = rules.choose_manual(state, "actor", ability, target)
	_check(staged.overrides.get("actor", {}).get("target_id") == target,
		ability + ": stages chosen target")
	return _round(staged, ability + " direct " + target)


func _event(plan: Dictionary, type: String, target: String) -> bool:
	for event in plan.get("events", []):
		if event.get("type") == type and event.get("target_id") == target:
			return true
	return false


func _no_substitute(state: Dictionary, ability: String, target: String, other: String) -> void:
	var staged: Dictionary = rules.choose_manual(state, "actor", ability, target)
	if not staged.overrides.has("actor"):
		_check(false, ability + ": invalidation fixture requires a staged choice")
		return
	_find(staged, target).hp = 0
	var plan := _round(staged, ability + " invalidated")
	if plan.get("valid", false):
		_check(not _event(plan, "performance", other) and not _event(plan, "status", other)
			and not _event(plan, "repel", other) and not _event(plan, "swap", other)
			and _find(plan.result, other).position == _find(state, other).position
			and _find(plan.result, other).hp == _find(state, other).hp,
			ability + ": invalidated choice does not select another target")
		var explained := false
		for event in plan.events:
			if event.get("unit_id") == "actor" and event.get("type") == "wait":
				explained = true
		_check(explained, ability + ": invalidated choice is explained")


func _dodge() -> void:
	var state := _state("rogue", "order_retreat", [
		_unit("near", "harpooner", Vector2i(2, 3)),
		_unit("far", "harpooner", Vector2i(7, 3)),
		_unit("dead", "harpooner", Vector2i(8, 3), 0)])
	_discover(state, "rogue_confusing_dodge", ["near", "far"], ["actor", "dead"])
	var standing_action: Dictionary = rules.preview(state, "actor", "rogue_confusing_dodge")
	_check(standing_action.get("valid", false), "Dodge autonomous fixture is legal")
	if standing_action.get("valid", false):
		_check(_find(standing_action.result, "actor").position == Vector2i(10, 10),
			"Dodge autonomous rule chooses the furthest living character")
	var plan := _direct(state, "rogue_confusing_dodge", "near")
	if plan.get("valid", false):
		_check(_find(plan.result, "actor").position == Vector2i(2, 3)
			and _find(plan.result, "near").position == Vector2i(1, 3),
			"Dodge swaps the chosen nearer character")
	_no_substitute(state, "rogue_confusing_dodge", "near", "far")


func _tripwire() -> void:
	var state := _state("rogue", "order_rogue_tripwire", [
		_unit("near", "harpooner", Vector2i(2, 3)),
		_unit("far", "harpooner", Vector2i(3, 3)),
		_unit("outside", "harpooner", Vector2i(5, 3)),
		_unit("ally", "knight", Vector2i(1, 5)),
		_unit("dead", "harpooner", Vector2i(1, 2), 0)])
	_discover(state, "rogue_tripwire", ["near", "far"], ["actor", "outside", "ally", "dead"])
	var standing := _round(state, "standing Tripwire")
	if standing.get("valid", false):
		_check(_event(standing, "status", "near") and not _event(standing, "status", "far"),
			"standing Tripwire chooses nearest")
	var plan := _direct(state, "rogue_tripwire", "far")
	if plan.get("valid", false):
		_check(_event(plan, "status", "far") and not _event(plan, "status", "near")
			and _find(plan.result, "far").statuses.has("tripwire_tangled"),
			"Tripwire holds the chosen second opponent")
	_no_substitute(state, "rogue_tripwire", "far", "near")


func _bell() -> void:
	var state := _state("necromancer", "order_necro_bell", [
		_unit("near", "harpooner", Vector2i(2, 3)),
		_unit("ally", "knight", Vector2i(1, 5)),
		_unit("blocked", "harpooner", Vector2i(4, 3)),
		_unit("edge", "harpooner", Vector2i(11, 3)),
		_unit("dead", "harpooner", Vector2i(3, 5), 0)])
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(5, 3),
		"hp": 20, "max_hp": 20, "statuses": {}}]
	_discover(state, "necro_grave_bell", ["near", "ally"], ["actor", "blocked", "edge", "dead", "crate"])
	var standing := _round(state, "standing Grave Bell")
	if standing.get("valid", false):
		_check(_event(standing, "repel", "near") and _find(standing.result, "near").position == Vector2i(3, 3),
			"standing Grave Bell repels nearest into open tile")
	var plan := _direct(state, "necro_grave_bell", "ally")
	if plan.get("valid", false):
		_check(_event(plan, "repel", "ally") and _find(plan.result, "ally").position == Vector2i(1, 6)
			and _find(plan.result, "near").position == Vector2i(2, 3),
			"Grave Bell carries the chosen ally's forced destination")
	_no_substitute(state, "necro_grave_bell", "ally", "near")


func _melody() -> void:
	var state := _state("bard", "order_inspiring_melody", [
		_unit("near", "harpooner", Vector2i(2, 3)),
		_unit("far", "harpooner", Vector2i(7, 3)),
		_unit("ally", "knight", Vector2i(1, 5)),
		_unit("dead", "harpooner", Vector2i(3, 5), 0)])
	_discover(state, "inspiring_melody", ["near", "far"], ["actor", "ally", "dead", "civilian"])
	var standing := _round(state, "standing Melody")
	if not standing.get("valid", false):
		return
	var selected := "near" if _event(standing, "performance", "near") else "far"
	_check(_event(standing, "performance", selected), "standing Melody picks one seeded listener")
	var target := "far" if selected == "near" else "near"
	var plan := _direct(state, "inspiring_melody", target)
	if plan.get("valid", false):
		_check(_event(plan, "performance", target), "Melody names the chosen listener")
		var recovered := false
		for event in plan.events:
			if event.get("type") == "recover" and event.get("unit_id") == target:
				recovered = true
		_check(recovered, "chosen listener loses its turn to laughter")
	_no_substitute(state, "inspiring_melody", target, selected)


func _stage() -> void:
	var state := _state("bard", "order_hold", [
		_unit("solo", "harpooner", Vector2i(3, 3)),
		_unit("far", "harpooner", Vector2i(7, 3)),
		_unit("neighbor", "harpooner", Vector2i(7, 4)),
		_unit("ally", "knight", Vector2i(6, 3)),
		_unit("dead", "harpooner", Vector2i(8, 3), 0)])
	_find(state, "actor").upgrades = {"bard_house_lights": 1}
	_discover(state, "bard_take_the_stage", ["solo", "far", "neighbor"], ["actor", "ally", "dead", "civilian"])
	var automatic: Dictionary = rules.preview(state, "actor", "bard_take_the_stage")
	_check(automatic.get("valid", false), "Take the Stage autonomous fixture is legal")
	if not automatic.get("valid", false):
		return
	var automatic_solo: bool = _find(automatic.result, "solo").hp == 17
	_check(automatic_solo != (_find(automatic.result, "far").hp == 17),
		"Take the Stage autonomous fixture chooses one distinct listener group")
	var target := "far" if automatic_solo else "solo"
	var plan := _direct(state, "bard_take_the_stage", target)
	if plan.get("valid", false):
		var cluster_hp := 17 if target == "far" else 20
		var solo_hp := 17 if target == "solo" else 20
		_check(_find(plan.result, "far").hp == cluster_hp and _find(plan.result, "neighbor").hp == cluster_hp
			and _find(plan.result, "solo").hp == solo_hp and _find(plan.result, "ally").hp == 20,
			"Take the Stage damages chosen listener and adjacent opponent, not others")
	if target != "far":
		var cluster := _direct(state, "bard_take_the_stage", "far")
		if cluster.get("valid", false):
			_check(_find(cluster.result, "far").hp == 17 and _find(cluster.result, "neighbor").hp == 17
				and _find(cluster.result, "solo").hp == 20 and _find(cluster.result, "ally").hp == 20,
				"Take the Stage retains its opponent-only area effect")
	_no_substitute(state, "bard_take_the_stage", target, "solo" if target == "far" else "far")
