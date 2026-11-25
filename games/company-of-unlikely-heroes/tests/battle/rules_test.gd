extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/rules_test.gd
# Fixtures deliberately own their positions and health rather than relying on tuning.
var failures: Array[String] = []
var rules: RefCounted
var definitions: Dictionary


func _initialize() -> void:
	var script_path := "res://rules/rules.gd"
	if not ResourceLoader.exists(script_path):
		# Keep the test executable before the implementation exists.
		rules = RefCounted.new()
		failures.append("Missing behavior: res://rules/rules.gd is not implemented")
	else:
		var script = load(script_path)
		if script == null or not script.can_instantiate():
			failures.append("Missing behavior: rules.gd cannot be instantiated")
			rules = RefCounted.new()
		else:
			rules = script.new()
			definitions = preload("res://tests/fixtures/rules_catalog.gd").definitions()
			definitions.abilities.healer_heal.params["prefer_wounded_self"] = true

	var required := ["new_game", "options", "preview", "apply_plan", "choose_manual", "preview_round", "commit_round"]
	for method in required:
		if not rules.has_method(method):
			failures.append("Missing behavior: rules.%s()" % method)
	if failures.is_empty():
		_test_options()
		_test_knight_push()
		_test_crate_targets()
		_test_crate_actions()
		_test_knight_aura()
		_test_aura_redirects_friendly_attacks()
		_test_harpoon_range()
		_test_healer_bonk()
		_test_healer_heal()
		_test_wizard_blast()
		_test_turn_bound_status_on_object()
		_test_wizard_pull()
		_test_recovery_expires_turn_end_status()
		_test_modes_and_restart()
		_test_round_preview()
		_test_elimination()
		_test_movement_forecast_order()
	if failures.is_empty():
		print("PASS: company rules")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, _team: String, role: String, pos: Vector2i, hp: int = 10) -> Dictionary:
	return {
		"id": id,
		"character_id": {"enemy": "harpooner", "civilian": "ferryman"}.get(role, role),
		"position": pos, "hp": hp, "max_hp": 10, "statuses": {}
	}


func _state(units: Array, fixture_defs: Dictionary = {}) -> Dictionary:
	var state: Dictionary = rules.new_game(fixture_defs if not fixture_defs.is_empty() else definitions, "fixture")
	state["width"] = 12
	state["height"] = 12
	state["units"] = units
	state["terrain"] = []
	state["default_tile"] = "stone"
	state["obstacles"] = []
	state["objective"] = {"handler": "escort", "subject": "civilian", "destination": Vector2i(9, 9)}
	state["orders"] = {}
	state["round"] = 1
	return state


func _find(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id", "") == id:
			return unit
	failures.append("Missing unit: " + id)
	return {}


func _plan(state: Dictionary, actor: String, ability: String, target: String = "") -> Dictionary:
	var before := state.duplicate(true)
	var result = rules.call("preview", state, actor, ability, target)
	_check(state == before, "%s preview must not mutate state" % ability)
	if not result is Dictionary:
		failures.append("%s preview must return a Dictionary" % ability)
		return {}
	_check(result.get("valid", false), "%s preview should be valid" % ability)
	_check(result.get("events", []) is Array and not result.get("events", []).is_empty(),
		"%s preview should include events" % ability)
	return result


func _apply(state: Dictionary, plan: Dictionary, ability: String) -> Dictionary:
	var before := state.duplicate(true)
	var result = rules.call("apply_plan", state, plan)
	_check(state == before, "%s apply_plan must not mutate input" % ability)
	if not result is Dictionary:
		failures.append("%s apply_plan must return a Dictionary" % ability)
		return {}
	return result


func _test_options() -> void:
	var state := _state([
		_unit("k", "heroes", "knight", Vector2i(0, 0)),
		_unit("h", "heroes", "healer", Vector2i(0, 1)),
		_unit("w", "heroes", "wizard", Vector2i(0, 2)),
		_unit("e", "enemies", "enemy", Vector2i(1, 0))
	])
	for entry in [["k", "knight_push", "knight_aura"], ["h", "healer_bonk", "healer_heal"], ["w", "wizard_blast", "wizard_pull"]]:
		var options = rules.call("options", state, entry[0])
		if not options is Array:
			failures.append("%s options must be an Array" % entry[0])
			continue
		var ids: Array = []
		for option in options:
			if option is Dictionary:
				ids.append(option.get("id", ""))
				_check(not str(option.get("label", "")).strip_edges().is_empty(), "Options need readable labels")
		_check(entry[1] in ids and entry[2] in ids, "%s must expose both abilities" % entry[0])


func _test_knight_push() -> void:
	var state := _state([
		_unit("k", "heroes", "knight", Vector2i(1, 1)),
		_unit("e", "enemies", "enemy", Vector2i(2, 1))
	])
	var plan := _plan(state, "k", "knight_push", "e")
	var result := _apply(state, plan, "knight_push")
	var enemy := _find(result, "e")
	_check(enemy.get("position") == Vector2i(3, 1), "Knight push moves enemy away one tile")
	_check(enemy.get("hp", 10) == 10, "Free knight push does not deal damage")
	var blocked := state.duplicate(true)
	blocked["obstacles"] = [{"id": "wall", "object_id": "crate", "statuses": {}, "position": Vector2i(3, 1), "hp": 10, "max_hp": 10}]
	var collision := _apply(blocked, _plan(blocked, "k", "knight_push", "e"), "knight_push collision")
	_check(_find(collision, "e").get("hp", 10) < 10, "Push collision damages target")


func _test_crate_targets() -> void:
	for entry in [["k", "knight", "knight_push"], ["h", "healer", "healer_bonk"]]:
		var state := _state([_unit(entry[0], "heroes", entry[1], Vector2i.ZERO)])
		state["obstacles"] = [
			{"id": "adjacent", "object_id": "crate", "statuses": {}, "position": Vector2i(1, 0), "hp": 10, "max_hp": 10},
			{"id": "far", "object_id": "crate", "statuses": {}, "position": Vector2i(2, 0), "hp": 10, "max_hp": 10},
			{"id": "destroyed", "object_id": "crate", "statuses": {}, "position": Vector2i(0, 1), "hp": 0, "max_hp": 10}
		]
		var before := state.duplicate(true)
		var choices = rules.call("targets", state, entry[0], entry[2])
		_check(state == before, "%s target selection must not mutate state" % entry[2])
		var ids: Array = []
		for choice in choices:
			ids.append(choice.get("id", ""))
		_check("adjacent" in ids, "%s offers adjacent living crate" % entry[2])
		_check("far" not in ids, "%s excludes nonadjacent crate" % entry[2])
		_check("destroyed" not in ids, "%s excludes destroyed crate" % entry[2])
		for target_id in ["adjacent", "far", "destroyed"]:
			var plan = rules.call("preview", state, entry[0], entry[2], target_id)
			_check(plan is Dictionary and plan.get("valid", false) == (target_id == "adjacent"),
				"%s preview accepts only adjacent living crate, not %s" % [entry[2], target_id])
			_check(state == before, "%s crate preview must not mutate state" % entry[2])

	var wizard_state := _state([_unit("w", "heroes", "wizard", Vector2i.ZERO)])
	wizard_state["obstacles"] = [{"id": "crate", "object_id": "crate", "statuses": {}, "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var wizard_choices = rules.call("targets", wizard_state, "w", "wizard_pull")
	for choice in wizard_choices:
		_check(choice.get("id", "") != "crate", "Wizard pull does not offer crates")
	var wizard_plan = rules.call("preview", wizard_state, "w", "wizard_pull", "crate")
	_check(wizard_plan is Dictionary and not wizard_plan.get("valid", false), "Wizard pull cannot target crates")


func _test_crate_actions() -> void:
	var push_state := _state([_unit("k", "heroes", "knight", Vector2i.ZERO)])
	push_state["obstacles"] = [{"id": "crate", "object_id": "crate", "statuses": {}, "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var pushed := _apply(push_state, _plan(push_state, "k", "knight_push", "crate"), "crate push")
	var crate: Dictionary = pushed.get("obstacles", [{}])[0]
	_check(crate.get("position") == Vector2i(2, 0), "Free crate push moves crate one tile")
	_check(crate.get("hp", 0) == 10, "Free crate push does not damage crate")

	var blocked := push_state.duplicate(true)
	blocked["obstacles"].append({"id": "wall", "object_id": "crate", "statuses": {}, "position": Vector2i(2, 0), "hp": 10, "max_hp": 10})
	var collision := _apply(blocked, _plan(blocked, "k", "knight_push", "crate"), "blocked crate push")
	var blocked_crate: Dictionary = collision.get("obstacles", [{}])[0]
	_check(blocked_crate.get("position") == Vector2i(1, 0), "Blocked crate stays in place")
	_check(blocked_crate.get("hp", 10) < 10, "Blocked crate push damages crate")

	var bonk_state := _state([_unit("h", "heroes", "healer", Vector2i.ZERO)])
	bonk_state["obstacles"] = [{"id": "crate", "object_id": "crate", "statuses": {}, "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var bonk_plan := _plan(bonk_state, "h", "healer_bonk", "crate")
	var bonked := _apply(bonk_state, bonk_plan, "crate bonk")
	var bonked_crate: Dictionary = bonked.get("obstacles", [{}])[0]
	_check(bonked_crate.get("hp", 10) < 10, "Bonk damages crate")
	_check(not bonked_crate.get("statuses", {}).has("taunt"), "Bonk does not taunt crate")
	for event in bonk_plan.get("events", []):
		_check(event.get("type", "") != "taunt", "Bonk on crate emits no taunt")

	var aura_state := _state([
		_unit("h", "heroes", "healer", Vector2i.ZERO),
		_unit("k", "heroes", "knight", Vector2i(1, 1)),
		_unit("enemy", "enemies", "enemy", Vector2i(2, 0))
	])
	aura_state["obstacles"] = [{"id": "crate", "object_id": "crate", "statuses": {}, "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var aura_active := _apply(aura_state, _plan(aura_state, "k", "knight_aura"), "knight_aura")
	var aura_bonk := _plan(aura_active, "h", "healer_bonk", "crate")
	var aura_after := _apply(aura_active, aura_bonk, "crate bonk near aura")
	_check(aura_after.get("obstacles", [{}])[0].get("hp", 10) < 10, "Aura does not protect a bonked crate")
	_check(_find(aura_after, "enemy").get("hp", 10) == 10, "Crate bonk near aura does not damage enemy")
	_check(not rules.has_status_handler(aura_after, "enemy", "retarget"), "Crate bonk near aura does not taunt enemy")
	for event in aura_bonk.get("events", []):
		_check(event.get("type", "") != "reflect", "Crate bonk near aura emits no reflect")
		_check(event.get("type", "") != "taunt", "Crate bonk near aura emits no taunt")


func _test_knight_aura() -> void:
	# Aura includes allies, the owner, enemy and civilian, but not distant units.
	for target in ["k", "h", "foe", "civilian", "far"]:
		var state := _state([
			_unit("k", "heroes", "knight", Vector2i(1, 1)),
			_unit("h", "heroes", "healer", Vector2i(1, 2)),
			_unit("foe", "enemies", "enemy", Vector2i(0, 1)),
			_unit("civilian", "civilian", "civilian", Vector2i(1, 0)),
			_unit("far", "heroes", "wizard", Vector2i(6, 1)),
			_unit("attacker", "enemies", "enemy",
				{"k": Vector2i(2, 1), "h": Vector2i(2, 2), "foe": Vector2i(0, 2),
				"civilian": Vector2i(0, 0), "far": Vector2i(7, 1)}[target])
		])
		var protected := _apply(state, _plan(state, "k", "knight_aura"), "knight_aura")
		var after := _apply(protected, _plan(protected, "attacker", "enemy_attack", target), "enemy_attack")
		if target == "far":
			_check(_find(after, "attacker").get("hp", 10) == 10, "Aura must not reflect for a distant unit")
			_check(_find(after, target).get("hp", 10) < 10, "Distant unit takes the original attack")
		else:
			_check(_find(after, target).get("hp", 0) == 10, "Aura prevents original damage to %s" % target)
			var damaged := 0
			for id in ["foe", "attacker"]:
				if id != target and _find(after, id).get("hp", 10) < 10:
					damaged += 1
			_check(damaged > 0, "Aura reflects damage for %s" % target)

	var state := _state([
		_unit("k", "heroes", "knight", Vector2i(1, 1)),
		_unit("attacker", "enemies", "enemy", Vector2i(3, 1))
	])
	state["obstacles"] = [{"id": "rock", "object_id": "crate", "statuses": {}, "position": Vector2i(1, 2), "hp": 10, "max_hp": 10}]
	var protected := _apply(state, _plan(state, "k", "knight_aura"), "knight_aura")
	var after := _apply(protected, _plan(protected, "attacker", "enemy_harpoon", "k"), "enemy_harpoon")
	_check(_find(after, "k").get("hp", 0) == 10, "Aura prevents range-two harpoon damage")
	_check(after.get("obstacles", [{}])[0].get("hp", 10) < 10, "Aura reflects to nearest obstacle rather than attacker")
	_check(_find(after, "attacker").get("hp", 10) == 10, "Aura does not automatically reflect to attacker")


func _test_aura_redirects_friendly_attacks() -> void:
	# The friendly-fire ward and the alternate enemy are both inside the aura.
	# The redirected attack must hit once, not bounce back through the aura.
	var state := _state([
		_unit("k", "heroes", "knight", Vector2i(2, 2)),
		_unit("ward", "heroes", "healer", Vector2i(3, 2)),
		_unit("w", "heroes", "wizard", Vector2i(4, 2)),
		_unit("recipient", "enemies", "enemy", Vector2i(1, 2))
	])
	var baseline := _apply(state, _plan(state, "w", "wizard_blast"), "unshielded blast")
	var blast_damage: int = 10 - _find(baseline, "ward").get("hp", 10)
	_check(blast_damage > 0, "Unshielded friendly-fire blast has positive damage")
	var protected := _apply(state, _plan(state, "k", "knight_aura"), "knight_aura")
	var reflected := _plan(protected, "w", "wizard_blast")
	var after := _apply(protected, reflected, "shielded blast")
	_check(_find(after, "ward").get("hp", 0) == 10, "Aura prevents friendly-fire blast damage to ward")
	_check(not rules.has_status_handler(after, "ward", "skip_action"), "Ward does not receive redirected blast knockdown")
	_check(_find(after, "recipient").get("hp", 10) == 10 - blast_damage, "Nearest alternate enemy receives exactly the original blast damage once")
	_check(rules.has_status_handler(after, "recipient", "skip_action"), "Reflected blast knocks down its actual recipient")
	_check(_find(after, "k").get("hp", 0) == 10, "Reflection does not loop back into the aura")
	_check(_find(after, "w").get("hp", 0) == 10, "Reflection does not damage the original attacker instead")
	_check(reflected.events.map(func(event: Dictionary) -> String: return event.type) == ["reflect", "damage"],
		"Action attribution preserves the ordered reflect and damage log")
	var first: Dictionary = reflected.events[0]
	_check(first.get("unit_id") == "k" and first.get("ward_id") == "ward" \
			and first.get("resolved_action") == {"unit_id": "w", "ability_id": "wizard_blast",
				"source_cell": Vector2i(4, 2), "actor_cell": Vector2i(4, 2), "event_count": 2},
		"A reflected cast preserves the Knight protector and groups both effects under the Wizard")
	var absorbed := protected.duplicate(true)
	absorbed.units.pop_back()
	var absorbed_plan := _plan(absorbed, "w", "wizard_blast")
	_check(absorbed_plan.result == absorbed and absorbed_plan.events.size() == 1
			and absorbed_plan.events[0].get("type") == "reflect" \
			and absorbed_plan.events[0].get("resolved_action", {}).get("unit_id") == "w",
		"Fully absorbed cast changes no state and is still attributed to its successful caster")
	var invalid: Dictionary = rules.preview(protected, "missing", "wizard_blast")
	_check(not invalid.valid and invalid.events.is_empty(), "An unknown caster emits no action provenance")

	# A shielded enemy can also be the initial ward. An adjacent obstacle is
	# the nearest eligible alternate recipient of the healer's attack.
	var bonk_state := _state([
		_unit("k", "heroes", "knight", Vector2i(2, 2)),
		_unit("enemy", "enemies", "enemy", Vector2i(3, 2)),
		_unit("h", "heroes", "healer", Vector2i(4, 2))
	])
	bonk_state["obstacles"] = [{"id": "rock", "object_id": "crate", "statuses": {}, "position": Vector2i(3, 3), "hp": 10, "max_hp": 10}]
	var bonk_baseline := _apply(bonk_state, _plan(bonk_state, "h", "healer_bonk", "enemy"), "unshielded bonk")
	var bonk_damage: int = 10 - _find(bonk_baseline, "enemy").get("hp", 10)
	_check(bonk_damage > 0, "Unshielded bonk has positive damage")
	var bonk_protected := _apply(bonk_state, _plan(bonk_state, "k", "knight_aura"), "knight_aura")
	var bonk_after := _apply(bonk_protected, _plan(bonk_protected, "h", "healer_bonk", "enemy"), "shielded bonk")
	_check(_find(bonk_after, "enemy").get("hp", 0) == 10, "Aura prevents bonk damage to shielded enemy")
	_check(bonk_after.get("obstacles", [{}])[0].get("hp", 10) == 10 - bonk_damage, "Nearest obstacle receives the original bonk damage instead")


func _test_healer_bonk() -> void:
	var state := _state([
		_unit("h", "heroes", "healer", Vector2i(1, 1)),
		_unit("e", "enemies", "enemy", Vector2i(2, 1))
	])
	var result := _apply(state, _plan(state, "h", "healer_bonk", "e"), "healer_bonk")
	var enemy := _find(result, "e")
	_check(enemy.get("hp", 10) < 10, "Healer bonk damages enemy")
	_check(enemy.get("statuses", {}).get("taunt", {}).get("source_id", "") == "h", "Healer bonk taunts enemy toward healer")


func _test_harpoon_range() -> void:
	for distance in [1, 2, 3]:
		var state := _state([
			_unit("e", "enemies", "enemy", Vector2i.ZERO),
			_unit("k", "heroes", "knight", Vector2i(distance, 0))
		])
		var before := state.duplicate(true)
		var plan = rules.call("preview", state, "e", "enemy_harpoon", "k")
		_check(state == before, "Harpoon preview must not mutate state")
		if not plan is Dictionary:
			failures.append("Harpoon preview must return a Dictionary")
			continue
		_check(plan.get("valid", false) == (distance <= 2),
			"Harpoon valid at Manhattan range 1 or 2, not %d" % distance)
		if distance <= 2 and plan.get("valid", false):
			var result := _apply(state, plan, "enemy_harpoon")
			_check(_find(result, "k").get("hp", 10) < 10, "Harpoon damages target at range %d" % distance)


func _test_healer_heal() -> void:
	var state := _state([
		_unit("h", "heroes", "healer", Vector2i(0, 0)),
		_unit("near", "heroes", "knight", Vector2i(1, 0), 6),
		_unit("far", "heroes", "wizard", Vector2i(3, 0), 2),
		_unit("enemy", "enemies", "enemy", Vector2i(0, 1), 1)
	])
	var result := _apply(state, _plan(state, "h", "healer_heal"), "healer_heal")
	_check(_find(result, "near").get("hp", 6) > 6, "Heal selects nearest injured ally")
	_check(_find(result, "near").get("hp", 11) <= 10, "Heal cannot exceed maximum hp")
	_check(_find(result, "far").get("hp", 0) == 2, "Heal does not choose the more injured distant ally")
	_check(_find(result, "enemy").get("hp", 0) == 1, "Heal does not select an enemy")
	var self_state := _state([_unit("h", "heroes", "healer", Vector2i.ZERO, 9), _unit("ally", "heroes", "knight", Vector2i(1, 0), 3)])
	var self_plan := _plan(self_state, "h", "healer_heal")
	_check(self_plan.get("events", [{}])[0].get("target_id") == "h", "Wounded healer previews healing self")
	var self_result := _apply(self_state, self_plan, "healer_heal")
	_check(_find(self_result, "h").get("hp") == 10, "Self-heal caps at maximum hp")
	_check(_find(self_result, "ally").get("hp") == 3, "Wounded healer takes priority over ally")
	var lone := _state([_unit("h", "heroes", "healer", Vector2i.ZERO, 5)])
	var lone_result := _apply(lone, _plan(lone, "h", "healer_heal"), "lone self heal")
	_check(_find(lone_result, "h").get("hp") == 8, "Lone wounded healer can heal self")
	var fallback := _state([_unit("h", "heroes", "healer", Vector2i.ZERO), _unit("ally", "heroes", "knight", Vector2i(1, 0)), _unit("far", "heroes", "wizard", Vector2i(2, 0), 5)])
	var fallback_plan := _plan(fallback, "h", "healer_heal")
	_check(fallback_plan.get("events", [{}])[0].get("target_id") == "ally", "Full healer selects nearest ally even when full")
	var fallback_result := _apply(fallback, fallback_plan, "fallback heal")
	_check(_find(fallback_result, "far").get("hp") == 5, "Heal does not skip a full nearest ally")
	var ordinary_defs := definitions.duplicate(true)
	ordinary_defs.abilities.healer_heal.params.erase("prefer_wounded_self")
	var ordinary := _state([_unit("h", "heroes", "healer", Vector2i.ZERO, 5), _unit("ally", "heroes", "knight", Vector2i(1, 0), 5)], ordinary_defs)
	var ordinary_result := _apply(ordinary, _plan(ordinary, "h", "healer_heal"), "ordinary heal")
	_check(_find(ordinary_result, "h").get("hp") == 5 and _find(ordinary_result, "ally").get("hp") == 8,
		"Heal without the policy retains other-only targeting")
	var standing_defs := definitions.duplicate(true)
	standing_defs.orders["support"] = {"label": "Support"}
	standing_defs.behaviors["support"] = {"handler": "use_ability", "params": {"ability": "healer_heal"}}
	standing_defs.classes.healer.habits["support"] = "support"
	var standing := _state([_unit("h", "heroes", "healer", Vector2i.ZERO, 5),
		_unit("ally", "heroes", "knight", Vector2i(1, 0), 5)], standing_defs)
	standing.orders["h"] = "support"
	var before := standing.duplicate(true)
	var round_plan: Dictionary = rules.preview_round(standing)
	var round_result: Dictionary = rules.commit_round(standing, round_plan)
	var self_event := false
	for event in round_plan.get("events", []):
		if event.get("ability_id") == "healer_heal" and event.get("target_id") == "h":
			self_event = true
	_check(standing == before and self_event, "Standing heal previews self without mutating state")
	_check(_find(round_result, "h").get("hp") == 8 and _find(round_result, "ally").get("hp") == 5,
		"Standing heal commits the previewed self target")
	var standing_fallback := _state([_unit("h", "heroes", "healer", Vector2i.ZERO),
		_unit("ally", "heroes", "knight", Vector2i(1, 0)),
		_unit("far", "heroes", "wizard", Vector2i(2, 0), 5)], standing_defs)
	standing_fallback.orders["h"] = "support"
	var fallback_round: Dictionary = rules.preview_round(standing_fallback)
	var fallback_event := false
	for event in fallback_round.get("events", []):
		if event.get("ability_id") == "healer_heal" and event.get("target_id") == "ally":
			fallback_event = true
	var fallback_committed: Dictionary = rules.commit_round(standing_fallback, fallback_round)
	_check(fallback_event and _find(fallback_committed, "far").get("hp") == 5,
		"Standing heal previews and commits the full nearest ally rather than a wounded distant ally")


func _test_wizard_blast() -> void:
	var state := _state([
		_unit("w", "heroes", "wizard", Vector2i.ZERO),
		_unit("ally", "heroes", "knight", Vector2i(1, 0)),
		_unit("enemy", "enemies", "enemy", Vector2i(3, 0))
	])
	var result := _apply(state, _plan(state, "w", "wizard_blast"), "wizard_blast")
	_check(_find(result, "ally").get("hp", 10) < 10, "Blast targets nearest unit even when allied")
	_check(rules.has_status_handler(result, "ally", "skip_action"), "Blast knocks its target down")
	_check(_find(result, "enemy").get("hp", 0) == 10, "Blast does not hit more distant enemy instead")
	var obstacle_state := _state([
		_unit("w", "heroes", "wizard", Vector2i.ZERO),
		_unit("enemy", "enemies", "enemy", Vector2i(3, 0))
	])
	obstacle_state["obstacles"] = [{"id": "rock", "object_id": "crate", "statuses": {}, "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var obstacle_result := _apply(obstacle_state, _plan(obstacle_state, "w", "wizard_blast"), "wizard_blast")
	_check(obstacle_result.get("obstacles", [{}])[0].get("hp", 10) < 10, "Blast targets nearest obstacle")
	_check(_find(obstacle_result, "enemy").get("hp", 0) == 10, "Blast does not bypass a nearer obstacle")


func _test_turn_bound_status_on_object() -> void:
	var fixture_defs := definitions.duplicate(true)
	fixture_defs["abilities"]["wizard_blast"]["params"]["status"] = "aura"
	var state := _state([_unit("w", "heroes", "wizard", Vector2i.ZERO)], fixture_defs)
	state["obstacles"] = [{"id": "crate", "object_id": "crate", "statuses": {},
		"position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var after := _apply(state, _plan(state, "w", "wizard_blast"), "blast on crate")
	var crate: Dictionary = after["obstacles"][0]
	_check(crate.get("hp") == 6, "Blast deals its configured nonlethal damage to the crate")
	_check(crate.get("statuses", {}).is_empty(), "Object without turns receives no turn-bound reflect status")
	var character_state := _state([
		_unit("w", "heroes", "wizard", Vector2i.ZERO),
		_unit("enemy", "enemies", "enemy", Vector2i(1, 0))
	], fixture_defs)
	var character_after := _apply(character_state, _plan(character_state, "w", "wizard_blast"), "blast on character")
	_check(_find(character_after, "enemy").get("hp") == 6,
		"Same blast deals configured nonlethal damage to a character")
	_check(rules.has_status_handler(character_after, "enemy", "reflect")
		and rules.status(character_after, "enemy", "aura").get("source_id") == "w",
		"Surviving character still receives the reflect status from the wizard")


func _test_wizard_pull() -> void:
	var state := _state([
		_unit("w", "heroes", "wizard", Vector2i(1, 1)),
		_unit("near", "enemies", "enemy", Vector2i(1, 2)),
		_unit("chosen", "enemies", "enemy", Vector2i(4, 1))
	])
	var result := _apply(state, _plan(state, "w", "wizard_pull", "chosen"), "wizard_pull")
	var chosen := _find(result, "chosen")
	_check(chosen.get("position") == Vector2i(1, 1), "Pull moves selected target to wizard former cell")
	_check(chosen.get("hp", 0) == 10, "Pull does not damage target by default")
	_check(_find(result, "w").get("hp", 10) < 10, "Pull recoils on wizard")
	_check(_find(result, "w").get("position") == Vector2i(0, 1), "Pull recoils wizard one tile away")
	_check(rules.has_status_handler(result, "w", "skip_action"), "Pull knocks wizard down")
	_check(_find(result, "near").get("hp", 0) == 10, "Pull respects selected target rather than nearest")


func _test_recovery_expires_turn_end_status() -> void:
	var state := _state([
		_unit("h", "heroes", "healer", Vector2i(1, 1)),
		_unit("enemy", "enemies", "enemy", Vector2i(2, 1)),
		_unit("w", "heroes", "wizard", Vector2i(3, 1)),
		_unit("civilian", "civilian", "civilian", Vector2i(8, 8))
	])
	state = _apply(state, _plan(state, "h", "healer_bonk", "enemy"), "taunting bonk")
	state = _apply(state, _plan(state, "w", "wizard_blast"), "knockdown blast")
	_check(rules.has_status_handler(state, "enemy", "retarget")
		and rules.status(state, "enemy", "taunt").get("source_id") == "h",
		"Fixture has a valid active taunt from the living healer")
	_check(rules.has_status_handler(state, "enemy", "skip_action"),
		"Fixture has a knockdown that skips the enemy's action")
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(state == before and plan.get("valid", false), "Recovery round previews without mutating input")
	var after: Dictionary = rules.commit_round(state, plan)
	var recovered := false
	for event in plan.get("events", []):
		if event.get("type", "") == "recover" and event.get("unit_id", "") == "enemy":
			recovered = true
	_check(recovered, "Knocked-down enemy spends its turn recovering")
	_check(_find(after, "enemy").get("position") == _find(before, "enemy").get("position")
		and _find(after, "h").get("hp") == _find(before, "h").get("hp"),
		"Recovering enemy does not move or attack the taunt source")
	_check(not rules.has_status_handler(after, "enemy", "skip_action"),
		"Recovery consumes knockdown")
	_check(not rules.has_status_handler(after, "enemy", "retarget"),
		"Recovery still expires the end-of-turn taunt")


func _test_modes_and_restart() -> void:
	var initial: Dictionary = rules.new_game(definitions, "fixture")
	_check(initial.get("overrides", {}).is_empty(), "Hybrid starts without an override")
	var before := initial.duplicate(true)
	var selected: Dictionary = rules.choose_manual(initial, "knight", "knight_aura", "")
	_check(initial == before, "Choosing an override must not mutate input")
	_check(selected.get("overrides", {}) == {"knight": {"ability_id": "knight_aura", "target_id": ""}},
		"Override stores the selected command")
	var edited: Dictionary = rules.choose_manual(selected, "knight", "knight_push", "")
	_check(edited.get("overrides", {}) == {"knight": {"ability_id": "knight_push", "target_id": ""}},
		"Editing replaces the selected command")
	var restarted: Dictionary = rules.new_game(definitions, "fixture")
	var initial_facts := initial.duplicate()
	var restarted_facts := restarted.duplicate()
	initial_facts.erase("catalog")
	restarted_facts.erase("catalog")
	_check(restarted_facts == initial_facts, "Restart creates a clean initial state")


func _test_round_preview() -> void:
	var state := _state([
		_unit("k", "heroes", "knight", Vector2i(0, 0)),
		_unit("enemy", "enemies", "enemy", Vector2i(1, 0)),
		_unit("civilian", "civilian", "civilian", Vector2i(4, 4))
	])
	state["objective"]["destination"] = Vector2i(5, 4)
	var unselected := state.duplicate(true)
	state = rules.choose_manual(state, "k", "knight_push", "enemy")
	_check(unselected.get("overrides", {}).is_empty() and state.get("overrides", {}).get("k", {}) == \
		{"ability_id": "knight_push", "target_id": "enemy"},
		"Round fixture installs the knight's manual push without mutating its input")
	var before := state.duplicate(true)
	var action_plan: Dictionary = rules.preview(state, "k", "knight_push", "enemy")
	_check(action_plan.get("valid", false), "Fixture has a valid individual action preview")
	_check(rules.commit_round(state, action_plan) == before,
		"An individual action preview cannot be committed as a whole round")
	var plan = rules.call("preview_round", state)
	_check(state == before, "Round preview must not mutate state")
	if not plan is Dictionary:
		failures.append("Round preview must return a Dictionary")
		return
	_check(plan.get("events", []) is Array and not plan.get("events", []).is_empty(), "Round preview includes action and NPC events")
	var committed = rules.call("commit_round", state, plan)
	_check(state == before, "Round commit must not mutate input")
	if not committed is Dictionary:
		failures.append("Round commit must return a Dictionary")
		return
	_check(_find(committed, "enemy").get("position") == Vector2i(2, 0), "Round commits previewed hero order")
	_check(_find(committed, "civilian").get("position") == Vector2i(5, 4), "Round resolves civilian movement to exit")
	_check(committed.get("outcome") == "victory", "Round resolves victory when civilian reaches exit")
	var repeated = rules.call("commit_round", before, plan)
	_check(committed == repeated, "Same previewed plan commits identical NPC and victory outcomes")


func _test_elimination() -> void:
	var fixture_defs := definitions.duplicate(true)
	fixture_defs.missions.fixture.objective = {
		"handler": "defeat_all", "team": "enemies", "text": "Defeat enemies",
		"victory_text": "Victory", "defeat_text": "Defeat", "victory_event": "Victory"
	}
	fixture_defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Wiped"}]
	fixture_defs.encounters.fixture.deadline = 0
	var state := _state([
		_unit("w", "heroes", "wizard", Vector2i(1, 1)),
		_unit("e", "enemies", "enemy", Vector2i(2, 1), 4)
	], fixture_defs)
	state.objective = {"handler": "defeat_all", "team": "enemies"}
	state = rules.choose_manual(state, "w", "wizard_blast", "")
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(state == before and plan.get("valid", false), "Elimination forecast is valid and non-mutating")
	var won: Dictionary = rules.commit_round(state, plan)
	_check(_matches_preview(won, plan), "Elimination commit matches forecast")
	_check(_find(won, "e").get("hp", 1) <= 0 and won.get("outcome") == "victory",
		"Defeating the last enemy wins")

	var alive := _state([
		_unit("h", "heroes", "healer", Vector2i(0, 0), 0),
		_unit("w", "heroes", "wizard", Vector2i(9, 9)),
		_unit("e", "enemies", "enemy", Vector2i(5, 5))
	], fixture_defs)
	alive.objective = {"handler": "defeat_all", "team": "enemies"}
	alive.round = 20
	var continued: Dictionary = rules.commit_round(alive, rules.preview_round(alive))
	_check(continued.get("outcome") == "ongoing", "One knocked-out hero is not a party wipe, even after round ten")
	var wiped := alive.duplicate(true)
	_find(wiped, "w")["hp"] = 0
	var lost: Dictionary = rules.commit_round(wiped, rules.preview_round(wiped))
	_check(lost.get("outcome") == "defeat", "All heroes knocked out causes defeat")


func _test_movement_forecast_order() -> void:
	var state := _state([
		_unit("k", "heroes", "knight", Vector2i(1, 1)),
		_unit("w", "heroes", "wizard", Vector2i(4, 1)),
		_unit("e", "enemies", "enemy", Vector2i(8, 8)),
		_unit("civilian", "civilian", "civilian", Vector2i(9, 8))
	])
	state = rules.choose_manual(state, "k", "move", "2,1")
	var before := state.duplicate(true)
	var forecast: Dictionary = rules.state_before_action(state, "w")
	_check(state == before, "Turn forecast does not mutate its source")
	_check(_find(forecast, "k").get("position") == Vector2i(2, 1),
		"Later hero forecasts see the earlier hero's chosen move")
	var plan: Dictionary = rules.preview_round(state)
	var committed: Dictionary = rules.commit_round(state, plan)
	_check(_find(committed, "k").get("position") == Vector2i(2, 1),
		"Committed movement matches the later hero's forecast")


func _matches_preview(committed: Dictionary, plan: Dictionary) -> bool:
	var gameplay := committed.duplicate(true)
	gameplay.erase("_terminal_commit")
	return gameplay == plan.get("result")
