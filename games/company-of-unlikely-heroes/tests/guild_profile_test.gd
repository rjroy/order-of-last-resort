extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_profile_test.gd
const PROFILE_SCRIPT := "res://guild_profile.gd"
const GUILD_NAME := "The Test Company"
const INITIAL_SEED := 147258
const RENEWED_SEED := 369121

var failures: Array[String] = []
var profile_store: Script


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
	_check(profile == {"name": GUILD_NAME, "board_seed": seed_value},
		label + ": only guild name and expected board seed are stored; got " + str(profile))


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
	_check_profile(_load_profile(path), INITIAL_SEED, "Reloaded profile before an outing")

	_test_write_failure(path)
	_test_unicode_and_int64()
	_test_invalid_versions()

	# Launch a new Godot process, rather than relying on a cached in-memory dictionary.
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/guild_profile_test.gd", "--", "--check-relaunch", path
	], output, true)
	_check(exit_code == 0, "Profile survives a process relaunch: " + str(output))

	var unchanged := _load_profile(path)
	_check_profile(unchanged, INITIAL_SEED, "Loading again does not refresh the board")
	# The caller invokes renew on return from an outing. It changes only the board seed,
	# so no payout or other persistent progression can be introduced by renewal.
	var renewed: Dictionary = profile_store.call("renew", path, unchanged, RENEWED_SEED)
	_check_profile(renewed, RENEWED_SEED, "Renewal after return")
	_check_profile(_load_profile(path), RENEWED_SEED, "Reloaded renewed profile")

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Could not write corrupt profile fixture")
	else:
		file.store_string("{ invalid json")
		file.close()
		_check(_load_profile(path).has("error"), "Corrupt profile reports an error")

	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_check(remove_error == OK, "Test-owned profile is removed: " + str(remove_error))


func _test_write_failure(path: String) -> void:
	if OS.get_name() != "Linux" or not FileAccess.file_exists("/bin/bash"):
		print("SKIP: write failure regression requires Linux and /bin/bash")
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


func _test_unicode_and_int64() -> void:
	var path := "user://guild_profile_unicode_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var expected := {"name": "Étoile 雪 🐉", "board_seed": 9223372036854775807}
	var created: Dictionary = profile_store.call("create", path, expected["name"], expected["board_seed"])
	_check(created == expected, "Unicode and maximum int64 creation: " + str(created))
	_check(_load_profile(path) == expected, "Unicode and maximum int64 reload")
	var renewed: Dictionary = profile_store.call("renew", path, expected, -9223372036854775807 - 1)
	expected["board_seed"] = -9223372036854775807 - 1
	_check(renewed == expected, "Minimum int64 renewal: " + str(renewed))
	_check(_load_profile(path) == expected, "Unicode and minimum int64 reload")
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_check(remove_error == OK, "Unicode test profile is removed: " + str(remove_error))


func _test_invalid_versions() -> void:
	var path := "user://guild_profile_versions_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	for version in ["1", true, [], {}, null, 1.5, 2]:
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
