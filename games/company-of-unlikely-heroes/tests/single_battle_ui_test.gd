extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/single_battle_ui_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
const FIXTURE_MISSION := "single_ui_fixture"
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
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write external catalog")
		_finish()
		return
	file.store_string(JSON.stringify(fixture))
	file.close()

	await _launch(PackedStringArray(["--mission=shield_wall"]))
	await _exercise_battle("built-in", false)
	await _launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(fixture_path),
		"--mission=" + FIXTURE_MISSION]))
	await _exercise_battle("external", true)

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
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit == null or not commit.is_visible_in_tree() or commit.disabled:
		_check(false, label + ": commit is visible and enabled")
		return
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


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: single battle UI")
	quit(0 if failures.is_empty() else 1)
