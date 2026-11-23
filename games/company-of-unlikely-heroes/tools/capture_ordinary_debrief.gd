extends "res://tests/village_outing_scene_test.gd"
## See CAPTURE_ORDINARY_DEBRIEF.md. This plays an actual fixed-outing victory.

const Catalog = preload("res://content/catalog.gd")
const BattleRules = preload("res://rules.gd")
const IMAGE_NAME := "ordinary-mission-cleared.png"


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("--output="):
		_fail_capture("Supply exactly one --output=<absolute empty directory>.")
		return
	var output := args[0].trim_prefix("--output=").simplify_path()
	var root_path := ProjectSettings.globalize_path("res://../../").simplify_path()
	var local := root_path.path_join(".lore/local")
	if DisplayServer.get_name() == "headless" or not output.is_absolute_path() \
			or not output.begins_with(local + "/"):
		_fail_capture("A graphical display and output below .lore/local/ are required.")
		return
	var path := root_path
	for component in output.trim_prefix(root_path + "/").split("/"):
		path = path.path_join(component)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_fail_capture("Output path contains a symbolic link: " + path)
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail_capture("Cannot create output directory.")
		return
	var directory := DirAccess.open(output)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_fail_capture("Output directory must be empty.")
		return
	# Preserve the stock catalog and omit only the optional upgrade definitions.
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	defs.erase("upgrades")
	var errors: PackedStringArray = Catalog.validate(defs)
	if not errors.is_empty() or defs.has("upgrades"):
		_fail_capture("Upgrade-free catalog is invalid: " + str(errors))
		return
	var fixture := output.path_join("catalog-no-upgrades.json")
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	if file == null:
		_fail_capture("Cannot write disposable external catalog.")
		return
	file.store_string(JSON.stringify(defs))
	file.close()
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--fixed-outings", "--content=" + fixture]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	var selector := _node("AdventureSelect") as OptionButton
	if scene.current_screen() != "guild" or not await _select_id(selector, "village_troubles"):
		_fail_capture("External fixed outings did not open village_troubles: " + str(failures))
		return
	for id in PARTY:
		await _press("Recruit_" + id)
	if not failures.is_empty() or scene.selected_recruits() != PARTY:
		_fail_capture("Could not recruit the fixed party: " + str(failures))
		return
	seed(12345)
	await _press("StartAdventure")
	if scene.current_screen() != "battle" or scene.battle_snapshot().get("mission_id") != "goblin_mob":
		_fail_capture("Expected first village battle, got " + scene.current_screen())
		return
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	await _play_battle("goblin_mob")
	var run: Dictionary = scene.get("_run")
	# Settlement deliberately clears run.mission for an intermediate victory;
	# the scene's committed battle snapshot remains available as _state.
	var terminal: Dictionary = scene.get("_state")
	var carry := _node("CarryReport") as Control
	var continue_button := _node("ContinueAdventure") as BaseButton
	if not failures.is_empty() or played_rounds < 1 or scene.current_screen() != "debrief" \
			or run.get("phase") != "ready" or run.get("mission_index") != 1 \
			or not run.get("reward_offers", []).is_empty() \
			or not run.get("chosen_reward", {}).is_empty() \
			or run.get("last_result", {}).get("outcome") != "victory" \
			or terminal.get("outcome") != "victory" \
			or not BattleRules.new().is_committed_terminal(terminal) \
			or carry == null or not carry.is_visible_in_tree() \
			or continue_button == null or not continue_button.is_visible_in_tree() or continue_button.disabled:
		_fail_capture("A real no-reward victory debrief was not reached: " + str(failures) \
			+ "; screen=" + scene.current_screen() + "; phase=" + str(run.get("phase")) \
			+ "; last_result=" + str(run.get("last_result")))
		return
	# Clear the terminal replay overlay without altering the settled state.
	if scene.find_child("TerminalCastReplay", true, false) != null:
		var key := InputEventKey.new()
		key.keycode = KEY_SHIFT
		key.pressed = true
		viewport.push_input(key, true)
		await process_frame
		key = InputEventKey.new()
		key.keycode = KEY_SHIFT
		viewport.push_input(key, true)
		await process_frame
	if scene.find_child("TerminalCastReplay", true, false) != null:
		_fail_capture("Terminal replay obscures the debrief.")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != VIEWPORT_SIZE \
			or image.save_png(output.path_join(IMAGE_NAME)) != OK:
		_fail_capture("Could not save the 1280x820 debrief.")
		return
	print("Captured real no-reward victory after %d committed rounds: %s" % [played_rounds, output.path_join(IMAGE_NAME)])
	quit(0)


# Reuse the forecast-based player from village_outing_scene_test, but capture
# only the final debrief and press Commit through the test's normal UI helper.
func _capture(_name: String) -> void:
	pass


func _click_commit() -> void:
	await _press("Commit")


func _fail_capture(message: String) -> void:
	push_error(message)
	quit(1)
