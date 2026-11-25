extends SceneTree

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_guild_progression_test.gd
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild_progression.gd")
const Profile = preload("res://guild_profile.gd")
const Rules = preload("res://rules.gd")
const Adventure = preload("res://adventure.gd")
const Commissions = preload("res://commissions.gd")
const FOUNDERS := ["knight", "healer", "wizard"]
const OLD_ROSTER := ["knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard"]

var failures: Array[String] = []
var paths: Array[String] = []
var defs: Dictionary


func _initialize() -> void:
	defs = Catalog.read_default()
	_test_saves()
	_test_progression()
	for path in paths:
		for file in [path, path + ".backup"]:
			if FileAccess.file_exists(file):
				_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK,
					"Remove isolated fixture " + file)
	if failures.is_empty():
		print("PASS: Smith guild progression")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _path() -> String:
	var path := "user://smith_guild_%d_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec(), paths.size()]
	paths.append(path)
	return path


func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Write isolated save fixture")
		return
	file.store_string(JSON.stringify(value))
	file.close()


func _stored(version: int, points := 0) -> Dictionary:
	if version == 1:
		return {"version": 1, "name": "Smith test", "board_seed": "123"}
	return {"version": version, "name": "Smith test", "board_seed": "123",
		"guild_id": "a".repeat(64), "points": str(points), "board_generation": "0",
		"recruited_ids": OLD_ROSTER.duplicate(), "purchased_ids": [],
		"preferred_loadouts": {}, "last_receipt": {}}


func _test_saves() -> void:
	var fresh_path := _path()
	var fresh: Dictionary = Profile.create(fresh_path, "Smith test", 123)
	_check(not fresh.has("error") and Profile.load_profile(fresh_path) == fresh,
		"Fresh guild round-trips")
	_check("blacksmith" not in fresh.get("recruited_ids", []), "Fresh guild does not own Smith")
	for version in [1, 2, 3]:
		var path := _path()
		_write(path, _stored(version))
		var loaded: Dictionary = Profile.load_profile(path)
		_check(not loaded.has("error") and not loaded.is_empty(), "Pre-Smith v%d save loads: %s" % [version, loaded])
		if loaded.has("error") or loaded.is_empty():
			continue
		for hero in OLD_ROSTER:
			_check(hero in loaded.get("recruited_ids", []), "v%d retains %s" % [version, hero])
		_check("blacksmith" not in loaded.get("recruited_ids", []), "v%d does not invent Smith ownership" % version)
		var renewed: Dictionary = Profile.renew(path, loaded, 456)
		_check(not renewed.has("error") and Profile.load_profile(path) == renewed,
			"Pre-Smith v%d save remains writable" % version)


func _petition(kind: String, ability := "") -> String:
	var matches: Array[String] = []
	for id in defs.get("guild_progression", {}).get("petitions", {}):
		var grant: Dictionary = defs.guild_progression.petitions[id].get("grant", {})
		if grant.get("hero_id") == "blacksmith" and grant.get("kind") == kind \
				and (ability.is_empty() or grant.get("ability_id") == ability):
			matches.append(id)
	_check(matches.size() == 1, "Exactly one Smith %s petition for %s, got %s" % [kind, ability, matches])
	return matches[0] if matches.size() == 1 else ""


func _row(profile: Dictionary, id: String) -> Dictionary:
	for row in Profile.petitions(defs, profile):
		if row.id == id:
			return row
	return {}


func _test_progression() -> void:
	var recruit := _petition("recruit")
	var bonk := _petition("ability", "healer_bonk")
	var acid := _petition("ability", "alchemist_acid")
	if recruit.is_empty() or bonk.is_empty() or acid.is_empty():
		return
	var profile := {"points": 20, "recruited_ids": FOUNDERS.duplicate(),
		"purchased_ids": [], "preferred_loadouts": {}}
	_check(_row(profile, recruit).get("cost") == 5, "Smith recruitment costs 5")
	_check(_row(profile, bonk).get("cost") == 4, "Smith Bonk costs 4")
	_check(_row(profile, acid).get("cost") == 5, "Smith Acid costs 5")
	_check(not _row(profile, bonk).get("can_buy", false), "Bonk requires Smith")
	_check(not _row(profile, acid).get("can_buy", false), "Acid requires Smith and Mixologist")
	var only_smith := profile.duplicate(true)
	only_smith.recruited_ids.append("blacksmith")
	_check(not _row(only_smith, acid).get("can_buy", false), "Acid requires Mixologist even with Smith")
	var only_alchemist := profile.duplicate(true)
	only_alchemist.recruited_ids.append("alchemist")
	_check(not _row(only_alchemist, acid).get("can_buy", false), "Acid requires Smith even with Mixologist")
	var legacy := only_smith.duplicate(true)
	legacy.recruited_ids.append("alchemist")
	_check(_row(legacy, recruit).get("owned", false) and not _row(legacy, recruit).get("can_buy", true),
		"Roster ownership without a purchase receipt prevents buying Smith twice")
	_check(_row(legacy, acid).get("can_buy", false), "Both roster-owned recruits satisfy Acid prerequisites without receipts")
	var poor := profile.duplicate(true)
	poor.points = 4
	_check(not _row(poor, recruit).get("can_buy", false), "Four points cannot recruit Smith")
	var exact := profile.duplicate(true)
	exact.points = 5
	var recruited: Dictionary = Progression.purchased_profile(defs, exact, recruit)
	_check(not recruited.has("error") and recruited.get("points") == 0 \
		and "blacksmith" in Profile.roster(defs, recruited), "Five points recruit Smith into actual guild roster")

	# A pre-existing test-owned save has points and the older roster. Purchases
	# and preferences then go through the same locked disk API as the guild UI.
	var path := _path()
	_write(path, _stored(3, 30))
	var disk: Dictionary = Profile.load_profile(path)
	disk = Profile.purchase(path, disk, defs, recruit)
	if disk.has("error"):
		_check(false, "Recruit Smith through profile API: " + str(disk))
		return
	var native: Dictionary = Profile.default_loadout(defs, disk, "blacksmith")
	_check(native.get("slots", {}).get("offense") == "blacksmith_hammer_time" \
		and native.get("slots", {}).get("utility") == "blacksmith_try_this" \
		and native.get("order_id") == "order_try_this", "Recruited Smith has native kit and standing Try This")
	if not native.is_empty():
		_test_pursue(disk, native, "blacksmith_try_this")
		var hammer := native.duplicate(true)
		hammer.order_id = "order_pursue"
		_test_pursue(disk, hammer, "blacksmith_hammer_time")
	for entry in [[bonk, "healer_bonk", 4], [acid, "alchemist_acid", 5]]:
		var previous: int = disk.points
		disk = Profile.purchase(path, disk, defs, entry[0])
		if disk.has("error"):
			_check(false, "Purchase " + entry[0] + ": " + str(disk))
			return
		_check(disk.points == previous - entry[2], entry[0] + " charges exactly once")
		_check(Profile.default_loadout(defs, disk, "blacksmith") == native,
			entry[0] + " does not silently equip the learned offense")
		_check(entry[1] in Profile.slot_options(defs, disk, "blacksmith").get("offense", []),
			entry[0] + " appears in Smith offense choices")
		var selected := native.duplicate(true)
		if selected.is_empty():
			continue
		selected.slots.offense = entry[1]
		selected.order_id = "order_pursue"
		var kit: Dictionary = Progression.effective_kit(defs, disk, "blacksmith", selected)
		_check(not kit.is_empty(), entry[0] + " supports Pursue with the equipped offense")
		for donor_order in ["order_aggressive", "order_throw_samples", "order_support", "order_make_rounds"]:
			_check(not kit.get("habits", {}).has(donor_order), entry[0] + " does not grant donor order " + donor_order)
		var saved: Dictionary = Profile.save_loadouts(path, disk, defs, {"blacksmith": selected})
		_check(not saved.has("error"), entry[0] + " explicit selection saves: " + str(saved))
		if saved.has("error"):
			continue
		disk = Profile.load_profile(path)
		_check(Profile.default_loadout(defs, disk, "blacksmith") == selected,
			entry[0] + " explicit selection survives reload")
		_test_pursue(disk, selected, entry[1])
		# Reset explicitly before checking the next purchase does not auto-equip.
		disk = Profile.save_loadouts(path, disk, defs, {"blacksmith": native})


func _test_pursue(profile: Dictionary, selection: Dictionary, ability: String) -> void:
	var board: Array = Commissions.board(defs, 123)
	if board.is_empty():
		_check(false, ability + " commission board exists")
		return
	var run: Dictionary = Adventure.start_guild_commission(defs, board[0],
		["blacksmith", "knight", "healer"], profile, {"blacksmith": selection}, 444)
	if run.get("phase") != "route":
		_check(false, ability + " guild company starts")
		return
	run = Adventure.choose_route(run, run.reports[0].mission_id)
	var deployed: Dictionary = Adventure.begin_mission(run)
	var state: Dictionary = deployed.get("mission", {})
	if state.is_empty():
		_check(false, ability + " guild company deploys")
		return
	var rules := Rules.new()
	var smith := _unit(state, "blacksmith")
	var enemy := {}
	for unit in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			if enemy.is_empty():
				enemy = unit
			else:
				unit.hp = 0
	if smith.is_empty() or enemy.is_empty():
		_check(false, ability + " deployed fixture has Smith and enemy")
		return
	state.obstacles = []
	for unit in state.units:
		if unit.id == "knight":
			unit.position = Vector2i(0, 1)
		elif unit.id == "healer":
			unit.position = Vector2i(0, 2)
	state.orders.knight = "order_hold"
	state.orders.healer = "order_hold"
	smith.position = Vector2i(1, 1)
	enemy.position = Vector2i(3, 1)
	var before_hp: int = enemy.hp
	var plan: Dictionary = rules.preview_round(state)
	var result: Dictionary = plan.get("result", {})
	var after_smith := _unit(result, "blacksmith")
	var after_enemy := _unit(result, enemy.id)
	_check(plan.get("valid", false) and not after_smith.is_empty() and not after_enemy.is_empty(),
		ability + " Pursue forecast resolves")
	if after_smith.is_empty() or after_enemy.is_empty():
		return
	if ability == "blacksmith_try_this":
		_check(after_smith.position == Vector2i(1, 1) and after_enemy.hp == before_hp \
			and _unit(result, "knight").get("fitted_by") == "blacksmith",
			"Default Try This fits the nearest hero without pursuing or attacking")
	elif ability == "alchemist_acid":
		_check(after_smith.position == Vector2i(1, 1) and after_enemy.hp < before_hp,
			"Acid Pursue attacks at range two without stepping")
	else:
		_check(after_smith.position == Vector2i(2, 1) and after_enemy.hp == before_hp,
			ability + " Pursue steps once into reach without attacking that activation")
	_check(rules.commit_round(state, plan) == result, ability + " Pursue commit matches forecast")


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}
