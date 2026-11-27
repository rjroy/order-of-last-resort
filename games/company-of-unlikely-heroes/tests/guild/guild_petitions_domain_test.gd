extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/guild_petitions_domain_test.gd
# Four earned points are produced by real committed victories and a forfeit,
# never by editing profile data. All files belong exclusively to this test.
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const PetitionOrder = preload("res://presentation/book/guild_petition_view_model.gd")
const PARTY := ["knight", "healer", "wizard"]
const SEED := 147258

var profile_store: Script = load("res://guild/guild_profile.gd")
var adventure: Script = load("res://expedition/adventure.gd")
var commissions: Script = load("res://expedition/commissions.gd")
var rules = Rules.new()
var failures: Array[String] = []
var paths: Array[String] = []


func _initialize() -> void:
	var missing: Array[String] = []
	for method in ["balance", "roster", "petitions", "purchase", "slot_options",
			"default_loadout", "order_options", "settle_return", "save_loadouts"]:
		if not profile_store.has_method(method):
			missing.append("GuildProfile." + method)
	for method in ["start_guild_commission", "receipt"]:
		if not adventure.has_method(method):
			missing.append("Adventure." + method)
	if not missing.is_empty():
		_check(false, "First-path domain API missing: " + ", ".join(missing))
	else:
		var defs := _fixture()
		_test_fresh(defs)
		_test_register_order(defs)
		_test_receipts(defs)
		_test_same_board_stale_return(defs)
		_test_purchase_path(defs, "recruit_bard")
		_test_purchase_path(defs, "teach_healer_blast")
	for path in paths:
		for owned_path in [path, path + ".backup"]:
			if FileAccess.file_exists(owned_path):
				_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(owned_path)) == OK,
					"Remove disposable profile file " + owned_path)
	if failures.is_empty():
		print("PASS: guild petitions domain")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _fixture() -> Dictionary:
	# Match the route integration fixture: cloned combat and test-owned route
	# reports, so route choice and reward randomness do not depend on live tuning.
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	var combat: Dictionary = defs.missions.shield_wall.duplicate(true)
	defs.mission_reports = {}
	defs.mission_kinds = {}
	for kind_index in range(4):
		var kind := "test_kind_%d" % kind_index
		defs.mission_kinds[kind] = {"label": kind, "descriptors": ["test hint %d" % kind_index]}
		for index in range(3):
			var id := "test_transit_%d_%d" % [kind_index, index]
			defs.missions[id] = combat.duplicate(true)
			defs.missions[id].title = id
			defs.mission_reports[id] = {"kind": kind, "descriptors": ["test " + id]}
	for index in range(8):
		var id := "test_destination_%d" % index
		defs.missions[id] = combat.duplicate(true)
		defs.missions[id].title = id
		defs.mission_reports[id] = {
			"kind": "test_kind_%d" % (index % 4),
			"descriptors": ["test " + id],
			"destination_descriptors": ["test destination %d" % index]
		}
	# Keep the stock eligible roster paired with its stock guild progression.
	return defs


func _new_profile() -> Array:
	var path := "user://petition_test_%d_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec(), paths.size()]
	paths.append(path)
	var profile: Dictionary = profile_store.call("create", path, "Petition Test", SEED)
	_check(not profile.has("error") and not profile.is_empty(), "Create isolated guild")
	return [path, profile]


func _balance(profile: Dictionary) -> int:
	return int(profile_store.call("balance", profile))


func _test_fresh(defs: Dictionary) -> void:
	var pair := _new_profile()
	var path: String = pair[0]
	var profile: Dictionary = pair[1]
	_check(_balance(profile) == 0, "New guild starts with zero points")
	var roster: Array = profile_store.call("roster", defs, profile)
	_check(roster.size() == 3 and _has_founders(roster),
		"New guild has exactly the Knight, Healer and Caster")
	var before: Dictionary = profile_store.call("load_profile", path)
	for id in ["recruit_bard", "teach_healer_blast", "song_weaving", "invalid_petition"]:
		profile_store.call("purchase", path, profile, defs, id)
		_check(profile_store.call("load_profile", path) == before,
			"Unaffordable, prerequisite-locked or unknown purchase changes nothing: " + id)
	var loadout: Dictionary = profile_store.call("default_loadout", defs, profile, "healer")
	_check(loadout.get("slots", {}).get("offense") == "healer_bonk"
		and loadout.get("slots", {}).get("utility") == "healer_heal",
		"Fresh Healer starts with Bonk and Heal")


func _test_register_order(defs: Dictionary) -> void:
	# Controlled fixture: recruited heroes lead the register, then each tier
	# reads alphabetically by the player-visible name, case-insensitively.
	var options := [
		{"id": "gamma", "label": "Zebra"},
		{"id": "beta", "label": "Cherry"},
		{"id": "alpha", "label": "apple"},
		{"id": "delta", "label": "banana split"},
	]
	var ordered: Array = PetitionOrder.ordered_hero_options(options, ["beta"])
	_check(_option_ids(ordered) == PackedStringArray(["beta", "alpha", "delta", "gamma"]),
		"Recruited heroes lead the register, alphabetical within each tier")
	# A fresh stock guild lists its founders first, then the locked recruits.
	var pair := _new_profile()
	var profile: Dictionary = pair[1]
	var heroes: Array = []
	for petition in profile_store.call("petitions", defs, profile):
		var hero_id := str(petition.get("hero_id", ""))
		if not hero_id.is_empty() and _option_ids(heroes).find(hero_id) < 0:
			heroes.append({"id": hero_id, "label": str(petition.get("recipient_label", hero_id))})
	ordered = PetitionOrder.ordered_hero_options(heroes, profile.get("recruited_ids", []))
	_check(_option_ids(ordered) == PackedStringArray(["knight", "wizard", "healer",
			"bard", "rogue", "necromancer", "blacksmith", "alchemist"]),
		"Fresh register lists the founders first, then locked heroes alphabetically")
	# The rows follow the same section order, keeping authored order within a hero.
	var register_rows: Array = PetitionOrder.rows(defs, profile_store.call("petitions", defs, profile))
	ordered = PetitionOrder.ordered_rows(register_rows, ordered)
	var hero_sequence: Array = []
	var previous_hero := ""
	for row in ordered:
		var hero := str(row.get("hero_id", ""))
		if hero != previous_hero:
			hero_sequence.append(hero)
			previous_hero = hero
	_check(PackedStringArray(hero_sequence) == PackedStringArray(["knight", "wizard",
			"healer", "bard", "rogue", "necromancer", "blacksmith", "alchemist"]),
		"Register rows follow the hero section order")
	_check(str(ordered[0].id) == "knight_rescue_line",
		"The first register row is the fresh guild's default selection")


func _option_ids(options: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for option in options:
		ids.append(str(option.id))
	return ids


func _run_commission(defs: Dictionary, profile: Dictionary, wins: int, length_index: int,
		loadouts: Dictionary = {}) -> Dictionary:
	var board: Array = commissions.call("board", defs, SEED)
	if board.size() <= length_index:
		_check(false, "Controlled commission board exists")
		return {}
	var offer: Dictionary = board[length_index]
	var run: Dictionary = adventure.call("start_guild_commission", defs, offer, PARTY, profile, loadouts, 444)
	if run.get("phase") != "route":
		_check(false, "Guild commission starts with founders")
		return {}
	for index in range(wins + 1):
		if run.get("phase") == "route":
			var reports: Array = run.get("reports", [])
			if reports.is_empty():
				_check(false, "Road offers a route")
				return {}
			run = adventure.call("choose_route", run, reports[0].mission_id)
		var deployed: Dictionary = adventure.call("begin_mission", run)
		var state: Dictionary = deployed.get("mission", {}).duplicate(true)
		if deployed.get("phase") != "mission" or state.is_empty():
			_check(false, "Controlled commission deploys")
			return {}
		var terminal: Dictionary
		if index == wins:
			terminal = rules.forfeit(state)
		else:
			for unit in state.units:
				if rules.entity_profile(state, unit.id).get("team") == "enemies":
					unit.hp = 0
			terminal = rules.commit_round(state, rules.preview_round(state))
			_check(terminal.get("outcome") == "victory", "Controlled victory is committed")
		run = adventure.call("settle_mission", deployed, terminal)
		if run.get("phase") == "finished":
			return run
		if run.get("phase") == "reward":
			var offers: Array = run.get("reward_offers", [])
			if offers.is_empty():
				_check(false, "Reward phase supplies an offer")
				return {}
			run = adventure.call("choose_reward", run, offers[0].hero_id, offers[0].upgrade_id)
	return run


func _check_receipt(run: Dictionary, roads: int, destination: String, points: int) -> void:
	if run.is_empty():
		return
	var receipt: Dictionary = adventure.call("receipt", run)
	_check(receipt.get("road_wins") == roads and receipt.get("road_points") == roads,
		"Receipt credits each of %d road victories once: %s" % [roads, receipt])
	_check(receipt.get("destination_outcome") == destination,
		"Receipt identifies destination outcome: " + str(receipt))
	_check(receipt.get("destination_points") == (5 if destination == "victory" else 0)
		and receipt.get("points") == points, "Receipt totals road and destination pay: " + str(receipt))


func _test_receipts(defs: Dictionary) -> void:
	for example in [[0, 0, "not_reached", 0], [2, 0, "not_reached", 2], [4, 0, "forfeit", 4],
			[5, 0, "victory", 9], [10, 2, "victory", 14]]:
		var pair := _new_profile()
		var run := _run_commission(defs, pair[1], example[0], example[1])
		_check_receipt(run, mini(example[0], 4 if example[1] == 0 else 9), example[2], example[3])
		if run.is_empty():
			continue
		var path: String = pair[0]
		var profile: Dictionary = pair[1]
		profile_store.call("settle_return", path, profile, run, SEED + 1)
		var settled: Dictionary = profile_store.call("load_profile", path)
		_check(_balance(settled) == example[3], "Return persists the receipt exactly once")
		profile_store.call("settle_return", path, profile, run, SEED + 1)
		_check(profile_store.call("load_profile", path) == settled,
			"Retry with stale profile cannot duplicate a return")
		profile_store.call("settle_return", path, settled, run, SEED + 2)
		_check(profile_store.call("load_profile", path) == settled,
			"Retry with current profile cannot duplicate a return")


func _test_same_board_stale_return(defs: Dictionary) -> void:
	# Fund one test-owned point for this independent concurrency fixture.
	defs = defs.duplicate(true)
	defs.guild_progression.petitions.order_knight_advance.cost = 1
	var pair := _new_profile()
	var path: String = pair[0]
	var funded: Dictionary = pair[1].duplicate(true)
	funded.points = 1
	funded = profile_store.call("_write_profile", path, funded)
	var original: Dictionary = profile_store.call("purchase", path, funded, defs, "order_knight_advance")
	if original.has("error"):
		_check(false, "Stale-return fixture purchases Advance: " + str(original))
		return
	var board: Array = commissions.call("board", defs, SEED)
	if board.is_empty():
		_check(false, "Stale-return fixture has a commission board")
		return
	var run: Dictionary = adventure.call("start_guild_commission", defs, board[0], PARTY, original, {}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, "Stale-return fixture starts a scoped outing")
		return
	run = adventure.call("choose_route", run, run.reports[0].mission_id)
	var deployed: Dictionary = adventure.call("begin_mission", run)
	var state: Dictionary = deployed.get("mission", {}).duplicate(true)
	if deployed.get("phase") != "mission" or state.is_empty():
		_check(false, "Stale-return fixture has an active mission")
		return

	# A different current snapshot changes a genuine preference while the
	# outing is in progress, without changing the guild or board identity.
	var knight: Dictionary = profile_store.call("default_loadout", defs, original, "knight")
	knight["order_id"] = "order_advance"
	var updated: Dictionary = profile_store.call("save_loadouts", path, original, defs, {"knight": knight})
	var current: Dictionary = profile_store.call("load_profile", path)
	if updated.has("error") or current.has("error") or current == original:
		_check(false, "Independent snapshot saves a valid changed preference: " + str(updated))
		return
	_check(current.get("guild_id") == original.get("guild_id")
		and current.get("board_seed") == original.get("board_seed")
		and current.get("board_generation") == original.get("board_generation"),
		"Preference update leaves guild and board identity unchanged")
	_check(current.get("preferred_loadouts", {}).get("knight") == knight,
		"Independent preference is persisted before return")

	for unit in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			unit.hp = 0
	var victory: Dictionary = rules.commit_round(state, rules.preview_round(state))
	if victory.get("outcome") != "victory":
		_check(false, "Stale-return fixture commits a road victory")
		return
	run = adventure.call("settle_mission", deployed, victory)
	if run.get("phase") == "reward":
		var offers: Array = run.get("reward_offers", [])
		if offers.is_empty():
			_check(false, "Stale-return fixture offers a road reward")
			return
		run = adventure.call("choose_reward", run, offers[0].hero_id, offers[0].upgrade_id)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, "Road victory advances to the next route")
		return
	run = adventure.call("choose_route", run, run.reports[0].mission_id)
	deployed = adventure.call("begin_mission", run)
	if deployed.get("phase") != "mission":
		_check(false, "Stale-return fixture deploys the second road")
		return
	run = adventure.call("settle_mission", deployed, rules.forfeit(deployed.mission))
	if run.get("phase") != "finished":
		_check(false, "Stale-return fixture finishes with a forfeit")
		return
	_check_receipt(run, 1, "not_reached", 1)

	var result: Dictionary = profile_store.call("settle_return", path, original, run, SEED + 1)
	var settled: Dictionary = profile_store.call("load_profile", path)
	_check(not result.has("error"), "Same-board stale return safely merges: " + str(result))
	_check(_balance(settled) == _balance(current) + 1,
		"Same-board stale return credits the earned point")
	_check(settled.get("preferred_loadouts", {}).get("knight") == knight,
		"Same-board stale return preserves the independently saved preference")
	_check(settled.get("board_generation") == int(current.get("board_generation", -1)) + 1,
		"Same-board stale return advances the board exactly once")
	if not result.has("error"):
		profile_store.call("settle_return", path, original, run, SEED + 1)
		profile_store.call("settle_return", path, settled, run, SEED + 2)
		_check(profile_store.call("load_profile", path) == settled,
			"Stale or refreshed retries cannot credit the receipt twice")

	# Reuse the original seed on a later generation: seed equality is not
	# authorization to settle an already consumed board.
	var renewed: Dictionary = profile_store.call("renew", path, settled, SEED + 2)
	if renewed.has("error"):
		_check(false, "Fixture can advance to a later board: " + str(renewed))
		return
	renewed = profile_store.call("renew", path, renewed, SEED)
	if renewed.has("error"):
		_check(false, "Fixture can reuse an old seed on a later board: " + str(renewed))
		return
	var later: Dictionary = profile_store.call("load_profile", path)
	profile_store.call("settle_return", path, original, run, SEED + 3)
	profile_store.call("settle_return", path, later, run, SEED + 3)
	_check(profile_store.call("load_profile", path) == later,
		"A later generation with the original seed cannot settle the old outing")

	# A new guild at the same test-owned path, name and seed is not the old guild.
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		_check(false, "Replace test-owned profile for recreated-guild boundary")
		return
	var backup := path + ".backup"
	if FileAccess.file_exists(backup) and DirAccess.remove_absolute(ProjectSettings.globalize_path(backup)) != OK:
		_check(false, "Remove test-owned backup for recreated-guild boundary")
		return
	var recreated: Dictionary = profile_store.call("create", path, "Petition Test", SEED)
	if recreated.has("error"):
		_check(false, "Recreate test-owned guild: " + str(recreated))
		return
	_check(recreated.get("guild_id") != original.get("guild_id"),
		"Recreated guild has a distinct identity")
	profile_store.call("settle_return", path, original, run, SEED + 1)
	profile_store.call("settle_return", path, recreated, run, SEED + 1)
	_check(profile_store.call("load_profile", path) == recreated,
		"Recreated guild cannot receive the previous guild's receipt")


func _test_purchase_path(defs: Dictionary, purchase_id: String) -> void:
	if purchase_id == "teach_healer_blast":
		# Buy the old native order independently while keeping the four-road
		# balance and Blast purchase path intact.
		defs = defs.duplicate(true)
		defs.guild_progression.petitions.order_healer_aggressive.cost = 1
	var pair := _new_profile()
	var path: String = pair[0]
	var profile: Dictionary = pair[1]
	var run := _run_commission(defs, profile, 4, 0)
	if run.is_empty():
		return
	_check_receipt(run, 4, "forfeit", 4)
	profile_store.call("settle_return", path, profile, run, SEED + 1)
	profile = profile_store.call("load_profile", path)
	if _balance(profile) != 4:
		_check(false, purchase_id + ": four road wins fund the purchase")
		return
	var default_before: Dictionary = profile_store.call("default_loadout", defs, profile, "healer")
	profile_store.call("purchase", path, profile, defs, purchase_id)
	var bought: Dictionary = profile_store.call("load_profile", path)
	_check(_balance(bought) == 0, purchase_id + ": purchase costs exactly four")
	profile_store.call("purchase", path, profile, defs, purchase_id)
	profile_store.call("purchase", path, bought, defs, purchase_id)
	_check(profile_store.call("load_profile", path) == bought,
		purchase_id + ": stale and repeat purchases do not charge again")
	profile_store.call("purchase", path, bought, defs, "song_weaving")
	_check(profile_store.call("load_profile", path) == bought, "Song Weaving remains unaffordable")
	var roster: Array = profile_store.call("roster", defs, bought)
	var default_after: Dictionary = profile_store.call("default_loadout", defs, bought, "healer")
	_check(default_after == default_before, purchase_id + ": purchase does not automatically equip Blast")
	if purchase_id == "recruit_bard":
		_check(roster.size() == 4 and _has_founders(roster) and "bard" in roster,
			"Bard unlock adds one roster choice, not a party slot")
		var bard: Dictionary = profile_store.call("default_loadout", defs, bought, "bard")
		_check(_contains_id(bard.get("slots", {}), "inspiring_melody")
			and _contains_id(bard.get("slots", {}), "healing_sonnet"),
			"Bard joins with both songs equipped")
		var orders: Variant = profile_store.call("order_options", defs, bought, "bard", bard)
		_check(_contains_id(orders, "order_inspiring_melody") \
			and _contains_id(orders, "order_hold") and not _contains_id(orders, "order_healing_sonnet"),
			"Bard starts with Melody and Hold, without free Sonnet")
		var invalid: Dictionary = adventure.call("start_guild_commission", defs,
			commissions.call("board", defs, SEED + 1)[0], PARTY + ["bard"], bought, {}, 444)
		_check(invalid.is_empty(), "Bard unlock does not allow a four-hero party")
	else:
		_check(roster.size() == 3 and _has_founders(roster), "Teaching does not recruit Bard")
		bought.points = 1
		bought = profile_store.call("_write_profile", path, bought)
		bought = profile_store.call("purchase", path, bought, defs, "order_healer_aggressive")
		if bought.has("error"):
			_check(false, "Fixture purchases Bonk pursuit: " + str(bought))
			return
		var blast_loadout := default_after.duplicate(true)
		blast_loadout["slots"]["offense"] = "wizard_blast"
		var options: Variant = profile_store.call("order_options", defs, bought, "healer", blast_loadout)
		var aggressive := _find_option(options, "order_aggressive")
		_check(_contains_id(options, "order_support") and not aggressive.is_empty()
			and _contains_id(aggressive.get("missing_abilities", []), "healer_bonk")
			and not _contains_id(options, "order_blast"),
			"Blast retains Support, explains the incompatible Bonk pursuit and grants no Wizard automation")
		options = profile_store.call("order_options", defs, bought, "healer", default_after)
		_check(_contains_id(options, "order_support") and _contains_id(options, "order_aggressive"),
			"Restoring Bonk restores the learned pursuit order")
		var slots: Variant = profile_store.call("slot_options", defs, bought, "healer")
		_check(_contains_id(slots, "wizard_blast") and _contains_id(slots, "healer_bonk"),
			"Learned Blast and Bonk are both available as slot choices")
		profile_store.call("save_loadouts", path, bought, defs, {"healer": blast_loadout})
		var saved: Dictionary = profile_store.call("load_profile", path)
		_check(_balance(saved) == 0, "Saving a loadout is free")
		_check(profile_store.call("load_profile", path) == saved, "Saved guild survives reload")
		var restored: Dictionary = profile_store.call("default_loadout", defs, saved, "healer")
		_check(restored.get("slots", {}).get("offense") == "wizard_blast"
			and restored.get("slots", {}).get("utility") == "healer_heal"
			and restored.get("order_id") == blast_loadout.get("order_id"),
			"Reload restores the saved Blast, Heal and compatible order without an explicit loadout")
		_test_blast_rewards(defs, saved)


func _test_blast_rewards(defs: Dictionary, profile: Dictionary) -> void:
	var offer: Dictionary = commissions.call("board", defs, SEED + 1)[0]
	for seed_value in range(1, 17):
		var run: Dictionary = adventure.call("start_guild_commission", defs, offer, PARTY,
			profile, {}, seed_value)
		if run.get("phase") != "route":
			_check(false, "Blast reward fixture starts a guild commission")
			return
		# Leave only a Heal and a Bonk-dependent reward available for Healer.
		# The deterministic fixture tests eligibility, not live rarity tuning.
		run.upgrades_by_id["healer"] = {}
		for id in defs.upgrades:
			var upgrade: Dictionary = defs.upgrades[id]
			if upgrade.hero_id == "healer" and id not in ["healer_heal_1", "healer_long_staff"]:
				run.upgrades_by_id.healer[id] = int(upgrade.cap)
		run = adventure.call("choose_route", run, run.reports[0].mission_id)
		var deployed: Dictionary = adventure.call("begin_mission", run)
		var state: Dictionary = deployed.get("mission", {}).duplicate(true)
		if state.is_empty():
			_check(false, "Blast reward fixture deploys")
			return
		var healer: Dictionary = rules.entity_profile(state, "healer")
		_check("wizard_blast" in healer.get("abilities", []) and "healer_bonk" not in healer.get("abilities", []),
			"Blast loadout survives deployment after reload")
		_check(not healer.get("habits", {}).has("order_aggressive")
			and not healer.get("habits", {}).has("order_blast"),
			"Effective combat orders exclude incompatible pursuit and unlearned automatic Blast")
		if seed_value == 1:
			_test_direct_blast(state)
		for unit in state.units:
			if rules.entity_profile(state, unit.id).get("team") == "enemies":
				unit.hp = 0
		var terminal: Dictionary = rules.commit_round(state, rules.preview_round(state))
		var settled: Dictionary = adventure.call("settle_mission", deployed, terminal)
		var healer_offers: Array = []
		for reward in settled.get("reward_offers", []):
			if reward.get("hero_id") == "healer":
				healer_offers.append(reward.get("upgrade_id"))
		_check(healer_offers == ["healer_heal_1"],
			"Equipped Blast filters Long Staff but retains Heal reward: " + str(healer_offers))


func _test_direct_blast(deployed: Dictionary) -> void:
	var state := deployed.duplicate(true)
	state["obstacles"] = []
	for unit in state.units:
		match unit.id:
			"healer":
				unit.position = Vector2i(1, 1)
			"knight":
				unit.position = Vector2i(0, 0)
			"wizard":
				unit.position = Vector2i(2, 1)
			_:
				if rules.entity_profile(state, unit.id).get("team") == "enemies":
					unit.hp = 0
	# Use the unguarded Wizard as the nearest ally so Knight's Guard cannot
	# absorb or reflect the damage and obscure the targeting assertion.
	var wizard_hp := 0
	for unit in state.units:
		if unit.id == "wizard":
			wizard_hp = unit.hp
	var plan: Dictionary = rules.preview(state, "healer", "wizard_blast", "")
	_check(plan.get("valid", false), "Healer can directly preview the actual Blast")
	var result: Dictionary = rules.apply_plan(state, plan)
	for unit in result.get("units", []):
		if unit.id == "wizard":
			_check(unit.hp < wizard_hp, "Healer Blast hits the nearest damageable ally")
			_check(rules.has_status_handler(result, "wizard", "skip_action"),
				"Healer Blast inflicts the actual Blast knockdown")
			return
	_check(false, "Healer Blast result retains the nearest ally")


func _contains_id(value: Variant, id: String) -> bool:
	if value is String:
		return value == id
	if value is Array:
		for entry in value:
			if _contains_id(entry, id):
				return true
	if value is Dictionary:
		if value.has(id):
			return true
		for entry in value.values():
			if _contains_id(entry, id):
				return true
	return false


func _has_founders(roster: Array) -> bool:
	for id in PARTY:
		if id not in roster:
			return false
	return true


func _find_option(value: Variant, id: String) -> Dictionary:
	if value is Array:
		for entry in value:
			var found := _find_option(entry, id)
			if not found.is_empty():
				return found
	elif value is Dictionary:
		if value.get("id") == id or value.get("order_id") == id:
			return value
		if value.get(id) is Dictionary:
			return value[id]
		for entry in value.values():
			var found := _find_option(entry, id)
			if not found.is_empty():
				return found
	return {}
