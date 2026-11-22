extends SceneTree
## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/storybook_gate_art_scene_test.gd
## Exercises the ordinary launch without an injected art manifest or local capture files.

const BoardRules = preload("res://rules/board.gd")
const MISSION := "wrong_side_of_the_door"

var failures: Array[String] = []
var scene: Node
var board: Control
var ink: Control
var viewport: SubViewport


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Storybook Gate art test requires a graphical renderer.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _launch()
	if board == null or ink == null:
		_check(false, "Normal storybook launch mounts the live board and ink")
		_finish()
		return
	var page: Control = scene.get("_storybook_page")
	var props: Dictionary = page.get("_props")
	var scenery: TextureRect = page.get("_scenery")
	_check(scenery.texture != null, "Normal storybook launch loads the scenery")
	for kind in ["gate_closed", "gate_open", "plate", "exit"]:
		var prop: Dictionary = props.get(kind, {})
		_check(prop.get("texture") is Texture2D and prop.get("anchor") is Vector2
			and prop.get("size") is Vector2 and prop.get("size", Vector2.ZERO).x > 0.0
			and prop.get("size", Vector2.ZERO).y > 0.0,
			"Normal storybook launch loads usable " + kind + " art")
	_check(bool(board.get("_pressure_gate_prop_installed")), "Art replaces the primitive gate")
	var opening: Dictionary = scene.battle_snapshot()
	_check(not BoardRules.pressure_gate_open(opening), "Opening authoritative gate is closed")
	_check_gate_art(false, props)

	if scenery.texture != null:
		var with_scenery := await _capture()
		scenery.visible = false
		var without_scenery := await _capture()
		scenery.visible = true
		_check(_difference(with_scenery, without_scenery, Rect2i(Vector2i.ZERO, with_scenery.get_size())) > 0.01,
			"Loaded scenery contributes to the rendered page")
	var gate_cell: Vector2i = opening.objective.gate
	var gate_region := _gate_region(gate_cell)
	var prop_layer: CanvasItem = ink.get("_prop_layer")
	var with_props := await _capture()
	prop_layer.visible = false
	var without_props := await _capture()
	prop_layer.visible = true
	_check(_difference(with_props, without_props, gate_region) > 0.005,
		"Loaded gate art contributes to the actual board composition")

	# Reach the plate through real board input and commit, distinguishing a
	# forecast from the authoritative state that selects the actual gate art.
	if await _move(Vector2i(1, 1)) and await _commit():
		var before: Dictionary = scene.battle_snapshot().duplicate(true)
		if await _move(before.objective.plate):
			var plan: Dictionary = scene.get("_plan")
			_check(plan.get("valid", false) and BoardRules.pressure_gate_open(plan.get("result", {})),
				"Plate move forecasts an open gate")
			_check(scene.battle_snapshot() == before and not BoardRules.pressure_gate_open(before),
				"Forecast leaves the authoritative gate closed")
			_check_gate_art(false, props)
			if await _commit():
				_check(BoardRules.pressure_gate_open(scene.battle_snapshot()), "Commit opens the actual gate")
				_check_gate_art(true, props)
				var open_with := await _capture()
				prop_layer.visible = false
				var open_without := await _capture()
				prop_layer.visible = true
				_check(_difference(open_with, open_without, gate_region) > 0.005,
					"Open gate art contributes to the actual board composition")

	_finish()


func _launch() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	var args := PackedStringArray(["--mission=" + MISSION])
	scene.configure_launch(args)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	board = scene.find_child("BridgeBoard", true, false) as Control
	ink = scene.find_child("StorybookInk", true, false) as Control
	_check(scene.current_screen() == "battle" and scene.battle_snapshot().get("mission_id") == MISSION,
		"Requested mission launches into battle")


func _check_gate_art(open: bool, props: Dictionary) -> void:
	var cues: Dictionary = ink.get("_cues")
	var actual: Dictionary = cues.get("gate_actual", {})
	var key := "gate_open" if open else "gate_closed"
	var expected: Dictionary = props.get(key, {})
	var selected: Dictionary = ink.call("_actual_gate_prop")
	_check(actual.get("open") == open and actual.get("cell") == scene.battle_snapshot().objective.gate,
		"Gate cue tracks authoritative " + key + " state")
	_check(expected.get("texture") is Texture2D and selected.get("texture") == expected.get("texture"),
		"Actual gate selects loaded " + key + " art")


func _move(destination: Vector2i) -> bool:
	var knight := Vector2i(-1, -1)
	for unit in scene.battle_snapshot().get("units", []):
		if unit.get("id") == "knight":
			knight = unit.position
	if knight == Vector2i(-1, -1):
		_check(false, "Knight is available")
		return false
	await _click(board.get_global_transform_with_canvas() * board.cell_center(knight))
	await _click(board.get_global_transform_with_canvas() * board.cell_center(destination))
	var command: Dictionary = scene.get("_planned_state").get("overrides", {}).get("knight", {})
	var staged: bool = command.get("ability_id") == "move" and command.get("target_id") == "%d,%d" % [destination.x, destination.y]
	_check(staged, "Board input stages Knight move to %s" % destination)
	return staged


func _commit() -> bool:
	var button := scene.find_child("Commit", true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, "Commit is available")
		return false
	var expected: Dictionary = scene.get("_plan").get("result", {}).duplicate(true)
	await _click(button.get_global_rect().get_center())
	var matches: bool = scene.battle_snapshot() == expected
	_check(matches, "Commit resolves the displayed forecast")
	return matches


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


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _gate_region(cell: Vector2i) -> Rect2i:
	var transform := board.get_global_transform_with_canvas()
	var center: Vector2 = transform * board.cell_center(cell)
	var step: Vector2 = (board.cell_center(Vector2i.ONE) - board.cell_center(Vector2i.ZERO)) * transform.get_scale()
	var rect := Rect2i(Vector2i(center - step * 0.45), Vector2i(step * 0.9))
	return rect.intersection(Rect2i(Vector2i.ZERO, viewport.size))


func _difference(first: Image, second: Image, region: Rect2i) -> float:
	if region.get_area() <= 0 or first.get_size() != second.get_size():
		_check(false, "Compared images have a nonempty region and matching dimensions")
		return 0.0
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
				changed += 1
	return float(changed) / region.get_area()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: normal storybook art composition and authoritative gate state")
	quit(0 if failures.is_empty() else 1)
