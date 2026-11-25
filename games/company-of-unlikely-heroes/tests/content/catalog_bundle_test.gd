extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/content/catalog_bundle_test.gd
const Catalog = preload("res://content/catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var loaded := Catalog.read_source(Catalog.DEFAULT_PATH)
	_check(not loaded.has("error"), "built-in manifest loads")
	if not loaded.has("error"):
		var defs: Dictionary = loaded.definitions
		_check(defs.missions.bridge_patrol.encounter == "road_patrol", "mission references assembled encounter")
		_check(defs.encounters.company_crossing.board == "bridge", "encounter references shared board")
		_check(defs.commission_settings.recruitment_roster == [
			"knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard", "blacksmith"],
			"assembled commission eligibility retains all eight heroes in order")
		_check(not defs.has("adventures"), "built-in catalog has no fixed routes")
		var deployed := Catalog.build(defs, "bridge_patrol", ["knight", "healer", "alchemist"])
		_check(deployed.units.size() == 5, "assembled party and enemies deploy")
		_check(deployed.objective.team == "enemies", "combat target team materializes its default")
		_check(Catalog.build(defs, "bridge_patrol").is_empty(), "company mission rejects omitted party")
		_check(Catalog.build(defs, "bridge_patrol", ["knight", "healer"]).is_empty(),
			"company mission rejects partial party")
		_check(Catalog.build(defs, "bridge_patrol", ["knight", "healer", "wizard", "alchemist"]).is_empty(),
			"company mission rejects oversized party")
		var fixed_defs: Dictionary = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(defs.duplicate(true))
		_check(not Catalog.build(fixed_defs, "test_escort").is_empty(), "custom fixed mission builds without party")
		_check(Catalog.build(fixed_defs, "test_escort", ["knight"]).is_empty(), "custom fixed mission rejects supplied party")
		_test_reachable_content(defs)
		var brewer: Dictionary = Catalog.profile(defs, "alchemist")
		_check("alchemist_splash" not in brewer.get("abilities", [])
			and "knight_aura" not in brewer.get("abilities", [])
			and brewer.get("abilities", []) != Catalog.profile(defs, "healer").get("abilities", []),
			"alchemist has a distinct kit rather than the old splash-and-ward mix-in")
		var invalid := defs.duplicate(true)
		invalid.missions.bridge_patrol.tier = 0
		_check(not Catalog.validate(invalid).is_empty(), "tier must be positive")
		_test_full_catalog(defs)
		_test_full_catalog(fixed_defs)
		_test_custom_bundle(fixed_defs)
		_test_invalid_full_catalogs(defs)
	_test_duplicate_parts()
	var practice := Catalog.read_source("res://content/practice/catalog.json")
	_check(not practice.has("error") and practice.get("definitions", {}).get("missions", {}).has("founders_practice"),
		"separate practice manifest loads its encounter")
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: catalog bundle")
	quit(1 if not failures.is_empty() else 0)


func _test_duplicate_parts() -> void:
	# Test-owned data exercises assembly before full-catalog validation.
	var prefix := "user://catalog_bundle_test_"
	var manifest := prefix + "manifest.json"
	var first := prefix + "first.json"
	var second := prefix + "second.json"
	_write(first, '{"characters":{"same":{}}}')
	_write(second, '{"characters":{"same":{}}}')
	_write(manifest, '{"parts":["catalog_bundle_test_first.json","catalog_bundle_test_second.json"]}')
	var result := Catalog.read_source(manifest)
	_check(result.has("error") and "Duplicate characters ID 'same'" in result.get("error", ""),
		"duplicate IDs across parts are rejected")
	for path in [manifest, first, second]:
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			failures.append("could not remove test file " + path)


func _test_reachable_content(defs: Dictionary) -> void:
	var retained_missions := [
		"bridge_patrol", "company_rescue", "goblin_mob", "harpoon_squad", "unwelcome_guest",
		"shield_wall", "wrong_side_of_the_door", "cowardly_captain", "explosive_situation",
		"bridge_is_out", "last_wagon", "duelists", "great_sheep_escape", "odd_couple",
		"unfortunate_healer", "dont_wake_the_giant", "hold_the_line", "last_one_standing",
		"unfortunate_ritual", "mirror_company",
	]
	for mission in retained_missions:
		_check(defs.missions.has(mission), "retained mission is assembled: " + mission)
	for mission in defs.missions:
		_check(defs.mission_reports.has(mission), "shipped mission has a commission report: " + mission)
	var encounters := {}
	for mission in defs.missions.values():
		encounters[mission.encounter] = true
	for encounter in defs.encounters:
		_check(encounters.has(encounter), "shipped encounter is reachable: " + encounter)
	for retired in ["ferryman", "extra_knight", "necromancer_wave"]:
		_check(not defs.missions.has(retired), "retired fixture is not shipped: " + retired)
	_check(defs.missions.has("company_rescue") and defs.characters.has("ferryman"),
		"company rescue and its ferryman character remain available")
	var placements: Array = defs.encounters[defs.missions.company_rescue.encounter].placements
	_check(placements.any(func(placement): return placement.get("character") == "ferryman"),
		"company rescue still places the ferryman")


func _test_full_catalog(defs: Dictionary) -> void:
	var path := "user://catalog_bundle_test_full.json"
	_write(path, JSON.stringify(defs))
	var result := Catalog.read_source(path)
	_check(not result.has("error") and result.get("definitions", {}) == defs,
		"full catalog input remains supported")
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		failures.append("could not remove test file " + path)


func _test_custom_bundle(defs: Dictionary) -> void:
	var manifest := "user://catalog_bundle_test_custom_manifest.json"
	var part := "user://catalog_bundle_test_custom_part.json"
	_write(part, JSON.stringify(defs))
	_write(manifest, '{"parts":["catalog_bundle_test_custom_part.json"]}')
	var result := Catalog.read_source(manifest)
	_check(not result.has("error") and result.get("definitions", {}) == defs,
		"custom bundle preserves fixed encounter definitions")
	if not result.has("error"):
		_check(not Catalog.build(result.definitions, "test_escort").is_empty(),
			"custom bundle fixed encounter builds")
	for path in [manifest, part]:
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			failures.append("could not remove test file " + path)


func _test_invalid_full_catalogs(defs: Dictionary) -> void:
	var path := "user://catalog_bundle_test_invalid.json"
	var invalid := defs.duplicate(true)
	invalid.encounters.road_patrol.party_slots.append([0, 0])
	_check_full_error(path, invalid, "must have exactly 3 party slots", "inconsistent commission slots")
	invalid = defs.duplicate(true)
	invalid.encounters.company_crossing.deadline = 0
	_check_full_error(path, invalid, "deadline failure requires a positive encounter deadline", "zero deadline failure")
	invalid.encounters.company_crossing.erase("deadline")
	_check_full_error(path, invalid, "deadline failure requires a positive encounter deadline", "absent deadline failure")
	invalid = defs.duplicate(true)
	invalid.missions.bridge_patrol.objective.handler = []
	_check_full_error(path, invalid, "missions.bridge_patrol.objective.handler: expected one of", "malformed objective handler")
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		failures.append("could not remove test file " + path)


func _check_full_error(path: String, defs: Dictionary, diagnostic: String, message: String) -> void:
	_write(path, JSON.stringify(defs))
	var result := Catalog.read_source(path)
	_check(result.has("error") and diagnostic in result.get("error", ""), message + " returns a diagnostic")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("could not write test file " + path)
	else:
		file.store_string(text)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
