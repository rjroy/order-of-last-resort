extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_gate_scene_test.gd
# Board, keyboard and Wizard actions use viewport input.
var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []
var scene: Node


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
	if scene.current_screen() != "battle":
		_check(false, "Storybook Gate launches into battle")
		_finish()
		return
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null or not board.has_method("cell_center"):
		_check(false, "Storybook Gate exposes an interactive board")
		_finish()
		return
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	_check(before.get("mission_id") == "wrong_side_of_the_door", "Requested Gate mission is loaded")
	var knight := _unit(before, "knight")
	var healer := _unit(before, "healer")
	if knight.is_empty() or healer.is_empty():
		_check(false, "Gate opens with Knight and Healer")
		_finish()
		return
	_check(before.get("orders", {}).get("knight") == "order_guard", "Knight defaults to Guard")
	var targets: Array = rules.targets(before, "knight", "move")
	if targets.size() < 2:
		_check(false, "Opening Knight has two legal moves for replacement")
		_finish()
		return
	# Keep the native window's incidental pointer position from opening a
	# tooltip that consumes Escape before the keyboard test reaches battle.
	await _hover(Vector2(-1, -1))
	await _keyboard_move(board, knight, targets[0], before)
	await _full_hero_actions(board, before)
	await _unavailable_bonk(board, before)
	await _click_cell(board, healer.position)
	_check(scene.get("_actor_id") == "healer", "Clicking Healer selects Healer on the board")
	await _click_cell(board, knight.position)
	_check(scene.get("_actor_id") == "knight", "Clicking Knight selects Knight on the board")
	await _click_cell(board, targets[0].position)
	_check_move(targets[0], "Clicking an adjacent square automatically stages Move")
	var move_overlay: Dictionary = board.get("_overlay")
	_check(move_overlay.get("quiet_manual_move", false), "Staged storybook Move opts into quiet markers")
	_check(targets[0].position in move_overlay.get("targets", []),
		"Quiet Move retains its legal destination in the board overlay")
	_check(scene.battle_snapshot() == before, "Staging a move does not change actual battle state")
	_check_other_orders(before)
	var first_plan: Dictionary = scene.get("_plan").duplicate(true)
	_check(first_plan.get("valid", false), "Staged move automatically produces a valid forecast")
	_check(_unit(first_plan.get("result", {}), "knight").get("position") == targets[0].position,
		"Forecast shows the staged destination")

	await _click_cell(board, targets[1].position)
	_check_move(targets[1], "Clicking another adjacent square replaces the staged move")
	_check(scene.battle_snapshot() == before, "Replacing a move leaves actual state unchanged")
	_check_other_orders(before)
	if not await _click_button("ClearCommand"):
		_finish()
		return
	var cleared: Dictionary = scene.get("_planned_state")
	_check(not (board.get("_overlay") as Dictionary).get("quiet_manual_move", false),
		"Clearing Move disables quiet markers")
	_check(cleared.get("overrides", {}).is_empty(), "Clear removes the direct command")
	_check(cleared.get("orders", {}).get("knight") == "order_guard", "Clearing restores Knight's default Guard")
	_check(scene.battle_snapshot() == before, "Clearing a move leaves actual state unchanged")
	_check_other_orders(before)
	var guard_plan: Dictionary = rules.preview_round(cleared)
	_check(scene.get("_plan") == guard_plan, "Cleared forecast uses standing orders including Guard")

	await _click_cell(board, targets[0].position)
	_check_move(targets[0], "Move can be staged again after clearing")
	var committed_plan: Dictionary = scene.get("_plan").duplicate(true)
	_check(scene.battle_snapshot() == before, "Restaged move waits for explicit commit")
	if await _click_button("Commit"):
		_check(scene.battle_snapshot() == committed_plan.get("result"),
			"Explicit commit resolves the displayed forecast")
		_check(scene.battle_snapshot() != before, "Commit advances actual battle state")
	_finish()


func _keyboard_move(board: Control, knight: Dictionary, target: Dictionary, before: Dictionary) -> void:
	_check(scene.get("_actor_id") == "knight", "Keyboard test starts with Knight selected")
	var delta: Vector2i = target.position - knight.position
	var keys := {Vector2i.LEFT: KEY_LEFT, Vector2i.RIGHT: KEY_RIGHT,
		Vector2i.UP: KEY_UP, Vector2i.DOWN: KEY_DOWN}
	if not keys.has(delta):
		_check(false, "Keyboard fixture has an adjacent cardinal move")
		return
	# The first focus starts the board cursor at the currently selected hero.
	board.grab_focus()
	await process_frame
	_check(root.gui_get_focus_owner() == board, "Board accepts keyboard focus")
	await _key(keys[delta])
	await _key(KEY_ENTER)
	_check_move(target, "Arrow and Enter stage Knight's adjacent Move from focused board")
	_check(scene.battle_snapshot() == before, "Keyboard Move previews without changing actual state")
	var plan: Dictionary = scene.get("_plan")
	_check(plan.get("valid", false) and _unit(plan.get("result", {}), "knight").get("position") == target.position,
		"Keyboard Move forecasts the chosen destination")
	await _key(KEY_ESCAPE)
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Escape clears the keyboard-staged Move")
	_check(scene.battle_snapshot() == before, "Clearing keyboard Move preserves actual state")


func _full_hero_actions(board: Control, before: Dictionary) -> void:
	var wizard := _unit(before, "wizard")
	if wizard.is_empty():
		_check(false, "Gate opens with Wizard")
		return
	await _click_cell(board, wizard.position)
	_check(scene.get("_actor_id") == "wizard", "Clicking Wizard selects Wizard")
	if not await _choose_action("wizard_blast"):
		return
	var planned: Dictionary = scene.get("_planned_state")
	var command: Dictionary = planned.get("overrides", {}).get("wizard", {})
	_check(command.get("ability_id") == "wizard_blast" and command.get("target_id", "") == "",
		"Choosing Blast stages an automatic action without selecting a target")
	_check((scene.get("_targets") as Array).is_empty(), "Automatic Blast does not offer aimed targets")
	var target_menu := scene.find_child("Targets", true, false) as Control
	_check(target_menu == null or not target_menu.is_visible_in_tree(),
		"Automatic Blast does not display a target picker")
	_check(scene.battle_snapshot() == before, "Blast forecast does not commit actual battle state")
	var plan: Dictionary = scene.get("_plan")
	var blast_target := ""
	var blast_text := ""
	for event in plan.get("events", []):
		if event.get("type") == "damage" and event.get("source_id") == "wizard":
			blast_target = str(event.get("target_id", ""))
			blast_text = str(event.get("text", ""))
			break
	_check(plan.get("valid", false) and not blast_target.is_empty()
		and not _unit(before, blast_target).is_empty(),
		"Blast forecast resolves a real target in the opening fixture")
	if await _click_button("ForecastDetails"):
		var visible_event := false
		for label in scene.find_children("*", "Label", true, false):
			if label.is_visible_in_tree() and not blast_text.is_empty() and blast_text in label.text:
				visible_event = true
		_check(visible_event, "Visible forecast shows the real Blast event")
		await _click_button("ForecastDetails")
	await _key(KEY_ESCAPE)
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Escape clears the staged Blast")

	await _aimed_pull(board, before)

	if not await _click_button("StandingOrders") or not await _choose_order("wizard", "order_blast"):
		return
	var edited: Dictionary = scene.battle_snapshot()
	_check(edited.get("orders", {}).get("wizard") == "order_blast",
		"Editing Wizard's standing order updates the actual order")
	_check(edited.get("orders", {}).get("knight") == before.get("orders", {}).get("knight")
		and edited.get("orders", {}).get("healer") == before.get("orders", {}).get("healer"),
		"Editing Wizard's standing order preserves the other heroes' orders")
	_check(scene.get("_plan") == rules.preview_round(scene.get("_planned_state")),
		"Changing a standing order refreshes the round forecast")
	await _choose_order("wizard", before.get("orders", {}).get("wizard", ""))
	await _click_button("StandingOrders")
	_check(scene.battle_snapshot() == before, "Restoring the order returns to the opening state")


func _aimed_pull(board: Control, before: Dictionary) -> void:
	var healer := Vector2i(0, 2) # A3
	var knight := Vector2i(0, 1) # A2
	var step := Vector2i(1, 3) # B4
	var context: Dictionary = rules.state_before_action(before, "wizard")
	if _unit(before, "healer").get("position") != healer or _unit(before, "knight").get("position") != knight \
			or not rules.targets(context, "wizard", "move").any(
				func(choice: Dictionary) -> bool: return choice.position == step):
		_check(false, "Gate fixture has Healer at A3, Knight at A2, and a legal Wizard Move to B4")
		return
	if not await _choose_action("wizard_pull"):
		return
	var highlights := _highlighted_cells(board).duplicate()
	_check(healer in highlights and knight in highlights and step not in highlights,
		"Pull highlights Healer and Knight, not the otherwise legal B4 Move")
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Choosing aimed Pull waits for a target")
	await _click_cell(board, step)
	_check(scene.get("_actor_id") == "wizard" and scene.get("_planned_state") == before \
		and _highlighted_cells(board) == highlights, "Before queueing Pull, off-target B4 is inert")

	await _escape_pull_hover(board, healer)
	await _click_cell(board, healer)
	_check(scene.get("_actor_id") == "healer", "After Escape, clicking A3 selects Healer rather than queuing Pull")
	await _click_cell(board, _unit(before, "wizard").position)
	await _click_cell(board, step)
	_check_wizard_command("move", "1,3", "After Escape leaves Pull aim, B4 stages ordinary Move")
	await _key(KEY_ESCAPE)
	if not await _choose_action("wizard_pull"):
		return
	await _click_cell(board, healer)
	_check_wizard_command("wizard_pull", "healer", "Clicking highlighted A3 stages Pull on Healer")
	_check(_highlighted_cells(board) == highlights, "Queued Pull keeps its targets highlighted for retargeting")
	var queued: Dictionary = scene.get("_planned_state").duplicate(true)
	await _click_cell(board, step)
	_check(scene.get("_actor_id") == "wizard" and scene.get("_planned_state") == queued \
		and _highlighted_cells(board) == highlights, "After queueing Pull, off-target B4 is inert")
	if scene.get("_planned_state") != queued:
		# Rearm on RED so the valid retarget and explicit Move checks are independent of the off-target failure.
		if not await _choose_action("wizard_pull"):
			return
		await _click_cell(board, healer)
	await _click_cell(board, knight)
	_check_wizard_command("wizard_pull", "knight", "Clicking highlighted A2 retargets Pull rather than selecting Knight")
	if not await _choose_action("wizard_pull"):
		return
	_check(_highlighted_cells(board).is_empty(), "Reselecting queued Pull deliberately exits aim")
	_check_wizard_command("wizard_pull", "knight", "Leaving aim keeps the queued Pull")
	await _click_cell(board, step)
	_check_wizard_command("move", "1,3", "After leaving queued Pull aim, B4 stages ordinary Move")
	if not await _choose_action("wizard_pull"):
		return
	await _click_cell(board, knight)
	if await _choose_action("move"):
		_check_wizard_command("wizard_pull", "knight", "Selecting Move keeps the queued Pull until a destination is chosen")
		_check(step in _highlighted_cells(board), "Explicit Move replaces Pull highlights with legal destinations")
		await _click_cell(board, step)
		_check_wizard_command("move", "1,3", "Explicit Move lets B4 replace the queued Pull")
	_check(scene.battle_snapshot() == before, "Aiming and changing commands do not commit battle state")
	await _key(KEY_ESCAPE)


func _escape_pull_hover(board: Control, cell: Vector2i) -> void:
	await _hover(board.get_global_transform_with_canvas() * board.cell_center(cell))
	var inspection: Label = scene.get("_storybook_page").get("_inspection")
	var aim_note := "Legal target"
	_check(inspection.is_visible_in_tree() and aim_note in inspection.text and aim_note in board.tooltip_text,
		"Hovering highlighted A3 advertises a legal Pull target in inspection and tooltip")
	# No mouse motion: the current hover must change when aim ends.
	await _key(KEY_ESCAPE)
	_check(_highlighted_cells(board).is_empty()
		and (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Escape leaves unqueued Pull aim and removes its highlights")
	_check(aim_note not in inspection.text and aim_note not in board.tooltip_text,
		"Escape removes stale Pull target text from both inspection and tooltip without mouse motion")


func _highlighted_cells(board: Control) -> Array:
	return (board.get("_overlay") as Dictionary).get("targets", [])


func _check_wizard_command(ability: String, target: String, message: String) -> void:
	var overrides: Dictionary = (scene.get("_planned_state") as Dictionary).get("overrides", {})
	var command: Dictionary = overrides.get("wizard", {})
	_check(scene.get("_actor_id") == "wizard" and overrides.size() == 1
		and command.get("ability_id") == ability and command.get("target_id") == target, message)


func _unavailable_bonk(board: Control, before: Dictionary) -> void:
	await _click_cell(board, _unit(before, "healer").position)
	var context: Dictionary = rules.state_before_action(scene.get("_planned_state"), "healer")
	_check(rules.targets(context, "healer", "healer_bonk").is_empty(),
		"Opening Healer Bonk has no legal targets")
	var menu := scene.find_child("Actions", true, false) as MenuButton
	var label: String = rules.ability_definition(before, "healer_bonk", "healer").get("label", "")
	if menu == null or not menu.is_visible_in_tree() or label.is_empty():
		_check(false, "Healer action menu is available")
		return
	var popup := menu.get_popup()
	var index := -1
	for i in popup.item_count:
		if popup.get_item_text(i).begins_with(label):
			index = i
			break
	_check(index >= 0, "Unavailable Healer Bonk remains discoverable with a reason")
	if index >= 0:
		var reason: String = popup.get_item_tooltip(index)
		if not popup.is_item_disabled(index):
			popup.id_pressed.emit(popup.get_item_id(index))
			await process_frame
		var explained := not reason.is_empty() or popup.get_item_text(index) != label
		for text in scene.find_children("*", "Label", true, false):
			var value: String = text.text.to_lower()
			if text.is_visible_in_tree() and ("no legal target" in value or "no target" in value):
				explained = true
		_check(explained, "Unavailable Healer Bonk explains why it cannot be used")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	_check(commit != null and commit.is_visible_in_tree() and not commit.disabled
		and (scene.get("_plan") as Dictionary).get("valid", false),
		"Unavailable Bonk leaves valid Commit available")
	_check(scene.battle_snapshot() == before, "Unavailable Bonk does not change battle state")
	await _key(KEY_ESCAPE)


func _choose_action(id: String) -> bool:
	var menu := scene.find_child("Actions", true, false) as MenuButton
	var label: String = rules.ability_definition(scene.battle_snapshot(), id, "wizard").get("label", "")
	if menu != null and menu.is_visible_in_tree() and not menu.disabled and not label.is_empty():
		var popup := menu.get_popup()
		for index in popup.item_count:
			if popup.get_item_text(index).begins_with(label) and not popup.is_item_disabled(index):
				menu.grab_focus()
				await _key(KEY_SPACE)
				if not popup.visible:
					break
				for _attempt in popup.item_count:
					if popup.get_focused_item() == index:
						break
					await _key(KEY_DOWN)
				if popup.get_focused_item() == index:
					await _key(KEY_ENTER)
					if not popup.visible:
						return true
				await _key(KEY_ESCAPE)
				break
	_check(false, "Actions menu offers " + id)
	return false


func _choose_order(hero: String, id: String) -> bool:
	var picker := scene.find_child(hero.to_pascal_case() + "Order", true, false) as OptionButton
	var label := ""
	for choice in rules.options(scene.battle_snapshot(), hero):
		if choice.kind == "order" and choice.id == id:
			label = choice.label
	if picker != null and picker.is_visible_in_tree() and not picker.disabled and not label.is_empty():
		for index in picker.item_count:
			if picker.get_item_text(index) == label and not picker.is_item_disabled(index):
				picker.select(index)
				picker.item_selected.emit(index)
				await process_frame
				return true
	_check(false, hero + " standing order control offers " + id)
	return false


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _check_move(target: Dictionary, message: String) -> void:
	var planned: Dictionary = scene.get("_planned_state")
	var overrides: Dictionary = planned.get("overrides", {})
	var command: Dictionary = overrides.get("knight", {})
	_check(overrides.size() == 1 and command.get("ability_id") == "move"
		and command.get("target_id") == target.id, message)


func _check_other_orders(before: Dictionary) -> void:
	var planned: Dictionary = scene.get("_planned_state")
	for actor in ["healer", "wizard"]:
		_check(planned.get("orders", {}).get(actor) == before.get("orders", {}).get(actor),
			actor + "'s standing order remains unchanged")


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _click_cell(board: Control, cell: Vector2i) -> void:
	var point: Vector2 = board.get_global_transform_with_canvas() * board.cell_center(cell)
	await _click(point)


func _hover(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame


func _click_button(name: String) -> bool:
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


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: storybook Gate scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
