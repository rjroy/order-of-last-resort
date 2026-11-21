extends "res://tests/commission_profile_recovery_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/cast_terminal_scene_test.gd
# The test-owned catalog makes the first real commission battle short, without
# manufacturing a terminal state or bypassing its settlement.

func _run() -> void:
	# The inherited helpers allocate a SubViewport; real pointer input needs the
	# window viewport instead, so release the unused one.
	viewport.free()
	if not _write_fixture():
		_cleanup()
		return
	root.size = VIEWPORT_SIZE
	await _terminal_round()
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) == OK,
		"Removed test-owned catalog")
	_cleanup()


func _terminal_round() -> void:
	var store = load("res://guild_profile.gd")
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Test-owned guild can be created: " + str(created))
		return
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(fixture_path)]))
	scene.configure_profile_path(profile_path)
	root.add_child(scene)
	await process_frame
	await process_frame
	await _press("Commission_0")
	for id in PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "First commission route opens battle")
		return
	var terminal_plan := {}
	for round_number in 10:
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		if not plan.get("valid", false):
			_check(false, "Round forecast is valid")
			return
		if plan.get("result", {}).get("outcome") != "ongoing":
			terminal_plan = plan
			break
		await _press("Commit")
		if scene.current_screen() != "battle":
			_check(false, "Nonterminal forecast remains in battle")
			return
	if terminal_plan.is_empty():
		_check(false, "Controlled battle forecasts a terminal round within ten commits")
		return
	_check(terminal_plan.get("result", {}).get("outcome") == "victory",
		"Controlled first mission forecasts victory")
	var commit := _node("Commit") as BaseButton
	if commit == null or commit.disabled:
		_check(false, "Terminal forecast can be committed")
		return
	commit.pressed.emit()
	_check(scene.current_screen() == "debrief" and scene.get("_run").get("phase") == "reward",
		"Terminal commit synchronously settles the mission and opens reward debrief")
	_check(scene.get("_state").get("outcome") == "victory",
		"Terminal battle outcome is committed synchronously")
	await process_frame
	var overlay := _node("TerminalCastReplay") as Control
	_check(overlay != null and overlay.is_visible_in_tree(), "Terminal cast overlay remains visible on the debrief")
	if overlay != null:
		_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Cosmetic overlay does not intercept clicks")
		var board: Node
		for child in overlay.find_children("*", "", true, false):
			if child.has_method("action_playback_snapshot"):
				board = child
				break
		_check(board != null,
			"Terminal overlay retains a board with committed action playback")
		if board != null:
			_check(not board.call("action_playback_snapshot").is_empty(), "Terminal action playback is active")
	var reward: BaseButton
	var offers: Array = scene.get("_run").get("reward_offers", [])
	for offer in offers:
		var id: String = offer.get("hero_id", "")
		var candidate := _node("Reward_" + id) as BaseButton
		if candidate != null and candidate.is_visible_in_tree() and not candidate.disabled:
			reward = candidate
			break
	if reward == null:
		_check(false, "Debrief offers an enabled reward")
		return
	await _click(reward)
	_check(not scene.get("_run").get("upgrades_by_id", {}).is_empty(),
		"First click selects the reward rather than being stolen by the overlay")
	_check(not is_instance_valid(overlay) or not overlay.is_visible_in_tree(),
		"Normal reward click dismisses the terminal overlay")
	await _press("ContinueAdventure")
	if scene.current_screen() != "routes":
		_check(false, "Reward continues to next routes")
		return
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "Next route opens a new battle")
		return
	_check(_node("TerminalCastReplay") == null or not (_node("TerminalCastReplay") as Control).is_visible_in_tree(),
		"Old terminal overlay does not leak into the next battle")
	var next_board := _node("BridgeBoard")
	_check(next_board != null and next_board.has_method("action_playback_snapshot")
		and next_board.call("action_playback_snapshot").is_empty(),
		"New battle board has no previous action playback")
	_check(scene.get("_plan").get("valid", false), "New battle has a valid forecast")
	var next_commit := _node("Commit") as BaseButton
	_check(next_commit != null and next_commit.is_visible_in_tree() and not next_commit.disabled,
		"New battle controls are ready")


func _click(control: Control) -> void:
	var position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
