extends SceneTree

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/expedition/smith_paste_reward_test.gd
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Rewards = preload("res://expedition/rewards.gd")
const Commissions = preload("res://expedition/commissions.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Rules = preload("res://rules/rules.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_test_reward()
	if failures.is_empty():
		print("PASS: smith Paste reward eligibility")
	else:
		for message in failures:
			push_error("FAIL: " + message)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _test_reward() -> void:
	# Read the actual catalog without rewriting reward eligibility or slot data.
	var defs: Dictionary = Catalog.read_default()
	var profile := {"guild_id": "paste-reward-test", "board_seed": 147258, "board_generation": 0,
		"points": 1000000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": ["knight", "healer", "wizard"]}
	for petition in ["recruit_alchemist", "alchemist_etching_paste", "recruit_blacksmith"]:
		profile = Progression.purchased_profile(defs, profile, petition)
		if profile.has("error"):
			_check(false, "Fixture purchases " + petition)
			return
	var acid_loadout := Progression.default_loadout(defs, profile, "alchemist")
	var acid_kit := Progression.effective_kit(defs, profile, "alchemist", acid_loadout)
	var paste_loadout := acid_loadout.duplicate(true)
	paste_loadout.slots.offense = "alchemist_etching_paste"
	for order: Dictionary in Progression.order_options(defs, profile, "alchemist", paste_loadout):
		if order.get("compatible", false):
			paste_loadout.order_id = order.id
			break
	var paste_kit := Progression.effective_kit(defs, profile, "alchemist", paste_loadout)
	var knight_loadout := Progression.default_loadout(defs, profile, "knight")
	var unrelated_kit := Progression.effective_kit(defs, profile, "knight", knight_loadout)
	_check("alchemist_acid" in acid_kit.get("abilities", []), "Acid control equips actual Acid")
	_check("alchemist_etching_paste" in paste_kit.get("abilities", [])
		and "alchemist_acid" not in paste_kit.get("abilities", []),
		"Trained Paste replaces Acid in actual offense slot")
	_check(not unrelated_kit.is_empty() and "alchemist_acid" not in unrelated_kit.abilities
		and "alchemist_etching_paste" not in unrelated_kit.abilities,
		"Unrelated actual kit has neither Acid-family source")
	if paste_kit.is_empty() or acid_kit.is_empty() or unrelated_kit.is_empty():
		return
	for reward in ["alchemist_brittle_glass", "alchemist_concentrate"]:
		_check(Rewards.eligible(defs, "alchemist", reward, {}, acid_kit),
			reward + " is eligible for equipped Acid")
		_check(not Rewards.eligible(defs, "alchemist", reward, {}, unrelated_kit),
			reward + " is ineligible for an unrelated kit")
	_check(Rewards.eligible(defs, "alchemist", "alchemist_brittle_glass", {}, paste_kit),
		"Brittle Glass is eligible for equipped Etching Paste")
	_check(not Rewards.eligible(defs, "alchemist", "alchemist_concentrate", {}, paste_kit),
		"Concentrate remains ineligible for Paste without Acid")

	var board := Commissions.board(defs, profile.board_seed)
	_check(not board.is_empty(), "Fixture has a commission")
	if board.is_empty():
		return
	var run := Adventure.start_guild_commission(defs, board[0], ["alchemist", "blacksmith", "knight"],
		profile, {"alchemist": paste_loadout}, 444)
	_check(run.get("phase") == "route", "Scoped commission starts with trained Paste")
	if run.get("phase") != "route":
		return
	# Fix only the offer, not eligibility: choose_reward must recheck the real kit.
	run.phase = "reward"
	run.reward_offers = [{"hero_id": "alchemist", "upgrade_id": "alchemist_brittle_glass"}]
	run = Adventure.choose_reward(run, "alchemist", "alchemist_brittle_glass")
	var claimed: int = run.get("upgrades_by_id", {}).get("alchemist", {}).get("alchemist_brittle_glass", 0)
	_check(claimed == 1, "Scoped commission accepts offered Brittle Glass with Paste equipped")
	if claimed != 1:
		return
	if run.get("phase") == "route":
		if run.get("reports", []).is_empty():
			_check(false, "Claim produces a next route")
			return
		run = Adventure.choose_route(run, run.reports[0].mission_id)
	run = Adventure.begin_mission(run)
	var state: Dictionary = run.get("mission", {})
	_check(not state.is_empty(), "Claim deploys into the next mission")
	if state.is_empty():
		return
	var actor := _unit(state, "alchemist")
	_check(actor.get("upgrades", {}).get("alchemist_brittle_glass", 0) == 1,
		"Claimed Glass reaches the deployed Mixologist")
	var smith := _unit(state, "blacksmith")
	var patient := _unit(state, "knight")
	if actor.is_empty() or smith.is_empty() or patient.is_empty():
		_check(false, "Deployed party contains the three fixture heroes")
		return
	state.width = 12
	state.height = 12
	state.terrain = []
	state.obstacles = []
	state.units = [actor, smith, patient,
		{"id": "neighbor", "character_id": "healer", "position": Vector2i(5, 5),
			"hp": 10, "max_hp": 20, "statuses": {}}]
	actor.position = Vector2i(4, 4)
	actor.fitted_by = "blacksmith"
	smith.position = Vector2i(0, 0)
	patient.position = Vector2i(4, 5)
	patient.hp = 10
	patient.max_hp = 20
	for seed_value in range(1, 10000):
		if Reactions.draw(seed_value, false).category == "cosmetic":
			actor.dose_rng_state = seed_value
			break
	var rules := Rules.new()
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "alchemist", "alchemist_etching_paste", "knight")
	_check(plan.get("valid", false) and state == before
		and plan == rules.preview(state, "alchemist", "alchemist_etching_paste", "knight"),
		"Claimed Glass Sealing Paste forecasts legally and repeatably")
	if not plan.get("valid", false):
		return
	var result: Dictionary = rules.apply_plan(state, plan)
	_check(result == plan.get("result") and state == before
		and _unit(result, "knight").hp == 12 and _unit(result, "neighbor").hp == 11,
		"Claimed Glass adds one friendly splash to fitted Paste and commits the forecast")
