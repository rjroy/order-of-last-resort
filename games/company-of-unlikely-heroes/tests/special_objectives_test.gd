extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/special_objectives_test.gd
# Controlled boards test rules, not the coordinates or balance of authored encounters.
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Catalog = preload("res://content/catalog.gd")
const IDS := ["wrong_side_of_the_door", "hold_the_line", "great_sheep_escape",
	"bridge_is_out", "dont_wake_the_giant", "unfortunate_ritual", "last_wagon"]
var rules = preload("res://rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_authored_openings()
	_test_gate()
	_test_survival()
	_test_sheep()
	_test_bridge()
	_test_authored_bridge_deadline()
	_test_combat_untimed()
	_test_noise()
	_test_ritual()
	_test_wagon()
	if failures.is_empty():
		print("PASS: special objectives")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": 10, "max_hp": 10, "statuses": {}}


func _fixture(objective: Dictionary, units: Array, behavior_fixture := "") -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	# No autonomous actions obscure the controlled end-of-round boards.
	for profile in defs.classes.values():
		profile.erase("behavior")
		profile.habits = {}
	if behavior_fixture == "sheep":
		defs.behaviors["hold"] = {"handler": "hold", "params": {}}
		defs.classes.civilian.behavior = "hold"
	elif behavior_fixture == "wagon_raider":
		defs.classes.enemy.behavior = "threat"
		defs.behaviors.threat.params.ability = "enemy_attack"
		defs.behaviors.threat.params.fallback_teams = ["civilian"]
		defs.abilities.enemy_attack.targeting.teams = ["civilian"]
	defs.tiles["void"] = {"label": "Void", "art_key": "void", "passable": false}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Party lost"}]
	var state: Dictionary = rules.new_game(defs, "fixture")
	_check(not state.is_empty(), "Controlled catalog builds before injecting runtime objective")
	if state.is_empty():
		return {}
	state.units = units
	state.party = ["knight", "healer", "wizard"]
	state.objective = objective.duplicate(true)
	state.terrain = []
	state.obstacles = []
	state.orders = {}
	state.overrides = {}
	state.round = 1
	return state


func _heroes() -> Array:
	return [_unit("knight", "knight", Vector2i(0, 0)),
		_unit("healer", "healer", Vector2i(0, 1)),
		_unit("wizard", "wizard", Vector2i(0, 2))]


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.id == id:
			return unit
	_check(false, "Missing fixture entity: " + id)
	return {}


func _round(state: Dictionary, label: String) -> Dictionary:
	if state.is_empty():
		_check(false, label + ": cannot forecast an empty fixture")
		return {}
	var before := state.duplicate(true)
	var forecast: Dictionary = rules.preview_round(state)
	_check(state == before and forecast == rules.preview_round(state), label + ": repeatable, pure forecast")
	_check(forecast.get("valid", false), label + ": valid forecast")
	if not forecast.get("valid", false):
		return {}
	var result: Dictionary = rules.commit_round(state, forecast)
	var comparable := result.duplicate(true)
	comparable.erase("_terminal_commit")
	_check(comparable == forecast.get("result"), label + ": commit agrees with forecast")
	return result


func _objective(handler: String, fields: Dictionary) -> Dictionary:
	var result := {"handler": handler}
	result.merge(fields)
	return result


func _test_authored_openings() -> void:
	var defs: Dictionary = Catalog.read_default()
	for id in IDS:
		for party in [["knight", "healer", "wizard"], ["necromancer", "rogue", "bard"]]:
			var state: Dictionary = rules.open_mission(defs, id, party)
			_check(not state.is_empty(), "%s opens with %s" % [id, party])
			if state.is_empty():
				continue
			_check(state.get("outcome") == "ongoing" and state.get("party") == party,
				id + ": preserves selected company and starts ongoing")
			_round(state, id + " opening")


func _test_gate() -> void:
	var obj := _objective("pressure_gate", {"plate": Vector2i(2, 1),
		"gate": Vector2i(3, 1), "exit": Vector2i(4, 1)})
	var units := _heroes()
	units.append(_unit("enemy", "harpooner", Vector2i(2, 1)))
	var state := _fixture(obj, units)
	if state.is_empty():
		return
	_entity(state, "knight").position = Vector2i(3, 2)
	var open: Dictionary = rules.preview(state, "knight", "move", "3,1")
	_check(open.get("valid", false), "Living enemy on plate opens gate to an ordinary move")
	_entity(state, "enemy").hp = 0
	_check(not rules.preview(state, "knight", "move", "3,1").get("valid", false),
		"Dead character does not hold gate open")
	_entity(state, "enemy").position = Vector2i(7, 7)
	_entity(state, "healer").position = Vector2i(2, 1)
	_check(rules.preview(state, "knight", "move", "3,1").get("valid", false),
		"Hero also opens gate")
	_entity(state, "healer").position = Vector2i(1, 1)
	_check(not rules.preview(state, "knight", "move", "3,1").get("valid", false),
		"Gate closes immediately when plate is vacated")
	# An ordinary push can also supply the occupant, without a plate-specific action.
	var push_obj := _objective("pressure_gate", {"plate": Vector2i(3, 1),
		"gate": Vector2i(5, 1), "exit": Vector2i(6, 1)})
	var push_units := _heroes()
	push_units.append(_unit("enemy", "harpooner", Vector2i(2, 1)))
	var push_state := _fixture(push_obj, push_units)
	if push_state.is_empty():
		return
	_entity(push_state, "knight").position = Vector2i(1, 1)
	var push: Dictionary = rules.preview(push_state, "knight", "knight_push", "enemy")
	_check(push.get("valid", false), "Ordinary knight push can target a plate occupant")
	if push.get("valid", false):
		var pushed: Dictionary = rules.apply_plan(push_state, push)
		_check(_entity(pushed, "enemy").position == Vector2i(3, 1),
			"Push puts the enemy on the pressure plate")
		_entity(pushed, "wizard").position = Vector2i(5, 2)
		_check(rules.preview(pushed, "wizard", "move", "5,1").get("valid", false),
			"Pushed enemy opens gate for another hero")
	var pending := _round(state, "Gate before exit")
	if not pending.is_empty():
		_check(pending.outcome == "ongoing", "Opening the gate is not itself victory")
	_entity(state, "knight").position = Vector2i(4, 1)
	var win := _round(state, "Hero at exit")
	if not win.is_empty():
		_check(win.outcome == "victory", "Any living hero at exit wins")
	_entity(state, "knight").hp = 0
	var dead := _round(state, "Dead hero at exit")
	if not dead.is_empty():
		_check(dead.outcome != "victory", "Dead hero at exit does not win")


func _test_survival() -> void:
	var obj := _objective("survive", {"turns": 6})
	var state := _fixture(obj, _heroes())
	if state.is_empty():
		return
	# Enemy remains alive: survival is not an elimination objective.
	state.units.append(_unit("enemy", "harpooner", Vector2i(8, 8)))
	for turn in range(1, 7):
		state = _round(state, "Survival turn %d" % turn)
		if state.is_empty():
			return
		_check(state.outcome == ("victory" if turn == 6 else "ongoing"),
			"Survival resolves on turn six, not earlier")
	_check(_entity(state, "enemy").hp > 0, "Survival does not require killing the enemy")
	var wiped := _fixture(obj, _heroes())
	if wiped.is_empty():
		return
	wiped.round = 6
	for id in wiped.party:
		_entity(wiped, id).hp = 0
	var result := _round(wiped, "Wipe on survival boundary")
	if not result.is_empty():
		_check(result.outcome == "defeat", "Party wipe takes priority over survival victory")


func _test_sheep() -> void:
	var pen := [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	var obj := _objective("herd_sheep", {"subjects": ["s1", "s2", "s3"], "pen": pen})
	var units := _heroes()
	for index in range(3):
		units.append(_unit("s%d" % (index + 1), "ferryman", pen[index]))
	var state := _fixture(obj, units)
	if state.is_empty():
		return
	_entity(state, "s3").position = Vector2i(6, 5)
	var partial := _round(state, "Two sheep penned")
	if not partial.is_empty():
		_check(partial.outcome == "ongoing", "Two of three sheep are insufficient")
	_entity(state, "s3").position = pen[2]
	var all := _round(state, "Three sheep penned")
	if not all.is_empty():
		_check(all.outcome == "victory", "Three living sheep in pen win")
	_entity(state, "s3").hp = 0
	var dead := _round(state, "Dead sheep in pen")
	if not dead.is_empty():
		_check(dead.outcome != "victory", "Dead sheep cannot count as penned")
	_test_sheep_flee(obj)


func _test_sheep_flee(obj: Dictionary) -> void:
	var units := _heroes()
	units.append(_unit("s1", "ferryman", Vector2i(4, 6)))
	units.append(_unit("s2", "ferryman", Vector2i(9, 8)))
	units.append(_unit("s3", "ferryman", Vector2i(9, 9)))
	var state := _fixture(obj, units, "sheep")
	if state.is_empty():
		return
	# Sheep hold on their own turns; the objective controls end-of-round movement.
	_entity(state, "knight").position = Vector2i(3, 6)
	var first := _round(state, "Sheep flee adjacent hero")
	if first.is_empty():
		return
	var sheep: Vector2i = _entity(first, "s1").position
	_check(absi(sheep.x - 3) + absi(sheep.y - 6) > 1,
		"Sheep moves away from an adjacent hero")
	_entity(first, "knight").position = Vector2i(0, 0)
	var settled := _round(first, "Sheep with no nearby character")
	if not settled.is_empty():
		_check(_entity(settled, "s1").position == sheep,
			"Sheep settles rather than wandering when no character is nearby")
	var penned := state.duplicate(true)
	_entity(penned, "s1").position = Vector2i(4, 4)
	_entity(penned, "knight").position = Vector2i(3, 4)
	var safe := _round(penned, "Penned sheep near hero")
	if not safe.is_empty():
		_check(_entity(safe, "s1").position == Vector2i(4, 4),
			"Penned sheep stays settled even when a hero is adjacent")


func _test_bridge() -> void:
	var obj := _objective("collapsing_bridge", {"exit": Vector2i(9, 2),
		"collapses": [{"round": 2, "cells": [Vector2i(4, 2)]}]})
	var state := _fixture(obj, _heroes())
	if state.is_empty():
		return
	state.round = 1
	var first := _round(state, "Bridge before collapse")
	if first.is_empty():
		return
	_check(rules.tile_definition(first, Vector2i(4, 2)).get("passable", false),
		"Scheduled bridge section remains passable before its round")
	var second := _round(first, "Bridge scheduled collapse")
	if second.is_empty():
		return
	_check(not rules.tile_definition(second, Vector2i(4, 2)).get("passable", true),
		"Scheduled section becomes impassable on its round")
	_check(rules.tile_definition(second, Vector2i(5, 2)).get("passable", false),
		"Unscheduled neighboring section remains passable")
	var occupied := first.duplicate(true)
	_entity(occupied, "knight").position = Vector2i(4, 2)
	var fallen := _round(occupied, "Collapse under hero")
	if not fallen.is_empty():
		_check(_entity(fallen, "knight").get("hp", 0) <= 0,
			"A hero on a collapsing section falls and is defeated")
	_entity(second, "knight").position = Vector2i(9, 2)
	var won := _round(second, "Bridge exit")
	if not won.is_empty():
		_check(won.outcome == "victory", "Living hero reaching far side wins")


func _test_authored_bridge_deadline() -> void:
	var defs: Dictionary = Catalog.read_default()
	var state: Dictionary = rules.open_mission(defs, "bridge_is_out", ["necromancer", "rogue", "bard"])
	_check(not state.is_empty(), "Authored bridge opens for the waiting company")
	if state.is_empty():
		return
	var deadline: int = rules.deadline(state)
	_check(deadline >= 6 and deadline <= 30, "Bridge has a bounded authored crossing deadline after both collapses")
	if deadline > 0:
		_check(str(rules.mission_definition(state).objective.text).to_lower().contains("round %d" % deadline),
			"Bridge objective explains the crossing deadline")
	# Still exercise the actual softlock when no deadline has been authored yet.
	var final_round := deadline if deadline >= 6 and deadline <= 30 else 6
	for turn in range(1, final_round + 1):
		if turn == final_round:
			var crossing := state.duplicate(true)
			_entity(crossing, "necromancer").position = crossing.objective.exit
			var won := _round(crossing, "Bridge exit on deadline")
			if not won.is_empty():
				_check(won.outcome == "victory", "A living hero at the exit on the deadline wins")
		state = _round(state, "Authored bridge waiting round %d" % turn)
		if state.is_empty():
			return
		for id in state.party:
			var hero := _entity(state, id)
			_check(hero.get("hp", 0) > 0 and hero.get("position", Vector2i(99, 99)).x < 2,
				"Waiting company remains alive on the west side in round %d" % turn)
		for span in state.objective.collapses:
			for cell in span.cells:
				_check(rules.tile_definition(state, cell).get("passable", false) == (turn < span.round),
					"Authored span changes passability on its scheduled round")
		_check(state.outcome == ("defeat" if turn == final_round else "ongoing"),
			"Unaided bridge waiting resolves as defeat at the crossing deadline, not earlier")
		if state.outcome != "ongoing":
			break


func _test_combat_untimed() -> void:
	var units := _heroes()
	units.append(_unit("enemy", "harpooner", Vector2i(8, 8)))
	var state := _fixture(_objective("defeat_all", {"team": "enemies"}), units)
	if state.is_empty():
		return
	state.round = 100
	var result := _round(state, "Conventional combat at a late round")
	if not result.is_empty():
		_check(result.outcome == "ongoing", "Conventional combat remains untimed")


func _test_noise() -> void:
	var obj := _objective("treasure_noise", {"treasure": Vector2i(4, 4),
		"noise": 0, "threshold": 2})
	var state := _fixture(obj, _heroes())
	if state.is_empty():
		return
	# A regular move produces one noise; the counter persists between rounds.
	for turn in range(2):
		var target := "1,0" if turn == 0 else "0,0"
		state = rules.choose_manual(state, "knight", "move", target)
		state = _round(state, "Noise move %d" % turn)
		if state.is_empty():
			return
		_check(state.objective.get("noise", -1) == turn + 1 and state.outcome == "ongoing",
			"Move noise accumulates; equality with threshold is safe")
	state = rules.choose_manual(state, "knight", "move", "1,0")
	var loud := _round(state, "Noise exceeds threshold")
	if not loud.is_empty():
		_check(loud.outcome == "defeat", "Exceeding the noise threshold wakes giant and fails")
	var quiet := _fixture(obj, _heroes())
	if quiet.is_empty():
		return
	_entity(quiet, "knight").position = Vector2i(4, 4)
	var won := _round(quiet, "Quiet treasure")
	if not won.is_empty():
		_check(won.outcome == "victory", "Reaching treasure within budget wins")
	quiet.objective.noise = 3
	var too_loud := _round(quiet, "Treasure after waking")
	if not too_loud.is_empty():
		_check(too_loud.outcome == "defeat", "Waking takes priority over simultaneous treasure")


func _test_ritual() -> void:
	var circles := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]
	var obj := _objective("ritual", {"circles": circles, "required_turns": 2, "held_turns": 0})
	var units := _heroes()
	units.append(_unit("enemy", "harpooner", circles[2]))
	var state := _fixture(obj, units)
	if state.is_empty():
		return
	_entity(state, "knight").position = circles[0]
	_entity(state, "healer").position = circles[1]
	var first := _round(state, "First complete ritual turn")
	if first.is_empty():
		return
	_check(first.outcome == "ongoing" and first.objective.get("held_turns") == 1,
		"Enemy occupies a circle and one complete turn is insufficient")
	var broken := first.duplicate(true)
	_entity(broken, "enemy").position = Vector2i(7, 7)
	broken = _round(broken, "Broken ritual")
	if not broken.is_empty():
		_check(broken.outcome == "ongoing" and broken.objective.get("held_turns") == 0,
			"Breaking occupancy resets consecutive-turn progress")
	var second := _round(first, "Second complete ritual turn")
	if not second.is_empty():
		_check(second.outcome == "victory", "Two consecutive fully occupied turns win")
	var all_heroes := _fixture(obj, _heroes())
	if all_heroes.is_empty():
		return
	for index in range(3):
		_entity(all_heroes, all_heroes.party[index]).position = circles[index]
	all_heroes = _round(all_heroes, "Hero-only ritual first turn")
	if not all_heroes.is_empty():
		all_heroes = _round(all_heroes, "Hero-only ritual second turn")
		if not all_heroes.is_empty():
			_check(all_heroes.outcome == "victory", "Three heroes can occupy the circles without an enemy")
	_entity(first, "enemy").hp = 0
	var corpse := _round(first, "Dead ritual occupant")
	if not corpse.is_empty():
		_check(corpse.outcome != "victory", "Dead enemy does not occupy a circle")


func _test_wagon() -> void:
	var obj := _objective("wagon", {"subject": "wagon", "destination": Vector2i(5, 4)})
	var units := _heroes()
	units.append(_unit("wagon", "ferryman", Vector2i(3, 4)))
	units.append(_unit("enemy", "harpooner", Vector2i(3, 5)))
	var state := _fixture(obj, units)
	if state.is_empty():
		return
	var stalled := _round(state, "Enemy adjacent to wagon")
	if stalled.is_empty():
		return
	_check(_entity(stalled, "wagon").position == Vector2i(3, 4),
		"Living adjacent enemy stalls wagon")
	var pushed_state := state.duplicate(true)
	_entity(pushed_state, "knight").position = Vector2i(2, 5)
	var push: Dictionary = rules.preview(pushed_state, "knight", "knight_push", "enemy")
	_check(push.get("valid", false), "Knight can push an adjacent wagon threat")
	if push.get("valid", false):
		pushed_state = rules.apply_plan(pushed_state, push)
		var cleared := _round(pushed_state, "Push clears wagon perimeter")
		if not cleared.is_empty():
			_check(_entity(cleared, "enemy").hp > 0 and _entity(cleared, "wagon").position == Vector2i(4, 4),
				"Displacing a living enemy lets the wagon advance without elimination")
	_entity(state, "enemy").hp = 0
	var moving := _round(state, "Defeated enemy adjacent to wagon")
	if moving.is_empty():
		return
	_check(_entity(moving, "wagon").position == Vector2i(4, 4),
		"Defeated adjacent enemy does not stall wagon; wagon advances one tile")
	_check(moving.outcome == "ongoing", "Wagon has not yet reached destination")
	var arrival := _round(moving, "Wagon arrival")
	if not arrival.is_empty():
		_check(arrival.outcome == "victory", "Wagon reaching village wins")
	var destroyed := state.duplicate(true)
	_entity(destroyed, "wagon").hp = 0
	var lost := _round(destroyed, "Destroyed wagon")
	if not lost.is_empty():
		_check(lost.outcome == "defeat", "Destroying wagon fails mission")
	_test_wagon_targeting(obj)


func _test_wagon_targeting(obj: Dictionary) -> void:
	var units := _heroes()
	units.append(_unit("wagon", "ferryman", Vector2i(3, 4)))
	units.append(_unit("enemy", "harpooner", Vector2i(3, 5)))
	var state := _fixture(obj, units, "wagon_raider")
	if state.is_empty():
		return
	_entity(state, "knight").position = Vector2i(4, 5)
	# Match the authored wagon raider's civilian-only fallback and strike targeting.
	var forecast: Dictionary = rules.preview_round(state)
	_check(forecast.get("valid", false), "Wagon targeting forecast is valid")
	if not forecast.get("valid", false):
		return
	var hit_wagon := false
	for event in forecast.get("events", []):
		if event.get("type") == "damage" and event.get("source_id") == "enemy" \
				and event.get("target_id") == "wagon":
			hit_wagon = true
	_check(hit_wagon, "Civilian-targeting raider attacks wagon with a hero also adjacent")
	_round(state, "Wagon priority")
