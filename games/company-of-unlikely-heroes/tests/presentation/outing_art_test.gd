extends SceneTree
## Run graphically: godot --path games/company-of-unlikely-heroes --script res://tests/presentation/outing_art_test.gd
## Add -- --capture=/absolute/path.png to save the test fixture, not an actual mission.

const Board = preload("res://presentation/battle/bridge_art.gd")
const CELL := Vector2i.ZERO
const NEIGHBOR := Vector2i.RIGHT
const CELLS := {CELL: "stone", NEIGHBOR: "stone"}
const ROLES := ["goblin", "hookhand", "bruiser", "village_troll"]

var board := Board.new()
var viewport := SubViewport.new()
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Outing art test needs a graphical renderer; omit --headless.")
		board.free()
		viewport.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE * Vector2(2, 1) + Board.GUTTER * 2.0)
	board.size = Vector2(viewport.size)
	var preview := SubViewportContainer.new()
	viewport.add_child(board)
	preview.add_child(viewport)
	root.add_child(preview)

	var empty := await _render()
	var figures := _tile(CELL).grow_individual(0, 3, 0, -22)
	var fallback := await _render("unknown_art")
	var harpooner := await _render("enemy", "spear")
	var frames: Array[Image] = [fallback, harpooner]
	for role in ROLES:
		var figure := await _render(role)
		_check(_silhouette_difference(figure, fallback, empty, figures) > 0.06,
			"%s should have a silhouette distinct from the raw fallback" % role)
		for other in range(1, frames.size()):
			var other_role: String = "harpooner" if other == 1 else ROLES[other - 2]
			_check(_silhouette_difference(figure, frames[other], empty, figures) > 0.06,
				"%s and %s should have distinct silhouettes" % [role, other_role])
		frames.append(figure)

	var occupied := frames.back() as Image
	var zone := {"objective_zone": [[0, 0], [5, 0]]}
	var empty_zone := await _render("", "", zone)
	_check(_changed_fraction(empty_zone, empty, _tile(CELL)) > 0.1,
		"The objective marking must make the empty square legible")
	var occupied_zone := await _render("village_troll", "", zone)
	var left_edge := Rect2i(_tile(CELL).position, Vector2i(17, 80))
	var right_edge := Rect2i(_tile(CELL).position + Vector2i(79, 0), Vector2i(17, 80))
	_check(_changed_fraction(occupied_zone, occupied, left_edge) > 0.08
		and _changed_fraction(occupied_zone, occupied, right_edge) > 0.08,
		"The occupied objective square must retain visible markings on both sides")
	_check(_changed_fraction(occupied_zone, occupied, _tile(NEIGHBOR)) == 0.0,
		"Objective paint must not spill into an unmarked cell")
	var moved := await _render("village_troll", "", {"objective_zone": [NEIGHBOR]})
	_check(_changed_fraction(moved, occupied, _tile(CELL)) == 0.0
		and _changed_fraction(moved, occupied, _tile(NEIGHBOR)) > 0.1,
		"The markings must follow the supplied cells and clear an old objective")

	var tactical := zone.merged({"selected": CELL, "commanded": CELL, "impact": [CELL],
		"paths": [[CELL, NEIGHBOR]]})
	var combined := await _render("village_troll", "", tactical)
	var tile := _tile(CELL).position
	var hp := Rect2i(tile + Vector2i(36, 69), Vector2i(26, 3))
	_check(_changed_fraction(combined, occupied, hp) == 0.0,
		"The zone and tactical overlays must not alter the occupied tile's HP pips")
	_check(_changed_fraction(combined, occupied_zone, Rect2i(tile, Vector2i(20, 20))) > 0.04,
		"Selection brackets must remain visible above the objective mark")
	_check(_changed_fraction(combined, occupied_zone, Rect2i(tile + Vector2i(64, 0), Vector2i(32, 26))) > 0.04,
		"Command/impact annotations must remain visible above the objective mark")
	_check(_changed_fraction(combined, occupied_zone, _tile(NEIGHBOR)) > 0.01,
		"Forecast paths must remain visible when they leave the objective")
	frames.append(empty_zone)
	frames.append(combined)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_save_comparison(frames, argument.trim_prefix("--capture="))

	if failures == 0:
		print("Outing art test passed: distinct silhouettes; objective squares remain legible with occupants and overlays.")
	quit(1 if failures else 0)


func _render(role := "", variant := "", overlay: Dictionary = {}) -> Image:
	var units := []
	if not role.is_empty():
		units.append({"id": role, "art_key": role, "variant": variant, "cell": CELL,
			"hp": 3, "max_hp": 5, "facing": -1})
	board.set_render_state(CELLS, units, overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _tile(cell: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(board.cell_center(cell) - Board.TILE * 0.5), Vector2i(Board.TILE))


func _contrasts(a: Color, b: Color) -> bool:
	var delta := a - b
	return maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0


func _changed_fraction(first: Image, second: Image, region: Rect2i) -> float:
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if _contrasts(first.get_pixel(x, y), second.get_pixel(x, y)):
				changed += 1
	return float(changed) / region.get_area()


# Compare coverage rather than colors, so tinting the fallback pawn does not pass.
func _silhouette_difference(first: Image, second: Image, empty: Image, region: Rect2i) -> float:
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var backdrop := empty.get_pixel(x, y)
			if _contrasts(first.get_pixel(x, y), backdrop) != _contrasts(second.get_pixel(x, y), backdrop):
				changed += 1
	return float(changed) / region.get_area()


func _save_comparison(frames: Array[Image], path: String) -> void:
	var extent := Vector2i(102, 86)
	var sheet := Image.create(extent.x * 4, extent.y * 2, false, frames[0].get_format())
	for index in frames.size():
		@warning_ignore("integer_division")
		var position := Vector2i(index % 4, index / 4) * extent
		sheet.blit_rect(frames[index], _tile(CELL).grow(3), position)
	_check(sheet.save_png(path) == OK, "Could not write the fixture to %s" % path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
