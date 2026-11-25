extends SceneTree
## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_gate_art_scene_test.gd
## Exercises the ordinary launch and Forecast layering without reference captures.

const BoardRules = preload("res://rules/board.gd")
const MISSION := "wrong_side_of_the_door"
const B4 := Vector2i(1, 3)
const A5 := Vector2i(0, 4)

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
	if await _move("knight", Vector2i(1, 1)) and await _commit():
		var before: Dictionary = scene.battle_snapshot().duplicate(true)
		if await _move("knight", before.objective.plate):
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

	await _launch()
	await _leaves_keep_board_exposed()
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


func _leaves_keep_board_exposed() -> void:
	var forecast := scene.find_child("ForecastDetails", true, false) as BaseButton
	var orders := scene.find_child("StandingOrders", true, false) as BaseButton
	var leaf := scene.find_child("ExtraDetails", true, false) as Control
	if board == null or ink == null or forecast == null or orders == null or leaf == null \
			or not forecast.is_visible_in_tree() or forecast.disabled:
		_check(false, "Normal Gate provides a live board, ink and details controls")
		return
	var before: Dictionary = scene.battle_snapshot()
	if not await _move("wizard", B4):
		return
	var forecast_point := forecast.get_global_rect().get_center()
	await _click(forecast_point)
	if not leaf.is_visible_in_tree() or not forecast.button_pressed:
		_check(false, "Clicking Forecast opens the details sheet")
		return
	var sheet_rect := leaf.get_global_rect()
	var board_rect := board.get_global_rect()
	_check(not sheet_rect.intersects(board_rect),
		"Forecast leaves the whole Gate board, including its gutters, exposed")
	var b4 := _gate_region(B4)
	var open_with_ink := await _capture()
	var open_without_ink := await _capture_without_ink()
	_check(_difference(open_with_ink, open_without_ink, b4) > 0.005,
		"Forecast keeps the previously obscured B4 move ink visible")
	var page: Control = scene.get("_storybook_page")
	var scenery: TextureRect = page.get("_scenery")
	scenery.hide()
	var open_without_scenery := await _capture()
	scenery.show()
	var gate: Vector2i = before.objective.gate
	_check(_difference(open_with_ink, open_without_scenery, _gate_region(gate + Vector2i.UP)) > 0.05,
		"Gate wall is still painted in the column immediately above its opening after refitting")
	_check(_difference(open_with_ink, open_without_scenery, _gate_region(gate)) == 0.0,
		"Painted wall does not cover the registered Gate opening")
	var figures := board.get_node("CastAndUnitMarkers") as CanvasItem
	figures.hide()
	var without_figures := await _capture()
	figures.show()
	for unit: Dictionary in before.units:
		if unit.hp > 0:
			var region := _gate_region(unit.position)
			_check(_difference(open_with_ink, open_without_scenery, region) == 0.0,
				"Gate surround leaves occupied %s exposed" % unit.position)
			_check(_difference(open_with_ink, without_figures, region) > 0.005,
				"Living %s is visibly rendered with Forecast open" % unit.id)

	await _click(sheet_rect.position + Vector2(8, 35))
	_check(_staged_move("wizard", B4) and leaf.is_visible_in_tree(),
		"Clicking paper does not retarget the staged move")
	await _click(_cell_point(A5))
	_check(_staged_move("wizard", A5) and scene.battle_snapshot() == before and leaf.is_visible_in_tree(),
		"Clicking the formerly blocked A5 stages a real move without closing Forecast or committing")
	await _click(orders.get_global_rect().get_center())
	_check(leaf.is_visible_in_tree() and orders.button_pressed and not forecast.button_pressed
		and board.get_global_rect().is_equal_approx(board_rect) and leaf.get_global_rect().is_equal_approx(sheet_rect),
		"Switching from Forecast to Standing orders keeps the layout and changes only the active tab")
	var picker := scene.find_child("KnightOrder", true, false) as OptionButton
	_check(picker != null and picker.has_focus(), "Opening Standing orders focuses the first enabled picker")
	await _click(_cell_point(Vector2i(0, 1))) # A2
	_check(scene.get("_actor_id") == "knight" and _staged_move("wizard", A5),
		"Clicking the board with Standing orders open selects Knight without replacing Wizard's Move")
	await _click(orders.get_global_rect().get_center())
	_check(not leaf.is_visible_in_tree() and not orders.button_pressed, "The active tab closes the leaf")


func _move(actor: String, destination: Vector2i) -> bool:
	for unit in scene.battle_snapshot().get("units", []):
		if unit.get("id") == actor:
			await _click(_cell_point(unit.position))
			await _click(_cell_point(destination))
			var staged := _staged_move(actor, destination)
			_check(staged, "Board input stages %s Move to %s" % [actor, destination])
			return staged
	_check(false, "%s is available" % actor)
	return false


func _staged_move(actor: String, destination: Vector2i) -> bool:
	var command: Dictionary = scene.get("_planned_state").get("overrides", {}).get(actor, {})
	return command.get("ability_id") == "move" and command.get("target_id") == "%d,%d" % [destination.x, destination.y]


func _cell_point(cell: Vector2i) -> Vector2:
	return board.get_global_transform_with_canvas() * board.cell_center(cell)


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


func _capture_without_ink() -> Image:
	var was_visible := ink.visible
	ink.hide()
	var image := await _capture()
	ink.visible = was_visible
	return image


func _gate_region(cell: Vector2i) -> Rect2i:
	var transform := board.get_global_transform_with_canvas()
	var center := _cell_point(cell)
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
		print("PASS: registered Gate wall and opening, occupied-cell rendering, both leaves, and real B4/A5 input")
	quit(0 if failures.is_empty() else 1)
