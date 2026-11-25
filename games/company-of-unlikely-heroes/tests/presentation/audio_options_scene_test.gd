extends SceneTree
## Run only with matching, fresh OLR_TEST_SANDBOX and XDG_DATA_HOME.
## The Master audio bus is muted for the entire test, independently of settings.

const Rules = preload("res://rules/rules.gd")
const PREFS := "user://battle_display.cfg"
const PROFILE := "user://audio_options_test_guild.json"
var failures: Array[String] = []
var scene: Node
var effects: Node
var music: AudioStreamPlayer
var last_gain := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sandbox := OS.get_environment("OLR_TEST_SANDBOX")
	if sandbox.is_empty() or not sandbox.is_absolute_path() \
			or OS.get_environment("XDG_DATA_HOME") != sandbox \
			or not OS.get_user_data_dir().begins_with(sandbox.trim_suffix("/") + "/") \
			or FileAccess.file_exists(PREFS) or FileAccess.file_exists(PROFILE):
		push_error("Use matching fresh OLR_TEST_SANDBOX and XDG_DATA_HOME directories.")
		quit(1)
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	# A pre-feature preference file must retain its old SFX level.
	var legacy := ConfigFile.new()
	legacy.set_value("battle", "sound_effects_volume", 0.3)
	legacy.set_value("battle", "show_hints", false)
	if not _check(legacy.save(PREFS) == OK, "Seed test-owned legacy preferences"):
		_finish()
		return
	root.size = Vector2i(1280, 820)
	await _launch(PackedStringArray())
	if await _guild_options():
		var controls := _controls()
		if controls.size() == 3:
			_check(is_equal_approx(controls.sfx.value, 0.3), "Legacy SFX value is honored")
			_check(controls.master.value > 0.0 and controls.music.value > 0.0,
				"Missing new preferences do not mute existing players")
			await _keyboard_adjust(controls.master, "Guild master")
			await _keyboard_adjust(controls.music, "Guild music")
			await _keyboard_adjust(controls.sfx, "Guild effects")
			controls.master.value = 0.8
			controls.music.value = 0.6
			controls.sfx.value = 0.4
			await process_frame
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	var service := scene.find_child("BackgroundMusic", true, false)
	effects = scene.find_child("SoundEffects", true, false)
	if not _check(service != null and effects != null and effects.has_signal("sound_requested"),
			"Shared music and effects services exist"):
		_finish()
		return
	effects.connect("sound_requested", _sound_requested)
	for player in service.find_children("*", "AudioStreamPlayer", true, false):
		if player.playing:
			music = player
			break
	if not _check(music != null and music.stream != null, "Music is playing"):
		_finish()
		return
	# Install a long, silent test-owned stream, independent of the shipped tracks.
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 8000
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	var samples := PackedByteArray()
	samples.resize(8000 * 20)
	stream.data = samples
	music.stream = stream
	music.play(5.0)
	await process_frame
	var opening: Dictionary = scene.battle_snapshot().duplicate(true)
	var targets: Array = Rules.new().targets(opening, "knight", "move")
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if _check(not targets.is_empty(), "Battle fixture has a legal move"):
		_check(await driver.command("knight", "move", str(targets[0].id)), "Stage a move")
	var staged: Dictionary = scene.get("_planned_state").duplicate(true)
	if await _battle_options():
		var controls := _controls()
		if controls.size() == 3:
			_check(is_equal_approx(controls.master.value, 0.8) \
				and is_equal_approx(controls.music.value, 0.6) \
				and is_equal_approx(controls.sfx.value, 0.4), "All three levels persist across scenes")
			await _keyboard_adjust(controls.master, "Battle master")
			await _keyboard_adjust(controls.music, "Battle music")
			await _keyboard_adjust(controls.sfx, "Battle effects")
			controls.master.value = 1.0
			controls.music.value = 1.0
			controls.sfx.value = 1.0
			await process_frame
			var music_full := _effective_gain(music)
			var sfx_full := _effect_gain()
			controls.music.value = 0.5
			await process_frame
			_check(_near_ratio(_effective_gain(music), music_full, 0.5), "Music level changes music live")
			_check(_near_ratio(_effect_gain(), sfx_full, 1.0), "Music level does not change effects")
			var live_effect: AudioStreamPlayer = effects.get_child(-1) as AudioStreamPlayer
			controls.sfx.value = 0.5
			_check(is_instance_valid(live_effect) and _near_ratio(_effective_gain(live_effect), sfx_full, 0.5),
				"An already-playing effect keeps its cue trim during live volume changes")
			await process_frame
			_check(_near_ratio(_effect_gain(), sfx_full, 0.5), "Effects level changes effects live")
			_check(_near_ratio(_effective_gain(music), music_full, 0.5), "Effects level does not change music")
			controls.master.value = 0.5
			await process_frame
			_check(_near_ratio(_effect_gain(), sfx_full, 0.25), "Master scales effects")
			_check(_near_ratio(_effective_gain(music), music_full, 0.25), "Master scales music")
			controls.master.value = 0.0
			await process_frame
			_check(_effect_gain() == 0.0 and _effective_gain(music) < 0.0001, "Zero master mutes both")
			_check(is_equal_approx(controls.music.value, 0.5) and is_equal_approx(controls.sfx.value, 0.5),
				"Master mute preserves category levels")
			controls.master.value = 1.0
			controls.music.value = 0.0
			await process_frame
			_check(_effective_gain(music) < 0.0001 and _near_ratio(_effect_gain(), sfx_full, 0.5),
				"Zero music mutes only music")
			controls.music.value = 0.5
			controls.sfx.value = 0.0
			await process_frame
			_check(_effect_gain() == 0.0 and _near_ratio(_effective_gain(music), music_full, 0.5),
				"Zero effects mutes only effects")
			_check(music.playing and music.stream == stream and music.get_playback_position() >= 4.0,
				"Adjusting and muting does not restart or stop the music playhead")
			_check(scene.get("_planned_state") == staged and scene.battle_snapshot() == opening,
				"Options changes preserve the staged command and battle")
			controls.master.value = 0.0
			controls.music.value = 0.7
			controls.sfx.value = 0.2
			await process_frame
	await _launch(PackedStringArray())
	if await _guild_options():
		var controls := _controls()
		if controls.size() == 3:
			_check(is_equal_approx(controls.master.value, 0.0) \
				and is_equal_approx(controls.music.value, 0.7) \
				and is_equal_approx(controls.sfx.value, 0.2),
				"Muted master and independent category values survive reload")
	var config := ConfigFile.new()
	_check(config.load(PREFS) == OK and config.get_value("battle", "show_hints", true) == false,
		"Saving audio preserves unrelated legacy preferences")
	_finish()


func _launch(args: PackedStringArray) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_profile_path(PROFILE)
	scene.configure_launch(args)
	root.add_child(scene)
	await process_frame
	await process_frame


func _guild_options() -> bool:
	for button in scene.find_children("*", "Button", true, false):
		if button is BaseButton and button.text == "Options" and button.is_visible_in_tree():
			button.pressed.emit()
			await process_frame
			return true
	return _check(false, "Guild Options is available")


func _battle_options() -> bool:
	var options := scene.find_child("Options", true, false) as MenuButton
	if not _check(options != null and options.is_visible_in_tree(), "Battle Options is available"):
		return false
	var popup := options.get_popup()
	popup.popup()
	await process_frame
	for i in popup.item_count:
		var label := popup.get_item_text(i).to_lower()
		if "volume" in label or "audio" in label or "sound" in label:
			popup.id_pressed.emit(popup.get_item_id(i))
			await process_frame
			await process_frame
			return true
	return _check(false, "Battle Options offers audio controls")


func _controls() -> Dictionary:
	# Stable accessible names for the three player-facing normalized controls.
	var result := {}
	for pair in [["master", "MasterVolume", "Master volume"],
			["music", "MusicVolume", "Music volume"],
			["sfx", "SoundEffectsVolume", "Sound effects volume"]]:
		var found: Range
		for node in scene.find_children(pair[1], "", true, false):
			if node is Range and node.is_visible_in_tree():
				found = node
				break
		if _check(found != null, "Visible " + pair[0] + " volume control"):
			_check(found.min_value == 0.0 and found.max_value == 1.0 \
				and found.focus_mode == Control.FOCUS_ALL, pair[0] + " is normalized and keyboard focusable")
			_check(found.accessibility_name == pair[2], pair[0] + " has an accessible name")
			result[pair[0]] = found
	return result


func _keyboard_adjust(slider: Range, label: String) -> void:
	slider.value = 0.5
	slider.grab_focus()
	await process_frame
	_check(slider.has_focus(), label + " receives keyboard focus")
	for down in [true, false]:
		var event := InputEventAction.new()
		event.action = "ui_right"
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	_check(slider.value > 0.5, label + " responds to the keyboard")


func _sound_requested(_kind: String, _unit: String, _ability: String, _cue: String, gain: float) -> void:
	last_gain = gain


func _effect_gain() -> float:
	last_gain = 0.0
	effects.call("planning", "knight")
	if last_gain <= 0.0:
		return 0.0
	# Newest player is last; older effects may still be playing.
	var players := effects.find_children("*", "AudioStreamPlayer", true, false)
	if players.is_empty():
		return 0.0
	return _effective_gain(players.back())


func _effective_gain(player: AudioStreamPlayer) -> float:
	var gain := db_to_linear(player.volume_db)
	var index := AudioServer.get_bus_index(player.bus)
	while index >= 0:
		# Ignore the test's output mute on Master, but include category mutes.
		if AudioServer.get_bus_name(index) != "Master" and AudioServer.is_bus_mute(index):
			return 0.0
		gain *= db_to_linear(AudioServer.get_bus_volume_db(index))
		if AudioServer.get_bus_name(index) == "Master":
			break
		index = AudioServer.get_bus_index(AudioServer.get_bus_send(index))
	return gain


func _near_ratio(actual: float, baseline: float, ratio: float) -> bool:
	return baseline > 0.00001 and absf(actual / baseline - ratio) < 0.06


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func _finish() -> void:
	if failures.is_empty():
		print("PASS: audio options")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
