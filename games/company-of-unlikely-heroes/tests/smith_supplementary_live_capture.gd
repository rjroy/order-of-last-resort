extends "res://tests/smith_committed_playback_test.gd"
## Controlled real rules commits fed to the real battle board's playback.
## --preflight is headless; live capture requires the common fresh sandbox.

const Preferences = preload("res://battle_display_preferences.gd")
const Sandbox = preload("res://tests/support/capture_sandbox.gd")
var scene: Node
var service: Node
var recorder := AudioEffectRecord.new()
var output := ""
var sounds: Array[Dictionary] = []
var started := 0
const SAMPLE_FRAMES := {"bonk": 12, "acid": 14, "hit": 5, "down": 16, "recover": 14, "defeat": 16}


func _initialize() -> void:
	call_deferred("_supplementary_run")


func _supplementary_run() -> void:
	_defs = Fixture.add_fixed_escort(Catalog.read_default().duplicate(true))
	_defs.characters.harpooner.behavior = "hold"
	_defs.characters.ferryman.behavior = "hold"
	_defs.characters.skeleton.behavior = "hold"
	_defs.abilities.wizard_blast.params.damage = 4
	_art.load_manifest()
	var examples := _supplementary_cases()
	if "--lifecycle-only" in OS.get_cmdline_user_args():
		examples = examples.filter(func(example): return example.id in ["hit", "down", "recover", "defeat"])
	if "--preflight" in OS.get_cmdline_user_args():
		_check(examples.size() == (4 if "--lifecycle-only" in OS.get_cmdline_user_args() else 7),
			"expected real committed supplementary fixtures")
		_supplementary_finish()
		return
	output = OS.get_environment("SMITH_SUPPLEMENTARY_DIR")
	var err := Sandbox.validate("SMITH_CAPTURE_SANDBOX", output)
	if DisplayServer.get_name().to_lower() != "wayland" or not err.is_empty():
		_check(false, "requires isolated Wayland sandbox: " + err)
		_supplementary_finish()
		return
	if not _failures.is_empty():
		_supplementary_finish()
		return
	Preferences.save_music_volume(0.0)
	_check(Preferences.load_music_volume() == 0.0, "scratch music preference saved")
	AudioServer.add_bus_effect(0, recorder)
	print("DISPLAY=", DisplayServer.get_name(), " DEVICE=", AudioServer.get_output_device(),
		" MIX_RATE=", AudioServer.get_mix_rate())
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	service = scene.find_child("SoundEffects", true, false)
	if not _check(service != null, "sound service available"):
		_supplementary_finish()
		return
	service.sound_requested.connect(_sound)
	print("MIX sfx=", service.volume, " master=", service.master_volume, " music=0")
	for example in examples:
		await _capture(example)
	scene.queue_free()
	await process_frame
	_supplementary_finish()


func _supplementary_cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pair in [["bonk", "healer_bonk"], ["acid", "alchemist_acid"]]:
		var state := _state("knight")
		_entity(state, "wearer").erase("fitted_by")
		_entity(state, "enemy").position = Vector2i(4, 7) if pair[0] == "bonk" else Vector2i(6, 6)
		var kit := Progression.playtest_kit(_defs, "blacksmith", {"offense": pair[1]})
		_check(kit.has("kit"), pair[0] + ": actual borrowed kit")
		if not kit.has("kit"):
			continue
		state["_guild"] = Catalog.FrozenCatalog.new({"kits": {"smith": kit.kit}})
		_add(out, pair[0], _commit(state, "smith", pair[1], "enemy"), "smith", pair[0])
	var state := _state("wizard")
	_entity(state, "enemy").position = Vector2i(4, 7)
	_add(out, "hit", _commit(state, "enemy", "enemy_attack", "smith"), "smith", "hit")
	_entity(state, "smith").hp = 1
	_add(out, "defeat", _commit(state, "enemy", "enemy_attack", "smith"), "smith", "defeat")
	_entity(state, "smith").hp = 20
	_entity(state, "smith").position = Vector2i(6, 5)
	_entity(state, "enemy").position = Vector2i(9, 5)
	_entity(state, "patient").position = Vector2i(2, 2)
	_entity(state, "wearer").erase("fitted_by")
	var fallen := _commit(state, "wearer", "wizard_blast")
	_add(out, "down", fallen, "smith", "down")
	if not fallen.is_empty():
		var plan := _rules.preview_round(fallen.state)
		var result := _rules.commit_round(fallen.state, plan)
		_add(out, "recover", {"state": result, "cues": Cues.build(fallen.state, result, plan.events, true)},
			"smith", "recover")
	state = _state("knight")
	_entity(state, "smith").upgrades = {"smith_quick_release": 1}
	_add(out, "release", _commit(state, "wearer", "smith_quick_release", "6,5"), "wearer", "")
	return out


func _add(out: Array[Dictionary], id: String, committed: Dictionary, actor: String, clip: String) -> void:
	if not _check(not committed.is_empty(), id + ": actual committed rules action"):
		return
	var timeline := _timeline(committed)
	var matching: Array = timeline.get("_entries").filter(func(entry):
		return entry.cue.get("unit_id") == actor and (clip.is_empty() or entry.cue.get("clip") == clip))
	_check(not matching.is_empty(), id + ": actual committed cue is scheduled")
	if not clip.is_empty() and not matching.is_empty():
		_check(matching[0].clip.path == "res://assets/cast/blacksmith.png",
			id + ": installed Smith atlas loaded")
	out.append({"id": id, "state": committed.state, "cues": committed.cues, "actor": actor, "clip": clip})


func _capture(example: Dictionary) -> void:
	scene.set("_actor_id", "")
	scene.call("_show_battle", example.state.duplicate(true))
	await process_frame
	await process_frame
	var board: Control = scene.get("_board")
	board.set_actual_draw_capture_enabled(true)
	var collected := {}
	var frames := {}
	sounds.clear()
	started = Time.get_ticks_msec()
	recorder.set_recording_active(true)
	board.play_committed_actions(example.cues)
	while Time.get_ticks_msec() - started < 15000:
		await RenderingServer.frame_post_draw
		var snapshot: Dictionary = board.actual_draw_snapshot()
		var actor: Dictionary = snapshot.get("actors", {}).get(example.actor, {})
		if example.clip.is_empty():
			var fraction: float = board.get("_playback").movement_fraction(example.actor)
			if not actor.is_empty() and actor.get("atlas", "").contains("knight") \
					and fraction > 0.0 and fraction < 1.0 and not frames.has("wearer"):
				frames["wearer"] = root.get_texture().get_image()
				collected["wearer"] = snapshot
				collected["wearer_motion_fraction"] = fraction
		elif actor.get("clip") == example.clip and actor.get("atlas") == "res://assets/cast/blacksmith.png" \
				and actor.get("source_frame") == SAMPLE_FRAMES.get(example.id) \
				and not frames.has("performer"):
			frames["performer"] = root.get_texture().get_image()
			collected["performer"] = snapshot
		if example.id == "acid" and not frames.has("flask"):
			var props: Array = snapshot.get("props", [])
			if props.any(func(prop): return prop.get("actor_id") == "smith" and prop.get("clip") == "acid_flask"):
				frames["flask"] = root.get_texture().get_image()
				collected["flask"] = snapshot
		if example.id in ["bonk", "acid"] and not frames.has("target"):
			var recipients: Array = snapshot.get("recipients", [])
			if recipients.any(func(mark): return mark.get("id", mark.get("target_id", "")) == "enemy"):
				frames["target"] = root.get_texture().get_image()
				collected["target"] = snapshot
		if not board.action_playback_pending():
			break
	await create_timer(0.4).timeout
	if example.id in ["hit", "down", "recover", "defeat"]:
		board.get("_figures").queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var settled: Dictionary = board.actual_draw_snapshot()
		var held: Dictionary = settled.get("actors", {}).get("smith", {})
		var expected_clip := "down" if example.id == "down" else ("defeat" if example.id == "defeat" else "ready")
		_check(held.get("atlas") == "res://assets/cast/blacksmith.png" and held.get("clip") == expected_clip,
			example.id + ": actual settled Smith uses " + expected_clip + ", got " + str(held))
		if example.id in ["down", "defeat"]:
			var clip = _art.clip_for("blacksmith", expected_clip)
			_check(clip != null and held.get("source_frame") == clip.source_frames.back(),
				example.id + ": actual held terminal source frame")
		frames["settled"] = root.get_texture().get_image()
		collected["settled"] = settled
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	_check(wav != null and wav.save_to_wav(output.path_join(example.id + ".wav")) == OK,
		example.id + ": actual Master mix saved")
	_check(frames.has("wearer" if example.clip.is_empty() else "performer"),
		example.id + ": actual desired actor drawing")
	if example.id == "acid":
		_check(frames.has("flask"), "acid: actual released flask drawn")
	for key in frames:
		_check(frames[key].save_png(output.path_join(example.id + "_" + key + ".png")) == OK,
			example.id + ": viewport frame saved")
	var file := FileAccess.open(output.path_join(example.id + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"draws": collected, "sound_requests": sounds, "cues": example.cues}, "\t"))
	print("CASE ", example.id, " frames=", str(frames.keys()), " sounds=", JSON.stringify(sounds))
	board.set_actual_draw_capture_enabled(false)


func _sound(kind: String, unit: String, ability: String, cue: String, gain: float) -> void:
	sounds.append({"ms": Time.get_ticks_msec() - started, "kind": kind, "unit_id": unit,
		"ability_id": ability, "cue_id": cue, "gain": gain})


func _supplementary_finish() -> void:
	for failure in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print("PASS: supplementary committed fixtures; graphical media still requires inspection")
	quit(0 if _failures.is_empty() else 1)
