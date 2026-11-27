extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_gate_scene_test.gd
# Board, keyboard, ability and leaf controls use viewport input. Automatic
# abilities stage immediately; targeted abilities aim, then take a board click.
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
	_check(scene.get("_actor_id") == "", "Clear command returns to neutral")
	_check(cleared.get("orders", {}).get("knight") == "order_guard", "Clearing restores Knight's default Guard")
	_check(scene.battle_snapshot() == before, "Clearing a move leaves actual state unchanged")
	_check_other_orders(before)
	var guard_plan: Dictionary = rules.preview_round(cleared)
	_check(scene.get("_plan") == guard_plan, "Cleared forecast uses standing orders including Guard")

	await _click_cell(board, knight.position)
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
	_check(scene.find_child("Actions", true, false) == null, "The old Actions menu is removed")
	_check_ability("wizard_blast", "Blast", true)
	_check_ability("wizard_pull", "Pull and recoil", true)
	_check_ability("move", "Move one tile", true)
	# The guard is outside Blast's reach. The Knight is farther away than
	# the Healer but remains a legal direct target.
	var guard := _unit(before, "gate_guard")
	var knight := _unit(before, "knight")
	if guard.is_empty() or knight.is_empty():
		_check(false, "Gate opens with a guard and Knight")
		return
	if not await _click_button("DirectOrder_wizard_blast"):
		return
	_check(scene.get("_aimed_ability_id") == "wizard_blast"
		and (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Pressing Blast aims without staging a command")
	_check(guard.position not in _highlighted_cells(board), "Aimed Blast excludes the out-of-range guard")
	_check(knight.position in _highlighted_cells(board), "Aimed Blast marks the farther legal Knight")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	_check(commit != null and commit.is_visible_in_tree() and commit.disabled,
		"Commit is disabled until Blast has a target")
	await _click_cell(board, knight.position)
	_check_wizard_command("wizard_blast", "knight", "Clicking the marked Knight stages Blast on the Knight")
	_check(scene.get("_aimed_ability_id") == "" and commit != null and not commit.disabled,
		"Choosing a Blast target ends aiming and enables Commit")
	var page: Node = scene.get("_storybook_page")
	_check((page.get("_target_rows") as Array).is_empty(),
		"The Knight on his own cell needs no occupant picker")
	_check(scene.battle_snapshot() == before, "Blast forecast does not commit actual battle state")
	var plan: Dictionary = scene.get("_plan")
	var blast_text := ""
	var knight_reflect := false
	for event in plan.get("events", []):
		if event.get("type") == "reflect" and event.get("ward_id") == "knight" \
				and event.get("target_id") == "gate_guard":
			knight_reflect = true
		if event.get("type") == "damage" and event.get("source_id") == "wizard" \
				and event.get("ability_id") == "wizard_blast" and event.get("target_id") == "gate_guard":
			blast_text = str(event.get("text", ""))
	_check(plan.get("valid", false) and knight_reflect and not blast_text.is_empty()
		and _unit(plan.get("result", {}), "healer").get("hp") == _unit(before, "healer").get("hp"),
		"Blast forecast targets the Knight, whose Guard reflects it to the out-of-range guard")
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
	_check(scene.get("_actor_id") == "wizard", "Clicking Wizard selects Wizard")
	var selection_marks := _highlighted_cells(board)
	_check(step in selection_marks and healer not in selection_marks and knight not in selection_marks,
		"Wizard selection marks quick Move destinations, not unarmed Pull targets")
	await _click_cell(board, healer)
	_check(scene.get("_actor_id") == "healer"
		and (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Clicking a legal Pull target outside aiming selects the ally instead")
	await _click_cell(board, _unit(before, "wizard").position)
	if not await _click_button("DirectOrder_wizard_pull"):
		return
	var marks := _highlighted_cells(board)
	_check(scene.get("_aimed_ability_id") == "wizard_pull" and healer in marks and knight in marks,
		"Aiming Pull marks both legal allies")
	_check(step not in marks and Vector2i(1, 1) not in marks,
		"Aiming Pull leaves the Move destination and an invalid cell unmarked")
	await _hover(board.get_global_transform_with_canvas() * board.cell_center(healer))
	var inspection: Label = scene.get("_storybook_page").get("_inspection")
	var aim_note := "Legal target"
	_check(inspection.is_visible_in_tree() and aim_note in inspection.text and aim_note in board.tooltip_text,
		"Hovering a marked ally advertises the legal Pull target in inspection and tooltip")
	await _click_cell(board, healer)
	_check_wizard_command("wizard_pull", "healer", "Clicking the marked healer stages Pull on her")
	_check(scene.get("_aimed_ability_id") == "" and step in _highlighted_cells(board)
		and healer not in _highlighted_cells(board) and knight not in _highlighted_cells(board),
		"Staging Pull ends aiming and restores quick Move marks")
	if not await _click_button("DirectOrder_wizard_pull"):
		return
	await _hover(board.get_global_transform_with_canvas() * board.cell_center(healer))
	await _key(KEY_ESCAPE)
	_check_wizard_command("wizard_pull", "healer", "Escape from aiming retains the staged Pull")
	_check(scene.get("_aimed_ability_id") == "" and healer not in _highlighted_cells(board)
		and knight not in _highlighted_cells(board), "Escape removes the aimed Pull marks")
	_check(aim_note not in inspection.text and aim_note not in board.tooltip_text,
		"Canceling aim drops the stale legal-target text without mouse motion")
	if not await _click_button("DirectOrder_wizard_pull"):
		return
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
	await _click_cell(board, _unit(before, "healer").position)
	_check(scene.get("_actor_id") == "healer", "Clicking the Healer selects her")
	var context: Dictionary = rules.state_before_action(scene.get("_planned_state"), "healer")
	_check(rules.targets(context, "healer", "healer_bonk").is_empty(),
		"Opening Healer Bonk has no legal targets")
	_check_ability("healer_heal", "Heal", true)
	var bonk := _check_ability("healer_bonk", "Bonk and taunt", false)
	if bonk != null:
		var explanation := "%s %s %s" % [bonk.text, bonk.accessibility_name, bonk.tooltip_text]
		_check("no legal target" in explanation.to_lower(), "The disabled Bonk explains why it is unavailable")
		await _click(bonk.get_global_rect().get_center())
	_check(scene.get("_aimed_ability_id") == ""
		and (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Using the unavailable Bonk neither aims nor stages it")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	_check(commit != null and commit.is_visible_in_tree() and not commit.disabled
		and (scene.get("_plan") as Dictionary).get("valid", false),
		"Unavailable Bonk leaves valid Commit available")
	_check(scene.battle_snapshot() == before, "Unavailable Bonk does not change battle state")
	await _key(KEY_ESCAPE)
	_check(scene.get("_actor_id") == "", "Escape clears the Healer selection")


func _check_ability(id: String, label: String, enabled: bool) -> Button:
	var button := scene.find_child("DirectOrder_" + id, true, false) as Button
	_check(button != null and button.is_visible_in_tree() and str(button.get_meta("ability_id", "")) == id
		and (label == button.text or label == button.accessibility_name) and button.disabled != enabled,
		"Visible Direct Order %s has its label, identity and expected enabled state" % id)
	return button


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
