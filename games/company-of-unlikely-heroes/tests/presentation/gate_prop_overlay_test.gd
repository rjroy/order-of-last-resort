extends SceneTree
## Run: godot --path games/company-of-unlikely-heroes --script res://tests/presentation/gate_prop_overlay_test.gd
## The replacement is represented by the board's installation hook, not a production asset.

const Board = preload("res://presentation/battle/bridge_art.gd")
const GATE := Vector2i(0, 0)
const TARGET := Vector2i(1, 0)
const CELLS := {GATE: "stone", TARGET: "stone"}

var failures: Array[String] = []
var board := Board.new()
var viewport := SubViewport.new()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Gate prop overlay test requires a graphical renderer.")
		board.free()
		viewport.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE * Vector2(2, 1) + Board.GUTTER * 2.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var container := SubViewportContainer.new()
	container.add_child(viewport)
	root.add_child(container)

	var bare := await _render({})
	for open in [false, true]:
		var overlay := {"pressure_gate": {"cell": GATE, "open": open}}
		var primitive := await _render(overlay)
		_check(_changed(primitive, bare, GATE) > 0.02,
			"Default %s gate is visibly drawn" % ("open" if open else "closed"))
		board.set_pressure_gate_prop_installed(true)
		var installed := await _render(overlay)
		_check(_changed(installed, bare, GATE) == 0.0,
			"Installed replacement suppresses the primitive gate")
		_check(_changed(primitive, installed, TARGET) == 0.0,
			"Installing replacement does not change another cell")
		board.set_pressure_gate_prop_installed(false)
		var removed := await _render(overlay)
		_check(_changed(primitive, removed, GATE) == 0.0,
			"Removing or lacking replacement restores the primitive")

	var normal := await _render({"targets": [TARGET]})
	var quiet := await _render({"targets": [TARGET], "quiet_manual_move": true})
	_check(_changed(normal, bare, TARGET) > 0.01, "Default target marker is visible")
	_check(_changed(quiet, bare, TARGET) > 0.0, "Quiet target marker remains visible")
	_check(_changed(normal, quiet, TARGET) > 0.01, "Quiet Move is visibly opt-in")
	_check(board.cell_at(board.cell_center(TARGET)) == TARGET, "Quiet marker preserves hit testing")
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: gate replacement hook, fallback, and quiet target rendering")
	quit(0 if failures.is_empty() else 1)


func _render(overlay: Dictionary) -> Image:
	board.set_render_state(CELLS, [], overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _changed(first: Image, second: Image, cell: Vector2i) -> float:
	var region := Rect2i(Vector2i(board.cell_center(cell) - Board.TILE * 0.5),
		Vector2i(Board.TILE)).grow(-2)
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				changed += 1
	return float(changed) / region.get_area()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
