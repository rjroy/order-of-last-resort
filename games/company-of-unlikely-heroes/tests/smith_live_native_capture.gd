extends SceneTree
## Live stock Smith clips on a controlled real battle board. Requires a normal
## Wayland/PulseAudio window, isolated XDG data, and SMITH_NATIVE_CAPTURE_DIR.
## Set SMITH_CAPTURE_SANDBOX and isolated XDG/TMP as documented in
## res://tests/support/capture_sandbox.gd before launching.

const Preferences = preload("res://battle_display_preferences.gd")
const Driver = preload("res://tests/support/storybook_driver.gd")
const CaptureSandbox = preload("res://tests/support/capture_sandbox.gd")
var scene: Node
var driver
var service: Node
var recorder := AudioEffectRecord.new()
var requests: Array[Dictionary] = []
var failures: Array[String] = []
var start_ms := 0
var output := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	output = OS.get_environment("SMITH_NATIVE_CAPTURE_DIR")
	var sandbox_error := CaptureSandbox.validate("SMITH_CAPTURE_SANDBOX", output)
	if DisplayServer.get_name().to_lower() != "wayland" or not sandbox_error.is_empty():
		push_error("Requires Wayland and a fresh isolated sandbox: " + sandbox_error)
		quit(1)
		return
	Preferences.save_music_volume(0.0)
	if not _check(Preferences.load_music_volume() == 0.0, "scratch music preference saved"):
		_finish()
		return
	AudioServer.add_bus_effect(0, recorder)
	print("DISPLAY=", DisplayServer.get_name(), " AUDIO_DEVICE=", AudioServer.get_output_device(),
		" MIX_RATE=", AudioServer.get_mix_rate())
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	driver = Driver.new(self, scene)
	service = scene.find_child("SoundEffects", true, false)
	if not _check(service != null, "real SoundEffects available"):
		_finish()
		return
	service.sound_requested.connect(_record)
	print("MIX sfx=", service.volume, " master=", service.master_volume, " music=0")
	await _case(false)
	await _case(true)
	scene.queue_free()
	await process_frame
	_finish()


func _fixture(pursue: bool) -> Dictionary:
	# Stock character IDs and catalog on the real battle page, with a controlled
	# local formation and HP so the intended action is unambiguous.
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.round = 1
	state.outcome = "ongoing"
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	state.units = [_unit("blacksmith", "blacksmith", Vector2i(3, 3)),
		_unit("knight", "knight", Vector2i(3, 5)),
		_unit("foe", "harpooner", Vector2i(5 if pursue else 4, 3))]
	state.party = ["blacksmith", "knight"]
	state.orders = {"blacksmith": "order_try_this", "knight": "order_hold"}
	state.overrides = {}
	return state


func _case(pursue: bool) -> void:
	var label := "pursue" if pursue else "hammer"
	var state := _fixture(pursue)
	scene.set("_actor_id", "")
	scene.call("_show_battle", state)
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	_begin()
	var staged: bool
	if pursue:
		staged = await driver.order("blacksmith", "order_pursue")
	else:
		staged = await driver.command("blacksmith", "blacksmith_hammer_time", "foe")
	scene.call("_refresh")
	await create_timer(1.0).timeout
	var preview := _end(label + "_preview.wav")
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(staged and plan.get("valid", false), label + ": real controls staged legal round: " + driver.error)
	var expected := state.duplicate(true)
	if pursue:
		# Standing-order changes are immediately saved, unlike direct commands.
		expected.orders.blacksmith = "order_pursue"
	_check(requests.is_empty() and preview.get("peak", -1) == 0 and scene.battle_snapshot() == expected,
		label + ": forecast stays silent and board changes only the selected standing order")
	var result: Dictionary = plan.get("result", {})
	if pursue:
		_check(_get_unit(result, "blacksmith").get("position") == Vector2i(4, 3),
			"Pursue forecast moves Smith one tile toward target")
		var moves: Array = plan.get("events", []).filter(func(event: Dictionary):
			return event.get("type") == "move" and event.get("unit_id") == "blacksmith")
		_check(moves.size() == 1, "Pursue resolves one Smith movement event: " + str(moves))
	else:
		_check(_get_unit(result, "foe").get("hp") == 18 \
			and _get_unit(result, "foe").get("position") == Vector2i(4, 3),
			"Hammer deals two damage without shoving target")
	var button := scene.find_child("Commit", true, false) as BaseButton
	if not _check(staged and button != null and button.is_visible_in_tree() and not button.disabled,
			label + ": Commit available"):
		return
	_begin()
	button.pressed.emit()
	_check(scene.battle_snapshot() == result, label + ": commit matches forecast")
	var board: Control = scene.get("_board")
	var playback = board.get("_playback")
	var wanted := [13, 28] if pursue else [12, 17]
	var images := {}
	var samples := {}
	var motion_ids := {}
	var beats: Array = []
	while Time.get_ticks_msec() - start_ms < 15000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_msec() - start_ms
		for beat in playback.presentation_beats():
			beats.append(beat.merged({"observed_ms": now}))
		for motion: Dictionary in playback.get("_motions"):
			if motion.get("unit_id") == "blacksmith":
				motion_ids[str(motion.get("order"))] = {"from": str(motion.from), "to": str(motion.to)}
		for entry in playback.active():
			if entry.cue.get("unit_id") != "blacksmith" or entry.cue.get("cast_key") != "blacksmith" \
					or entry.cue.get("clip") != ("pursue" if pursue else "hammer_time") \
					or entry.clip.path != "res://assets/cast/blacksmith.png" or entry.elapsed_ms >= entry.clip.total_ms:
				continue
			var source_frame: int = entry.clip.source_frames[entry.clip.frame_index(entry.elapsed_ms)]
			if source_frame in wanted and not images.has(source_frame):
				images[source_frame] = root.get_texture().get_image()
				samples[source_frame] = {"observed_ms": now, "clip_elapsed_ms": entry.elapsed_ms,
					"clip_path": entry.clip.path, "clip": entry.cue.clip,
					"movement_fraction": playback.movement_fraction("blacksmith")}
		if not board.action_playback_pending() and now > 500:
			break
	_check(not board.action_playback_pending(), label + ": real-time playback completed")
	await create_timer(0.4).timeout
	var commit := _end(label + "_commit.wav")
	for frame in wanted:
		_check(images.has(frame), label + ": captured source frame " + str(frame))
		if images.has(frame):
			_check(images[frame].save_png(output.path_join("%s_f%d.png" % [label, frame])) == OK,
				label + ": viewport frame saved")
	if pursue:
		_check(motion_ids.size() == 1, "Pursue playback has exactly one Smith displacement: " + str(motion_ids))
		_check(requests.filter(func(item): return item.unit_id == "blacksmith" and item.kind == "step").size() == 2,
			"Pursue produces two Smith footfall cues")
	else:
		_check(requests.filter(func(item): return item.unit_id == "blacksmith" \
			and item.ability_id == "blacksmith_hammer_time" and item.cue_id == "smith_hammer").size() == 1,
			"Hammer produces one Smith impact cue")
	var evidence := {"fixture": "stock character IDs and catalog, controlled positions and HP",
		"label": label, "preview": preview, "commit": commit, "events": plan.get("events", []),
		"frame_samples": samples, "smith_motions": motion_ids, "presentation_beats": beats,
		"sound_requests": requests}
	var file := FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE)
	if _check(file != null, label + ": metadata created"):
		file.store_string(JSON.stringify(evidence, "\t"))
	print("CASE ", label, " preview=", JSON.stringify(preview), " commit=", JSON.stringify(commit),
		" frames=", JSON.stringify(samples), " smith_motions=", JSON.stringify(motion_ids),
		" requests=", JSON.stringify(requests))


func _begin() -> void:
	requests.clear()
	start_ms = Time.get_ticks_msec()
	recorder.set_recording_active(true)


func _end(name: String) -> Dictionary:
	recorder.set_recording_active(false)
	var elapsed := Time.get_ticks_msec() - start_ms
	var wav := recorder.get_recording()
	if not _check(wav != null and wav.save_to_wav(output.path_join(name)) == OK, name + ": saved"):
		return {"peak": -1}
	var peak := 0
	for i in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	return {"elapsed_ms": elapsed, "peak": peak, "bytes": wav.data.size(), "rate": wav.mix_rate}


func _record(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	requests.append({"ms": Time.get_ticks_msec() - start_ms, "kind": kind,
		"unit_id": unit_id, "ability_id": ability_id, "cue_id": cue_id, "gain": gain})


func _unit(id: String, character: String, at: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": at, "hp": 20, "max_hp": 20, "statuses": {}}


func _get_unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok


func _finish() -> void:
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: stock Smith live native capture; media requires inspection")
	quit(0 if failures.is_empty() else 1)
