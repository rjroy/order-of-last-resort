extends "res://tests/village_outing_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_scene_test.gd
# Use the existing bounded, forecast-driven battle player, but enter through the
# normal commission flow and never use a player's profile.
const GUILD_NAME := "The Test Company"
const GAME_TITLE := "Barnaby's Order of Last Resort"
const BOARD_SEED := 147258
const FOUNDER_PARTY := ["healer", "knight", "wizard"]
var profile_path := "user://commission_scene_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]


func _run() -> void:
	_check(root.title == GAME_TITLE, "Window displays the game title")
	if OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "Windows", "macOS"]:
		var godot_dir := "Godot" if OS.get_name() in ["Windows", "macOS"] else "godot"
		var title_suffix := "%s/app_userdata/%s" % [godot_dir, GAME_TITLE]
		_check(OS.get_user_data_dir().replace("\\", "/").ends_with(title_suffix),
			"User data uses the current game title")
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
	_check(GAME_TITLE in _visible_text(), "Guild creation displays the game title")
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
	if scene.current_screen() != "commissions":
		_cleanup()
		return
	if not await _test_practice_after_commission_back():
		_cleanup()
		return
	await _press("PracticeOutings")
	_check(GAME_TITLE in _visible_text(), "Practice outings displays the game title")
	await _press("BackToCommissions")
	var store = load("res://guild_profile.gd")
	var saved: Dictionary = store.load_profile(profile_path)
	_check(saved.get("name") == GUILD_NAME, "Creation persists the entered name")
	# Fix the test-owned board seed so this scene regression is reproducible.
	store.renew(profile_path, saved, BOARD_SEED)
	await _launch_normal()
	_check(scene.current_screen() == "commissions", "Reloading the saved guild opens its board")
	_check(store.load_profile(profile_path).get("name") == GUILD_NAME, "Reload retains the guild name")
	_check(store.load_profile(profile_path).get("board_seed") == BOARD_SEED, "Reload retains the controlled board seed")
	for board_size in [Vector2i(1280, 820), Vector2i(960, 615)]:
		viewport.size = board_size
		await _launch_normal()
		await _check_petitions_entry("zero points")
	viewport.size = VIEWPORT_SIZE
	await _launch_normal()
	_check(_node("Route_0") == null and _node("Route_1") == null,
		"Commission board does not reveal route reports")
	var board_offers: Array = []
	var board_titles: Array[String] = []
	for i in 3:
		var commission := _node("Commission_%d" % i) as BaseButton
		_check(commission != null and commission.is_visible_in_tree() and not commission.disabled,
			"Commission %d is visible and selectable" % i)
		if commission != null:
			var offer := _commission_snapshot(i)
			var title := commission.accessibility_name.trim_prefix("Choose commission: ")
			_check(not title.is_empty() and title != commission.accessibility_name
				and title in offer.get("labels", []), "Commission %d shows its destination title" % i)
			_check(title not in board_titles, "Commission %d has a distinct destination" % i)
			board_titles.append(title)
			board_offers.append(offer)
	_check(_node("Commission_3") == null, "Commission board offers exactly three commissions")
	var run: Dictionary = scene.get("_run")
	_check(run.get("reports", []).is_empty(), "No route reports appear before accepting a commission")
	await _launch_normal()
	for i in board_offers.size():
		_check(_commission_snapshot(i) == board_offers[i], "Reload preserves commission %d" % i)
	await _press("Commission_0")
	_check(scene.current_screen() == "guild", "Accepting a commission opens recruitment")
	run = scene.get("_run")
	_check(run.get("reports", []).is_empty(), "Reports remain hidden until the company is recruited")
	_check(_node("Route_0") == null and _node("Route_1") == null,
		"Recruitment does not reveal route reports")
	for id in ["knight", "healer", "wizard"]:
		var recruit := _node("Recruit_" + id) as BaseButton
		_check(recruit != null and recruit.is_visible_in_tree() and not recruit.disabled,
			"Fresh guild can recruit founder " + id)
	for id in ["bard", "rogue", "alchemist", "necromancer"]:
		_check(_node("Recruit_" + id) == null, "Locked recruit is absent from fresh guild: " + id)
	for id in ["knight", "healer", "wizard"]:
		await _press("Recruit_" + id)
	for id in ["knight", "healer", "wizard"]:
		var edit := _node("EditHero_" + id) as Button
		_check(edit != null and edit.is_visible_in_tree() and not edit.disabled
			and "edit loadout" in edit.text.to_lower(),
			id + " has a visible labeled loadout button")
		if edit == null or edit.disabled:
			continue
		edit.grab_focus()
		_check(viewport.gui_get_focus_owner() == edit, id + " loadout button accepts keyboard focus")
		for down in [true, false]:
			var action := InputEventAction.new()
			action.action = "ui_accept"
			action.pressed = down
			viewport.push_input(action, true)
			await process_frame
		var hero := _node("LoadoutHero") as Label
		var expected: Dictionary = scene.call("_hero_row", id)
		_check(hero != null and hero.text == expected.name,
			"Keyboard activation opens the selected " + id + " loadout")
		if hero != null:
			await _press("RecruitList")
	await _press("EditHero_healer")
	var recruit_list := _node("RecruitList") as BaseButton
	_check(recruit_list != null and recruit_list.is_visible_in_tree() and not recruit_list.disabled
		and _node("LoadoutHero") != null and _node("Recruit_healer") == null,
		"Selected hero opens a loadout folio with a return to available recruits")
	await _press("RecruitList")
	_check(_node("Recruit_healer") != null and _node("LoadoutHero") == null,
		"Returning to recruits restores the recruit list")
	await _press("PartyEarlier_healer")
	_check(scene.selected_recruits() == FOUNDER_PARTY, "Recruitment preserves the chosen order")
	await _press("StartAdventure")
	if scene.current_screen() != "routes":
		_check(false, "A recruited company receives route reports before battle")
		_cleanup()
		return
	run = scene.get("_run")
	# Keep reward choices reproducible without changing the commission route.
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 12345
	run.reward_rng_state = reward_rng.state
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
	_check(scene.battle_snapshot().get("party") == FOUNDER_PARTY, "Battle carries the selected party order")
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
	for id in FOUNDER_PARTY:
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
	for id in FOUNDER_PARTY:
		expected_hp[id] = adventure.next_mission_hp(run, id)
	await _press("Route_1")
	_check(scene.current_screen() == "battle", "The next report starts the next battle")
	if scene.current_screen() == "battle":
		_check(scene.battle_snapshot().get("party") == FOUNDER_PARTY, "The next battle retains party order")
		run = scene.get("_run")
		_check(run.get("carry_by_id", {}) == carry and run.get("upgrades_by_id", {}) == upgrades,
			"Next battle retains carried state and reward")
		var battle: Dictionary = scene.battle_snapshot()
		for unit in battle.get("units", []):
			var id := str(unit.get("id", ""))
			if id in FOUNDER_PARTY:
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


func _check_petitions_entry(scenario: String) -> void:
	for tick in 3:
		await process_frame
	var button := _node("Petitions") as Button
	var context := "%s at %s" % [scenario, viewport.size]
	for index in 3:
		var choose := _node("Commission_%d" % index) as Button
		_check(choose != null and choose.is_visible_in_tree() and not choose.disabled
			and choose.text == "Choose commission",
			context + ": commission %d has a visible enabled Choose commission button" % index)
		if choose != null:
			var choose_bounds := choose.get_global_rect()
			_check(choose_bounds.has_area()
				and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(choose_bounds),
				context + ": commission %d button fits the viewport" % index)
			var parent := choose.get_parent()
			while parent != null and parent != viewport:
				if parent is Control and parent.clip_contents:
					_check(parent.get_global_rect().encloses(choose_bounds),
						context + ": commission %d button is not clipped" % index)
				parent = parent.get_parent()
	_check(button != null and button.is_visible_in_tree() and not button.disabled
		and "guild petitions" in button.text.to_lower(),
		context + ": board has a visible actionable Guild petitions button")
	if button == null:
		return
	_check(button.theme_type_variation != "QuietButton",
		context + ": petitions entry is presented as an action, not quiet text")
	var bounds := button.get_global_rect()
	_check(bounds.has_area() and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(bounds),
		context + ": petitions button fits the viewport")
	var ancestor := button.get_parent()
	while ancestor != null and ancestor != viewport:
		if ancestor is Control and ancestor.clip_contents:
			_check(ancestor.get_global_rect().encloses(bounds), context + ": petitions button is not clipped")
		ancestor = ancestor.get_parent()
	for name in ["PracticeOutings", "CommissionCard_0", "CommissionCard_1", "CommissionCard_2"]:
		var other := _node(name) as Control
		if other != null and other.is_visible_in_tree():
			_check(not bounds.intersects(other.get_global_rect()),
				context + ": petitions does not overlap " + name)
	if viewport.get_parent() is SubViewportContainer:
		await _practice_window_click(button)
	else:
		var point := bounds.get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		viewport.push_input(motion, true)
		await process_frame
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			event.position = point
			event.global_position = point
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			viewport.push_input(event, true)
			await process_frame
	_check(_node("Petition_recruit_bard") != null,
		context + ": clicking the actual board entry opens petitions")


func _test_practice_after_commission_back() -> bool:
	var store = load("res://guild_profile.gd")
	var before: Dictionary = store.load_profile(profile_path)
	if before.is_empty() or before.has("error"):
		_check(false, "Fresh guild profile is available before practice: " + str(before))
		return false
	var original_bytes := FileAccess.get_file_as_bytes(profile_path)
	await _press("Commission_0")
	if scene.current_screen() != "guild":
		_check(false, "Commission recruitment opens before returning to the board")
		return false
	await _press("BackToCommissions")
	if scene.current_screen() != "commissions":
		_check(false, "Recruitment returns to the commission board")
		return false
	await _press("PracticeOutings")
	var selector := _node("AdventureSelect") as OptionButton
	var start := _node("StartAdventure") as Button
	if scene.current_screen() != "guild" or selector == null or not selector.is_visible_in_tree() \
			or selector.disabled or start == null or not start.is_visible_in_tree():
		_check(false, "Practice after commission back exposes its normal selector and departure")
		return false
	_check(start.disabled and start.text == "Depart on practice outing",
		"Practice departure is initially disabled and identifies the practice outing")
	if not await _select_id(selector, "first_outing"):
		return false
	for id in ["knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard"]:
		var recruit := _node("Recruit_" + id) as BaseButton
		_check(recruit != null and recruit.is_visible_in_tree() and not recruit.disabled,
			"Practice offers unrestricted recruit " + id)
	for id in ["knight", "healer", "bard"]:
		await _press("Recruit_" + id)
	start = _node("StartAdventure") as Button
	if start == null or start.disabled:
		_check(false, "Practice party enables departure")
		return false
	await _press("StartAdventure")
	if scene.current_screen() != "battle":
		_check(false, "Practice departure starts a battle, not commission reports")
		return false
	_check(scene.battle_snapshot().get("party") == ["knight", "healer", "bard"],
		"Practice deploys the selected unrestricted company")
	# The battle page was just built; let its containers finish layout before
	# the GUI driver derives a click position from the forfeit button.
	await process_frame
	var controls = load("res://tests/forfeit_controls.gd")
	var forfeit: BaseButton = controls.button(viewport, ["forfeit"])
	if forfeit == null:
		_check(false, "Practice battle offers forfeit")
		return false
	var forfeit_rect := forfeit.get_global_rect()
	if forfeit_rect.size.x <= 0 or forfeit_rect.size.y <= 0 \
			or not Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE)).encloses(forfeit_rect):
		_check(false, "Practice forfeit button has a reachable laid-out rectangle: " + str(forfeit_rect))
		return false
	await _practice_window_click(forfeit)
	var cancel: BaseButton = controls.button(viewport, ["cancel"])
	var confirm: BaseButton = controls.button(viewport, ["forfeit mission"], forfeit)
	if cancel == null or confirm == null:
		_check(false, "Practice forfeit requires confirmation and offers cancel (button rect: %s)" % str(forfeit_rect))
		return false
	await _practice_window_click(confirm)
	var outcome := _node("RunOutcome")
	if scene.current_screen() != "result" or outcome == null:
		_check(false, "Practice forfeit opens the ordinary defeat result")
		return false
	_check(outcome.get_meta("outcome", "") == "defeat", "Practice forfeit settles as defeat")
	await _press("ReturnToGuild")
	_check(scene.current_screen() == "guild" and _node("AdventureSelect") != null,
		"Returning after practice defeat opens practice recruitment")
	var after: Dictionary = store.load_profile(profile_path)
	_check(after == before and FileAccess.get_file_as_bytes(profile_path) == original_bytes,
		"Practice defeat does not settle or change the guild profile, seed, or points")
	if scene.current_screen() != "guild" or _node("AdventureSelect") == null:
		return false
	await _press("BackToCommissions")
	if scene.current_screen() != "commissions":
		_check(false, "Practice returns to the commission board")
		return false
	return true


func _practice_window_click(control: Control) -> void:
	var container := viewport.get_parent() as SubViewportContainer
	if container == null:
		_check(false, "Practice click requires the scaled viewport container")
		return
	var point := container.get_global_transform_with_canvas() * control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _commission_snapshot(index: int) -> Dictionary:
	var card := _node("CommissionCard_%d" % index)
	var button := _node("Commission_%d" % index) as BaseButton
	if card == null or button == null:
		return {}
	var labels: Array[String] = []
	for node in card.find_children("*", "Label", true, false):
		if node.is_visible_in_tree():
			labels.append(str(node.text))
	return {"title": button.accessibility_name, "description": button.accessibility_description,
		"labels": labels}


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
				for id in FOUNDER_PARTY:
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
	_remove_test_backup()
	_finish()


func _remove_test_backup() -> bool:
	var backup := profile_path + ".backup"
	if not FileAccess.file_exists(backup):
		return true
	var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(backup)) == OK
	_check(removed, "Test-owned profile backup is removed")
	return removed
