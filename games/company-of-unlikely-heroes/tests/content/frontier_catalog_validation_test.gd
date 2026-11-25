extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/content/frontier_catalog_validation_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Catalog = preload("res://content/catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_objectives()
	_test_survival_reserves()
	_test_traits()
	_test_frontier_behaviors()
	if failures.is_empty():
		print("PASS: frontier catalog validation")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _valid(defs: Dictionary, label: String) -> void:
	var errors: PackedStringArray = Catalog.validate(defs)
	if not errors.is_empty():
		failures.append("%s should be valid: %s" % [label, "; ".join(errors)])


func _invalid(defs: Dictionary, path: String, label: String) -> void:
	var errors: PackedStringArray = Catalog.validate(defs)
	for error in errors:
		if error.contains(path):
			return
	failures.append("%s should report %s; got: %s" % [label, path, "; ".join(errors)])


func _defs(handler: String, fields: Dictionary) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.tiles["void"] = {"label": "Void", "art_key": "void", "passable": false}
	defs.boards.fixture.locations.merge({"plate": [2, 3], "gate": [3, 3], "target": [8, 8]})
	defs.boards.fixture["zones"] = {
		"pen": [[8, 6], [9, 6]], "span": [[4, 4]], "other_span": [[5, 4]],
		"circles": [[6, 5], [7, 5]]
	}
	var objective := {"handler": handler, "text": "Objective", "victory_text": "Victory",
		"defeat_text": "Defeat", "victory_event": "Victory"}
	objective.merge(fields)
	defs.missions.fixture.objective = objective
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Lost"}]
	return defs


func _test_objectives() -> void:
	var samples := [
		{"handler": "pressure_gate", "fields": {"plate": "plate", "gate": "gate", "exit": "target"},
			"squares": ["plate", "gate", "exit"]},
		{"handler": "survive", "fields": {"turns": 3}},
		{"handler": "herd_sheep", "fields": {"subjects": ["civilian"], "pen": "pen"},
			"zones": ["pen"]},
		{"handler": "collapsing_bridge", "fields": {"exit": "target",
			"collapses": [{"round": 2, "cells": "span"}, {"round": 5, "cells": "other_span"}]},
			"squares": ["exit"]},
		{"handler": "treasure_noise", "fields": {"treasure": "target", "threshold": 4},
			"squares": ["treasure"]},
		{"handler": "ritual", "fields": {"circles": "circles", "required_turns": 3},
			"zones": ["circles"]},
		{"handler": "wagon", "fields": {"subject": "civilian", "destination": "target"},
			"squares": ["destination"]}
	]
	for sample in samples:
		var defs := _defs(sample.handler, sample.fields)
		_valid(defs, sample.handler + " edited fixture")
		for field in sample.get("squares", []):
			var bad := defs.duplicate(true)
			bad.missions.fixture.objective[field] = "missing_square"
			_invalid(bad, "missions.fixture.objective." + field, sample.handler + " unknown square")
		for field in sample.get("zones", []):
			var bad := defs.duplicate(true)
			bad.missions.fixture.objective[field] = "missing_zone"
			_invalid(bad, "missions.fixture.objective." + field, sample.handler + " unknown zone")

	var gate := _defs("pressure_gate", {"plate": "plate", "gate": "gate", "exit": "target"})
	gate.boards.fixture.locations["same_plate"] = gate.boards.fixture.locations.plate.duplicate()
	gate.missions.fixture.objective.gate = "same_plate"
	_invalid(gate, "missions.fixture.objective.gate", "gate and plate resolve to the same square")

	var sheep := _defs("herd_sheep", {"subjects": ["civilian"], "pen": "pen"})
	sheep.missions.fixture.objective.subjects = ["missing"]
	_invalid(sheep, "missions.fixture.objective.subjects", "missing sheep placement")
	sheep.encounters.fixture.placements.append({"id": "box", "object": "crate", "at": [7, 7]})
	sheep.missions.fixture.objective.subjects = ["box"]
	_invalid(sheep, "missions.fixture.objective.subjects", "object cannot be a sheep subject")
	sheep.missions.fixture.objective.subjects = ["civilian", "civilian"]
	_invalid(sheep, "missions.fixture.objective.subjects", "duplicate sheep subject")
	var crowded := _defs("herd_sheep", {"subjects": ["civilian", "sheep_two", "sheep_three"], "pen": "pen"})
	crowded.encounters.fixture.placements.append_array([
		{"id": "sheep_two", "character": "ferryman", "at": [7, 7]},
		{"id": "sheep_three", "character": "ferryman", "at": [7, 8]}
	])
	_invalid(crowded, "missions.fixture.objective.pen", "pen has fewer cells than sheep")

	var bridge := _defs("collapsing_bridge", {"exit": "target",
		"collapses": [{"round": 2, "cells": "span"}, {"round": 5, "cells": "other_span"}]})
	var bad_zone := bridge.duplicate(true)
	bad_zone.missions.fixture.objective.collapses[0].cells = "missing_zone"
	_invalid(bad_zone, "missions.fixture.objective.collapses[0].cells", "unknown collapse zone")
	var bad_round := bridge.duplicate(true)
	bad_round.missions.fixture.objective.collapses[0].round = 0
	_invalid(bad_round, "missions.fixture.objective.collapses[0].round", "nonpositive collapse round")
	var duplicate_round := bridge.duplicate(true)
	duplicate_round.missions.fixture.objective.collapses[1].round = 2
	_valid(duplicate_round, "distinct spans may collapse in the same round")
	var overlapping_spans := bridge.duplicate(true)
	overlapping_spans.boards.fixture.zones.other_span.append([4.0, 4.0])
	_invalid(overlapping_spans, "missions.fixture.objective.collapses[1].cells",
		"one physical cell cannot collapse in separate rounds even through distinct zones")


func _test_survival_reserves() -> void:
	var defs := _defs("survive", {"turns": 5, "reserve_round": 2,
		"reserve_placements": ["harpooner", "enemy_two"]})
	defs.encounters.fixture.placements.append({"id": "enemy_two", "character": "harpooner", "at": [7, 7]})
	defs.encounters.fixture.placements.append({"id": "box", "object": "crate", "at": [8, 7]})
	_valid(defs, "survival with distinct enemy reserves")
	var last_round := defs.duplicate(true)
	last_round.missions.fixture.objective.reserve_round = 5
	_valid(last_round, "reserves at the last survival round")
	for field in ["reserve_round", "reserve_placements"]:
		var missing := defs.duplicate(true)
		missing.missions.fixture.objective.erase(field)
		_invalid(missing, "missions.fixture.objective." + field, "reserve fields must be paired")
	for round_value in [1, 0, 6, 2.5, "2"]:
		var bad := defs.duplicate(true)
		bad.missions.fixture.objective.reserve_round = round_value
		_invalid(bad, "missions.fixture.objective.reserve_round", "invalid reserve round %s" % str(round_value))
	for ids in [["missing"], ["harpooner", "harpooner"], ["civilian"], ["box"]]:
		var bad := defs.duplicate(true)
		bad.missions.fixture.objective.reserve_placements = ids
		_invalid(bad, "missions.fixture.objective.reserve_placements", "invalid reserve placements %s" % str(ids))


func _test_traits() -> void:
	var cases := [
		{"kind": "adjacent_guard", "protects": "knight", "reduction": 2},
		{"kind": "adjacent_damage_bonus", "benefits": "healer", "damage": 2},
		{"kind": "death_blast", "damage": 3, "range": 2},
		{"kind": "retaliate", "damage": 2, "range": 2},
		{"kind": "ally_death_bonus", "allies": ["knight", "healer"], "movement": 2}
	]
	for spec in cases:
		var defs := _defs("survive", {"turns": 3})
		defs.characters.harpooner["traits"] = [spec.duplicate(true)]
		_valid(defs, "edited " + spec.kind + " trait")
		var unknown := defs.duplicate(true)
		unknown.characters.harpooner.traits[0].kind = "not_a_trait"
		_invalid(unknown, "characters.harpooner.traits[0].kind", "unknown trait kind")
		for field in ["protects", "benefits"]:
			if spec.has(field):
				var bad := defs.duplicate(true)
				bad.characters.harpooner.traits[0][field] = "missing_character"
				_invalid(bad, "characters.harpooner.traits[0]." + field, "unknown trait character")
		if spec.has("allies"):
			var bad := defs.duplicate(true)
			bad.characters.harpooner.traits[0].allies = ["missing_character"]
			_invalid(bad, "characters.harpooner.traits[0].allies", "unknown trait ally")


func _test_frontier_behaviors() -> void:
	var defs := _defs("survive", {"turns": 3})
	defs.events["swap"] = {"text": "swap"}
	defs.abilities["field_heal"] = {"label": "Heal", "help": "Heal", "handler": "enemy_heal",
		"params": {"amount": 3, "charges": 3}, "targeting": {"kind": "automatic", "teams": ["enemies"]}}
	defs.abilities["ally_swap"] = {"label": "Swap", "help": "Swap", "handler": "swap_ally",
		"params": {"character": "harpooner", "range": 4},
		"targeting": {"kind": "automatic", "teams": ["enemies"]}}
	defs.behaviors["medic"] = {"handler": "finite_healer", "params": {"team": "enemies",
		"move_ability": "move", "heal_ability": "field_heal", "ability": "enemy_attack"}}
	defs.behaviors["swapper"] = {"handler": "swap_ally", "params": {"team": "heroes",
		"ally": "harpooner", "move_ability": "move", "swap_ability": "ally_swap", "ability": "enemy_attack"}}
	defs.behaviors["retreater"] = {"handler": "retreat_attack", "params": {"team": "heroes",
		"move_ability": "move", "ability": "enemy_attack"}}
	_valid(defs, "edited frontier ability and behavior fixtures")
	for test in [
		{"behavior": "medic", "field": "heal_ability", "value": "enemy_attack"},
		{"behavior": "swapper", "field": "swap_ability", "value": "enemy_attack"},
		{"behavior": "retreater", "field": "ability", "value": "move"},
		{"behavior": "medic", "field": "move_ability", "value": "enemy_attack"},
		{"behavior": "swapper", "field": "ally", "value": "missing_character"}
	]:
		var bad := defs.duplicate(true)
		bad.behaviors[test.behavior].params[test.field] = test.value
		_invalid(bad, "behaviors.%s.params.%s" % [test.behavior, test.field],
			"invalid frontier behavior " + test.field)
	var bad_swap := defs.duplicate(true)
	bad_swap.abilities.ally_swap.params.character = "missing_character"
	_invalid(bad_swap, "abilities.ally_swap.params.character", "unknown swap target")
	var malformed_heal := defs.duplicate(true)
	malformed_heal.abilities.field_heal.targeting.kind = []
	_invalid(malformed_heal, "abilities.field_heal.targeting.kind", "malformed heal targeting")
	for charges in [0, -1, 1.5, "3", null]:
		var bad_charges := defs.duplicate(true)
		bad_charges.abilities.field_heal.params.charges = charges
		_invalid(bad_charges, "abilities.field_heal.params.charges", "invalid heal charges %s" % str(charges))
	var missing_charges := defs.duplicate(true)
	missing_charges.abilities.field_heal.params.erase("charges")
	_invalid(missing_charges, "abilities.field_heal.params.charges", "missing heal charges")
