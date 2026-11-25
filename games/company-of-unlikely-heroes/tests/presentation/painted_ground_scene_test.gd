extends SceneTree
## Run graphically from the repo root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/painted_ground_scene_test.gd
## Uses an external copy of the stock catalog to test an identical, ID-colliding custom board.

var failures: Array[String] = []
var scene: Node
var board: Control
var preview: SubViewportContainer
var viewport: SubViewport
var fixture := "user://painted_ground_catalog_%d.json" % OS.get_process_id()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Painted ground scene test requires a graphical renderer.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	var catalog: Dictionary = load("res://content/catalog.gd").read_default()
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	if catalog.is_empty() or file == null:
		_check(false, "Can create the external catalog fixture")
		_finish()
		return
	file.store_string(JSON.stringify(catalog))
	file.close()

	await _launch("hold_the_line")
	var line_cells: Dictionary = board.get("_cells").duplicate()
	var line := await _render(line_cells)
	await _launch("great_sheep_escape")
	var sheep_cells: Dictionary = board.get("_cells").duplicate()
	var sheep := await _render(sheep_cells)
	_check(line_cells == sheep_cells, "The two stock missions use identical underlying terrain")
	_check(_difference(line, sheep, Rect2i(Vector2i.ZERO, line.get_size())) > 0.25,
		"Different stock board IDs show distinct painted ground even with identical terrain")

	await _launch("bridge_is_out")
	var bridge_cells: Dictionary = board.get("_cells").duplicate()
	var intact := await _render(bridge_cells)
	var marked := await _render(bridge_cells, {"selected": Vector2i(2, 2)})
	var selected_region := _cell_region(Vector2i(2, 2))
	_check(_difference(intact, marked, selected_region) > 0.01,
		"Selection remains visible on painted ground")
	_check(board.cell_at(board.cell_center(Vector2i(2, 2))) == Vector2i(2, 2),
		"Painted ground preserves grid hit testing")
	var collapsed_cells := bridge_cells.duplicate()
	collapsed_cells[Vector2i(2, 2)] = "broken"
	var collapsed := await _render(collapsed_cells)
	_check(_difference(intact, collapsed, selected_region) > 0.05,
		"A collapsed bridge cell visibly changes")
	var unchanged_region := _cell_region(Vector2i(5, 2)).grow(-5)
	_check(_difference(intact, collapsed, unchanged_region) < 0.01,
		"Collapse retains the stock painted ground outside the changed cell")

	await _launch("bridge_is_out", ProjectSettings.globalize_path(fixture))
	var custom_cells: Dictionary = board.get("_cells").duplicate()
	var custom := await _render(custom_cells)
	_check(custom_cells == bridge_cells, "Custom collision fixture preserves stock geometry and terrain")
	_check(_difference(intact, custom, Rect2i(Vector2i.ZERO, intact.get_size())) > 0.25,
		"External catalog with the same board ID uses fallback, not stock painted ground")
	_check(board.cell_at(board.cell_center(Vector2i(2, 2))) == Vector2i(2, 2),
		"Fallback preserves grid hit testing")
	_finish()


func _launch(mission: String, content := "") -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	var args := PackedStringArray(["--mission=" + mission])
	if not content.is_empty():
		args.append("--content=" + content)
	scene.configure_launch(args)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	board = scene.find_child("BridgeBoard", true, false) as Control
	_check(scene.current_screen() == "battle" and board != null, mission + " launches its battle board")
	if board == null:
		_finish()
		return
	# Retain the actual scene-configured board but give every capture the same extent.
	preview = SubViewportContainer.new()
	viewport = SubViewport.new()
	viewport.size = Vector2i(734, 468)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	root.add_child(preview)
	board.reparent(viewport)
	board.position = Vector2.ZERO
	board.size = Vector2(viewport.size)


func _render(cells: Dictionary, overlay: Dictionary = {}) -> Image:
	board.set_render_state(cells, [], overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _cell_region(cell: Vector2i) -> Rect2i:
	var center: Vector2 = board.cell_center(cell)
	var scale_factor: float = board.get("_map_scale")
	var extent := Vector2(96, 80) * scale_factor
	return Rect2i(Vector2i(center - extent * 0.5), Vector2i(extent))


func _difference(first: Image, second: Image, region: Rect2i) -> float:
	if first.get_size() != second.get_size() or region.get_area() <= 0:
		_check(false, "Compared board images have equal, nonempty dimensions")
		return 0.0
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
				changed += 1
	return float(changed) / region.get_area()


func _finish() -> void:
	if FileAccess.file_exists(fixture):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture)) == OK,
			"Temporary catalog fixture was removed")
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: stock painted ground, fallback, grid overlays, and collapse")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
