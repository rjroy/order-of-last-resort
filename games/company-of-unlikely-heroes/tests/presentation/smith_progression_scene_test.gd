extends "res://tests/support/scene_fixture.gd"

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/smith_progression_scene_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")


func _run() -> void:
	root.size = VIEWPORT_SIZE
	viewport.size = VIEWPORT_SIZE
	root.add_child(viewport)
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	var defs: Dictionary = Catalog.read_default()
	await _release_at_initiative(defs, true)
	await _release_at_initiative(defs, false)
	await _reward_debrief(defs)
	scene.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	_finish()


func _release_opening(defs: Dictionary, smith_first: bool) -> Dictionary:
	var fixture := defs.duplicate(true)
	fixture.characters.release_enemy = fixture.characters.grunt.duplicate(true)
	fixture.characters.release_enemy.behavior = "hold"
	var habits: Dictionary = Catalog.profile(fixture, "healer").habits.duplicate()
	habits.order_hold = "hold"
	fixture.characters.healer.habits = habits
	fixture.characters.healer.default_order = "order_hold"
	fixture.encounters.release_fixture = {"board": "road", "seed": 2,
		"party_slots": [[0, 1], [1, 1], [5, 3]] if smith_first else [[1, 1], [0, 1], [5, 3]],
		"placements": [{"id": "enemy", "character": "release_enemy", "at": [4, 1]}]}
	fixture.missions.release_fixture = fixture.missions.shield_wall.duplicate(true)
	fixture.missions.release_fixture.encounter = "release_fixture"
	fixture.missions.release_fixture.erase("default_party")
	var party := ["blacksmith", "knight", "healer"] if smith_first else ["knight", "blacksmith", "healer"]
	var opening: Dictionary = Rules.open_mission(fixture, "release_fixture", party)
	if opening.is_empty():
		_check(false, "Quick Release fixture opens")
		return {}
	_unit(opening, "blacksmith").upgrades = {"smith_quick_release": 1}
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	await process_frame
	await process_frame
	return opening


func _release_at_initiative(defs: Dictionary, smith_first: bool) -> void:
	var opening := await _release_opening(defs, smith_first)
	if opening.is_empty():
		return
	_check(await driver.select_actor("knight"), "Select actual wearer: " + driver.error)
	if not smith_first:
		_check(not await driver.action("smith_quick_release"),
			"Later Smith cannot offer Quick Release before fitting the Knight")
		var standing: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
		_check(not _unit(opening, "knight").has("fitted_by")
			and _unit(standing.get("result", {}), "knight").get("fitted_by") == "blacksmith",
			"Later Smith fits Knight only after Knight's activation")
		await _press("Commit")
		_check(scene.battle_snapshot() == standing.get("result"),
			"Later Smith commits the forecast fitting")
		opening = scene.battle_snapshot().duplicate(true)
		_check(await driver.select_actor("knight"), "Reselect fitted Knight: " + driver.error)
	else:
		_check(not _unit(opening, "knight").has("fitted_by"),
			"Earlier Smith has not yet mutated the real board")
	if not await driver.action("smith_quick_release"):
		_check(false, "Wearer's pre-activation controls offer Quick Release: " + driver.error)
		return
	var release_board := scene.find_child("BridgeBoard", true, false) as Control
	var marks: Array = (release_board.get("_overlay") as Dictionary).get("targets", [])
	_check(Vector2i(1, 2) in marks, "Quick Release marks an open adjacent destination")
	if not await driver.target("1,2"):
		_check(false, "Choose the Quick Release destination: " + driver.error)
		return
	var planned: Dictionary = scene.get("_planned_state")
	_check(planned.get("overrides", {}).get("knight", {}).get("ability_id") == "smith_quick_release",
		"Quick Release is the wearer's single direct command")
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(plan.get("valid", false) and scene.battle_snapshot() == opening,
		"Quick Release forecast is valid without mutating the actual board")
	_check(_unit(plan.get("result", {}), "knight").get("position") == Vector2i(1, 2)
		and plan.get("events", []).any(func(event: Dictionary):
			return event.get("type") == "fitted_release" and event.get("unit_id") == "knight"),
		"Forecast removes the fitting and moves the wearer")
	_check(_unit(plan.get("result", {}), "knight").get("fitted_by", "")
		== ("" if smith_first else "blacksmith"),
		"Later Smith may fit the Knight again after Quick Release")
	await _press("Commit")
	_check(scene.battle_snapshot() == plan.get("result"),
		"Quick Release commit reproduces the displayed forecast")


func _reward_debrief(defs: Dictionary) -> void:
	var fixture: Dictionary = preload("res://tests/fixtures/controlled_commission.gd").build(defs)
	if not fixture.get("upgrades", {}).has("smith_leather_apron"):
		_check(false, "Stock Leather Apron reward exists")
		return
	for id in fixture.upgrades.keys():
		if fixture.upgrades[id].hero_id == "blacksmith" and id != "smith_leather_apron":
			fixture.upgrades.erase(id)
	fixture.classes.test_commission_enemy.max_hp = 2
	fixture.encounters.test_commission_battle.placements[0].at = [2, 1]
	var errors: PackedStringArray = Catalog.validate(fixture)
	_check(errors.is_empty(), "Scoped reward fixture validates: " + str(errors))
	if not errors.is_empty():
		return
	var profile := {"guild_id": "smith-scene-fixture", "board_seed": 12345, "board_generation": 0,
		"recruited_ids": ["blacksmith", "knight", "healer"], "purchased_ids": [],
		"preferred_loadouts": {}}
	var board: Array = Commissions.board(fixture, 12345)
	var run: Dictionary = Adventure.start_guild_commission(fixture, board[0],
		["blacksmith", "knight", "healer"], profile, {}, 42)
	_check(run.get("phase") == "route", "Scoped Smith commission starts")
	if run.get("phase") != "route":
		return
	run = Adventure.choose_route(run, run.reports[0].mission_id)
	run = Adventure.begin_mission(run)
	_check(run.get("phase") == "mission", "Scoped road deploys")
	if run.get("phase") != "mission":
		return
	scene.set("_definitions", fixture)
	scene.set("_fixed_mission", "")
	scene.set("_run", run)
	scene.call("_show_battle", run.mission)
	await process_frame
	await process_frame
	if not await driver.command("blacksmith", "blacksmith_hammer_time", "fixture_foe"):
		_check(false, "Smith can defeat the controlled road foe: " + driver.error)
		return
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(plan.get("result", {}).get("outcome") == "victory", "Hammer forecasts road victory")
	await _press("Commit")
	_check(scene.current_screen() == "debrief", "Committed victory opens the actual debrief")
	if scene.current_screen() != "debrief":
		return
	run = scene.get("_run")
	_check(run.get("phase") == "reward"
		and {"hero_id": "blacksmith", "upgrade_id": "smith_leather_apron"} in run.get("reward_offers", []),
		"Actual scoped victory draws the stock Smith reward")
	var button := _node("Reward_blacksmith") as BaseButton
	_check(button != null and button.is_visible_in_tree() and not button.disabled,
		"Debrief offers a visible enabled Reward_blacksmith button")
	if button == null or button.disabled or not button.is_visible_in_tree():
		return
	await _press("Reward_blacksmith")
	run = scene.get("_run")
	_check(run.get("chosen_reward", {}) == {"hero_id": "blacksmith", "upgrade_id": "smith_leather_apron"}
		and run.get("upgrades_by_id", {}).get("blacksmith", {}).get("smith_leather_apron") == 1,
		"Pressing the Smith reward button claims the offered stock upgrade")
	await _press("ContinueAdventure")
	_check(scene.current_screen() == "routes", "Claim continues to the next route")
	if scene.current_screen() != "routes":
		return
	await _press("Route_0")
	_check(scene.current_screen() == "battle", "Next route deploys a battle")
	if scene.current_screen() == "battle":
		var smith := _unit(scene.battle_snapshot(), "blacksmith")
		_check(smith.get("upgrades", {}).get("smith_leather_apron") == 1
			and smith.get("max_hp") == int(Catalog.profile(fixture, "blacksmith").max_hp) + 1,
			"Next mission deploys the claimed Leather Apron and its HP")


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}
