extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/catalog_bundle_test.gd
const Catalog = preload("res://content/catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var loaded := Catalog.read_source(Catalog.DEFAULT_PATH)
	_check(not loaded.has("error"), "built-in manifest loads")
	if not loaded.has("error"):
		var defs: Dictionary = loaded.definitions
		_check(defs.missions.bridge_patrol.encounter == "road_patrol", "adventure mission references assembled encounter")
		_check(defs.encounters.company_crossing.board == "bridge", "adventure references shared board")
		var deployed := Catalog.build(defs, "bridge_patrol", ["knight", "healer", "alchemist"])
		_check(deployed.units.size() == 5, "assembled party and enemies deploy")
		_check(deployed.objective.team == "enemies", "combat target team materializes its default")
		_check(Catalog.build(defs, "bridge_patrol").is_empty(), "company mission rejects omitted party")
		_check(Catalog.build(defs, "bridge_patrol", ["knight", "healer"]).is_empty(),
			"company mission rejects partial party")
		_check(Catalog.build(defs, "bridge_patrol", ["knight", "healer", "wizard", "alchemist"]).is_empty(),
			"company mission rejects oversized party")
		_check(not Catalog.build(defs, "ferryman").is_empty(), "fixed mission builds without party")
		_check(Catalog.build(defs, "ferryman", ["knight"]).is_empty(), "fixed mission rejects supplied party")
		var brewer: Dictionary = Catalog.profile(defs, "alchemist")
		_check(brewer.abilities == ["move", "alchemist_splash", "knight_aura"]
			and defs.abilities.alchemist_splash.params.damage == 3,
			"alchemist has a distinct risky splash and ward kit")
		var invalid := defs.duplicate(true)
		invalid.missions.bridge_patrol.tier = 0
		_check(not Catalog.validate(invalid).is_empty(), "tier must be positive")
		_test_full_catalog(defs)
		_test_invalid_full_catalogs(defs)
	_test_duplicate_parts()
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


func _test_full_catalog(defs: Dictionary) -> void:
	var path := "user://catalog_bundle_test_full.json"
	_write(path, JSON.stringify(defs))
	var result := Catalog.read_source(path)
	_check(not result.has("error") and result.get("definitions", {}) == defs,
		"full catalog input remains supported")
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		failures.append("could not remove test file " + path)


func _test_invalid_full_catalogs(defs: Dictionary) -> void:
	var path := "user://catalog_bundle_test_invalid.json"
	var invalid := defs.duplicate(true)
	invalid.encounters.road_patrol.party_slots.append([0, 0])
	_check_full_error(path, invalid, "must have exactly 3 party slots", "excess adventure slots")
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
