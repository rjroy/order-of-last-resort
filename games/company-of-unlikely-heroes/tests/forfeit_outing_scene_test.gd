extends "res://tests/commission_storybook_settlement_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/forfeit_outing_scene_test.gd
const ForfeitControls = preload("res://tests/forfeit_controls.gd")


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
		_check(false, "Normal commission enters a battle")
		_cleanup()
		return
	if not await _earn_upgrade_and_deploy():
		_cleanup()
		return
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var run_before: Dictionary = scene.get("_run").duplicate(true)
	_check(before.get("mission_id") != "wrong_side_of_the_door",
		"Commission fixture exercises an unrelated combat")
	var upgrades := _node("ShowLoadout") as BaseButton
	var loadout := _node("OutingLoadout") as Window
	_check(upgrades != null and upgrades.is_visible_in_tree() and not upgrades.disabled
		and loadout != null and not loadout.visible, "Outing upgrades are available before confirmation")
	var escape := ForfeitControls.button(viewport, ["forfeit"])
	_check(escape != null, "Normal combat exposes Forfeit before committing a round")
	if escape == null:
		_cleanup()
		return
	await ForfeitControls.click(self, escape)
	_check(scene.current_screen() == "battle" and scene.battle_snapshot() == before
		and scene.get("_run") == run_before, "Opening confirmation does not settle the outing")
	var cancel := ForfeitControls.button(viewport, ["cancel"])
	var confirm := ForfeitControls.button(viewport, ["forfeit mission"], escape)
	_check(cancel != null and confirm != null, "Outing forfeit requires explicit confirmation")
	if cancel == null or confirm == null:
		_cleanup()
		return
	if upgrades != null and loadout != null:
		var focus_before := viewport.gui_get_focus_owner()
		if upgrades.is_visible_in_tree() and not upgrades.disabled:
			upgrades.pressed.emit()
			await process_frame
		_check(not loadout.visible and cancel.is_visible_in_tree()
			and viewport.gui_get_focus_owner() == focus_before,
			"Upgrades accessibility activation cannot stack a dialog or steal confirmation focus")
		if loadout.visible:
			# Keep the defeat assertions independent on a broken implementation.
			loadout.hide()
			cancel.grab_focus()
			await process_frame
	await ForfeitControls.click(self, confirm)
	var settled: Dictionary = scene.get("_run").duplicate(true)
	_check(settled.get("phase") == "finished" and settled.get("outcome") == "defeat"
		and settled.get("last_result", {}).get("outcome") == "defeat",
		"Confirmed forfeit uses the ordinary defeat settlement")
	_check(settled.get("mission_index") == run_before.get("mission_index")
		and settled.get("reward_offers", []).is_empty()
		and settled.get("upgrades_by_id") == run_before.get("upgrades_by_id"),
		"Defeat neither advances the route nor awards rewards")
	_check(scene.current_screen() == "result", "Defeat opens the ordinary outing result")
	await process_frame
	_check(scene.get("_run") == settled, "Settlement is not repeated after the confirmation")
	var return_button := _node("ReturnToGuild") as BaseButton
	if return_button == null or not return_button.is_visible_in_tree() or return_button.disabled:
		_check(false, "Ordinary result offers return to guild")
	else:
		await ForfeitControls.click(self, return_button)
		var guild: Dictionary = scene.get("_run")
		_check(scene.current_screen() == "commissions" and guild.is_empty()
			and guild.get("upgrades_by_id", {}).is_empty()
			and guild.get("reward_offers", []).is_empty() and guild.get("chosen_reward", {}).is_empty(),
			"Returning to guild performs the normal outing reset")
	_cleanup()


func _earn_upgrade_and_deploy() -> bool:
	# Use the inherited deterministic stock-commission player and actual reward
	# controls: an opening battle has no upgrade button until one is earned.
	var decisive := false
	for round_index in MAX_ROUNDS:
		await _stage_best_command()
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		if not plan.get("valid", false):
			_check(false, "First outing round %d has a legal forecast" % round_index)
			return false
		var outcome: String = plan.get("result", {}).get("outcome", "")
		var commit := _node("Commit") as BaseButton
		if commit == null or not commit.is_visible_in_tree() or commit.disabled:
			_check(false, "First outing battle has an enabled Commit")
			return false
		await _settlement_click(commit.get_global_rect().get_center())
		if outcome != "ongoing":
			decisive = outcome == "victory"
			break
		if scene.current_screen() != "battle":
			_check(false, "Nonterminal outing commit stays in battle")
			return false
	if not decisive or scene.current_screen() != "debrief":
		_check(false, "First outing battle reaches a victory reward debrief")
		return false
	var reward: BaseButton
	for id in FOUNDER_PARTY:
		var candidate := _node("Reward_" + id) as BaseButton
		if candidate != null and candidate.is_visible_in_tree() and not candidate.disabled:
			reward = candidate
			break
	if reward == null:
		_check(false, "Victory offers an eligible upgrade")
		return false
	if not await RewardClick.click(self, reward, _settlement_click):
		return false
	var owned: Dictionary = scene.get("_run").get("upgrades_by_id", {}).duplicate(true)
	if not owned.values().any(func(upgrades: Dictionary) -> bool: return not upgrades.is_empty()):
		_check(false, "GUI reward choice earns an upgrade")
		return false
	var continuation := _node("ContinueAdventure") as BaseButton
	if continuation == null or not continuation.is_visible_in_tree() or continuation.disabled:
		_check(false, "Claimed upgrade enables continuation")
		return false
	await _settlement_click(continuation.get_global_rect().get_center())
	if scene.current_screen() != "routes":
		_check(false, "Claimed upgrade continues to route choice")
		return false
	await _press("Route_0")
	if scene.current_screen() != "battle" or scene.get("_run").get("upgrades_by_id") != owned:
		_check(false, "Next battle deploys with the earned upgrade")
		return false
	return true
