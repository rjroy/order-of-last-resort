extends SceneTree
## Run graphically with an isolated XDG_DATA_HOME, then run again with
## -- --verify-reload using the same directory. The first run leaves both
## grid on and nameplates off; the second verifies persistence and restores them.
## The first run seeds an old grid-only settings file and refuses to overwrite one.

const GRID := "Show Grid"
const NAMES := "Show Nameplates"
var failures: Array[String] = []
var scene: Node
var board: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires a graphical renderer.")
		quit(1)
		return
	root.size = Vector2i(1280, 820)
	var reload := "--verify-reload" in OS.get_cmdline_user_args()
	if not reload and not _seed_legacy_preferences():
		_finish()
		return
	await _launch()
	if board == null:
		_finish()
		return
	if not await _check_options(true if reload else false, false if reload else true):
		_finish()
		return
	if reload:
		await _exercise_tiles()
		await _toggle(NAMES)
		await _check_options(true, true)
		_finish()
		return

	await _toggle(GRID)
	await _check_options(true, true)
	var labels := _labels()
	_check(not labels.is_empty(), "Battle has nameplates to display")
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	if not await _stage_move(before):
		_finish()
		return
	var draft: Dictionary = (scene.get("_planned_state") as Dictionary).duplicate(true)
	var actor: String = scene.get("_actor_id")
	await _exercise_keyboard_options(before, draft, actor)
	# Disable processing for the comparison interval even if a state refresh
	# calls set_process(true). Establish the pose once, before the baseline.
	var previous_process_mode := board.process_mode
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.set("_ready_ms", 0.0)
	(board.get_node("CastAndUnitMarkers") as CanvasItem).queue_redraw()
	var both_shown := await _capture()
	await _toggle(GRID)
	await _check_options(false, true)
	_check_draft(before, draft, actor)
	var grid_hidden := await _capture()
	_check(_difference(both_shown, grid_hidden, _board_rect()) > 100,
		"Hiding the grid immediately changes the rendered battle")
	await _toggle(NAMES)
	await _check_options(false, false)
	_check_draft(before, draft, actor)
	var both_hidden := await _capture()
	_check(_name_difference(grid_hidden, both_hidden) > 5,
		"Nameplate text is visible with grid hidden and disappears when nameplates are hidden")
	await _toggle(GRID)
	await _check_options(true, false)
	_check_draft(before, draft, actor)
	var names_hidden := await _capture()
	_check(_difference(both_hidden, names_hidden, _board_rect()) > 100,
		"Showing the grid changes the board even with nameplates hidden")
	await _toggle(NAMES)
	await _check_options(true, true)
	_check_draft(before, draft, actor)
	var restored := await _capture()
	_check(_name_difference(restored, names_hidden) > 5,
		"Nameplate text is visible with grid shown and disappears when nameplates are hidden")
	_check(_labels() == labels, "Display choices preserve the underlying unit labels")
	board.process_mode = previous_process_mode
	await _clear_command()
	await _exercise_tiles()

	await _toggle(NAMES)
	await _check_options(true, false)
	var restart := scene.find_child("Restart", true, false) as BaseButton
	if restart == null or not restart.is_visible_in_tree():
		_check(false, "Standalone battle exposes Restart")
	else:
		await _click(restart.get_global_rect().get_center())
		await process_frame
		board = scene.find_child("BridgeBoard", true, false) as Control
		if board != null:
			await _check_options(true, false)
			await _exercise_tiles()
		else:
			_check(false, "Restart returns to a battle board")
	await _launch()
	if board != null:
		await _check_options(true, false)
		await _exercise_tiles()
	_finish()


func _launch() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	board = scene.find_child("BridgeBoard", true, false) as Control
	_check(scene.current_screen() == "battle" and board != null, "Gate battle launches")
	if board != null:
		# Freeze idle animation for pixel comparisons, without changing board data.
		board.set_process(false)


func _seed_legacy_preferences() -> bool:
	const PATH := "user://battle_display.cfg"
	if FileAccess.file_exists(PATH):
		_check(false, "Use a fresh isolated XDG_DATA_HOME; refusing to overwrite existing preferences")
		return false
	var config := ConfigFile.new()
	config.set_value("battle", "grid_visible", false)
	var error := config.save(PATH)
	_check(error == OK, "Test-owned legacy grid-only preferences can be seeded")
	return error == OK


func _exercise_keyboard_options(before: Dictionary, draft: Dictionary, actor: String) -> void:
	var button := _options()
	if button == null:
		return
	button.grab_focus()
	await process_frame
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	var menu := button.get_popup()
	if not menu.visible:
		_check(false, "Keyboard activation opens Options")
		return
	await _key(KEY_DOWN, true)
	await _key(KEY_DOWN, false)
	var index := menu.get_focused_item()
	if index < 0 or index >= menu.item_count:
		_check(false, "Keyboard navigation focuses an Options check")
		menu.hide()
		return
	var initially_checked := menu.is_item_checked(index)
	await _key(KEY_ENTER, true)
	var after_press := menu.is_item_checked(index)
	await _key(KEY_ENTER, true, true)
	_check(menu.is_item_checked(index) == after_press,
		"An accept echo does not change the check again")
	await _key(KEY_ENTER, false)
	_check(menu.is_item_checked(index) != initially_checked,
		"One held accept changes the focused check exactly once")
	_check_draft(before, draft, actor)
	# Escape is sent to the window, as it would be by the player, while the
	# check menu is still open. It must dismiss only the menu, not the draft.
	_check(menu.visible, "Options stays open after selecting a check")
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	_check(not menu.visible, "Escape dismisses Options")
	_check_draft(before, draft, actor)
	# Restore the selected check through the ordinary pointer path for the
	# subsequent four-way rendering checks.
	if menu.is_item_checked(index) != initially_checked:
		await _toggle(menu.get_item_text(index))
	await _check_options(true, true)


func _key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)
	await process_frame


func _options() -> MenuButton:
	for candidate in scene.find_children("*", "MenuButton", true, false):
		var button := candidate as MenuButton
		if button.is_visible_in_tree() and button.text.to_lower() == "options":
			return button
	_check(false, "Battle exposes an Options menu")
	return null


func _item(menu: PopupMenu, label: String) -> int:
	for index in menu.item_count:
		if menu.get_item_text(index).to_lower() == label.to_lower():
			return index
	_check(false, "Options contains " + label)
	return -1


func _check_options(grid: bool, names: bool) -> bool:
	var button := _options()
	if button == null:
		return false
	await _click(button.get_global_rect().get_center())
	var menu := button.get_popup()
	_check(menu.visible, "Clicking Options opens the menu")
	var grid_index := _item(menu, GRID)
	var names_index := _item(menu, NAMES)
	var valid := grid_index >= 0 and names_index >= 0
	if valid:
		_check(menu.is_item_checkable(grid_index) and menu.is_item_checkable(names_index),
			"Both Options entries are checkable")
		_check(menu.is_item_checked(grid_index) == grid, "Show Grid reflects the saved choice")
		_check(menu.is_item_checked(names_index) == names, "Show Nameplates reflects the saved choice")
	menu.hide()
	await process_frame
	return valid


func _toggle(label: String) -> void:
	var button := _options()
	if button == null:
		return
	await _click(button.get_global_rect().get_center())
	var menu := button.get_popup()
	var index := _item(menu, label)
	if index < 0 or not menu.visible:
		_check(false, "Options opens to allow clicking " + label)
		menu.hide()
		return
	# Route pointer input through the root window so Godot dispatches it to the
	# embedded popup window, rather than bypassing its window input handling.
	_check(menu.item_count == 2, "Options has the two display checks")
	var point := Vector2(menu.position) \
		+ Vector2(menu.size.x * 0.5, menu.size.y * (index + 0.5) / menu.item_count)
	await _click(point)
	if menu.visible:
		menu.hide()
	await process_frame


func _labels() -> Dictionary:
	var result := {}
	for unit in board.get("_units"):
		if not str(unit.get("label", "")).is_empty():
			result[unit.id] = unit.label
	return result


func _stage_move(before: Dictionary) -> bool:
	var rules = load("res://rules.gd").new()
	var knight := {}
	var healer := {}
	for unit in before.get("units", []):
		if unit.id == "knight":
			knight = unit
		if unit.id == "healer":
			healer = unit
	var targets: Array = rules.targets(before, "knight", "move")
	if knight.is_empty() or healer.is_empty() or targets.is_empty():
		_check(false, "Gate has heroes and a legal Knight move")
		return false
	await _click_cell(healer.position)
	_check(scene.get("_actor_id") == "healer", "Hero tile selects Healer")
	await _click_cell(knight.position)
	_check(scene.get("_actor_id") == "knight", "Hero tile selects Knight")
	await _click_cell(targets[0].position)
	var command: Dictionary = (scene.get("_planned_state") as Dictionary).get("overrides", {}).get("knight", {})
	_check(command.get("ability_id") == "move" and command.get("target_id") == targets[0].id,
		"Destination tile stages the legal move")
	_check(scene.battle_snapshot() == before, "Tile interaction remains a preview")
	return true


func _check_draft(before: Dictionary, draft: Dictionary, actor: String) -> void:
	_check(scene.battle_snapshot() == before, "Changing display options does not resolve the battle")
	_check(scene.get("_planned_state") == draft and scene.get("_actor_id") == actor,
		"Changing display options preserves the selected hero and draft")


func _exercise_tiles() -> void:
	if await _stage_move(scene.battle_snapshot().duplicate(true)):
		await _clear_command()


func _clear_command() -> void:
	var clear := scene.find_child("ClearCommand", true, false) as BaseButton
	if clear != null:
		await _click(clear.get_global_rect().get_center())
	else:
		_check(false, "Battle exposes Clear command")


func _click_cell(cell: Vector2i) -> void:
	await _click(board.get_global_transform_with_canvas() * board.cell_center(cell))


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _board_rect() -> Rect2i:
	return Rect2i(board.get_global_rect())


func _name_difference(first: Image, second: Image) -> int:
	var changed := 0
	var scale: float = board.get("_map_scale")
	for unit in board.get("_units"):
		if str(unit.get("label", "")).is_empty():
			continue
		# The existing marker draws text at the bottom of the unit's tile.
		var center: Vector2 = board.cell_center(unit.cell)
		var origin := center + Vector2(-45, 24) * scale
		var corner := center + Vector2(45, 40) * scale
		var transform := board.get_global_transform_with_canvas()
		var region := Rect2i(Rect2(transform * origin, (corner - origin) * transform.get_scale()))
		changed += _difference(first, second, region)
	return changed


func _difference(first: Image, second: Image, region: Rect2i) -> int:
	if first.get_size() != second.get_size():
		return 0
	var rect := region.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
	var changed := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: combat display options")
	quit(0 if failures.is_empty() else 1)
