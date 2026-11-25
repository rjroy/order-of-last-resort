extends SceneTree
## Run with a fresh XDG_DATA_HOME and SMITH_MIX_DIR set to an existing directory.
## Requires an actual Wayland window and normal audio device. Records this game's
## Master bus only, using real frame processing and the actual battle controls.
## Set SMITH_CAPTURE_SANDBOX and the isolated XDG/TMP directories as documented
## in res://tests/support/capture_sandbox.gd before launching.

const Rules = preload("res://rules.gd")
const Preferences = preload("res://battle_display_preferences.gd")
const Driver = preload("res://tests/support/storybook_driver.gd")
const CaptureSandbox = preload("res://tests/support/capture_sandbox.gd")
var rules := Rules.new()
var scene: Node
var service: Node
var driver
var recorder := AudioEffectRecord.new()
var heard: Array[Dictionary] = []
var failures: Array[String] = []
var capture_start := 0
var output := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	output = OS.get_environment("SMITH_MIX_DIR")
	var sandbox_error := CaptureSandbox.validate("SMITH_CAPTURE_SANDBOX", output)
	if DisplayServer.get_name().to_lower() != "wayland" or not sandbox_error.is_empty():
		push_error("Requires Wayland and a fresh isolated sandbox: " + sandbox_error)
		quit(1)
		return
	print("DISPLAY_DRIVER=", DisplayServer.get_name(), " AUDIO_DEVICE=", AudioServer.get_output_device(),
		" MIX_RATE=", AudioServer.get_mix_rate(), " OUTPUT=", output)
	Preferences.save_music_volume(0.0)
	if Preferences.load_music_volume() != 0.0:
		push_error("Could not mute music in isolated preferences")
		quit(1)
		return
	AudioServer.add_bus_effect(0, recorder)
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	driver = Driver.new(self, scene)
	service = scene.find_child("SoundEffects", true, false)
	if service == null:
		push_error("No real SoundEffects service")
		quit(1)
		return
	service.sound_requested.connect(_record)
	print("MIX_SETTINGS sfx=", service.volume, " master=", service.master_volume, " music=0")
	var state := _fixture()
	await _case(state, "actor", "blacksmith_try_this", "ally", "smith_fit", "fit")
	await _case(_fixture(), "actor", "blacksmith_hammer_time", "foe", "smith_hammer", "hammer")
	var fitting: Dictionary = rules.preview(state, "actor", "blacksmith_try_this", "ally")
	if _check(fitting.get("valid", false), "release setup legal"):
		await _case(rules.apply_plan(state, fitting), "ally", "smith_quick_release", "3,5", "smith_release", "release")
	scene.queue_free()
	await process_frame
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	if failures.is_empty():
		print("PASS: live mixed capture")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _fixture() -> Dictionary:
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.round = 1
	state.outcome = "ongoing"
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	state.units = [_unit("actor", "blacksmith", Vector2i(3, 3)),
		_unit("ally", "knight", Vector2i(3, 4)),
		_unit("foe", "harpooner", Vector2i(4, 3))]
	state.units[0].upgrades = {"smith_quick_release": 1}
	state.party = ["actor", "ally"]
	state.orders = {}
	state.overrides = {}
	return state


func _case(state: Dictionary, actor: String, ability: String, target: String, key: String, name: String) -> void:
	scene.call("_show_battle", state)
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	_start_capture(name + "_preview")
	var staged: bool = await driver.command(actor, ability, target)
	_check(staged, name + ": command controls staged action: " + driver.error)
	var plan: Dictionary = scene.get("_plan")
	_check(plan.get("valid", false) and plan.events.any(func(event):
		return event.get("resolved_action", {}).get("unit_id") == actor \
			and event.get("resolved_action", {}).get("ability_id") == ability),
		name + ": forecast includes action")
	# Recompute the displayed forecast while recording, not merely idle silence.
	scene.call("_refresh")
	await create_timer(1.0).timeout
	_check(heard.is_empty(), name + ": no forecast sound requests")
	_end_capture(name + "_preview")
	var button := scene.find_child("Commit", true, false) as BaseButton
	if not _check(staged and button != null and button.is_visible_in_tree() and not button.disabled,
			name + ": real commit button enabled"):
		return
	_start_capture(name + "_commit")
	button.pressed.emit()
	var board: Control = scene.get("_board")
	var start := Time.get_ticks_msec()
	await process_frame
	while board.action_playback_pending() and Time.get_ticks_msec() - start < 15000:
		await process_frame
	_check(not board.action_playback_pending(), name + ": real-time playback completed")
	await create_timer(0.6).timeout
	_end_capture(name + "_commit")
	var impacts := heard.filter(func(sound): return sound.kind == "impact" \
		and sound.unit_id == actor and sound.ability_id == ability and sound.cue_id == key)
	_check(impacts.size() == 1, name + ": one intended impact")


func _start_capture(label: String) -> void:
	heard.clear()
	capture_start = Time.get_ticks_msec()
	recorder.set_recording_active(true)
	print("CAPTURE_START ", label)


func _end_capture(label: String) -> void:
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	_check(wav != null and wav.save_to_wav(output.path_join(label + ".wav")) == OK,
		label + ": master bus WAV saved")
	print("CAPTURE_END ", label, " elapsed_ms=", Time.get_ticks_msec() - capture_start,
		" requests=", JSON.stringify(heard))


func _record(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	heard.append({"ms": Time.get_ticks_msec() - capture_start, "kind": kind,
		"unit_id": unit_id, "ability_id": ability_id, "cue_id": cue_id, "gain": gain})


func _unit(id: String, character: String, at: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": at,
		"hp": 20, "max_hp": 20, "statuses": {}}


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok
