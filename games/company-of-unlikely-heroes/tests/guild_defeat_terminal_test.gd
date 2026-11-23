extends "res://tests/cast_terminal_scene_test.gd"
## godot --path games/company-of-unlikely-heroes --script res://tests/guild_defeat_terminal_test.gd
## A real last living party member is struck down in a commission mission.


func _run() -> void:
	viewport.free()
	if not _write_fixture():
		_cleanup()
		return
	root.size = VIEWPORT_SIZE
	for skip in [true, false]:
		await _run_wipe_case(skip)
		if is_instance_valid(scene):
			scene.queue_free()
			await process_frame
		if FileAccess.file_exists(profile_path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path)) == OK,
				"Removed test-owned profile between wipe cases")
		_remove_test_backup()
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) == OK,
		"Removed test-owned catalog")
	_cleanup()


func _run_wipe_case(skip: bool) -> void:
	var store = load("res://guild_profile.gd")
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Test-owned guild is created")
	else:
		scene = load("res://main.tscn").instantiate()
		scene.configure_launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(fixture_path)]))
		scene.configure_profile_path(profile_path)
		root.add_child(scene)
		await process_frame
		await process_frame
		await _press("Commission_0")
		for id in PARTY:
			await _press("Recruit_" + id)
		await _press("StartAdventure")
		await _press("Route_0")
		await _wipe(skip)


func _wipe(skip: bool) -> void:
	if scene.current_screen() != "battle":
		_check(false, "Controlled commission mission opens")
		return
	var rules = preload("res://rules.gd").new()
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	for unit in state.units:
		if unit.id in PARTY:
			unit.hp = 1 if unit.id == "knight" else 0
			unit.position = Vector2i(3, 3) if unit.id == "knight" else Vector2i(1, 1)
		elif unit.id == "grunt_1":
			unit.position = Vector2i(4, 4)
			unit.hp = 20
			unit.max_hp = 20
	state = rules.set_order(state, "knight", "order_hold")
	scene.call("_show_battle", state)
	scene.set("_planned_state", rules.choose_manual(state, "knight", "move", "3,4"))
	scene.call("_refresh")
	var before_carry: Dictionary = scene.get("_run").carry_by_id.duplicate(true)
	var plan: Dictionary = scene.get("_plan")
	_check(plan.get("valid", false) and plan.get("result", {}).get("outcome") == "defeat" \
		and plan.events.any(func(event): return event.get("type") == "damage" \
			and event.get("target_id") == "knight" and event.get("amount", 0) > 0),
		"Enemy's real hit forecasts the party wipe: " + str(plan.get("events", [])) \
			+ " outcome=" + str(plan.get("result", {}).get("outcome")))
	if not plan.get("valid", false) or plan.get("result", {}).get("outcome") != "defeat":
		return
	var commit := _node("Commit") as BaseButton
	if commit == null or commit.disabled:
		_check(false, "Party wipe can be committed")
		return
	commit.pressed.emit()
	_check(scene.current_screen() == "result" and scene.get("_run").get("phase") == "finished" \
		and scene.get("_run").get("outcome") == "defeat",
		"Party wipe synchronously settles to results")
	_check(scene.get("_run").carry_by_id == before_carry,
		"Party wipe leaves adventure carryover unchanged")
	var replay = scene.get("_terminal_board")
	_check(replay != null and replay.action_playback_snapshot().any(func(cue): return \
		cue.get("unit_id") == "knight" and cue.get("clip") == "defeat"),
		"Terminal replay retains the last hero's defeat")
	if replay != null:
		if skip:
			var event := InputEventKey.new()
			event.keycode = KEY_SPACE
			event.pressed = true
			scene._input(event)
			_check(scene.get("_terminal_board") == null and scene.get("_terminal_replay") == null \
				and scene.current_screen() == "result", "Skipping replay releases its board and keeps results")
		else:
			await _drain_replay(replay, before_carry)


func _drain_replay(replay: Node, before_carry: Dictionary) -> void:
	var saw_final_frame := false
	var deadline := Time.get_ticks_msec() + 15000
	while is_instance_valid(replay) and scene.get("_terminal_board") == replay \
			and Time.get_ticks_msec() < deadline:
		var entries: Array = replay.get("_playback").active()
		for entry in entries:
			if entry.cue.get("unit_id") == "knight" and entry.cue.get("clip") == "defeat" \
					and entry.elapsed_ms < entry.clip.total_ms \
					and entry.clip.frame_index(entry.elapsed_ms) == entry.clip.frames.size() - 1:
				saw_final_frame = true
		await process_frame
	_check(saw_final_frame, "Last hero reaches the final defeat frame during natural playback")
	_check(scene.get("_terminal_board") == null and scene.get("_terminal_replay") == null,
		"Natural playback removes the terminal replay without input")
	_check(scene.current_screen() == "result" and scene.get("_run").get("phase") == "finished" \
		and scene.get("_run").get("outcome") == "defeat" and scene.get("_run").carry_by_id == before_carry,
		"Natural playback preserves the defeat result and carryover")
