extends "res://tests/journeys/guild_first_paths_scene_test.gd"

# Run headless with --script res://tests/journeys/guild_four_road_walkthrough_test.gd.
# For real GUI evidence use a graphical display and
# -- --capture-dir=/absolute/existing/directory.
# Unlike the controlled domain fixture, every victory here is played through
# the stock commission UI. Failure to win is reported, never replaced by data.

func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var store = load("res://guild/guild_profile.gd")
	var adv = load("res://expedition/adventure.gd")
	if not store.has_method("balance") or not adv.has_method("receipt"):
		_check(false, "Four-road walkthrough requires guild balance and receipt")
		_cleanup()
		return
	var profile: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if profile.has("error"):
		_check(false, "Create disposable guild: " + str(profile))
		_cleanup()
		return
	await _launch_normal()
	var reloaded: Dictionary = store.load_profile(profile_path)
	if reloaded.has("error") or reloaded.is_empty():
		_check(false, "Created guild could not be reloaded: " + str(reloaded))
		_cleanup()
		return
	if scene.current_screen() != "commissions":
		_check(false, "Loaded guild opens commissions, got " + scene.current_screen())
		_cleanup()
		return
	await _press("Commission_0")
	if scene.current_screen() != "guild":
		_check(false, "Accepting a commission opens recruitment, got " + scene.current_screen())
		_cleanup()
		return
	for id in FOUNDERS:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	for road_index in range(4):
		if scene.current_screen() != "routes":
			_check(false, "Road %d begins with a route choice" % (road_index + 1))
			_cleanup()
			return
		await _press("Route_0")
		if not await _play_winning_road(road_index):
			_cleanup()
			return
		var reward: BaseButton
		for id in FOUNDERS:
			var candidate := _node("Reward_" + id) as BaseButton
			if candidate != null and candidate.is_visible_in_tree() and not candidate.disabled:
				reward = candidate
				break
		if reward == null:
			_check(false, "Road %d offers a temporary reward" % (road_index + 1))
			_cleanup()
			return
		if not await RewardClick.click(self, reward, _settlement_click):
			_cleanup()
			return
		var continuation := _node("ContinueAdventure") as BaseButton
		if continuation == null or continuation.disabled:
			_check(false, "Road %d reward enables continuation" % (road_index + 1))
			_cleanup()
			return
		await _settlement_click(continuation.get_global_rect().get_center())
	if scene.current_screen() != "battle":
		_check(false, "Four road wins deploy the destination")
		_cleanup()
		return
	var escape := ForfeitControls.button(viewport, ["forfeit"])
	if escape == null:
		_check(false, "Destination offers Forfeit")
		_cleanup()
		return
	await ForfeitControls.click(self, escape)
	var confirm := ForfeitControls.button(viewport, ["forfeit mission"], escape)
	if confirm == null:
		_check(false, "Destination forfeit requires confirmation")
		_cleanup()
		return
	await ForfeitControls.click(self, confirm)
	if scene.current_screen() != "result":
		_check(false, "Destination forfeit reaches the return receipt")
		_cleanup()
		return
	var receipt: Dictionary = adv.call("receipt", scene.get("_run"))
	_check(receipt.get("road_wins") == 4 and receipt.get("road_points") == 4
		and receipt.get("destination_outcome") == "forfeit"
		and receipt.get("destination_points") == 0 and receipt.get("points") == 4,
		"Four real road wins and destination forfeit produce 4 + 0")
	var road := _node("ReceiptRoad")
	var destination := _node("ReceiptDestination")
	var total := _node("ReceiptTotal")
	for row_data in [[road, "Road (4 wins)", "4 points"], [destination, "Destination (forfeited)", "0 points"],
			[total, "Total", "4 points"]]:
		var entry: Node = row_data[0]
		var heading := entry.get_node("ReceiptLabel") as Label if entry != null else null
		var amount := entry.get_node("ReceiptValue") as Label if entry != null else null
		_check(_reachable(heading) and _reachable(amount) and heading.text == row_data[1] and amount.text == row_data[2],
			"Actual return receipt prints %s and %s" % [row_data[1], row_data[2]])
	await _capture("four_roads_actual_receipt")
	var return_button := _node("ReturnToGuild") as BaseButton
	if not _reachable(return_button) or return_button.disabled:
		_check(false, "Actual receipt permits return")
		_cleanup()
		return
	await ForfeitControls.click(self, return_button)
	var settled: Dictionary = store.load_profile(profile_path)
	_check(store.call("balance", settled) == 4 and settled.get("last_receipt", {}) == receipt,
		"Actual return banks exactly the four points printed on its receipt")
	await _capture("four_roads_actual_balance")
	await _launch_normal()
	_check(store.call("balance", store.load_profile(profile_path)) == 4,
		"Actual four-point balance survives reload")
	await _capture("four_roads_reloaded_balance")
	_cleanup()


func _play_winning_road(index: int) -> bool:
	if scene.current_screen() != "battle":
		_check(false, "Road %d deploys" % (index + 1))
		return false
	for round_index in MAX_ROUNDS:
		await _stage_founder_command()
		var plan: Dictionary = scene.get("_plan")
		if not plan.get("valid", false):
			_check(false, "Road %d round %d has a legal forecast" % [index + 1, round_index])
			return false
		var outcome: String = plan.get("result", {}).get("outcome", "")
		var commit := _node("Commit") as BaseButton
		if commit == null or not commit.is_visible_in_tree() or commit.disabled:
			_check(false, "Road %d has an enabled Commit" % (index + 1))
			return false
		await _settlement_click(commit.get_global_rect().get_center())
		if outcome != "ongoing":
			_check(outcome == "victory" and scene.current_screen() == "debrief",
				"Stock battle player wins road %d" % (index + 1))
			return outcome == "victory" and scene.current_screen() == "debrief"
	_check(false, "Road %d reaches no victory within the round limit" % (index + 1))
	return false
