extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/bard_test.gd
var failures: Array[String] = []
var rules = preload("res://rules/rules.gd").new()
var catalog = preload("res://content/catalog.gd")
var defs: Dictionary


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(catalog.read_default())
	if not defs.get("characters", {}).has("bard"):
		_check(false, "Bard must be authored")
	else:
		# Stationary foes expose lost activations; the escort must not end the fixture early.
		defs.characters.harpooner.behavior = "hold"
		defs.characters.ferryman.behavior = "hold"
		defs.encounters.test_escort.deadline = 100
		_test_kit()
		_test_solo_immunity()
		_test_random_alternation()
		_test_encounter_rng()
		_test_sonnet()
		_test_sonnet_random()
		_test_overrides()
		_test_knockdown_performance_protection()
	if failures.is_empty():
		print("PASS: Bard integration")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _unit(id: String, character: String, at: Vector2i, hp := 20) -> Dictionary:
	return {"id": id, "character_id": character, "position": at,
		"hp": hp, "max_hp": 20, "statuses": {}}


func _state(two_enemies := false) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(4, 4),
		"hp": 10, "max_hp": 10, "statuses": {}}]
	state.units = [_unit("bard", "bard", Vector2i(1, 1)),
		_unit("ally", "knight", Vector2i(2, 1)),
		_unit("enemy_a", "harpooner", Vector2i(8, 8)),
		_unit("dead", "harpooner", Vector2i(7, 8), 0),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	if two_enemies:
		state.units.append(_unit("enemy_b", "harpooner", Vector2i(8, 9)))
	state.orders = {"ally": "order_cautious"}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return state


func _unit_at(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _round(state: Dictionary, description: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and state == before, description + " forecasts without mutation")
	_check(plan == rules.preview_round(state), description + " forecast repeats exactly")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.commit_round(state, plan)
	_check(result == plan.get("result"), description + " commits the forecast")
	_check(result.get("outcome") == "ongoing",
		description + " keeps the fixture playable (outcome: %s)" % result.get("outcome"))
	return plan


func _event_units(plan: Dictionary, type: String) -> Array:
	var ids := []
	for event in plan.get("events", []):
		if event.get("type") == type:
			ids.append(event.get("unit_id", ""))
	return ids


func _ordered(state: Dictionary, order: String) -> Dictionary:
	var selected: Dictionary = rules.set_order(state, "bard", order)
	_check(selected.get("orders", {}).get("bard") == order, "Bard selects " + order)
	return selected


func _test_kit() -> void:
	var state := _state()
	var options: Array = rules.options(state, "bard")
	var ids := []
	for option in options:
		ids.append(option.get("id"))
	_check("move" in ids, "Bard can be directly moved")
	_check("order_inspiring_melody" in ids and "order_healing_sonnet" in ids,
		"Bard offers both persistent song orders")
	var hold := false
	for option in options:
		if option.get("kind") == "order" and str(option.get("label", "")).to_lower() == "hold":
			hold = true
	_check(hold, "Bard offers standing Hold")
	for song in ["inspiring_melody", "healing_sonnet"]:
		var choices: Array = rules.targets(state, "bard", song)
		_check(choices.size() == 1 and choices[0].get("id") == "enemy_a",
			song + " Direct form offers the living opponent, not ally, corpse or crate")
		_check(not rules.preview(state, "bard", song, "ally").get("valid", false)
			and not rules.preview(state, "bard", song, "crate").get("valid", false)
			and not rules.preview(state, "bard", song, "enemy_a").get("valid", false),
			song + " low-level automatic preview does not accept a target argument")
		_check(rules.preview(state, "bard", song).get("valid", false),
			song + " low-level automatic preview selects an eligible listener")


func _test_solo_immunity() -> void:
	var state := _ordered(_state(), "order_inspiring_melody")
	for index in range(3):
		var plan := _round(state, "Solo melody round %d" % (index + 1))
		if plan.is_empty():
			return
		var recovered := _event_units(plan, "recover")
		_check(("enemy_a" in recovered) == (index != 1),
			"Solo opponent loses activation in R1 and R3, but not immune R2")
		state = plan.result
		_check(state.get("orders", {}).get("bard") == "order_inspiring_melody",
			"Melody remains the standing order")


func _test_random_alternation() -> void:
	var first_targets := {}
	for seed_value in range(1, 33):
		var state := _ordered(_state(true), "order_inspiring_melody")
		state.rng_state = seed_value
		var first := _round(state, "Melody seed %d" % seed_value)
		if first.is_empty():
			return
		var first_lost := _event_units(first, "recover")
		_check(first_lost.size() == 1 and first_lost[0] in ["enemy_a", "enemy_b"],
			"Melody selects one living opponent, not ally, corpse or crate")
		if first_lost.size() != 1 or first_lost[0] not in ["enemy_a", "enemy_b"]:
			continue
		first_targets[first_lost[0]] = true
		var second := _round(first.result, "Alternating melody")
		var second_lost := _event_units(second, "recover")
		_check(second_lost.size() == 1 and second_lost[0] in ["enemy_a", "enemy_b"]
			and second_lost[0] != first_lost[0], "Other opponent loses its activation next round")
	_check(first_targets.size() == 2, "Different seeds can choose either first opponent")


func _test_encounter_rng() -> void:
	# The civilian and opponents hold, and removing the other hero isolates song draws.
	for order in ["order_inspiring_melody", "order_healing_sonnet"]:
		var state := _ordered(_state(true), order)
		state.units.erase(_unit_at(state, "ally"))
		state.rng_state = 12345
		var initial_rng: int = state.rng_state
		var plan := _round(state, order + " isolated random draw")
		if plan.is_empty():
			continue
		var committed: Dictionary = rules.commit_round(state, plan)
		_check(state.rng_state == initial_rng, order + " preview and commit leave input RNG untouched")
		_check(committed.rng_state != initial_rng, order + " commits an advanced encounter RNG")
		if order == "order_inspiring_melody":
			_check(_event_units(plan, "recover").size() == 1, "Melody actually selects an opponent")
		else:
			_check(_unit_at(committed, "enemy_a").hp + _unit_at(committed, "enemy_b").hp == 39,
				"Sonnet actually selects and damages an opponent")

	var solo := _ordered(_state(), "order_inspiring_melody")
	solo.units.erase(_unit_at(solo, "ally"))
	solo.rng_state = 12345
	var first := _round(solo, "Solo melody before immune round")
	if first.is_empty():
		return
	_check("enemy_a" in _event_units(first, "recover"), "Solo target loses its first activation")
	var immune: Dictionary = rules.commit_round(solo, first)
	var immune_rng: int = immune.rng_state
	var second := _round(immune, "Solo melody with no eligible opponent")
	if second.is_empty():
		return
	var after: Dictionary = rules.commit_round(immune, second)
	_check("enemy_a" not in _event_units(second, "recover"), "Immune opponent does not lose a second activation")
	_check(immune.rng_state == immune_rng and after.rng_state == immune_rng,
		"No eligible listener leaves encounter RNG unchanged in preview and commit")


func _test_sonnet() -> void:
	var state := _ordered(_state(), "order_inspiring_melody")
	var melody := _round(state, "Melody before sonnet")
	if melody.is_empty():
		return
	state = _ordered(melody.result, "order_healing_sonnet")
	var sonnet := _round(state, "Sonnet against laughter-immune enemy")
	if sonnet.is_empty():
		return
	var result: Dictionary = sonnet.result
	_check(_unit_at(result, "enemy_a").get("hp") == 19,
		"Sonnet deals one damage despite laughter immunity")
	_check(_unit_at(result, "ally").get("hp") == 20 and result.obstacles[0].hp == 10
		and _unit_at(result, "dead").get("hp") == 0, "Sonnet excludes ally, crate and corpse")
	var next := _round(result, "Persistent sonnet")
	if not next.is_empty():
		_check(_unit_at(next.result, "enemy_a").get("hp") == 18, "Sonnet repeats next round")
		var switched := _ordered(next.result, "order_inspiring_melody")
		var alternate := _round(switched, "Switch back to melody")
		if not alternate.is_empty():
			_check("enemy_a" in _event_units(alternate, "recover"), "Melody works after Sonnet")
			var returned := _ordered(alternate.result, "order_healing_sonnet")
			var again := _round(returned, "Switch back to sonnet")
			if not again.is_empty():
				_check(_unit_at(again.result, "enemy_a").get("hp") == 17,
					"Sonnet works again after Melody")


func _test_sonnet_random() -> void:
	var targets := {}
	for seed_value in range(1, 33):
		var state := _ordered(_state(true), "order_healing_sonnet")
		state.rng_state = seed_value
		var plan := _round(state, "Sonnet seed %d" % seed_value)
		if plan.is_empty():
			return
		var a: int = _unit_at(plan.result, "enemy_a").get("hp", 20)
		var b: int = _unit_at(plan.result, "enemy_b").get("hp", 20)
		_check((a == 19 and b == 20) or (a == 20 and b == 19),
			"Sonnet damages exactly one living opponent by one")
		_check(_unit_at(plan.result, "ally").get("hp") == 20 and plan.result.obstacles[0].hp == 10
			and _unit_at(plan.result, "dead").get("hp") == 0,
			"Sonnet never selects an ally, crate, or corpse")
		if a == 19:
			targets["enemy_a"] = true
		if b == 19:
			targets["enemy_b"] = true
	_check(targets.size() == 2, "Different seeds can choose either Sonnet target")


func _test_overrides() -> void:
	for order in ["order_inspiring_melody", "order_healing_sonnet"]:
		var state := _ordered(_state(), order)
		var selected: Dictionary = rules.choose_manual(state, "ally", "move", "2,2")
		var rejected: Dictionary = rules.choose_manual(selected, "bard", "move", "1,2")
		_check(rejected.get("overrides", {}).size() == 1 and rejected.overrides.has("ally"),
			"Only one hero may be directly commanded per round")
		var directed := _round(selected, order + " while ally moves")
		if directed.is_empty():
			continue
		var after: Dictionary = directed.result
		_check(after.get("orders", {}).get("bard") == order, "Directing ally preserves Bard song")
		if order == "order_inspiring_melody":
			_check("enemy_a" in _event_units(directed, "recover"), "Melody runs while ally is directed")
		else:
			_check(_unit_at(after, "enemy_a").get("hp") == 19, "Sonnet runs while ally is directed")
		var moving: Dictionary = rules.choose_manual(after, "bard", "move", "1,2")
		var moved := _round(moving, "Direct Bard move")
		if moved.is_empty():
			continue
		_check(_unit_at(moved.result, "bard").get("position") == Vector2i(1, 2),
			"Bard executes direct movement")
		_check(moved.result.get("orders", {}).get("bard") == order, "Direct movement preserves song")
		var resumed := _round(moved.result, "Song resumes after movement")
		if resumed.is_empty():
			continue
		if order == "order_inspiring_melody":
			_check("enemy_a" in _event_units(resumed, "recover"), "Melody resumes after movement")
		else:
			_check(_unit_at(resumed.result, "enemy_a").get("hp") == 18, "Sonnet resumes after movement")


func _test_knockdown_performance_protection() -> void:
	# Exercise the authored performance handler with a test-owned knockdown
	# status rather than changing the shipped Melody's laughter mechanic.
	var original := defs
	defs = defs.duplicate(true)
	defs.abilities["fixture_knockdown_song"] = defs.abilities.inspiring_melody.duplicate(true)
	defs.abilities.fixture_knockdown_song.params.status = "knockdown"
	defs.characters.bard.abilities = catalog.profile(defs, "bard").abilities.duplicate()
	defs.characters.bard.abilities.append("fixture_knockdown_song")
	var errors: PackedStringArray = catalog.validate(defs)
	_check(errors.is_empty(), "Knockdown performance fixture validates: " + str(errors))
	if not errors.is_empty():
		defs = original
		return
	var state := _state()
	defs = original
	_check(not state.is_empty() and not _unit_at(state, "enemy_a").is_empty(),
		"Knockdown performance fixture deploys")
	if state.is_empty() or _unit_at(state, "enemy_a").is_empty():
		return
	state.rng_state = 12345
	_unit_at(state, "enemy_a")["alchemy_statuses"] = {"stiff_upper_lip": {
		"source_id": "enemy_a", "expires_after_round": state.round + 1}}
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "bard", "fixture_knockdown_song")
	_check(plan.get("valid", false) and state == before
		and plan == rules.preview(state, "bard", "fixture_knockdown_song"),
		"Protected knockdown performance is a valid, pure, repeatable action")
	if not plan.get("valid", false):
		return
	var protected: Dictionary = rules.apply_plan(state, plan)
	_check(protected == plan.get("result") and protected.rng_state != before.rng_state,
		"Protected performance commits its forecast and advances listener RNG")
	var target := _unit_at(protected, "enemy_a")
	_check(not target.get("alchemy_statuses", {}).has("stiff_upper_lip")
		and not target.statuses.has("knockdown"),
		"Stiff Upper Lip is consumed and prevents this knockdown")
	var consumed := 0
	var invalid := false
	for event in plan.get("events", []):
		if event.get("status_id") == "stiff_upper_lip" and event.get("consumed", false) \
				and event.get("target_id") == "enemy_a":
			consumed += 1
		if event.get("type") == "invalid":
			invalid = true
	_check(consumed == 1 and not invalid,
		"Performance propagates exactly one protection-consumed event and no invalid action")
	var second: Dictionary = rules.preview(protected, "bard", "fixture_knockdown_song")
	_check(second.get("valid", false), "A second knockdown performance is valid")
	if second.get("valid", false):
		var next: Dictionary = rules.apply_plan(protected, second)
		_check(next == second.get("result") and _unit_at(next, "enemy_a").statuses.has("knockdown"),
			"Consumed protection does not prevent the next knockdown")
