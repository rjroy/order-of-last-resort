extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_catalog_test.gd
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
	defs.adventures = {"first_outing": {
		"label": "Test company", "roster": ["knight", "healer", "wizard"],
		"party_size": 3, "missions": ["fixture"]
	}}
	defs.commission_settings = {"roster_adventure": "first_outing"}
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
	for value in ["missing_adventure", "", 42, null]:
		var bad := defs.duplicate(true)
		bad.commission_settings.roster_adventure = value
		_invalid(bad, "invalid roster adventure " + str(value))
	var missing := defs.duplicate(true)
	missing.commission_settings.erase("roster_adventure")
	_invalid(missing, "missing roster adventure")


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
	# This encounter and mission are not referenced by the roster adventure.
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


func _test_authored() -> void:
	var defs: Dictionary = Catalog.read_default()
	_valid(defs, "built-in commission catalog")
	if defs.get("mission_reports", {}).size() != 20:
		failures.append("built-in catalog must include all 20 mission reports")
