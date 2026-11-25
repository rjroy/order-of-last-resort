extends SceneTree

const Crossing := preload("res://crossing.tscn")
const Layout := preload("res://crossing_layout.gd")
const View := preload("res://crossing_view.gd")

var _failures: PackedStringArray


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Crossing.instantiate()
	root.add_child(scene)
	await process_frame
	var board: View = scene.get_node("Board")
	_check(board.art_errors.is_empty(), "Source PNGs and sheets load: " + "; ".join(board.art_errors))
	_check_authored_cells(board)
	_check_click_and_overlays(board)
	_check_crate(board)
	_check_actions(board)
	if _failures.is_empty():
		print("PASS: assets, all authored cells, click/selection, bridge, threat, shadows, play-size, crate, guard and heal")
		quit()
	else:
		for failure: String in _failures:
			printerr("FAIL: " + failure)
		quit(1)


func _check_authored_cells(board: View) -> void:
	var production := ProjectSettings.globalize_path("res://").path_join(
			"../../../../../../../games/company-of-unlikely-heroes/content")
	var common: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			production.path_join("shared/common.json").simplify_path()))
	_check(common is Dictionary, "Read authored shared/common.json")
	if not common is Dictionary:
		return
	var authored: Dictionary = common.boards.bridge
	var dimensions := Vector2i(authored.width, authored.height)
	_check(dimensions == Layout.GRID_SIZE, "Projection has the authored board dimensions")
	var shore: Array[Vector2i] = []
	for at: Array in authored.shore_cells:
		shore.append(Vector2i(at[0], at[1]))
	var bridge_cells: Array[Vector2i] = []
	for tile: Dictionary in authored.tiles:
		if tile.type == "bridge":
			bridge_cells.append(Vector2i(tile.at[0], tile.at[1]))
	_check(bridge_cells.size() == 1 and bridge_cells.has(Layout.SPAN),
			"D3 is the only authored bridge cell")
	_check(Layout.project(Vector2(Layout.SPAN)).is_equal_approx(Vector2(768, 522)),
			"D3 registration matches the guide")
	for y in dimensions.y:
		for x in dimensions.x:
			var cell := Vector2i(x, y)
			var center := Layout.project(Vector2(cell))
			_check(Layout.cell_at(center) == cell, "Center rounds back to " + Layout.address(cell))
			board.set_span_intact(true)
			_check(board.can_select(cell) == (shore.has(cell) or bridge_cells.has(cell)),
					"Authored intact passability at " + Layout.address(cell))
			board.set_span_intact(false)
			_check(board.can_select(cell) == shore.has(cell),
					"Authored absent passability at " + Layout.address(cell))
	board.set_span_intact(true)


func _check_click_and_overlays(board: View) -> void:
	_click(board, Layout.HEALER)
	_check(board.selected == Layout.HEALER, "A2 hit registers through the board transform")
	_click(board, Vector2i(3, 3))
	_check(board.selected == Layout.HEALER, "Gap ignores click")
	_click(board, Layout.SPAN)
	_check(board.selected == Layout.SPAN, "Intact bridge is selectable")
	board.set_span_intact(false)
	_check(board.selected == Layout.INVALID, "Removing the bridge clears the invalid selection")
	_click(board, Layout.SPAN)
	_check(board.selected == Layout.INVALID, "Water does not accept clicks")
	board.set_span_intact(true)
	var full_scale := board.board_transform().x.length()
	board.set_display(&"play_size", true)
	var stress_scale := board.board_transform().x.length()
	_check(stress_scale < full_scale and is_equal_approx(stress_scale * Layout.COLUMN.x, 65.0),
			"Play-size mode scales to a 65 px tile")
	_click(board, Vector2i(4, 2))
	_check(board.selected == Vector2i(4, 2), "Hit testing tracks the new size")
	board.set_display(&"threat", false)
	board.set_display(&"selection", false)
	board.set_display(&"shadows", false)
	_check(not board.threat_visible and not board.selection_visible and not board.shadows_visible,
			"Overlay toggles are independent")
	_check(board.selected == Vector2i(4, 2), "Hiding a mark preserves picked tile")
	for layer: StringName in [&"threat", &"selection", &"shadows"]:
		board.set_display(layer, true)
	_check(board.threat_visible and board.selection_visible and board.shadows_visible, "Restore marks")


func _click(board: View, cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = board.board_transform() * Layout.project(Vector2(cell))
	board._gui_input(event)


func _check_crate(board: View) -> void:
	var start := Layout.project(Vector2(Layout.CRATE_START))
	var finish := Layout.project(Vector2(Layout.CRATE_END))
	board.select_cell(Layout.CRATE_START)
	board.set_span_intact(false)
	_check(board.move_crate(), "Start crate move without span")
	_check(not board.move_crate(), "Ignore repeat while crate is moving")
	_check(board.crate_cell == Layout.CRATE_END, "Crate advances one authored shore tile")
	_check(board.selected == Layout.CRATE_END, "The selection follows the picked crate")
	_check(board.crate_foot().is_equal_approx(start), "Crate interpolation begins at old contact")
	board._process(View.CRATE_SLIDE_SECONDS / 2.0)
	_check(board.crate_foot().is_equal_approx(start.lerp(finish, 0.5)), "Contact moves with crate")
	board._process(View.CRATE_SLIDE_SECONDS)
	_check(board.crate_foot().is_equal_approx(finish), "Crate ends centered on its new tile")
	_check(board.move_crate(), "Crate can return to its original tile")


func _check_actions(board: View) -> void:
	for actor: StringName in [View.KNIGHT, View.HEALER]:
		board.play_action(actor)
		_check(board.frame_index(actor) == 0, String(actor) + " starts at frame 0")
		board._process(0.42)
		_check(board.frame_index(actor) > 0, String(actor) + " advances through timed frames")
		board.play_action(actor)
		_check(board.frame_index(actor) == 0, String(actor) + " replay rewinds")
		board._process(10.0)
		_check(board.frame_index(actor) == 0, String(actor) + " rests at the first pose again")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
