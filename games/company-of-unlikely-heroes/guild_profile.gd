extends RefCounted

## The profile records only the guild identity and the next commission board.
## It is not an adventure save or a record of rewards.
const DEFAULT_PATH := "user://company_of_unlikely_heroes/guild_profile_v1.json"
const MAX_NAME_LENGTH := 80
const FORMAT_VERSION := 1


## Returns {} for a missing profile, {"error": ...} for invalid or unreadable
## data, or {"name": String, "board_seed": int} for a valid profile.
static func load_profile(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			return {"error": "Profile path is a directory."}
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Could not read profile: %s" % error_string(FileAccess.get_open_error())}
	var contents := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"error": "Could not read profile: %s" % error_string(read_error)}
	var json := JSON.new()
	if json.parse(contents) != OK or not json.data is Dictionary:
		return {"error": "Invalid profile data."}
	var data: Dictionary = json.data
	var version: Variant = data.get("version")
	if data.size() != 3 or (not version is int and not version is float):
		return {"error": "Unsupported or invalid profile format."}
	if version != FORMAT_VERSION:
		return {"error": "Unsupported or invalid profile format."}
	if not data.get("name") is String or not data.get("board_seed") is String:
		return {"error": "Invalid profile fields."}
	var guild_name: String = data["name"]
	var seed_text: String = data["board_seed"]
	if not _valid_name(guild_name) or not seed_text.is_valid_int():
		return {"error": "Invalid profile fields."}
	# Reject numbers outside the signed 64-bit range rather than silently clamping.
	var seed_value := seed_text.to_int()
	if str(seed_value) != seed_text:
		return {"error": "Invalid profile seed."}
	return {"name": guild_name, "board_seed": seed_value}


## Creates a profile only when no file already exists. Returns the same shapes
## as load_profile, with validation and write failures reported as errors.
static func create(path: String, guild_name: String, seed: int) -> Dictionary:
	guild_name = guild_name.strip_edges()
	if not _valid_name(guild_name):
		return {"error": "Guild name must contain 1 to %d characters." % MAX_NAME_LENGTH}
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return {"error": "A guild profile already exists."}
	return _write_profile(path, {"name": guild_name, "board_seed": seed})


## Replaces only the board seed of the current profile after an outing.
## Rejects stale or invalid caller data rather than overwriting another profile.
static func renew(path: String, profile: Dictionary, new_seed: int) -> Dictionary:
	var current := load_profile(path)
	if current.has("error"):
		return current
	if current.is_empty():
		return {"error": "Guild profile does not exist."}
	if current != profile:
		return {"error": "Guild profile has changed or is invalid."}
	return _write_profile(path, {"name": current["name"], "board_seed": new_seed})


static func _valid_name(guild_name: String) -> bool:
	return not guild_name.strip_edges().is_empty() and guild_name.length() <= MAX_NAME_LENGTH


static func _write_profile(path: String, profile: Dictionary) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory := absolute_path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return {"error": "Could not create profile directory: %s" % error_string(error)}
	# A sibling ensures the final rename stays on the same filesystem.
	var temp_path := "%s.tmp.%d.%d" % [absolute_path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"error": "Could not write profile: %s" % error_string(FileAccess.get_open_error())}
	# A decimal string preserves all 64-bit seeds through JSON parsing.
	var contents := JSON.stringify({
		"version": FORMAT_VERSION,
		"name": profile["name"],
		"board_seed": str(profile["board_seed"]),
	})
	var stored := file.store_string(contents)
	file.flush()
	error = file.get_error()
	file.close()
	if not stored or error != OK:
		DirAccess.remove_absolute(temp_path)
		return {"error": "Could not write profile%s" % (": " + error_string(error) if error != OK else ".")}
	# A successful buffered write or flush does not guarantee the closed file
	# contains the data. Verify bounded bytes before replacing the old profile.
	var expected := contents.to_utf8_buffer()
	var check := FileAccess.open(temp_path, FileAccess.READ)
	if check == null:
		DirAccess.remove_absolute(temp_path)
		return {"error": "Could not verify written profile."}
	var matches := check.get_length() == expected.size()
	if matches:
		matches = check.get_buffer(expected.size()) == expected and check.get_error() == OK
	check.close()
	if not matches:
		DirAccess.remove_absolute(temp_path)
		return {"error": "Written profile did not match expected data."}
	error = DirAccess.rename_absolute(temp_path, absolute_path)
	if error != OK:
		DirAccess.remove_absolute(temp_path)
		return {"error": "Could not replace profile: %s" % error_string(error)}
	return profile
