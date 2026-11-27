extends "res://tests/support/scene_fixture.gd"

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/smith_command_picker_scene_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const SMITH := "blacksmith"
const KNIGHT := "knight"
const PUSH := "knight_push"
const TARGET := "practice_raider"
const TARGET_CELL := Vector2i(3, 1)


func _run() -> void:
	root.size = VIEWPORT_SIZE
	viewport.size = VIEWPORT_SIZE
	root.add_child(viewport)
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	if not defs.get("characters", {}).has(SMITH):
		_check(false, "Hobby Smith must be available to exercise the command picker")
		_finish()
		return
	await _earlier_smith(defs)
	await _later_smith(defs)
	_finish()


func _opening(defs: Dictionary, smith_first: bool) -> Dictionary:
	var fixture := defs.duplicate(true)
	fixture.characters.practice_raider = fixture.characters.grunt.duplicate(true)
	fixture.characters.practice_raider.behavior = "hold"
	# The third hero and enemy hold still; the fitting and Pull are the only
	# relevant changes on this deliberately open corridor.
	var habits: Dictionary = Catalog.profile(fixture, "healer").habits.duplicate()
	habits["order_hold"] = "hold"
	fixture.characters.healer.habits = habits
	fixture.characters.healer.default_order = "order_hold"
	# Ordinary Push can also target allies. Put the later Smith out of
	# Push range but keep Knight his nearest eligible recipient for Try This.
	var slots := [[0, 1], [1, 1], [5, 3]] if smith_first else [[1, 1], [0, 0], [5, 3]]
	fixture.encounters.smith_picker_fixture = {
		"board": "road", "seed": 2, "party_slots": slots,
		"placements": [{"id": TARGET, "character": TARGET, "at": [3, 1]}],
	}
	fixture.missions.smith_picker_fixture = fixture.missions.shield_wall.duplicate(true)
	fixture.missions.smith_picker_fixture.encounter = "smith_picker_fixture"
	fixture.missions.smith_picker_fixture.erase("default_party")
	var party := [SMITH, KNIGHT, "healer"] if smith_first else [KNIGHT, SMITH, "healer"]
	var opening: Dictionary = Rules.open_mission(fixture, "smith_picker_fixture", party)
	if opening.is_empty():
		_check(false, "Test-owned Smith corridor opens")
		return {}
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	await process_frame
	await process_frame
	_check(scene.battle_snapshot() == opening, "Fixture mounts without changing the opening")
	return opening


func _earlier_smith(defs: Dictionary) -> void:
	var opening := await _opening(defs, true)
	if opening.is_empty():
		return
	if not await driver.select_actor(KNIGHT):
		_check(false, "Select Knight after earlier Smith: " + driver.error)
		return
	var push := _push_button()
	_check(push != null and not push.disabled and "Push → Pull" in push.text,
		"Earlier Smith enables the actual Push → Pull ability button")
	if not await driver.action(PUSH):
		_check(false, "Knight can aim the converted Pull: " + driver.error)
		return
	_check(scene.get("_aimed_ability_id") == PUSH and TARGET_CELL in _marked_cells(),
		"Aiming the converted ability marks the distance-two Pull target beyond ordinary Push")
	_check(scene.battle_snapshot() == opening and scene.get("_planned_state").overrides.is_empty(),
		"Selecting and aiming do not apply the fitting, stage an action, or mutate battle state")
	if not await driver.target(TARGET):
		_check(false, "Knight can stage the ranged Pull target: " + driver.error)
		return
	var planned: Dictionary = scene.get("_planned_state")
	var overrides: Dictionary = planned.get("overrides", {})
	_check(overrides.size() == 1 and overrides.has(KNIGHT), "Pull uses the company's one command, leaving Smith on standing Try This")
	var draft: Dictionary = overrides.get(KNIGHT, {})
	_check(draft.get("ability_id") == PUSH and draft.get("target_id") == TARGET,
		"The staged Pull retains the Push slot and the exact chosen raider")
	var forecast: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(forecast.get("valid", false), "Pull produces a valid forecast")
	_check(_unit(forecast.get("result", {}), TARGET).get("position") == Vector2i(2, 1),
		"Forecast pulls the raider one tile towards Knight")
	_check(scene.battle_snapshot() == opening, "Forecast leaves all actual state, including fitting and RNG, unchanged")
	if not await driver.clear():
		_check(false, "Pull command can be cleared: " + driver.error)
		return
	_check(scene.battle_snapshot() == opening and (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Clearing the command restores the same unmodified opening")
	if not await driver.select_actor(KNIGHT) or not await driver.action(PUSH) or not await driver.target(TARGET):
		_check(false, "Pull can be staged again after clearing: " + driver.error)
		return
	_check(scene.get("_plan") == forecast, "Restaging forecasts the same round without preview mutation")
	await _press("Commit")
	_check(scene.battle_snapshot() == forecast.get("result"), "Commit replays the displayed Pull forecast exactly")


func _later_smith(defs: Dictionary) -> void:
	var opening := await _opening(defs, false)
	if opening.is_empty():
		return
	if not await driver.select_actor(KNIGHT):
		_check(false, "Select earlier Knight: " + driver.error)
		return
	var push := _push_button()
	var later_label := push.text if push != null else ""
	_check(later_label.begins_with("Push") and not later_label.contains("Pull")
		and not later_label.contains("→"),
		"Later Smith leaves the current command labeled ordinary Push: " + later_label)
	_check(push != null and push.disabled, "Ordinary Push is visibly disabled with no legal adjacent target")
	if push != null:
		await driver._click(push.get_global_rect().get_center())
	_check(scene.get("_aimed_ability_id") == "" and TARGET_CELL not in _marked_cells(),
		"Pressing disabled Push cannot aim at the distant raider before the later fitting")
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"An out-of-reach Pull leaves no direct command staged")
	var forecast: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(_unit(forecast.get("result", {}), TARGET).get("position") == Vector2i(3, 1),
		"Later standing Try This does not retroactively pull during Knight's turn")
	_check(forecast.get("events", []).any(func(event: Dictionary) -> bool:
		return event.get("type") == "fit" and event.get("unit_id") == SMITH and event.get("target_id") == KNIGHT),
		"Later Smith still fits Knight from outside ordinary Push range")
	_check(scene.battle_snapshot() == opening, "Later-Smith forecast does not mutate the opening")
	await _press("Commit")
	_check(scene.battle_snapshot() == forecast.get("result"), "Later-Smith commit matches its forecast")
	if not await driver.select_actor(KNIGHT):
		_check(false, "Later fitting makes Pull available on Knight's next activation: " + driver.error)
		return
	if not await driver.action(PUSH):
		_check(false, "Next-round fitting enables the converted ability: " + driver.error)
		return
	_check(scene.get("_aimed_ability_id") == PUSH and TARGET_CELL in _marked_cells(),
		"Aiming the fitted ability next round marks the ranged Pull target")


func _push_button() -> Button:
	var button := scene.find_child("DirectOrder_" + PUSH, true, false) as Button
	if button == null or not button.is_visible_in_tree() or str(button.get_meta("ability_id", "")) != PUSH:
		return null
	return button


func _marked_cells() -> Array:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		return []
	return (board.get("_overlay") as Dictionary).get("targets", [])


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}
