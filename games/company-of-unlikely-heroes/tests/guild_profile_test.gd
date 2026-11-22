extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_profile_test.gd
const PROFILE_SCRIPT := "res://guild_profile.gd"
const GUILD_NAME := "The Test Company"
const INITIAL_SEED := 147258
const RENEWED_SEED := 369121
const FOUNDERS := ["knight", "healer", "wizard"]
const LEGACY_ROSTER := ["knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard"]

var failures: Array[String] = []
var profile_store: Script
var completed: Dictionary = {}


func _initialize() -> void:
	if not ResourceLoader.exists(PROFILE_SCRIPT):
		_check(false, "Missing guild_profile.gd")
	else:
		profile_store = load(PROFILE_SCRIPT)
		var args := OS.get_cmdline_user_args()
		if args.size() == 2 and args[0] == "--check-relaunch":
			_check_profile(_load_profile(args[1]), INITIAL_SEED, "Relaunched process")
		elif args.size() == 2 and args[0] == "--check-write-failure":
			var original := _load_profile(args[1])
			_check_profile(original, INITIAL_SEED, "Before limited write")
			var result: Dictionary = profile_store.call("renew", args[1], original, RENEWED_SEED)
			_check(result.has("error"), "Limited write reports an error: " + str(result))
			var message: String = result.get("error", "")
			_check(message.begins_with("Could not write profile") or message.begins_with("Written profile did not match"),
				"Limited write fails during writing or verification: " + str(result))
			_check_profile(_load_profile(args[1]), INITIAL_SEED, "After limited write")
		else:
			_test_profile()
			_check(completed.get("profile", false), "Profile test body completed")
	if failures.is_empty():
		print("PASS: guild profile")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _load_profile(path: String) -> Dictionary:
	return profile_store.call("load_profile", path)


func _check_profile(profile: Dictionary, seed_value: int, label: String) -> void:
	_check(profile.get("name") == GUILD_NAME and profile.get("board_seed") == seed_value,
		label + ": expected guild identity and board seed; got " + str(profile))


func _check_roster(profile: Dictionary, expected: Array, label: String) -> void:
	var roster: Variant = profile.get("recruited_ids")
	_check(roster is Array, label + ": profile exposes recruited_ids: " + str(profile))
	if roster is Array:
		var actual: Array = roster.duplicate()
		var wanted := expected.duplicate()
		actual.sort()
		wanted.sort()
		_check(actual == wanted, label + ": expected roster " + str(wanted) + "; got " + str(actual))


func _check_zero_points(profile: Dictionary, label: String, expected_purchases: Array = []) -> void:
	_check(profile.has("points") and profile.get("points") == 0,
		label + ": no points are invented: " + str(profile))
	_check(profile.get("purchased_ids") is Array and profile.get("purchased_ids") == expected_purchases,
		label + ": only expected entitlements are recorded: " + str(profile))
	_check(profile.get("board_generation") is int and profile.get("board_generation", -1) >= 0,
		label + ": profile exposes a nonnegative board generation: " + str(profile))


func _check_renewed_progression(before: Dictionary, after: Dictionary, label: String) -> void:
	for key in ["recruited_ids", "points", "purchased_ids"]:
		_check(before.has(key) and after.has(key) and before[key] == after[key],
			label + ": renewal preserves " + key)
	var previous_generation: Variant = before.get("board_generation")
	var next_generation: Variant = after.get("board_generation")
	_check(previous_generation is int and next_generation is int,
		label + ": renewal exposes board generations")
	if previous_generation is int and next_generation is int:
		_check(next_generation == previous_generation + 1,
			label + ": renewal increments board generation exactly once")


func _test_profile() -> void:
	# A unique test-owned file avoids touching any player's real profile or parallel test.
	var path := "user://guild_profile_test_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(_load_profile(path).is_empty(), "Missing profile loads as an empty dictionary")
	for blank in ["", " ", "\t\n"]:
		var rejected: Dictionary = profile_store.call("create", path, blank, INITIAL_SEED)
		_check(rejected.has("error"), "Blank guild name is rejected: " + str(blank))
		_check(_load_profile(path).is_empty(), "Rejected name does not create a profile")

	var created: Dictionary = profile_store.call("create", path, GUILD_NAME, INITIAL_SEED)
	_check_profile(created, INITIAL_SEED, "Created profile")
	_check_roster(created, FOUNDERS, "Fresh profile")
	_check_zero_points(created, "Fresh profile")
	var reloaded := _load_profile(path)
	_check_profile(reloaded, INITIAL_SEED, "Reloaded profile before an outing")
	_check(reloaded == created, "Creation round-trips every progression field")

	_test_write_failure(path)
	_check(completed.get("write_failure", false), "Write failure test completed or was skipped")
	_test_unicode_and_int64()
	_check(completed.get("unicode", false), "Unicode and int64 test completed")
	_test_invalid_versions()
	_check(completed.get("versions", false), "Invalid versions test completed")
	_test_legacy_migration()
	_check(completed.get("migration", false), "Legacy migration test completed")
	_test_v2_preference()

	# Launch a new Godot process, rather than relying on a cached in-memory dictionary.
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/guild_profile_test.gd", "--", "--check-relaunch", path
	], output, true)
	_check(exit_code == 0, "Profile survives a process relaunch: " + str(output))

	var unchanged := _load_profile(path)
	_check_profile(unchanged, INITIAL_SEED, "Loading again does not refresh the board")
	# Renewal must preserve all progression while replacing the board seed.
	var renewed: Dictionary = profile_store.call("renew", path, unchanged, RENEWED_SEED)
	_check_profile(renewed, RENEWED_SEED, "Renewal after return")
	_check_renewed_progression(unchanged, renewed, "Renewal after return")
	_check(_load_profile(path) == renewed, "Renewed progression survives disk round-trip")
	var before_stale := FileAccess.get_file_as_bytes(path)
	var stale: Dictionary = profile_store.call("renew", path, unchanged, INITIAL_SEED)
	_check(stale.has("error"), "Stale profile cannot overwrite a newer update")
	_check(FileAccess.get_file_as_bytes(path) == before_stale, "Stale update leaves file unchanged")

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Could not write corrupt profile fixture")
	else:
		file.store_string("{ invalid json")
		file.close()
		_check(_load_profile(path).has("error"), "Corrupt profile reports an error")
		var rejected_create: Dictionary = profile_store.call("create", path, GUILD_NAME, INITIAL_SEED)
		_check(rejected_create.has("error"), "Create does not overwrite a corrupt profile")
		var rejected_renew: Dictionary = profile_store.call("renew", path, renewed, INITIAL_SEED)
		_check(rejected_renew.has("error"), "Renew does not overwrite a corrupt profile")
		_check(FileAccess.get_file_as_string(path) == "{ invalid json", "Corrupt file remains available for recovery")

	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_check(remove_error == OK, "Test-owned profile is removed: " + str(remove_error))
	completed["profile"] = true


func _test_write_failure(path: String) -> void:
	if OS.get_name() != "Linux" or not FileAccess.file_exists("/bin/bash"):
		print("SKIP: write failure regression requires Linux and /bin/bash")
		completed["write_failure"] = true
		return
	var output: Array = []
	var original_bytes := FileAccess.get_file_as_bytes(path)
	# The child inherits the ignored SIGXFSZ and a zero-byte file size limit.
	# Positional arguments avoid interpolating test paths into shell code.
	var exit_code := OS.execute("/bin/bash", [
		"-c", "trap '' XFSZ; ulimit -f 0 || exit 77; exec \"$@\"", "guild-profile-test",
		OS.get_executable_path(), "--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/guild_profile_test.gd", "--", "--check-write-failure", path
	], output, true)
	if exit_code == 77:
		print("SKIP: could not set file size limit")
		completed["write_failure"] = true
		return
	_check(exit_code == 0, "Failed write preserves profile: " + str(output))
	_check_profile(_load_profile(path), INITIAL_SEED, "Profile preserved after failed write")
	_check(FileAccess.get_file_as_bytes(path) == original_bytes, "Failed write preserves original bytes")
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory := DirAccess.open(absolute_path.get_base_dir())
	if directory == null:
		_check(false, "Could not inspect profile directory for temporary files")
		return
	for entry in directory.get_files():
		_check(not entry.begins_with(absolute_path.get_file() + ".tmp."),
			"Failed write leaves no temporary file: " + entry)
	completed["write_failure"] = true


func _test_unicode_and_int64() -> void:
	var path := "user://guild_profile_unicode_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var expected := {"name": "Étoile 雪 🐉", "board_seed": 9223372036854775807}
	var created: Dictionary = profile_store.call("create", path, expected["name"], expected["board_seed"])
	_check(created.get("name") == expected["name"] and created.get("board_seed") == expected["board_seed"],
		"Unicode and maximum int64 creation: " + str(created))
	_check(_load_profile(path) == created, "Unicode and maximum int64 reload")
	var renewed: Dictionary = profile_store.call("renew", path, created, -9223372036854775807 - 1)
	_check(renewed.get("name") == expected["name"] and renewed.get("board_seed") == -9223372036854775807 - 1,
		"Minimum int64 renewal: " + str(renewed))
	_check_renewed_progression(created, renewed, "Unicode profile renewal")
	_check(_load_profile(path) == renewed, "Unicode and minimum int64 reload")
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_check(remove_error == OK, "Unicode test profile is removed: " + str(remove_error))
	completed["unicode"] = true


func _test_invalid_versions() -> void:
	var path := "user://guild_profile_versions_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var current_version: int = profile_store.get_script_constant_map().get("FORMAT_VERSION", 1)
	_check(current_version > 1, "Progression uses a new profile format version")
	for version in ["1", true, [], {}, null, 1.5, current_version + 1]:
		var contents := JSON.stringify({"version": version, "name": GUILD_NAME, "board_seed": str(INITIAL_SEED)})
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_check(false, "Could not write invalid version fixture")
			return
		file.store_string(contents)
		file.close()
		_check(_load_profile(path).has("error"), "Invalid version reports error: " + str(version))
		var created: Dictionary = profile_store.call("create", path, GUILD_NAME, INITIAL_SEED)
		_check(created.has("error"), "Invalid version cannot be overwritten by create")
		var renewed: Dictionary = profile_store.call("renew", path,
			{"name": GUILD_NAME, "board_seed": INITIAL_SEED}, RENEWED_SEED)
		_check(renewed.has("error"), "Invalid version cannot be overwritten by renew")
		_check(FileAccess.get_file_as_string(path) == contents, "Invalid version file remains unchanged")
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(remove_error == OK, "Version test profile is removed: " + str(remove_error))
	completed["versions"] = true


func _test_legacy_migration() -> void:
	var path := "user://guild_profile_legacy_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Could not write legacy profile fixture")
		return
	file.store_string('{"version":1,"name":"The Test Company","board_seed":"147258"}')
	file.close()
	var migrated := _load_profile(path)
	_check_profile(migrated, INITIAL_SEED, "Migrated v1 profile")
	_check_roster(migrated, LEGACY_ROSTER, "Migrated v1 profile")
	_check_zero_points(migrated, "Migrated v1 profile", ["alchemist_throw_samples"])
	var defs: Dictionary = preload("res://content/catalog.gd").read_default()
	for hero in LEGACY_ROSTER:
		var kit: Dictionary = profile_store.call("default_loadout", defs, migrated, hero)
		_check(not kit.is_empty(), "Migrated v1 retains a usable kit for " + hero)
		for row in profile_store.call("petitions", defs, migrated):
			if row.get("id") == "recruit_" + hero:
				_check(row.get("owned", false), "Migrated v1 does not pay twice for " + hero)
	if not migrated.has("error") and not migrated.is_empty():
		var renewed: Dictionary = profile_store.call("renew", path, migrated, RENEWED_SEED)
		_check_profile(renewed, RENEWED_SEED, "Renewed migrated profile")
		_check_renewed_progression(migrated, renewed, "Migrated profile")
		_check(_load_profile(path) == renewed, "Migrated progression survives disk round-trip")
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(remove_error == OK, "Legacy test profile is removed: " + str(remove_error))
	completed["migration"] = true


func _test_v2_preference() -> void:
	var path := "user://guild_profile_v2_preference_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	# This is an already-written v2 preference, not a fresh guild purchase.
	var stored := {"version": 2, "name": GUILD_NAME, "board_seed": str(INITIAL_SEED),
		"guild_id": "a".repeat(64), "points": "0", "board_generation": "0",
		"recruited_ids": LEGACY_ROSTER, "purchased_ids": [],
		"preferred_loadouts": {"alchemist": {"slots": {"offense": "alchemist_acid",
			"utility": "alchemist_potion"}, "order_id": "order_throw_samples"}},
		"last_receipt": {}}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Could not write existing v2 profile")
		return
	file.store_string(JSON.stringify(stored))
	file.close()
	var loaded := _load_profile(path)
	var defs: Dictionary = preload("res://content/catalog.gd").read_default()
	_check(not loaded.has("error"), "Existing v2 profile loads")
	if not loaded.has("error"):
		_check_zero_points(loaded, "Migrated v2 profile", ["alchemist_throw_samples"])
		_check(profile_store.call("default_loadout", defs, loaded, "alchemist") == stored.preferred_loadouts.alchemist,
			"Existing v2 Throw Samples preference remains valid without another purchase")
		var renewed: Dictionary = profile_store.call("renew", path, loaded, RENEWED_SEED)
		_check(not renewed.has("error") and _load_profile(path) == renewed
			and renewed.get("preferred_loadouts", {}) == stored.preferred_loadouts,
			"Existing v2 preference survives save and reload")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
		"Existing v2 profile fixture is removed")
