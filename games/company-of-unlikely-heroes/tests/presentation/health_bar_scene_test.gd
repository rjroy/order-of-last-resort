extends SceneTree
## Run graphically with a fresh, isolated XDG_DATA_HOME:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/health_bar_scene_test.gd
## Preferences are written to that directory, as in normal play.

const Board = preload("res://presentation/battle/bridge_art.gd")
const OPTION := "Always show health bar"
const CELL := Vector2i(0, 0)
const CELLS := {CELL: "stone"}
const UNIT := {"id": "probe", "cell": CELL, "art_key": "knight",
	"hp": 1, "max_hp": 4}

var failures := 0
var scene: Node
var board: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Health bar test requires a graphical renderer.")
		quit(1)
		return
	if FileAccess.file_exists("user://battle_display.cfg"):
		printerr("Use a fresh isolated XDG_DATA_HOME; refusing to alter preferences.")
		quit(1)
		return
	root.size = Vector2i(1280, 820)
	await _launch()
	if board == null:
		_finish()
		return
	var menu := _menu()
	var index := _item(menu)
	if index < 0:
		_finish()
		return
	_check(menu.is_item_checkable(index) and not menu.is_item_checked(index),
		"Always show health bar defaults off")
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var draft: Dictionary = (scene.get("_planned_state") as Dictionary).duplicate(true)
	var actor: String = scene.get("_actor_id")

	# Use a controlled isolated unit and freeze the figure so only the health
	# marker differs. Zero max HP suppresses the marker without changing its pose.
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.set("_ready_ms", 0.0)
	var absent := await _render(UNIT.merged({"max_hp": 0}, true))
	var full_hidden := await _render(UNIT.merged({"hp": 4}, true))
	_check(_difference(absent, full_hidden, _bar_rect()) == 0,
		"Full-health unit has no bar by default")
	var quarter := await _render(UNIT)
	var half := await _render(UNIT.merged({"hp": 2}, true))
	_check(_difference(absent, quarter, _bar_rect()) > 10,
		"Wounded unit shows a bar on the right edge")
	_check(_difference(quarter, half, _local_rect(Rect2(79, 46, 3, 6))) > 0,
		"Additional health fills the middle of the vertical bar")
	_check(_difference(quarter, half, _local_rect(Rect2(79, 35, 3, 6))) == 0,
		"Additional health does not fill the top first")

	# Stage full health once. The option itself must invalidate the figure
	# canvas; setting render state again would mask a missing redraw.
	full_hidden = await _render(UNIT.merged({"hp": 4}, true))
	await _toggle(menu, index)
	_check(menu.is_item_checked(index), "Option updates its check immediately")
	_check(scene.battle_snapshot() == before and scene.get("_planned_state") == draft
		and scene.get("_actor_id") == actor, "Changing the option preserves the battle and draft")
	var full_shown := await _capture()
	_check(_difference(absent, full_shown, _bar_rect()) > 10,
		"Enabling the option immediately shows a full-health bar")
	await _toggle(menu, index)
	var hidden_again := await _capture()
	_check(_difference(absent, hidden_again, _bar_rect()) == 0,
		"Disabling the option immediately hides a full-health bar")
	await _toggle(menu, index)
	await _launch()
	menu = _menu()
	index = _item(menu)
	if index >= 0:
		_check(menu.is_item_checked(index), "Choice persists when a new battle scene loads")
	_finish()


func _launch() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	board = scene.find_child("BridgeBoard", true, false) as Control
	_check(board != null and scene.current_screen() == "battle", "Standalone battle launches")


func _menu() -> PopupMenu:
	for candidate in scene.find_children("*", "MenuButton", true, false):
		var button := candidate as MenuButton
		if button.is_visible_in_tree() and button.text.to_lower() == "options":
			return button.get_popup()
	_check(false, "Battle exposes Options")
	return null


func _item(menu: PopupMenu) -> int:
	if menu != null:
		for index in menu.item_count:
			if menu.get_item_text(index).to_lower() == OPTION.to_lower():
				return index
	_check(false, "Options contains " + OPTION)
	return -1


func _toggle(menu: PopupMenu, index: int) -> void:
	var button := menu.get_parent() as MenuButton
	await _click(button.get_global_rect().get_center())
	_check(menu.visible, "Options opens before selecting a display choice")
	menu.id_pressed.emit(menu.get_item_id(index))
	await process_frame
	await process_frame
	menu.hide()
	await process_frame


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


func _render(unit: Dictionary) -> Image:
	board.set_render_state(CELLS, [unit])
	return await _capture()


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _local_rect(rect: Rect2) -> Rect2i:
	var scale: float = board.get("_map_scale")
	var origin: Vector2 = board.cell_center(CELL) - Board.TILE * 0.5 * scale
	# The captured viewport texture excludes window letterboxing but may be
	# larger than the logical canvas when the window is scaled.
	var image_scale := Vector2(root.get_texture().get_image().get_size()) / root.get_visible_rect().size
	var transform := Transform2D(0.0, image_scale, 0.0, Vector2.ZERO) * board.get_global_transform_with_canvas()
	var start := transform * (origin + rect.position * scale)
	var end := transform * (origin + rect.end * scale)
	return Rect2i(Vector2i(start.floor()), Vector2i(end.ceil() - start.floor()))


func _bar_rect() -> Rect2i:
	return _local_rect(Rect2(77, 32, 7, 31))


func _difference(first: Image, second: Image, area: Rect2i) -> int:
	var changed := 0
	for y in range(maxi(0, area.position.y), mini(first.get_height(), area.end.y)):
		for x in range(maxi(0, area.position.x), mini(first.get_width(), area.end.x)):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func _finish() -> void:
	if failures == 0:
		print("PASS: health bars and display option")
	quit(1 if failures else 0)
