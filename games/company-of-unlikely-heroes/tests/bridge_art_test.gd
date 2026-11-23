extends SceneTree
## Run graphically from the repo root:
## godot --path games/company-of-unlikely-heroes --script res://tests/bridge_art_test.gd
## Add -- --capture=/absolute/path.png to save the plain, tinted, and moved-exit boards.

const Board = preload("res://bridge_art.gd")
const STONE_CELL := Vector2i(0, 0)
const BRIDGE_CELL := Vector2i(1, 0)
const BROKEN_CELL := Vector2i(2, 0)
const EXIT_ART_CELL := Vector2i(3, 0)
const WATER_CELL := Vector2i(0, 1)
const CUSTOM_CELL := Vector2i(1, 1)
const CONTROL_CELL := Vector2i(2, 1)
const CELLS := {
	STONE_CELL: "stone",
	BRIDGE_CELL: "bridge",
	BROKEN_CELL: "broken",
	EXIT_ART_CELL: "exit",
	WATER_CELL: "water",
	CUSTOM_CELL: "custom_floor",
	CONTROL_CELL: "obstacle",
	Vector2i(3, 1): "safe",
}

var failures := 0
var board := Board.new()
var viewport := SubViewport.new()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Bridge art test needs a graphical renderer; omit --headless.")
		board.free()
		viewport.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE * Vector2(4, 2) + Board.GUTTER * 2.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var preview := SubViewportContainer.new()
	preview.add_child(viewport)
	root.add_child(preview)

	var shore := {}
	for cell in CELLS:
		if cell != CONTROL_CELL:
			shore[cell] = true

	var plain := await _render(CELLS)
	var tinted := await _render(CELLS, {"safe": shore})
	for cell in shore:
		_check(_changed_fraction(plain, tinted, cell) > 0.15,
			"Shore should tint %s art at %s" % [CELLS[cell], cell])
	_check(_same_tile(plain, tinted, CONTROL_CELL), "Unmarked art must not receive shore tint")

	var alternate := CELLS.duplicate()
	alternate[STONE_CELL] = "safe"
	alternate[BRIDGE_CELL] = "stone"
	alternate[BROKEN_CELL] = "water"
	alternate[EXIT_ART_CELL] = "safe"
	var alternate_plain := await _render(alternate)
	var alternate_tinted := await _render(alternate, {"safe": shore})
	_check(_changed_fraction(tinted, alternate_tinted, STONE_CELL) > 0.15,
		"Tinted stone should retain masonry instead of becoming safe art")
	_check(_changed_fraction(tinted, alternate_tinted, BRIDGE_CELL) > 0.04,
		"Tinted bridge should retain its rim and cracks")
	_check(_changed_fraction(tinted, alternate_tinted, BROKEN_CELL) > 0.15,
		"Tinted rubble should remain distinct from tinted water")
	_check(_same_tile(plain, alternate_plain, EXIT_ART_CELL),
		"Decorative exit art must not add a lantern or EXIT label to the safe backdrop")

	var first := await _render(CELLS, {"safe": shore, "exit": BRIDGE_CELL})
	var moved := await _render(CELLS, {"safe": shore, "exit": STONE_CELL})
	_check(_changed_fraction(tinted, first, BRIDGE_CELL) > 0.04,
		"The objective should mark a bridge tile without exit art")
	_check(_same_tile(tinted, moved, BRIDGE_CELL), "Moving the objective must remove its old marker")
	_check(_same_tile(tinted, first, STONE_CELL) and _changed_fraction(tinted, moved, STONE_CELL) > 0.04,
		"The marker must follow the objective to its new tile")
	_check(_same_tile(tinted, first, EXIT_ART_CELL) and _same_tile(tinted, moved, EXIT_ART_CELL),
		"Changing the objective must not affect decorative exit art")

	# This board has no painting. Compare fixed interior and edge regions rather
	# than whole-board differences, which cannot distinguish a fill change from
	# the intended removal of tile outlines.
	board.set_grid_visible(true)
	var grid_shown := await _render(CELLS)
	board.set_grid_visible(false)
	var grid_hidden := await _render(CELLS)
	for cell in [STONE_CELL, CUSTOM_CELL, Vector2i(3, 1)]:
		var origin := Vector2i(board.cell_center(cell) - Board.TILE * 0.5)
		var interior := Rect2i(origin + Vector2i(12, 12), Vector2i(72, 56))
		var top_edge := Rect2i(origin + Vector2i(8, 2), Vector2i(80, 7))
		_check(_changed_region_fraction(grid_shown, grid_hidden, interior) < 0.01,
			"Hiding the grid preserves the tinted %s tile interior" % CELLS[cell])
		_check(_changed_region_fraction(grid_shown, grid_hidden, top_edge) > 0.05,
			"Hiding the grid removes the %s tile outline" % CELLS[cell])
	board.set_grid_visible(true)
	var grid_restored := await _render(CELLS)
	_check(grid_shown.get_data() == grid_restored.get_data(),
		"Showing the grid restores the procedural board rendering")

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_save_comparison([plain, first, moved], argument.trim_prefix("--capture="))
	if failures == 0:
		print("Bridge art test passed: shore tint preserves tile art and the exit marker follows the objective.")
	quit(1 if failures else 0)


func _render(cells: Dictionary, overlay: Dictionary = {}) -> Image:
	board.set_render_state(cells, [], overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _tile_region(cell: Vector2i) -> Rect2i:
	var full := Rect2i(Vector2i(board.cell_center(cell) - Board.TILE * 0.5), Vector2i(Board.TILE))
	return full.grow(-2)


func _same_tile(first: Image, second: Image, cell: Vector2i) -> bool:
	var region := _tile_region(cell)
	return first.get_region(region).get_data() == second.get_region(region).get_data()


func _changed_fraction(first: Image, second: Image, cell: Vector2i) -> float:
	return _changed_region_fraction(first, second, _tile_region(cell))


func _changed_region_fraction(first: Image, second: Image, region: Rect2i) -> float:
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var diff := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(diff.r), maxf(absf(diff.g), absf(diff.b))) > 4.0 / 255.0:
				changed += 1
	return float(changed) / region.get_area()


func _save_comparison(frames: Array[Image], path: String) -> void:
	var frame := frames[0]
	var sheet := Image.create(frame.get_width(), frame.get_height() * frames.size(), false, frame.get_format())
	for index in range(frames.size()):
		sheet.blit_rect(frames[index], Rect2i(Vector2i.ZERO, frame.get_size()),
			Vector2i(0, index * frame.get_height()))
	_check(sheet.save_png(path) == OK, "Could not write capture to %s" % path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
