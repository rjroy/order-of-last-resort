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
var draws := {"board": 0, "tactical": 0, "figures": 0}


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
	board.draw.connect(func(): draws.board += 1)
	board.get("_tactical").draw.connect(func(): draws.tactical += 1)
	board.get("_figures").draw.connect(func(): draws.figures += 1)

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
	await _pushed_obstacle_timing()
	for split in [false, true]:
		await _invalidation(split)

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_save_comparison([plain, first, moved], argument.trim_prefix("--capture="))
	if failures == 0:
		print("Bridge art test passed: terrain, objective, obstacle timing and layer redraws.")
	quit(1 if failures else 0)


func _render(cells: Dictionary, overlay: Dictionary = {}) -> Image:
	board.set_render_state(cells, [], overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _pushed_obstacle_timing() -> void:
	var rules = preload("res://rules.gd").new()
	var defs: Dictionary = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(
		preload("res://content/catalog.gd").read_default())
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 4
	state.height = 2
	state.default_tile = "stone"
	state.terrain = []
	state.units = [{"id": "knight", "character_id": "knight", "position": Vector2i(0, 1),
		"hp": 10, "max_hp": 10, "statuses": {}}]
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": CUSTOM_CELL,
		"hp": 10, "max_hp": 10, "statuses": {}}]
	state.orders = {}
	state.overrides = {}
	var plan: Dictionary = rules.preview(state, "knight", "knight_push", "crate")
	_check(plan.get("valid", false), "Crate push fixture resolves")
	if not plan.get("valid", false):
		return
	_check(plan.result.obstacles[0].position == CONTROL_CELL, "Crate really moves to the next tile")
	var cues: Array = preload("res://presentation/cast_cues.gd").build(state, plan.result, plan.events, true)
	var bare := await _render(CELLS)
	board.clear_action_playback()
	board.set_render_state(CELLS, [], {"obstacles": [{"id": "crate", "art_key": "crate",
		"position": CONTROL_CELL, "hp": 10, "max_hp": 10}]})
	board.play_committed_actions(cues)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image()
	_check(_changed_fraction(bare, before, CUSTOM_CELL) > 0.04 \
		and _same_tile(bare, before, CONTROL_CELL),
		"Pushed crate remains visibly at its source before impact")
	board._process((board.action_playback_remaining_ms() + 1.0) / 1000.0)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image()
	_check(_same_tile(bare, after, CUSTOM_CELL) and _changed_fraction(bare, after, CONTROL_CELL) > 0.04,
		"Pushed crate visibly lands at the destination after impact")
	await _blocked_obstacle_contact(state, rules)


func _blocked_obstacle_contact(state: Dictionary, rules) -> void:
	state.obstacles.append({"id": "wall", "object_id": "crate", "position": CONTROL_CELL,
		"hp": 10, "max_hp": 10, "statuses": {}})
	var plan: Dictionary = rules.preview(state, "knight", "knight_push", "crate")
	_check(plan.get("valid", false), "Blocked crate Push fixture resolves")
	if not plan.get("valid", false):
		return
	_check(plan.result.obstacles[0].position == CUSTOM_CELL and plan.events.any(
		func(event): return event.get("type") == "damage" and event.get("target_id") == "crate" \
			and int(event.get("amount", 0)) > 0),
		"Blocked Push actually damages the unmoved crate")
	var cues: Array = preload("res://presentation/cast_cues.gd").build(state, plan.result, plan.events, true)
	var overlay := {"obstacles": [
		{"id": "crate", "art_key": "crate", "position": CUSTOM_CELL,
			"hp": plan.result.obstacles[0].hp, "max_hp": 10},
		{"id": "wall", "art_key": "crate", "position": CONTROL_CELL, "hp": 10, "max_hp": 10}]}
	board.clear_action_playback()
	var before := await _render(CELLS, overlay)
	board.play_committed_actions(cues)
	board.set_process(false)
	var entries: Array = board.get("_playback").get("_entries")
	var actions := entries.filter(func(entry): return entry.cue.get("unit_id") == "knight")
	if actions.is_empty():
		_check(false, "Clipless blocked Push still has an impact moment")
		return
	board._process((actions[0].impact_ms - actions[0].elapsed_ms + 40.0) / 1000.0)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var impact := viewport.get_texture().get_image()
	_check(_changed_fraction(before, impact, CUSTOM_CELL) > 0.001,
		"Clipless blocked Push shows visible contact feedback on the damaged crate")


func _invalidation(split: bool) -> void:
	var mode := "split" if split else "combined"
	board.clear_action_playback()
	board.set_foreground_above_scenery(split)
	board.set_render_state(CELLS, [
		{"id": "idle", "art_key": "healer", "cast_key": "healer", "cell": STONE_CELL}
	], {"obstacles": [{"id": "crate", "art_key": "crate", "position": CONTROL_CELL,
		"hp": 10, "max_hp": 10}]})
	board.set_process(false)
	var ready = board.get("_cast").clip_for("healer", "ready")
	if ready == null or not ready.loop or ready.frame_ends.size() < 2:
		_check(false, "Animated idle fixture is available")
		return
	var rate: float = board.get("_ready_rates")["idle"]
	board.set("_ready_ms", (ready.frame_ends[0] - 1.0) / rate)
	await _flush_draws()
	_reset_draws()
	board._process(2.0 / rate / 1000.0)
	board.set_process(false)
	await _flush_draws()
	_check(draws.figures > 0, "%s: idle frame redraws figures" % mode)
	_check(draws.board == 0 and draws.tactical == 0,
		"%s: idle frame does not redraw board or tactical layer" % mode)

	# A silent action carries a deterministic obstacle displacement, while a
	# later action keeps playback alive after the crate has settled.
	var destination_image := viewport.get_texture().get_image()
	var cues := [
		{"unit_id": "actor", "silent_action": true, "motions": [
			{"unit_id": "crate", "from": CUSTOM_CELL, "to": CONTROL_CELL}]},
		{"unit_id": "later", "silent_action": true},
	]
	_reset_draws()
	board.play_committed_actions(cues)
	board.set_process(false)
	await _flush_draws()
	var source_image := viewport.get_texture().get_image()
	_check(draws.tactical > 0 if split else draws.board > 0,
		"%s: enqueue redraws the obstacle's layer" % mode)
	if split:
		_check(draws.board == 0, "split: enqueue leaves terrain alone")
	_check(_changed_fraction(destination_image, source_image, CUSTOM_CELL) > 0.001 \
		and _changed_fraction(destination_image, source_image, CONTROL_CELL) > 0.001,
		"%s: enqueue displays the obstacle at its source" % mode)
	var motions: Array = board.get("_playback").get("_motions")
	if motions.is_empty():
		_check(false, "%s: displacement fixture enters playback" % mode)
		return
	var motion: Dictionary = motions[0]
	var start_ms: float = -motion.elapsed_ms
	var duration_ms: float = motion.duration_ms
	await _flush_draws()
	_reset_draws()
	board._process((start_ms + duration_ms * 0.5) / 1000.0)
	board.set_process(false)
	await _flush_draws()
	var moving := viewport.get_texture().get_image()
	_check(draws.tactical > 0 if split else draws.board > 0,
		"%s: moving obstacle redraws its layer" % mode)
	if split:
		_check(draws.board == 0, "split: obstacle movement leaves terrain alone")
	_reset_draws()
	board.clear_action_playback()
	board.set_process(false)
	await _flush_draws()
	var cleared := viewport.get_texture().get_image()
	_check(draws.tactical > 0 if split else draws.board > 0,
		"%s: clearing a moving obstacle redraws its layer" % mode)
	if split:
		_check(draws.board == 0, "split: clearing movement leaves terrain alone")
	_check(_same_tile(destination_image, cleared, CUSTOM_CELL) \
		and _same_tile(destination_image, cleared, CONTROL_CELL),
		"%s: clearing movement restores the obstacle to the board state" % mode)

	board.play_committed_actions(cues)
	board.set_process(false)
	await _flush_draws()
	board._process((start_ms + duration_ms * 0.5) / 1000.0)
	board.set_process(false)
	await _flush_draws()
	moving = viewport.get_texture().get_image()
	_reset_draws()
	board._process((duration_ms * 0.5 + 1.0) / 1000.0)
	board.set_process(false)
	await _flush_draws()
	var landed := viewport.get_texture().get_image()
	_check(draws.tactical > 0 if split else draws.board > 0,
		"%s: obstacle landing redraws its layer" % mode)
	_check(_changed_fraction(moving, landed, CONTROL_CELL) > 0.001,
		"%s: obstacle visibly reaches its destination" % mode)
	_check(board.action_playback_pending(), "%s: later action keeps playback pending" % mode)
	_reset_draws()
	board._process(0.01)
	board.set_process(false)
	await _flush_draws()
	_check(draws.board == 0 and draws.tactical == 0,
		"%s: settled obstacle does not keep redrawing its layer" % mode)
	board.clear_action_playback()
	board.set_process(false)


func _flush_draws() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _reset_draws() -> void:
	for key in draws:
		draws[key] = 0


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
