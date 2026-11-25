extends "res://tests/support/scene_fixture.gd"

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/smith_summon_overlay_scene_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const SUMMON_AT := Vector2i(2, 1)
const LANDING := Vector2i(1, 1)


func _run() -> void:
	root.size = VIEWPORT_SIZE
	viewport.size = VIEWPORT_SIZE
	root.add_child(viewport)
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	defs.characters.overlay_raider = defs.characters.grunt.duplicate(true)
	defs.characters.overlay_raider.behavior = "hold"
	defs.encounters.smith_summon_overlay = {
		"board": "road", "seed": 7,
		"party_slots": [[2, 2], [4, 1], [3, 1]],
		"placements": [{"id": "overlay_raider", "character": "overlay_raider", "at": [6, 3]}],
	}
	defs.missions.smith_summon_overlay = defs.missions.shield_wall.duplicate(true)
	defs.missions.smith_summon_overlay.encounter = "smith_summon_overlay"
	defs.missions.smith_summon_overlay.erase("default_party")
	var opening: Dictionary = Rules.open_mission(defs, "smith_summon_overlay",
		["necromancer", "blacksmith", "knight"])
	if opening.is_empty():
		_check(false, "Test-owned summon, Smith and Knight battle opens")
		_finish()
		return
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	await process_frame
	await process_frame
	if not await driver.command("necromancer", "summon_skeleton", "2,1"):
		_check(false, "Summon is staged through the real controls: " + driver.error)
		_finish()
		return
	_check(scene.battle_snapshot() == opening, "Staging and forecasting leave the opening unchanged")
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(plan.get("valid", false), "Ordered round has a valid forecast")
	var summons: Array = plan.get("result", {}).get("units", []).filter(
		func(unit: Dictionary): return unit.get("character_id") == "skeleton")
	if summons.size() != 1:
		_check(false, "Forecast contains exactly one newly summoned skeleton")
		_finish()
		return
	var skeleton: Dictionary = summons[0]
	_check(not opening.units.any(func(unit: Dictionary): return unit.id == skeleton.id),
		"Skeleton does not exist on the opening board")
	var events: Array = plan.get("events", [])
	var fits := events.filter(func(event: Dictionary):
		return event.get("type") == "fit" and event.get("unit_id") == "blacksmith" \
			and event.get("target_id") == "knight")
	var shoves := events.filter(func(event: Dictionary):
		return event.get("type") == "push" and event.get("unit_id") == "knight" \
			and event.get("target_id") == skeleton.id and event.get("from_position") == SUMMON_AT \
			and event.get("position") == LANDING)
	_check(fits.size() == 1 and shoves.size() == 1 and events.find(fits[0]) < events.find(shoves[0]),
		"Standing Smith fits Knight before standing Guard shoves the new skeleton")
	_check(skeleton.position == LANDING, "Forecast places the skeleton at the shove landing")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	_check(board != null and board.is_visible_in_tree(), "Forecast board is visible")
	if board != null:
		var paths: Array = (board.get("_overlay") as Dictionary).get("paths", [])
		_check([SUMMON_AT, LANDING] in paths,
			"Board forecast draws the new skeleton's actual shove origin and landing")
	await _press("Commit")
	var committed: Dictionary = scene.battle_snapshot()
	_check(committed == plan.get("result"), "Commit equals the displayed forecast")
	var committed_skeletons: Array = committed.get("units", []).filter(
		func(unit: Dictionary): return unit.get("id") == skeleton.id)
	_check(committed_skeletons.size() == 1 and committed_skeletons[0].position == LANDING,
		"Committed skeleton lands at the forecast destination")
	_finish()
