extends SceneTree
## Run with a graphical display from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_bridge_surround_scene_test.gd

const CastSprites = preload("res://presentation/cast/cast_sprites.gd")
const Rules = preload("res://rules/rules.gd")
const FIELD_ART := "res://assets/storybook-field/frontier-field-surround-rgba.png"
const LINE_ART := "res://assets/storybook-surrounds/frontier_line_board.png"
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
	scene.configure_launch(PackedStringArray(["--mission=bridge_is_out"]))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", "The Bridge Is Out launches into battle")
	if scene.current_screen() != "battle":
		_finish()
		return
	var state: Dictionary = scene.battle_snapshot()
	var page: Control = scene.get("_storybook_page")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	var markers := scene.find_child("ObjectiveMarkers", true, false) as Control
	_check(state.get("mission_id") == "bridge_is_out" and page != null and board != null,
		"Requested mission mounts its live storybook board")
	if page == null or board == null:
		_finish()
		return
	_check(page.get("_board_id") == "frontier_bridge_board", "Mission selects the bridge board")
	var scenery: TextureRect = page.get("_scenery")
	_check(scenery != null and scenery.texture != null and scenery.is_visible_in_tree(),
		"Bridge board selects a visible illustrated surround")
	if scenery != null and scenery.texture != null:
		_check(board.foreground_above_scenery(),
			"Registered bridge surround uses the tactical foreground layout")
		_check(scenery.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"Bridge surround does not intercept input")
		for path: String in [FIELD_ART, LINE_ART, GATE_ART]:
			_check(scenery.texture != CastSprites.load_texture(path),
				"Bridge board selects its own surround, not " + path)
		await _check_wings_and_channel(page, board, scenery, state)
		await _check_forecast_wing(page, board, scenery, state)
	await _check_collapse_stamps(board, markers, state)
	_finish()


func _check_wings_and_channel(page: Control, board: Control, scenery: TextureRect, state: Dictionary) -> void:
	var previous_mode := board.process_mode
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.set("_ready_ms", 0.0)
	(board.get_node("CastAndUnitMarkers") as CanvasItem).queue_redraw()
	var with_art := await _frame()
	scenery.hide()
	var without_art := await _frame()
	scenery.show()
	board.process_mode = previous_mode
	if with_art.get_size() != without_art.get_size():
		_check(false, "Compared bridge frames have matching dimensions")
		return
	var transform := board.get_global_transform_with_canvas()
	var first: Vector2 = transform * board.cell_center(Vector2i.ZERO)
	var step: Vector2 = transform * board.cell_center(Vector2i.ONE) - first
	var last: Vector2 = transform * board.cell_center(Vector2i(state.width - 1, state.height - 1))
	var start := first - step * 0.5
	var end := last + step * 0.5
	var bounds := Rect2i(Vector2i.ZERO, with_art.get_size())
	var edge: float = page.get_script().get_script_constant_map().get("EDGE")
	var origin: Vector2 = page.get_global_transform_with_canvas() * Vector2.ZERO
	var left := Rect2i(ceili(origin.x + edge), ceili(start.y),
		floori(start.x - origin.x - edge), floori(end.y - start.y))
	var right := Rect2i(ceili(end.x), ceili(start.y),
		floori(origin.x + page.size.x - edge - end.x), floori(end.y - start.y))
	for wing: Rect2i in [left, right]:
		_check(wing.get_area() > 0 and bounds.encloses(wing)
			and _changed(with_art, without_art, wing, 4) > 0,
			"Bridge surround visibly contributes to each side wing")
	# Keep the original water, banks and deck through the entire middle channel,
	# not merely through the 35 playable cells.
	var x0 := ceili(start.x) + 1
	var x1 := floori(end.x) - 1
	var channel := Rect2i(x0, 0, x1 - x0, bounds.size.y)
	_check(channel.get_area() > 0 and bounds.encloses(channel)
		and _changed(with_art, without_art, channel, 1) == 0,
		"Bridge surround preserves the full original central channel above and below the grid")


func _check_forecast_wing(page: Control, board: Control, scenery: TextureRect, state: Dictionary) -> void:
	var forecast := scene.find_child("ForecastDetails", true, false) as BaseButton
	var leaf := scene.find_child("ExtraDetails", true, false) as Control
	if forecast == null or leaf == null or not forecast.is_visible_in_tree():
		_check(false, "Bridge has a visible Forecast control and leaf")
		return
	var previous_mode := board.process_mode
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.set("_ready_ms", 0.0)
	(board.get_node("CastAndUnitMarkers") as CanvasItem).queue_redraw()
	for viewport_size: Vector2i in [Vector2i(1280, 820), Vector2i(1000, 700)]:
		viewport.size = viewport_size
		await _frame()
		var closed_transform := board.get_global_transform_with_canvas()
		var closed_first: Vector2 = closed_transform * board.cell_center(Vector2i.ZERO)
		var closed_step: Vector2 = closed_transform * board.cell_center(Vector2i.ONE) - closed_first
		var closed_last: Vector2 = closed_transform * board.cell_center(Vector2i(state.width - 1, 0))
		var closed_end := closed_last.x + closed_step.x * 0.5
		var edge: float = page.get_script().get_script_constant_map().get("EDGE")
		var origin: Vector2 = page.get_global_transform_with_canvas() * Vector2.ZERO
		var frame_right := origin.x + page.size.x - edge
		var reference_wing_cells := (frame_right - closed_end) / closed_step.x
		forecast.pressed.emit()
		await _frame()
		_check(leaf.is_visible_in_tree() and not leaf.get_global_rect().intersects(board.get_global_rect()),
			"%s Forecast opens without covering the live board" % str(viewport_size))
		var transform := board.get_global_transform_with_canvas()
		var first: Vector2 = transform * board.cell_center(Vector2i.ZERO)
		var step: Vector2 = transform * board.cell_center(Vector2i.ONE) - first
		var last: Vector2 = transform * board.cell_center(Vector2i(state.width - 1, 0))
		var grid_right := last.x + step.x * 0.5
		var header: Control = page.get("_header")
		var sample_top := ceili(header.get_global_rect().end.y + 2.0)
		var sample_bottom := floori(leaf.get_global_rect().position.y - 2.0)
		# Keep the original wing's extent in board-cell units, with a quarter
		# cell of transition room. Space farther away belongs to the backdrop,
		# not an ever-stretched copy of the narrow registered wing.
		var near := Rect2i(ceili(grid_right + step.x * 0.15), sample_top,
			floori(step.x * 0.7), sample_bottom - sample_top)
		var far_x := ceili(grid_right + step.x * (reference_wing_cells + 0.25))
		var far := Rect2i(far_x, sample_top, floori(frame_right) - far_x, sample_bottom - sample_top)
		var bounds := Rect2i(Vector2i.ZERO, viewport.size)
		var shown := await _frame()
		scenery.hide()
		var hidden := await _frame()
		scenery.show()
		_check(near.get_area() > 0 and bounds.encloses(near) and _changed(shown, hidden, near, 4) > 0,
			"%s Forecast retains illustrated scenery beside the board" % str(viewport_size))
		_check(far.get_area() > 0 and bounds.encloses(far) and _changed(shown, hidden, far, 1) == 0,
			"%s Forecast does not stretch registered wing art across the distant backdrop" % str(viewport_size))
		for unit: Dictionary in state.get("units", []):
			if unit.get("id") == "knight":
				await _click(transform * board.cell_center(unit.position))
				_check(scene.get("_actor_id") == "knight" and scene.battle_snapshot() == state,
					"%s Forecast leaves real board selection available without committing" % str(viewport_size))
				break
		forecast.pressed.emit()
		await _frame()
	viewport.size = Vector2i(1280, 820)
	board.process_mode = previous_mode
	await _frame()


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


func _check_collapse_stamps(board: Control, markers: Control, state: Dictionary) -> void:
	if markers == null:
		_check(false, "Bridge has an objective marker layer")
		return
	var expected: Dictionary = Rules.new().objective_markers(state)
	var scheduled: Array = state.objective.get("collapses", [])
	_check(scheduled.size() == 2, "Bridge has both scheduled span collapses")
	if scheduled.size() != 2:
		return
	var previous_mode := board.process_mode
	# Keep the mounted layout and figures intact: only the stamp layer changes.
	# Reapplying the foreground mode here would mask a failed attach-time sync.
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.set("_ready_ms", 0.0)
	var figures := board.get_node("CastAndUnitMarkers") as CanvasItem
	figures.queue_redraw()
	var shown := await _frame()
	markers.hide()
	var hidden := await _frame()
	markers.show()
	board.process_mode = previous_mode
	var transform := board.get_global_transform_with_canvas()
	var step: Vector2 = transform * board.cell_center(Vector2i.ONE) \
		- transform * board.cell_center(Vector2i.ZERO)
	var count := 0
	for collapse: Dictionary in scheduled:
		for cell: Vector2i in collapse.get("cells", []):
			count += 1
			var mark: Dictionary = expected.get(cell, {})
			_check(mark.get("kind") == "collapse", "Scheduled %s has a collapse marker" % cell)
			# Use a whole cell, not fixed stamp colors or a screenshot reference.
			var center: Vector2 = transform * board.cell_center(cell)
			var region := Rect2i(Rect2(center - step * 0.45, step * 0.9))
			_check(_changed(shown, hidden, region, 1) > 4,
				"Collapse stamp visibly contributes over the deck at %s" % cell)
	_check(count == 6, "Both collapse spans contain six scheduled stamp cells")


func _changed(first: Image, second: Image, region: Rect2i, stride: int) -> int:
	var changed := 0
	var bounds := Rect2i(Vector2i.ZERO, first.get_size())
	var clipped := region.intersection(bounds)
	for y in range(clipped.position.y, clipped.end.y, stride):
		for x in range(clipped.position.x, clipped.end.x, stride):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
				changed += 1
	return changed


func _frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: Bridge Is Out surround and collapse stamps")
	quit(0 if failures.is_empty() else 1)
