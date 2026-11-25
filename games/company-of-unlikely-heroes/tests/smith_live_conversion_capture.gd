extends SceneTree
## Real-time, game-only conversion evidence. Supply --case=ID (repeatable),
## or explicitly --all, and SMITH_CAPTURE_ROOT in a fresh isolated sandbox.
## The fixture contract is shared with smith_playback_scene_test.gd.
## Beat metadata and audio requests are timestamps, not perceptual approval.
## Set SMITH_CAPTURE_SANDBOX and isolated XDG/TMP as documented in
## res://tests/support/capture_sandbox.gd before launching.

const Driver = preload("res://tests/support/storybook_driver.gd")
const Preferences = preload("res://battle_display_preferences.gd")
const CaptureSandbox = preload("res://tests/support/capture_sandbox.gd")
const MODULES := [
	"res://tests/smith_playback_borrowed_cases.gd",
	"res://tests/smith_playback_tactical_cases.gd",
	"res://tests/smith_playback_alchemy_cases.gd",
	"res://tests/smith_playback_performance_summon_cases.gd",
]
const MAX_SECONDS := 20.0
var scene: Node
var driver
var service: Node
var recorder := AudioEffectRecord.new()
var stem_recorder := AudioEffectRecord.new()
var failures: Array[String] = []
var requests: Array[Dictionary] = []
var started := 0
var output := ""
var capture_phase := ""
var selected_actor := ""
var selected_ability := ""
var selected_effective := ""
var stem_bus := "SmithEvidenceWearer"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var requested: Array[String] = []
	var excluded: Array[String] = []
	var expected_count := -1
	var all := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			requested.append(arg.trim_prefix("--case="))
		elif arg == "--all":
			all = true
		elif arg.begins_with("--exclude="):
			excluded.append(arg.trim_prefix("--exclude="))
		elif arg.begins_with("--expected-count="):
			expected_count = int(arg.trim_prefix("--expected-count="))
	output = OS.get_environment("SMITH_CAPTURE_ROOT")
	var data := OS.get_environment("XDG_DATA_HOME")
	var sandbox_error := CaptureSandbox.validate("SMITH_CAPTURE_SANDBOX", output)
	if DisplayServer.get_name().to_lower() != "wayland" or not sandbox_error.is_empty() \
			or (requested.is_empty() and not all) or (all and not requested.is_empty()):
		push_error("Requires Wayland, fresh isolated sandbox and --case=ID or --all: " + sandbox_error)
		quit(1)
		return
	var examples: Array[Dictionary] = []
	for path in MODULES:
		if not ResourceLoader.exists(path):
			_check(false, "missing fixture module: " + path)
		else:
			examples.append_array(load(path).cases())
	var ids: Array = examples.map(func(example: Dictionary): return example.get("id", ""))
	for id in ids:
		_check(not id.is_empty() and ids.count(id) == 1, "fixture IDs must be unique: " + str(id))
	for id in requested:
		_check(ids.count(id) == 1 and requested.count(id) == 1, "unknown or repeated case: " + id)
	for id in excluded:
		_check(ids.count(id) == 1 and excluded.count(id) == 1, "unknown or repeated exclusion: " + id)
	if not all:
		examples = examples.filter(func(example: Dictionary): return example.get("id") in requested)
	examples = examples.filter(func(example: Dictionary): return example.get("id") not in excluded)
	if expected_count >= 0:
		_check(examples.size() == expected_count, "expected %d selected cases; found %d" % [expected_count, examples.size()])
	if not failures.is_empty():
		_finish()
		return
	Preferences.save_music_volume(0.0)
	if not _check(Preferences.load_music_volume() == 0.0, "isolated music preference saved"):
		_finish()
		return
	AudioServer.add_bus_effect(0, recorder)
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, stem_bus)
	AudioServer.set_bus_send(bus, "Master")
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioServer.add_bus_effect(bus, stem_recorder)
	print("STEM bus=", stem_bus, " send=Master gain_db=", AudioServer.get_bus_volume_db(bus))
	print("DISPLAY=", DisplayServer.get_name(), " AUDIO_DEVICE=", AudioServer.get_output_device(),
		" MIX_RATE=", AudioServer.get_mix_rate(), " XDG_DATA_HOME=", data)
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	driver = Driver.new(self, scene)
	service = scene.find_child("SoundEffects", true, false)
	if not _check(service != null and service.has_signal("sound_requested"), "sound service available"):
		_finish()
		return
	service.sound_requested.connect(_record)
	print("MIX sfx=", service.volume, " master=", service.master_volume, " music=0")
	for example in examples:
		await _capture_case(example)
	scene.queue_free()
	await process_frame
	_finish()


func _capture_case(example: Dictionary) -> void:
	var id: String = example.id
	var dir := output.path_join(id)
	if not _check(id.is_valid_filename() and not DirAccess.dir_exists_absolute(dir)
			and DirAccess.make_dir_absolute(dir) == OK, id + ": new output directory"):
		return
	var state: Dictionary = example.get("state", {})
	if not _check(not state.is_empty(), id + ": fixture state exists"):
		return
	scene.set("_opening_state", state.duplicate(true))
	scene.set("_actor_id", "")
	scene.call("_show_battle", state.duplicate(true))
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	_begin()
	var actor: String = example.actor
	var ability: String = example.ability
	selected_actor = actor
	selected_ability = ability
	selected_effective = example.effective
	var target: String = example.get("target", "")
	var staged: bool = await driver.select_actor(actor) and await driver.action(ability)
	if staged and not target.is_empty():
		staged = await driver.target(target)
	scene.call("_refresh")
	await create_timer(1.0).timeout
	var preview := _end(dir.path_join("preview.wav"), dir.path_join("preview_stem.wav"))
	var preview_requests := requests.duplicate(true)
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	var effective: String = example.effective
	var converted: Array = plan.get("events", []).filter(func(event: Dictionary):
		var action: Dictionary = event.get("resolved_action", {})
		return action.get("unit_id") == actor and action.get("ability_id") == effective \
			and action.get("source_ability_id") == ability)
	_check(staged and plan.get("valid", false) and converted.size() == 1,
		id + ": controls staged intended converted action: " + driver.error)
	_check(plan.get("events", []).any(func(event: Dictionary):
		return event.get("type") == "fitted_conversion" and event.get("unit_id") == actor \
			and event.get("ability_id") == effective and event.get("source_ability_id") == ability),
		id + ": actual fitting conversion forecast")
	_check(scene.battle_snapshot() == state and preview_requests.is_empty() and preview.get("peak", -1) == 0,
		id + ": preview unchanged and digitally silent")
	var button := scene.find_child("Commit", true, false) as BaseButton
	if not _check(staged and button != null and not button.disabled and button.is_visible_in_tree(),
			id + ": Commit available"):
		return
	await RenderingServer.frame_post_draw
	var previous := root.get_texture().get_image()
	var previous_ms := -1
	_begin()
	capture_phase = "commit"
	button.pressed.emit()
	_check(scene.battle_snapshot() == plan.get("result"), id + ": commit matches forecast")
	var board: Control = scene.get("_board")
	var playback = board.get("_playback")
	var beats: Array[Dictionary] = []
	var impact_at := -1
	var post_saved := false
	var frame_before_ms := -1
	var frame_at_ms := -1
	var frame_after_ms := -1
	var frame_before: Image
	var frame_at: Image
	var frame_after: Image
	while Time.get_ticks_msec() - started < int(MAX_SECONDS * 1000):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_msec() - started
		for beat: Dictionary in playback.presentation_beats():
			var observed := beat.duplicate(true)
			observed["observed_ms"] = now
			beats.append(observed)
			if impact_at < 0 and beat.get("kind") == "impact" and beat.get("actor_id") == actor \
					and beat.get("form_id") == effective and beat.get("source_ability_id") == ability \
					and beat.get("branch") == "converted":
				impact_at = now
				frame_before_ms = previous_ms
				frame_before = previous
				frame_at = root.get_texture().get_image()
				frame_at_ms = now
		if impact_at >= 0 and not post_saved and now >= impact_at + 180:
			frame_after = root.get_texture().get_image()
			post_saved = true
			frame_after_ms = now
		if impact_at < 0:
			previous = root.get_texture().get_image()
			previous_ms = now
		if not board.action_playback_pending() and (impact_at < 0 or post_saved) and now > 500:
			break
	_check(not board.action_playback_pending(), id + ": live playback drained")
	await create_timer(0.4).timeout
	var commit := _end(dir.path_join("commit.wav"), dir.path_join("wearer_stem.wav"))
	# PNG encoding is deliberately outside the live playback and audio capture.
	if impact_at >= 0:
		_check(frame_before != null and frame_before.save_png(dir.path_join("before.png")) == OK,
			id + ": before frame saved")
		_check(frame_at != null and frame_at.save_png(dir.path_join("impact.png")) == OK,
			id + ": impact frame saved")
		_check(frame_after != null and frame_after.save_png(dir.path_join("after.png")) == OK,
			id + ": after frame saved")
	var actor_requests := requests.filter(func(sound: Dictionary): return sound.get("routed_to_stem", false))
	var other_requests := requests.filter(func(sound: Dictionary):
		return not sound.get("routed_to_stem", false))
	var stem: Dictionary = commit.get("stem", {})
	var stem_status := "no_matching_request" if actor_requests.is_empty() else \
		("captured_nonzero" if stem.get("peak", 0) > 0 and stem.get("rms", 0.0) > 0.0 else "matching_request_but_silent_stem")
	_check(stem_status != "matching_request_but_silent_stem", id + ": routed sound reaches stem")
	if effective == "clear_jump":
		_check(actor_requests.any(func(sound): return sound.kind == "motion_land" and sound.cue_id == "step"),
			id + ": actual Clear Jump landing step is captured")
	var metadata := {"id": id, "actor": actor, "source": ability, "effective": effective,
		"target": target, "preview": preview, "preview_requests": preview_requests,
		"commit": commit, "requests": requests, "presentation_beats": beats,
		"wearer_action_requests": actor_requests, "other_requests": other_requests, "stem_status": stem_status,
		"converted_impact_observed_ms": impact_at,
		"frame_before_ms": frame_before_ms, "frame_impact_ms": frame_at_ms,
		"frame_after_ms": frame_after_ms}
	var file := FileAccess.open(dir.path_join("evidence.json"), FileAccess.WRITE)
	if _check(file != null, id + ": metadata opened"):
		file.store_string(JSON.stringify(metadata, "\t"))
	print("CASE ", id, " converted_impact_ms=", impact_at, " preview=", JSON.stringify(preview),
		" commit=", JSON.stringify(commit), " stem_status=", stem_status, " wearer_action_requests=", JSON.stringify(actor_requests),
		" other_requests=", JSON.stringify(other_requests))
	if impact_at < 0:
		print("MISSING_CONVERTED_PRESENTATION ", id, ": other actors' cues are not conversion evidence")
	if actor_requests.is_empty():
		print("NO_ACTOR_IMPACT_SOUND_REQUEST ", id, ": nonzero round audio is not converted cue evidence")


func _begin() -> void:
	requests.clear()
	started = Time.get_ticks_msec()
	capture_phase = "preview"
	recorder.set_recording_active(true)
	stem_recorder.set_recording_active(true)


func _end(path: String, stem_path: String) -> Dictionary:
	recorder.set_recording_active(false)
	stem_recorder.set_recording_active(false)
	capture_phase = ""
	var duration := Time.get_ticks_msec() - started
	var wav := recorder.get_recording()
	var stem := stem_recorder.get_recording()
	var master_stats := _save_wav(wav, path)
	master_stats["elapsed_ms"] = duration
	master_stats["stem"] = _save_wav(stem, stem_path)
	return master_stats


func _save_wav(wav: AudioStreamWAV, path: String) -> Dictionary:
	if not _check(wav != null and wav.save_to_wav(path) == OK, path + ": saved"):
		return {"peak": -1, "rms": -1.0}
	var peak := 0
	var sum_squares := 0.0
	for i in range(0, wav.data.size(), 2):
		var value := wav.data.decode_s16(i)
		peak = maxi(peak, absi(value))
		sum_squares += float(value) * value
	return {"samples_bytes": wav.data.size(), "sample_rate": wav.mix_rate,
		"stereo": wav.stereo, "peak": peak,
		"rms": sqrt(sum_squares / maxi(1, wav.data.size() / 2))}


func _record(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	var match_action := capture_phase == "commit" and unit_id == selected_actor \
		and ability_id in [selected_ability, selected_effective] \
		and kind in ["impact", "takeoff", "claim", "motion_land"]
	var player := service.get_child(service.get_child_count() - 1) as AudioStreamPlayer
	var routed := false
	if match_action:
		if _check(player != null and player.playing, "matching sound has its live service player"):
			player.bus = stem_bus
			routed = player.bus == stem_bus
			_check(routed, "matching player assigned to wearer bus")
	requests.append({"ms": Time.get_ticks_msec() - started, "kind": kind,
		"unit_id": unit_id, "ability_id": ability_id, "cue_id": cue_id, "gain": gain,
		"routed_to_stem": routed})


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok


func _finish() -> void:
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: live conversion evidence captured; media requires review")
	quit(0 if failures.is_empty() else 1)
