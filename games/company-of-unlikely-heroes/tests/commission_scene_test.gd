extends "res://tests/village_outing_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_scene_test.gd
# Use the existing bounded, forecast-driven battle player, but enter through the
# normal commission flow and never use a player's profile.
const GUILD_NAME := "The Test Company"
const BOARD_SEED := 147258
var profile_path := "user://commission_scene_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]


func _run() -> void:
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	container.scale = Vector2(0.5, 0.5)
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	await _launch_normal()
	if scene.current_screen() != "guild_creation":
		_check(false, "Fresh normal launch opens guild creation")
		_cleanup()
		return
	var input := _node("GuildName") as LineEdit
	_check(input != null and input.is_visible_in_tree(), "Guild name is editable")
	if input == null:
		_cleanup()
		return
	input.text = GUILD_NAME
	input.text_changed.emit(input.text)
	await process_frame
	await _press("CreateGuild")
	_check(scene.current_screen() == "commissions", "Creating a guild opens commissions")
	var store = load("res://guild_profile.gd")
	var saved: Dictionary = store.load_profile(profile_path)
	_check(saved.get("name") == GUILD_NAME, "Creation persists the entered name")
	# Fix the test-owned board seed so this scene regression is reproducible.
	store.renew(profile_path, saved, BOARD_SEED)
	await _launch_normal()
	_check(scene.current_screen() == "commissions", "Reloading the saved guild opens its board")
	_check(store.load_profile(profile_path).get("name") == GUILD_NAME, "Reload retains the guild name")
	_check(store.load_profile(profile_path).get("board_seed") == BOARD_SEED, "Reload retains the controlled board seed")
	_check(_node("Route_0") == null and _node("Route_1") == null,
		"Commission board does not reveal route reports")
	var board_text: Array = []
	for i in 3:
		var commission := _node("Commission_%d" % i) as BaseButton
		_check(commission != null and commission.is_visible_in_tree() and not commission.disabled,
			"Commission %d is visible and selectable" % i)
		if commission != null:
			board_text.append(commission.text)
	_check(_node("Commission_3") == null, "Commission board offers exactly three commissions")
	var run: Dictionary = scene.get("_run")
	_check(run.get("reports", []).is_empty(), "No route reports appear before accepting a commission")
	await _launch_normal()
	for i in board_text.size():
		var commission := _node("Commission_%d" % i) as BaseButton
		_check(commission != null and commission.text == board_text[i], "Reload preserves commission %d" % i)
	await _press("Commission_0")
	_check(scene.current_screen() == "guild", "Accepting a commission opens recruitment")
	run = scene.get("_run")
	_check(run.get("reports", []).is_empty(), "Reports remain hidden until the company is recruited")
	_check(_node("Route_0") == null and _node("Route_1") == null,
		"Recruitment does not reveal route reports")
	for id in ["knight", "healer", "bard"]:
		await _press("Recruit_" + id)
	await _press("PartyEarlier_healer")
	_check(scene.selected_recruits() == PARTY, "Recruitment preserves the chosen order")
	await _press("StartAdventure")
	if scene.current_screen() != "routes":
		_check(false, "A recruited company receives route reports before battle")
		_cleanup()
		return
	run = scene.get("_run")
	var reports: Array = run.get("reports", [])
	_check(run.get("phase") == "route" and reports.size() == 2, "Exactly two route reports are offered")
	for report in reports:
		for key in ["mission_id", "description", "hint_kind", "hint_text"]:
			_check(not str(report.get(key, "")).is_empty(), "Route report includes " + key)
		_check(str(report.get("description", "")) in _visible_text()
			and str(report.get("hint_text", "")) in _visible_text(), "Both report details are visible to the player")
	for i in 2:
		var route := _node("Route_%d" % i) as BaseButton
		_check(route != null and route.is_visible_in_tree() and not route.disabled,
			"Route %d is visible and selectable" % i)
	if reports.size() != 2:
		_cleanup()
		return
	var chosen_mission := str(reports[0].get("mission_id", ""))
	var chosen_hint := str(reports[0].get("hint_text", ""))
	var initial_count: int = run.get("mission_count", -1)
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "Selecting a report starts its battle")
		_cleanup()
		return
	_check(scene.battle_snapshot().get("mission_id") == chosen_mission, "Battle matches the selected report")
	_check(scene.battle_snapshot().get("party") == PARTY, "Battle carries the selected party order")
	await _play_battle(chosen_mission)
	if scene.current_screen() != "debrief":
		_check(false, "Winning the first battle opens a reward debrief, got " + scene.current_screen())
		_cleanup()
		return
	run = scene.get("_run")
	_check(run.get("scout_note", "") == chosen_hint and chosen_hint in _visible_text(),
		"Debrief shows the selected report's prior scout hint")
	_check(_node("Route_0") == null and _node("Route_1") == null,
		"Future route choices are absent from the debrief")
	var continuation := _node("ContinueAdventure") as BaseButton
	_check(continuation != null and continuation.disabled, "A reward is required before the next fork")
	var reward: BaseButton
	for id in PARTY:
		reward = _node("Reward_" + id) as BaseButton
		if reward != null and not reward.disabled and reward.is_visible_in_tree():
			break
		reward = null
	_check(reward != null, "Debrief offers an eligible reward")
	if reward == null:
		_cleanup()
		return
	await _press(str(reward.name))
	run = scene.get("_run")
	var carry: Dictionary = run.get("carry_by_id", {}).duplicate(true)
	var upgrades: Dictionary = run.get("upgrades_by_id", {}).duplicate(true)
	_check(not carry.is_empty() and not upgrades.is_empty(), "Reward and hero carry are recorded")
	await _press("ContinueAdventure")
	_check(scene.current_screen() == "routes", "Reward continuation opens the next fork, not a battle")
	run = scene.get("_run")
	_check(run.get("phase") == "route" and run.get("reports", []).size() == 2,
		"The next fork offers two reports")
	_check(run.get("mission_count", -1) == initial_count, "The accepted commission retains its mission count")
	_check(run.get("carry_by_id", {}) == carry and run.get("upgrades_by_id", {}) == upgrades,
		"Hero carry and chosen reward survive the fork")
	var adventure = load("res://adventure.gd")
	var expected_hp: Dictionary = {}
	for id in PARTY:
		expected_hp[id] = adventure.next_mission_hp(run, id)
	await _press("Route_1")
	_check(scene.current_screen() == "battle", "The next report starts the next battle")
	if scene.current_screen() == "battle":
		_check(scene.battle_snapshot().get("party") == PARTY, "The next battle retains party order")
		run = scene.get("_run")
		_check(run.get("carry_by_id", {}) == carry and run.get("upgrades_by_id", {}) == upgrades,
			"Next battle retains carried state and reward")
		var battle: Dictionary = scene.battle_snapshot()
		for unit in battle.get("units", []):
			var id := str(unit.get("id", ""))
			if id in PARTY:
				_check(unit.get("hp") == expected_hp[id], id + " deploys with carried HP")
				_check(unit.get("upgrades", {}) == upgrades.get(id, {}), id + " deploys with chosen upgrades")
				_check(battle.get("orders", {}).get(id) == carry.get(id, {}).get("order"),
					id + " deploys with the carried order")
		await _finish_outing()
	if scene.current_screen() == "result":
		var old_seed: int = store.load_profile(profile_path).get("board_seed", -1)
		await _press("ReturnToGuild")
		_check(scene.current_screen() == "commissions", "Returning after a terminal outing refreshes the board")
		var refreshed: Dictionary = store.load_profile(profile_path)
		_check(refreshed.get("name") == GUILD_NAME and refreshed.get("board_seed", -1) != old_seed,
			"Return persists the same guild name with a fresh board seed")
		await _launch_normal()
		_check(scene.current_screen() == "commissions"
			and store.load_profile(profile_path) == refreshed, "Relaunch preserves the refreshed board profile")
	else:
		_check(false, "Outing reaches an actual terminal result before returning")
	_cleanup()


func _visible_text() -> String:
	var text := ""
	for node in scene.find_children("*", "", true, false):
		if node is Label or node is RichTextLabel or node is BaseButton:
			if node.is_visible_in_tree():
				text += str(node.text) + "\n"
	return text


func _finish_outing() -> void:
	# Stand and commit through the remaining encounters. No manufactured result
	# or direct call to a transition handler can exercise the return path.
	for step in 400:
		match scene.current_screen():
			"battle":
				await _press("Commit")
			"debrief":
				var picked := false
				for id in PARTY:
					var reward := _node("Reward_" + id) as BaseButton
					if reward != null and reward.is_visible_in_tree() and not reward.disabled:
						await _press(str(reward.name))
						picked = true
						break
				var continuation := _node("ContinueAdventure") as BaseButton
				if continuation == null or continuation.disabled:
					_check(false, "Remaining debrief can select a reward" if not picked else "Reward enables continuation")
					return
				await _press("ContinueAdventure")
			"routes":
				await _press("Route_0")
			"result":
				return
			_:
				_check(false, "Unexpected outing screen " + scene.current_screen())
				return
	_check(false, "Outing did not terminate within 400 interactions")


func _launch_normal() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(profile_path)
	viewport.add_child(scene)
	await process_frame
	await process_frame


func _cleanup() -> void:
	if FileAccess.file_exists(profile_path):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path)) == OK,
			"Test-owned profile is removed")
	_finish()
