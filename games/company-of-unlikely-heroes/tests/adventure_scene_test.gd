extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/adventure_scene_test.gd
# In a graphical session add -- --capture-guild=/absolute/path.png or
# --capture-battle=/absolute/path.png to inspect the actual viewport.
var failures: Array[String] = []
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if not scene.has_method("current_screen") or not scene.has_method("selected_recruits") \
			or not scene.has_method("battle_snapshot"):
		_check(false, "Scene must expose the adventure screen and snapshot contract")
		_finish()
		return
	_check(scene.current_screen() == "guild", "Default launch opens the guild")
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
	for name in ["BattleScreen", "MissionTitle", "RoundText", "ObjectiveText", "ObjectiveProgress",
			"InitiativeText", "BridgeBoard", "ActorSelect", "AbilitySelect", "TargetSelect",
			"Preview", "ClearCommand", "PreviewText", "Commit", "CommandedHero", "LastResult"]:
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
	var order := _order_picker("knight")
	if order == null or order.item_count < 2:
		_check(false, "Knight has an editable standing order")
	else:
		var index := (order.selected + 1) % order.item_count
		var order_id := str(order.get_item_metadata(index))
		await _select(order, index)
		_check(scene.battle_snapshot().get("orders", {}).get("knight") == order_id,
			"Standing order changes the selected hero's order")
	var round_before: Dictionary = scene.battle_snapshot()
	if await _choose_first_ability("wizard"):
		await _press("Preview")
		_check(not str(_node("PreviewText").text).strip_edges().is_empty(), "Override shows a forecast")
		_check(scene.battle_snapshot().get("round") == round_before.get("round"), "Preview does not advance")
		_check("wizard" in str(_node("CommandedHero").text).to_lower(),
			"HUD identifies the commanded hero")
		await _press("Commit")
		_check(scene.current_screen() == "battle", "Opening combat remains active after one round")
		if scene.current_screen() == "battle":
			_check(scene.battle_snapshot().get("round", 0) > round_before.get("round", 0),
				"Commit advances the round")
			if await _choose_first_ability("knight"):
				await _press("Preview")
				_check("knight" in str(_node("CommandedHero").text).to_lower(),
					"A different hero can be commanded next round")
	await _exercise_transition_fixture()
	_finish()


func _exercise_transition_fixture() -> void:
	# Keep this UI transition probe separate from the shipped-content winning routes.
	# The wizard takes recoil, then the adjacent alchemist defeats a fragile foe.
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default().duplicate(true)
	defs.encounters.road_patrol.party_slots = [[1, 1], [1, 2], [3, 1]]
	defs.encounters.road_patrol.placements = [{"id": "raider_one", "character": "scene_foe", "at": [4, 1]}]
	defs.characters.scene_foe = {"class": "enemy", "label": "Scene foe", "max_hp": 1, "behavior": "hold"}
	defs.encounters.company_crossing.deadline = 1
	var path := "user://adventure_scene_fixture_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write the isolated content fixture")
		return
	file.store_string(JSON.stringify(defs))
	file.close()
	scene.queue_free()
	await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(path)]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	for id in ["wizard", "knight", "alchemist"]:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	if scene.current_screen() == "battle":
		var order := _order_picker("alchemist")
		if order != null:
			await _select_id(order, "order_blast")
		else:
			_check(false, "Fixture offers the alchemist order")
		if await _select_id(_node("ActorSelect") as OptionButton, "wizard") \
				and await _select_id(_node("AbilitySelect") as OptionButton, "wizard_pull") \
				and await _select_id(_node("TargetSelect") as OptionButton, "knight"):
			await _press("Preview")
			await _press("Commit")
	_check(scene.current_screen() == "debrief", "Committed fixture victory opens debrief")
	if scene.current_screen() == "debrief":
		var report := _node("CarryReport")
		_check(report != null and "Wizard   4/6 HP → 4/6 HP  ·  Wounded" in str(report.text),
			"Debrief reports the wizard's recoil wound and carry")
		await process_frame
		_check(scene.current_screen() == "debrief", "Debrief waits for explicit continuation")
		await _press("ContinueAdventure")
		_check(scene.current_screen() == "battle", "Continue starts the second mission")
		if scene.current_screen() == "battle":
			var second: Dictionary = scene.battle_snapshot()
			_check(second.get("mission_id") == "company_rescue", "Second mission is the rescue")
			var wizard_hp := -1
			for unit in second.get("units", []):
				if unit.get("id") == "wizard":
					wizard_hp = unit.get("hp", -1)
			_check(wizard_hp == 4, "Second mission carries the wizard's wound")
			await _press("Commit")
			_check(scene.current_screen() == "result", "Deadline defeat ends the adventure")
			if scene.current_screen() == "result":
				var outcome := _node("RunOutcome")
				_check(outcome != null and outcome.get_meta("outcome", "") == "defeat",
					"Result identifies defeat")
				await _press("ReturnToGuild")
				_check(scene.current_screen() == "guild" and scene.selected_recruits().is_empty(),
					"Returning to guild resets the selection")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
		"Temporary content fixture is removed")


func _select_id(picker: OptionButton, id: String) -> bool:
	if picker != null:
		for i in picker.item_count:
			if str(picker.get_item_metadata(i)) == id:
				await _select(picker, i)
				return true
	_check(false, "Missing selectable choice " + id)
	return false


func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _order_picker(id: String) -> OptionButton:
	for picker in scene.find_children("*", "OptionButton", true, false):
		if picker.get_meta("actor_id", "") == id:
			return picker
	return null


func _choose_first_ability(actor: String) -> bool:
	var actors := _node("ActorSelect") as OptionButton
	if actors == null:
		_check(false, "Actor selector is available")
		return false
	for i in actors.item_count:
		if str(actors.get_item_metadata(i)) == actor:
			await _select(actors, i)
			var abilities := _node("AbilitySelect") as OptionButton
			if abilities != null and abilities.item_count > 0:
				await _select(abilities, 0)
				return true
	_check(false, "Selectable actor and ability: " + actor)
	return false


func _select(picker: OptionButton, index: int) -> void:
	if picker.disabled or picker.is_item_disabled(index) or not picker.is_visible_in_tree():
		_check(false, "%s option %d is selectable" % [picker.name, index])
		return
	picker.select(index)
	picker.item_selected.emit(index)
	await process_frame


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
