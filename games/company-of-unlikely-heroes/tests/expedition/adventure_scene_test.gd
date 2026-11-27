extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/expedition/adventure_scene_test.gd
# In a graphical session add -- --capture-guild=/absolute/path.png or
# --capture-battle=/absolute/path.png to inspect the actual viewport.
var failures: Array[String] = []
var scene: Node
var driver
var profile_path := "user://adventure_scene_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Create isolated legacy guild profile")
		_finish()
		return
	file.store_string('{"version":1,"name":"Scene Test","board_seed":"147258"}')
	file.close()
	var store = load("res://guild/guild_profile.gd")
	var catalog: Dictionary = load("res://content/catalog.gd").read_default()
	var migrated: Dictionary = store.load_profile(profile_path)
	_check(not migrated.has("error") and migrated.get("name") == "Scene Test" \
		and migrated.get("board_seed") == 147258 and "bard" in migrated.get("recruited_ids", []) \
		and "rogue" in migrated.get("recruited_ids", []),
		"Legacy v1 profile migrates its identity, seed and earlier roster")
	if migrated.has("error"):
		_finish()
		return
	# Fund only this migrated fixture, then exercise real permanent purchases.
	migrated.points = int(catalog.guild_progression.petitions.order_bard_sonnet.cost)
	migrated = store._write_profile(profile_path, migrated)
	for id in ["order_bard_sonnet"]:
		if migrated.has("error"):
			break
		migrated = store.purchase(profile_path, migrated, catalog, id)
		_check(not migrated.has("error") and id in migrated.get("purchased_ids", []),
			"Purchase journey fixture order " + id)
	if migrated.has("error"):
		_finish()
		return
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(profile_path)
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
	_check(scene.current_screen() == "commissions", "Normal launch opens commissions")
	await _press("Commission_0")
	_check(scene.current_screen() == "guild", "Commission opens recruitment")
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
	_check(scene.current_screen() == "routes", "Recruitment opens field reports")
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "Starting a full company launches battle")
		_finish()
		return
	for name in ["BridgeBoard", "StandingOrders", "ForecastDetails", "ClearCommand", "Commit"]:
		_check(_node(name) != null, "Battle exposes " + name)
	_check(_node("Actions") == null, "Battle has no legacy Actions menu")
	_check(_node("ModeDirect") == null and _node("ModeStanding") == null,
		"Battle has no retired mode selectors")
	var battle: Dictionary = scene.battle_snapshot()
	var units: Array = battle.get("units", [])
	if units.size() >= 3:
		for i in range(3):
			_check(units[i].get("id") == picks[i], "Deployed turn order follows guild selection")
			var defs: Dictionary = scene.get("_definitions")
			var mission: Dictionary = defs.missions[battle.mission_id]
			var slot: Array = defs.encounters[mission.encounter].party_slots[i]
			_check(units[i].get("position") == Vector2i(slot[0], slot[1]),
				"Selected turn order determines deployed slots")
	else:
		_check(false, "Battle deploys all three recruits")
	var plan: Dictionary = scene.get("_plan")
	var first_events: Array[String] = []
	for event in plan.get("events", []):
		var action: Dictionary = event.get("resolved_action", {})
		var actor := str(action.get("unit_id", ""))
		if actor.is_empty() and event.get("type") in ["recover", "wait"]:
			actor = str(event.get("unit_id", ""))
		if actor in picks and actor not in first_events:
			first_events.append(actor)
	_check(plan.get("valid", false) and first_events == picks,
		"Opening forecast resolves each hero's action or skipped turn in deployment order: " + str(first_events))
	await _capture("capture-battle")
	var order_id := "order_knight_advance_move"
	_check(battle.get("orders", {}).get("knight") == "order_guard" \
		and await driver.order("knight", order_id), "Knight can switch from Guard to move-only advance")
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
		_check(summary != null and summary.is_visible_in_tree()
			and driver.rules.display_name(round_before, "wizard") in summary.text,
			"HUD identifies the commanded hero")
		await _press("Commit")
		_check(scene.current_screen() == "battle", "Opening combat remains active after one round")
		if scene.current_screen() == "battle":
			_check(scene.battle_snapshot().get("round", 0) > round_before.get("round", 0),
				"Commit advances the round")
			# The Caster's Blast can knock the Knight down again before his turn.
			if await _choose_first_ability("healer"):
				summary = scene.get("_storybook_page").get("_summary") as Label
				_check(summary != null and summary.is_visible_in_tree()
					and driver.rules.display_name(scene.battle_snapshot(), "healer") in summary.text,
					"A different hero can be commanded next round")
	await _exercise_bard_guild()
	_finish()


func _exercise_bard_guild() -> void:
	scene.queue_free()
	await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(profile_path)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	await _press("Commission_0")
	var recruit := _node("Recruit_bard") as BaseButton
	_check(recruit != null and not recruit.disabled, "Guild offers Bard")
	if recruit == null or recruit.disabled:
		return
	await _press("Recruit_bard")
	_check("bard" in scene.selected_recruits(), "Bard joins the company")
	await _press("Recruit_healer")
	await _press("Recruit_wizard")
	await _press("StartAdventure")
	await _press("Route_0")
	_check(scene.current_screen() == "battle", "Company with Bard deploys")
	if scene.current_screen() != "battle":
		return
	for id in ["order_inspiring_melody", "order_healing_sonnet"]:
		if await driver.order("bard", id):
			_check(scene.battle_snapshot().get("orders", {}).get("bard") == id,
				"Bard scene selects " + id)
		else:
			_check(false, driver.error)


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
	for path in [profile_path, profile_path + ".backup"]:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
				"Remove isolated profile " + path)
	if failures.is_empty():
		print("PASS: adventure scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
