extends SceneTree
## Run with a graphical renderer and an isolated XDG_DATA_HOME. Run once normally,
## then again with -- --verify-reload using the same XDG_DATA_HOME.
## The first run leaves the grid hidden; the second verifies and restores it.

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
	await _launch()
	if board == null:
		_finish()
		return
	var toggle := _grid_toggle()
	if toggle == null:
		_finish()
		return
	var reload := "--verify-reload" in OS.get_cmdline_user_args()
	_check(toggle.button_pressed != reload, "Grid control reflects the saved choice on launch")
	if reload:
		await _exercise_tiles()
		await _click(toggle.get_global_rect().get_center())
		_check(toggle.button_pressed, "Grid can be shown after restarting the game")
	else:
		var labels := _labels()
		var before := await _capture()
		await _click(toggle.get_global_rect().get_center())
		_check(not toggle.button_pressed, "Grid can be hidden during combat")
		var hidden := await _capture()
		_check(_difference(before, hidden) > 100, "Hiding the grid immediately changes the rendered battle")
		_check(_labels() == labels and not labels.is_empty(), "Hiding the grid preserves unit nameplates")
		await _exercise_tiles()
		await _click(toggle.get_global_rect().get_center())
		_check(toggle.button_pressed, "Grid can be shown again during combat")
		var shown := await _capture()
		_check(_difference(hidden, shown) > 100, "Showing the grid immediately changes the rendered battle")
		_check(_labels() == labels, "Showing the grid preserves unit nameplates")
		await _exercise_tiles()
		await _click(toggle.get_global_rect().get_center())
		await _launch()
		toggle = _grid_toggle()
		if toggle != null:
			_check(not toggle.button_pressed, "A fresh fight retains the hidden grid choice")
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


func _grid_toggle() -> BaseButton:
	for candidate in scene.find_children("*", "BaseButton", true, false):
		var button := candidate as BaseButton
		if button.is_visible_in_tree() and "grid" in (button.text + " " + button.accessibility_name).to_lower():
			_check(button.toggle_mode, "Grid control exposes its checked state")
			return button
	_check(false, "Battle exposes a visible grid toggle")
	return null


func _labels() -> Dictionary:
	var result := {}
	for unit in board.get("_units"):
		if not str(unit.get("label", "")).is_empty():
			result[unit.id] = unit.label
	return result


func _exercise_tiles() -> void:
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
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
		return
	await _click_cell(healer.position)
	_check(scene.get("_actor_id") == "healer", "Hero tile selects Healer")
	await _click_cell(knight.position)
	_check(scene.get("_actor_id") == "knight", "Hero tile selects Knight")
	await _click_cell(targets[0].position)
	var command: Dictionary = (scene.get("_planned_state") as Dictionary).get("overrides", {}).get("knight", {})
	_check(command.get("ability_id") == "move" and command.get("target_id") == targets[0].id,
		"Destination tile stages the legal move")
	_check(scene.battle_snapshot() == before, "Tile interaction remains a preview")
	var clear := scene.find_child("ClearCommand", true, false) as BaseButton
	if clear != null:
		await _click(clear.get_global_rect().get_center())


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


func _difference(first: Image, second: Image) -> int:
	if first.get_size() != second.get_size():
		return 0
	var rect := Rect2i(board.get_global_rect())
	rect = rect.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
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
		print("PASS: combat grid visibility")
	quit(0 if failures.is_empty() else 1)
