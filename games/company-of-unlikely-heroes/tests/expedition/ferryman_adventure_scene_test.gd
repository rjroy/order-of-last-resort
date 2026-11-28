extends "res://tests/journeys/ferryman_rescue_scene_test.gd"
## godot --path games/company-of-unlikely-heroes --script res://tests/expedition/ferryman_adventure_scene_test.gd -- --output="$PWD/.lore/local/ferryman-adventure"
## Commission route and stock rescue; no injected battle or settled run.


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
	# Make the stock rescue eligible as a tier-one road in this in-memory fixture,
	# without changing its encounter, so its settlement is reached immediately.
	var source := Catalog.read_source(Catalog.DEFAULT_PATH)
	if source.has("error"):
		_finish(str(source.error))
		return
	var defs: Dictionary = source.definitions
	defs.mission_reports.company_rescue.erase("destination_descriptors")
	defs.missions.company_rescue.tier = 1
	var errors: PackedStringArray = Catalog.validate(defs)
	if not errors.is_empty():
		_finish("Commission rescue fixture is invalid: " + str(errors))
		return
	var fixture := output.path_join("rescue-catalog.json")
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	if file == null:
		_finish("Cannot write rescue catalog fixture.")
		return
	file.store_string(JSON.stringify(defs))
	file.close()
	var commissions = load("res://expedition/commissions.gd")
	var adventure = load("res://expedition/adventure.gd")
	var board_seed := -1
	var offer_index := -1
	var route_index := -1
	for candidate in range(1, 501):
		var offers: Array = commissions.board(defs, candidate)
		for index in offers.size():
			var run: Dictionary = adventure.start_commission(defs, offers[index], ["knight", "healer", "wizard"], 12345)
			for report_index in run.get("reports", []).size():
				if run.reports[report_index].mission_id == "company_rescue":
					board_seed = candidate
					offer_index = index
					route_index = report_index
					break
			if board_seed >= 0:
				break
		if board_seed >= 0:
			break
	if board_seed < 0:
		_finish("No commission offered the rescue in the controlled seed range.")
		return
	var profile := output.path_join("profile.json")
	var created: Dictionary = load("res://guild/guild_profile.gd").create(profile, "Ferryman test", board_seed)
	if created.has("error"):
		_finish("Cannot create isolated guild: " + str(created))
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--content=" + fixture]))
	scene.configure_profile_path(profile)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if not await _press("Commission_%d" % offer_index):
		_finish("")
		return
	for id in ["knight", "healer", "wizard"]:
		if not await _press("Recruit_" + id):
			_finish("")
			return
	if not await _press("StartAdventure") or not await _press("Route_%d" % route_index):
		_finish("")
		return
	_check(scene.current_screen() == "battle" and scene.battle_snapshot().get("mission_id") == "company_rescue",
		"Selected commission report opens the stock rescue")
	if scene.current_screen() != "battle":
		_finish("")
		return
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var board := scene.find_child("BridgeBoard", true, false)
	_check(board.get("_units_by_id").get("civilian", {}).get("cast_key") == "ferryman"
		and board.get("_units_by_id").get("harpooner", {}).get("cast_key") == "harpooner",
		"Both authored actors coexist on the live outing board")
	await _capture("adventure-ready.png")
	for command in ROUTE:
		if not command.is_empty() and not await driver.command(command[0], command[1], command[2]):
			_finish(driver.error)
			return
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
				and event.get("target_id") == "civilian"), "Committed victory names Ferryman")
			_check(scene.current_screen() != "battle", "Commission leaves battle on victory")
			var overlay := scene.find_child("TerminalCastReplay", true, false) as Control
			_check(overlay != null and overlay.is_visible_in_tree(), "Terminal replay is visible after settlement")
			if overlay != null:
				var replay: Node
				for child in overlay.find_children("*", "", true, false):
					if child.has_method("action_playback_snapshot"):
						replay = child
						break
				_check(replay != null and _has_cue(replay.call("action_playback_snapshot"), "safe_bank"),
					"Settled commission retains the Ferryman safe_bank performance")
				if replay != null:
					await _watch_terminal_replay(replay)
			_finish("")
			return
		if scene.current_screen() != "battle":
			_finish("Stock commission rescue ended without victory.")
			return
	_check(false, "Stock commission rescue reaches victory before deadline")
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
	var entries: Array = playback.get("_entries").duplicate()
	var initial_remaining: float = scene.call("_terminal_playback_remaining_ms")
	# Allow the entire queued timeline, plus the production stall watchdog and
	# one timeline's worth of wall-clock scheduling slack.
	var budget_ms := int(ceil(initial_remaining * 2.0)) + int(scene.TERMINAL_REPLAY_STALL_MS)
	var started := Time.get_ticks_msec()
	var capture: Image
	var saw_final_frame := false
	var peak_safe: float = safe.elapsed_ms
	while is_instance_valid(replay) and scene.find_child("TerminalCastReplay", true, false) != null \
			and Time.get_ticks_msec() - started < budget_ms:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(replay):
			break
		peak_safe = maxf(peak_safe, safe.elapsed_ms)
		if safe in playback.active() and replay.is_visible_in_tree():
			if capture == null and safe.elapsed_ms >= safe.clip.total_ms * 0.5:
				capture = viewport.get_texture().get_image()
			if safe.clip.frame_index(safe.elapsed_ms) == safe.clip.frames.size() - 1:
				saw_final_frame = true
	peak_safe = maxf(peak_safe, safe.elapsed_ms)
	var wall_ms := Time.get_ticks_msec() - started
	var closed: bool = scene.find_child("TerminalCastReplay", true, false) == null
	print("Terminal replay: queue %.0f ms, travel %.0f ms, safe_bank %.0f / %.0f ms, wall %d / %d ms, closed %s" % [
		initial_remaining, travel.clip.total_ms, peak_safe, safe.clip.total_ms, wall_ms, budget_ms, closed])
	_check(capture != null, "Safe bank is visible during normal real-time playback")
	if capture != null:
		_check(capture.save_png(output.path_join("adventure-normal-playback.png")) == OK,
			"Saved adventure-normal-playback.png")
	_check(saw_final_frame, "Safe bank final frame is rendered during normal playback")
	_check(peak_safe >= safe.clip.total_ms, "Normal terminal replay does not truncate safe_bank")
	_check(closed, "Terminal replay closes naturally within its queue-aware watchdog")
	if closed:
		_check(entries.all(func(entry): return entry.elapsed_ms >= entry.duration_ms),
			"Terminal replay does not close before its queued cast performances complete")


func _press(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is available")
		return false
	button.pressed.emit()
	await process_frame
	return true
