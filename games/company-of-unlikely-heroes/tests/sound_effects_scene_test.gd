extends SceneTree
## With a fresh isolated XDG_DATA_HOME:
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/sound_effects_scene_test.gd
## Observe the real sound service at dispatch, not forecast or cue construction.

const Rules = preload("res://rules.gd")
const Cues = preload("res://presentation/cast_cues.gd")
var failures: Array[String] = []
var sounds: Array[Dictionary] = []
var scene: Node
var service: Node
var clock_ms := 0.0
var saw_player := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	service = scene.find_child("SoundEffects", true, false)
	if not _check(service != null and service.has_signal("sound_requested"),
			"Game exposes the shared sound service's real dispatch signal"):
		_finish()
		return
	service.connect("sound_requested", _on_sound)
	var options := scene.find_child("Options", true, false) as MenuButton
	var volume := scene.find_child("SoundEffectsVolume", true, false) as Range
	if not _check(options != null and volume != null and volume.min_value == 0.0 and volume.max_value == 1.0,
			"Options exposes one normalized Sound effects volume control"):
		_finish()
		return
	await _open_volume(options, volume)
	options.get_popup().hide()
	volume.value = 0.5
	await _close_volume(volume)
	await process_frame
	sounds.clear()
	var opening: Dictionary = scene.battle_snapshot().duplicate(true)
	var targets: Array = Rules.new().targets(opening, "knight", "move")
	if not _check(not targets.is_empty(), "Opening Knight has a legal board move"):
		_finish()
		return
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not _check(await driver.command("knight", "move", str(targets[0].id)),
			"Real player input stages a Knight move: " + driver.error):
		_finish()
		return
	var pencil := _matching("planning", "knight", "move")
	_check(pencil.size() == 1 and _matching("impact").is_empty() and _matching("step").is_empty(),
		"Staging a move dispatches one pencil sound, not combat or step sounds")
	if pencil.size() == 1:
		_check(pencil[0].cue_id == "pencil", "The planning sound is the pencil cue")
	var pencil_gain := float(pencil[0].gain) if pencil.size() == 1 else 0.0
	var staged_count := sounds.size()
	var staged: Dictionary = scene.get("_planned_state").duplicate(true)
	await _open_volume(options, volume)
	await _close_volume(volume)
	_check(scene.get("_planned_state") == staged, "Opening and closing volume preserves the staged command")
	scene.call("_refresh")
	scene.call("_refresh")
	_check(sounds.size() == staged_count and scene.battle_snapshot() == opening,
		"Forecast rebuilds do not dispatch sounds or commit a round")
	var plan: Dictionary = scene.get("_plan")
	var expected_steps := _move_count(plan.events, "knight")
	_check(expected_steps == 1, "The real opening forecast contains one Knight step")
	var board: Control = scene.get("_board")
	board.set_process(false)
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if not _check(commit != null and not commit.disabled, "Planned move can commit"):
		_finish()
		return
	commit.pressed.emit()
	board.set_process(false)
	_drain(board)
	_check(_matching("step", "knight", "move").size() == expected_steps,
		"One committed Knight step dispatches exactly one step sound")
	_check(saw_player, "A dispatched sound is wired to a playing AudioStreamPlayer with a stream")
	_guard_then_retreat_sound_order()
	await _push_retreat_and_rapid_commit(pencil_gain)
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	volume = scene.find_child("SoundEffectsVolume", true, false) as Range
	if _check(volume != null and is_equal_approx(volume.value, 0.5),
			"Sound effects volume persists across a fresh game scene"):
		var second_service := scene.find_child("SoundEffects", true, false)
		if _check(second_service != null and second_service.has_signal("sound_requested"),
				"Relaunched game has the shared sound service"):
			second_service.connect("sound_requested", _on_sound)
			volume.value = 0.0
			sounds.clear()
			var second_driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
			var state: Dictionary = scene.battle_snapshot()
			var second_targets: Array = Rules.new().targets(state, "knight", "move")
			if _check(not second_targets.is_empty(), "Muted launch has a legal Knight move"):
				_check(await second_driver.command("knight", "move", str(second_targets[0].id)),
					"Muted player can still stage a move")
				var muted_board: Control = scene.get("_board")
				muted_board.set_process(false)
				var muted_commit := scene.find_child("Commit", true, false) as BaseButton
				if _check(muted_commit != null and not muted_commit.disabled, "Muted round can commit"):
					muted_commit.pressed.emit()
					muted_board.set_process(false)
					service = second_service
					_drain(muted_board)
				_check(sounds.is_empty(), "Zero volume dispatches no planning or committed sounds")
	_finish()


func _guard_then_retreat_sound_order() -> void:
	var rules := Rules.new()
	for large_advance in [false, true]:
		var state: Dictionary = scene.battle_snapshot().duplicate(true)
		state.width = 12
		state.height = 12
		state.default_tile = "stone"
		state.terrain = []
		state.obstacles = []
		state.round = 1
		state.outcome = "ongoing"
		state.objective = {"handler": "survive", "turns": 99, "reserves": []}
		state.units = [_unit("knight", "knight", Vector2i(1, 1)),
			_unit("rogue", "rogue", Vector2i(4, 4)),
			_unit("enemy", "harpooner", Vector2i(6, 4))]
		state.units[1]["upgrades"] = {"rogue_exit_strategy": 1}
		state.party = ["knight", "rogue"]
		state.orders = {}
		state.overrides = {}
		state = rules.set_order(state, "rogue", "order_retreat")
		scene.call("_show_battle", state)
		scene.set("_planned_state", rules.choose_manual(state, "knight", "knight_aura"))
		scene.call("_refresh")
		var plan: Dictionary = scene.get("_plan")
		var guard_index: int = plan.events.find_custom(func(event):
			return event.get("resolved_action", {}).get("unit_id") == "knight" \
				and event.get("resolved_action", {}).get("ability_id") == "knight_aura")
		var steps: Array = plan.events.filter(func(event):
			return event.get("type") == "move" and event.get("unit_id") == "rogue")
		if not _check(plan.get("valid", false) and guard_index >= 0 and steps.size() == 2 \
				and plan.events.find(steps[0]) > guard_index and plan.events.find(steps[1]) > plan.events.find(steps[0]),
				"Real Guard resolves before both Exit Strategy steps"):
			continue
		var board: Control = scene.get("_board")
		board.set_process(false)
		sounds.clear()
		var commit := scene.find_child("Commit", true, false) as BaseButton
		if not _check(commit != null and not commit.disabled, "Guard and retreat round can commit"):
			continue
		commit.pressed.emit()
		board.set_process(false)
		if large_advance:
			clock_ms += 10000.0
			board.call("_process", 10.0)
			board.set_process(false)
			_check(not board.action_playback_pending(), "Large advance drains the Guard and retreat playback")
		else:
			_drain(board)
		var sequence := sounds.filter(func(sound): return \
			(sound.kind == "impact" and sound.unit_id == "knight" and sound.ability_id == "knight_aura") \
			or (sound.kind == "step" and sound.unit_id == "rogue" and sound.ability_id == "move"))
		_check(sequence.size() == 3 and sequence[0].kind == "impact" \
			and sequence[1].kind == "step" and sequence[2].kind == "step",
			"Guard impact precedes both distinct step landings (%s advance)" \
				% ("large" if large_advance else "small"))
		var count := sounds.size()
		board.call("_process", 10.0)
		board.set_process(false)
		_check(sounds.size() == count, "Advancing an already drained timeline does not repeat sounds")


func _push_retreat_and_rapid_commit(pencil_gain: float) -> void:
	var rules := Rules.new()
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.round = 1
	state.outcome = "ongoing"
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	state.units = [_unit("knight", "knight", Vector2i(2, 4)),
		_unit("rogue", "rogue", Vector2i(3, 4)),
		_unit("enemy", "harpooner", Vector2i(6, 4))]
	state.units[1]["upgrades"] = {"rogue_exit_strategy": 1}
	state.party = ["knight", "rogue"]
	state.orders = {}
	state.overrides = {}
	state = rules.set_order(state, "rogue", "order_retreat")
	scene.call("_show_battle", state)
	scene.set("_planned_state", rules.choose_manual(state, "knight", "knight_push", "rogue"))
	scene.call("_refresh")
	var first: Dictionary = scene.get("_plan").duplicate(true)
	var steps := _move_count(first.events, "rogue")
	var cast_cues: Array = Cues.build(state, first.result, first.events)
	_check(first.get("valid", false) and steps == 2,
		"Committed fixture resolves a real Push followed by both Exit Strategy steps")
	_check(not cast_cues.any(func(cue): return cue.get("unit_id") == "knight" \
		and not str(cue.get("clip", "")).is_empty()),
		"Knight Push is supported even without actor-owned action artwork")
	var board: Control = scene.get("_board")
	board.set_process(false)
	sounds.clear()
	scene.call("_refresh")
	_check(sounds.is_empty(), "Push and retreat forecast itself remains silent")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if not _check(commit != null and not commit.disabled, "Push round can commit"):
		return
	commit.pressed.emit()
	board.set_process(false)
	var entries: Array = board.get("_playback").get("_entries")
	var pushes := entries.filter(func(entry): return entry.cue.get("unit_id") == "knight" \
		and entry.cue.get("action_beat", false))
	if not _check(pushes.size() == 1, "Clipless Push is present on the committed timeline"):
		return
	var push_entry = pushes[0]
	# Commit again immediately, before advancing the first visual/audio timeline.
	var second: Dictionary = scene.get("_plan").duplicate(true)
	if not _check(second.get("valid", false) and not commit.disabled, "Second round can commit during playback"):
		return
	var expected_steps := steps + _move_count(second.events, "rogue")
	commit.pressed.emit()
	board.set_process(false)
	var before_impact: float = maxf(0.0, push_entry.impact_ms - push_entry.elapsed_ms - 1.0)
	clock_ms += before_impact
	board.call("_process", before_impact / 1000.0)
	board.set_process(false)
	_check(_matching("impact", "knight", "knight_push").is_empty() \
		and _matching("step", "rogue", "move").is_empty(),
		"Clipless Push and later retreat are quiet before the Push impact")
	clock_ms += 2.0
	board.call("_process", 0.002)
	board.set_process(false)
	_check(_matching("impact", "knight", "knight_push").size() == 1,
		"Clipless Push dispatches sound at its committed impact")
	_drain(board)
	var push_sounds := _matching("impact", "knight", "knight_push")
	var footsteps := _matching("step", "rogue", "move")
	_check(push_sounds.size() == 1, "Clipless Knight Push dispatches its impact exactly once")
	_check(footsteps.size() == expected_steps,
		"Rapid batches dispatch one step per resolved voluntary step, with no forced-move footstep or duplicates")
	if push_sounds.size() == 1 and footsteps.size() >= 2:
		_check(float(footsteps[0].at) > float(push_sounds[0].at) \
			and float(footsteps[1].at) > float(footsteps[0].at),
			"Push impact precedes the Rogue's separately audible steps")
		_check(pencil_gain > 0.0 and pencil_gain < float(push_sounds[0].gain),
			"Planning pencil is softer than a combat impact at the same effects volume")


func _drain(board: Control) -> void:
	var elapsed := 0.0
	while board.action_playback_pending() and elapsed < 30000.0:
		clock_ms += 10.0
		elapsed += 10.0
		board.call("_process", 0.01)
		board.set_process(false)
		for player in [service] + service.find_children("*", "", true, false):
			if (player is AudioStreamPlayer or player is AudioStreamPlayer2D or player is AudioStreamPlayer3D) \
					and player.stream != null and player.playing:
				saw_player = true
	_check(not board.action_playback_pending(), "Committed sound timeline drains")


func _on_sound(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	_check(not cue_id.is_empty() and gain > 0.0 and gain <= 1.0,
		"Actual sound dispatch identifies a cue and a positive linear gain")
	sounds.append({"kind": kind, "unit_id": unit_id, "ability_id": ability_id,
		"cue_id": cue_id, "gain": gain, "at": clock_ms})


func _matching(kind: String, unit_id := "", ability_id := "") -> Array:
	return sounds.filter(func(sound): return sound.kind == kind \
		and (unit_id.is_empty() or sound.unit_id == unit_id) \
		and (ability_id.is_empty() or sound.ability_id == ability_id))


func _move_count(events: Array, id: String) -> int:
	return events.filter(func(event): return event.get("type") == "move" and event.get("unit_id") == id).size()


func _open_volume(options: MenuButton, volume: Range) -> void:
	var popup := options.get_popup()
	popup.popup()
	await process_frame
	var index := -1
	for item in popup.item_count:
		if popup.get_item_text(item) == "Volume…":
			index = item
	if not _check(index >= 0, "Options offers Volume"):
		return
	popup.id_pressed.emit(popup.get_item_id(index))
	await process_frame
	await process_frame
	_check(volume.is_visible_in_tree(), "Selecting the Options item opens the sound volume control")


func _close_volume(volume: Range) -> void:
	var parent: Node = volume
	while parent != null and not parent is AcceptDialog:
		parent = parent.get_parent()
	if _check(parent is AcceptDialog, "Sound effects volume has a closeable dialog"):
		parent.get_ok_button().pressed.emit()
		await process_frame


func _unit(id: String, character: String, at: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": at, "hp": 20,
		"max_hp": 20, "statuses": {}}


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func _finish() -> void:
	if failures.is_empty():
		print("PASS: committed sound effects, planning and volume")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
