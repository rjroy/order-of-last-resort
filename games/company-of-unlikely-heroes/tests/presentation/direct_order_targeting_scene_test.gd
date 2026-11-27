extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/direct_order_targeting_scene_test.gd
# Regression for explicit ability selection, independent drafts and real board input.
var failures: Array[String] = []
var scene: Node
var rules

# A genuine board-edge Move/Summon target for the necromancer placed at (6, 2)
# on the 7x5 "road" board: (6, 1) sits on the rightmost column.
const EDGE_CELL := Vector2i(6, 1)
const EDGE_ACTOR_CELL := Vector2i(6, 2)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Instance methods (state_before_action, targets) need a rules instance;
	# only static helpers such as open_mission work on the loaded script.
	rules = load("res://rules/rules.gd").new()
	await _scenario_selection_and_pull()
	await _scenario_invalid_target()
	await _scenario_move_and_cell_ability()
	await _scenario_draft_and_cancel()
	await _scenario_occupant_choice()
	await _scenario_occupant_dismissal()
	await _scenario_leaf_hides_occupant_choice()
	await _scenario_alchemy()
	await _scenario_empty_repeat_batch()
	_finish()


func _launch(opening: Dictionary) -> bool:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	# Hand the scene its own copies so later comparisons against `opening`
	# detect mutation instead of aliasing it.
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening.duplicate(true))
	await process_frame
	return scene.current_screen() == "battle"


# Each scenario starts with a fresh scene. Board clicks travel through the viewport.
func _scenario_selection_and_pull() -> void:
	var opening := wizard_state()
	if not await _launch(opening):
		_check(false, "Wizard fixture launches")
		return
	await _click_cell(Vector2i(1, 1))
	_check(scene.get("_actor_id") == "wizard" and _staged_override("wizard").is_empty(),
		"Clicking the selected hero retains selection without staging")
	await _click_cell(Vector2i(2, 2))
	_check(scene.get("_actor_id") == "healer" and _staged_override("wizard").is_empty(),
		"Clicking an ally switches selection without Pull")
	await _click_cell(Vector2i(1, 1))
	if not await _press_ability(opening, "wizard", "wizard_pull"):
		return
	var board := _node("BridgeBoard") as Control
	if board != null:
		var marks: Array = (board.get("_overlay") as Dictionary).get("targets", [])
		var context: Dictionary = rules.state_before_action(opening, "wizard")
		var expected: Array = []
		for target in rules.targets(context, "wizard", "wizard_pull"):
			if target.position not in expected:
				expected.append(target.position)
		_check(marks.size() == expected.size() and marks.all(func(cell): return cell in expected),
			"Aiming marks only legal Pull targets")
	await _click_cell(Vector2i(2, 2))
	var staged := _staged_override("wizard")
	_check(staged.get("ability_id") == "wizard_pull" and staged.get("target_id") == "healer",
		"Choosing Pull then clicking the ally stages Pull on that ally")
	_check(scene.battle_snapshot() == opening, "Staging Pull leaves committed state unchanged")


func _scenario_invalid_target() -> void:
	var opening := wizard_state()
	if not await _launch(opening):
		_check(false, "Wizard fixture launches")
		return
	if not await _press_ability(opening, "wizard", "wizard_pull"):
		return
	await _click_cell(Vector2i(4, 4))
	_check(_staged_override("wizard").is_empty(), "An invalid aim click does not stage another action")


func _scenario_move_and_cell_ability() -> void:
	var opening := edge_state()
	if not await _launch(opening):
		_check(false, "Edge fixture launches")
		return
	var context: Dictionary = rules.state_before_action(opening, "necromancer")
	var move_legal: bool = rules.targets(context, "necromancer", "move").any(func(t): return t.position == EDGE_CELL)
	var summon_legal: bool = rules.targets(context, "necromancer", "summon_skeleton").any(func(t): return t.position == EDGE_CELL)
	_check(move_legal and summon_legal, "Edge fixture offers both Move and Summon on the destination")
	if not move_legal or not summon_legal:
		return
	await _click_cell(EDGE_CELL)
	_check(_staged_override("necromancer").get("ability_id") == "move",
		"A normal click on a shared legal destination stages Move")
	_check(scene.battle_snapshot() == opening, "Move preview does not resolve the round")
	if not await _press_ability(opening, "necromancer", "summon_skeleton"):
		return
	await _click_cell(EDGE_CELL)
	var staged := _staged_override("necromancer")
	_check(staged.get("ability_id") == "summon_skeleton" and staged.get("target_id") == "6,1",
		"Choosing Summon then clicking the same cell stages Summon")


func _scenario_draft_and_cancel() -> void:
	var opening := wizard_state()
	if not await _launch(opening):
		_check(false, "Wizard fixture launches")
		return
	if not await _press_ability(opening, "wizard", "wizard_blast"):
		return
	_check(_staged_override("wizard").get("ability_id") == "wizard_blast", "Automatic Blast stages immediately")
	var draft: Dictionary = scene.get("_planned_state").duplicate(true)
	await _click_cell(Vector2i(2, 2))
	_check(scene.get("_actor_id") == "healer" and scene.get("_planned_state") == draft,
		"Switching heroes retains the draft")
	var summary := scene.get("_storybook_page").get("_summary") as Label
	_check(summary != null and summary.is_visible_in_tree() and rules.display_name(opening, "wizard") in summary.text,
		"Draft summary remains visible and names its hero while inspecting another")
	var draft_control := _node("DraftSummary") as Control
	_check(draft_control != null and draft_control.is_visible_in_tree()
		and draft_control.focus_mode == Control.FOCUS_ALL and not draft_control.accessibility_name.is_empty(),
		"DraftSummary is visible, keyboard-focusable and has an accessible name")
	if draft_control != null and summary != null:
		_check(draft_control == summary or draft_control.is_ancestor_of(summary),
			"DraftSummary contains the complete existing summary text")
		if draft_control.is_visible_in_tree() and draft_control.focus_mode == Control.FOCUS_ALL:
			draft_control.grab_focus()
			await process_frame
			_check(scene.get_viewport().gui_get_focus_owner() == draft_control,
				"DraftSummary can receive keyboard focus")
	await _click_cell(Vector2i(1, 1))
	if not await _press_ability(opening, "wizard", "wizard_pull"):
		return
	_check(scene.get("_planned_state") == draft, "Entering aim retains the old draft")
	_check_commit_blocked(opening, "aiming")
	var cancel := _node("CancelTargeting") as Button
	_check(cancel != null and cancel.is_visible_in_tree() and not cancel.disabled,
		"CancelTargeting is visible and enabled while aiming")
	if cancel == null or not cancel.is_visible_in_tree() or cancel.disabled:
		return
	cancel.pressed.emit()
	await process_frame
	_check(scene.get("_planned_state") == draft, "Cancel targeting retains the draft")
	if not await _press_ability(opening, "wizard", "wizard_pull"):
		return
	await _press_escape()
	_check(scene.get("_planned_state") == draft, "Escape from aiming retains the draft")
	var clear := _node("ClearCommand") as Button
	_check(clear != null and clear.is_visible_in_tree() and not clear.disabled, "Clear command is available")
	if clear == null or clear.disabled:
		return
	clear.pressed.emit()
	await process_frame
	_check(scene.get("_actor_id") == "" and _staged_override("wizard").is_empty(),
		"Clear command discards the draft and returns to neutral")
	var board := _node("BridgeBoard") as Control
	_check(board != null and scene.get_viewport().gui_get_focus_owner() == board,
		"Clearing returns keyboard focus to the board")
	if board != null and scene.get_viewport().gui_get_focus_owner() == board:
		await _press_key(KEY_ENTER)
		_check(scene.get("_actor_id") != "", "The board can select a hero by keyboard from neutral")
		var clear_selection := _node("ClearCommand") as Button
		_check(clear_selection != null and not clear_selection.disabled, "Clear selection is available without a draft")
		if clear_selection != null and not clear_selection.disabled:
			clear_selection.pressed.emit()
			await process_frame
			_check(scene.get("_actor_id") == "" and scene.get_viewport().gui_get_focus_owner() == board,
				"Clear selection returns to keyboard-usable neutral")


func _scenario_occupant_choice() -> void:
	var opening := occupant_state()
	if not await _launch(opening):
		_check(false, "Occupant fixture launches")
		return
	var context: Dictionary = rules.state_before_action(opening, "necromancer")
	var moves: Array = rules.targets(context, "necromancer", "move")
	_check(not moves.is_empty(), "Occupant fixture has a legal move for an existing draft")
	if moves.is_empty():
		return
	await _click_cell(moves[0].position)
	var draft: Dictionary = scene.get("_planned_state").duplicate(true)
	_check(_staged_override("necromancer").get("ability_id") == "move", "Move draft is staged before occupant choice")
	if not await _press_ability(opening, "necromancer", "raise_dead"):
		return
	await _click_cell(Vector2i(4, 3))
	var first_name: String = rules.display_name(opening, "fallen_raider")
	var second_name: String = rules.display_name(opening, "sunken_raider")
	var first := _visible_button_containing(first_name)
	var second := _visible_button_containing(second_name)
	_check(first != null and second != null and first != second, "Stacked corpses have distinct visible choices")
	_check(scene.get("_planned_state") == draft, "Occupant choice retains the existing draft")
	_check_commit_blocked(opening, "occupant choice")
	if first == null or second == null or first == second:
		return
	_check(first_name in first.accessibility_name and second_name in second.accessibility_name,
		"Corpse choice accessible names identify their occupants")
	var viewport_rect := Rect2(Vector2.ZERO, scene.get_viewport().get_visible_rect().size)
	_check(viewport_rect.encloses(first.get_global_rect()) and viewport_rect.encloses(second.get_global_rect()),
		"Occupant choices stay inside the viewport")
	var focus := scene.get_viewport().gui_get_focus_owner()
	_check(focus == first or focus == second, "Occupant choice receives keyboard focus")
	second.pressed.emit()
	await process_frame
	var staged := _staged_override("necromancer")
	_check(staged.get("ability_id") == "raise_dead" and staged.get("target_id") == "sunken_raider",
		"Choosing the second corpse stages its identity")
	var board := _node("BridgeBoard") as Control
	_check(board != null and (board.get("_overlay") as Dictionary).get("chosen_target") == Vector2i(4, 3),
		"The shared cell remains marked for the chosen occupant")
	_check(board != null and scene.get_viewport().gui_get_focus_owner() == board,
		"Focus returns to the board after occupant choice")


func _scenario_occupant_dismissal() -> void:
	var opening := occupant_state()
	if not await _launch(opening):
		_check(false, "Occupant fixture launches")
		return
	if not await _press_ability(opening, "necromancer", "raise_dead"):
		return
	await _click_cell(Vector2i(4, 3))
	var first_name: String = rules.display_name(opening, "fallen_raider")
	var choice := _visible_button_containing(first_name)
	_check(choice != null, "Corpse choice appears before dismissal")
	await _press_escape()
	_check(_visible_button_containing(first_name) == null, "Escape dismisses the occupant choice")
	_check(_staged_override("necromancer").is_empty(), "Dismissing the choice stages nothing")
	var board := _node("BridgeBoard") as Control
	_check(board != null and scene.get_viewport().gui_get_focus_owner() != null,
		"Dismissing the choice leaves keyboard focus")
	# Re-enter aiming rather than relying on whether Escape returned to aiming or selection.
	if not await _press_ability(opening, "necromancer", "raise_dead"):
		return
	await _click_cell(Vector2i(4, 3))
	choice = _visible_button_containing(first_name)
	if choice == null:
		_check(false, "First corpse can be chosen after dismissal")
		return
	choice.pressed.emit()
	await process_frame
	_check(_staged_override("necromancer").get("target_id") == "fallen_raider",
		"Choosing the first corpse stages its own identity")


func _scenario_leaf_hides_occupant_choice() -> void:
	var opening := occupant_state()
	if not await _launch(opening):
		_check(false, "Occupant fixture launches")
		return
	if not await _press_ability(opening, "necromancer", "raise_dead"):
		return
	await _click_cell(Vector2i(4, 3))
	var name: String = rules.display_name(opening, "fallen_raider")
	_check(_visible_button_containing(name) != null, "Occupant choice is visible before opening a leaf")
	var forecast := _visible_button_containing("Forecast")
	if forecast == null:
		_check(false, "Forecast control is available")
		return
	forecast.pressed.emit()
	await process_frame
	_check(_visible_button_containing(name) == null, "Opening Forecast hides occupant choices")
	forecast.pressed.emit()
	await process_frame
	var orders := _visible_button_containing("Standing orders")
	if orders == null:
		_check(false, "Standing orders control is available")
		return
	orders.pressed.emit()
	await process_frame
	_check(_visible_button_containing(name) == null, "Opening Standing orders hides occupant choices")


func _scenario_alchemy() -> void:
	var opening := alchemist_state()
	if not await _launch(opening):
		_check(false, "Alchemist fixture launches")
		return
	var board := _node("BridgeBoard") as Control
	var disclosure := _node("LockedDose") as Label
	if board == null or disclosure == null:
		_check(false, "Board and locked dose disclosure exist")
		return
	var geometry := board.get_global_rect()
	var context: Dictionary = rules.state_before_action(opening, "alchemist")
	var dose: Dictionary = rules.dose_forecast(context, "alchemist", "alchemist_potion")
	_check(not dose.is_empty() and disclosure.is_visible_in_tree() and str(dose.get("description", "")) in disclosure.text,
		"Rules-provided dose is visible before choosing a recipient")
	await _click_cell(Vector2i(2, 2))
	_check(scene.get("_actor_id") == "alchemist" and _staged_override("alchemist").is_empty(),
		"Clicking self outside aim retains selection and does not stage potion")
	if not await _press_ability(opening, "alchemist", "alchemist_potion"):
		return
	await _click_cell(Vector2i(2, 2))
	var staged := _staged_override("alchemist")
	_check(staged.get("ability_id") == "alchemist_potion" and staged.get("target_id") == "alchemist",
		"Choosing potion then clicking self stages a self potion")
	_check(scene.battle_snapshot() == opening, "Potion preview leaves committed state unchanged")
	var summary := scene.get("_storybook_page").get("_summary") as Label
	var label: String = rules.command_ability(context, "alchemist", "alchemist_potion").get("label", "")
	_check(summary != null and summary.is_visible_in_tree() and not label.is_empty() and label in summary.text
		and rules.display_name(opening, "alchemist") in summary.text,
		"Visible draft names the potion and recipient")
	await _click_cell(Vector2i(1, 2))
	_check(scene.get("_actor_id") == "healer" and not disclosure.is_visible_in_tree(), "Switching heroes hides the dose")
	_check(summary != null and summary.is_visible_in_tree() and label in summary.text,
		"Potion draft remains visible when dose hides")
	_check(board.get_global_rect().is_equal_approx(geometry), "Hiding dose does not move or resize the board")
	await _click_cell(Vector2i(2, 2))
	_check(disclosure.is_visible_in_tree() and board.get_global_rect().is_equal_approx(geometry),
		"Showing dose again does not move or resize the board")


func _scenario_empty_repeat_batch() -> void:
	var opening := alchemist_state()
	for unit: Dictionary in opening.units:
		if unit.id == "alchemist":
			unit["upgrades"] = {"alchemist_keep_the_culture": 1}
			break
	if not await _launch(opening):
		_check(false, "Upgraded alchemist fixture launches")
		return
	var button := _node("DirectOrder_alchemist_repeat_batch") as Button
	_check(button != null and button.is_visible_in_tree() and button.disabled,
		"Repeat Batch is visible and disabled with an empty bottle")
	if button != null:
		_check("empty bottle" in (button.tooltip_text + " " + button.accessibility_description).to_lower(),
			"Repeat Batch explains the empty bottle")


func _check_commit_blocked(opening: Dictionary, phase: String) -> void:
	var commit := _node("Commit") as Button
	_check(commit != null and commit.disabled, "Commit is disabled during " + phase)
	_check(scene.battle_snapshot() == opening, "The round stays unresolved during " + phase)


func _press_ability(opening: Dictionary, actor: String, ability: String) -> bool:
	var context: Dictionary = rules.state_before_action(opening, actor)
	var label: String = rules.command_ability(context, actor, ability).get("label", "")
	var button := _visible_button_containing(label) if not label.is_empty() else null
	_check(button != null and not button.disabled, "Visible enabled ability button: " + ability)
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	await process_frame
	return true


func _visible_button_containing(needle: String) -> Button:
	return _visible_button_recursive(scene, needle)


func _visible_button_recursive(node: Node, needle: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree():
		var text := str((node as Button).text)
		var accessible := str((node as Button).accessibility_name)
		if needle.to_lower() in text.to_lower() or needle.to_lower() in accessible.to_lower():
			return node as Button
	for child in node.get_children():
		var found := _visible_button_recursive(child, needle)
		if found != null:
			return found
	return null


func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _staged_override(actor: String) -> Dictionary:
	return scene.get("_planned_state").get("overrides", {}).get(actor, {})


# ---------------------------------------------------------------------
# Fixtures. Placement order matters: the launch auto-selects the first
# living commandable unit.
# ---------------------------------------------------------------------
static func _catalog_defs() -> Dictionary:
	var defs: Dictionary = load("res://content/catalog.gd").read_default().duplicate(true)
	defs.characters.practice_raider = defs.characters.grunt.duplicate(true)
	defs.characters.practice_raider.behavior = "hold"
	return defs


static func _mission_state(defs: Dictionary, mission_id: String) -> Dictionary:
	return load("res://rules/rules.gd").open_mission(defs, mission_id)


static func necromancer_state() -> Dictionary:
	var defs := _catalog_defs()
	defs.encounters.direct_order_basic_encounter = {"board": "road", "seed": 2, "placements": [
		{"id": "healer", "character": "healer", "at": [1, 1]},
		{"id": "necromancer", "character": "necromancer", "at": [2, 2]},
		{"id": "practice_raider", "character": "practice_raider", "at": [3, 1]},
		{"id": "fallen_raider", "character": "harpooner", "at": [4, 3], "hp": 0},
	]}
	defs.missions.direct_order_basic_mission = defs.missions.shield_wall.duplicate(true)
	defs.missions.direct_order_basic_mission.encounter = "direct_order_basic_encounter"
	defs.missions.direct_order_basic_mission.erase("default_party")
	return _mission_state(defs, "direct_order_basic_mission")


static func wizard_state() -> Dictionary:
	var defs := _catalog_defs()
	defs.encounters.direct_order_wizard_encounter = {"board": "road", "seed": 2, "placements": [
		{"id": "wizard", "character": "wizard", "at": [1, 1]},
		{"id": "healer", "character": "healer", "at": [2, 2]},
	]}
	defs.missions.direct_order_wizard_mission = defs.missions.shield_wall.duplicate(true)
	defs.missions.direct_order_wizard_mission.encounter = "direct_order_wizard_encounter"
	defs.missions.direct_order_wizard_mission.erase("default_party")
	return _mission_state(defs, "direct_order_wizard_mission")


static func edge_state() -> Dictionary:
	var defs := _catalog_defs()
	defs.encounters.direct_order_edge_encounter = {"board": "road", "seed": 2, "placements": [
		{"id": "necromancer", "character": "necromancer", "at": [6, 2]},
		{"id": "healer", "character": "healer", "at": [1, 1]},
		{"id": "practice_raider", "character": "practice_raider", "at": [3, 1]},
		{"id": "fallen_raider", "character": "harpooner", "at": [4, 3], "hp": 0},
	]}
	defs.missions.direct_order_edge_mission = defs.missions.shield_wall.duplicate(true)
	defs.missions.direct_order_edge_mission.encounter = "direct_order_edge_encounter"
	defs.missions.direct_order_edge_mission.erase("default_party")
	return _mission_state(defs, "direct_order_edge_mission")


static func occupant_state() -> Dictionary:
	var defs := _catalog_defs()
	defs.encounters.direct_order_occupant_encounter = {"board": "road", "seed": 2, "placements": [
		{"id": "necromancer", "character": "necromancer", "at": [2, 2]},
		{"id": "fallen_raider", "character": "harpooner", "at": [4, 3], "hp": 0},
		{"id": "sunken_raider", "character": "grunt", "at": [4, 2], "hp": 0},
	]}
	defs.missions.direct_order_occupant_mission = defs.missions.shield_wall.duplicate(true)
	defs.missions.direct_order_occupant_mission.encounter = "direct_order_occupant_encounter"
	defs.missions.direct_order_occupant_mission.erase("default_party")
	var state := _mission_state(defs, "direct_order_occupant_mission")
	# The catalog validator forbids overlapping placements, but two defeats
	# on one tile are a legal runtime shape: stack the second corpse in the
	# built state.
	for unit in state.units:
		if unit.id == "sunken_raider":
			unit.position = Vector2i(4, 3)
	return state


static func alchemist_state() -> Dictionary:
	var defs := _catalog_defs()
	defs.encounters.direct_order_alchemist_encounter = {"board": "road", "seed": 2, "placements": [
		{"id": "alchemist", "character": "alchemist", "at": [2, 2]},
		{"id": "healer", "character": "healer", "at": [1, 2]},
		{"id": "practice_raider", "character": "practice_raider", "at": [3, 1]},
	]}
	defs.missions.direct_order_alchemist_mission = defs.missions.shield_wall.duplicate(true)
	defs.missions.direct_order_alchemist_mission.encounter = "direct_order_alchemist_encounter"
	defs.missions.direct_order_alchemist_mission.erase("default_party")
	return _mission_state(defs, "direct_order_alchemist_mission")


# ---------------------------------------------------------------------
# Real board and key input.
# ---------------------------------------------------------------------
func _click_cell(cell: Vector2i) -> void:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		_check(false, "The bridge board is available")
		return
	var point: Vector2 = board.get_global_transform_with_canvas() * board.cell_center(cell)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		scene.get_viewport().push_input(event, true)
		await process_frame


func _press_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	press.echo = false
	scene.get_viewport().push_input(press, true)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	release.echo = false
	scene.get_viewport().push_input(release, true)
	await process_frame


func _press_escape() -> void:
	await _press_key(KEY_ESCAPE)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: direct_order_targeting_scene_test")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
