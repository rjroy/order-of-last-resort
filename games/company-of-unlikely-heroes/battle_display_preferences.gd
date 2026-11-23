extends RefCounted
## Display choices belong to the player, not to a guild or a mission.

const PATH := "user://battle_display.cfg"
const SECTION := "battle"
const GRID_VISIBLE := "grid_visible"


static func load_grid_visible() -> bool:
	var config := ConfigFile.new()
	if _load(config) != OK:
		return true
	var stored: Variant = config.get_value(SECTION, GRID_VISIBLE, true)
	if stored is bool:
		return stored
	push_warning("Ignoring an invalid battlefield grid preference.")
	return true


static func save_grid_visible(shown: bool) -> void:
	var config := ConfigFile.new()
	var load_error := _load(config)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return
	config.set_value(SECTION, GRID_VISIBLE, shown)
	print_verbose("Saving battlefield grid preference (visible: %s) to %s." % [shown, PATH])
	var error := config.save(PATH)
	if error == OK:
		print_verbose("Battlefield grid preference saved.")
	else:
		push_warning("Could not save battlefield grid preference to %s: %s" % [PATH, error_string(error)])


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
