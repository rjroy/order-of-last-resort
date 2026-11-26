extends "res://tests/expedition/forfeit_outing_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/journeys/guild_first_paths_scene_test.gd
# Normal stock commission, disposable profile, real GUI commands and commits.
const FOUNDERS := ["knight", "healer", "wizard"]


# Captures are the unscaled off-screen viewport, not a screen/window grab.
# Never overwrite an earlier run's evidence.
func _capture(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):
			continue
		var directory := arg.trim_prefix("--capture-dir=")
		if directory.is_empty() or not directory.is_absolute_path() \
				or not DirAccess.dir_exists_absolute(directory) or DisplayServer.get_name() == "headless":
			_check(false, "Capture requires an existing absolute directory and graphical display")
			return
		var path := directory.path_join(name + ".png")
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			_check(false, "Capture refuses to overwrite " + path)
			return
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty() or image.get_size() != VIEWPORT_SIZE:
			_check(false, "Capture has no full-sized viewport image: " + name)
			return
		# Empty GPU captures can be valid PNGs; require visible pixel variation.
		var first := image.get_pixel(0, 0)
		var varied := false
		for y in range(0, image.get_height(), 16):
			for x in range(0, image.get_width(), 16):
				if image.get_pixel(x, y) != first:
					varied = true
					break
			if varied:
				break
		if not varied:
			_check(false, "Capture contains only a uniform image: " + name)
			return
		_check(image.save_png(path) == OK, "Capture saves " + name)


# Callers must check this completion marker as well as the exit status: a
# script error can abort a deferred coroutine without reaching _finish().
func _finish() -> void:
	if failures.is_empty():
		print("PASS: guild first paths test completed")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var store = load("res://guild/guild_profile.gd")
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Disposable guild can be created: " + str(created))
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
		var recruit := _node("Recruit_" + id) as BaseButton
		_check(recruit != null and recruit.is_visible_in_tree() and not recruit.disabled,
			"Fresh guild can recruit founder " + id)
	for id in ["bard", "rogue", "necromancer", "alchemist"]:
		var recruit := _node("Recruit_" + id) as BaseButton
		_check(recruit == null or not recruit.is_visible_in_tree() or recruit.disabled,
			"Fresh guild cannot recruit locked hero " + id)
	for id in FOUNDERS:
		await _press("Recruit_" + id)
	_check(scene.selected_recruits() == FOUNDERS, "Fresh guild selects the three founders")
	await _press("StartAdventure")
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "Founders enter the first road battle")
		_cleanup()
		return
	if not await _win_road_and_continue():
		_cleanup()
		return
	var escape := ForfeitControls.button(viewport, ["forfeit"])
	if escape == null:
		_check(false, "Second mission offers forfeit")
		_cleanup()
		return
	await ForfeitControls.click(self, escape)
	var cancel := ForfeitControls.button(viewport, ["cancel"])
	var confirm := ForfeitControls.button(viewport, ["forfeit mission"], escape)
	if cancel == null or confirm == null:
		_check(false, "Forfeit requires confirmation and permits cancellation")
		_cleanup()
		return
	var before_cancel: Dictionary = store.load_profile(profile_path)
	await ForfeitControls.click(self, cancel)
	_check(scene.current_screen() == "battle" and store.load_profile(profile_path) == before_cancel,
		"Canceling forfeit leaves the mission and guild ledger unchanged")
	await ForfeitControls.click(self, escape)
	confirm = ForfeitControls.button(viewport, ["forfeit mission"], escape)
	if confirm == null:
		_check(false, "Forfeit can be confirmed after cancellation")
		_cleanup()
		return
	await ForfeitControls.click(self, confirm)
	_check(scene.current_screen() == "result", "Confirmed forfeit reaches the ordinary result")
	var result_text := _visible_text().to_lower()
	_check(_shows_one_point(result_text),
		"Result tells the player that the earlier road earned one guild point")
	var return_button := _node("ReturnToGuild") as BaseButton
	if return_button == null or not return_button.is_visible_in_tree() or return_button.disabled:
		_check(false, "Forfeit result permits return to guild")
		_cleanup()
		return
	await ForfeitControls.click(self, return_button)
	var settled: Dictionary = store.load_profile(profile_path)
	var guild_text := _visible_text().to_lower()
	_check(_shows_one_point(guild_text),
		"Returning after forfeit shows the earned point in the guild")
	_check(settled != before_cancel, "Returning persists earned progress")
	await _launch_normal()
	_check(store.load_profile(profile_path) == settled, "Relaunch preserves settled progress")
	guild_text = _visible_text().to_lower()
	_check(_shows_one_point(guild_text),
		"Relaunch still displays the one-point balance")
	await _launch_normal()
	_check(store.load_profile(profile_path) == settled, "Repeated reload cannot settle the same outing twice")
	_cleanup()


func _win_road_and_continue() -> bool:
	var decisive := false
	for round_index in MAX_ROUNDS:
		await _stage_founder_command()
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		if not plan.get("valid", false):
			_check(false, "Road round %d has a legal forecast" % round_index)
			return false
		var outcome: String = plan.get("result", {}).get("outcome", "")
		var commit := _node("Commit") as BaseButton
		if commit == null or not commit.is_visible_in_tree() or commit.disabled:
			_check(false, "Road has an enabled Commit")
			return false
		await _settlement_click(commit.get_global_rect().get_center())
		if outcome != "ongoing":
			decisive = outcome == "victory"
			break
	if not decisive or scene.current_screen() != "debrief":
		_check(false, "First road reaches a victory debrief")
		return false
	var text := _visible_text().to_lower()
	_check(_shows_one_point(text), "Road victory displays one point earned so far")
	var reward: BaseButton
	for id in FOUNDERS:
		var candidate := _node("Reward_" + id) as BaseButton
		if candidate != null and candidate.is_visible_in_tree() and not candidate.disabled:
			reward = candidate
			break
	if reward == null:
		_check(false, "Road victory also offers a separate temporary upgrade")
		return false
	if not await RewardClick.click(self, reward, _settlement_click):
		return false
	var continuation := _node("ContinueAdventure") as BaseButton
	if continuation == null or continuation.disabled:
		_check(false, "Claiming the temporary upgrade enables continuation")
		return false
	await _settlement_click(continuation.get_global_rect().get_center())
	if scene.current_screen() != "routes":
		_check(false, "Road victory continues to the next route")
		return false
	await _press("Route_0")
	_check(scene.current_screen() == "battle", "Second road deploys")
	return scene.current_screen() == "battle"


func _shows_one_point(text: String) -> bool:
	var expression := RegEx.new()
	expression.compile("(?i)(\\b1\\s+(?:guild\\s+)?points?\\b|\\b(?:guild\\s+)?points?\\s*[:+]\\s*1\\b)")
	return expression.search(text) != null


func _stage_founder_command() -> void:
	# The inherited driver hardcodes its Bard party; this one uses the founders.
	var rules = load("res://rules/rules.gd").new()
	var state: Dictionary = scene.battle_snapshot()
	var best_score := _score(scene.get("_plan").get("result", {}), FOUNDERS)
	var best := {}
	for actor in FOUNDERS:
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
				var score := _score(forecast.get("result", {}), FOUNDERS)
				if score > best_score:
					best_score = score
					best = {"actor": actor, "ability": option.id, "target": target.id}
	if best.is_empty():
		return
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await driver.command(best.actor, best.ability, str(best.target)):
		_check(false, "Storybook command editor stages the chosen founder action: " + driver.error)
		return
	var staged: Dictionary = scene.get("_planned_state")
	_check(staged.get("overrides", {}).get(best.actor, {}).get("ability_id") == best.ability,
		"Storybook command editor stages the chosen founder action")
