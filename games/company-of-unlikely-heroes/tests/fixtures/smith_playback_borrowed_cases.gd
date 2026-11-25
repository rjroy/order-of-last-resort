extends RefCounted
## Real purchased kits, using the same guild APIs and formations as
## smith_borrowed_guild_conversions_test.gd. No donor character is modified.

const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")
const Rules = preload("res://rules/rules.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")

# Hero, petition, source ability, prerequisites, target, effective ability.
const ROWS := [
	["knight", "knight_learn_bonk", "healer_bonk", [], "ally", "keep_your_head_down"],
	["healer", "teach_healer_blast", "wizard_blast", [], "", "mending_blast"],
	["wizard", "wizard_learn_dodge", "rogue_confusing_dodge", ["recruit_rogue"], "", "clear_jump"],
	["bard", "bard_learn_push", "knight_push", ["recruit_bard"], "enemy", "fitted_pull"],
	["rogue", "rogue_learn_potion", "alchemist_potion", ["recruit_rogue", "recruit_alchemist"], "enemy", "bitter_medicine"],
	["necromancer", "necro_learn_melody", "inspiring_melody", ["recruit_necromancer", "recruit_bard"], "", "inspiring_melody_in_tune"],
	["alchemist", "alchemist_learn_pull", "wizard_pull", ["recruit_alchemist"], "enemy", "send_off"],
]


static func cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in ROWS:
		result.append(_case(row))
	return result


static func _case(row: Array) -> Dictionary:
	var hero: String = row[0]
	var id := "borrowed_%s_%s" % [hero, row[2]]
	var result := {"id": id, "state": {}, "actor": hero, "ability": row[2],
		"target": "", "effective": row[5]}
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	var profile := {"guild_id": "borrowed-playback-test", "board_seed": 147258, "board_generation": 0,
		"points": 1000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": ["knight", "healer", "wizard"]}
	for petition in ["recruit_blacksmith"] + row[3] + [row[1]]:
		profile = Progression.purchased_profile(defs, profile, petition)
		if profile.has("error"):
			result["error"] = "purchase %s: %s" % [petition, profile]
			return result
	var loadout := Progression.default_loadout(defs, profile, hero)
	var grant: Dictionary = defs.guild_progression.petitions[row[1]].grant
	if loadout.is_empty() or grant.get("ability_id") != row[2]:
		result["error"] = "purchase does not grant expected ability"
		return result
	loadout.slots[grant.slot_id] = row[2]
	var compatible := false
	for option in Progression.order_options(defs, profile, hero, loadout):
		if option.compatible:
			loadout.order_id = option.id
			compatible = true
			break
	if not compatible:
		result["error"] = "no compatible standing order"
		return result
	var board := Commissions.board(defs, profile.board_seed)
	var ally := "healer" if hero == "knight" else "knight"
	var run := Adventure.start_guild_commission(defs, board[0], ["blacksmith", hero, ally],
		profile, {hero: loadout}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		result["error"] = "guild commission did not start"
		return result
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		result["error"] = "guild mission did not start"
		return result
	var rules := Rules.new()
	if row[2] not in rules.entity_profile(state, hero).get("abilities", []):
		result["error"] = "purchased ability is not equipped"
		return result
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	var enemy := ""
	for unit: Dictionary in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			if enemy.is_empty():
				enemy = unit.id
			else:
				unit.hp = 0
	if enemy.is_empty():
		result["error"] = "guild mission has no enemy"
		return result
	for unit_id in ["blacksmith", hero, ally, enemy]:
		_unit(state, unit_id).hp = 20
		_unit(state, unit_id).max_hp = 20
	_unit(state, "blacksmith").position = Vector2i(4, 3)
	_unit(state, hero).position = Vector2i(4, 4)
	_unit(state, ally).position = Vector2i(5, 4)
	_unit(state, ally).hp = 10
	_unit(state, enemy).position = Vector2i(7, 4)
	state.orders.blacksmith = "order_try_this"
	for seed_value in range(1, 10000):
		if Reactions.draw(seed_value, true).category == "cosmetic":
			state.dose_seed = seed_value
			break
	if hero == "wizard":
		_unit(state, ally).position = Vector2i(10, 10)
	if hero == "rogue":
		_unit(state, ally).position = Vector2i(9, 9)
		_unit(state, enemy).position = Vector2i(5, 4)
	result.target = ally if row[4] == "ally" else (enemy if row[4] == "enemy" else "")
	result.state = state
	return result


static func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}
