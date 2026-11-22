extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/adventure_scene_test.gd
# In a graphical session add -- --capture-guild=/absolute/path.png or
# --capture-battle=/absolute/path.png to inspect the actual viewport.
var failures: Array[String] = []
var scene: Node
var driver


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--fixed-outings"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not scene.has_method("current_screen") or not scene.has_method("selected_recruits") \
			or not scene.has_method("battle_snapshot"):
		_check(false, "Scene must expose the adventure screen and snapshot contract")
		_finish()
		return
	_check(scene.current_screen() == "guild", "Fixed outings launch opens the guild")
	_check(_node("GuildScreen") != null, "Guild screen is present")
	_check(_node("ModeDirect") == null and _node("ModeStanding") == null,
		"Guild has no retired mode selectors")
	await _capture("capture-guild")
	var start := _node("StartAdventure") as BaseButton
	if start == null:
		_check(false, "Guild offers StartAdventure")
		_finish()
		return
	_check(start.disabled, "Cannot launch an empty company")
	var rogue := _node("Recruit_rogue") as BaseButton
	_check(rogue != null and not rogue.disabled, "Guild offers Rogue as a selectable recruit")
	if rogue != null and not rogue.disabled:
		await _press("Recruit_rogue")
		_check("rogue" in scene.selected_recruits(), "Selecting Rogue adds them to the company")
		await _press("Recruit_rogue")
		_check("rogue" not in scene.selected_recruits(), "Rogue can be deselected")
	await _press("Recruit_knight")
	await _press("Recruit_healer")
	_check((_node("StartAdventure") as BaseButton).disabled, "Two recruits are not enough")
	await _press("Recruit_wizard")
	_check(not (_node("StartAdventure") as BaseButton).disabled, "Three recruits can launch")
	var fourth := _node("Recruit_alchemist") as BaseButton
	if fourth != null and not fourth.disabled:
		await _press("Recruit_alchemist")
	_check(scene.selected_recruits().size() == 3, "A fourth recruit cannot overfill the company")
	await _press("PartyEarlier_wizard")
	var picks: Array = scene.selected_recruits()
	_check(picks == ["knight", "wizard", "healer"], "Earlier changes the selected turn order")
	await _press("PartyLater_knight")
	picks = scene.selected_recruits()
	_check(picks == ["wizard", "knight", "healer"], "Later changes the selected turn order")
	await _press("StartAdventure")
	if scene.current_screen() != "battle":
		_check(false, "Starting a full company launches battle")
		_finish()
		return
	for name in ["BridgeBoard", "Actions", "StandingOrders", "ForecastDetails", "ClearCommand", "Commit"]:
		_check(_node(name) != null, "Battle exposes " + name)
	_check(_node("ModeDirect") == null and _node("ModeStanding") == null,
		"Battle has no retired mode selectors")
	var battle: Dictionary = scene.battle_snapshot()
	var units: Array = battle.get("units", [])
	if units.size() >= 3:
		for i in range(3):
			_check(units[i].get("id") == picks[i], "Deployed turn order follows guild selection")
			_check(units[i].get("position") == [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)][i],
				"Selected turn order determines deployed slots")
	else:
		_check(false, "Battle deploys all three recruits")
	var plan: Dictionary = scene.get("_plan")
	var first_events: Array[String] = []
	for event in plan.get("events", []):
		var actor := str(event.get("unit_id", ""))
		if actor in picks and actor not in first_events:
			first_events.append(actor)
	_check(first_events == picks, "Opening forecast executes heroes in the selected order")
	await _capture("capture-battle")
	var order_id := ""
	for choice: Dictionary in driver.rules.options(battle, "knight"):
		if choice.kind == "order" and choice.id != battle.get("orders", {}).get("knight"):
			order_id = choice.id
			break
	_check(not order_id.is_empty() and await driver.order("knight", order_id), "Knight has an editable standing order")
	_check(scene.battle_snapshot().get("orders", {}).get("knight") == order_id,
		"Standing order changes the selected hero's order")
	var round_before: Dictionary = scene.battle_snapshot()
	if await _choose_first_ability("wizard"):
		await _press("ForecastDetails")
		var forecast := scene.get("_storybook_page").get("_forecast_text") as Label
		_check(forecast != null and forecast.is_visible_in_tree() and not forecast.text.strip_edges().is_empty(),
			"Override shows a forecast")
		await _press("ForecastDetails")
		_check(scene.battle_snapshot().get("round") == round_before.get("round"), "Preview does not advance")
		var summary := scene.get("_storybook_page").get("_summary") as Label
		_check(summary != null and summary.is_visible_in_tree() and "wizard" in summary.text.to_lower(),
			"HUD identifies the commanded hero")
		await _press("Commit")
		_check(scene.current_screen() == "battle", "Opening combat remains active after one round")
		if scene.current_screen() == "battle":
			_check(scene.battle_snapshot().get("round", 0) > round_before.get("round", 0),
				"Commit advances the round")
			if await _choose_first_ability("knight"):
				summary = scene.get("_storybook_page").get("_summary") as Label
				_check(summary != null and summary.is_visible_in_tree() and "knight" in summary.text.to_lower(),
					"A different hero can be commanded next round")
	await _exercise_transition_fixture()
	await _exercise_bard_guild()
	_finish()


func _exercise_bard_guild() -> void:
	scene.queue_free()
	await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--fixed-outings"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var recruit := _node("Recruit_bard") as BaseButton
	_check(recruit != null and not recruit.disabled, "Guild offers Bard")
	if recruit == null or recruit.disabled:
		return
	await _press("Recruit_bard")
	_check("bard" in scene.selected_recruits(), "Bard joins the company")
	await _press("Recruit_healer")
	await _press("Recruit_wizard")
	await _press("StartAdventure")
	_check(scene.current_screen() == "battle", "Company with Bard deploys")
	if scene.current_screen() != "battle":
		return
	for id in ["order_inspiring_melody", "order_healing_sonnet"]:
		if await driver.order("bard", id):
			_check(scene.battle_snapshot().get("orders", {}).get("bard") == id,
				"Bard scene selects " + id)
		else:
			_check(false, driver.error)


func _exercise_transition_fixture() -> void:
	# Keep the stock catalog and control the transient battle state: Wizard takes
	# recoil, then Alchemist defeats the remaining fragile foe.
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default()
	scene.queue_free()
	await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--fixed-outings"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	for id in ["wizard", "knight", "alchemist"]:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 12345
	var outing: Dictionary = scene.get("_run")
	outing.reward_rng_state = reward_rng.state
	if scene.current_screen() == "battle":
		var state: Dictionary = scene.get("_state").duplicate(true)
		var foe_set := false
		for unit: Dictionary in state.units:
			if unit.id == "alchemist":
				unit.position = Vector2i(3, 1)
			elif unit.id not in ["wizard", "knight", "alchemist"]:
				if not foe_set:
					unit.position = Vector2i(4, 1)
					unit.hp = 1
					foe_set = true
				else:
					unit.hp = 0
		_check(foe_set, "Stock patrol supplies a foe for the transition fixture")
		scene.set("_state", state)
		scene.set("_planned_state", state.duplicate(true))
		_check(await driver.order("alchemist", "order_blast"), driver.error)
		if await driver.command("wizard", "wizard_pull", "knight"):
			await _press("Commit")
		else:
			_check(false, driver.error)
	_check(scene.current_screen() == "debrief", "Committed fixture victory opens debrief")
	if scene.current_screen() == "debrief":
		var report := _node("CarryReport")
		_check(report != null and "Wizard   4/6 HP → 4/6 HP  ·  Wounded" in str(report.text),
			"Debrief reports the wizard's recoil wound and carry")
		await process_frame
		_check(scene.current_screen() == "debrief", "Debrief waits for explicit continuation")
		var reward := _node("Reward_knight") as BaseButton
		_check(reward != null and reward.is_visible_in_tree(), "Knight has a visible reward offer")
		_check(_node("Reward_wizard") != null and _node("Reward_alchemist") == null,
			"Only eligible heroes have reward offers")
		var continue_button := _node("ContinueAdventure") as BaseButton
		_check(continue_button != null and continue_button.disabled, "Continuation requires one reward")
		var offered_run: Dictionary = scene.get("_run")
		_check(offered_run.get("phase") == "reward" and offered_run.get("reward_offers", []).size() == 2,
			"Debrief offers one choice per eligible hero")
		# A disabled continuation cannot bypass the choice through its public handler.
		if continue_button != null:
			_check(continue_button.disabled, "No unchosen reward can be bypassed")
		if reward != null:
			await _press("Reward_knight")
			var chosen_run: Dictionary = scene.get("_run")
			_check(chosen_run.get("phase") == "ready", "Selecting one reward completes the choice")
			_check(_node("Reward_knight") == null and _node("Reward_wizard") == null,
				"Claimed debrief exposes no second reward button")
			var counts: Dictionary = chosen_run.get("upgrades_by_id", {})
			var count := 0
			for hero in counts:
				for value in counts[hero].values():
					count += int(value)
			_check(count == 1 and counts.get("alchemist", {}).is_empty(), "Only one eligible hero gains a reward")
		await _press("ContinueAdventure")
		_check(scene.current_screen() == "battle", "Continue starts the second mission")
		if scene.current_screen() == "battle":
			var second: Dictionary = scene.battle_snapshot()
			_check(second.get("mission_id") == "company_rescue", "Second mission is the rescue")
			var run: Dictionary = scene.get("_run")
			var knight_rewards: Dictionary = run.get("upgrades_by_id", {}).get("knight", {})
			var loadout := _node("ShowLoadout") as BaseButton
			_check(loadout != null and loadout.is_visible_in_tree(), "Battle shows outing upgrades control")
			if loadout != null and not knight_rewards.is_empty():
				var upgrade_id: String = knight_rewards.keys()[0]
				var upgrade: Dictionary = defs.upgrades[upgrade_id]
				await _press("ShowLoadout")
				var dialog := _node("OutingLoadout") as Window
				_check(dialog != null and dialog.visible, "Outing loadout opens")
				if dialog != null:
					var text := ""
					for label in dialog.find_children("*", "Label", true, false):
						text += str(label.text) + "\n"
					_check(upgrade.label in text and upgrade.description in text and "Knight" in text,
						"Loadout displays the claimed hero, reward and description")
					dialog.hide()
			var wizard_hp := -1
			for unit in second.get("units", []):
				if unit.get("id") == "wizard":
					wizard_hp = unit.get("hp", -1)
			_check(wizard_hp == 4, "Second mission carries the wizard's wound")
			var final_round: Dictionary = scene.get("_state").duplicate(true)
			final_round.round = driver.rules.deadline(final_round)
			scene.set("_state", final_round)
			scene.set("_planned_state", final_round.duplicate(true))
			# Refresh the forecast through an ordinary order selection.
			_check(await driver.order("knight", str(final_round.orders.knight)), driver.error)
			await _press("Commit")
			_check(scene.current_screen() == "result", "Deadline defeat ends the adventure")
			if scene.current_screen() == "result":
				var outcome := _node("RunOutcome")
				_check(outcome != null and outcome.get_meta("outcome", "") == "defeat",
					"Result identifies defeat")
				await _press("ReturnToGuild")
				_check(scene.current_screen() == "guild" and scene.selected_recruits().is_empty(),
					"Returning to guild resets the selection")
				var guild_run: Dictionary = scene.get("_run")
				_check(guild_run.get("upgrades_by_id", {}).is_empty() and guild_run.get("reward_offers", []).is_empty(),
					"Returning after defeat clears rewards")
func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _choose_first_ability(actor: String) -> bool:
	var state: Dictionary = scene.get("_state")
	var context: Dictionary = driver.rules.state_before_action(state, actor)
	for choice: Dictionary in driver.rules.options(state, actor):
		if choice.kind != "action":
			continue
		var targets: Array = driver.rules.targets(context, actor, choice.id)
		var target := str(targets[0].id) if not targets.is_empty() else ""
		if await driver.command(actor, choice.id, target):
			return true
	_check(false, "Selectable actor and ability: " + actor)
	return false


func _press(name: String) -> void:
	var button := _node(name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is visible and enabled")
		return
	button.pressed.emit()
	await process_frame


func _capture(key: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--" + key + "="):
			continue
		var path := arg.trim_prefix("--" + key + "=")
		if not path.is_absolute_path():
			_check(false, "Capture path must be absolute")
			return
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(image != null and not image.is_empty() and image.save_png(path) == OK,
			"Capture saves the viewport")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: adventure scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
