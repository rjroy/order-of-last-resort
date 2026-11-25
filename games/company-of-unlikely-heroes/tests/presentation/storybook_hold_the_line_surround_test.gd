extends SceneTree
## Run with a graphical display from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_hold_the_line_surround_test.gd

const CastSprites = preload("res://presentation/cast/cast_sprites.gd")
const FIELD_ART := "res://assets/storybook-field/frontier-field-surround-rgba.png"
const GATE_ART := "res://assets/storybook-gate/gate-scenery-surround-wall-rgba.png"

var failures: Array[String] = []
var viewport: SubViewport
var scene: Node


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires a graphical display.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=hold_the_line"]))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", "Hold the Line launches into battle")
	if scene.current_screen() != "battle":
		_finish()
		return
	var state: Dictionary = scene.battle_snapshot()
	var page: Control = scene.get("_storybook_page")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	_check(state.get("mission_id") == "hold_the_line" and page != null and board != null,
		"Requested mission mounts its live storybook board")
	if page == null or board == null:
		_finish()
		return
	_check(page.get("_board_id") == "frontier_line_board", "Mission selects the line board")
	var scenery: TextureRect = page.get("_scenery")
	_check(scenery != null and scenery.texture != null and scenery.is_visible_in_tree(),
		"Line board selects a visible illustrated surround")
	if scenery == null or scenery.texture == null:
		_finish()
		return
	_check(scenery.texture != CastSprites.load_texture(FIELD_ART)
		and scenery.texture != CastSprites.load_texture(GATE_ART),
		"Line board selects its own surround, not the Field or Gate artwork")
	_check(scenery.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Surround does not intercept board input")
	_check((page.get("_props") as Dictionary).is_empty(), "Line board does not install Gate props")
	await _check_registration(scenery, board, state)
	var knight := {}
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == "knight":
			knight = unit
	if knight.is_empty():
		_check(false, "Hold the Line has a Knight to select")
	else:
		await _click(board.get_global_transform_with_canvas() * board.cell_center(knight.position))
		_check(scene.get("_actor_id") == "knight" and scene.battle_snapshot() == state,
			"Real board input selects the Knight without changing battle state")
		await _check_edge_occupant(scenery, board, knight.position)
	_finish()


## Compare live frames instead of prescribing the surround's artwork or colors.
func _check_registration(scenery: TextureRect, board: Control, state: Dictionary) -> void:
	# Lock the ready animation and redraw at that phase before either capture.
	# Otherwise the scenery toggle can coincide with a different cast frame.
	var previous_process_mode := board.process_mode
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.set("_ready_ms", 0.0)
	(board.get_node("CastAndUnitMarkers") as CanvasItem).queue_redraw()
	var with_art := await _frame()
	scenery.hide()
	var without_art := await _frame()
	scenery.show()
	board.process_mode = previous_process_mode
	await process_frame
	_check(with_art.get_size() == without_art.get_size(), "Compared frames have matching dimensions")
	if with_art.get_size() != without_art.get_size():
		return
	var transform := board.get_global_transform_with_canvas()
	var first: Vector2 = transform * board.cell_center(Vector2i.ZERO)
	var step: Vector2 = transform * board.cell_center(Vector2i.ONE) - first
	var last: Vector2 = transform * board.cell_center(Vector2i(state.width - 1, state.height - 1))
	# Use the whole playable footprint, excluding only partially covered edge pixels.
	var start := first - step * 0.5
	var end := last + step * 0.5
	var grid := Rect2i(Vector2i(ceili(start.x), ceili(start.y)),
		Vector2i(floori(end.x) - ceili(start.x), floori(end.y) - ceili(start.y)))
	var bounds := Rect2i(Vector2i.ZERO, with_art.get_size())
	_check(grid.get_area() > 0 and bounds.encloses(grid), "Playable grid is inside the rendered frame")
	if grid.get_area() <= 0 or not bounds.encloses(grid):
		return
	_check(_changed_samples(with_art, without_art, grid, 1) == 0,
		"Surround leaves the playable grid unchanged, including occupied cells")
	var page: Control = scene.get("_storybook_page")
	var edge: float = page.get_script().get_script_constant_map().get("EDGE")
	var rail_top: float = page.get("_rail_top")
	var page_origin: Vector2 = page.get_global_transform_with_canvas() * Vector2.ZERO
	var left := Rect2i(ceili(page_origin.x + edge), ceili(start.y),
		floori(start.x - page_origin.x - edge), floori(end.y - start.y))
	var right := Rect2i(ceili(end.x), ceili(start.y),
		floori(page_origin.x + page.size.x - edge - end.x), floori(end.y - start.y))
	_check(left.get_area() > 0 and _changed_samples(with_art, without_art, left) > 0,
		"Surround contributes visible artwork on the left margin")
	_check(right.get_area() > 0 and _changed_samples(with_art, without_art, right) > 0,
		"Surround contributes visible artwork on the right margin")
	var rail := Rect2i(0, ceili(page_origin.y + rail_top + 2.0),
		bounds.size.x, bounds.size.y - ceili(page_origin.y + rail_top + 2.0))
	_check(rail.get_area() > 0 and bounds.encloses(rail)
		and _changed_samples(with_art, without_art, rail, 1) == 0,
		"Surround leaves the rail and controls unchanged")
	var frame_width := floori(edge - 1.0)
	var frame_regions := [
		Rect2i(0, 0, bounds.size.x, frame_width),
		Rect2i(0, 0, frame_width, bounds.size.y),
		Rect2i(bounds.size.x - frame_width, 0, frame_width, bounds.size.y),
	]
	for region: Rect2i in frame_regions:
		_check(_changed_samples(with_art, without_art, region, 1) == 0,
			"Surround leaves the book frame unchanged")


func _changed_samples(first: Image, second: Image, region: Rect2i, stride := 4) -> int:
	var changed := 0
	for y in range(region.position.y, region.end.y, stride):
		for x in range(region.position.x, region.end.x, stride):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
				changed += 1
	return changed


func _check_edge_occupant(scenery: TextureRect, board: Control, knight_position: Vector2i) -> void:
	var destination := Vector2i(3, 0)
	_check(knight_position == Vector2i(3, 1), "Knight starts immediately below D1")
	if knight_position != Vector2i(3, 1):
		return
	var transform := board.get_global_transform_with_canvas()
	await _click(transform * board.cell_center(destination))
	var planned: Dictionary = scene.get("_planned_state")
	var command: Dictionary = planned.get("overrides", {}).get("knight", {})
	_check(command.get("ability_id") == "move" and command.get("target_id") == "3,0",
		"Knight's D1 move is staged through the board")
	if command.get("ability_id") != "move" or command.get("target_id") != "3,0":
		return
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit == null or commit.disabled or not commit.is_visible_in_tree():
		_check(false, "Commit is available for the D1 move")
		return
	await _click(commit.get_global_rect().get_center())
	var moved := false
	for unit: Dictionary in scene.battle_snapshot().get("units", []):
		if unit.get("id") == "knight" and unit.get("position") == destination:
			moved = true
	_check(moved, "Committed Knight occupies D1")
	if not moved:
		return
	# Finish action playback, then hold the same ready pose for all four frames.
	board._process((board.action_playback_remaining_ms() + 1.0) / 1000.0)
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.set("_ready_ms", 0.0)
	var figures := board.get_node("CastAndUnitMarkers") as CanvasItem
	figures.queue_redraw()
	var with_both := await _frame()
	figures.hide()
	var scenery_only := await _frame()
	scenery.hide()
	var neither := await _frame()
	figures.show()
	var figures_only := await _frame()
	scenery.show()
	board.process_mode = Node.PROCESS_MODE_INHERIT

	# Measure the figure's contribution above D1, outside the aperture. Compare
	# the two backgrounds rather than any particular artwork or hair color.
	var center: Vector2 = transform * board.cell_center(destination)
	var step: Vector2 = transform * board.cell_center(Vector2i.ONE) - transform * board.cell_center(Vector2i.ZERO)
	var top := center.y - step.y * 0.5
	var region := Rect2i(Rect2(Vector2(center.x - step.x * 0.5, top - step.y * 0.5),
		Vector2(step.x, step.y * 0.5))).intersection(Rect2i(Vector2i.ZERO, with_both.get_size()))
	var baseline := 0.0
	var actual := 0.0
	var visible_pixels := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var difference := _pixel_distance(figures_only.get_pixel(x, y), neither.get_pixel(x, y))
			if difference > 20.0 / 255.0:
				baseline += difference
				actual += _pixel_distance(with_both.get_pixel(x, y), scenery_only.get_pixel(x, y))
				visible_pixels += 1
	_check(visible_pixels > 8, "Knight has visible foreground pixels above the D1 grid edge")
	_check(baseline > 0.0 and actual >= baseline * 0.85,
		"Line surround preserves the edge Knight's foreground contribution above the grid")


func _pixel_distance(first: Color, second: Color) -> float:
	var delta := first - second
	return maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b)))


func _frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		viewport.push_input(event, true)
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: Hold the Line registered surround and board input")
	quit(0 if failures.is_empty() else 1)
