extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/rules_test.gd
# Fixtures deliberately own their positions and health rather than relying on tuning.
var failures: Array[String] = []
var rules: RefCounted


func _initialize() -> void:
	var script_path := "res://rules.gd"
	if not ResourceLoader.exists(script_path):
		# Keep the test executable before the implementation exists.
		rules = RefCounted.new()
		failures.append("Missing behavior: res://rules.gd is not implemented")
	else:
		var script = load(script_path)
		if script == null or not script.can_instantiate():
			failures.append("Missing behavior: rules.gd cannot be instantiated")
			rules = RefCounted.new()
		else:
			rules = script.new()

	var required := ["new_game", "options", "preview", "apply_plan", "advance_round", "choose_manual", "preview_round", "commit_round"]
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
		_test_wizard_pull()
		_test_modes_and_restart()
		_test_round_preview()
	if failures.is_empty():
		print("PASS: company rules")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, team: String, role: String, pos: Vector2i, hp: int = 10) -> Dictionary:
	return {
		"id": id, "team": team, "class": role, "position": pos,
		"hp": hp, "max_hp": 10, "knocked_down": false, "taunted_by": ""
	}


func _state(units: Array, mode: String = "hybrid", remaining: int = 1) -> Dictionary:
	return {"units": units, "terrain": [], "obstacles": [], "exit": Vector2i(9, 9),
		"orders": {}, "mode": mode, "round": 1, "manual_remaining": remaining}


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
	blocked["obstacles"] = [{"id": "wall", "position": Vector2i(3, 1), "hp": 10, "max_hp": 10}]
	var collision := _apply(blocked, _plan(blocked, "k", "knight_push", "e"), "knight_push collision")
	_check(_find(collision, "e").get("hp", 10) < 10, "Push collision damages target")


func _test_crate_targets() -> void:
	for entry in [["k", "knight", "knight_push"], ["h", "healer", "healer_bonk"]]:
		var state := _state([_unit(entry[0], "heroes", entry[1], Vector2i.ZERO)])
		state["obstacles"] = [
			{"id": "adjacent", "position": Vector2i(1, 0), "hp": 10, "max_hp": 10},
			{"id": "far", "position": Vector2i(2, 0), "hp": 10, "max_hp": 10},
			{"id": "destroyed", "position": Vector2i(0, 1), "hp": 0, "max_hp": 10}
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
	wizard_state["obstacles"] = [{"id": "crate", "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var wizard_choices = rules.call("targets", wizard_state, "w", "wizard_pull")
	for choice in wizard_choices:
		_check(choice.get("id", "") != "crate", "Wizard pull does not offer crates")
	var wizard_plan = rules.call("preview", wizard_state, "w", "wizard_pull", "crate")
	_check(wizard_plan is Dictionary and not wizard_plan.get("valid", false), "Wizard pull cannot target crates")


func _test_crate_actions() -> void:
	var push_state := _state([_unit("k", "heroes", "knight", Vector2i.ZERO)])
	push_state["obstacles"] = [{"id": "crate", "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var pushed := _apply(push_state, _plan(push_state, "k", "knight_push", "crate"), "crate push")
	var crate: Dictionary = pushed.get("obstacles", [{}])[0]
	_check(crate.get("position") == Vector2i(2, 0), "Free crate push moves crate one tile")
	_check(crate.get("hp", 0) == 10, "Free crate push does not damage crate")

	var blocked := push_state.duplicate(true)
	blocked["obstacles"].append({"id": "wall", "position": Vector2i(2, 0), "hp": 10, "max_hp": 10})
	var collision := _apply(blocked, _plan(blocked, "k", "knight_push", "crate"), "blocked crate push")
	var blocked_crate: Dictionary = collision.get("obstacles", [{}])[0]
	_check(blocked_crate.get("position") == Vector2i(1, 0), "Blocked crate stays in place")
	_check(blocked_crate.get("hp", 10) < 10, "Blocked crate push damages crate")

	var bonk_state := _state([_unit("h", "heroes", "healer", Vector2i.ZERO)])
	bonk_state["obstacles"] = [{"id": "crate", "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var bonk_plan := _plan(bonk_state, "h", "healer_bonk", "crate")
	var bonked := _apply(bonk_state, bonk_plan, "crate bonk")
	var bonked_crate: Dictionary = bonked.get("obstacles", [{}])[0]
	_check(bonked_crate.get("hp", 10) < 10, "Bonk damages crate")
	_check(not bonked_crate.has("taunted_by"), "Bonk does not taunt crate")
	for event in bonk_plan.get("events", []):
		_check(event.get("type", "") != "taunt", "Bonk on crate emits no taunt")

	var aura_state := _state([
		_unit("h", "heroes", "healer", Vector2i.ZERO),
		_unit("k", "heroes", "knight", Vector2i(1, 1)),
		_unit("enemy", "enemies", "enemy", Vector2i(2, 0))
	])
	aura_state["obstacles"] = [{"id": "crate", "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var aura_active := _apply(aura_state, _plan(aura_state, "k", "knight_aura"), "knight_aura")
	var aura_bonk := _plan(aura_active, "h", "healer_bonk", "crate")
	var aura_after := _apply(aura_active, aura_bonk, "crate bonk near aura")
	_check(aura_after.get("obstacles", [{}])[0].get("hp", 10) < 10, "Aura does not protect a bonked crate")
	_check(_find(aura_after, "enemy").get("hp", 10) == 10, "Crate bonk near aura does not damage enemy")
	_check(_find(aura_after, "enemy").get("taunted_by", "") == "", "Crate bonk near aura does not taunt enemy")
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
	state["obstacles"] = [{"id": "rock", "position": Vector2i(1, 2), "hp": 10, "max_hp": 10}]
	var protected := _apply(state, _plan(state, "k", "knight_aura"), "knight_aura")
	var after := _apply(protected, _plan(protected, "attacker", "enemy_harpoon", "k"), "enemy_harpoon")
	_check(_find(after, "k").get("hp", 0) == 10, "Aura prevents range-two harpoon damage")
	_check(after.get("obstacles", [{}])[0].get("hp", 10) < 10, "Aura reflects to nearest obstacle rather than attacker")
	_check(_find(after, "attacker").get("hp", 10) == 10, "Aura does not automatically reflect to attacker")


func _test_aura_redirects_friendly_attacks() -> void:
	# The friendly-fire ward and the alternate enemy are both inside the aura.
	# The redirected attack must hit once, not bounce back through the aura.
	var state := _state([
		_unit("k", "heroes", "knight", Vector2i.ZERO),
		_unit("ward", "heroes", "healer", Vector2i(1, 0)),
		_unit("w", "heroes", "wizard", Vector2i(2, 0)),
		_unit("recipient", "enemies", "enemy", Vector2i(-1, 0))
	])
	var baseline := _apply(state, _plan(state, "w", "wizard_blast"), "unshielded blast")
	var blast_damage: int = 10 - _find(baseline, "ward").get("hp", 10)
	_check(blast_damage > 0, "Unshielded friendly-fire blast has positive damage")
	var protected := _apply(state, _plan(state, "k", "knight_aura"), "knight_aura")
	var after := _apply(protected, _plan(protected, "w", "wizard_blast"), "shielded blast")
	_check(_find(after, "ward").get("hp", 0) == 10, "Aura prevents friendly-fire blast damage to ward")
	_check(not _find(after, "ward").get("knocked_down", false), "Ward does not receive redirected blast knockdown")
	_check(_find(after, "recipient").get("hp", 10) == 10 - blast_damage, "Nearest alternate enemy receives exactly the original blast damage once")
	_check(_find(after, "recipient").get("knocked_down", false), "Reflected blast knocks down its actual recipient")
	_check(_find(after, "k").get("hp", 0) == 10, "Reflection does not loop back into the aura")
	_check(_find(after, "w").get("hp", 0) == 10, "Reflection does not damage the original attacker instead")

	# A shielded enemy can also be the initial ward. An adjacent obstacle is
	# the nearest eligible alternate recipient of the healer's attack.
	var bonk_state := _state([
		_unit("k", "heroes", "knight", Vector2i.ZERO),
		_unit("enemy", "enemies", "enemy", Vector2i(1, 0)),
		_unit("h", "heroes", "healer", Vector2i(2, 0))
	])
	bonk_state["obstacles"] = [{"id": "rock", "position": Vector2i(1, 1), "hp": 10, "max_hp": 10}]
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
	_check(enemy.get("taunted_by", "") == "h", "Healer bonk taunts enemy toward healer")


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
	var self_state := _state([_unit("h", "heroes", "healer", Vector2i.ZERO, 5), _unit("ally", "heroes", "knight", Vector2i(1, 0), 10), _unit("far", "heroes", "wizard", Vector2i(2, 0), 5)])
	var self_result := _apply(self_state, _plan(self_state, "h", "healer_heal"), "healer_heal")
	_check(_find(self_result, "h").get("hp", 0) == 5, "Heal excludes healer")
	_check(_find(self_result, "far").get("hp", 0) == 5, "Heal does not skip a full nearest ally")


func _test_wizard_blast() -> void:
	var state := _state([
		_unit("w", "heroes", "wizard", Vector2i.ZERO),
		_unit("ally", "heroes", "knight", Vector2i(1, 0)),
		_unit("enemy", "enemies", "enemy", Vector2i(3, 0))
	])
	var result := _apply(state, _plan(state, "w", "wizard_blast"), "wizard_blast")
	_check(_find(result, "ally").get("hp", 10) < 10, "Blast targets nearest unit even when allied")
	_check(_find(result, "ally").get("knocked_down", false), "Blast knocks its target down")
	_check(_find(result, "enemy").get("hp", 0) == 10, "Blast does not hit more distant enemy instead")
	var obstacle_state := _state([
		_unit("w", "heroes", "wizard", Vector2i.ZERO),
		_unit("enemy", "enemies", "enemy", Vector2i(3, 0))
	])
	obstacle_state["obstacles"] = [{"id": "rock", "position": Vector2i(1, 0), "hp": 10, "max_hp": 10}]
	var obstacle_result := _apply(obstacle_state, _plan(obstacle_state, "w", "wizard_blast"), "wizard_blast")
	_check(obstacle_result.get("obstacles", [{}])[0].get("hp", 10) < 10, "Blast targets nearest obstacle")
	_check(_find(obstacle_result, "enemy").get("hp", 0) == 10, "Blast does not bypass a nearer obstacle")


func _test_wizard_pull() -> void:
	var state := _state([
		_unit("w", "heroes", "wizard", Vector2i.ZERO),
		_unit("near", "enemies", "enemy", Vector2i(0, 1)),
		_unit("chosen", "enemies", "enemy", Vector2i(3, 0))
	])
	var result := _apply(state, _plan(state, "w", "wizard_pull", "chosen"), "wizard_pull")
	var chosen := _find(result, "chosen")
	_check(chosen.get("position") == Vector2i.ZERO, "Pull moves selected target to wizard former cell")
	_check(chosen.get("hp", 0) == 10, "Pull does not damage target by default")
	_check(_find(result, "w").get("hp", 10) < 10, "Pull recoils on wizard")
	_check(_find(result, "w").get("position") == Vector2i(-1, 0), "Pull recoils wizard one tile away")
	_check(_find(result, "w").get("knocked_down", false), "Pull knocks wizard down")
	_check(_find(result, "near").get("hp", 0) == 10, "Pull respects selected target rather than nearest")


func _test_modes_and_restart() -> void:
	for pair in [["hybrid", 1], ["direct", 3], ["standing", 0]]:
		var mode: String = pair[0]
		var budget: int = pair[1]
		var initial = rules.call("new_game", mode)
		if not initial is Dictionary:
			failures.append("%s new_game must return Dictionary" % mode)
			continue
		_check(initial.get("manual_remaining", -1) == budget, "%s starts with %d manual slots" % [mode, budget])
		var exhausted: Dictionary = initial.duplicate(true)
		# Direct mode has exactly three heroes and three slots. Add a fourth
		# living hero so overflow attempts a new override, not an edit.
		if mode == "direct":
			exhausted["units"].append(_unit("spare", "heroes", "knight", Vector2i(0, 0)))
		var overflow_id: String = "healer" if mode == "hybrid" else ("spare" if mode == "direct" else "knight")
		var overflow_action: String = "healer_heal" if mode == "hybrid" else "knight_aura"
		var valid = rules.call("preview", exhausted, overflow_id, overflow_action, "")
		_check(valid is Dictionary and valid.get("valid", false), "%s overflow action must be legal for a living hero" % mode)
		if mode != "standing":
			var accepted = rules.call("choose_manual", exhausted, overflow_id, overflow_action, "")
			_check(accepted is Dictionary and accepted.get("manual_remaining", -1) == budget - 1,
				"%s overflow action must be accepted when a slot is available" % mode)
		var choices := [["knight", "knight_aura"], ["healer", "healer_heal"], ["wizard", "wizard_blast"]]
		for i in range(budget):
			var choice: Array = choices[i]
			var previous: Dictionary = exhausted.duplicate(true)
			var action_plan = rules.call("preview", exhausted, choice[0], choice[1], "")
			_check(action_plan is Dictionary and action_plan.get("valid", false), "%s prior override %d must be legal" % [mode, i + 1])
			var selected = rules.call("choose_manual", exhausted, choice[0], choice[1], "")
			_check(exhausted == previous, "%s prior override must not mutate input" % mode)
			if not selected is Dictionary:
				failures.append("%s prior override must return Dictionary" % mode)
				break
			exhausted = selected
			_check(exhausted.get("manual_remaining", -1) == budget - i - 1,
				"%s prior override %d consumes one slot" % [mode, i + 1])
		_check(exhausted.get("manual_remaining", -1) == 0, "%s has exhausted its manual slots" % mode)
		var before := exhausted.duplicate(true)
		var rejected = rules.call("choose_manual", exhausted, overflow_id, overflow_action, "")
		_check(exhausted == before and rejected == before, "%s rejects a manual choice when exhausted" % mode)
		var next = rules.call("advance_round", exhausted)
		_check(exhausted == before, "%s advance_round must not mutate input" % mode)
		if next is Dictionary:
			_check(next.get("manual_remaining", -1) == budget, "%s restores manual budget each round" % mode)
			_check(next.get("round", 0) == initial.get("round", 1) + 1, "%s advances round" % mode)
		else:
			failures.append("%s advance_round must return Dictionary" % mode)
		var restarted = rules.call("new_game", mode)
		_check(restarted == initial, "%s restart creates a clean initial state" % mode)

	# Use a controlled legal choice to verify actual slot consumption.
	for pair in [["hybrid", 1], ["direct", 3]]:
		var state := _state([_unit("k", "heroes", "knight", Vector2i.ZERO)], pair[0], pair[1])
		var before := state.duplicate(true)
		var selected = rules.call("choose_manual", state, "k", "knight_aura", "")
		_check(state == before, "%s manual choice must not mutate input" % pair[0])
		if selected is Dictionary:
			_check(selected.get("manual_remaining", -1) == pair[1] - 1, "%s consumes exactly one slot" % pair[0])
			var edited = rules.call("choose_manual", selected, "k", "knight_push", "")
			_check(edited is Dictionary and edited.get("manual_remaining", -1) == pair[1] - 1,
				"%s editing an override does not consume another slot" % pair[0])
		else:
			failures.append("%s manual choice must return Dictionary" % pair[0])


func _test_round_preview() -> void:
	var state := _state([
		_unit("k", "heroes", "knight", Vector2i(0, 0)),
		_unit("enemy", "enemies", "enemy", Vector2i(1, 0)),
		_unit("civilian", "civilian", "civilian", Vector2i(4, 4))
	])
	state["exit"] = Vector2i(5, 4)
	state["orders"] = {"k": {"ability_id": "knight_push", "target_id": "enemy"}}
	var before := state.duplicate(true)
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
	_check(committed.get("victory", false), "Round resolves victory when civilian reaches exit")
	var repeated = rules.call("commit_round", before, plan)
	_check(committed == repeated, "Same previewed plan commits identical NPC and victory outcomes")
