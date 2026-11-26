extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_gate_scene_test.gd
# Board, keyboard, footer and leaf controls use viewport input. Automatic
# abilities are named footer buttons; targeted abilities are exercised
# target-first on the board, and Escape clears selection while retaining
# staged commands.
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
	# Escape clears the selection while the staged command is retained; Clear
	# command is the explicit way to discard a preview.
	await _key(KEY_ESCAPE)
	_check(scene.get("_actor_id") == "", "Escape clears the selection while the staged Move is retained")
	_check(not (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Escape retains the staged keyboard Move")
	_check(scene.battle_snapshot() == before, "Escape preserves actual battle state")
	if not await _click_button("ClearCommand"):
		return
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Clear command discards the staged keyboard Move")


func _full_hero_actions(board: Control, before: Dictionary) -> void:
	var wizard := _unit(before, "wizard")
	if wizard.is_empty():
		_check(false, "Gate opens with Wizard")
		return
	await _click_cell(board, wizard.position)
	_check(scene.get("_actor_id") == "wizard", "Clicking Wizard selects Wizard")
	# Selecting a hero marks the union of legal targets across all its
	# targeted actions, not only an aimed ability or Move.
	var selection_marks := _highlighted_cells(board)
	_check(Vector2i(0, 2) in selection_marks and Vector2i(0, 1) in selection_marks,
		"Wizard selection marks every legal Pull target")
	_check(Vector2i(1, 3) in selection_marks,
		"Wizard selection also marks Move destinations, not only an aimed ability")
	# Approved phase-2 controls: the old Actions menu is gone and every
	# automatic ability is a named footer button; targeted abilities are not.
	_check(scene.find_child("Actions", true, false) == null, "The old Actions menu is removed")
	var blast := _visible_button_containing("Blast nearest")
	_check(blast != null, "Selecting Wizard shows a named footer button for the automatic Blast")
	_check(_visible_button_containing("Pull and recoil") == null,
		"The targeted Pull is not a footer action")
	_check(_visible_button_containing("Move one tile") == null,
		"The targeted Move is not a footer action")
	if blast == null:
		return
	await _click(blast.get_global_rect().get_center())
	var planned: Dictionary = scene.get("_planned_state")
	var command: Dictionary = planned.get("overrides", {}).get("wizard", {})
	_check(command.get("ability_id") == "wizard_blast" and command.get("target_id", "") == "",
		"Pressing the automatic footer button stages Blast without selecting a target")
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
	# Escape clears the selection but keeps the staged command; Clear command
	# is the explicit way to discard a preview.
	await _key(KEY_ESCAPE)
	_check(scene.get("_actor_id") == "", "Escape clears the selection after staging Blast")
	_check(not (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Escape retains the staged Blast")
	if not await _click_button("ClearCommand"):
		return
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Clear command discards the staged Blast")

	await _targeted_pull(board, before)

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


func _targeted_pull(board: Control, before: Dictionary) -> void:
	var healer := Vector2i(0, 2) # A3
	var knight := Vector2i(0, 1) # A2
	var step := Vector2i(1, 3) # B4
	if _unit(before, "healer").get("position") != healer or _unit(before, "knight").get("position") != knight \
			or not rules.targets(rules.state_before_action(before, "wizard"), "wizard", "move").any(
				func(choice: Dictionary) -> bool: return choice.position == step):
		_check(false, "Gate fixture has Healer at A3, Knight at A2, and a legal Wizard Move to B4")
		return
	await _click_cell(board, _unit(before, "wizard").position)
	_check(scene.get("_actor_id") == "wizard", "Clicking Wizard selects Wizard for target-first Pull")
	# Selecting a hero marks the union of legal targets across all its
	# targeted actions, not only an aimed ability or Move.
	var marks := _highlighted_cells(board)
	_check(healer in marks and knight in marks,
		"Wizard selection marks every legal Pull target")
	_check(step in marks,
		"Wizard selection also marks Move destinations, not only an aimed ability")
	_check(not (Vector2i(1, 1) in marks), "A cell outside every targeted action stays unmarked")
	await _hover(board.get_global_transform_with_canvas() * board.cell_center(healer))
	var inspection: Label = scene.get("_storybook_page").get("_inspection")
	var aim_note := "Legal target"
	_check(inspection.is_visible_in_tree() and aim_note in inspection.text and aim_note in board.tooltip_text,
		"Hovering a marked ally advertises the legal Pull target in inspection and tooltip")
	await _click_cell(board, healer)
	_check_wizard_command("wizard_pull", "healer", "Clicking the marked healer stages Pull on her")
	_check(healer in _highlighted_cells(board) and knight in _highlighted_cells(board),
		"Staged Pull keeps the selection marks for retargeting")
	# Escape dismisses transient editing state, then clears the selection,
	# while the staged command is retained.
	await _key(KEY_ESCAPE)
	_check(scene.get("_actor_id") == "" and not (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Escape clears the selection and retains the staged Pull")
	_check(_highlighted_cells(board).is_empty(),
		"Clearing the selection removes the legal-target marks")
	_check(aim_note not in inspection.text and aim_note not in board.tooltip_text,
		"Clearing the selection drops the stale legal-target text without mouse motion")
	await _click_cell(board, _unit(before, "wizard").position)
	await _click_cell(board, knight)
	_check_wizard_command("wizard_pull", "knight", "Clicking the marked knight retargets Pull")
	await _click_cell(board, step)
	_check_wizard_command("move", "1,3", "A legal Move destination replaces the staged Pull")
	await _key(KEY_ESCAPE)
	_check(scene.get("_actor_id") == "", "Escape clears the selection after the Move staging")
	if not await _click_button("ClearCommand"):
		return
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Clear command discards the staged Move preview")


func _highlighted_cells(board: Control) -> Array:
	return (board.get("_overlay") as Dictionary).get("targets", [])


func _check_wizard_command(ability: String, target: String, message: String) -> void:
	var overrides: Dictionary = (scene.get("_planned_state") as Dictionary).get("overrides", {})
	var command: Dictionary = overrides.get("wizard", {})
	_check(scene.get("_actor_id") == "wizard" and overrides.size() == 1
		and command.get("ability_id") == ability and command.get("target_id") == target, message)


func _unavailable_bonk(board: Control, before: Dictionary) -> void:
	# Start unselected: a legal friendly target must not capture this click.
	await _key(KEY_ESCAPE)
	await _click_cell(board, _unit(before, "healer").position)
	_check(scene.get("_actor_id") == "healer", "Clicking the Healer selects her")
	var context: Dictionary = rules.state_before_action(scene.get("_planned_state"), "healer")
	_check(rules.targets(context, "healer", "healer_bonk").is_empty(),
		"Opening Healer Bonk has no legal targets")
	# Automatic abilities are footer buttons; a targeted action with no legal
	# targets offers no control and marks nothing on the board.
	_check(_visible_button_containing("Heal self or nearest ally") != null,
		"Selecting the Healer shows her automatic Heal as a footer button")
	_check(_visible_button_containing("Bonk and taunt") == null,
		"The unavailable targeted Bonk is not a footer action")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	_check(commit != null and commit.is_visible_in_tree() and not commit.disabled
		and (scene.get("_plan") as Dictionary).get("valid", false),
		"Unavailable Bonk leaves valid Commit available")
	_check(scene.battle_snapshot() == before, "Unavailable Bonk does not change battle state")
	await _key(KEY_ESCAPE)
	_check(scene.get("_actor_id") == "", "Escape clears the Healer selection")


func _visible_button_containing(needle: String) -> Button:
	return _visible_button_recursive(scene, needle)


func _visible_button_recursive(node: Node, needle: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree():
		var text := str((node as Button).text)
		var accessible := str((node as Button).accessibility_name)
		if needle in text or needle in accessible:
			return node as Button
	for child in node.get_children():
		var found := _visible_button_recursive(child, needle)
		if found != null:
			return found
	return null


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
