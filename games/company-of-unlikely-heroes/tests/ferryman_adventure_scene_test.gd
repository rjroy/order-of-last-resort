extends "res://tests/ferryman_rescue_scene_test.gd"
## godot --path games/company-of-unlikely-heroes --script res://tests/ferryman_adventure_scene_test.gd -- --output="$PWD/.lore/local/ferryman-adventure"
## Real fixed outing and stock patrol; no injected battle or settled run.


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_finish("A graphical renderer is required.")
		return
	var args := OS.get_cmdline_user_args()
	var local := ProjectSettings.globalize_path("res://../../.lore/local").simplify_path()
	if args.size() != 1 or not args[0].begins_with("--output="):
		_finish("Supply exactly one --output=<absolute directory>.")
		return
	output = args[0].trim_prefix("--output=").simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/"):
		_finish("Output must be under .lore/local.")
		return
	var path := local
	for part in output.trim_prefix(local + "/").split("/"):
		path = path.path_join(part)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_finish("Output must not contain symbolic links.")
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_finish("Cannot create output directory.")
		return
	var dir := DirAccess.open(output)
	if dir == null or not dir.get_files().is_empty() or not dir.get_directories().is_empty():
		_finish("Output directory must be empty.")
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--fixed-outings"]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	for id in ["knight", "healer", "wizard"]:
		if not await _press("Recruit_" + id):
			_finish("")
			return
	if not await _press("StartAdventure"):
		_finish("")
		return
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await driver.order("wizard", "order_blast"):
		_finish(driver.error)
		return
	for i in 3:
		if i == 2 and not await driver.command("wizard", "wizard_pull", "raider_two"):
			_finish(driver.error)
			return
		if not await _press("Commit"):
			_finish("")
			return
	_check(scene.current_screen() == "debrief", "Actual patrol victory settles to debrief")
	if scene.current_screen() != "debrief":
		_finish("")
		return
	var offered := false
	for id in ["knight", "healer", "wizard"]:
		var reward := scene.find_child("Reward_" + id, true, false) as BaseButton
		if reward != null and not reward.disabled and reward.is_visible_in_tree():
			offered = await _press("Reward_" + id)
			break
	if not offered or not await _press("ContinueAdventure"):
		_finish("Cannot continue to rescue.")
		return
	_check(scene.current_screen() == "battle" and scene.battle_snapshot().get("mission_id") == "company_rescue",
		"Actual outing opens the stock rescue")
	if scene.current_screen() != "battle":
		_finish("")
		return
	var board := scene.find_child("BridgeBoard", true, false)
	_check(board.get("_units_by_id").get("civilian", {}).get("cast_key") == "ferryman"
		and board.get("_units_by_id").get("harpooner", {}).get("cast_key") == "harpooner",
		"Both authored actors coexist on the live outing board")
	await _capture("adventure-ready.png")
	for i in 10:
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		if not plan.get("valid", false):
			_finish("Rescue forecast is invalid.")
			return
		var terminal: bool = plan.result.outcome == "victory"
		if not await _press("Commit"):
			_finish("")
			return
		if terminal:
			_check(plan.events.any(func(event): return event.get("type") == "victory" \
				and event.get("target_id") == "civilian"), "Actual committed victory names Ferryman")
			_check(scene.current_screen() != "battle", "Actual outing leaves battle on victory")
			var overlay := scene.find_child("TerminalCastReplay", true, false) as Control
			_check(overlay != null and overlay.is_visible_in_tree(), "Terminal replay is visible after settlement")
			if overlay != null:
				var replay: Node
				for child in overlay.find_children("*", "", true, false):
					if child.has_method("action_playback_snapshot"):
						replay = child
						break
				_check(replay != null and _has_cue(replay.call("action_playback_snapshot"), "safe_bank"),
					"Settled adventure retains the Ferryman safe_bank performance")
				if replay != null:
					await _watch_terminal_replay(replay)
			_finish("")
			return
		if scene.current_screen() != "battle":
			_finish("Stock outing rescue ended without victory.")
			return
	_check(false, "Stock outing rescue reaches victory before deadline")
	_finish("")


func _watch_terminal_replay(replay: Node) -> void:
	var playback = replay.get("_playback")
	var safe = null
	var travel = null
	for entry in playback.get("_entries"):
		if entry.cue.get("unit_id") == "civilian":
			if entry.cue.get("clip") == "safe_bank":
				safe = entry
			elif entry.cue.get("clip") == "travel":
				travel = entry
	_check(safe != null and travel != null, "Terminal stock round queues travel then safe_bank")
	if safe == null or travel == null:
		return
	var started := Time.get_ticks_msec()
	var captured := false
	var peak_safe: float = safe.elapsed_ms
	while is_instance_valid(replay) and scene.find_child("TerminalCastReplay", true, false) != null \
			and Time.get_ticks_msec() - started < 7000:
		await process_frame
		if not is_instance_valid(replay):
			break
		peak_safe = maxf(peak_safe, safe.elapsed_ms)
		if not captured and safe.elapsed_ms >= 1000.0:
			captured = true
			await _capture("adventure-normal-playback.png")
	peak_safe = maxf(peak_safe, safe.elapsed_ms)
	var wall_ms := Time.get_ticks_msec() - started
	print("Terminal replay: travel %.0f ms, safe_bank %.0f / %.0f ms, wall %d ms" % [
		travel.clip.total_ms, peak_safe, safe.clip.total_ms, wall_ms])
	_check(captured, "Safe bank is visible during normal real-time playback")
	_check(peak_safe >= safe.clip.total_ms, "Normal terminal replay does not truncate safe_bank")


func _press(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is available")
		return false
	button.pressed.emit()
	await process_frame
	return true
