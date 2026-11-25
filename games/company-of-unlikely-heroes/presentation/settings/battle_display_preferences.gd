extends RefCounted
## Display choices belong to the player, not to a guild or a mission.

const PATH := "user://battle_display.cfg"
const SECTION := "battle"
const GRID_VISIBLE := "grid_visible"
const GRID_LABELS_VISIBLE := "grid_labels_visible"
const NAMEPLATES_VISIBLE := "nameplates_visible"
const ALWAYS_SHOW_HEALTH_BAR := "always_show_health_bar"
const SHOW_HINTS := "show_hints"
const SOUND_EFFECTS_VOLUME := "sound_effects_volume"
const MASTER_VOLUME := "master_volume"
const MUSIC_VOLUME := "music_volume"


static func load_grid_visible() -> bool:
	return _load_visibility(GRID_VISIBLE, "grid")


static func load_grid_labels_visible() -> bool:
	return _load_visibility(GRID_LABELS_VISIBLE, "grid labels")


static func load_nameplates_visible() -> bool:
	return _load_visibility(NAMEPLATES_VISIBLE, "nameplate")


static func load_always_show_health_bar() -> bool:
	return _load_visibility(ALWAYS_SHOW_HEALTH_BAR, "always show health bar", false)


static func load_show_hints() -> bool:
	return _load_visibility(SHOW_HINTS, "hints")


static func save_grid_visible(shown: bool) -> void:
	_save_visibility(GRID_VISIBLE, "grid", shown)


static func save_grid_labels_visible(shown: bool) -> void:
	_save_visibility(GRID_LABELS_VISIBLE, "grid labels", shown)


static func save_nameplates_visible(shown: bool) -> void:
	_save_visibility(NAMEPLATES_VISIBLE, "nameplate", shown)


static func save_always_show_health_bar(shown: bool) -> void:
	_save_visibility(ALWAYS_SHOW_HEALTH_BAR, "always show health bar", shown)


static func save_show_hints(shown: bool) -> void:
	_save_visibility(SHOW_HINTS, "hints", shown)


static func load_sound_effects_volume() -> float:
	return _load_volume(SOUND_EFFECTS_VOLUME, 0.8)


static func load_master_volume() -> float:
	return _load_volume(MASTER_VOLUME, 1.0)


static func load_music_volume() -> float:
	return _load_volume(MUSIC_VOLUME, 1.0)


static func _load_volume(key: String, default: float) -> float:
	var config := ConfigFile.new()
	if _load(config) != OK:
		return default
	var stored: Variant = config.get_value(SECTION, key, default)
	if (stored is float or stored is int) and is_finite(float(stored)) \
			and float(stored) >= 0.0 and float(stored) <= 1.0:
		return float(stored)
	push_warning("Ignoring invalid %s preference." % key)
	return default


static func save_sound_effects_volume(volume: float) -> void:
	_save_volume(SOUND_EFFECTS_VOLUME, volume)


static func save_master_volume(volume: float) -> void:
	_save_volume(MASTER_VOLUME, volume)


static func save_music_volume(volume: float) -> void:
	_save_volume(MUSIC_VOLUME, volume)


static func _save_volume(key: String, volume: float) -> void:
	var config := ConfigFile.new()
	var load_error := _load(config)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return
	config.set_value(SECTION, key, clampf(volume, 0.0, 1.0))
	print_verbose("Saving %s to %s." % [key, PATH])
	var error := config.save(PATH)
	if error != OK:
		push_warning("Could not save %s to %s: %s" % [key, PATH, error_string(error)])
	else:
		print_verbose("%s saved." % key)


static func _load_visibility(key: String, label: String, default := true) -> bool:
	var config := ConfigFile.new()
	if _load(config) != OK:
		return default
	var stored: Variant = config.get_value(SECTION, key, default)
	if stored is bool:
		return stored
	push_warning("Ignoring an invalid battlefield %s preference." % label)
	return default


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
