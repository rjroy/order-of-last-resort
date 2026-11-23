extends "res://tests/commission_storybook_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_storybook_settlement_test.gd
# Unlike cast_terminal_scene_test, this uses the stock catalog and no launch
# flags. The test-owned board seed makes the actual first route reproducible.
func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var store = load("res://guild_profile.gd")
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Disposable guild can be created: " + str(created))
		_cleanup()
		return
	await _launch_normal()
	await _press("Commission_0")
	for id in FOUNDER_PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "Stock commission enters its first battle")
		_cleanup()
		return
	var decisive := false
	for round_index in MAX_ROUNDS:
		await _stage_best_command()
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		if not plan.get("valid", false):
			_check(false, "Stock round %d has a legal forecast" % round_index)
			break
		var outcome: String = plan.get("result", {}).get("outcome", "")
		if outcome != "ongoing":
			_check(outcome == "victory", "Stock first battle forecasts victory")
			decisive = outcome == "victory"
		var commit := _node("Commit") as BaseButton
		if commit == null or not commit.is_visible_in_tree() or commit.disabled:
			_check(false, "Stock battle has an enabled storybook Commit")
			break
		var desk := _node("CommandedHero") as Control
		_check(desk == null or not desk.is_visible_in_tree(), "Old command desk stays hidden")
		if outcome == "ongoing":
			var before_round: int = scene.battle_snapshot().get("round", 0)
			await _press("Commit")
			_check(scene.battle_snapshot().get("round", 0) > before_round,
				"Nonterminal commit advances the round")
		else:
			await _settlement_click(commit.get_global_rect().get_center())
		if outcome != "ongoing":
			break
		if scene.current_screen() != "battle":
			_check(false, "Nonterminal commit stays in battle")
			break
	_check(decisive, "Stock first battle reaches a decisive legal victory within the round limit")
	if not decisive or scene.current_screen() != "debrief":
		_check(false, "Decisive Commit opens the reward debrief")
		_cleanup()
		return
	_check(scene.get("_run").get("phase") == "reward", "Victory settles to reward phase")
	var reward: BaseButton
	for id in FOUNDER_PARTY:
		var candidate := _node("Reward_" + id) as BaseButton
		if candidate != null and candidate.is_visible_in_tree() and not candidate.disabled:
			reward = candidate
			break
	if reward == null:
		_check(false, "Reward debrief offers an enabled claim")
		_cleanup()
		return
	if not await RewardClick.click(self, reward, _settlement_click):
		_cleanup()
		return
	var upgrades: Dictionary = scene.get("_run").get("upgrades_by_id", {}).duplicate(true)
	_check(upgrades.values().any(func(owned: Dictionary) -> bool: return not owned.is_empty()),
		"Actual GUI click claims an upgrade")
	var continuation := _node("ContinueAdventure") as BaseButton
	if continuation == null or continuation.disabled:
		_check(false, "Claim enables continuation")
		_cleanup()
		return
	await _settlement_click(continuation.get_global_rect().get_center())
	_check(scene.current_screen() == "routes", "Claim continues to the next field reports")
	if scene.current_screen() == "routes":
		await _press("Route_0")
	_check(scene.current_screen() == "battle", "Next field report deploys a new battle")
	if scene.current_screen() == "battle":
		var opening: Dictionary = scene.battle_snapshot().duplicate(true)
		_check(scene.get("_run").get("upgrades_by_id", {}) == upgrades, "Claim survives deployment")
		var overlay := _node("TerminalCastReplay") as Control
		_check(overlay == null or not overlay.is_visible_in_tree(), "Previous replay does not cover the next battle")
		var restart := _node("Restart") as Control
		_check(restart == null or not restart.is_visible_in_tree(), "Commission battle offers no restart")
		var desk := _node("CommandedHero") as Control
		_check(desk == null or not desk.is_visible_in_tree(), "Next battle has no visible old desk")
		var loadout := _node("ShowLoadout") as BaseButton
		if loadout == null or not loadout.is_visible_in_tree() or loadout.disabled:
			_check(false, "Next battle exposes outing loadout")
		else:
			await _settlement_click(loadout.get_global_rect().get_center())
			var dialog := _node("OutingLoadout") as Window
			_check(dialog != null and dialog.visible, "GUI opens the claimed loadout")
			_check(scene.battle_snapshot() == opening, "Opening loadout does not restart the battle")
			if dialog != null:
				dialog.hide()
		# Outlast the terminal replay's 3.2 second maximum.
		await create_timer(4.0).timeout
		_check(scene.current_screen() == "battle" and scene.battle_snapshot() == opening,
			"Old replay callbacks do not alter the next battle")
	_cleanup()


const RewardClick = preload("res://tests/support/reward_click.gd")


func _stage_best_command() -> void:
	var rules = load("res://rules.gd").new()
	var state: Dictionary = scene.battle_snapshot()
	var best_score := _score(scene.get("_plan").get("result", {}), FOUNDER_PARTY)
	var best := {}
	for actor in FOUNDER_PARTY:
		var context: Dictionary = rules.state_before_action(state, actor)
		if not rules.can_act(context, actor):
			continue
		for option in rules.options(state, actor):
			if option.kind != "action":
				continue
			var targets: Array = rules.targets(context, actor, option.id)
			if targets.is_empty():
				if option.target_kind in ["enemy", "ally", "cell", "unit"]:
					continue
				targets = [{"id": ""}]
			for target in targets:
				var draft: Dictionary = rules.choose_manual(state, actor, option.id, target.id)
				var forecast: Dictionary = rules.preview_round(draft)
				var score := _score(forecast.get("result", {}), FOUNDER_PARTY)
				if score > best_score:
					best_score = score
					best = {"actor": actor, "ability": option.id, "target": target.id}
	if best.is_empty():
		return
	var board := _node("BridgeBoard") as Control
	var actor_position := Vector2i(-1, -1)
	for unit in state.get("units", []):
		if unit.id == best.actor:
			actor_position = unit.position
	if board == null or actor_position == Vector2i(-1, -1):
		_check(false, "Chosen actor is visible on the storybook board")
		return
	await _settlement_click(board.get_global_transform_with_canvas() * board.cell_center(actor_position))
	var page: Node = scene.get("_storybook_page")
	page.emit_signal("action_selected", best.ability)
	if not best.target.is_empty():
		page.emit_signal("target_selected", best.target)
	await process_frame
	var staged: Dictionary = scene.get("_planned_state")
	_check(staged.get("overrides", {}).get(best.actor, {}).get("ability_id") == best.ability,
		"Storybook command editor stages the chosen legal action")


func _settlement_click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		viewport.push_input(event, true)
		await process_frame
