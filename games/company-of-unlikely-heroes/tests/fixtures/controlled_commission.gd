extends RefCounted
## Test-owned defeat-all encounters and reports for commission transition tests.

static func build(source: Dictionary) -> Dictionary:
	var defs := source.duplicate(true)
	defs.commission_settings.tiered = false
	defs.tiles["test_commission_floor"] = {"label": "Floor", "art_key": "open", "passable": true}
	defs.boards["test_commission_board"] = {"width": 8, "height": 8,
		"default_tile": "test_commission_floor", "tiles": [], "locations": {}}
	defs.behaviors["test_commission_hold"] = {"handler": "hold", "params": {}}
	defs.classes["test_commission_enemy"] = {"team": "enemies", "art_key": "enemy", "max_hp": 3,
		"capabilities": ["blocks_movement", "mobile", "pushable", "pullable", "damageable",
			"protectable", "tauntable", "recoverable"],
		"abilities": ["move"], "habits": {}, "behavior": "test_commission_hold"}
	defs.characters["test_commission_enemy"] = {"class": "test_commission_enemy", "label": "Fixture foe"}
	defs.encounters["test_commission_battle"] = {"board": "test_commission_board",
		"party_slots": [[1, 1], [1, 2], [1, 3]],
		"placements": [{"id": "fixture_foe", "character": "test_commission_enemy", "at": [6, 6]}]}
	var mission := {"title": "Fixture battle", "encounter": "test_commission_battle",
		"objective": {"handler": "defeat_all", "text": "Defeat the foe.",
			"victory_text": "Won.", "defeat_text": "Lost.", "victory_event": "Won."},
		"failures": [{"handler": "party_wiped", "event": "Lost."}], "tier": 1}
	defs.mission_reports = {}
	defs.mission_kinds = {}
	for kind_index in range(4):
		var kind := "test_commission_kind_%d" % kind_index
		defs.mission_kinds[kind] = {"label": kind, "descriptors": ["Fixture hint %d" % kind_index]}
		for index in range(3):
			var id := "test_commission_road_%d_%d" % [kind_index, index]
			defs.missions[id] = mission.duplicate(true)
			defs.mission_reports[id] = {"kind": kind, "descriptors": ["Fixture road " + id]}
	for index in range(8):
		var id := "test_commission_destination_%d" % index
		defs.missions[id] = mission.duplicate(true)
		defs.mission_reports[id] = {"kind": "test_commission_kind_%d" % (index % 4),
			"descriptors": ["Fixture destination " + id], "destination_descriptors": ["Destination " + id]}
	return defs
