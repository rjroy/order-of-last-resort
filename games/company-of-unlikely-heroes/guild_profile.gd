extends RefCounted

## Only guild progress and preparation persist. Missions and their rewards do not.
# Keep the original location so v1 guilds are found and grandfathered.
const DEFAULT_PATH := "user://company_of_unlikely_heroes/guild_profile_v1.json"
const MAX_NAME_LENGTH := 80
const FORMAT_VERSION := 3
const FOUNDERS := ["knight", "healer", "wizard"]
const LEGACY_ROSTER := ["knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard"]
const MAX_COUNTER := 9223372036854775807
const Adventure = preload("res://adventure.gd")
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild_progression.gd")


## Returns {} for a missing profile, {"error": ...} for invalid or unreadable
## data, or a profile dictionary for a valid file. v1 migration is read-only
## until the first successful update, so a failed load/update never rewrites it.
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
	# JSON numbers arrive as floats; Array membership uses strict variant types.
	if not (version is int or version is float) or float(version) not in [1.0, 2.0, float(FORMAT_VERSION)]:
		return {"error": "Unsupported or invalid profile format."}
	if not data.get("name") is String or not data.get("board_seed") is String:
		return {"error": "Invalid profile fields."}
	var guild_name: String = data["name"]
	var seed_value: Variant = _parse_int(data.board_seed)
	if not _valid_name(guild_name) or seed_value == null:
		return {"error": "Invalid profile fields."}
	if float(version) == 1.0:
		if data.size() != 3:
			return {"error": "Unsupported or invalid profile format."}
		var legacy_id := ("legacy\n%s\n%s" % [guild_name, data.board_seed]).sha256_text()
		return _migrate_legacy(_new_profile(guild_name, seed_value, legacy_id, LEGACY_ROSTER))
	var result := _read_progression(data, seed_value)
	if float(version) == 2.0 and not result.has("error"):
		return _migrate_legacy(result)
	return result


static func _migrate_legacy(profile: Dictionary) -> Dictionary:
	# Existing recruits already had this order, whether or not it was selected.
	if "alchemist" in profile.recruited_ids and "alchemist_throw_samples" not in profile.purchased_ids:
		profile.purchased_ids.append("alchemist_throw_samples")
	return profile


## Creates a profile only when no file already exists. Returns the same shapes
## as load_profile, with validation and write failures reported as errors.
static func create(path: String, guild_name: String, seed: int) -> Dictionary:
	guild_name = guild_name.strip_edges()
	if not _valid_name(guild_name):
		return {"error": "Guild name must contain 1 to %d characters." % MAX_NAME_LENGTH}
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return {"error": "A guild profile already exists."}
	var guild_id := Crypto.new().generate_random_bytes(32).hex_encode()
	if guild_id.is_empty():
		return {"error": "Could not create a guild identity."}
	return _write_profile(path, _new_profile(guild_name, seed, guild_id, FOUNDERS))


## Unscoped commission compatibility: renew without crediting a receipt.
static func renew(path: String, profile: Dictionary, new_seed: int) -> Dictionary:
	var current := _current_profile(path, profile)
	if current.has("error"):
		return current
	var next := _renewed_profile(current, new_seed)
	return next if next.has("error") else _write_profile(path, next)


static func balance(profile: Dictionary) -> int:
	return profile.get("points", 0)


static func roster(defs: Dictionary, profile: Dictionary) -> Array[String]:
	return Progression.roster(defs, profile)


static func petitions(defs: Dictionary, profile: Dictionary) -> Array[Dictionary]:
	return Progression.petitions(defs, profile)


static func purchase(path: String, profile: Dictionary, defs: Dictionary, petition_id: String) -> Dictionary:
	var current := _current_profile(path, profile)
	if current.has("error"):
		return current
	if not Catalog.validate(defs).is_empty() or not Catalog.validate_guild_progression(defs).is_empty():
		return {"error": "This catalog does not have valid guild petitions."}
	var next := Progression.purchased_profile(defs, current, petition_id)
	return next if next.has("error") else _write_profile(path, next)


static func slot_options(defs: Dictionary, profile: Dictionary, hero_id: String) -> Dictionary:
	return Progression.slot_options(defs, profile, hero_id)


static func default_loadout(defs: Dictionary, profile: Dictionary, hero_id: String) -> Dictionary:
	return Progression.default_loadout(defs, profile, hero_id)


static func order_options(defs: Dictionary, profile: Dictionary, hero_id: String,
		loadout: Dictionary) -> Array[Dictionary]:
	return Progression.order_options(defs, profile, hero_id, loadout)


static func save_loadouts(path: String, profile: Dictionary, defs: Dictionary, loadouts: Dictionary) -> Dictionary:
	var current := _current_profile(path, profile)
	if current.has("error"):
		return current
	if not Catalog.validate(defs).is_empty() or not Catalog.validate_guild_progression(defs).is_empty() \
			or not Progression.valid_loadouts(defs, current, loadouts):
		return {"error": "The company has an invalid or incompatible loadout."}
	var next := current.duplicate(true)
	next.preferred_loadouts.merge(loadouts.duplicate(true), true)
	return current if next == current else _write_profile(path, next)


static func valid_loadouts(defs: Dictionary, profile: Dictionary, loadouts: Dictionary) -> bool:
	return Progression.valid_loadouts(defs, profile, loadouts)


static func settle_return(path: String, profile: Dictionary, run: Dictionary, new_seed: int) -> Dictionary:
	var current := _load_existing_profile(path)
	if current.has("error"):
		return current
	# Only a return can rebase: validate the run against the caller's board,
	# then apply the payout to the latest snapshot of that exact board.
	if not is_same(current.guild_id, profile.get("guild_id")) \
			or not is_same(current.board_seed, profile.get("board_seed")) \
			or not is_same(current.board_generation, profile.get("board_generation")):
		return {"error": "This commission cannot be settled on the current board."}
	var receipt := Adventure.settlement_receipt(run, profile)
	if receipt.is_empty():
		return {"error": "This commission cannot be settled on the current board."}
	if new_seed == current.board_seed:
		return {"error": "Returning requires a fresh commission board seed."}
	var next := _renewed_profile(current, new_seed)
	if next.has("error"):
		return next
	if current.points > MAX_COUNTER - receipt.points:
		return {"error": "The guild point balance is too large."}
	next.points += receipt.points
	next.last_receipt = receipt
	return _write_profile(path, next)


static func _current_profile(path: String, profile: Dictionary) -> Dictionary:
	var current := _load_existing_profile(path)
	if current.has("error"):
		return current
	if current != profile:
		return {"error": "Guild profile has changed or is invalid."}
	return current


static func _load_existing_profile(path: String) -> Dictionary:
	var current := load_profile(path)
	if current.is_empty():
		return {"error": "Guild profile does not exist."}
	return current


static func _renewed_profile(current: Dictionary, new_seed: int) -> Dictionary:
	if current.board_generation == MAX_COUNTER:
		return {"error": "The guild board generation is too large."}
	var next := current.duplicate(true)
	next.board_seed = new_seed
	next.board_generation += 1
	return next


static func _new_profile(guild_name: String, seed: int, guild_id: String, recruits: Array) -> Dictionary:
	return {"name": guild_name, "board_seed": seed, "guild_id": guild_id, "points": 0,
		"recruited_ids": recruits.duplicate(), "purchased_ids": [], "board_generation": 0,
		"preferred_loadouts": {}, "last_receipt": {}}


static func _read_progression(data: Dictionary, seed: int) -> Dictionary:
	var points: Variant = _parse_int(data.get("points"))
	var generation: Variant = _parse_int(data.get("board_generation"))
	var guild_id: Variant = data.get("guild_id")
	if data.size() != 10 or points == null or points < 0 or generation == null or generation < 0 \
			or not guild_id is String or guild_id.length() != 64 or not guild_id.is_valid_hex_number() \
			or not _is_id_array(data.get("recruited_ids")) or not _is_id_array(data.get("purchased_ids")) \
			or not _valid_stored_loadouts(data.get("preferred_loadouts"), data.get("recruited_ids")):
		return {"error": "Invalid guild progression fields."}
	var receipt := _read_receipt(data.get("last_receipt"), generation)
	if receipt.has("error"):
		return receipt
	var result := data.duplicate(true)
	result.erase("version")
	result.board_seed = seed
	result.points = points
	result.board_generation = generation
	result.last_receipt = receipt
	return result


static func _valid_stored_loadouts(value: Variant, recruits: Array) -> bool:
	if not value is Dictionary:
		return false
	for hero_id in value:
		var loadout: Variant = value[hero_id]
		if hero_id not in recruits or not loadout is Dictionary \
				or loadout.size() != 2 or not _is_id(loadout.get("order_id")):
			return false
		var slots: Variant = loadout.get("slots")
		if not slots is Dictionary or slots.is_empty():
			return false
		for slot_id in slots:
			if not _is_id(slot_id) or not _is_id(slots[slot_id]):
				return false
	return true


static func _read_receipt(value: Variant, generation: int) -> Dictionary:
	if value is Dictionary and value.is_empty():
		return {}
	var invalid := {"error": "Invalid guild receipt."}
	if not value is Dictionary or value.size() != 7:
		return invalid
	var source_seed: Variant = _parse_int(value.get("board_seed"))
	var source_generation: Variant = _parse_int(value.get("board_generation"))
	if source_seed == null or source_generation == null or source_generation < 0 or source_generation >= generation:
		return invalid
	var destination: Variant = value.get("destination_outcome")
	var roads: Variant = value.get("road_wins")
	if not destination is String or destination not in ["not_reached", "victory", "defeat", "forfeit"] \
			or not (roads is int or roads is float) or roads < 0 or roads > 9 or float(roads) != floorf(roads):
		return invalid
	var receipt := Adventure.accounting(source_seed, source_generation, int(roads), destination)
	for key in ["road_points", "destination_points", "points"]:
		var amount: Variant = value.get(key)
		if not (amount is int or amount is float) or float(amount) != float(receipt[key]):
			return invalid
	return receipt


static func _parse_int(value: Variant) -> Variant:
	if not value is String or not value.is_valid_int():
		return null
	var number: int = value.to_int()
	# Reject overflow and noncanonical decimals instead of accepting clamped values.
	return number if str(number) == value else null


static func _is_id_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen := {}
	for id in value:
		if not _is_id(id) or seen.has(id):
			return false
		seen[id] = true
	return true


static func _is_id(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


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
	# Decimal strings preserve 64-bit values through JSON's floating-point parser.
	var persisted := profile.duplicate(true)
	persisted.version = FORMAT_VERSION
	for field in ["board_seed", "board_generation", "points"]:
		persisted[field] = str(persisted[field])
	if not persisted.last_receipt.is_empty():
		for field in ["board_seed", "board_generation"]:
			persisted.last_receipt[field] = str(persisted.last_receipt[field])
	var contents := JSON.stringify(persisted)
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
