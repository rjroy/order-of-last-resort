extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/rogue_test.gd
# Integration coverage of authored Rogue behavior with test-owned board geometry.
var failures: Array[String] = []
var rules = preload("res://rules.gd").new()
var catalog = preload("res://content/catalog.gd")
var defs: Dictionary


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(catalog.read_default())
	if not defs.get("characters", {}).has("rogue"):
		_check(false, "Rogue must be authored")
	else:
		_test_dodge()
		_test_wasnt_me()
		_test_redirect_excludes_original_target()
		_test_redirect_fallback_when_alternate_leaves()
		_test_retreat_and_hybrid()
	if failures.is_empty():
		print("PASS: Rogue integration")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i, hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": hp, "max_hp": 10, "statuses": {}}


func _state(units: Array) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = units
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return state


func _unit_at(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _ids(choices: Array) -> Array:
	var result := []
	for choice in choices:
		result.append(choice.get("id", ""))
	return result


func _test_dodge() -> void:
	for other in ["knight", "harpooner"]:
		var state := _state([
			_unit("rogue", "rogue", Vector2i(2, 2)),
			_unit("near", "harpooner", Vector2i(3, 2)),
			_unit("far", other, Vector2i(8, 2)),
			_unit("dead", "knight", Vector2i(11, 11), 0)
		])
		state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(11, 10),
			"hp": 10, "max_hp": 10, "statuses": {}}]
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview(state, "rogue", "rogue_confusing_dodge")
		_check(plan.get("valid", false), "Confusing Dodge is usable with a living %s" % other)
		_check(state == before, "Dodge forecast does not mutate the board")
		if not plan.get("valid", false):
			continue
		var result: Dictionary = rules.apply_plan(state, plan)
		_check(result == plan.get("result"), "Dodge resolution agrees with forecast")
		_check(_unit_at(result, "rogue").get("position") == Vector2i(8, 2)
			and _unit_at(result, "far").get("position") == Vector2i(2, 2),
			"Dodge swaps with the furthest living character, including %s" % other)
		_check(result.obstacles[0].position == Vector2i(11, 10), "Dodge excludes objects")
	var tied := _state([
		_unit("rogue", "rogue", Vector2i(5, 5)),
		_unit("a", "knight", Vector2i(1, 5)),
		_unit("b", "harpooner", Vector2i(9, 5))
	])
	var first: Dictionary = rules.preview(tied, "rogue", "rogue_confusing_dodge")
	var reordered := tied.duplicate(true)
	reordered.units = [reordered.units[0], reordered.units[2], reordered.units[1]]
	var second: Dictionary = rules.preview(reordered, "rogue", "rogue_confusing_dodge")
	_check(first.get("valid", false) and second.get("valid", false), "Tied Dodge targets are valid")
	if first.get("valid", false) and second.get("valid", false):
		_check(_unit_at(first.result, "rogue").position == _unit_at(second.result, "rogue").position,
			"Dodge tie-break is deterministic regardless of unit array order")
		_check(_unit_at(first.result, "rogue").position == Vector2i(1, 5)
			and _unit_at(second.result, "a").position == Vector2i(5, 5),
			"Dodge chooses the lowest instance ID among equally distant characters")


func _test_wasnt_me() -> void:
	var state := _state([
		_unit("rogue", "rogue", Vector2i(1, 1)),
		_unit("attacker", "harpooner", Vector2i(4, 4)),
		_unit("victim", "harpooner", Vector2i(4, 5)),
		_unit("isolated", "harpooner", Vector2i(9, 9)),
		_unit("dead", "knight", Vector2i(9, 8), 0),
		_unit("hero", "knight", Vector2i(3, 4))
	])
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(9, 10),
		"hp": 10, "max_hp": 10, "statuses": {}}]
	var choices := _ids(rules.targets(state, "rogue", "rogue_wasnt_me"))
	_check("attacker" in choices, "Wasn't Me offers an enemy with adjacent living characters")
	_check("isolated" not in choices and "hero" not in choices and "crate" not in choices,
		"Wasn't Me excludes isolated enemies, allies, and objects")
	var plan: Dictionary = rules.preview(state, "rogue", "rogue_wasnt_me", "attacker")
	_check(plan.get("valid", false), "Wasn't Me can mark the eligible enemy")
	if not plan.get("valid", false):
		return
	var marked: Dictionary = rules.apply_plan(state, plan)
	# Leave only the enemy ally as an adjacent alternate recipient.
	_unit_at(marked, "hero").position = Vector2i(2, 4)
	var tied := marked.duplicate(true)
	tied.units.append(_unit("victim_b", "harpooner", Vector2i(5, 4)))
	var mark_fixture := state.duplicate(true)
	_unit_at(mark_fixture, "hero").position = Vector2i(2, 4)
	mark_fixture.units.append(_unit("victim_b", "harpooner", Vector2i(5, 4)))
	var reordered_mark_fixture := mark_fixture.duplicate(true)
	reordered_mark_fixture.units.reverse()
	for fixture in [mark_fixture, reordered_mark_fixture]:
		var tied_mark: Dictionary = rules.preview(fixture, "rogue", "rogue_wasnt_me", "attacker")
		var victim_id := ""
		for event in tied_mark.get("events", []):
			if event.get("type") == "misdirect":
				victim_id = event.get("victim_id", "")
		_check(tied_mark.get("valid", false) and victim_id == "victim",
			"Mark forecasts the lowest eligible neighboring instance ID regardless of unit order")
	var tied_attack: Dictionary = rules.preview(tied, "attacker", "enemy_harpoon", "hero")
	var reordered := tied.duplicate(true)
	reordered.units.reverse()
	var reordered_attack: Dictionary = rules.preview(reordered, "attacker", "enemy_harpoon", "hero")
	_check(tied_attack.get("valid", false) and reordered_attack.get("valid", false),
		"Redirect with tied adjacent characters can be forecast")
	if tied_attack.get("valid", false) and reordered_attack.get("valid", false):
		var a_hp: int = _unit_at(tied_attack.result, "victim").hp
		var b_hp: int = _unit_at(tied_attack.result, "victim_b").hp
		_check((a_hp < 10) != (b_hp < 10), "Redirect selects exactly one adjacent victim")
		_check(a_hp < 10 and b_hp == 10, "Redirect selects the lowest eligible neighboring instance ID")
		_check(a_hp == _unit_at(reordered_attack.result, "victim").hp
			and b_hp == _unit_at(reordered_attack.result, "victim_b").hp,
			"Redirect victim tie-break is deterministic across unit order")
	var attack: Dictionary = rules.preview(marked, "attacker", "enemy_harpoon", "hero")
	_check(attack.get("valid", false), "Marked enemy can attack the hero")
	if not attack.get("valid", false):
		return
	var after: Dictionary = rules.apply_plan(marked, attack)
	_check(after == attack.result, "Redirected attack resolves exactly as forecast")
	_check(_unit_at(after, "hero").hp == 10 and _unit_at(after, "victim").hp < 10,
		"Next attack redirects to the adjacent enemy ally")
	var next: Dictionary = rules.preview(after, "attacker", "enemy_harpoon", "hero")
	_check(next.get("valid", false), "Enemy can attack again after redirect")
	if next.get("valid", false):
		var twice: Dictionary = rules.apply_plan(after, next)
		_check(_unit_at(twice, "hero").hp < 10 and _unit_at(twice, "victim").hp == _unit_at(after, "victim").hp,
			"Redirect is consumed after exactly one attack")


func _test_redirect_excludes_original_target() -> void:
	var state := _state([
		_unit("rogue", "rogue", Vector2i(1, 1)),
		_unit("attacker", "harpooner", Vector2i(4, 4)),
		_unit("a_original", "knight", Vector2i(3, 4)),
		_unit("z_alternative", "harpooner", Vector2i(4, 5))
	])
	var mark: Dictionary = rules.preview(state, "rogue", "rogue_wasnt_me", "attacker")
	_check(mark.get("valid", false), "Can mark an enemy adjacent to its intended victim and an ally")
	if not mark.get("valid", false):
		return
	var marked: Dictionary = rules.apply_plan(state, mark)
	var before := marked.duplicate(true)
	var attack: Dictionary = rules.preview(marked, "attacker", "enemy_attack", "a_original")
	_check(attack.get("valid", false) and marked == before,
		"Attack with lowest-ID original victim forecasts without mutation")
	if not attack.get("valid", false):
		return
	var after: Dictionary = rules.apply_plan(marked, attack)
	_check(after == attack.get("result"), "Redirect commit agrees with attack forecast")
	_check(_unit_at(after, "a_original").hp == 10 and _unit_at(after, "z_alternative").hp < 10,
		"Misdirection chooses the enemy ally instead of the lowest-ID original target")
	var damage_targets := []
	for event in attack.get("events", []):
		if event.get("type") == "damage":
			damage_targets.append(event.get("target_id"))
	_check(damage_targets == ["z_alternative"], "Forecast reports the actual redirected damage recipient")


func _test_redirect_fallback_when_alternate_leaves() -> void:
	var state := _state([
		_unit("rogue", "rogue", Vector2i(1, 1)),
		_unit("attacker", "harpooner", Vector2i(4, 4)),
		_unit("original", "knight", Vector2i(3, 4)),
		_unit("alternate", "harpooner", Vector2i(4, 5))
	])
	var mark: Dictionary = rules.preview(state, "rogue", "rogue_wasnt_me", "attacker")
	_check(mark.get("valid", false), "Can mark attacker while an alternate is adjacent")
	if not mark.get("valid", false):
		return
	var marked: Dictionary = rules.apply_plan(state, mark)
	_check(rules.has_status_handler(marked, "attacker", "misdirect"), "Attacker has the misdirection mark")
	_unit_at(marked, "alternate").position = Vector2i(4, 6)
	var before := marked.duplicate(true)
	var attack: Dictionary = rules.preview(marked, "attacker", "enemy_attack", "original")
	_check(attack.get("valid", false) and marked == before, "Fallback attack forecasts without mutation")
	if not attack.get("valid", false):
		return
	var board = preload("res://rules/board.gd")
	var fallback_text: String = board.text(marked, "misdirect_missing", {
		"actor": board.display_name(marked, _unit_at(marked, "attacker")),
		"target": board.display_name(marked, _unit_at(marked, "original"))
	})
	var fallback_emitted := false
	for event in attack.get("events", []):
		if event.get("type") == "misdirect" and event.get("text") == fallback_text \
				and event.get("unit_id") == "attacker" and event.get("target_id") == "original":
			fallback_emitted = true
	_check(fallback_emitted, "Forecast emits the missing-alternate fallback event")
	var after: Dictionary = rules.apply_plan(marked, attack)
	_check(after == attack.get("result"), "Fallback attack resolves as forecast")
	_check(_unit_at(after, "original").hp < 10 and _unit_at(after, "alternate").hp == 10,
		"Original target takes damage when the alternate leaves adjacency")
	_check(not rules.has_status_handler(after, "attacker", "misdirect"),
		"Fallback attack consumes the misdirection mark")


func _test_retreat_and_hybrid() -> void:
	var state := _state([
		_unit("rogue", "rogue", Vector2i(4, 4)),
		_unit("near", "harpooner", Vector2i(5, 4)),
		_unit("far", "harpooner", Vector2i(1, 4)),
		_unit("civilian", "ferryman", Vector2i(10, 10))
	])
	var ordered: Dictionary = rules.set_order(state, "rogue", "order_retreat")
	_check(ordered.get("orders", {}).get("rogue") == "order_retreat", "Rogue offers the Retreat standing order")
	var before := ordered.duplicate(true)
	var plan: Dictionary = rules.preview_round(ordered)
	_check(ordered == before and plan.get("valid", false), "Retreat round forecasts without mutation")
	var result: Dictionary = rules.commit_round(ordered, plan)
	_check(result == plan.get("result"), "Retreat round commit matches forecast")
	_check(_unit_at(result, "rogue").get("position") == Vector2i(3, 4),
		"Retreat moves away from the nearest opponent rather than the farther opponent")
	var chosen: Dictionary = rules.choose_manual(state, "rogue", "rogue_confusing_dodge", "")
	_check(chosen.get("overrides", {}).get("rogue", {}).get("ability_id") == "rogue_confusing_dodge",
		"Hybrid can reserve Rogue's Dodge")
	var forecast: Dictionary = rules.preview_round(chosen)
	var committed: Dictionary = rules.commit_round(chosen, forecast)
	_check(forecast.get("valid", false) and committed == forecast.get("result"),
		"Rogue hybrid override commits the forecast")
