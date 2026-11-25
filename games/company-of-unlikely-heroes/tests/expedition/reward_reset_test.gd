extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/expedition/reward_reset_test.gd
# Controlled commission missions and three single-entry pools isolate reset from live tuning.
var catalog: Script = load("res://content/catalog.gd")
var adventure: Script = load("res://expedition/adventure.gd")
var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []
const PARTY := ["bard", "necromancer", "knight"]


func _initialize() -> void:
	var defs: Dictionary = catalog.read_default().duplicate(true)
	if defs.is_empty():
		_check(false, "Default catalog loads for the controlled reset fixture")
	else:
		_test_reset(defs, "victory")
		_test_reset(defs, "defeat")
	if failures.is_empty():
		print("PASS: claimed reward resets after victory and defeat")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _ids(options: Array) -> Array:
	return options.map(func(option: Dictionary) -> Variant: return option.get("id"))


func _fixture(source: Dictionary) -> Dictionary:
	var defs := source.duplicate(true)
	for hero in PARTY:
		defs.characters[hero]["max_hp"] = 20
	defs.characters.skeleton["max_hp"] = 3
	defs.characters.bard["default_order"] = "order_hold"
	defs.upgrades = {
		"reset_lights": {"hero_id": "bard", "label": "Fixture lights", "description": "Gain the stage.",
			"rarity": "legendary", "cap": 1, "effect": "house_lights", "amount": 1,
			"ability": "bard_take_the_stage", "order": "order_take_the_stage", "behavior": "take_the_stage"},
		"reset_ribs": {"hero_id": "necromancer", "label": "Fixture ribs", "description": "Skeleton HP.",
			"rarity": "common", "cap": 1, "effect": "spare_ribs", "amount": 2},
		"reset_hp": {"hero_id": "knight", "label": "Fixture HP", "description": "Maximum HP.",
			"rarity": "common", "cap": 1, "effect": "max_hp", "amount": 4},
	}
	# Preserve authored stage behavior without tying test pool values to its reward record.
	var authored: Dictionary = source.get("upgrades", {}).get("bard_house_lights", {})
	if authored.has("behavior"):
		defs.upgrades.reset_lights.behavior = authored.behavior
	# Every report deploys the same controlled defeat-all encounter.
	for id in defs.mission_reports:
		defs.missions[id] = source.missions.goblin_mob.duplicate(true)
	return defs


func _start(defs: Dictionary) -> Dictionary:
	var board: Array = preload("res://expedition/commissions.gd").board(defs, 919)
	return adventure.call("start_commission", defs, board[0], PARTY, 919)


func _deploy(run: Dictionary) -> Dictionary:
	if run.get("phase") == "route":
		run = adventure.call("choose_route", run, run.reports[0].mission_id)
	return adventure.call("begin_mission", run)


func _commit_terminal(run: Dictionary, outcome: String) -> Dictionary:
	var state: Dictionary = run.get("mission", {}).duplicate(true)
	if state.is_empty():
		_check(false, outcome + ": deployed board exists")
		return {}
	for unit in state.units:
		if outcome == "victory" and rules.entity_profile(state, unit.id).get("team") == "enemies":
			unit.hp = 0
		elif outcome == "defeat" and unit.id in PARTY:
			unit.hp = 0
	var plan: Dictionary = rules.preview_round(state)
	var terminal: Dictionary = rules.commit_round(state, plan)
	_check(terminal.get("outcome") == outcome, "Controlled round commits " + outcome)
	return adventure.call("settle_mission", run, terminal)


func _test_reset(source: Dictionary, outcome: String) -> void:
	var defs := _fixture(source)
	var untouched := defs.duplicate(true)
	var errors: PackedStringArray = catalog.validate(defs)
	_check(errors.is_empty(), outcome + ": test-owned catalog validates: " + str(errors))
	if not errors.is_empty():
		return
	var run := _start(defs)
	for claim in [["bard", "reset_lights"], ["necromancer", "reset_ribs"], ["knight", "reset_hp"]]:
		run = _deploy(run)
		run = _commit_terminal(run, "victory")
		var offer := {"hero_id": claim[0], "upgrade_id": claim[1]}
		_check(offer in run.get("reward_offers", []), outcome + ": real victory offers " + str(offer))
		if offer not in run.get("reward_offers", []):
			return
		run = adventure.call("choose_reward", run, claim[0], claim[1])
		_check(run.get("upgrades_by_id", {}).get(claim[0], {}).get(claim[1]) == 1,
			outcome + ": real choice grants " + claim[1])
	run = _deploy(run)
	var active: Dictionary = run.get("mission", {})
	if active.is_empty():
		_check(false, outcome + ": upgraded final mission deploys")
		return
	var knight_base := int(catalog.profile(defs, "knight").max_hp)
	_check(_entity(active, "knight").get("max_hp") == knight_base + 4,
		outcome + ": HP reward is active before reset")
	_check("bard_take_the_stage" in _ids(rules.options(active, "bard"))
		and "order_take_the_stage" in _ids(rules.options(active, "bard")),
		outcome + ": House Lights grants ability and order before reset")
	_check_skeleton(active, int(catalog.profile(defs, "skeleton").max_hp) + 2, outcome + " upgraded")
	var changed: Dictionary = rules.set_order(active, "bard", "order_take_the_stage")
	_check(changed.get("orders", {}).get("bard") == "order_take_the_stage",
		outcome + ": upgraded standing order is selectable")
	run.mission = changed
	var finished := _commit_terminal(run, outcome)
	if outcome == "victory" and finished.get("phase") == "ready":
		finished = _commit_terminal(_deploy(finished), "victory")
	_check(finished.get("phase") == "finished", outcome + ": commission ends")
	_check(defs == untouched, outcome + ": commission does not mutate external catalog")
	var fresh := _start(defs)
	_check(fresh.get("upgrades_by_id", {}).is_empty() and fresh.get("reward_offers", []).is_empty(),
		outcome + ": new commission starts without counts or offers")
	fresh = _deploy(fresh)
	var board: Dictionary = fresh.get("mission", {})
	if board.is_empty():
		_check(false, outcome + ": fresh outing deploys")
		return
	for hero in PARTY:
		var unit := _entity(board, hero)
		var base := int(catalog.profile(defs, hero).max_hp)
		_check(unit.get("hp") == base and unit.get("max_hp") == base and unit.get("upgrades", {}).is_empty(),
			outcome + ": " + hero + " deploys at base HP with no upgrades")
	_check("bard_take_the_stage" not in _ids(rules.options(board, "bard"))
		and "order_take_the_stage" not in _ids(rules.options(board, "bard"))
		and board.orders.get("bard") == "order_hold",
		outcome + ": Bard loses stage action and order and returns to Hold")
	_check_skeleton(board, int(catalog.profile(defs, "skeleton").max_hp), outcome + " fresh")
	var first := _commit_terminal(fresh, "victory")
	_check(first.get("reward_offers", []).size() == 3,
		outcome + ": previously exhausted entries are eligible again")


func _check_skeleton(state: Dictionary, expected: int, label: String) -> void:
	var targets: Array = rules.targets(state, "necromancer", "summon_skeleton")
	_check(not targets.is_empty(), label + ": skeleton summon has a legal target")
	if targets.is_empty():
		return
	var plan: Dictionary = rules.preview(state, "necromancer", "summon_skeleton", str(targets[0].id))
	_check(plan.get("valid", false), label + ": skeleton summon is legal")
	if not plan.get("valid", false):
		return
	var result: Dictionary = rules.apply_plan(state, plan)
	var skeletons: Array = result.units.filter(func(unit: Dictionary) -> bool:
		return unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0)
	_check(skeletons.size() == 1 and skeletons[0].get("hp") == expected
		and skeletons[0].get("max_hp") == expected, label + ": skeleton starts at expected HP")
