extends SceneTree

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_borrowed_guild_conversions_test.gd
## Purchases and deployment use the stock guild APIs; no character learns an
## ability through a modified character definition.
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild_progression.gd")
const Adventure = preload("res://adventure.gd")
const Commissions = preload("res://commissions.gd")
const Rules = preload("res://rules.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")

# Hero, petition, ability, donor order, prerequisites, target.
const CASES := [
	["knight", "knight_learn_bonk", "healer_bonk", "order_aggressive", [], "ally"],
	["healer", "teach_healer_blast", "wizard_blast", "order_blast", [], ""],
	["wizard", "wizard_learn_dodge", "rogue_confusing_dodge", "order_retreat", ["recruit_rogue"], ""],
	["bard", "bard_learn_push", "knight_push", "order_advance", ["recruit_bard"], "enemy"],
	["rogue", "rogue_learn_potion", "alchemist_potion", "order_make_rounds", ["recruit_rogue", "recruit_alchemist"], "enemy"],
	["necromancer", "necro_learn_melody", "inspiring_melody", "order_inspiring_melody", ["recruit_necromancer", "recruit_bard"], ""],
	["alchemist", "alchemist_learn_pull", "wizard_pull", "order_blast", ["recruit_alchemist"], "enemy"],
]

var defs: Dictionary
var rules := Rules.new()
var failures: Array[String] = []


func _initialize() -> void:
	defs = Catalog.read_default().duplicate(true)
	for example in CASES:
		_exercise(example)
	if failures.is_empty():
		print("PASS: Smith borrowed guild conversions")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _exercise(example: Array) -> void:
	var hero: String = example[0]
	var petition: String = example[1]
	var ability: String = example[2]
	var label := hero + " / " + ability
	var profile := {"guild_id": "borrowed-guild-test", "board_seed": 147258, "board_generation": 0,
		"points": 1000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": ["knight", "healer", "wizard"]}
	for id in ["recruit_blacksmith"] + example[4] + [petition]:
		profile = Progression.purchased_profile(defs, profile, id)
		if profile.has("error"):
			_check(false, label + ": purchase " + id + " failed: " + str(profile))
			return
	_check(petition in profile.purchased_ids, label + ": actual petition is owned")
	var loadout := Progression.default_loadout(defs, profile, hero)
	var grant: Dictionary = defs.guild_progression.petitions[petition].grant
	if loadout.is_empty() or grant.get("ability_id") != ability:
		_check(false, label + ": purchased grant resolves to the expected slot ability")
		return
	loadout.slots[grant.slot_id] = ability
	var equipped := false
	for row in Progression.order_options(defs, profile, hero, loadout):
		if row.compatible:
			loadout.order_id = row.id
			equipped = true
			break
	if not equipped:
		_check(false, label + ": equipped ability has a compatible standing order")
		return
	var board := Commissions.board(defs, profile.board_seed)
	if board.is_empty():
		_check(false, label + ": stock commission board exists")
		return
	var ally := "healer" if hero == "knight" else "knight"
	var run := Adventure.start_guild_commission(defs, board[0], ["blacksmith", hero, ally],
		profile, {hero: loadout}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, label + ": purchased guild company starts")
		return
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		_check(false, label + ": guild company deploys")
		return
	var kit: Dictionary = rules.entity_profile(state, hero)
	_check(ability in kit.get("abilities", []), label + ": deployed actor owns equipped source ability")
	_check(not kit.get("habits", {}).has(example[3]), label + ": donor standing order is not granted")
	_check(_unit(state, hero).get("upgrades", {}).is_empty(), label + ": no donor outing upgrades are granted")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	var enemy := ""
	for unit: Dictionary in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			if enemy.is_empty():
				enemy = unit.id
			else:
				unit.hp = 0
	if enemy.is_empty():
		_check(false, label + ": stock mission has an opponent")
		return
	for id in ["blacksmith", hero, ally, enemy]:
		_unit(state, id).hp = 20
		_unit(state, id).max_hp = 20
	_unit(state, "blacksmith").position = Vector2i(4, 3)
	_unit(state, hero).position = Vector2i(4, 4)
	_unit(state, ally).position = Vector2i(5, 4)
	_unit(state, ally).hp = 10
	_unit(state, enemy).position = Vector2i(7, 4)
	state.orders.blacksmith = "order_try_this"
	state.dose_seed = _cosmetic_seed()
	if hero == "wizard":
		_unit(state, ally).position = Vector2i(10, 10)
	if hero == "rogue":
		_unit(state, ally).position = Vector2i(9, 9)
		_unit(state, enemy).position = Vector2i(5, 4)
	var target: String = ally if example[5] == "ally" else (enemy if example[5] == "enemy" else "")
	var original := state.duplicate(true)
	var before: Dictionary = rules.state_before_action(state, hero)
	_check(state == original and _unit(before, hero).get("fitted_by") == "blacksmith",
		label + ": earlier Smith standing order fits the deployed actor without mutating source")
	var plan: Dictionary = rules.preview(before, hero, ability, target)
	_check(plan == rules.preview(before, hero, ability, target), label + ": action preview is deterministic")
	_check(plan.get("valid", false), label + ": converted action is legal")
	if plan.get("valid", false):
		var result: Dictionary = rules.apply_plan(before, plan)
		_check(result == plan.get("result"), label + ": action commit matches preview")
		_check(plan.events.any(func(event): return event.get("type") == "fitted_conversion" \
			and event.get("unit_id") == hero and event.get("source_id") == "blacksmith" \
			and event.get("source_ability_id") == ability), label + ": conversion identifies performer, Smith and source ability")
		_check(not _unit(result, hero).has("fitted_by"), label + ": alternate consumes fitting")
		_check_outcome(example, result, hero, ally, enemy)
	var staged: Dictionary = rules.choose_manual(state, hero, ability, target)
	var round_plan: Dictionary = rules.preview_round(staged)
	_check(round_plan == rules.preview_round(staged) and state == original,
		label + ": full round forecast is deterministic and does not mutate source")
	_check(round_plan.get("valid", false), label + ": full round forecast is valid")
	if round_plan.get("valid", false):
		_check(round_plan.events.any(func(event): return event.get("type") == "fitted_conversion" \
			and event.get("unit_id") == hero and event.get("source_id") == "blacksmith" \
			and event.get("source_ability_id") == ability), label + ": full round performs the same sourced conversion")
		_check(rules.commit_round(staged, round_plan) == round_plan.result,
			label + ": full round commit matches forecast")


func _check_outcome(example: Array, result: Dictionary, hero: String, ally: String, enemy: String) -> void:
	match example[2]:
		"healer_bonk":
			var cover: Dictionary = _unit(result, ally).get("statuses", {}).get("keep_your_head_down", {})
			_check(cover.get("source_id") == hero and cover.get("amount") == 2 and _unit(result, ally).hp == 10,
				"Knight's fitted Bonk grants two-point cover rather than harming the ally")
		"wizard_blast":
			_check(_unit(result, ally).hp == 14 and _unit(result, enemy).hp == 20,
				"Healer's fitted Blast heals the wounded ally for four")
		"rogue_confusing_dodge":
			_check(_unit(result, hero).position == Vector2i(6, 4) \
				and _unit(result, enemy).position == Vector2i(7, 4) \
				and _unit(result, ally).position == Vector2i(10, 10),
				"Caster's fitted Dodge jumps next to the enemy without swapping the far ally")
		"knight_push":
			_check(_unit(result, enemy).position == Vector2i(6, 4) and _unit(result, enemy).hp == 20,
				"Bard's fitted Push pulls the distant enemy one tile without damage")
		"alchemist_potion":
			_check(_unit(result, enemy).hp == 19, "Dodger's fitted Potion damages the enemy for one")
		"inspiring_melody":
			var inspired: Array = result.units.filter(func(unit): return \
				unit.get("statuses", {}).get("inspired", {}).get("source_id") == hero)
			_check(inspired.size() == 1 and _unit(result, enemy).statuses.is_empty(),
				"Crypter's fitted Melody inspires one hero instead of making the enemy laugh")
		"wizard_pull":
			_check(_unit(result, enemy).position == Vector2i(8, 4) \
				and _unit(result, hero).position == Vector2i(4, 4) and _unit(result, hero).hp == 20,
				"Mixologist's fitted Pull pushes the enemy away without recoil")


func _cosmetic_seed() -> int:
	for seed_value in range(1, 10000):
		if Reactions.draw(seed_value, true).category == "cosmetic":
			return seed_value
	return 12345
