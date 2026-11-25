extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/expedition/special_objectives_test.gd
# Controlled boards test rules, not the coordinates or balance of authored encounters.
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Catalog = preload("res://content/catalog.gd")
const IDS := ["wrong_side_of_the_door", "hold_the_line", "great_sheep_escape",
	"bridge_is_out", "dont_wake_the_giant", "unfortunate_ritual", "last_wagon"]
var rules = preload("res://rules/rules.gd").new()
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
	_test_objective_knockdown()
	_test_mixed_objective_skips()
	_test_guard_objective_knockdown()
	_test_ordinary_selected_hold_recovery()
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


func _fixture(objective: Dictionary, units: Array, behavior_fixture := "", knockdown_fixture := false) -> Dictionary:
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
	elif behavior_fixture in ["mixed_skips", "mixed_hold", "objective_guard"]:
		if behavior_fixture != "mixed_hold":
			defs.classes.civilian.abilities.append("knight_aura")
			defs.behaviors["fixture_guard"] = {"handler": "use_ability", "params": {"ability": "knight_aura"}}
			defs.classes.civilian.behavior = "fixture_guard"
			# Keep the Guard effect observable without reflecting the test hit.
			defs.classes.civilian.capabilities.erase("protectable")
	elif behavior_fixture == "ordinary_hold":
		defs.orders["order_hold"] = {"label": "Hold"}
		defs.behaviors["hold"] = {"handler": "hold", "params": {}}
		defs.classes.knight.habits = {"order_hold": "hold"}
	if behavior_fixture in ["mixed_skips", "mixed_hold"]:
		defs.characters.bard = {"class": "wizard", "label": "Bard"}
		defs.upgrades = {"fixture_laughing_fit": {
			"hero_id": "bard", "effect": "laughing_fit", "amount": 2, "rarity": "common",
			"cap": 1, "label": "Fit", "description": "Fixture fit"}}
		defs.statuses.laughter = {"label": "Laughter", "handler": "skip_action",
			"expiry": "consume_action", "params": {"skip_event": "laugh_skip",
				"immunity_rounds": 1, "immune_label": "Immune"}}
		defs.abilities["fixture_laugh"] = defs.abilities.knight_aura.duplicate(true)
		defs.abilities.fixture_laugh.params.status = "laughter"
		defs.classes.wizard.abilities.append("fixture_laugh")
		defs.events.laugh_skip = {"text": "laugh_skip"}
		defs.abilities.healer_bonk.targeting.teams = ["civilian"]
		defs.abilities.healer_bonk.targeting.range = 2
	if knockdown_fixture:
		defs.abilities.wizard_blast.params.damage = 0
		defs.abilities.wizard_blast.targeting = {
			"kind": "entity", "range": 1, "capabilities": ["damageable"]}
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


func _test_objective_knockdown() -> void:
	for kind in ["wagon", "sheep"]:
		for before_slot in [true, false]:
			_objective_knockdown_case(kind, before_slot, false)
			_objective_knockdown_case(kind, before_slot, true)


func _objective_knockdown_case(kind: String, before_slot: bool, jelly: bool) -> void:
	var start := Vector2i(4, 4)
	var obj := _objective("wagon", {"subject": "subject", "destination": Vector2i(9, 4)}) \
		if kind == "wagon" else _objective("herd_sheep", {
			"subjects": ["subject"], "pen": [Vector2i(9, 9)]})
	var wizard := _unit("wizard", "wizard", Vector2i(3, 4))
	var subject := _unit("subject", "ferryman", start)
	var units := [_unit("knight", "knight", Vector2i(0, 0)),
		_unit("healer", "healer", Vector2i(0, 1))]
	units.append_array([wizard, subject] if before_slot else [subject, wizard])
	var state := _fixture(obj, units, "sheep" if kind == "sheep" else "", true)
	if state.is_empty():
		return
	# A targeted, harmless authored knockdown makes initiative order the only variable.
	if jelly:
		_entity(state, "subject")["alchemy_statuses"] = {"jelly_knees": {"source_id": "wizard"}}
	var label := "%s knockdown %s nominal slot%s" % [
		kind, "before" if before_slot else "after", " with Jelly Knees" if jelly else ""]
	var action: Dictionary = rules.preview(state, "wizard", "wizard_blast", "subject")
	_check(action.get("valid", false) and _entity(action.get("result", state), "subject").statuses.has("knockdown"),
		label + ": fixture applies authored knockdown")
	state = rules.choose_manual(state, "wizard", "wizard_blast", "subject")
	var skipped := _round(state, label)
	if skipped.is_empty():
		return
	var recovered := _entity(skipped, "subject")
	_check(recovered.position == start, label + ": skips objective movement")
	_check(not recovered.statuses.has("knockdown")
		and not recovered.get("alchemy_statuses", {}).has("jelly_knees"),
		label + ": consumes concurrent knockdowns on that activation")
	skipped.overrides = {}
	var resumed := _round(skipped, label + " following round")
	if not resumed.is_empty():
		_check(_entity(resumed, "subject").position != start,
			label + ": resumes movement the following round")


func _test_mixed_objective_skips() -> void:
	for mode in ["guard", "hold", "guard_hit"]:
		var hit_before_objective: bool = mode == "guard_hit"
		var guard: bool = mode != "hold"
		var subject := _unit("subject", "ferryman", Vector2i(4, 4))
		subject.hp = 20
		subject.max_hp = 20
		subject.statuses = {"laughter": {"source_id": "bard"}, "knockdown": {"source_id": "wizard"}}
		var bard := _unit("bard", "bard", Vector2i(0, 3))
		bard["upgrades"] = {"fixture_laughing_fit": 1}
		var units := [bard, subject, _unit("healer", "healer", Vector2i(3, 4)),
			_unit("knight", "knight", Vector2i(0, 0)), _unit("wizard", "wizard", Vector2i(0, 2))]
		var state := _fixture(_objective("wagon", {
			"subject": "subject", "destination": Vector2i(9, 4)}), units,
			"mixed_skips" if guard else "mixed_hold")
		if state.is_empty():
			return
		if hit_before_objective:
			state = rules.choose_manual(state, "healer", "healer_bonk", "subject")
		var label: String = "Mixed skips " + mode
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview_round(state)
		_check(plan.get("valid", false) and state == before and plan == rules.preview_round(state),
			label + ": forecast is valid, pure and repeatable")
		if not plan.get("valid", false):
			continue
		var result: Dictionary = rules.commit_round(state, plan)
		_check(result == plan.get("result"), label + ": commit matches forecast")
		var recoveries := []
		var fit_grants := []
		var fit_consumptions := []
		var healer_event := -1
		for index in range(plan.events.size()):
			var event: Dictionary = plan.events[index]
			if event.get("type") == "recover" and event.get("unit_id") == "subject":
				recoveries.append({"index": index, "ids": event.get("status_ids", [])})
			if event.get("type") == "status" and event.get("status_id") == "laughing_fit" \
					and event.get("unit_id") == "subject":
				if str(event.get("text", "")).contains("drops their guard"):
					fit_grants.append(index)
				elif str(event.get("text", "")).contains("increases the hit"):
					fit_consumptions.append(index)
				else:
					_check(false, label + ": unexpected Laughing Fit status event")
			if (event.get("unit_id") == "healer" and event.get("type") == "wait") \
					or (event.get("source_id") == "healer" and event.get("type") == "damage"):
				healer_event = index
		_check(recoveries.size() == 1 and healer_event >= 0, label + ": one actual activation is skipped")
		if recoveries.size() == 1 and healer_event >= 0:
			_check("laughter" in recoveries[0].ids and "knockdown" in recoveries[0].ids
				and ((recoveries[0].index < healer_event) == guard),
				label + ": both effects are credited at the next real activation")
		_check(fit_grants.size() == 1 and recoveries.size() == 1
			and fit_grants[0] == recoveries[0].index + 1,
			label + ": Laughing Fit is granted and reported once at that activation")
		_check(fit_consumptions.size() == (1 if hit_before_objective else 0)
			and (not hit_before_objective or fit_consumptions[0] < healer_event),
			label + ": intervening hit reports one consumption and no duplicate")
		var after := _entity(result, "subject")
		_check(after.position == (Vector2i(5, 4) if guard else Vector2i(4, 4))
			and not after.statuses.has("aura") and not after.statuses.has("knockdown")
			and after.statuses.get("laughter", {}).has("immune_through_round"),
			label + ": only the real activation is skipped and laughter immunity retained")
		_check(after.hp == (16 if hit_before_objective else 20), label + ": intervening hit gets one bonus")
		var hit: Dictionary = rules.preview(result, "healer", "healer_bonk", "subject")
		_check(hit.get("valid", false), label + ": follow-up hit is legal")
		if hit.get("valid", false):
			var hit_fits := _fit_event_count(hit.events, "increases the hit")
			_check(hit_fits == (0 if hit_before_objective else 1),
				label + ": follow-up reports exactly the unspent consumption")
			_check(_fit_event_count(hit.events, "drops their guard") == 0,
				label + ": follow-up does not report another grant")
			var once: Dictionary = rules.apply_plan(result, hit)
			_check(_entity(once, "subject").hp == (14 if hit_before_objective else 16),
				label + ": next hit receives only any unspent bonus")
			var second: Dictionary = rules.preview(once, "healer", "healer_bonk", "subject")
			_check(second.get("valid", false), label + ": second follow-up hit is legal")
			if second.get("valid", false):
				_check(_fit_event_count(second.events, "increases the hit") == 0
					and _fit_event_count(second.events, "drops their guard") == 0,
					label + ": second follow-up reports no repeated consumption")
				_check(_entity(rules.apply_plan(once, second), "subject").hp
					== (12 if hit_before_objective else 14), label + ": no extra damage on the second hit")


func _fit_event_count(events: Array, phrase: String) -> int:
	var count := 0
	for event in events:
		if event.get("type") == "status" and event.get("status_id") == "laughing_fit" \
				and event.get("unit_id") == "subject" and str(event.get("text", "")).contains(phrase):
			count += 1
	return count


func _test_guard_objective_knockdown() -> void:
	for before_slot in [true, false]:
		var wizard := _unit("wizard", "wizard", Vector2i(3, 4))
		var subject := _unit("subject", "ferryman", Vector2i(4, 4))
		var units := [_unit("knight", "knight", Vector2i(0, 0)),
			_unit("healer", "healer", Vector2i(0, 1))]
		units.append_array([wizard, subject] if before_slot else [subject, wizard])
		var state := _fixture(_objective("wagon", {
			"subject": "subject", "destination": Vector2i(9, 4)}), units, "objective_guard", true)
		if state.is_empty():
			continue
		state = rules.choose_manual(state, "wizard", "wizard_blast", "subject")
		var label := "Guard wagon knockdown " + ("before" if before_slot else "after") + " initiative"
		var result := _round(state, label)
		if result.is_empty():
			continue
		var wagon := _entity(result, "subject")
		_check(wagon.position == (Vector2i(5, 4) if before_slot else Vector2i(4, 4))
			and wagon.statuses.has("aura") != before_slot and not wagon.statuses.has("knockdown"),
			label + ": skips exactly the next real activation, not both")


func _test_ordinary_selected_hold_recovery() -> void:
	var state := _fixture(_objective("survive", {"turns": 5}), _heroes(), "ordinary_hold")
	if state.is_empty():
		return
	state = rules.set_order(state, "knight", "order_hold")
	_check(state.orders.get("knight") == "order_hold", "Ordinary hero selects Hold")
	_entity(state, "knight").statuses = {"knockdown": {"source_id": "wizard"}}
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), "Ordinary selected Hold recovery forecasts")
	if not plan.get("valid", false):
		return
	var recoveries: Array = plan.events.filter(func(event: Dictionary) -> bool:
		return event.get("type") == "recover" and event.get("unit_id") == "knight" \
			and "knockdown" in event.get("status_ids", []))
	var result: Dictionary = rules.commit_round(state, plan)
	_check(recoveries.size() == 1 and not _entity(result, "knight").statuses.has("knockdown"),
		"Ordinary hero recovers at initiative even when explicitly ordered to Hold")
