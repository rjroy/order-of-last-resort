extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/objective_terminal_regression_test.gd
const Board = preload("res://rules/board.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Rules = preload("res://rules.gd")
const WAGON_FAILURE := "The quartermaster reports that {subject_label} was lost at {position}."
const WAGON_REPORT := "The quartermaster reports that Civilian was lost at B3."

var rules := Rules.new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_hopeless_ritual()
	_test_ritual_with_summons()
	_test_wagon_failure_copy()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: objective terminal regressions")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_hopeless_ritual() -> void:
	var state := _ritual([_unit("wizard", "wizard", Vector2i(3, 3)),
		_unit("knight", "knight", Vector2i(3, 2), 4), _unit("enemy", "harpooner", Vector2i(3, 5))],
		["wizard", "knight"])
	if state.is_empty():
		return
	_check(_round(state).outcome == "ongoing", "Two heroes and one enemy can still fill all three circles")
	state = rules.choose_manual(state, "wizard", "wizard_blast")
	var blasted := _round(state)
	_check(not Board.alive(Board.entity(blasted, "knight")), "Legal friendly-fire Blast defeats the Knight")
	_check(Board.alive(Board.entity(blasted, "enemy")), "The living enemy counts, but two bodies are not enough")
	_check(blasted.outcome == "defeat", "Ritual fails as soon as Blast leaves too few possible occupants")
	_check(rules.is_committed_terminal(blasted), "Hopeless ritual produces a committed terminal result")
	_check(not rules.mission_result_text(blasted).is_empty(), "Hopeless ritual explains the defeat")

	var solo := _ritual([_unit("wizard", "wizard", Vector2i(3, 3)),
		_unit("enemy", "harpooner", Vector2i(3, 4), 0)], ["wizard"])
	if not solo.is_empty():
		_check(_round(solo).outcome == "defeat", "A lone Wizard cannot use eligible enemy corpses")


func _test_ritual_with_summons() -> void:
	var solo := _ritual([_unit("necro", "necromancer", Vector2i(3, 3)),
		_unit("enemy", "harpooner", Vector2i(3, 4), 0),
		_unit("fallen_ally", "knight", Vector2i(2, 3), 0)], ["necro"])
	if solo.is_empty():
		return
	_check(_round(solo).outcome == "ongoing", "Lone Necromancer can still summon a skeleton and raise a corpse")
	var summoned := _round(rules.choose_manual(solo, "necro", "summon_skeleton", "4,3"))
	_check(summoned.outcome == "ongoing" and Board.alive(Board.entity(summoned, "necro_skeleton")),
		"A living skeleton counts, and one pending Raise Dead is enough")
	if summoned.outcome == "ongoing":
		var raised := _round(rules.choose_manual(summoned, "necro", "raise_dead", "enemy"))
		_check(raised.outcome == "ongoing" and raised.objective.held_turns == 1,
			"Raising the enemy on the last circle begins the ritual")
		_check(_round(raised).outcome == "victory", "Necromancer and both summons can complete the ritual")

	var no_corpse := summoned.duplicate(true)
	Board.entity(no_corpse, "enemy")["corpse_consumed"] = true
	_check(_round(no_corpse).outcome == "defeat", "A living skeleton cannot be counted twice, and consumed or friendly corpses cannot be raised")

	var occupied_corpse := solo.duplicate(true)
	Board.entity(occupied_corpse, "enemy").position = Board.entity(occupied_corpse, "necro").position
	_check(_round(occupied_corpse).outcome == "ongoing", "A temporarily occupied corpse can be raised after its cell clears")


func _test_wagon_failure_copy() -> void:
	var defs := _definitions()
	defs.missions.fixture.objective.merge({"handler": "wagon"}, true)
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Party lost"},
		{"handler": "subject_dead", "event": WAGON_FAILURE}]
	var state := rules.new_game(defs, "fixture")
	_check(not state.is_empty(), "Wagon fixture builds")
	if state.is_empty():
		return
	Board.entity(state, "civilian").hp = 0
	var lost := _round(state)
	_check(lost.outcome == "defeat", "Destroyed wagon loses")
	_check(rules.mission_result_text(lost) == WAGON_REPORT, "Wagon defeat formats the authored subject_dead event")
	for id in ["knight", "healer", "wizard"]:
		Board.entity(state, id).hp = 0
	_check(rules.mission_result_text(_round(state)) == "Party lost", "Party wipe outranks the authored wagon failure")


func _round(state: Dictionary) -> Dictionary:
	var plan := rules.preview_round(state)
	_check(plan.get("valid", false), "Regression round forecasts")
	var result := rules.commit_round(state, plan)
	var comparable := result.duplicate(true)
	comparable.erase("_terminal_commit")
	_check(comparable == plan.result, "Forecast agrees with commit")
	return result


func _unit(id: String, character: String, cell: Vector2i, hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": cell, "hp": hp, "max_hp": 10, "statuses": {}}


func _ritual(units: Array, party: Array) -> Dictionary:
	var defs := _definitions()
	var objective: Dictionary = defs.missions.fixture.objective
	objective.erase("subject")
	objective.erase("destination")
	objective.merge({"handler": "ritual", "circles": "circles", "required_turns": 2}, true)
	var state := rules.new_game(defs, "fixture")
	_check(not state.is_empty(), "Ritual fixture builds")
	if not state.is_empty():
		state.units = units
		state["party"] = party
	return state


func _definitions() -> Dictionary:
	var defs := Fixture.definitions()
	for profile in defs.classes.values():
		profile.erase("behavior")
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Party lost"}]
	defs.boards.fixture["zones"] = {"circles": [[3, 3], [4, 3], [3, 4]]}
	defs.capabilities["minion"] = {"label": "Minion"}
	defs.classes["minion"] = {"team": "heroes", "art_key": "unit", "max_hp": 2, "habits": {},
		"abilities": ["move"], "capabilities": ["minion", "mobile", "blocks_movement"]}
	defs.characters["necromancer"] = {"class": "wizard", "label": "Necromancer",
		"abilities": ["move", "summon_skeleton", "raise_dead"]}
	for kind in ["skeleton", "zombie"]:
		defs.characters[kind] = {"class": "minion", "label": kind}
	defs.events["summon"] = {"text": "{actor} calls {position}"}
	defs.events["raise"] = {"text": "{actor} raises {corpse}"}
	defs.abilities["summon_skeleton"] = {"label": "Summon", "help": "Summon", "handler": "summon",
		"params": {"character": "skeleton", "priority": 0}, "targeting": {"kind": "cell", "range": 1}}
	defs.abilities["raise_dead"] = {"label": "Raise", "help": "Raise", "handler": "summon",
		"params": {"character": "zombie", "priority": 1}, "targeting": {"kind": "entity", "teams": ["enemies"]}}
	return defs
