extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/content/commission_catalog_test.gd
const Catalog = preload("res://content/catalog.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var defs := _fixture()
	_valid(defs, "controlled commission catalog")
	_test_optional_configuration()
	_test_configuration(defs)
	_test_reports(defs)
	_test_pool(defs)
	_test_tiered_catalog()
	_test_variants()
	_test_malformed_encounter_does_not_hide_hp_error()
	if "--controlled-only" not in OS.get_cmdline_user_args():
		_test_authored()
	if failures.is_empty():
		print("PASS: commission catalog validation")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _valid(defs: Dictionary, label: String) -> void:
	var errors: PackedStringArray = Catalog.validate(defs)
	if not errors.is_empty():
		failures.append("%s should validate: %s" % [label, "; ".join(errors)])


func _invalid(defs: Dictionary, label: String) -> void:
	var errors: PackedStringArray = Catalog.validate(defs)
	if errors.is_empty():
		failures.append(label + " should be rejected")


func _invalid_at(defs: Dictionary, paths: Array, label: String) -> void:
	var errors: PackedStringArray = Catalog.validate(defs)
	var diagnostic := "\n".join(errors)
	for path in paths:
		if path not in diagnostic:
			failures.append("%s should report %s; got: %s" % [label, path, diagnostic])


func _fixture() -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.encounters.fixture.placements = [
		{"id": "harpooner", "character": "harpooner", "at": [5, 1]},
		{"id": "civilian", "character": "ferryman", "at": [1, 2]}
	]
	defs.encounters.fixture.party_slots = [[1, 1], [0, 2], [4, 2]]
	defs.missions.fixture.failures.append({"handler": "party_wiped", "event": "Party lost"})
	defs.erase("adventures")
	defs.commission_settings = {"recruitment_roster": ["knight", "healer", "wizard"]}
	defs.mission_kinds = {}
	defs.mission_reports = {}
	for kind_index in range(3):
		var kind := "test_kind_%d" % kind_index
		defs.mission_kinds[kind] = {"label": kind, "descriptors": ["Kind report"]}
		for index in range(4):
			var id := "transit_%d_%d" % [kind_index, index]
			defs.missions[id] = defs.missions.fixture.duplicate(true)
			defs.mission_reports[id] = {"kind": kind, "descriptors": ["Transit report"]}
	for index in range(8):
		var id := "destination_%d" % index
		defs.missions[id] = defs.missions.fixture.duplicate(true)
		defs.mission_reports[id] = {
			"kind": "test_kind_%d" % (index % 3), "descriptors": ["Destination report"],
			"destination_descriptors": ["Destination offer"]
		}
	return defs


func _test_optional_configuration() -> void:
	_valid(Fixture.definitions(), "legacy catalog without commission tables")
	var defs := _fixture()
	for table in ["commission_settings", "mission_reports", "mission_kinds"]:
		var partial := defs.duplicate(true)
		partial.erase(table)
		_invalid(partial, "partial commission configuration missing " + table)


func _test_configuration(defs: Dictionary) -> void:
	for value in [[], ["missing_hero"], ["knight", "knight", "wizard"],
			["knight", "healer", "ferryman"], "knight", 42, null]:
		var bad := defs.duplicate(true)
		bad.commission_settings.recruitment_roster = value
		_invalid_at(bad, ["commission_settings.recruitment_roster"], "invalid recruitment roster " + str(value))
	var missing := defs.duplicate(true)
	missing.commission_settings.erase("recruitment_roster")
	_invalid_at(missing, ["commission_settings.recruitment_roster"], "missing recruitment roster")


func _test_reports(defs: Dictionary) -> void:
	var bad_kind := defs.duplicate(true)
	bad_kind.mission_reports.transit_0_0.kind = "unknown_kind"
	_invalid(bad_kind, "report references unknown kind")
	var bad_mission := defs.duplicate(true)
	bad_mission.mission_reports["unknown_mission"] = bad_mission.mission_reports.transit_0_0.duplicate(true)
	_invalid(bad_mission, "report references unknown mission")
	for field in ["descriptors", "destination_descriptors"]:
		for value in [[], [""], [42], "not an array"]:
			var bad := defs.duplicate(true)
			bad.mission_reports.destination_0[field] = value
			_invalid(bad, "invalid report %s: %s" % [field, str(value)])
	var missing := defs.duplicate(true)
	missing.mission_reports.transit_0_0.erase("descriptors")
	_invalid(missing, "report missing descriptors")
	var no_kind_descriptions := defs.duplicate(true)
	no_kind_descriptions.mission_kinds.test_kind_0.descriptors = []
	_invalid(no_kind_descriptions, "kind missing usable descriptors")
	var no_kind_label := defs.duplicate(true)
	no_kind_label.mission_kinds.test_kind_0.erase("label")
	_invalid(no_kind_label, "kind missing label")


func _test_pool(defs: Dictionary) -> void:
	var no_destinations := defs.duplicate(true)
	for id in no_destinations.mission_reports:
		no_destinations.mission_reports[id].erase("destination_descriptors")
	_invalid(no_destinations, "pool without destinations")
	var too_few_destinations := defs.duplicate(true)
	for index in range(2, 8):
		too_few_destinations.mission_reports["destination_%d" % index].erase("destination_descriptors")
	_invalid(too_few_destinations, "pool with fewer than three destinations")
	var one_transit_kind := defs.duplicate(true)
	for kind_index in range(1, 3):
		for index in range(4):
			one_transit_kind.mission_reports.erase("transit_%d_%d" % [kind_index, index])
	_invalid(one_transit_kind, "pool with only one transit kind")
	var tiny := defs.duplicate(true)
	for kind_index in range(3):
		for index in range(4):
			if kind_index >= 2 or index > 0:
				tiny.mission_reports.erase("transit_%d_%d" % [kind_index, index])
	for index in range(3, 8):
		tiny.mission_reports.erase("destination_%d" % index)
	_valid(tiny, "small pool with two transit kinds and three destinations")
	_test_commission_deployment(defs)


func _test_commission_deployment(defs: Dictionary) -> void:
	# Change only one reported mission while all other reports keep their slots.
	var controlled := defs.duplicate(true)
	controlled.encounters["commission_only"] = controlled.encounters.fixture.duplicate(true)
	controlled.missions.transit_0_0.encounter = "commission_only"
	_valid(controlled, "commission-only deployment fixture")
	var unsuitable := controlled.duplicate(true)
	unsuitable.encounters.commission_only.party_slots = [[1, 1], [0, 2]]
	_invalid_at(unsuitable, ["mission_reports.transit_0_0", "encounters.commission_only.party_slots"],
		"reported mission cannot deploy roster party")
	var collision := controlled.duplicate(true)
	collision.encounters.commission_only.placements.append(
		{"id": "knight", "character": "knight", "at": [8, 8]})
	_invalid_at(collision, ["mission_reports.transit_0_0", "encounters.commission_only.placements"],
		"reported mission placement collides with roster")
	var no_wipe := controlled.duplicate(true)
	no_wipe.missions.transit_0_0.failures = [
		{"handler": "subject_dead", "event": "Subject lost"},
		{"handler": "deadline", "event": "Deadline"}
	]
	_invalid_at(no_wipe, ["mission_reports.transit_0_0", "missions.transit_0_0.failures"],
		"reported mission lacks party-wiped failure")


func _tiered_fixture() -> Dictionary:
	var defs := _fixture()
	defs.commission_settings.tiered = true
	# Ten independent roads, two kinds in each tier, plus two extra roads.
	for kind_index in range(3):
		for index in range(4):
			defs.missions["transit_%d_%d" % [kind_index, index]].tier = index + 1
	for kind_index in range(2):
		var id := "tier_five_%d" % kind_index
		defs.missions[id] = defs.missions.fixture.duplicate(true)
		defs.missions[id].tier = 5
		defs.mission_reports[id] = {
			"kind": "test_kind_%d" % kind_index, "descriptors": ["Road"]
		}
	return defs


func _test_tiered_catalog() -> void:
	var defs := _tiered_fixture()
	_valid(defs, "tiered catalog with two road kinds per tier and no report road_tier")
	for value in ["true", 1, null]:
		var bad := defs.duplicate(true)
		bad.commission_settings.tiered = value
		_invalid(bad, "malformed tiered opt-in " + str(value))
	for value in [0, 6, -1, 1.5, "1", true, null]:
		var bad := defs.duplicate(true)
		bad.missions.transit_0_0.tier = value
		_invalid_at(bad, ["missions.transit_0_0.tier"], "invalid road mission tier " + str(value))
	var missing := defs.duplicate(true)
	missing.missions.transit_0_0.erase("tier")
	_invalid_at(missing, ["missions.transit_0_0.tier"], "tiered road missing mission tier")
	for tier in range(1, 6):
		var one_kind := defs.duplicate(true)
		for id in one_kind.mission_reports:
			var report: Dictionary = one_kind.mission_reports[id]
			if not report.has("destination_descriptors") and one_kind.missions[id].get("tier") == tier and report.kind != "test_kind_0":
				report.kind = "test_kind_0"
		_invalid_at(one_kind, ["road tier %d requires at least two different kinds" % tier],
			"tier %d with only one road kind" % tier)
	var legacy := _fixture()
	legacy.commission_settings.tiered = false
	_valid(legacy, "legacy commission catalog explicitly opts out")
	_valid(_fixture(), "legacy commission catalog without opt-in")


func _variant_fixture() -> Dictionary:
	var defs := _fixture()
	defs.missions["variant"] = defs.missions.transit_0_0.duplicate(true)
	defs.missions["variant"].base_mission_id = "transit_0_0"
	defs.missions["variant"].enemy_max_hp = {"harpooner": 6}
	defs.mission_reports["variant"] = defs.mission_reports.transit_0_0.duplicate(true)
	return defs


func _unit(world: Dictionary, id: String) -> Dictionary:
	for unit in world.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _test_variants() -> void:
	var defs := _variant_fixture()
	_valid(defs, "variant references a canonical mission and overrides enemy HP")
	var party := ["knight", "healer", "wizard"]
	var variant := _unit(Catalog.build(defs, "variant", party), "harpooner")
	var canonical := _unit(Catalog.build(defs, "transit_0_0", party), "harpooner")
	if variant.get("max_hp") != 6 or variant.get("hp") != 6:
		failures.append("variant enemy must start at its overridden maximum HP 6")
	if canonical.get("max_hp") != 10 or canonical.get("hp") != 10:
		failures.append("canonical enemy must retain its original maximum and starting HP 10")
	var wounded := defs.duplicate(true)
	wounded.encounters.fixture.placements[0].hp = 4
	_valid(wounded, "variant with an explicitly wounded enemy")
	var wounded_unit := _unit(Catalog.build(wounded, "variant", party), "harpooner")
	if wounded_unit.get("max_hp") != 6 or wounded_unit.get("hp") != 4:
		failures.append("variant must preserve explicit starting HP 4 under its maximum 6")
	var raised_cap := defs.duplicate(true)
	raised_cap.encounters["variant_encounter"] = raised_cap.encounters.fixture.duplicate(true)
	raised_cap.encounters.variant_encounter.placements[0].hp = 12
	raised_cap.missions.variant.encounter = "variant_encounter"
	raised_cap.missions.variant.enemy_max_hp.harpooner = 14
	_valid(raised_cap, "variant starting above inherited HP but below its raised cap")
	var raised_unit := _unit(Catalog.build(raised_cap, "variant", party), "harpooner")
	if raised_unit.get("max_hp") != 14 or raised_unit.get("hp") != 12:
		failures.append("variant must start at HP 12 under its raised maximum 14")
	var no_override := raised_cap.duplicate(true)
	no_override.missions.variant.erase("enemy_max_hp")
	_invalid(no_override, "starting HP above inherited maximum without override")
	for reference in ["missing", "variant"]:
		var bad := defs.duplicate(true)
		bad.missions.variant.base_mission_id = reference
		_invalid(bad, "invalid variant base " + reference)
	var chain := defs.duplicate(true)
	chain.missions.transit_0_0.base_mission_id = "transit_0_1"
	_invalid(chain, "variant base cannot itself be a variant")
	for overrides in [{"missing": 6}, {"civilian": 6}, {"harpooner": 0},
			{"harpooner": -1}, {"harpooner": 1.5}, {"harpooner": "6"},
			{"harpooner": true}, [], null]:
		var bad := defs.duplicate(true)
		bad.missions.variant.enemy_max_hp = overrides
		_invalid(bad, "invalid enemy max HP override " + str(overrides))
	var above_cap := defs.duplicate(true)
	above_cap.encounters.fixture.placements[0].hp = 7
	_invalid(above_cap, "explicit enemy starting HP exceeds variant cap")


func _test_malformed_encounter_does_not_hide_hp_error() -> void:
	var defs := _fixture()
	defs.missions.fixture.encounter = 42
	defs.encounters.fixture.placements[0].hp = 11
	_invalid_at(defs, ["missions.fixture.encounter", "encounters.fixture.placements[0].hp",
		"missions.transit_0_0"], "malformed encounter reference and sibling starting HP")
	for malformed in ["placement_id", "team"]:
		var bad := _variant_fixture()
		bad.missions.variant.enemy_max_hp = {"harpooner": 6, "missing": 6}
		var source_path := "encounters.fixture.placements[0].id"
		if malformed == "placement_id":
			bad.encounters.fixture.placements[0].id = 42
		else:
			bad.characters.harpooner.team = 42
			source_path = "characters.harpooner.team"
		_invalid_at(bad, [source_path, "missions.variant.enemy_max_hp.harpooner",
			"missions.variant.enemy_max_hp.missing"], "malformed " + malformed + " and later HP map errors")


func _test_authored() -> void:
	var source := Catalog.read_source(Catalog.DEFAULT_PATH)
	if source.has("error"):
		failures.append("built-in commission catalog failed to load: " + str(source.error))
		return
	var defs: Dictionary = source.definitions
	_valid(defs, "built-in commission catalog")
	var reports: Dictionary = defs.get("mission_reports", {})
	for id in ["bridge_patrol", "goblin_mob", "harpoon_squad", "shield_wall",
			"cowardly_captain", "explosive_situation", "unfortunate_healer",
			"duelists", "odd_couple", "mirror_company", "last_one_standing"]:
		if not reports.has(id) or reports[id].has("destination_descriptors"):
			failures.append("built-in road report must remain a road: " + id)
	for id in ["company_rescue", "unwelcome_guest", "wrong_side_of_the_door",
			"hold_the_line", "great_sheep_escape", "bridge_is_out",
			"dont_wake_the_giant", "unfortunate_ritual", "last_wagon"]:
		if not reports.has(id) or not reports[id].has("destination_descriptors"):
			failures.append("built-in destination report must remain a destination: " + id)
