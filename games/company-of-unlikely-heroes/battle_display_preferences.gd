extends RefCounted
## Display choices belong to the player, not to a guild or a mission.

const PATH := "user://battle_display.cfg"
const SECTION := "battle"
const GRID_VISIBLE := "grid_visible"
const NAMEPLATES_VISIBLE := "nameplates_visible"


static func load_grid_visible() -> bool:
	return _load_visibility(GRID_VISIBLE, "grid")


static func load_nameplates_visible() -> bool:
	return _load_visibility(NAMEPLATES_VISIBLE, "nameplate")


static func save_grid_visible(shown: bool) -> void:
	_save_visibility(GRID_VISIBLE, "grid", shown)


static func save_nameplates_visible(shown: bool) -> void:
	_save_visibility(NAMEPLATES_VISIBLE, "nameplate", shown)


static func _load_visibility(key: String, label: String) -> bool:
	var config := ConfigFile.new()
	if _load(config) != OK:
		return true
	var stored: Variant = config.get_value(SECTION, key, true)
	if stored is bool:
		return stored
	push_warning("Ignoring an invalid battlefield %s preference." % label)
	return true


static func _save_visibility(key: String, label: String, shown: bool) -> void:
	var config := ConfigFile.new()
	var load_error := _load(config)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return
	config.set_value(SECTION, key, shown)
	print_verbose("Saving battlefield %s preference (visible: %s) to %s." % [label, shown, PATH])
	var error := config.save(PATH)
	if error == OK:
		print_verbose("Battlefield %s preference saved." % label)
	else:
		push_warning("Could not save battlefield %s preference to %s: %s" % [label, PATH, error_string(error)])


static func _load(config: ConfigFile) -> Error:
	print_verbose("Reading battle display preferences from %s." % PATH)
	var error := config.load(PATH)
	match error:
		OK:
			print_verbose("Battle display preferences loaded.")
		ERR_FILE_NOT_FOUND:
			print_verbose("No saved battle display preferences.")
		_:
			push_warning("Could not read battle display preferences from %s: %s" % [PATH, error_string(error)])
	return error
