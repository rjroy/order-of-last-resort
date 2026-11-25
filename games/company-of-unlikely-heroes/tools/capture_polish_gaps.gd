extends "res://tools/capture_guild_book.gd"
## Supplement capture_guild_book with exceptional and intermediate states.

const Controls = preload("res://tests/support/forfeit_controls.gd")
const GapRules = preload("res://rules/rules.gd")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("--output="):
		_finish_capture("Supply exactly one --output=<absolute directory>.")
		return
	output = args[0].trim_prefix("--output=").simplify_path()
	var local := ProjectSettings.globalize_path("res://../../.lore/local").simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/") or DisplayServer.get_name() == "headless":
		_finish_capture("Use a graphical renderer and an output directory under .lore/local/.")
		return
	var path := ProjectSettings.globalize_path("res://../../").simplify_path()
	for component in output.trim_prefix(path + "/").split("/"):
		path = path.path_join(component)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_finish_capture("Output path contains a symbolic link: " + path)
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_finish_capture("Cannot create output directory.")
		return
	var directory := DirAccess.open(output)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_finish_capture("Output directory must be empty.")
		return
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var profile := output.path_join("profile.json")
	var file := FileAccess.open(profile, FileAccess.WRITE)
	if file == null:
		_finish_capture("Cannot create disposable corrupt profile.")
		return
	file.store_string("{ invalid json")
	file.close()
	await _launch_gap(PackedStringArray(), profile)
	if not _screen_is("profile_error") or not await _save_capture("01-profile-recovery"):
		_finish_capture(failure)
		return
	await _launch_gap(PackedStringArray(["--mission=missing_polish_mission"]), profile)
	if not _screen_is("error") or scene.find_child("LaunchErrorText", true, false) == null \
			or not await _save_capture("02-invalid-launch"):
		_finish_capture(failure if not failure.is_empty() else "Missing launch error detail.")
		return
	if DirAccess.remove_absolute(profile) != OK:
		_finish_capture("Cannot remove disposable corrupt profile.")
		return
	await _launch_gap(PackedStringArray(), profile)
	var name_edit := scene.find_child("GuildName", true, false) as LineEdit
	var create := scene.find_child("CreateGuild", true, false) as BaseButton
	if not _screen_is("guild_creation") or name_edit == null or create == null or not create.disabled \
			or not await _save_capture("03-empty-name"):
		_finish_capture(failure if not failure.is_empty() else "Empty guild name was not disabled.")
		return
	name_edit.text = "The Extraordinarily Long Company of Unlikely Heroes"
	name_edit.text_changed.emit(name_edit.text)
	if create.disabled or not await _save_capture("04-long-name") or not await _press_button("CreateGuild") \
			or not _screen_is("battle") or not await _press_button("SkipPractice") \
			or not _screen_is("commissions") or not await _save_capture("05-long-name-commissions"):
		_finish_capture(failure if not failure.is_empty() else "Long guild name failed.")
		return
	var store = load("res://guild/guild_profile.gd")
	var seeded: Dictionary = store.renew(profile, scene.get("_guild_profile"), BOARD_SEED)
	if seeded.has("error"):
		_finish_capture("Cannot seed disposable commission board: " + str(seeded.error))
		return
	await _launch_gap(PackedStringArray(), profile)
	if not _screen_is("commissions") or not await _press_button("Commission_0") or not _screen_is("guild") \
			or not await _save_capture("06-empty-recruitment"):
		_finish_capture(failure if not failure.is_empty() else "Cannot open recruitment.")
		return
	for id in FOUNDERS:
		if not await _press_button("Recruit_" + id):
			_finish_capture(failure)
			return
	if scene.selected_recruits().size() != 3 or not await _save_capture("07-full-recruitment") \
			or not await _press_button("StartAdventure") or not _screen_is("routes") \
			or not await _press_button("Route_0") or not _screen_is("battle"):
		_finish_capture(failure if not failure.is_empty() else "Could not deploy full party.")
		return
	var before: Dictionary = scene.battle_snapshot()
	var board := scene.find_child("BridgeBoard", true, false) as Control
	var knight := {}
	for unit: Dictionary in before.get("units", []):
		if unit.get("id") == "knight":
			knight = unit
	var targets: Array = GapRules.new().targets(before, "knight", "move")
	if board == null or knight.is_empty() or targets.is_empty():
		_finish_capture("No board, knight, or legal move.")
		return
	if not await _capture_leaf("StandingOrders", "13-standing-orders-open"):
		_finish_capture(failure)
		return
	await _click(board.get_global_transform_with_canvas() * board.cell_center(knight.position))
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if scene.get("_actor_id") != "knight" or not await driver.action("move") \
			or (scene.get("_targets") as Array).is_empty() or not await _save_capture("08-targeting"):
		_finish_capture(failure if not failure.is_empty() else "Knight move targeting was not offered.")
		return
	await _click(board.get_global_transform_with_canvas() * board.cell_center(targets[0].position))
	var command: Dictionary = scene.get("_planned_state").get("overrides", {}).get("knight", {})
	var plan: Dictionary = scene.get("_plan")
	if command.get("ability_id") != "move" or command.get("target_id") != targets[0].id \
			or not plan.get("valid", false) or scene.battle_snapshot() != before \
			or not await _save_capture("09-forecast"):
		_finish_capture(failure if not failure.is_empty() else "Move forecast was not staged.")
		return
	if not await _capture_leaf("ForecastDetails", "14-round-forecast-open"):
		_finish_capture(failure)
		return
	var expected: Dictionary = plan.result.duplicate(true)
	if not await _press_button("Commit") or scene.battle_snapshot() != expected \
			or not await _save_capture("10-resolution"):
		_finish_capture(failure if not failure.is_empty() else "Resolution differed from forecast.")
		return
	var forfeit := Controls.button(viewport, ["forfeit"])
	if forfeit == null:
		_finish_capture("Forfeit control missing.")
		return
	await Controls.click(self, forfeit)
	var confirm := Controls.button(viewport, ["forfeit mission"], forfeit)
	if confirm == null or Controls.button(viewport, ["cancel"]) == null \
			or not await _save_capture("11-forfeit-confirmation"):
		_finish_capture(failure if not failure.is_empty() else "Forfeit confirmation missing.")
		return
	await Controls.click(self, confirm)
	var settled: Dictionary = scene.get("_run")
	if not _screen_is("result") or settled.get("outcome") != "defeat" \
			or not settled.get("mission", {}).get("_voluntary_defeat", false) \
			or not await _save_capture("12-forfeit-result"):
		_finish_capture(failure if not failure.is_empty() else "Forfeit did not settle as a voluntary defeat.")
		return
	await _launch_gap(PackedStringArray(["--mission=wrong_side_of_the_door"]), profile)
	if not _screen_is("battle"):
		_finish_capture(failure)
		return
	board = scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		_finish_capture("No Gate board to capture.")
		return
	var transform := board.get_global_transform_with_canvas()
	await _click(transform * board.cell_center(Vector2i(0, 3)))
	await _click(transform * board.cell_center(Vector2i(1, 3)))
	var gate_move: Dictionary = scene.get("_planned_state").get("overrides", {}).get("wizard", {})
	if gate_move.get("target_id") != "1,3" or not await _capture_leaf("ForecastDetails", "15-gate-forecast-open"):
		_finish_capture(failure if not failure.is_empty() else "Could not capture the Gate with a staged B4 move.")
		return
	print("Completed supplemental captures in " + output)
	_finish_capture("")


func _capture_leaf(button_name: String, filename: String) -> bool:
	var leaf := scene.find_child("ExtraDetails", true, false) as Control
	if leaf == null or not await _press_button(button_name) or not leaf.is_visible_in_tree():
		failure = "Could not open the battle leaf for " + filename
		return false
	if not await _save_capture(filename) or not await _press_button(button_name) or leaf.is_visible_in_tree():
		if failure.is_empty():
			failure = "Could not close the battle leaf after " + filename
		return false
	return true


func _launch_gap(args: PackedStringArray, profile: String) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(args)
	scene.configure_profile_path(profile)
	viewport.add_child(scene)
	await process_frame
	await process_frame
