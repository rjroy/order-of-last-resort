extends "res://tests/journeys/commission_profile_recovery_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/cast_terminal_scene_test.gd
# The test-owned catalog makes the first real commission battle short, without
# manufacturing a terminal state or bypassing its settlement.
const RewardClick = preload("res://tests/support/reward_click.gd")


func _run() -> void:
	# The inherited helpers allocate a SubViewport; real pointer input needs the
	# window viewport instead, so release the unused one.
	viewport.free()
	if not _write_fixture():
		_cleanup()
		return
	root.size = VIEWPORT_SIZE
	await _terminal_round()
	await _rapid_terminal_pickup()
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) == OK,
		"Removed test-owned catalog")
	_cleanup()


func _terminal_round() -> void:
	var store = load("res://guild/guild_profile.gd")
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
	if not await RewardClick.click(self, reward, _click):
		return
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


func _rapid_terminal_pickup() -> void:
	if scene.current_screen() != "battle":
		_check(false, "Rapid pickup fixture needs the next real commission battle")
		return
	var rules = preload("res://rules/rules.gd").new()
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.objective = {"handler": "survive", "turns": state.round + 1, "reserves": []}
	var positions := {"knight": Vector2i(3, 3), "healer": Vector2i(1, 1),
		"wizard": Vector2i(1, 2), "grunt_1": Vector2i(4, 3)}
	for unit in state.units:
		if positions.has(unit.id):
			unit.position = positions[unit.id]
		if unit.id == "knight":
			unit["upgrades"] = {"knight_shield_throw": 1}
		if unit.id == "grunt_1":
			unit.hp = 20
			unit.max_hp = 20
	for id in ["healer", "wizard"]:
		state = rules.set_order(state, id, "order_hold")
	state = rules.set_order(state, "knight", "order_advance")
	scene.call("_show_battle", state)
	var staged: Dictionary = rules.choose_manual(state, "knight", "knight_shield_throw", "grunt_1")
	scene.set("_planned_state", staged)
	scene.call("_refresh")
	var first: Dictionary = scene.get("_plan")
	if not first.get("valid", false) or first.get("result", {}).get("outcome") != "ongoing":
		_check(false, "Throw round forecasts a valid nonterminal result")
		return
	(_node("Commit") as BaseButton).pressed.emit()
	var board = scene.get("_board")
	board.set_process(false)
	var entries: Array = board.get("_playback").active()
	var throws := entries.filter(func(entry): return entry.cue.get("unit_id") == "knight" \
		and entry.cue.get("clip") == "shield_throw")
	if throws.size() != 1:
		_check(false, "Real throw commit queues one shield throw")
		return
	var throw = throws[0]
	_check(throw.gift != null and throw.elapsed_ms < throw.clip.release_ms,
		"Prior committed shield has not yet released")
	var terminal: Dictionary = scene.get("_plan")
	_check(terminal.get("valid", false) and terminal.get("result", {}).get("outcome") == "victory" \
		and terminal.events.any(func(event): return event.get("type") == "shield_retrieve"),
		"Next committed round retrieves the shield and ends the mission")
	if not terminal.get("valid", false) or terminal.get("result", {}).get("outcome") != "victory":
		return
	(_node("Commit") as BaseButton).pressed.emit()
	_check(scene.get("_state").get("outcome") == "victory" and scene.get("_run").get("phase") != "mission",
		"Rapid pickup settles synchronously")
	var replay = scene.get("_terminal_board")
	_check(replay == board, "Terminal replay retains the board with the earlier throw")
	if replay != board:
		return
	var retained: Array = replay.get("_playback").active()
	var retained_throws := retained.filter(func(entry): return entry.cue.get("unit_id") == "knight" \
		and entry.cue.get("clip") == "shield_throw")
	_check(retained_throws.size() == 1 and retained_throws[0] == throw \
		and throw.elapsed_ms < throw.clip.release_ms,
		"Terminal transfer keeps the original unreleased throw exactly once")
	replay.set_process(false)
	replay._process((throw.clip.release_ms - throw.elapsed_ms + 1.0) / 1000.0)
	_check(throw.gift_from is Vector2 and throw.gift_to is Vector2,
		"Retained throw reaches its shield release in terminal replay")
	scene.call("_clear_terminal_replay")
	_check(scene.get("_terminal_board") == null and scene.get("_terminal_replay") == null,
		"Skipping terminal replay tears down the retained board")


func _click(position: Vector2) -> void:
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
