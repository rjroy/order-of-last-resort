extends "res://tests/commission_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_storybook_scene_test.gd
# Exercise the ordinary guild flow with a disposable profile and no launch flags.
const Profile = preload("res://guild_profile.gd")


func _run() -> void:
	# The inherited scene fixture owns a SubViewport, but real Window input is
	# needed for GUI hover and button press/release handling in this test.
	viewport.free()
	root.size = VIEWPORT_SIZE
	await process_frame
	await _launch_commission_window()
	if not await _found_with_keyboard():
		_cleanup()
		return
	Profile.renew(profile_path, Profile.load_profile(profile_path), BOARD_SEED)
	await _launch_commission_window()
	await _press("Commission_0")
	_check(scene.current_screen() == "guild", "Commission opens recruitment")
	for id in FOUNDER_PARTY:
		await _press("Recruit_" + id)
	_check(scene.selected_recruits() == FOUNDER_PARTY, "Selected party order is retained")
	await _press("StartAdventure")
	if scene.current_screen() != "routes":
		_check(false, "Recruitment opens the route choice")
		_cleanup()
		return
	var run: Dictionary = scene.get("_run")
	var reports: Array = run.get("reports", [])
	if reports.is_empty():
		_check(false, "Route choice offers a report")
		_cleanup()
		return
	var mission := str(reports[0].get("mission_id", ""))
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "Selecting a route opens battle")
		_cleanup()
		return
	var opening: Dictionary = scene.battle_snapshot().duplicate(true)
	_check(opening.get("mission_id") == mission and opening.get("party") == FOUNDER_PARTY,
		"Battle uses the chosen route and recruited party")
	var ink := _node("StorybookInk") as Control
	_check(ink != null and ink.is_visible_in_tree(), "Normal launch displays the storybook battle page")
	var desk := _node("CommandedHero") as Control
	_check(desk == null or not desk.is_visible_in_tree(), "Legacy command desk is not visible")
	var board := _node("BridgeBoard") as Control
	if ink == null or not ink.is_visible_in_tree() or board == null or not board.has_method("cell_center"):
		_check(false, "Normal commission battle exposes the interactive storybook board")
		_cleanup()
		return
	var rules = load("res://rules.gd").new()
	var knight: Dictionary = {}
	var healer: Dictionary = {}
	for unit in opening.get("units", []):
		if unit.get("id") == "knight":
			knight = unit
		elif unit.get("id") == "healer":
			healer = unit
	if knight.is_empty() or healer.is_empty():
		_check(false, "Recruited heroes appear on the board")
		_cleanup()
		return
	await _commission_cell(board, healer.position)
	_check(scene.get("_actor_id") == "healer", "Clicking the board selects Healer")
	await _commission_cell(board, knight.position)
	_check(scene.get("_actor_id") == "knight", "Clicking the board selects Knight")
	var targets: Array = rules.targets(opening, "knight", "move")
	if targets.is_empty():
		_check(false, "Knight has a legal opening move")
		_cleanup()
		return
	var target: Dictionary = targets[0]
	await _commission_cell(board, target.position)
	var planned: Dictionary = scene.get("_planned_state")
	var command: Dictionary = planned.get("overrides", {}).get("knight", {})
	_check(command.get("ability_id") == "move" and command.get("target_id") == target.id,
		"Clicking a legal destination stages the board-first move")
	_check(scene.battle_snapshot() == opening, "Staging does not commit the battle")
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	_check(plan.get("valid", false), "The staged move produces a valid forecast")
	var commit := _node("Commit") as BaseButton
	if commit == null or not commit.is_visible_in_tree() or commit.disabled:
		_check(false, "Storybook commit is visible and enabled")
		_cleanup()
		return
	await _commission_click(commit.get_global_rect().get_center())
	_check(scene.battle_snapshot() == rules.commit_round(planned, plan),
		"Clicking commit resolves the displayed forecast")
	_check(scene.battle_snapshot() != opening, "Commit advances the battle")
	_cleanup()


func _found_with_keyboard() -> bool:
	var input := _node("GuildName") as LineEdit
	var create := _node("CreateGuild") as Button
	var notice := _node("GuildNameFeedback") as Label
	if scene.current_screen() != "guild_creation" or input == null or create == null or notice == null:
		_check(false, "Fresh normal launch opens the guild creation form")
		return false
	var hint := "1 to %d characters." % Profile.MAX_NAME_LENGTH
	_check(notice.text == hint and input.has_focus() and create.disabled,
		"Fresh form shows the name length hint and focuses the field, not the disabled action")
	await _key_in_window(KEY_ENTER)
	_check(scene.current_screen() == "guild_creation" and notice.text == "Enter a guild name."
		and input.has_focus() and not FileAccess.file_exists(profile_path),
		"Empty submission explains what to enter, without saving or losing focus")
	await _key_in_window(KEY_SPACE, 32)
	_check(create.disabled, "Whitespace does not enable the action")
	await _key_in_window(KEY_BACKSPACE)

	var long_name := "The Lantern Company ".repeat(5).left(Profile.MAX_NAME_LENGTH - 1) + "!"
	for character in long_name:
		await _key_in_window(character.to_upper().unicode_at(0), character.unicode_at(0))
	await _key_in_window(KEY_X, 120)
	_check(input.text == long_name and not create.disabled and notice.text == hint,
		"Typing the longest valid name clears the error and enables Create; extra input is capped")

	var concurrent := Profile.create(profile_path, "Already Founded", BOARD_SEED)
	if concurrent.has("error"):
		_check(false, "Test can create a concurrent profile")
		return false
	await _key_in_window(KEY_ENTER)
	_check(scene.current_screen() == "guild_creation" and "already exists" in notice.text
		and input.text == long_name and Profile.load_profile(profile_path) == concurrent,
		"Save failure is visible, retains the typed name and does not overwrite the profile")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path)) == OK,
		"Test can remove its concurrent profile")
	await _key_in_window(KEY_BACKSPACE)
	await _key_in_window(KEY_1, 33)
	_check(notice.text == hint and input.text == long_name, "Editing clears the stale save error")

	await _key_in_window(KEY_TAB)
	_check(create.has_focus(), "Tab moves from the name field to Create guild")
	await _key_in_window(KEY_TAB, 0, true)
	_check(input.has_focus(), "Shift+Tab returns to the name field")
	await _key_in_window(KEY_TAB)
	await _key_in_window(KEY_ENTER)
	_check(scene.current_screen() == "commissions" and Profile.load_profile(profile_path).get("name") == long_name,
		"Keyboard activation opens commissions and saves the complete long name")
	return scene.current_screen() == "commissions"


func _key_in_window(code: int, unicode := 0, shift := false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.unicode = unicode
		event.shift_pressed = shift
		event.pressed = down
		root.push_input(event, true)
		await process_frame


func _commission_cell(board: Control, cell: Vector2i) -> void:
	await _commission_click(board.get_global_transform_with_canvas() * board.cell_center(cell))


func _launch_commission_window() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(profile_path)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame


func _commission_click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
