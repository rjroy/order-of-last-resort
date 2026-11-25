extends VBoxContainer
## Shared player-facing volume controls; changing a slider reports intent.

signal volume_changed(category: String, value: float)

const Preferences = preload("res://presentation/settings/battle_display_preferences.gd")
var _sliders := {}
var _values := {}


func _ready() -> void:
	for spec in [
		["master", "Master", "MasterVolume", "Master volume"],
		["music", "Music", "MusicVolume", "Music volume"],
		["sfx", "Sound effects", "SoundEffectsVolume", "Sound effects volume"],
	]:
		var heading := Label.new()
		heading.text = spec[1]
		add_child(heading)
		var marker := Label.new()
		marker.text = ">"
		marker.position = Vector2(-19, 0)
		marker.hide()
		heading.add_child(marker)
		var row := HBoxContainer.new()
		add_child(row)
		var slider := HSlider.new()
		slider.name = spec[2]
		slider.accessibility_name = spec[3]
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.focus_mode = Control.FOCUS_ALL
		slider.custom_minimum_size.x = 230
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 52
		row.add_child(value)
		_sliders[spec[0]] = slider
		_values[spec[0]] = value
		slider.focus_entered.connect(marker.show)
		slider.focus_exited.connect(marker.hide)
		slider.value_changed.connect(_changed.bind(spec[0]))
	refresh()


func refresh() -> void:
	var levels := {
		"master": Preferences.load_master_volume(),
		"music": Preferences.load_music_volume(),
		"sfx": Preferences.load_sound_effects_volume(),
	}
	for category in levels:
		_sliders[category].set_value_no_signal(levels[category])
		_values[category].text = "%d%%" % roundi(levels[category] * 100.0)


func focus_master() -> void:
	_sliders["master"].grab_focus()


func _changed(value: float, category: String) -> void:
	_values[category].text = "%d%%" % roundi(value * 100.0)
	volume_changed.emit(category, value)
