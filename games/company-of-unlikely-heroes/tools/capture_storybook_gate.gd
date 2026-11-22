extends SceneTree
## Graphical capture from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tools/capture_storybook_gate.gd -- --output="$PWD/.lore/local/storybook-gate"
## Supply a new or empty directory under .lore/local. No existing profile is used.

const BoardRules = preload("res://rules/board.gd")
const SIZE := Vector2i(1280, 820)
const MISSION := "wrong_side_of_the_door"

var viewport: SubViewport
var scene: Node
var output := ""
var failure := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--output=") or not output.is_empty():
			_finish("Supply exactly one --output=<absolute directory> argument.")
			return
		output = arg.trim_prefix("--output=").simplify_path()
	var local := ProjectSettings.globalize_path("res://../../.lore/local").simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/"):
		_finish("Supply an absolute --output directory under .lore/local/.")
		return
	if DisplayServer.get_name() == "headless":
		_finish("A graphical renderer is required.")
		return
	# Reject links in the output path so an apparently local path cannot write elsewhere.
	var path := local
	for component in output.trim_prefix(local + "/").split("/"):
		path = path.path_join(component)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_finish("Output path must not contain symbolic links: " + path)
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_finish("Cannot create output directory: " + output)
		return
	var directory := DirAccess.open(output)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_finish("Output directory must be empty: " + output)
		return

	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--storybook", "--mission=" + MISSION]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if scene.current_screen() != "battle" or scene.battle_snapshot().get("mission_id") != MISSION:
		_finish("Could not launch the storybook gate mission.")
		return

	# Move Knight one square in round 1, so C2 is reachable in round 2.
	if not await _move_to(Vector2i(1, 1)) or not await _commit():
		_finish(failure)
		return
	var before: Dictionary = scene.battle_snapshot()
	if before.get("round") != 2 or _knight_position(before) != Vector2i(1, 1) \
			or BoardRules.pressure_gate_open(before):
		_finish("Round 2 must start with Knight at B2 and the gate closed.")
		return
	# Exercise the visible clear control, then capture its restored standing forecast.
	if not await _move_to(Vector2i(2, 1)) or not await _press("ClearCommand"):
		_finish(failure)
		return
	if scene.battle_snapshot() != before or not scene.get("_planned_state").get("overrides", {}).is_empty():
		_finish("Clear did not restore the unplanned round.")
		return
	if not await _capture("round-2-unplanned.png"):
		_finish(failure)
		return
	if not await _move_to(Vector2i(2, 1)):
		_finish(failure)
		return
	var plan: Dictionary = scene.get("_plan")
	if scene.battle_snapshot() != before or not plan.get("valid", false) \
			or _knight_position(plan.get("result", {})) != Vector2i(2, 1) \
			or not BoardRules.pressure_gate_open(plan.get("result", {})):
		_finish("C2 preview did not predict Knight opening the gate without changing the live state.")
		return
	if not await _capture("round-2-preview.png") or not await _commit():
		_finish(failure)
		return
	var after: Dictionary = scene.battle_snapshot()
	if _knight_position(after) != Vector2i(2, 1) or not BoardRules.pressure_gate_open(after):
		_finish("The committed move did not open the gate.")
		return
	if not await _capture("round-2-committed.png"):
		_finish(failure)
		return
	if FileAccess.file_exists(output.path_join("unused-profile.json")):
		_finish("Unexpected profile write during fixed-mission capture.")
		return
	print("Captured storybook gate sequence in " + output)
	_finish("")


func _move_to(cell: Vector2i) -> bool:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null or not board.is_visible_in_tree():
		return _fail("BridgeBoard is not visible.")
	var knight := _knight_position(scene.battle_snapshot())
	if knight == Vector2i(-1, -1):
		return _fail("Knight is missing from the battle.")
	await _click(board.get_global_transform_with_canvas() * board.cell_center(knight))
	await _click(board.get_global_transform_with_canvas() * board.cell_center(cell))
	var command: Dictionary = scene.get("_planned_state").get("overrides", {}).get("knight", {})
	if command.get("ability_id") != "move" or command.get("target_id") != "%d,%d" % [cell.x, cell.y]:
		return _fail("Clicking the board did not stage Knight's move to %s." % cell)
	return true


func _commit() -> bool:
	var plan: Dictionary = scene.get("_plan")
	if not plan.get("valid", false):
		return _fail("The round has no valid preview.")
	var expected: Dictionary = plan.get("result", {}).duplicate(true)
	if not await _press("Commit"):
		return false
	if scene.battle_snapshot() != expected:
		return _fail("Committed round differs from the preview.")
	return true


func _press(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		return _fail(name + " is not available.")
	await _click(button.get_global_transform_with_canvas() * (button.size * 0.5))
	return true


func _click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = point
		event.global_position = point
		event.pressed = down
		viewport.push_input(event, true)
		await process_frame


func _knight_position(state: Dictionary) -> Vector2i:
	for unit in state.get("units", []):
		if unit.get("id") == "knight":
			return unit.get("position", Vector2i(-1, -1))
	return Vector2i(-1, -1)


func _capture(filename: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != SIZE:
		return _fail("Could not read the full viewport for " + filename)
	if image.save_png(output.path_join(filename)) != OK:
		return _fail("Could not write " + filename)
	print("Captured " + filename)
	return true


func _fail(message: String) -> bool:
	failure = message
	return false


func _finish(message: String) -> void:
	if not message.is_empty():
		push_error(message)
	quit(0 if message.is_empty() else 1)
