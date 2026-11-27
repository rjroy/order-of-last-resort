extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/direct_order_fitted_agency_test.gd
const Catalog = preload("res://content/catalog.gd")
var rules = preload("res://rules/rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(Catalog.read_default().duplicate(true))
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.encounters.test_escort.deadline = 100
	defs.abilities.healer_heal.params.amount = 3
	defs.abilities.wizard_blast.params.damage = 4
	defs.abilities.healing_sonnet.params.damage = 2
	for hero in ["healer", "wizard", "rogue", "necromancer", "bard", "knight", "blacksmith"]:
		defs.characters[hero].abilities = Catalog.profile(defs, hero).abilities.duplicate()
		defs.characters[hero].habits = Catalog.profile(defs, hero).habits.duplicate()
		defs.characters[hero].habits.order_hold = "hold"
		defs.characters[hero].default_order = "order_hold"
	defs.characters.rogue.abilities.append("rogue_tripwire")
	defs.characters.necromancer.abilities.append("necro_grave_bell")
	_doctor()
	_mending()
	_jump()
	_cut()
	_bell()
	_songs()
	_fallback()
	_form_drift()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: fitted direct order agency")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i, hp := 20) -> Dictionary:
	return {"id": id, "character_id": character, "position": position, "hp": hp,
		"max_hp": 20, "statuses": {}, "upgrades": {}}


func _state(hero: String, units: Array) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [_unit("actor", hero, Vector2i(3, 3))] + units + [
		_unit("smith", "blacksmith", Vector2i(0, 0)),
		_unit("civilian", "ferryman", Vector2i(11, 10))]
	_find(state, "actor").fitted_by = "smith"
	state.orders = {"actor": "order_hold", "smith": "order_hold", "a": "order_hold",
		"b": "order_hold", "c": "order_hold"}
	state.overrides = {}
	state.rng_state = 12345
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return state


func _find(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _has_event(plan: Dictionary, type: String, target: String) -> bool:
	return plan.get("events", []).any(func(event: Dictionary) -> bool:
		return event.get("type") == type and event.get("target_id") == target)


func _round(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and state == before and plan == rules.preview_round(state),
		label + ": valid, repeatable and pure round forecast")
	if plan.get("valid", false):
		_check(rules.commit_round(state, plan) == plan.result and state == before,
			label + ": commit equals forecast")
	return plan


func _discover(state: Dictionary, ability: String, legal: Array, illegal: Array) -> void:
	var before: Dictionary = rules.state_before_action(state, "actor")
	var form: Dictionary = rules.command_ability(before, "actor", ability)
	_check(form.get("targeting", {}).get("kind") == "entity", ability + ": fitted direct form is entity-targeted")
	var ids: Array = rules.targets(before, "actor", ability).map(func(choice: Dictionary): return choice.get("id"))
	for id in legal:
		_check(id in ids, ability + ": offers " + id)
	for id in illegal:
		_check(id not in ids, ability + ": excludes " + id)


func _direct(state: Dictionary, ability: String, target: String) -> Dictionary:
	var before: Dictionary = rules.state_before_action(state, "actor")
	_check(rules.preview(before, "actor", ability, target, true).get("valid", false),
		ability + ": chosen fitted action is legal")
	var staged: Dictionary = rules.choose_manual(state, "actor", ability, target)
	_check(staged.overrides.get("actor", {}).get("target_id") == target, ability + ": chosen target stages")
	var plan := _round(staged, ability + " → " + target)
	if plan.get("valid", false):
		_check(_has_event(plan, "fitted_conversion", target), ability + ": conversion names chosen primary")
		_check(not _find(plan.result, "actor").has("fitted_by"), ability + ": conversion consumes fitting")
	return plan


func _authored(state: Dictionary, ability: String, expected: String) -> void:
	var plan: Dictionary = rules.preview(state, "actor", ability)
	_check(plan.get("valid", false), ability + ": authored autonomous fixture is legal")
	if plan.get("valid", false):
		_check(_has_event(plan, "fitted_conversion", expected), ability + ": authored selection remains " + expected)


func _invalid(state: Dictionary, ability: String, target: String, alternative: String) -> void:
	var staged: Dictionary = rules.choose_manual(state, "actor", ability, target)
	if not staged.overrides.has("actor"):
		_check(false, ability + ": invalidation requires a staged target")
		return
	_find(staged, target).hp = 0
	var plan := _round(staged, ability + " invalidated")
	if plan.get("valid", false):
		_check(not _has_event(plan, "fitted_conversion", alternative),
			ability + ": invalid target does not select a different primary")
		_check(plan.events.any(func(event: Dictionary) -> bool:
			return event.get("unit_id") == "actor" and event.get("type") == "wait"),
			ability + ": invalidation is explained")


func _doctor() -> void:
	var state := _state("healer", [_unit("near", "harpooner", Vector2i(4, 3)),
		_unit("far", "harpooner", Vector2i(7, 3)), _unit("dead", "harpooner", Vector2i(5, 5), 0)])
	_discover(state, "healer_heal", ["near", "far"], ["actor", "smith", "dead", "civilian"])
	_authored(state, "healer_heal", "near")
	var plan := _direct(state, "healer_heal", "far")
	if plan.get("valid", false):
		_check(_find(plan.result, "far").hp == 17 and _find(plan.result, "near").hp == 20,
			"Doctor's Orders damages chosen opponent, not nearest")
	_invalid(state, "healer_heal", "far", "near")


func _mending() -> void:
	var state := _state("wizard", [_unit("a", "knight", Vector2i(4, 3), 10),
		_unit("b", "healer", Vector2i(7, 3), 10), _unit("c", "rogue", Vector2i(8, 3), 10),
		_unit("enemy", "harpooner", Vector2i(9, 6))])
	_find(state, "actor").upgrades = {"wizard_conductive_personality": 1}
	_discover(state, "wizard_blast", ["a", "b", "c"], ["actor", "smith", "enemy", "civilian"])
	_authored(state, "wizard_blast", "a")
	var plan := _direct(state, "wizard_blast", "b")
	if plan.get("valid", false):
		_check(_find(plan.result, "b").hp == 14 and _find(plan.result, "c").hp == 12
			and _find(plan.result, "a").hp == 10,
			"Mending Blast heals chosen primary and its nearest wounded secondary")
	_invalid(state, "wizard_blast", "b", "a")
	var last_patient := _state("wizard", [_unit("a", "knight", Vector2i(4, 3), 10),
		_unit("enemy", "harpooner", Vector2i(7, 3))])
	_discover(last_patient, "wizard_blast", ["a"], ["actor", "enemy"])
	var staged: Dictionary = rules.choose_manual(last_patient, "actor", "wizard_blast", "a")
	_check(staged.overrides.get("actor", {}).get("target_id") == "a",
		"Mending Blast: last wounded patient stages as fitted target")
	_find(staged, "a").hp = 20
	var invalidated := _round(staged, "Mending Blast last patient healed before action")
	if invalidated.get("valid", false):
		_check(invalidated.events.any(func(event: Dictionary) -> bool:
			return event.get("unit_id") == "actor" and event.get("type") == "wait"),
			"Mending Blast waits when its last patient is no longer wounded")
		_check(_find(invalidated.result, "a").hp == 20
			and _find(invalidated.result, "actor").get("fitted_by") == "smith",
			"Mending Blast does not damage the former patient or spend the fitting")


func _jump() -> void:
	var state := _state("rogue", [_unit("near", "harpooner", Vector2i(6, 3)),
		_unit("far", "harpooner", Vector2i(9, 3)), _unit("dead", "harpooner", Vector2i(10, 4), 0)])
	_discover(state, "rogue_confusing_dodge", ["near", "far"], ["actor", "smith", "dead", "civilian"])
	_authored(state, "rogue_confusing_dodge", "far")
	var plan := _direct(state, "rogue_confusing_dodge", "near")
	if plan.get("valid", false):
		_check(_has_event(plan, "move", "near") and _find(plan.result, "actor").position == Vector2i(5, 3)
			and _find(plan.result, "near").position == Vector2i(6, 3),
			"Clear Jump lands on closest open neighbor of chosen opponent without swapping")
	_invalid(state, "rogue_confusing_dodge", "near", "far")


func _cut() -> void:
	var state := _state("rogue", [_unit("a", "knight", Vector2i(4, 3)),
		_unit("b", "healer", Vector2i(3, 5)), _unit("c", "wizard", Vector2i(6, 3)),
		_unit("enemy", "harpooner", Vector2i(7, 7))])
	for id in ["a", "b", "c"]:
		_find(state, id).statuses.tripwire_tangled = {"remaining": 2}
	_discover(state, "rogue_tripwire", ["a", "b"], ["actor", "c", "enemy", "civilian"])
	_authored(state, "rogue_tripwire", "a")
	var plan := _direct(state, "rogue_tripwire", "b")
	if plan.get("valid", false):
		_check(_has_event(plan, "status", "b") and not _find(plan.result, "b").statuses.has("tripwire_tangled")
			and _find(plan.result, "a").statuses.has("tripwire_tangled"),
			"Cut the Wire frees chosen held ally, not nearest")
	_invalid(state, "rogue_tripwire", "b", "a")


func _bell() -> void:
	var state := _state("necromancer", [_unit("near", "harpooner", Vector2i(5, 3)),
		_unit("b", "healer", Vector2i(3, 7)), _unit("adjacent", "harpooner", Vector2i(3, 4)),
		_unit("blocked", "harpooner", Vector2i(7, 3))])
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(6, 3),
		"hp": 20, "max_hp": 20, "statuses": {}}]
	_discover(state, "necro_grave_bell", ["near", "b"], ["actor", "adjacent", "blocked", "crate"])
	# The smith is farther away than near, and the near landing is open.
	var autonomous: Dictionary = rules.preview(state, "actor", "necro_grave_bell")
	_check(autonomous.get("valid", false), "Dinner Bell authored fixture is legal")
	if autonomous.get("valid", false):
		_check(_has_event(autonomous, "pull", "near"), "Dinner Bell authored selection is nearest eligible")
	var plan := _direct(state, "necro_grave_bell", "b")
	if plan.get("valid", false):
		_check(_has_event(plan, "pull", "b") and _find(plan.result, "b").position == Vector2i(3, 6)
			and _find(plan.result, "near").position == Vector2i(5, 3),
			"Dinner Bell draws chosen ally to its legal destination")
	_invalid(state, "necro_grave_bell", "b", "near")


func _songs() -> void:
	for ability in ["inspiring_melody", "healing_sonnet", "bard_take_the_stage"]:
		var state := _state("bard", [_unit("a", "knight", Vector2i(5, 3), 6),
			_unit("b", "healer", Vector2i(7, 3), 10),
			_unit("c", "wizard", Vector2i(7, 4), 14),
			_unit("enemy", "harpooner", Vector2i(9, 8))])
		_find(state, "actor").upgrades = {"bard_house_lights": 1, "bard_front_row_seats": 1}
		_discover(state, ability, ["a", "b", "c"], ["enemy", "civilian"])
		var auto: Dictionary = rules.preview(state, "actor", ability)
		_check(auto.get("valid", false), ability + ": autonomous fitted song is legal")
		if not auto.get("valid", false):
			continue
		var selected := ""
		for event in auto.events:
			if event.get("type") == "fitted_conversion":
				selected = event.get("target_id", "")
		_check(not selected.is_empty(), ability + ": autonomous draw identifies primary")
		# c is outside Front Row's two lowest HP for the healing forms; when
		# Melody draws c, use b to retain a distinct direct choice.
		var target := "b" if selected == "c" else "c"
		var plan := _direct(state, ability, target)
		if plan.get("valid", false):
			_check(plan.result.rng_state == state.rng_state, ability + ": explicit primary does not draw RNG")
			if ability == "inspiring_melody":
				_check(_find(plan.result, target).statuses.has("inspired"), "in-tune Melody inspires chosen hero")
			elif ability == "healing_sonnet":
				_check(_find(plan.result, target).hp == _find(state, target).hp + 2,
					"in-tune Sonnet heals chosen hero")
			else:
				_check(_find(plan.result, "b").hp == 12 and _find(plan.result, "c").hp == 16
					and _find(plan.result, "a").hp == 6,
					"Company Chorus heals selected soloist and adjacent wounded hero")
		_invalid(state, ability, target, "a" if target != "a" else "b")


func _fallback() -> void:
	var state := _state("wizard", [_unit("enemy", "harpooner", Vector2i(7, 3))])
	_discover(state, "wizard_blast", ["enemy", "civilian"], ["actor"])
	var plan := _direct_fallback(state, "wizard_blast", "enemy")
	if plan.get("valid", false):
		_check(_find(plan.result, "enemy").hp == 16 and _find(plan.result, "actor").get("fitted_by") == "smith",
			"unavailable Mending Blast falls back to ordinary Blast and retains fitting")


func _direct_fallback(state: Dictionary, ability: String, target: String) -> Dictionary:
	var staged: Dictionary = rules.choose_manual(state, "actor", ability, target)
	_check(staged.overrides.get("actor", {}).get("target_id") == target, ability + ": fallback stages")
	return _round(staged, ability + " fallback")


func _form_drift() -> void:
	var state := _state("wizard", [_unit("a", "knight", Vector2i(5, 3), 10),
		_unit("enemy", "harpooner", Vector2i(8, 3))])
	var smith := _find(state, "smith")
	smith.position = Vector2i(2, 3)
	state.units.erase(smith)
	state.units.push_front(smith)
	_find(state, "actor").erase("fitted_by")
	var before: Dictionary = rules.state_before_action(state, "actor")
	_check(not _find(before, "actor").has("fitted_by")
		and rules.preview(before, "actor", "wizard_blast", "a", true).get("valid", false),
		"form drift: Smith holds and ordinary Blast can target wounded ally")
	var staged: Dictionary = rules.choose_manual(state, "actor", "wizard_blast", "a")
	_check(staged.overrides.get("actor", {}).get("target_id") == "a",
		"form drift: ordinary Blast target stages")
	staged = rules.set_order(staged, "smith", "order_try_this")
	_check(staged.orders.get("smith") == "order_try_this", "form drift: Smith switches to Try This")
	var plan := _round(staged, "ordinary Blast becomes Mending Blast")
	if plan.get("valid", false):
		_check(_has_event(plan, "fit", "actor"), "form drift: Smith fits the actor before their turn")
		_check(plan.events.any(func(event: Dictionary) -> bool:
			return event.get("unit_id") == "actor" and event.get("type") == "wait" \
				and "form" in str(event.get("text", "")).to_lower()),
			"form drift: wait explains the changed form")
		_check(_find(plan.result, "a").hp == 10
			and _find(plan.result, "actor").get("fitted_by") == "smith",
			"form drift: neither damages nor heals the ally, and retains the new fitting")
