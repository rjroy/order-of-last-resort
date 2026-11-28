extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtester_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Rules = preload("res://rules/rules.gd")
const RUNNER_PATH = "res://tools/road_balance/road_playtester.gd"

var rules = Rules.new()
var runner: RefCounted
var failures: Array[String] = []


func _initialize() -> void:
	if not ResourceLoader.exists(RUNNER_PATH):
		failures.append("Missing behavior: road playtester run_case is not implemented")
	else:
		var script = load(RUNNER_PATH)
		if script == null or not script.can_instantiate():
			failures.append("Missing behavior: road playtester cannot be instantiated")
		else:
			runner = script.new()
			if not runner.has_method("run_case"):
				failures.append("Missing behavior: road playtester.run_case()")
			else:
				_test_replay_and_outcomes()
				_test_pressure_and_carryover()
				_test_invalid_policy()
				_test_staged_opening()
				_test_late_enemy()
	if failures.is_empty():
		print("PASS: deterministic road playtester contract")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": hp, "max_hp": 10, "statuses": {}}


func _state(enemy_hp: int, enemy_position: Vector2i, hero_hp := 10,
		blast_knockdown := true, enemy_behavior := true) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.missions.fixture.objective = {"handler": "defeat_all", "team": "enemies",
		"text": "Defeat enemies", "victory_text": "Victory", "defeat_text": "Defeat",
		"victory_event": "Victory"}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Wiped"}]
	defs.encounters.fixture.deadline = 0
	defs.abilities.wizard_blast.targeting.merge({"range": 4, "direct": {"help": "Aim"}}, true)
	if not blast_knockdown:
		defs.abilities.wizard_blast.params.status = "taunt"
	if not enemy_behavior:
		defs.classes.enemy.erase("behavior")
	var state: Dictionary = rules.new_game(defs, "fixture")
	state.units = [_unit("w", "wizard", Vector2i(1, 1), hero_hp),
		_unit("e", "harpooner", enemy_position, enemy_hp)]
	state.terrain = []
	state.obstacles = []
	state.orders = {}
	state.objective = {"handler": "defeat_all", "team": "enemies"}
	return state


func _run(state: Dictionary, policy: String, limit: int) -> Dictionary:
	var result: Variant = runner.run_case(rules, state, policy, limit)
	if not result is Dictionary:
		failures.append(policy + ": run_case must return a Dictionary")
		return {}
	return result


func _replay(initial: Dictionary, result: Dictionary, label: String) -> Dictionary:
	var trace: Variant = result.get("rounds")
	if not trace is Array:
		failures.append(label + ": rounds must be an Array")
		return {}
	var state := initial.duplicate(true)
	for row in trace:
		if not row is Dictionary or not row.get("draft") is Dictionary or not row.get("events") is Array:
			failures.append(label + ": each round needs a draft Dictionary and events Array")
			return {}
		var draft: Dictionary = row.draft
		if not draft.is_empty():
			if not (draft.get("unit_id") is String and draft.get("ability_id") is String \
					and draft.get("target_id") is String):
				failures.append(label + ": draft needs string unit_id, ability_id and target_id")
				return {}
			var selected: Dictionary = rules.choose_manual(state, draft.unit_id, draft.ability_id, draft.target_id)
			if not selected.overrides.has(draft.unit_id):
				failures.append(label + ": draft is not an accepted direct command")
				return {}
			var before_action: Dictionary = rules.state_before_action(state, draft.unit_id)
			var action: Dictionary = rules.preview(before_action, draft.unit_id, draft.ability_id, draft.target_id, true)
			_check(action.valid, label + ": draft must be legal on the actor's turn board")
			state = selected
		var plan: Dictionary = rules.preview_round(state)
		_check(plan.valid and plan.events == row.events, label + ": logged events must replay exactly")
		state = rules.commit_round(state, plan)
	return state


func _test_replay_and_outcomes() -> void:
	var saw_command := false
	for policy in ["wizard_first", "forecast_first"]:
		var initial := _state(4, Vector2i(2, 1))
		var before := initial.duplicate(true)
		var result := _run(initial, policy, 4)
		var repeat := _run(initial, policy, 4)
		_check(initial == before, policy + ": opening must remain unchanged")
		_check(result == repeat, policy + ": full in-memory result must be deterministic")
		_check(result.get("status") in ["victory", "defeat", "round_limit"], policy + ": valid status required")
		_check(result.get("metrics") is Dictionary, policy + ": metrics Dictionary required")
		var after := _replay(initial, result, policy)
		if not after.is_empty():
			var expected: String = "round_limit" if after.outcome == "ongoing" else after.outcome
			_check(result.get("status") == expected, policy + ": status must match committed outcome")
			if policy == "wizard_first":
				_check(expected == "victory", "wizard-first can win the controlled one-hit fight")
		for row in result.get("rounds", []):
			if row is Dictionary and row.get("draft") is Dictionary and not row.draft.is_empty():
				saw_command = true
	_check(saw_command, "controlled reachable enemy requires at least one nonempty direct command")

	# A cap is not a defeat. With nobody in reach, one round cannot end this fight.
	var far := _state(10, Vector2i(11, 11))
	var capped := _run(far, "wizard_first", 1)
	var after_cap := _replay(far, capped, "cap")
	_check(not after_cap.is_empty() and after_cap.outcome == "ongoing"
		and capped.get("status") == "round_limit", "ongoing fight at cap is not a defeat")
	_check_health(capped, after_cap, false, "cap")
	var wiped := _state(10, Vector2i(2, 1), 0)
	var lost := _run(wiped, "forecast_first", 1)
	var after_loss := _replay(wiped, lost, "wiped")
	_check(not after_loss.is_empty() and after_loss.outcome == "defeat"
		and lost.get("status") == "defeat", "a committed party wipe is a defeat")
	_check_health(lost, after_loss, false, "defeat")

	# A fallen companion rejoins at one only after a victory.
	var victory := _state(4, Vector2i(2, 1))
	victory.units.append(_unit("h", "healer", Vector2i(0, 1), 0))
	var won := _run(victory, "wizard_first", 1)
	var after_win := _replay(victory, won, "fallen victory")
	_check(won.get("status") == "victory", "fallen companion fixture wins")
	_check_health(won, after_win, true, "fallen victory")
	var metrics: Dictionary = won.get("metrics", {})
	_check(metrics.get("ending_hp", {}).get("h") == 0
		and metrics.get("carryover_hp", {}).get("h") == 1,
		"fallen hero has zero ending HP and one projected victory carryover HP")


func _check_health(result: Dictionary, after: Dictionary, victory: bool, label: String) -> void:
	if after.is_empty() or not result.get("metrics") is Dictionary:
		failures.append(label + ": ending metrics require replayed state")
		return
	var metrics: Dictionary = result.metrics
	var ending: Variant = metrics.get("ending_hp")
	var carry: Variant = metrics.get("carryover_hp")
	_check(ending is Dictionary, label + ": ending_hp must report raw HP")
	if not victory:
		_check(carry == null or (carry is Dictionary and carry.is_empty()),
			label + ": non-victory has no projected carryover HP")
	else:
		_check(carry is Dictionary, label + ": victory has projected carryover HP")
	for unit in after.units:
		if unit.id not in ["w", "h"]:
			continue
		_check(ending is Dictionary and ending.get(unit.id) == unit.hp,
			label + ": ending HP matches committed " + unit.id)
		if victory:
			_check(carry is Dictionary and carry.get(unit.id) == maxi(1, unit.hp),
				label + ": victory carryover projects " + unit.id)


func _test_pressure_and_carryover() -> void:
	# The enemy can attack in the opening unless the command suppresses it.
	# Replay establishes the expected damage and whether the enemy actually acts.
	for enemy_hp in [4, 10]:
		# The higher-HP variant survives Blast without knockdown and can attack.
		var initial := _state(enemy_hp, Vector2i(2, 1), 6, enemy_hp != 10)
		var result := _run(initial, "wizard_first", 1)
		var after := _replay(initial, result, "pressure")
		var metrics: Variant = result.get("metrics")
		if after.is_empty() or not metrics is Dictionary:
			failures.append("pressure: metrics and replayed state required")
			continue
		_check_health(result, after, result.get("status") == "victory", "pressure")
		var fallen: Variant = metrics.get("fallen_heroes")
		var actions: Variant = metrics.get("enemy_actions_by_round")
		_check(fallen is Array and (("w" in fallen) == (after.units[0].hp <= 0)),
			"fallen_heroes records knocked-out company members")
		var trace: Array = result.get("rounds", [])
		if trace.size() != 1 or not trace[0] is Dictionary or not trace[0].get("events") is Array:
			failures.append("pressure: one round of events required")
			continue
		var enemy_acted := false
		for event in trace[0].events:
			if event.get("type") == "damage" and event.get("source_id") == "e":
				enemy_acted = true
		_check(enemy_acted == (enemy_hp == 10),
			"controlled opening distinguishes a suppressed enemy from an attacker")
		_check(actions is Array and actions.size() == 1 and actions[0] == int(enemy_acted),
			"opening enemy action count excludes skipped or defeated turns")

	# A distant enemy with no behavior must hold, not produce pressure.
	var idle := _state(10, Vector2i(11, 11), 10, true, false)
	var result := _run(idle, "wizard_first", 1)
	var metrics: Dictionary = result.get("metrics", {})
	var actions: Variant = metrics.get("enemy_actions_by_round")
	_check(actions is Array and actions.size() == 1 and actions[0] == 0,
		"enemy Hold is not an action creating pressure")


func _test_invalid_policy() -> void:
	var result := _run(_state(4, Vector2i(2, 1)), "not_a_policy", 1)
	_check(result.has("error") and not str(result.error).is_empty()
		and result.get("status", "") not in ["victory", "defeat", "round_limit"],
		"unsupported policy must report an explicit error, not an outcome")


func _test_staged_opening() -> void:
	var initial := _state(4, Vector2i(2, 1))
	var staged: Dictionary = rules.choose_manual(initial, "w", "wizard_blast", "e")
	_check(staged.get("overrides", {}).has("w"), "staged-opening fixture has an override")
	var before := staged.duplicate(true)
	var result := _run(staged, "wizard_first", 1)
	_check(staged == before, "rejecting staged opening must not mutate it")
	_check(result.has("error") and not str(result.error).is_empty()
		and not result.has("status") and not result.has("rounds") and not result.has("metrics"),
		"pre-staged opening must return an explicit error and no result")


func _test_late_enemy() -> void:
	var defs: Dictionary = Fixture.definitions()
	defs.missions.fixture.objective = {"handler": "defeat_all", "team": "enemies",
		"text": "Defeat all", "victory_text": "Victory", "defeat_text": "Defeat",
		"victory_event": "Victory"}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Wiped"}]
	defs.encounters.fixture.deadline = 0
	defs.classes.still_enemy = defs.classes.enemy.duplicate(true)
	defs.classes.still_enemy.erase("behavior")
	defs.classes.healer.abilities = ["healer_bonk", "healer_heal"]
	defs.characters.harpooner.class = "still_enemy"
	defs.characters.bell_undead = {"class": "enemy", "label": "Bell undead"}
	var state: Dictionary = rules.new_game(defs, "fixture")
	if state.is_empty():
		failures.append("bell: controlled catalog must build")
		return
	state.units = [_unit("healer", "healer", Vector2i(3, 3), 10),
		_unit("first", "harpooner", Vector2i(4, 3), 2),
		_unit("crew", "harpooner", Vector2i(10, 10), 100)]
	state.orders = {}
	state.terrain = []
	state.obstacles = []
	state.objective["corpse_bell"] = {"character": "bell_undead"}
	var staged: Dictionary = rules.choose_manual(state, "healer", "healer_bonk", "first")
	var first: Dictionary = rules.preview_round(staged)
	if not first.valid:
		failures.append("bell: first fall must be legal")
		return
	state = rules.commit_round(staged, first)
	_check(first.events.any(func(event): return event.get("type") == "corpse_bell_marked"),
		"bell: actual first fall marks a corpse")
	_check(state.overrides.is_empty() and state.outcome == "ongoing",
		"bell: runner starts without a staged command")
	var result := _run(state, "forecast_first", 2)
	var after := _replay(state, result, "bell")
	var rounds: Variant = result.get("rounds")
	if after.is_empty() or not rounds is Array or rounds.size() != 2:
		failures.append("bell: two replayable rounds are required")
		return
	var raised := ""
	for event in rounds[0].events:
		if event.get("type") == "corpse_bell_raised":
			raised = event.get("unit_id", "")
	_check(not raised.is_empty(), "bell: a new hostile appears after the first runner round")
	var acted := false
	for event in rounds[1].events:
		if event.get("resolved_action", {}).get("unit_id") == raised and not raised.is_empty():
			acted = true
	_check(acted, "bell: newly raised hostile actually acts in the next round")
	var draft: Dictionary = rounds[1].draft
	_check(draft.get("ability_id") == "healer_bonk" and draft.get("target_id") == raised,
		"bell: forecast scoring values damage to the newly raised hostile")
	var metrics: Dictionary = result.get("metrics", {})
	var actions: Variant = metrics.get("enemy_actions_by_round")
	_check(actions is Array and actions.size() == 2 and actions[0] == 0 and actions[1] == 1,
		"bell: newly raised hostile's first action counts as enemy pressure")
