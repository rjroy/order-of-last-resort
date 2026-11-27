extends "res://tools/capture_guild_book.gd"
## Run the graphical recipe in assets/help/README.md. Never writes to source assets.

const PRESSURE_GATE = preload("res://rules/board.gd")
const CAPTURE_SEED := 677
const MISSION := "wrong_side_of_the_door"
const B2 := Vector2i(1, 1)
const C2 := Vector2i(2, 1)
# Pixel rectangles in the 1280 × 820 source frames. Keep controls and text at
# close to native size instead of shrinking a whole spread into the handbook.
const CROPS := [
	["commission-full", "commission-selection", Rect2i(27, 138, 408, 608)],
	["recruitment-full", "recruitment", Rect2i(27, 141, 530, 581)],
	["reports-full", "field-reports", Rect2i(36, 125, 592, 657)],
	["battle-controls-full", "battle-controls", Rect2i(35, 679, 564, 56)],
	["battle-controls-full", "battle-commit", Rect2i(866, 740, 382, 60)],
	["battle-controls-full", "battle-board", Rect2i(318, 95, 522, 345)],
	["battle-forecast-full", "battle-forecast", Rect2i(811, 383, 438, 320)],
]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("--output="):
		_finish_capture("Supply --output=<new absolute directory under .lore/local/help-book-capture/>.")
		return
	output = args[0].trim_prefix("--output=").simplify_path()
	var repo := ProjectSettings.globalize_path("res://../../").simplify_path()
	var allowed := repo.path_join(".lore/local/help-book-capture")
	if not output.is_absolute_path() or not output.begins_with(allowed + "/"):
		_finish_capture("Capture output must be under " + allowed)
		return
	if DisplayServer.get_name() == "headless":
		_finish_capture("A graphical renderer is required.")
		return

	# Refuse symlinks and nonempty destinations, including existing profiles.
	var path := repo
	for component in output.trim_prefix(repo + "/").split("/"):
		path = path.path_join(component)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_finish_capture("Output path must not contain symbolic links: " + path)
			return
	var result := DirAccess.make_dir_recursive_absolute(output)
	var directory := DirAccess.open(output)
	if result != OK or directory == null \
			or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_finish_capture("Capture output must be new or empty.")
		return

	viewport.size = SIZE
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var profile := output.path_join("profile.json")
	var created: Dictionary = load("res://guild/guild_profile.gd").create(profile, "The Lantern Company", CAPTURE_SEED)
	if created.has("error"):
		_finish_capture(str(created.error))
		return
	await _mount(PackedStringArray(), profile)
	if not await _capture_guild_views():
		_finish_capture(failure if not failure.is_empty() else "Could not capture guild views.")
		return

	await _mount(PackedStringArray(["--mission=" + MISSION]), profile)
	if not await _capture_battle_views():
		_finish_capture(failure if not failure.is_empty() else "Could not capture battle views.")
		return
	_finish_capture(_save_crops())


func _mount(args: PackedStringArray, profile: String) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(args)
	scene.configure_profile_path(profile)
	viewport.add_child(scene)
	await process_frame
	await process_frame


func _capture_guild_views() -> bool:
	if not _screen_is("commissions") or not await _save_capture("commission-full") \
			or not await _press_button("Commission_0") or not _screen_is("guild"):
		return false
	for hero in FOUNDERS:
		if not await _press_button("Recruit_" + hero):
			return false
	if scene.selected_recruits() != FOUNDERS:
		failure = "Deployment order did not match the selected heroes."
		return false
	return await _save_capture("recruitment-full") \
		and await _press_button("StartAdventure") and _screen_is("routes") \
		and await _save_capture("reports-full")


func _capture_battle_views() -> bool:
	if not _screen_is("battle"):
		return false
	var board := _node("BridgeBoard") as Control
	if board == null or not board.has_method("cell_center"):
		failure = "Interactive battle board is missing."
		return false
	await _click_cell(board, Vector2i(0, 1)) # Select the Knight at A2.
	await _click_cell(board, B2)
	var first_plan: Dictionary = scene.get("_plan")
	if not first_plan.get("valid", false) or _knight_position(first_plan.get("result", {})) != B2 \
			or not await _press_button("Commit"):
		return false

	# Keep frames clear of the first round's cosmetic playback.
	var deadline := Time.get_ticks_msec() + 5000
	while not (board.call("action_playback_snapshot") as Array).is_empty():
		if Time.get_ticks_msec() >= deadline:
			failure = "The first round's action playback did not finish."
			return false
		await process_frame
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	if before.get("mission_id") != MISSION or before.get("round") != 2 or _knight_position(before) != B2:
		failure = "The Knight did not reach B2 after round one."
		return false
	await _click_cell(board, B2)
	await _click_cell(board, C2)
	var plan: Dictionary = scene.get("_plan")
	var predicted: Dictionary = plan.get("result", {})
	if scene.battle_snapshot() != before or not plan.get("valid", false) \
			or _knight_position(predicted) != C2 or not PRESSURE_GATE.pressure_gate_open(predicted) \
			or PRESSURE_GATE.pressure_gate_open(before):
		failure = "The staged move must predict an open gate without changing the live board."
		return false
	if not await _save_capture("battle-controls-full") or not await _press_button("ForecastDetails"):
		return false
	var leaf := _node("ExtraDetails") as Control
	if leaf == null or not leaf.is_visible_in_tree() or scene.battle_snapshot() != before:
		failure = "Forecast must open beside the unchanged battle board."
		return false
	return await _save_capture("battle-forecast-full")


func _click_cell(board: Control, cell: Vector2i) -> void:
	await _click(board.get_global_transform_with_canvas() * (board.call("cell_center", cell) as Vector2))


func _knight_position(state: Dictionary) -> Vector2i:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == "knight":
			return unit.position
	return Vector2i(-1, -1)


func _save_crops() -> String:
	var crop_dir := output.path_join("crops")
	if DirAccess.make_dir_absolute(crop_dir) != OK:
		return "Cannot create crop directory."
	for item: Array in CROPS:
		var source := Image.load_from_file(output.path_join(item[0] + ".png"))
		var region: Rect2i = item[2]
		if source == null or source.get_size() != SIZE or not Rect2i(Vector2i.ZERO, SIZE).encloses(region):
			return "Invalid source frame or rectangle for " + item[1]
		var crop := source.get_region(region)
		if crop.get_size() != region.size or crop.save_png(crop_dir.path_join(item[1] + ".png")) != OK:
			return "Cannot save " + item[1]
		print("Cropped %s: %s" % [item[1], region.size])
	return ""


func _finish_capture(message: String) -> void:
	if viewport.get_parent() == null:
		viewport.free()
	super._finish_capture(message)
