extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_gate_outcome_scene_test.gd
var failures: Array[String] = []
var rules = preload("res://rules/rules.gd").new()
var scene: Node
var board: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	board = scene.find_child("BridgeBoard", true, false) as Control
	if scene.current_screen() != "battle" or board == null:
		_check(false, "Storybook Gate launches into battle")
		_finish()
		return
	var opening: Dictionary = scene.battle_snapshot().duplicate(true)
	await _move_into_vacated_cell()
	if not await _button("Restart"):
		_finish()
		return
	_check(scene.battle_snapshot() == opening, "Restart resets the forecast-vacated Move fixture")
	# Knight holds the plate, then Healer passes the gate after Guard defeats the goblin.
	for step in [
		["knight", Vector2i(1, 1)], ["knight", Vector2i(2, 1)],
		["healer", Vector2i(1, 2)], [],
		["healer", Vector2i(2, 2)], ["healer", Vector2i(3, 2)],
		["healer", Vector2i(4, 2)], ["healer", Vector2i(5, 2)]
	]:
		if not await _round(step):
			_finish()
			return
	var victory: Dictionary = scene.battle_snapshot()
	_check(victory.get("outcome") == "victory", "Legal route reaches victory")
	var page: Variant = scene.get("_storybook_page")
	var summary: Label = page.get("_summary")
	var objective: Label = page.get("_objective")
	var victory_text := str(rules.mission_definition(opening).get("objective", {}).get("victory_text", ""))
	_check(not victory_text.is_empty() and objective.is_visible_in_tree() and victory_text in objective.text,
		"Terminal page reports the mission victory")
	_check(summary.is_visible_in_tree() and "preview" not in summary.text.to_lower()
		and "this round" not in summary.text.to_lower(),
		"Victory footer contains no pending or hypothetical command")
	_check("get any living hero to the exit" not in objective.text.to_lower()
		and "get a hero to f3" not in objective.text.to_lower(),
		"Victory page does not present the opening objective as unfinished")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	_check(commit == null or not commit.is_visible_in_tree() or commit.disabled,
		"Victory does not offer a live Commit")
	if await _button("Restart"):
		_check(scene.current_screen() == "battle" and scene.battle_snapshot() == opening,
			"Restart restores the original Gate mission")
		commit = scene.find_child("Commit", true, false) as BaseButton
		_check(commit != null and commit.is_visible_in_tree() and not commit.disabled,
			"Restart restores the live Commit control")
	_finish()


func _move_into_vacated_cell() -> void:
	if not await _round(["knight", Vector2i(1, 1)], true) \
			or not await _round(["knight", Vector2i(2, 1)]):
		return
	if not await _button("StandingOrders"):
		return
	var picker := scene.find_child("HealerOrder", true, false) as OptionButton
	var order_label := ""
	for choice in rules.options(scene.battle_snapshot(), "healer"):
		if choice.kind == "order" and choice.id == "order_aggressive":
			order_label = choice.label
	var order_index := -1
	if picker != null and picker.is_visible_in_tree():
		for i in picker.item_count:
			if picker.get_item_text(i) == order_label:
				order_index = i
				break
	if order_index < 0:
		_check(false, "Healer offers Pursue and bonk")
		return
	picker.select(order_index)
	picker.item_selected.emit(order_index)
	await process_frame
	if not await _button("StandingOrders"):
		return
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var vacated := Vector2i(0, 2) # A3, still occupied on the actual board.
	_check(_unit(before, "healer").get("position") == vacated,
		"Healer still occupies A3 before the forecast")
	var context: Dictionary = rules.state_before_action(before, "wizard")
	_check(_unit(context, "healer").get("position") == Vector2i(1, 2),
		"Pursue forecasts Healer moving from A3 to B3 before Wizard acts")
	_check(rules.targets(context, "wizard", "move").any(
		func(choice: Dictionary) -> bool: return choice.position == vacated),
		"A3 is a legal Wizard Move in the acting snapshot")
	var wizard_cell: Vector2i = _unit(before, "wizard").position
	await _cell(wizard_cell)
	await _explicit_move_into_vacated_cell(before, vacated)
	if not await _button("ClearCommand"):
		return
	_check(scene.get("_actor_id") == "" and scene.get("_planned_state").overrides.is_empty(),
		"Clear command discards the Move and returns to neutral")
	await _quick_move_then_vacated_replacement(before, wizard_cell, vacated)


func _explicit_move_into_vacated_cell(before: Dictionary, vacated: Vector2i) -> void:
	if not await _button("DirectOrder_move"):
		return
	_check(scene.get("_aimed_ability_id") == "move" and vacated in _highlighted_cells(),
		"Explicit Move aims at the forecast-vacated A3")
	_check(scene.get("_planned_state").overrides.is_empty(), "Aiming Move does not stage it")
	await _cell(vacated)
	_check(_wizard_move_is("0,2"),
		"After aiming Move, clicking A3 stages Wizard Move rather than selecting Healer")
	_check(scene.battle_snapshot() == before, "Explicit Wizard Move remains an uncommitted forecast")


func _quick_move_then_vacated_replacement(before: Dictionary, wizard_cell: Vector2i, vacated: Vector2i) -> void:
	var step := Vector2i(1, 3) # B4
	await _cell(wizard_cell)
	_check(step in _highlighted_cells(), "Wizard selection marks the quick Move to B4")
	await _cell(step)
	_check(_wizard_move_is("1,3"), "Clicking B4 without aiming queues the Wizard Move directly")
	var queued: Dictionary = scene.get("_planned_state").duplicate(true)
	var plan: Dictionary = scene.get("_plan").duplicate(true)

	var knight_cell: Vector2i = _unit(before, "knight").position
	_check(knight_cell not in _highlighted_cells(), "Knight is not highlighted for quick Wizard Move")
	await _cell(knight_cell)
	_check(scene.get("_actor_id") == "knight" and scene.get("_planned_state") == queued,
		"Clicking Knight selects him without replacing the Wizard Move")
	await _cell(wizard_cell)
	_check(_wizard_move_is("1,3") and scene.get("_plan") == plan,
		"Reselecting Wizard retains the queued Move and its forecast")
	await _cell(vacated)
	_check(scene.get("_actor_id") == "healer" and scene.get("_planned_state") == queued
		and scene.get("_plan") == plan,
		"Without aiming, clicking the currently occupied A3 selects Healer and preserves the B4 draft")
	await _cell(wizard_cell)
	if not await _button("DirectOrder_move"):
		return
	_check(scene.get("_aimed_ability_id") == "move" and vacated in _highlighted_cells(),
		"Aiming Move again marks A3 even while Healer visibly occupies it")

	var motion := InputEventMouseMotion.new()
	motion.position = board.get_global_transform_with_canvas() * board.cell_center(vacated)
	motion.global_position = motion.position
	root.push_input(motion, true)
	await process_frame
	var inspection: Label = scene.get("_storybook_page").get("_inspection")
	var healer_name: String = rules.display_name(before, "healer")
	_check(inspection.is_visible_in_tree() and "A3" in inspection.text and healer_name in inspection.text
		and "Legal target" in inspection.text and "Legal target" in board.tooltip_text,
		"Aimed Move inspection describes both the current Healer and the forecast destination at A3")
	await _cell(vacated)
	_check(_wizard_move_is("0,2"),
		"Clicking aimed A3 replaces B4 with A3 rather than selecting Healer")
	_check(scene.battle_snapshot() == before, "Move replacement does not commit battle state")


func _highlighted_cells() -> Array:
	return (board.get("_overlay") as Dictionary).get("targets", [])


func _wizard_move_is(target: String) -> bool:
	var overrides: Dictionary = (scene.get("_planned_state") as Dictionary).get("overrides", {})
	var command: Dictionary = overrides.get("wizard", {})
	return scene.get("_actor_id") == "wizard" and overrides.size() == 1 \
		and command.get("ability_id") == "move" and command.get("target_id") == target


func _round(step: Array, inspect_opening_knight := false) -> bool:
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	if not step.is_empty():
		var actor := str(step[0])
		var destination: Vector2i = step[1]
		var unit := _unit(before, actor)
		if unit.is_empty():
			_check(false, "Route actor is present: " + actor)
			return false
		await _cell(unit.position)
		if scene.get("_actor_id") != actor:
			_check(false, "Route selects or retains " + actor)
			return false
		await _cell(destination)
		var planned: Dictionary = scene.get("_planned_state")
		var command: Dictionary = planned.get("overrides", {}).get(actor, {})
		var expected := "%d,%d" % [destination.x, destination.y]
		if command.get("ability_id") != "move" or command.get("target_id") != expected:
			_check(false, "Route stages %s Move to %s" % [actor, expected])
			return false
		_check(scene.battle_snapshot() == before, "Route preview does not commit")
		if inspect_opening_knight:
			# Focus initializes the cursor at Knight. Visit B2 and return to A2
			# so inspection is generated through the real keyboard path.
			board.release_focus()
			board.grab_focus()
			await process_frame
			_check(root.gui_get_focus_owner() == board, "Board accepts inspection focus")
			await _key(KEY_RIGHT)
			await _key(KEY_LEFT)
			var inspection: String = scene.get("_storybook_inspection")
			_check("A2" in inspection and rules.display_name(before, "knight") in inspection and "HP" in inspection,
				"Focused A2 inspection identifies Knight before commitment")
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	var expected: Dictionary = rules.commit_round(scene.get("_planned_state"), plan)
	if not plan.get("valid", false) or not await _button("Commit"):
		_check(false, "Route round has a valid committable forecast")
		return false
	_check(scene.battle_snapshot() == expected, "Route commit matches its forecast")
	if inspect_opening_knight:
		var inspection: String = scene.get("_storybook_inspection")
		_check(not ("A2" in inspection and rules.display_name(before, "knight") in inspection and "HP" in inspection),
			"After Knight moves, A2 inspection does not claim Knight still occupies it")
	if not step.is_empty() and _unit(scene.battle_snapshot(), step[0]).get("position") != step[1]:
		_check(false, "Route actor reaches destination: " + str(step))
		return false
	return true


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _cell(cell: Vector2i) -> void:
	await _click(board.get_global_transform_with_canvas() * board.cell_center(cell))


func _button(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is visible and enabled")
		return false
	await _click(button.get_global_rect().get_center())
	return true


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: storybook Gate outcome scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
