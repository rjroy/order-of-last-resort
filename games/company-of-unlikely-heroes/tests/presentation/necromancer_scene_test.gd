extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/necromancer_scene_test.gd
# This exercises a test-owned combat snapshot through the actual battle controls.
var failures: Array[String] = []
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var opening := practice_snapshot()
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	await process_frame
	if scene.current_screen() != "battle":
		_check(false, "Practice mission launches into battle")
		_finish()
		return

	var initial: Dictionary = scene.battle_snapshot()
	_check(_unit(initial, "healer").get("position") == Vector2i(1, 1), "Healer starts at B2")
	_check(_unit(initial, "necromancer").get("position") == Vector2i(2, 2), "Necromancer starts at C3")
	_check(_unit(initial, "practice_raider").get("position") == Vector2i(3, 1), "Raider starts at D2")
	_check(_unit(initial, "fallen_raider").get("position") == Vector2i(4, 3)
		and _unit(initial, "fallen_raider").get("hp") == 0, "Corpse starts at E4")

	if not await _command("necromancer", "raise_dead", "fallen_raider"):
		_finish()
		return
	var first: Dictionary = scene.get("_plan").duplicate(true)
	_check(_has_summon(first, "necromancer_zombie", Vector2i(4, 3), 3),
		"Round 1 previews a 3 HP zombie at E4")
	if not await _commit_matches(first):
		_finish()
		return

	if not await _command("necromancer", "summon_skeleton", "2,1"):
		_finish()
		return
	var second: Dictionary = scene.get("_plan").duplicate(true)
	_check(_has_summon(second, "necromancer_skeleton", Vector2i(2, 1), 1),
		"Round 2 previews a 1 HP skeleton at C2")
	if not await _commit_matches(second):
		_finish()
		return
	var board := _node("BridgeBoard")
	_check(board != null and board.is_visible_in_tree(), "Battle board is visible")
	if board != null:
		var drawn: Array = board.get("_units")
		_check(_drawn(drawn, "necromancer_zombie", "zombie"), "Board displays the zombie art key")
		_check(_drawn(drawn, "necromancer_skeleton", "skeleton"), "Board displays the skeleton art key")

	var stay: Dictionary = scene.get("_plan").duplicate(true)
	_check(_wave_hits(stay, "healer") and _wave_hits(stay, "necromancer")
		and _wave_hits(stay, "practice_raider"), "Standing forecast shows Wave hitting all three neighbors")
	await _press("ForecastDetails")
	var forecast := scene.get("_storybook_page").get("_forecast_text") as Label
	_check(forecast != null and forecast.is_visible_in_tree() and "Wave" in str(forecast.text),
		"Visible standing forecast names Wave")
	await _press("ForecastDetails")
	var before: Dictionary = scene.battle_snapshot()
	if not await _command("healer", "move", "0,1"):
		_finish()
		return
	var escape: Dictionary = scene.get("_plan").duplicate(true)
	_check(scene.battle_snapshot() == before, "Preview does not mutate the battle")
	_check(not _wave_hits(escape, "healer") and _wave_hits(escape, "necromancer")
		and _wave_hits(escape, "practice_raider"), "Moving to A2 avoids Wave while the other hits remain")
	_check(_move_precedes_wave(escape), "Forecast orders the Healer's move before Wave")
	if await _commit_matches(escape):
		var healer := _unit(scene.battle_snapshot(), "healer")
		_check(healer.get("position") == Vector2i(0, 1) and healer.get("hp") == 7,
			"Healer ends at A2 with full HP")
	await _ambiguous_target_after_commit()
	_finish()


static func practice_snapshot(wounded := "", bard := false) -> Dictionary:
	var defs: Dictionary = load("res://content/catalog.gd").read_default().duplicate(true)
	defs.characters.practice_raider = defs.characters.grunt.duplicate(true)
	defs.characters.practice_raider.behavior = "hold"
	if bard:
		defs.characters.practice_raider.max_hp = 30
	var first := "bard" if bard else "healer"
	var placements := [
		{"id": first, "character": first, "at": [1, 1]},
		{"id": "necromancer", "character": "necromancer", "at": [2, 2]},
		{"id": "practice_raider", "character": "practice_raider", "at": [3, 1]},
		{"id": "fallen_raider", "character": "harpooner", "at": [4, 3], "hp": 0},
	]
	for placement in placements:
		if placement.id == wounded:
			placement.hp = 4
	defs.encounters.test_cast_encounter = {"board": "road", "seed": 2, "placements": placements}
	defs.missions.test_cast_mission = defs.missions.shield_wall.duplicate(true)
	defs.missions.test_cast_mission.encounter = "test_cast_encounter"
	defs.missions.test_cast_mission.erase("default_party")
	return load("res://rules/rules.gd").open_mission(defs, "test_cast_mission")


func _ambiguous_target_after_commit() -> void:
	if not await _press("Restart"):
		return
	var state: Dictionary = scene.battle_snapshot()
	var corpse := _unit(state, "fallen_raider")
	var identities := ["ambiguous_corpse_one", "ambiguous_corpse_two"]
	for id in identities:
		var extra: Dictionary = corpse.duplicate(true)
		extra.id = id
		extra.position = Vector2i(3, 3)
		state.units.append(extra)
	scene.set("_state", state)
	scene.set("_planned_state", state.duplicate(true))
	scene.call("_sync_actors")
	scene.call("_sync_command")
	scene.call("_refresh")
	await process_frame
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await driver.command("necromancer", "raise_dead", "fallen_raider"):
		_check(false, "Single corpse can be staged: " + driver.error)
		return
	var board := _node("BridgeBoard") as Control
	var cell := Vector2i(3, 3)
	await driver._click(board.get_global_transform_with_canvas() * board.cell_center(cell))
	_check(_matches_floating_choices(identities),
		"Clicking the shared tile offers both distinct floating corpse choices")
	await _press_escape()
	_check((scene.get("_storybook_ambiguous") as Array).is_empty(),
		"Escape dismisses the open floating choice")
	_check(scene.get("_planned_state").get("overrides", {}).get("necromancer", {}).get("ability_id") == "raise_dead",
		"Dismissing the choice retains the staged Raise Dead")
	if not await driver.select_actor("necromancer"):
		_check(false, "Necromancer can be reselected after dismissal: " + driver.error)
		return
	await driver._click(board.get_global_transform_with_canvas() * board.cell_center(cell))
	_check(_matches_floating_choices(identities),
		"Legal floating choices can be opened again before committing")
	for id in identities:
		if not await driver.target(id, "raise_dead"):
			_check(false, "Cannot stage the named corpse " + id + ": " + driver.error)
			return
		var drafted: Dictionary = scene.get("_planned_state").overrides.get("necromancer", {})
		_check(drafted.get("ability_id") == "raise_dead" and drafted.get("target_id") == id,
			"Choosing the floating entry stages precisely " + id)
	if not await driver.target("fallen_raider"):
		_check(false, "Can restore the original staged Raise Dead: " + driver.error)
		return
	await driver._click(board.get_global_transform_with_canvas() * board.cell_center(cell))
	_check(_matches_floating_choices(identities), "Both choices remain available before Commit")
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	_check(plan.get("valid", false) and _has_summon(plan, "necromancer_zombie", Vector2i(4, 3), 3),
		"Ambiguous re-aiming retains the previously staged valid Raise Dead")
	if not await _commit_matches(plan):
		return
	_check(_floating_choices().is_empty() and (scene.get("_storybook_ambiguous") as Array).is_empty(),
		"Committing dismisses the previous round's floating choices")


func _floating_choices() -> Dictionary:
	var choices := {}
	var rows: Array = scene.get("_storybook_page").get("_target_rows")
	for row: Dictionary in rows:
		var button := _visible_button(str(row.get("label", "")))
		if button != null:
			choices[str(row.get("id"))] = button
	return choices


func _matches_floating_choices(expected_ids: Array) -> bool:
	var choices := _floating_choices()
	var labels := {}
	for id in expected_ids:
		var composite := "raise_dead::" + str(id)
		if not choices.has(composite):
			return false
		labels[str((choices[composite] as Button).text)] = true
	return labels.size() == expected_ids.size()


func _visible_button(label: String) -> Button:
	return _visible_button_search(scene, label)


func _visible_button_search(node: Node, label: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree():
		if str((node as Button).text) == label or str((node as Button).accessibility_name) == label:
			return node as Button
	for child in node.get_children():
		var found := _visible_button_search(child, label)
		if found != null:
			return found
	return null


func _press_escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		event.echo = false
		scene.get_viewport().push_input(event, true)
		await process_frame


func _command(actor: String, ability: String, target: String) -> bool:
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var ok: bool = await driver.command(actor, ability, target)
	_check(ok, "Book command is available: " + driver.error)
	return ok


func _press(name: String) -> bool:
	var button := _node(name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is visible and enabled")
		return false
	button.pressed.emit()
	await process_frame
	return true


func _commit_matches(plan: Dictionary) -> bool:
	_check(plan.get("valid", false), "Forecast is valid")
	if not await _press("Commit"):
		return false
	_check(scene.battle_snapshot() == plan.get("result"), "Commit matches the complete forecast")
	var ongoing: bool = scene.current_screen() == "battle"
	_check(ongoing, "Practice battle remains active")
	return ongoing


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _has_summon(plan: Dictionary, id: String, position: Vector2i, hp: int) -> bool:
	for event in plan.get("events", []):
		if event.get("type") == "summon" and event.get("summon_id") == id:
			return event.get("position") == position and event.get("hp") == hp
	return false


func _drawn(units: Array, id: String, art_key: String) -> bool:
	for unit in units:
		if unit.get("id") == id and unit.get("art_key") == art_key and unit.get("hp", 0) > 0:
			return true
	return false


func _wave_hits(plan: Dictionary, target: String) -> bool:
	for event in plan.get("events", []):
		if event.get("type") == "damage" and event.get("ability_id") == "wave" \
				and event.get("source_id") == "necromancer_skeleton" and event.get("target_id") == target:
			return true
	return false


func _move_precedes_wave(plan: Dictionary) -> bool:
	var moved := false
	for event in plan.get("events", []):
		if event.get("type") == "move" and event.get("unit_id") == "healer" \
				and event.get("position") == Vector2i(0, 1):
			moved = true
		if event.get("type") == "wave" and event.get("unit_id") == "necromancer_skeleton":
			return moved
	return false


func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: Necromancer practice scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
