extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/direct_order_targeting_scene_test.gd
# Regression for the approved target-first Direct Order interaction: board
# clicks stage targeted abilities immediately, ambiguous cells present a
# target-anchored contextual choice with per-target identity that never
# draws above an open leaf and takes keyboard focus directly, automatic
# abilities are named footer buttons, selection marks the union of legal
# targets, legal self targets stage instead of clearing, the locked dose
# shows on selection, keyboard focus returns to the board after a choice,
# the legacy Actions/Targets menus are gone, and clearing selection never
# discards a staged command.
# Every scenario launches a fresh main scene with its own fixture state.
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
	await _scenario_unique_target_stages()
	await _scenario_friendly_pull_priority()
	await _scenario_non_targetable_switching()
	await _scenario_clearing_retains_command()
	await _scenario_unambiguous_move()
	await _scenario_choice_and_edge_placement()
	await _scenario_occupant_choice_identity()
	await _scenario_leaf_hides_choice()
	await _scenario_keyboard_choice_focus()
	await _scenario_automatic_footer_action()
	await _scenario_selection_marks_union()
	await _scenario_choice_without_legacy_menus()
	await _scenario_self_potion_priority()
	await _scenario_locked_dose_on_selection()
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


# ---------------------------------------------------------------------
# A unique legal target stages immediately without mutating committed state.
# ---------------------------------------------------------------------
func _scenario_unique_target_stages() -> void:
	var opening := necromancer_state()
	if not await _launch(opening):
		_check(false, "The necromancer fixture launches into battle")
		return
	await _click_cell(Vector2i(2, 2))
	_check(scene.get("_actor_id") == "necromancer", "Clicking the necromancer selects it")
	await _click_cell(Vector2i(4, 3))
	var staged: Dictionary = _staged_override("necromancer")
	_check(staged.get("ability_id") == "raise_dead",
		"A unique corpse target stages Raise Dead immediately")
	_check(staged.get("target_id") == "fallen_raider",
		"The staged target is the corpse")
	_check(scene.battle_snapshot() == opening,
		"Staging does not mutate the committed battle state")


# ---------------------------------------------------------------------
# A legal friendly target stages Wizard Pull and keeps the actor selected.
# ---------------------------------------------------------------------
func _scenario_friendly_pull_priority() -> void:
	if not await _launch(wizard_state()):
		_check(false, "The wizard fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "wizard", "The wizard is selected after launch")
	await _click_cell(Vector2i(2, 2))
	var staged: Dictionary = _staged_override("wizard")
	_check(staged.get("ability_id") == "wizard_pull",
		"A legal friendly target stages Wizard Pull instead of switching heroes")
	_check(staged.get("target_id") == "healer",
		"The staged friendly target is the healer")
	_check(scene.get("_actor_id") == "wizard",
		"Staging a friendly targeted action keeps the acting hero selected")


# ---------------------------------------------------------------------
# A friendly hero that is not a legal target switches selection.
# ---------------------------------------------------------------------
func _scenario_non_targetable_switching() -> void:
	if not await _launch(wizard_state()):
		_check(false, "The wizard fixture launches into battle")
		return
	await _press_escape()
	_check(scene.get("_actor_id") == "", "Escape clears the initial selection")
	await _click_cell(Vector2i(2, 2))
	_check(scene.get("_actor_id") == "healer", "Clicking the healer selects it")
	await _click_cell(Vector2i(1, 1))
	_check(scene.get("_actor_id") == "wizard",
		"A non-targetable friendly hero switches selection")


# ---------------------------------------------------------------------
# Selected-hero and Escape clearing retain a genuinely staged command.
# ---------------------------------------------------------------------
func _scenario_clearing_retains_command() -> void:
	if not await _launch(necromancer_state()):
		_check(false, "The necromancer fixture launches into battle")
		return
	await _click_cell(Vector2i(2, 2))
	await _click_cell(Vector2i(4, 3))
	_check(_staged_override("necromancer").get("ability_id") == "raise_dead",
		"Raise Dead is staged before the clearing checks")
	var retained: Dictionary = scene.get("_planned_state").duplicate(true)
	await _click_cell(Vector2i(2, 2))
	_check(scene.get("_actor_id") == "", "Clicking the selected hero clears selection")
	_check(scene.get("_planned_state") == retained,
		"Clearing selection retains the staged command")
	await _click_cell(Vector2i(2, 2))
	_check(scene.get("_actor_id") == "necromancer", "Clicking the hero again reselects it")
	await _press_escape()
	_check(scene.get("_actor_id") == "", "Escape clears the current hero selection")
	_check(scene.get("_planned_state") == retained,
		"Escape retains an already staged command")


# ---------------------------------------------------------------------
# An unambiguous empty destination stages Move directly.
# ---------------------------------------------------------------------
func _scenario_unambiguous_move() -> void:
	if not await _launch(necromancer_state()):
		_check(false, "The necromancer fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "healer", "The healer is selected after launch")
	await _click_cell(Vector2i(0, 1))
	var staged: Dictionary = _staged_override("healer")
	_check(staged.get("ability_id") == "move",
		"An unambiguous empty destination stages Move immediately")
	_check(staged.get("target_id") == "0,1", "The staged Move uses cell 0,1")


# ---------------------------------------------------------------------
# Move and Summon compete on one edge cell: nothing stages before the
# choice, each choice button stages its own action, and the open choice
# presents accessible target-anchored buttons (plan step 3 placement).
# ---------------------------------------------------------------------
func _scenario_choice_and_edge_placement() -> void:
	var opening := edge_state()
	if not await _launch(opening):
		_check(false, "The edge fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "necromancer", "The necromancer is selected after launch")
	# Guard the fixture: this cell must stay a legal edge target for both actions.
	var context: Dictionary = rules.state_before_action(opening, "necromancer")
	var move_legal: bool = rules.targets(context, "necromancer", "move").any(
		func(choice: Dictionary) -> bool: return choice.position == EDGE_CELL)
	var summon_legal: bool = rules.targets(context, "necromancer", "summon_skeleton").any(
		func(choice: Dictionary) -> bool: return choice.position == EDGE_CELL)
	_check(move_legal and summon_legal,
		"Cell 6,1 is a legal Move and Summon destination on the board edge")
	if not move_legal or not summon_legal:
		return
	await _click_cell(EDGE_CELL)
	_check(not scene.get("_planned_state").get("overrides", {}).has("necromancer"),
		"An ambiguous cell stages no command while the choice is open")
	if _find_button_containing("Summon") == null:
		_check(false, "The Summon choice button is offered")
	else:
		await _press_choice_containing("Summon")
	var summon_staged: Dictionary = _staged_override("necromancer")
	_check(summon_staged.get("ability_id") == "summon_skeleton",
		"Choosing Summon Skeleton from the cell choice stages that ability")
	_check(summon_staged.get("target_id") == "6,1",
		"Summon Skeleton targets the clicked edge cell")
	await _click_cell(EDGE_CELL)
	if _find_button_containing("Move") == null:
		_check(false, "The Move choice button is offered")
	else:
		await _press_choice_containing("Move")
	var move_staged: Dictionary = _staged_override("necromancer")
	_check(move_staged.get("ability_id") == "move",
		"Choosing Move from the same cell stages Move")
	_check(move_staged.get("target_id") == "6,1", "Move targets the clicked edge cell")
	# Re-open the choice to exercise where the buttons are placed.
	await _click_cell(EDGE_CELL)
	_check(scene.get("_actor_id") == "necromancer",
		"The open choice keeps the selected hero")
	_check(_find_button_containing("Move") != null and _find_button_containing("Summon") != null,
		"Target-adjacent choice buttons are offered at the edge target")
	_check_placement_for_button("Move")
	_check_placement_for_button("Summon")


# ---------------------------------------------------------------------
# Two raisable corpses share one cell: each choice button must name its
# target so the pair stays distinguishable.
# ---------------------------------------------------------------------
func _scenario_occupant_choice_identity() -> void:
	var opening := occupant_state()
	if not await _launch(opening):
		_check(false, "The occupant fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "necromancer", "The necromancer is selected after launch")
	await _click_cell(Vector2i(4, 3))
	var first_name: String = rules.display_name(opening, "fallen_raider")
	var second_name: String = rules.display_name(opening, "sunken_raider")
	var first_button := _find_button_containing(first_name)
	var second_button := _find_button_containing(second_name)
	_check(first_button != null, "The fallen raider choice names its corpse")
	_check(second_button != null, "The sunken raider choice names its corpse")
	if first_button == null or second_button == null:
		return
	_check(str(first_button.text) != str(second_button.text),
		"Two corpses on one cell offer distinguishable choices")
	_check(first_name in str(first_button.accessibility_name),
		"The corpse choice accessible name carries the fallen raider identity")
	_check(second_name in str(second_button.accessibility_name),
		"The corpse choice accessible name carries the sunken raider identity")
	first_button.pressed.emit()
	await process_frame
	var staged: Dictionary = _staged_override("necromancer")
	_check(staged.get("ability_id") == "raise_dead" and staged.get("target_id") == "fallen_raider",
		"Pressing a named corpse choice stages that corpse")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		_check(false, "The bridge board is available for the chosen-target checks")
		return
	var overlay: Dictionary = board.get("_overlay")
	_check(overlay.get("chosen_target") == Vector2i(4, 3),
		"Staging the first corpse marks the shared cell as the chosen target")
	# The position-deduplicated marks must not lose the chosen-target marker
	# when the staged occupant is not the pair kept for the shared cell.
	await _click_cell(Vector2i(4, 3))
	var later_button := _find_button_containing(second_name)
	if later_button == null:
		_check(false, "The sunken raider choice is offered again for restaging")
		return
	later_button.pressed.emit()
	await process_frame
	var restaged: Dictionary = _staged_override("necromancer")
	_check(restaged.get("ability_id") == "raise_dead" and restaged.get("target_id") == "sunken_raider",
		"Pressing the other named corpse choice restages that corpse")
	overlay = board.get("_overlay")
	_check(overlay.get("chosen_target") == Vector2i(4, 3),
		"Staging the non-first occupant keeps the shared cell marked as the chosen target")


# ---------------------------------------------------------------------
# The floating choice must not stay drawn above an open Forecast or
# Standing orders leaf.
# ---------------------------------------------------------------------
func _scenario_leaf_hides_choice() -> void:
	if not await _launch(edge_state()):
		_check(false, "The edge fixture launches into battle")
		return
	await _click_cell(EDGE_CELL)
	var summon := _find_button_containing("Summon")
	_check(summon != null and summon.is_visible_in_tree(),
		"The floating choice is visible before a leaf opens")
	var forecast := _find_button_containing("Forecast")
	if forecast == null:
		_check(false, "The Forecast control is available")
		return
	forecast.pressed.emit()
	await process_frame
	summon = _find_button_containing("Summon")
	_check(summon == null or not summon.is_visible_in_tree(),
		"Opening the forecast leaf hides the floating choice")
	forecast.pressed.emit()
	await process_frame
	var orders := _find_button_containing("Standing orders")
	if orders == null:
		_check(false, "The Standing orders control is available")
		return
	orders.pressed.emit()
	await process_frame
	summon = _find_button_containing("Summon")
	_check(summon == null or not summon.is_visible_in_tree(),
		"Opening the standing orders leaf hides the floating choice")
	orders.pressed.emit()
	await process_frame


# ---------------------------------------------------------------------
# Keyboard flow: Enter on an ambiguous cell opens the choice with focus
# moved directly onto a choice button, so Enter can select without
# tabbing through the footer.
# ---------------------------------------------------------------------
func _scenario_keyboard_choice_focus() -> void:
	if not await _launch(edge_state()):
		_check(false, "The edge fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "necromancer", "The necromancer is selected after launch")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		_check(false, "The bridge board is available for keyboard navigation")
		return
	board.grab_focus()
	await process_frame
	_check(scene.get_viewport().gui_get_focus_owner() == board,
		"The battle board holds keyboard focus")
	await _press_key(KEY_UP)
	_check(scene.get("_storybook_focus_cell") == Vector2i(6, 1),
		"Arrow keys move the board cursor to the choice cell")
	await _press_key(KEY_ENTER)
	_check(_find_button_containing("Move") != null and _find_button_containing("Summon") != null,
		"Enter on the ambiguous cell opens the choice")
	var focus := scene.get_viewport().gui_get_focus_owner()
	var focused_text := ""
	if focus is Button:
		focused_text = str((focus as Button).text)
	_check("Move" in focused_text or "Summon" in focused_text,
		"Opening a choice through the keyboard moves focus directly to a choice button")
	if focused_text.is_empty():
		return
	var expected: String = "summon_skeleton" if "Summon" in focused_text else "move"
	await _press_key(KEY_ENTER)
	var staged: Dictionary = _staged_override("necromancer")
	_check(staged.get("ability_id") == expected,
		"Enter selects the focused choice without tabbing through the footer")
	# The choice closes; focus must return to the board so keyboard play
	# continues without reaching for the pointer.
	if scene.get_viewport().gui_get_focus_owner() != board:
		_check(false, "Focus returns to the board after the choice stages")
		return
	_check(scene.get("_storybook_focus_cell") == EDGE_ACTOR_CELL,
		"The board cursor restarts on the selected hero when focus returns")
	await _press_key(KEY_UP)
	_check(scene.get("_storybook_focus_cell") == EDGE_CELL,
		"Arrow keys still move the board cursor after the choice closes")
	await _press_key(KEY_DOWN)
	await _press_key(KEY_ENTER)
	_check(scene.get("_actor_id") == "",
		"Enter on the selected hero clears the selection after a choice")


# ---------------------------------------------------------------------
# Automatic abilities are visible named footer buttons and stage directly;
# targeted abilities are not footer actions and the old Actions menu is
# removed.
# ---------------------------------------------------------------------
func _scenario_automatic_footer_action() -> void:
	if not await _launch(wizard_state()):
		_check(false, "The wizard fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "wizard", "The wizard is selected after launch")
	_check(_node("Actions") == null, "The old Actions menu is removed")
	var blast := _visible_button_containing("Blast nearest")
	_check(blast != null, "Selecting the Wizard shows a named footer button for the automatic Blast")
	_check(_visible_button_containing("Pull and recoil") == null,
		"The targeted Pull is not a footer action")
	_check(_visible_button_containing("Move one tile") == null,
		"The targeted Move is not a footer action")
	if blast == null:
		return
	blast.pressed.emit()
	await process_frame
	var staged: Dictionary = _staged_override("wizard")
	_check(staged.get("ability_id") == "wizard_blast" and staged.get("target_id", "") == "",
		"The automatic footer button stages Blast directly without a target")


# ---------------------------------------------------------------------
# Selecting a hero marks the union of legal targets across all targeted
# actions; clearing the selection removes those marks.
# ---------------------------------------------------------------------
func _scenario_selection_marks_union() -> void:
	if not await _launch(wizard_state()):
		_check(false, "The wizard fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "wizard", "The wizard is selected after launch")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		_check(false, "The bridge board is available for mark checks")
		return
	var marks: Array = (board.get("_overlay") as Dictionary).get("targets", [])
	_check(Vector2i(2, 2) in marks, "Wizard selection marks the legal Pull target")
	_check(Vector2i(0, 1) in marks, "Wizard selection also marks legal Move destinations")
	_check(not (Vector2i(4, 4) in marks), "A cell outside every targeted action stays unmarked")
	await _click_cell(Vector2i(1, 1))
	_check(scene.get("_actor_id") == "", "Clicking the selected hero clears selection")
	if Vector2i(2, 2) in marks:
		var cleared_marks: Array = (board.get("_overlay") as Dictionary).get("targets", [])
		_check(cleared_marks.is_empty(), "Clearing the selection removes the legal-target marks")


# ---------------------------------------------------------------------
# When a contextual choice opens, only the floating accessible choice
# surface is offered: the legacy Actions and Targets menus are gone.
# ---------------------------------------------------------------------
func _scenario_choice_without_legacy_menus() -> void:
	if not await _launch(edge_state()):
		_check(false, "The edge fixture launches into battle")
		return
	await _click_cell(EDGE_CELL)
	_check(_find_button_containing("Move") != null and _find_button_containing("Summon") != null,
		"The floating choice surface is offered")
	_check(_node("Actions") == null, "The old Actions menu is removed")
	var targets_menu := _node("Targets") as Control
	_check(targets_menu == null or not targets_menu.is_visible_in_tree(),
		"An open choice uses only the floating surface, not the legacy Targets menu")


# ---------------------------------------------------------------------
# Self-target priority: a fresh Alchemist's own cell is a legal potion
# target, so clicking it stages the self potion instead of clearing the
# selection. Heroes without a legal self target keep the own-cell clear.
# ---------------------------------------------------------------------
func _scenario_self_potion_priority() -> void:
	if not await _launch(alchemist_state()):
		_check(false, "The alchemist fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "alchemist", "The alchemist is selected after launch")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		_check(false, "The bridge board is available for the self-potion checks")
		return
	var marks: Array = (board.get("_overlay") as Dictionary).get("targets", [])
	_check(Vector2i(2, 2) in marks,
		"The alchemist's own cell is marked as a legal potion target")
	await _click_cell(Vector2i(2, 2))
	var staged: Dictionary = _staged_override("alchemist")
	_check(staged.get("ability_id") == "alchemist_potion",
		"Clicking the selected hero's own cell stages its legal self potion")
	_check(staged.get("target_id") == "alchemist",
		"The self potion targets the Alchemist herself")
	_check(scene.get("_actor_id") == "alchemist",
		"Staging the self potion retains the Alchemist's selection")


# ---------------------------------------------------------------------
# Target-first locked dose: selecting a hero with a dose ability shows the
# locked dose disclosure before any target is chosen; clearing the
# selection hides it again.
# ---------------------------------------------------------------------
func _scenario_locked_dose_on_selection() -> void:
	var opening := alchemist_state()
	if not await _launch(opening):
		_check(false, "The alchemist fixture launches into battle")
		return
	_check(scene.get("_actor_id") == "alchemist", "The alchemist is selected after launch")
	# The dose expectation comes from the rules on this exact fixture state,
	# never from a hardcoded recipe or draw.
	var context: Dictionary = rules.state_before_action(opening, "alchemist")
	var dose_descriptions: Array = []
	for choice in rules.options(opening, "alchemist"):
		if choice.kind != "action":
			continue
		var dose: Dictionary = rules.dose_forecast(context, "alchemist", choice.id)
		if not dose.is_empty():
			dose_descriptions.append(str(dose.get("description", "")))
	if dose_descriptions.is_empty():
		_check(false, "The alchemist fixture has a legal dose ability")
		return
	var disclosure := _node("LockedDose") as Label
	if disclosure == null:
		_check(false, "The locked dose disclosure is available")
		return
	_check(disclosure.is_visible_in_tree(),
		"Selecting the Alchemist shows the locked dose before a target is chosen")
	if not disclosure.is_visible_in_tree():
		return
	var shown := false
	for description in dose_descriptions:
		if not str(description).is_empty() and str(description) in disclosure.text:
			shown = true
	_check(shown, "The locked dose shows the current rules-provided dose")
	# Staging a targeted dose command must not leave the summary suppressed:
	# the dose disclosure may hide or stay, but the normal command preview
	# remains visible and describes the staged action and target.
	await _click_cell(Vector2i(2, 2))
	var staged_dose: Dictionary = _staged_override("alchemist")
	_check(staged_dose.get("ability_id") == "alchemist_potion" and staged_dose.get("target_id") == "alchemist",
		"Staging the targeted self potion keeps a staged dose command")
	var summary := scene.get("_storybook_page").get("_summary") as Label
	if staged_dose.get("ability_id") != "alchemist_potion" or summary == null:
		_check(false, "The command summary is available after a staged dose command")
		return
	_check(summary.is_visible_in_tree(),
		"The command summary stays visible after staging a targeted dose command")
	if summary.is_visible_in_tree():
		var action_label: String = str(rules.command_ability(context, "alchemist", "alchemist_potion").get("label", ""))
		_check(action_label in summary.text and rules.display_name(opening, "alchemist") in summary.text,
			"The command summary describes the staged dose action and target")
	await _press_escape()
	_check(not disclosure.is_visible_in_tree(),
		"Clearing the selection hides the locked dose disclosure")


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


func _check_placement_for_button(needle: String) -> void:
	var button := _find_button_containing(needle)
	if button == null:
		_check(false, "The %s choice button is offered at the edge target" % needle)
		return
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		_check(false, "The bridge board is available for placement checks")
		return
	var accessible := str(button.accessibility_name)
	_check(needle.to_lower() in accessible.to_lower(),
		"The %s choice button has an accessible name" % needle)
	var rect: Rect2 = button.get_global_rect()
	var target_center: Vector2 = board.get_global_transform_with_canvas() * board.cell_center(EDGE_CELL)
	var selected_center: Vector2 = board.get_global_transform_with_canvas() * board.cell_center(EDGE_ACTOR_CELL)
	var viewport_rect := Rect2(Vector2.ZERO, scene.get_viewport().get_visible_rect().size)
	_check(viewport_rect.encloses(rect), "The %s choice button stays inside the viewport" % needle)
	_check(rect.position.y < _footer_top(),
		"The %s choice button is beside the board, not in the footer" % needle)
	var cell_span: float = board.cell_center(Vector2i(1, 0)).distance_to(board.cell_center(Vector2i(0, 0)))
	_check(rect.get_center().distance_to(target_center) <= cell_span * 2.5,
		"The %s choice button sits beside the clicked target" % needle)
	_check(not rect.has_point(target_center),
		"The %s choice button does not cover the target" % needle)
	_check(not rect.has_point(selected_center),
		"The %s choice button does not cover the selected hero" % needle)


func _footer_top() -> float:
	var clear := scene.find_child("ClearCommand", true, false) as Control
	if clear == null:
		return 10000.0
	return clear.get_global_rect().position.y


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


func _press_choice_containing(needle: String) -> void:
	var button := _find_button_containing(needle)
	if button == null:
		_check(false, "The %s choice button is available" % needle)
		return
	button.pressed.emit()
	await process_frame


func _find_button_containing(needle: String) -> Button:
	return _find_button_recursive(scene, needle)


func _find_button_recursive(node: Node, needle: String) -> Button:
	if node is Button:
		var text := str((node as Button).text)
		var accessible := str((node as Button).accessibility_name)
		if needle.to_lower() in text.to_lower() or needle.to_lower() in accessible.to_lower():
			return node as Button
	for child in node.get_children():
		var found := _find_button_recursive(child, needle)
		if found != null:
			return found
	return null


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
