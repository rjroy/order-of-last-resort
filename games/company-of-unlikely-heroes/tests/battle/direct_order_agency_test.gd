extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/direct_order_agency_test.gd
var rules = preload("res://rules/rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(
		preload("res://content/catalog.gd").read_default())
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.encounters.test_escort.deadline = 100
	# The assertions own effect quantities rather than stock balance.
	defs.abilities.wizard_blast.params.damage = 4
	defs.abilities.healer_heal.params.amount = 3
	defs.abilities.healer_heal.targeting.range = 5
	defs.abilities.healer_heal.params.prefer_wounded_self = true
	defs.abilities.healing_sonnet.params.damage = 1
	_blast()
	_heal()
	_song()
	if failures.is_empty():
		print("PASS: direct order target agency")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i, hp := 20) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": hp, "max_hp": 20, "statuses": {}}


func _state(actor: String, order: String) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.units = [
		_unit("actor", actor, Vector2i(1, 1)),
		_unit("near", "harpooner", Vector2i(2, 1)),
		_unit("far", "harpooner", Vector2i(5, 1)),
		_unit("ally", "knight", Vector2i(3, 2), 10),
		_unit("other", "knight", Vector2i(5, 2), 10),
		_unit("dead", "harpooner", Vector2i(6, 1), 0),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	state.obstacles = [
		{"id": "crate", "object_id": "crate", "position": Vector2i(4, 1),
			"hp": 20, "max_hp": 20, "statuses": {}},
		{"id": "broken", "object_id": "crate", "position": Vector2i(7, 1),
			"hp": 0, "max_hp": 20, "statuses": {}}]
	state.orders = {"actor": order, "ally": "order_cautious", "other": "order_cautious"}
	state.overrides = {}
	state.rng_state = 12345
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return state


func _entity(state: Dictionary, id: String) -> Dictionary:
	for entity in state.units + state.obstacles:
		if entity.id == id:
			return entity
	return {}


func _forecast(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), label + ": round forecast valid")
	_check(state == before and plan == rules.preview_round(state), label + ": forecast is stable and read-only")
	if plan.get("valid", false):
		_check(rules.commit_round(state, plan) == plan.result, label + ": commit agrees with forecast")
	return plan


func _discovery(state: Dictionary, ability: String, included: Array, excluded: Array) -> void:
	var before: Dictionary = rules.state_before_action(state, "actor")
	var form: Dictionary = rules.command_ability(before, "actor", ability)
	_check(form.get("targeting", {}).get("kind") == "entity", ability + ": effective Direct form aims at an entity")
	var ids := []
	for target in rules.targets(before, "actor", ability):
		ids.append(target.get("id"))
	for id in included:
		_check(id in ids, ability + ": offers legal target " + id)
	for id in excluded:
		_check(id not in ids, ability + ": excludes illegal target " + id)


func _direct(state: Dictionary, ability: String, target: String, amount: int) -> void:
	var before: Dictionary = rules.state_before_action(state, "actor")
	var action: Dictionary = rules.preview(before, "actor", ability, target, true)
	_check(action.get("valid", false), ability + ": direct action preview accepts " + target)
	if action.get("valid", false):
		_check(int(_entity(action.result, target).get("hp", -100))
			== int(_entity(before, target).get("hp", -100)) + amount,
			ability + ": direct action preview honors " + target)
	var staged: Dictionary = rules.choose_manual(state, "actor", ability, target)
	var override: Dictionary = staged.overrides.get("actor", {})
	_check(override.get("target_id") == target, ability + ": stages chosen " + target)
	# Check the one-command boundary independently of whether the chosen target works yet.
	var second: Dictionary = rules.choose_manual(staged, "ally", "move", "0,0")
	if not override.is_empty():
		_check(second.overrides == staged.overrides, ability + ": another hero cannot add a second override")
	var plan := _forecast(staged, ability + " direct " + target)
	if plan.get("valid", false):
		var original := int(_entity(state, target).get("hp", -100))
		_check(int(_entity(plan.result, target).get("hp", -100)) == original + amount,
			ability + ": forecast honors chosen " + target)


func _blast() -> void:
	var state := _state("wizard", "order_blast")
	_discovery(state, "wizard_blast", ["near", "far", "ally", "crate"], ["actor", "dead", "broken"])
	var standing := _forecast(state, "standing Blast")
	if standing.get("valid", false):
		_check(_entity(standing.result, "near").hp == 16 and _entity(standing.result, "far").hp == 20,
			"standing Blast still hits nearest")
	for target in ["far", "ally", "crate"]:
		_direct(state, "wizard_blast", target, -4)
	_invalidated(state, "wizard_blast", "far", "near")
	_earlier_turn_invalidates_blast(state)


func _earlier_turn_invalidates_blast(state: Dictionary) -> void:
	var changed := state.duplicate(true)
	changed.units.push_front(_unit("earlier", "wizard", Vector2i(6, 1)))
	changed.orders["earlier"] = "order_cautious"
	_entity(changed, "far").hp = 4
	var before: Dictionary = rules.state_before_action(changed, "actor")
	_check(rules.preview(before, "actor", "wizard_blast", "far", true).get("valid", false),
		"Blast can aim at the living target before changing the earlier Standing Order")
	var staged: Dictionary = rules.choose_manual(changed, "actor", "wizard_blast", "far")
	var reordered: Dictionary = rules.set_order(staged, "earlier", "order_blast")
	_check(reordered.overrides == staged.overrides and not reordered.overrides.is_empty(),
		"Changing the earlier Standing Order keeps the staged Blast target")
	_check(_entity(reordered, "far").hp == 4, "Target is still alive when the round begins")
	var plan := _forecast(reordered, "Blast invalidated by earlier turn")
	if not plan.get("valid", false):
		return
	_check(_entity(plan.result, "far").hp == 0 and _entity(plan.result, "near").hp == 20,
		"Earlier Standing Blast kills the target; Direct Blast does not hit the next candidate")
	_check(plan.events.any(func(event: Dictionary) -> bool:
		return event.get("unit_id") == "actor" and event.get("type") == "wait" \
			and event.get("target_id") == "far" and "no longer a legal target" in event.get("text", "")),
		"Forecast names the invalidated Direct Blast target")


func _heal() -> void:
	var state := _state("healer", "order_support")
	_entity(state, "actor").hp = 10
	_discovery(state, "healer_heal", ["actor", "ally", "other"], ["near", "dead", "crate", "civilian"])
	var standing := _forecast(state, "standing Heal wounded self")
	if standing.get("valid", false):
		_check(_entity(standing.result, "actor").hp == 13 and _entity(standing.result, "other").hp == 10,
			"standing Heal still prefers wounded self")
	_direct(state, "healer_heal", "other", 3)
	var full := state.duplicate(true)
	_entity(full, "actor").hp = 20
	var nearest := _forecast(full, "standing Heal full self")
	if nearest.get("valid", false):
		_check(_entity(nearest.result, "ally").hp == 13 and _entity(nearest.result, "other").hp == 10,
			"standing Heal still chooses nearest ally when self is full")
	_direct(full, "healer_heal", "other", 3)


func _song() -> void:
	var state := _state("bard", "order_healing_sonnet")
	_discovery(state, "healing_sonnet", ["near", "far"], ["actor", "ally", "dead", "crate", "civilian"])
	var standing := _forecast(state, "standing Sonnet seeded listener")
	if not standing.get("valid", false):
		return
	var near_hp: int = _entity(standing.result, "near").hp
	var far_hp: int = _entity(standing.result, "far").hp
	_check((near_hp == 19 and far_hp == 20) or (near_hp == 20 and far_hp == 19),
		"standing Sonnet chooses exactly one seeded opponent")
	if near_hp == 19 or far_hp == 19:
		_direct(state, "healing_sonnet", "far" if near_hp == 19 else "near", -1)


func _invalidated(state: Dictionary, ability: String, chosen: String, default_target: String) -> void:
	var missing: Dictionary = rules.choose_manual(state, "actor", ability, "")
	if missing.overrides.has("actor"):
		var missing_plan := _forecast(missing, ability + " missing target")
		if missing_plan.get("valid", false):
			_check(_entity(missing_plan.result, default_target).hp == 20,
				ability + ": missing target never selects a default")
	var staged: Dictionary = rules.choose_manual(state, "actor", ability, chosen)
	if not staged.overrides.has("actor"):
		_check(false, ability + ": cannot exercise invalidation until chosen target stages")
		return
	var before: Dictionary = rules.state_before_action(staged, "actor")
	var choices: Array = rules.targets(before, "actor", ability)
	_check(choices.any(func(choice): return choice.get("id") == chosen),
		ability + ": invalidated target was legal when staged")
	_check(rules.preview(before, "actor", ability, chosen, true).get("valid", false),
		ability + ": invalidated target was actionable when staged")
	_entity(staged, chosen).hp = 0
	var plan := _forecast(staged, ability + " invalidated target")
	if plan.get("valid", false):
		_check(_entity(plan.result, default_target).hp == 20, ability + ": invalid target never retargets")
		var explained := false
		for event in plan.events:
			if event.get("unit_id") == "actor" and event.get("type") == "wait":
				var text := str(event.get("text", "")).to_lower()
				explained = "valid" in text or "target" in text or "cannot" in text
		_check(explained, ability + ": forecast explains the failed action")
