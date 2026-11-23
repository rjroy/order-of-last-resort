extends "res://tests/ferryman_rescue_scene_test.gd"
## godot --path games/company-of-unlikely-heroes --script res://tests/ferryman_impact_geometry_scene_test.gd -- --output="$PWD/.lore/local/ferryman-impact"
## Stock rescue route; compare actual rendered pixels with a civilian-hidden
## reference at each frozen point on the committed board timeline.


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
	scene.configure_launch(PackedStringArray(["--storybook", "--mission=goblin_mob"]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	var opening: Dictionary = Rules.open_mission(Catalog.read_default(), "company_rescue",
		["knight", "healer", "wizard"])
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	await process_frame
	var board := scene.find_child("BridgeBoard", true, false)
	if board == null:
		_finish("Stock rescue board did not open.")
		return
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	for command in [["knight", "move", "2,1"], ["knight", "knight_push", "crate"],
			["wizard", "move", "1,1"]]:
		if not await driver.command(command[0], command[1], command[2]):
			_finish(driver.error)
			return
		if not await _commit():
			_finish("")
			return
		board.call("_process", 30.0)
		board.set_process(false)
	if not await driver.order("knight", "order_advance") \
			or not await driver.command("wizard", "wizard_pull", "harpooner"):
		_finish(driver.error)
		return
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	_check(plan.get("valid", false), "Stock fourth-round forecast is valid")
	var hit_index := -1
	var move_index := -1
	for i in plan.get("events", []).size():
		var event: Dictionary = plan.events[i]
		if event.get("type") == "damage" and event.get("source_id") == "harpooner" \
				and event.get("target_id") == "civilian" and event.get("amount", 0) > 0:
			hit_index = i
		if event.get("type") == "move" and event.get("unit_id") == "civilian" \
				and event.get("position") == Vector2i(3, 2):
			move_index = i
	_check(hit_index >= 0 and move_index > hit_index, "Real C3 hit precedes civilian movement to D3")
	_check(_unit(scene.battle_snapshot(), "civilian").get("position") == Vector2i(2, 2) \
		and _unit(plan.result, "civilian").get("position") == Vector2i(3, 2),
		"Committed round changes Ferryman position C3 to D3")
	if not await _commit():
		_finish("")
		return
	board.set_process(false)
	var playback = board.get("_playback")
	var shot = null
	var flinch = null
	var travel = null
	for entry in playback.get("_entries"):
		if entry.cue.get("unit_id") == "harpooner" and entry.cue.get("clip") == "ranged_cast":
			shot = entry
		elif entry.cue.get("unit_id") == "civilian" and entry.cue.get("clip") == "flinch":
			flinch = entry
		elif entry.cue.get("unit_id") == "civilian" and entry.cue.get("clip") == "travel":
			travel = entry
	if shot == null or flinch == null or travel == null:
		_finish("Committed round must queue the real shot, flinch and travel.")
		return
	_check(shot.cue.get("target_cell") == Vector2i(2, 2)
		and flinch.cue.get("source_cell") == Vector2i(2, 2), "Shot and flinch name the actual C3 impact")
	_advance_to(board, shot, shot.clip.release_ms + 150.0)
	_check(shot.flight_progress() > 0.0 and shot.flight_progress() < 1.0, "Projectile is in flight")
	await _assert_pixels(board, "flight", Vector2i(2, 2), Vector2i(3, 2))
	_check(_unit(scene.battle_snapshot(), "civilian").get("position") == Vector2i(3, 2) \
		and board.get("_units_by_id").get("civilian", {}).get("cell") == Vector2i(3, 2),
		"Presentation placement does not alter committed state or board input geometry")
	_advance_to(board, shot, shot.impact_ms + 80.0)
	_check(flinch.elapsed_ms >= 0.0 and flinch.elapsed_ms < flinch.clip.total_ms, "Flinch is active at impact")
	await _assert_pixels(board, "impact", Vector2i(2, 2), Vector2i(3, 2))
	_advance_to(board, travel, travel.clip.total_ms * 0.9)
	_check(travel.elapsed_ms >= 0.0 and travel.elapsed_ms < travel.clip.total_ms, "Travel is active")
	await _assert_pixels(board, "travel", Vector2i(3, 2), Vector2i(2, 2))
	board.call("_process", 30.0)
	board.set_process(false)
	_check(board.call("action_playback_snapshot").is_empty(), "Committed timeline finishes")
	await _assert_pixels(board, "rest", Vector2i(3, 2), Vector2i(2, 2))
	_finish("")


func _commit() -> bool:
	var button := scene.find_child("Commit", true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, "Commit is available")
		return false
	button.pressed.emit()
	await process_frame
	return true


func _advance_to(board: Node, entry, elapsed_ms: float) -> void:
	board.call("_process", maxf(0.0, elapsed_ms - entry.elapsed_ms) / 1000.0 + 0.001)
	board.set_process(false)


func _assert_pixels(board: Node, name: String, expected: Vector2i, other: Vector2i) -> void:
	await _capture(name + ".png")
	var visible := viewport.get_texture().get_image()
	var cells: Dictionary = board.get("_cells").duplicate(true)
	var units: Array = board.get("_units").duplicate(true)
	var overlay: Dictionary = board.get("_overlay").duplicate(true)
	var without := units.filter(func(unit): return unit.get("id") != "civilian")
	var playback = board.get("_playback")
	var entries: Array = playback.get("_entries").duplicate()
	var hidden: Array = entries.duplicate()
	for i in range(hidden.size() - 1, -1, -1):
		if hidden[i].cue.get("unit_id") == "civilian":
			hidden.remove_at(i)
	playback.set("_entries", hidden)
	board.call("set_render_state", cells, without, overlay)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var blank := viewport.get_texture().get_image()
	var expected_count := _body_difference(board, visible, blank, expected)
	var other_count := _body_difference(board, visible, blank, other)
	print("%s: rendered actor difference at %s=%d, %s=%d" % [
		name, expected, expected_count, other, other_count])
	_check(expected_count > 50 and expected_count > other_count,
		"%s visibly places Ferryman at %s, not %s (%d vs %d pixels)" % [
			name, expected, other, expected_count, other_count])
	playback.set("_entries", entries)
	board.call("set_render_state", cells, units, overlay)
	board.set_process(false)


func _body_difference(board: Node, visible: Image, blank: Image, cell: Vector2i) -> int:
	var center: Vector2 = board.get_global_transform_with_canvas() * board.cell_center(cell)
	var next: Vector2 = board.get_global_transform_with_canvas() * board.cell_center(cell + Vector2i(1, 0))
	var width := next.x - center.x
	var count := 0
	for y in range(maxi(0, int(center.y - width * 0.48)), mini(visible.get_height(), int(center.y + width * 0.22))):
		for x in range(maxi(0, int(center.x - width * 0.32)), mini(visible.get_width(), int(center.x + width * 0.32))):
			var delta := visible.get_pixel(x, y) - blank.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				count += 1
	return count
