extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/single_battle_ui_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const RulesCatalog = preload("res://tests/fixtures/rules_catalog.gd")
const FIXTURE_MISSION := "single_ui_fixture"
const GATE_BOARD := "frontier_gate_board"
const LONG_KNIGHT := "Dame Alexandria of Dawn, Knight of the Golden Orchard and South March"
var failures: Array[String] = []
var scene: Node
var fixture_path := "user://single_battle_ui_%d.json" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 820)
	var definitions: Dictionary = Catalog.read_default()
	if definitions.is_empty():
		_check(false, "Built-in catalog loads")
		_finish()
		return
	# These standalone fixtures are not referenced by stock guild routes.
	for id in ["ferryman", "necromancer_wave", "extra_knight"]:
		_check(not definitions.get("missions", {}).has(id),
			"Standalone regression mission " + id + " is absent from the built-in catalog")

	# Generate an external catalog with its own mission and encounter. Deliberately
	# collide with the stock field board ID to exercise the procedural fallback.
	var fixture := definitions.duplicate(true)
	fixture.missions[FIXTURE_MISSION] = fixture.missions.shield_wall.duplicate(true)
	fixture.missions[FIXTURE_MISSION].title = "External UI fixture"
	fixture.missions[FIXTURE_MISSION].encounter = "single_ui_encounter"
	fixture.encounters["single_ui_encounter"] = fixture.encounters.frontier_shield_wall.duplicate(true)
	fixture.boards.frontier_field.width = 8
	if not _write_fixture(fixture):
		_finish()
		return

	await _launch(PackedStringArray(["--mission=shield_wall"]))
	await _exercise_battle("built-in", false)
	await _launch_external(FIXTURE_MISSION)
	await _exercise_battle("external", true)
	await _exercise_external_gate(Vector2i(9, 6), LONG_KNIGHT)
	await _exercise_external_gate(Vector2i(18, 5), LONG_KNIGHT + ", Keeper of the Autumn Road and Seven Bridges", true)

	# A retired flag may be rejected or treated as an alias, but it must never
	# lead to the old command desk. Inspect options before launch because an
	# intentionally rejected launch quits the headless tree.
	var options: Dictionary = scene.call("_read_launch_options", PackedStringArray(["--test-ui"]))
	if not options.has("error"):
		await _launch(PackedStringArray(["--mission=shield_wall", "--test-ui"]))
		_check_storybook("test-ui alias")
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) != OK:
		_check(false, "External catalog fixture is removed")
	_finish()


func _write_fixture(fixture: Dictionary) -> bool:
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write external catalog")
		return false
	file.store_string(JSON.stringify(fixture))
	file.close()
	return true


func _launch_external(mission: String) -> void:
	await _launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(fixture_path),
		"--mission=" + mission]))


func _launch(args: PackedStringArray) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(args)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame


func _check_storybook(label: String) -> bool:
	var ink := scene.find_child("StorybookInk", true, false) as Control
	var board := scene.find_child("BridgeBoard", true, false) as Control
	var desk := scene.find_child("CommandedHero", true, false) as Control
	var valid: bool = scene.current_screen() == "battle" and ink != null and ink.is_visible_in_tree() \
		and board != null and board.is_visible_in_tree()
	_check(valid, label + ": live storybook board and ink are visible")
	_check(desk == null or not desk.is_visible_in_tree(), label + ": no legacy command desk")
	return valid


func _exercise_battle(label: String, external: bool) -> void:
	if not _check_storybook(label):
		return
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if external:
		var page: Control = scene.get("_storybook_page")
		var scenery: TextureRect = page.get("_scenery")
		_check(scenery == null or scenery.texture == null,
			"External colliding board ID does not load stock scenery")
		_check(board.get("_painting") == null, "External colliding board ID uses procedural board")
		_check((board.get("_bounds") as Rect2i).size == Vector2i(8, 5),
			"External board renders its authored 8 by 5 geometry")
	var before: Dictionary = scene.battle_snapshot()
	_check(before.get("mission_id") == (FIXTURE_MISSION if external else "shield_wall"),
		label + ": requested mission is active")
	var knight := {}
	for unit in before.get("units", []):
		if unit.get("id") == "knight":
			knight = unit
	if knight.is_empty():
		_check(false, label + ": Knight is present")
		return
	var targets: Array = Rules.new().targets(before, "knight", "move")
	if targets.is_empty():
		_check(false, label + ": Knight has an opening move")
		return
	await _click(board.get_global_transform_with_canvas() * board.cell_center(knight.position))
	_check(scene.get("_actor_id") == "knight", label + ": board selects Knight")
	await _click(board.get_global_transform_with_canvas() * board.cell_center(targets[0].position))
	var planned: Dictionary = scene.get("_planned_state")
	var command: Dictionary = planned.get("overrides", {}).get("knight", {})
	_check(command.get("ability_id") == "move" and command.get("target_id") == targets[0].id,
		label + ": board destination stages a move")
	_check(scene.battle_snapshot() == before, label + ": staging leaves battle uncommitted")
	await _commit_forecast(before, label)


func _exercise_external_gate(dimensions: Vector2i, hero_label: String, test_targets := false) -> void:
	var plate := dimensions - Vector2i.ONE
	var fixture := RulesCatalog.definitions()
	fixture.characters.knight.label = hero_label
	fixture.boards = {GATE_BOARD: {"width": dimensions.x, "height": dimensions.y,
		"default_tile": "stone", "tiles": [], "locations": {
			"plate": [plate.x, plate.y], "gate": [4, 2], "exit": [0, 0]}}}
	fixture.encounters.fixture = {"board": GATE_BOARD, "placements": [
		{"id": "knight", "character": "knight", "at": [plate.x - 1, plate.y]}]}
	fixture.missions.fixture = {"title": "External Gate", "encounter": "fixture", "failures": [],
		"objective": {"handler": "pressure_gate", "plate": "plate", "gate": "gate", "exit": "exit",
			"text": "Reach the exit", "victory_text": "Victory", "defeat_text": "Defeat", "victory_event": "Victory"}}
	if not _write_fixture(fixture):
		return
	await _launch_external("fixture")
	if not _check_storybook("external pressure gate"):
		return
	var board := scene.find_child("BridgeBoard", true, false) as Control
	var page: Control = scene.get("_storybook_page")
	var scenery: TextureRect = page.get("_scenery")
	_check(board.get("_painting") == null and scenery.texture == null,
		"External Gate ID does not load the built-in painting or surround")
	_check((page.get("_props") as Dictionary).is_empty() and not board.get("_pressure_gate_prop_installed"),
		"External Gate ID keeps the primitive gate instead of the built-in props")
	var markers := board.find_child("ObjectiveMarkers", false, false) as Control
	_check(markers != null and markers.is_visible_in_tree()
		and markers.get_meta("markers", {}).get(plate, {}).get("kind") == "plate",
		"Procedural marker layer exposes the authored pressure plate")

	# The plate lies outside both dimensions of the stock board.
	_check((board.get("_bounds") as Rect2i).size == dimensions and board.cell_at(board.cell_center(plate)) == plate,
		"External pressure gate maps the full authored board")
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	await _check_long_action_rail(hero_label, plate, test_targets)
	board.grab_focus()
	await process_frame
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	var gate: Vector2i = before.objective.gate
	var rules := Rules.new()
	var plan: Dictionary = scene.get("_plan")
	_check(scene.battle_snapshot() == before and not rules.tile_definition(before, gate).passable,
		"Keyboard preview leaves the actual gate closed")
	_check(plan.get("valid", false) and rules.tile_definition(plan.result, gate).passable,
		"Keyboard Move to the external plate forecasts an open gate")
	await _key(KEY_ESCAPE)
	_check(scene.get("_planned_state").get("overrides", {}).is_empty(),
		"Clearing the keyboard preview leaves the external plate unstaged")
	var forecast := scene.find_child("ForecastDetails", true, false) as BaseButton
	var leaf := scene.find_child("ExtraDetails", true, false) as Control
	if forecast == null or leaf == null:
		_check(false, "The external Gate has the ordinary forecast controls")
		return
	await _click(forecast.get_global_rect().get_center())
	_check(leaf.is_visible_in_tree() and not leaf.get_global_rect().intersects(board.get_global_rect()),
		"Forecast leaves the entire external %s board unobscured" % dimensions)
	await _click(board.get_global_transform_with_canvas() * board.cell_center(plate))
	plan = scene.get("_plan")
	_check(leaf.is_visible_in_tree() and scene.battle_snapshot() == before
		and plan.get("valid", false) and rules.tile_definition(plan.result, gate).passable,
		"Real click reaches the external %s edge plate while Forecast is open" % dimensions)
	await _commit_forecast(before, "external pressure gate %s" % dimensions)


func _check_long_action_rail(hero_label: String, plate: Vector2i, test_targets: bool) -> void:
	var actions := scene.find_child("Actions", true, false) as MenuButton
	var targets := scene.find_child("Targets", true, false) as MenuButton
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if actions == null or targets == null or commit == null:
		_check(false, "Custom Gate exposes the ordinary command rail")
		return
	var full_label := hero_label + "’s actions"
	var commit_bounds := commit.get_global_rect()
	_check(not targets.is_visible_in_tree() and root.get_visible_rect().encloses(commit_bounds),
		"An authored long name leaves the entire Commit control on screen without Targets: %s" % commit_bounds)
	_check(actions.text == full_label and actions.accessibility_name == full_label and actions.tooltip_text == full_label,
		"Ellipsizing preserves the full authored Actions caption for hover and accessibility")
	var font_size := actions.get_theme_font_size("font_size")
	var caption_width := actions.get_theme_font("font").get_string_size(full_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_check(actions.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and actions.size.x < caption_width,
		"The overlong Actions caption is constrained and ellipsized")
	if not test_targets:
		return
	var menu := actions.get_popup()
	var move_index := -1
	for index in menu.item_count:
		if menu.get_item_text(index) == "move":
			move_index = index
			break
	if not await _choose_menu_item(actions, move_index):
		return
	var choices: Array = scene.get("_targets")
	var plate_index := choices.find_custom(func(choice: Dictionary) -> bool: return choice.position == plate)
	if choices.size() < 2 or plate_index < 0:
		_check(false, "Fixture has two real Move choices including the plate")
		return
	var plate_id: String = choices[plate_index].id
	# Exercise the chooser at the presentation boundary with real eligible targets.
	# Which overlapping entity produces the chooser is covered by the Necromancer scene test.
	scene.set("_storybook_ambiguous", choices)
	scene.call("_render_storybook")
	await process_frame
	await process_frame
	_check(targets.is_visible_in_tree() and root.get_visible_rect().encloses(targets.get_global_rect())
		and commit.get_global_rect().is_equal_approx(commit_bounds)
		and not targets.get_global_rect().intersects(actions.get_global_rect()),
		"Showing Targets fits the chooser without shifting Commit")
	if not await _choose_menu_item(targets, plate_index):
		return
	var staged: Dictionary = scene.get("_planned_state").get("overrides", {}).get("knight", {})
	_check(staged.get("target_id") == plate_id,
		"Selecting the plate in the visible Targets menu keeps the original action semantics")
	var clear := scene.find_child("ClearCommand", true, false) as BaseButton
	await _click(clear.get_global_rect().get_center())
	_check(not targets.is_visible_in_tree() and scene.get("_planned_state").get("overrides", {}).is_empty(),
		"Clear restores the no-target state for the real board click")


func _choose_menu_item(button: MenuButton, index: int) -> bool:
	await _click(button.get_global_rect().get_center())
	var popup := button.get_popup()
	if index >= 0 and popup.visible:
		for _step in popup.item_count:
			if popup.get_focused_item() == index:
				await _key(KEY_ENTER)
				if not popup.visible:
					return true
				break
			await _key(KEY_DOWN)
	if popup.visible:
		await _key(KEY_ESCAPE)
	_check(false, "The visible %s menu accepts its intended selection" % button.name)
	return false


func _commit_forecast(before: Dictionary, label: String) -> void:
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit == null or not commit.is_visible_in_tree() or commit.disabled:
		_check(false, label + ": commit is visible and enabled")
		return
	_check(root.get_visible_rect().encloses(commit.get_global_rect()),
		label + ": the entire Commit control and click center are on screen")
	await _click(commit.get_global_rect().get_center())
	_check(plan.get("valid", false) and scene.battle_snapshot() == plan.get("result")
		and scene.battle_snapshot() != before, label + ": commit resolves the forecast")


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
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: single battle UI")
	quit(0 if failures.is_empty() else 1)
