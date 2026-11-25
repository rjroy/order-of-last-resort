extends SceneTree
## Headless fixture preflight:
##   godot --headless --path games/company-of-unlikely-heroes \
##     --script res://tests/presentation/smith_live_visual_verification.gd -- --preflight
##
## Capture only after publication and an explicit window slot. Use fresh,
## isolated directories as described in tests/support/capture_sandbox.gd.
## Set OLR_VISUAL_SANDBOX to that sandbox and create an empty output directory:
##   godot --path games/company-of-unlikely-heroes \
##     --script res://tests/presentation/smith_live_visual_verification.gd -- \
##     --output-dir=/absolute/sandbox/evidence [--case=ID ...]
## The output is disposable evidence, not a runtime input. Each PNG contains
## unscaled crops of the actual game board; the JSON maps cells to observations.

const Rules = preload("res://rules/rules.gd")
const Driver = preload("res://tests/support/storybook_driver.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const Sprites = preload("res://presentation/cast/cast_sprites.gd")
const Playback = preload("res://presentation/cast/cast_playback.gd")
const Preferences = preload("res://presentation/settings/battle_display_preferences.gd")
const Sandbox = preload("res://tests/support/capture_sandbox.gd")
const AUDIO_CASES := ["knight_push", "rogue_confusing_dodge",
	"borrowed_wizard_rogue_confusing_dodge", "rogue_wasnt_me", "knight_shield_throw"]
const EXPECTED_CLIPS := {
	"borrowed_knight_healer_bonk": "keep_your_head_down",
	"borrowed_healer_wizard_blast": "blast",
	"borrowed_wizard_rogue_confusing_dodge": "clear_jump",
	"borrowed_bard_knight_push": "fitted_pull",
	"borrowed_rogue_alchemist_potion": "bitter_medicine",
	"borrowed_necromancer_inspiring_melody": "melody",
	"borrowed_alchemist_wizard_pull": "send_off",
	"knight_push": "fitted_pull", "knight_aura": "clear_the_floor",
	"healer_bonk": "keep_your_head_down", "healer_heal": "blast",
	"wizard_blast": "blast", "wizard_pull": "send_off",
	"rogue_wasnt_me": "it_was_me", "rogue_confusing_dodge": "clear_jump",
	"knight_rescue_line": "safety_distance", "healer_field_dressing": "bonk",
	"wizard_ring_sparks": "ring_sparks", "rogue_tripwire": "cut_the_wire",
	"knight_shield_throw": "lend_a_shield", "alchemist_acid": "acid",
	"alchemist_potion": "hostile_dose", "alchemist_etching_paste": "etching_paste",
	"alchemist_plain_tonic": "hostile_dose", "alchemist_repeat_batch": "acid",
	"healing_sonnet": "healing_sonnet", "inspiring_melody": "inspiring_melody",
	"bard_take_the_stage": "healing_sonnet", "summon_skeleton": "recall",
	"raise_dead": "hush", "necro_grave_bell": "grave_bell",
	"necromancer_say_hello_to_that_one": "stay_close",
	"variant_blast_self": "mending_blast_self", "variant_blast_fallback": "blast",
	"variant_knight_bonk_shield_away": "keep_your_head_down_unshielded",
	"variant_buffer_self": "potion",
	"variant_counterbatch_damage": "hostile_dose",
}
const MODULES := [
	"res://tests/fixtures/smith_playback_borrowed_cases.gd",
	"res://tests/fixtures/smith_playback_tactical_cases.gd",
	"res://tests/fixtures/smith_playback_alchemy_cases.gd",
	"res://tests/fixtures/smith_playback_performance_summon_cases.gd",
]
const MAX_FRAMES := 2400
const MAX_PANELS := 20
var failures: Array[String] = []
var sounds: Array[Dictionary] = []
var scene: Node
var driver
var rules := Rules.new()
var art := Sprites.new()
var output_dir := ""
var recorder := AudioEffectRecord.new()
var service: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var preflight := false
	var selected: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--preflight":
			preflight = true
		elif arg.begins_with("--case="):
			selected.append(arg.trim_prefix("--case="))
		elif arg.begins_with("--output-dir="):
			output_dir = arg.trim_prefix("--output-dir=")
	var examples: Array[Dictionary] = []
	for path in MODULES:
		if not ResourceLoader.exists(path):
			_check(false, "missing fixture module " + path)
		else:
			examples.append_array(load(path).cases())
	_check(examples.size() == 32, "matrix contains 25 native and seven borrowed cases")
	_add_variants(examples)
	art.load_manifest()
	if not selected.is_empty():
		for id in selected:
			_check(selected.count(id) == 1 and examples.any(func(c: Dictionary): return c.get("id") == id),
				"unknown or repeated case " + id)
		examples = examples.filter(func(c: Dictionary): return c.get("id") in selected)
	var ids: Array = []
	for example in examples:
		_check(not example.id in ids, "duplicate case " + str(example.id))
		ids.append(example.id)
		_preflight_case(example)
	if preflight:
		print("Preflight cases: ", examples.size(), ". No rendered or audible evidence collected.")
		_finish()
		return
	_check(DisplayServer.get_name() != "headless", "capture requires a normal graphical viewport")
	output_dir = output_dir.simplify_path()
	var sandbox_error: String = Sandbox.validate("OLR_VISUAL_SANDBOX", output_dir)
	_check(sandbox_error.is_empty(), sandbox_error)
	if DirAccess.dir_exists_absolute(output_dir):
		var dir := DirAccess.open(output_dir)
		_check(dir.get_files().is_empty() and dir.get_directories().is_empty(), "output directory must be empty")
	if not failures.is_empty():
		_finish()
		return
	Preferences.save_music_volume(0.0)
	_check(Preferences.load_music_volume() == 0.0, "isolated music disabled for game-only recording")
	AudioServer.add_bus_effect(0, recorder)
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	driver = Driver.new(self, scene)
	service = scene.find_child("SoundEffects", true, false)
	if service == null or not service.has_signal("sound_requested"):
		_check(false, "sound request observation unavailable")
	else:
		service.sound_requested.connect(_record_sound)
	var board: Control = scene.get("_board")
	_check(board != null and board.has_method("actual_draw_snapshot") \
		and board.has_method("set_actual_draw_capture_enabled"),
		"actual drawn-figure/ink observation API unavailable; scheduler metadata is not a substitute")
	if failures.is_empty():
		for example in examples:
			await _capture_case(example)
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	_finish()


func _preflight_case(example: Dictionary) -> void:
	var id: String = example.get("id", "")
	var state: Dictionary = example.get("state", {})
	if state.is_empty():
		_check(false, id + ": empty state")
		return
	var original := state.duplicate(true)
	var staged: Dictionary = rules.choose_manual(state, example.actor, example.ability, example.get("target", ""))
	var plan: Dictionary = rules.preview_round(staged)
	_check(state == original and plan.get("valid", false), id + ": pure valid round preview")
	var actions: Array = plan.get("events", []).filter(func(event: Dictionary):
		var action: Dictionary = event.get("resolved_action", {})
		return action.get("unit_id") == example.actor and action.get("ability_id") == example.effective \
			and (example.get("fallback", false) or action.get("source_ability_id") == example.ability))
	_check(actions.size() == 1, id + ": expected performed action")
	var timeline := Playback.new()
	timeline.enqueue(Cues.build(state, plan.get("result", {}), plan.get("events", []), true), art)
	var entries: Array = timeline.get("_entries").filter(func(entry):
		return entry.cue.get("unit_id") == example.actor \
			and entry.cue.get("performance", {}).get("form_id") == example.effective \
			and entry.cue.get("action_beat", false))
	_check(entries.size() == 1, id + ": one scheduled performer clip")
	if entries.size() == 1:
		_check(entries[0].cue.get("clip") == EXPECTED_CLIPS.get(id), id + ": expected performer clip, got " \
			+ str(entries[0].cue.get("clip")))
		_check(entries[0].clip != null and not entries[0].clip.path.is_empty(),
			id + ": scheduled clip has published atlas")
	if example.get("fallback", false):
		_check(plan.get("events", []).any(func(event: Dictionary):
			return event.get("type") == "fitted_fallback" and event.get("unit_id") == example.actor),
			id + ": ordinary fallback recorded")


func _add_variants(examples: Array[Dictionary]) -> void:
	var blast := _copy_case(examples, "wizard_blast", "variant_blast_self")
	if not blast.is_empty():
		var state: Dictionary = blast.state
		for id in state.party:
			var unit := _unit(state, id)
			unit.hp = unit.max_hp
		_unit(state, "wizard").hp -= 2
		examples.append(blast)
	var fallback := _copy_case(examples, "wizard_blast", "variant_blast_fallback")
	if not fallback.is_empty():
		for id in fallback.state.party:
			var unit := _unit(fallback.state, id)
			unit.hp = unit.max_hp
		fallback.effective = "wizard_blast"
		fallback["fallback"] = true
		examples.append(fallback)
	var shield := _copy_case(examples, "borrowed_knight_healer_bonk", "variant_knight_bonk_shield_away")
	if not shield.is_empty():
		_unit(shield.state, "knight")["shield_position"] = Vector2i(3, 4)
		examples.append(shield)
	var dose := _copy_case(examples, "alchemist_acid", "variant_buffer_self")
	if not dose.is_empty():
		dose.target = "alchemist"
		_unit(dose.state, "alchemist").hp -= 1
		examples.append(dose)
	var counter := _copy_case(examples, "alchemist_potion", "variant_counterbatch_damage")
	if not counter.is_empty():
		var state: Dictionary = counter.state
		_unit(state, "alchemist").upgrades = {"alchemist_keep_the_culture": 1}
		var bottled: Dictionary = rules.preview(state, "alchemist", "alchemist_potion", "knight")
		if bottled.get("valid", false):
			counter.state = rules.apply_plan(state, bottled)
			counter.ability = "alchemist_repeat_batch"
			counter.effective = "counterbatch"
			counter.target = "raider_one"
			examples.append(counter)
		else:
			_check(false, "counterbatch damage: could not create real ordinary potion bottle")


func _copy_case(examples: Array[Dictionary], source: String, id: String) -> Dictionary:
	for example in examples:
		if example.id == source:
			var copy := example.duplicate(true)
			copy.id = id
			return copy
	_check(false, "missing base for " + id)
	return {}


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _capture_case(example: Dictionary) -> void:
	var id: String = example.id
	var state: Dictionary = example.state
	scene.set("_opening_state", state.duplicate(true))
	scene.set("_actor_id", "")
	scene.call("_show_battle", state.duplicate(true))
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	sounds.clear()
	var board: Control = scene.get("_board")
	board.set_actual_draw_capture_enabled(true)
	recorder.set_recording_active(true)
	if not await driver.command(example.actor, example.ability, example.get("target", "")):
		recorder.set_recording_active(false)
		_check(false, id + ": controls: " + driver.error)
		return
	await create_timer(0.25).timeout
	recorder.set_recording_active(false)
	var preview_wav := recorder.get_recording()
	var preview_peak := _peak(preview_wav)
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(scene.battle_snapshot() == state and sounds.is_empty() and preview_peak == 0,
		id + ": silent immutable preview (master PCM peak %d)" % preview_peak)
	var panels: Array[Image] = []
	var observations: Array[Dictionary] = []
	await RenderingServer.frame_post_draw
	_record_frame(board, panels, observations, "preview", [])
	var button := scene.find_child("Commit", true, false) as BaseButton
	if button == null or button.disabled:
		_check(false, id + ": commit unavailable")
		return
	if id in AUDIO_CASES:
		recorder.set_recording_active(true)
	button.pressed.emit()
	_check(scene.battle_snapshot() == plan.get("result"), id + ": commit equals forecast")
	var playback = board.get("_playback")
	var frames := 0
	var matched := false
	var last_source_frame := -100
	var saw_prop := false
	while board.committed_visuals_pending() and frames < MAX_FRAMES:
		await RenderingServer.frame_post_draw
		var beats: Array = playback.presentation_beats().duplicate(true)
		var draw: Dictionary = board.actual_draw_snapshot()
		var relevant: Array = beats.filter(func(beat: Dictionary):
			return beat.get("actor_id") == example.actor and beat.get("form_id") == example.effective)
		if not relevant.is_empty():
			for beat in relevant:
				_check_effect_draw(id, beat, draw)
				if beat.get("kind") == "impact":
					matched = true
					var actual_actor: Dictionary = draw.get("actors", {}).get(example.actor, {})
					_check(actual_actor.get("clip") == EXPECTED_CLIPS.get(id) \
						and not str(actual_actor.get("atlas", "")).is_empty() \
						and int(actual_actor.get("source_frame", -1)) >= 0,
						id + ": actual impact draw must use expected published performer clip; got " \
						+ str(actual_actor))
					if id in ["variant_knight_bonk_shield_away", "variant_counterbatch_damage"]:
						_check(actual_actor.get("source_frame") == 13,
							id + ": actual impact draw must show source-frame marker 13")
						var expected_kind := "status" if id == "variant_knight_bonk_shield_away" else "damage"
						_check(beat.get("effects", []).any(func(effect: Dictionary):
							return effect.get("kind") == expected_kind \
								and effect.get("target_id") == example.target),
							id + ": impact must affect the selected recipient")
			_record_frame(board, panels, observations, "marker", relevant)
		var actor: Dictionary = draw.get("actors", {}).get(example.actor, {})
		var source_frame: int = actor.get("source_frame", -1)
		var is_prop: bool = not draw.get("props", []).is_empty()
		if actor.get("clip") == EXPECTED_CLIPS.get(id) and source_frame >= 0 \
				and (last_source_frame < 0 or source_frame - last_source_frame >= 7):
			if panels.size() < MAX_PANELS - 3:
				_record_frame(board, panels, observations, "performer", [])
				last_source_frame = source_frame
		if is_prop and not saw_prop and panels.size() < MAX_PANELS - 2:
			_record_frame(board, panels, observations, "detached prop", [])
			saw_prop = true
		frames += 1
	_check(matched, id + ": real-time playback crossed the intended impact")
	_check(frames < MAX_FRAMES, id + ": playback did not drain")
	if id == "knight_shield_throw":
		_check(saw_prop, id + ": detached shield was actually drawn in flight")
	var audio_result := {}
	if id in AUDIO_CASES:
		await create_timer(0.35).timeout
		recorder.set_recording_active(false)
		var wav := recorder.get_recording()
		audio_result = {"peak": _peak(wav), "mix_rate": wav.mix_rate if wav != null else 0,
			"stereo": wav.stereo if wav != null else false}
		_check(wav != null and wav.save_to_wav(output_dir.path_join(id + ".wav")) == OK,
			id + ": changed-case Master WAV saved")
		_check(audio_result.peak > 0, id + ": changed-case Master WAV is non-silent")
		var wearer: Array = sounds.filter(func(sound: Dictionary):
			return sound.unit_id == example.actor and sound.ability_id == example.ability)
		_check(not wearer.is_empty(), id + ": changed performer emitted actual sound request")
		var expected_sounds := {
			"knight_push": [["impact", "fitted_knight_pull"]],
			"rogue_confusing_dodge": [["takeoff", "fitted_jump_cape"], ["motion_land", "step"]],
			"borrowed_wizard_rogue_confusing_dodge": [["takeoff", "fitted_jump_caster"], ["motion_land", "step"]],
			"rogue_wasnt_me": [["impact", "bonk"], ["claim", "fitted_claim"]],
			"knight_shield_throw": [["impact", "fitted_shield_seat"]],
		}
		for expected in expected_sounds.get(id, []):
			_check(wearer.any(func(sound: Dictionary):
				return sound.kind == expected[0] and sound.cue_id == expected[1]),
				id + ": missing actual changed performer request " + str(expected))
	await RenderingServer.frame_post_draw
	_record_frame(board, panels, observations, "settled", [])
	if panels.is_empty():
		_check(false, id + ": no frames captured")
		return
	var sheet := _contact_sheet(panels)
	_check(sheet.save_png(output_dir.path_join(id + ".png")) == OK, id + ": sheet saved")
	var file := FileAccess.open(output_dir.path_join(id + ".json"), FileAccess.WRITE)
	if file == null:
		_check(false, id + ": observation file could not be opened")
		return
	file.store_string(JSON.stringify({"case": id, "actor": example.actor, "source": example.ability,
		"expected_effective": example.effective, "fallback": example.get("fallback", false),
		"panels": observations, "preview_master_peak": preview_peak,
		"sound_requests_after_preview": sounds, "changed_case_master": audio_result,
		"evidence": "real-time game viewport; draw records require visual inspection"}, "\t"))


func _record_frame(board: Control, panels: Array[Image], observations: Array[Dictionary],
		label: String, beats: Array) -> void:
	if panels.size() >= MAX_PANELS:
		_check(false, "panel limit exceeded")
		return
	var image := root.get_texture().get_image()
	var rect := Rect2i(board.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		_check(false, "board crop is outside viewport")
		return
	var draw: Variant = board.call("actual_draw_snapshot")
	_check(draw is Dictionary and not draw.is_empty(), "renderer returned no actual draw records")
	panels.append(image.get_region(rect))
	observations.append({"index": panels.size() - 1, "label": label, "board_rect": str(rect),
		"markers": beats, "actual_draw": draw})


func _check_effect_draw(id: String, beat: Dictionary, draw: Dictionary) -> void:
	for effect: Dictionary in beat.get("effects", []):
		var kind: String = effect.get("kind", "")
		var moving := kind in ["pull", "push", "move", "recall"]
		if kind not in ["heal", "damage", "status", "taunt", "pull", "push", "move", "recall", "rally"]:
			continue
		var target: String = effect.get("target_id", "")
		var cell: Variant = effect.get("to") if moving else effect.get("cell")
		var recipients: Array = draw.get("recipients", [])
		_check(recipients.any(func(recipient: Dictionary):
			return recipient.get("target_id") == target and recipient.get("cell") == cell),
			id + ": recipient feedback must be painted at the actual effect cell")
		if moving:
			var actor: Dictionary = draw.get("actors", {}).get(target, {})
			_check(actor.get("cell") == cell, id + ": moved recipient must be drawn at landing")


func _contact_sheet(panels: Array[Image]) -> Image:
	var width := 0
	var height := 0
	for image in panels:
		width = maxi(width, image.get_width())
		height = maxi(height, image.get_height())
	var result := Image.create(width * 2, height * ceili(float(panels.size()) / 2.0), false, Image.FORMAT_RGBA8)
	result.fill(Color.BLACK)
	for index in panels.size():
		var image := panels[index]
		result.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()),
			Vector2i((index % 2) * width, (index / 2) * height))
	return result


func _record_sound(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	sounds.append({"kind": kind, "unit_id": unit_id, "ability_id": ability_id, "cue_id": cue_id, "gain": gain})


func _peak(wav: AudioStreamWAV) -> int:
	if wav == null or wav.data.is_empty():
		return -1
	var peak := 0
	for index in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(index)))
	return peak


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: Smith visual verification")
	quit(0 if failures.is_empty() else 1)
