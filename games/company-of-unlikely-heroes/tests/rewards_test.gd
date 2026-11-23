extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/rewards_test.gd
const Catalog = preload("res://content/catalog.gd")
var adventure: Script = load("res://adventure.gd")
var rules = preload("res://rules.gd").new()
var failures: Array[String] = []
var defs: Dictionary

# [display name, rarity, acquisition cap]. Same-named rewards are distinguished
# by their hero. This is an integration contract for the authored pools.
const POOLS := {
	"knight": [["+1 HP", "common", 5], ["+2 HP", "uncommon", 2], ["+1 shield damage", "uncommon", 3], ["+5 HP", "rare", 1], ["Dig In", "rare", 1], ["Shield Throw", "rare", 1], ["+3 shield damage", "rare", 1], ["Wide Guard", "legendary", 1]],
	"healer": [["+1 HP", "common", 3], ["+1 Bonk damage", "common", 2], ["+2 HP", "uncommon", 1], ["+1 heal", "uncommon", 2], ["+2 Bonk damage", "uncommon", 1], ["+2 heal", "rare", 1], ["Long Staff", "rare", 1], ["Strong Swing", "rare", 1], ["Me or You", "legendary", 1]],
	"wizard": [["Spare Robes", "common", 3], ["More Powder", "common", 2], ["Padded Landing", "uncommon", 2], ["Demolition Practice", "uncommon", 2], ["Duck!", "rare", 1], ["Braced Casting", "rare", 1], ["Parting Gift", "rare", 1], ["Conductive Personality", "legendary", 1]],
	"rogue": [["Thick Coat", "common", 2], ["Cheap Shot", "common", 2], ["Exit Strategy", "uncommon", 1], ["Borrowed Courage", "uncommon", 2], ["Pass the Buck", "rare", 1], ["Pocket Sand", "rare", 1], ["Long Finger", "rare", 1], ["Body Double", "legendary", 1]],
	"bard": [["Road Legs", "common", 2], ["Sharper Notes", "common", 2], ["Busker's Hat", "uncommon", 2], ["Front Row Seats", "uncommon", 1], ["Laughing Fit", "rare", 1], ["Heckler", "rare", 1], ["House Lights", "legendary", 1]],
	"necromancer": [["Spare Ribs", "common", 3], ["Good Soil", "common", 2], ["Heavy Bouquet", "uncommon", 2], ["Broad Wave", "uncommon", 1], ["Long-Stemmed", "rare", 1], ["Warm Welcome", "rare", 1], ["Say Hello to That One", "rare", 1], ["Wake Reception", "legendary", 1]],
	"alchemist": [["Padded Apron", "common", 2], ["Stronger Dose", "common", 2], ["Concentrate", "uncommon", 2], ["Long Ladle", "uncommon", 1], ["Spare Vial", "rare", 1], ["Brittle Glass", "rare", 1], ["Keep the Culture", "legendary", 1]],
}


func _initialize() -> void:
	defs = Catalog.read_default()
	_test_content()
	_test_offers()
	_test_caps_and_rarities()
	_test_terminal_boundaries()
	_test_alchemist_acquisition()
	if failures.is_empty():
		print("PASS: reward content and outing")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _start(source: Dictionary, party: Array, seed_value: int) -> Dictionary:
	var fixture: Dictionary = preload("res://tests/fixtures/controlled_commission.gd").build(source)
	var board: Array = preload("res://commissions.gd").board(fixture, 12345)
	return _route(adventure.call("start_commission", fixture, board[0], party, seed_value))


func _route(run: Dictionary) -> Dictionary:
	if run.get("phase") == "route":
		return adventure.call("choose_route", run, run.reports[0].mission_id)
	return run


func _test_content() -> void:
	var upgrades: Dictionary = defs.get("upgrades", {})
	_check(upgrades.size() == 55, "Seven shipped hero pools contain exactly 55 entries")
	for hero in POOLS:
		var remaining: Array = POOLS[hero].duplicate(true)
		for id in upgrades:
			var entry: Dictionary = upgrades[id]
			if entry.get("hero_id") != hero:
				continue
			var signature := [entry.get("label"), str(entry.get("rarity", "")).to_lower(), int(entry.get("cap", 0))]
			_check(signature in remaining, "%s has expected reward %s" % [hero, signature])
			remaining.erase(signature)
			_check(not str(entry.get("description", "")).strip_edges().is_empty(), str(id) + " describes its effect")
		_check(remaining.is_empty(), "%s missing entries: %s" % [hero, remaining])
	for entry in upgrades.values():
		_check(entry.get("hero_id") in POOLS, "Only the seven shipped heroes have rewards")


func _victory(run: Dictionary) -> Dictionary:
	var deployed: Dictionary = adventure.call("begin_mission", _route(run))
	var state: Dictionary = deployed.get("mission", {}).duplicate(true)
	if state.is_empty():
		_check(false, "Reward fixture deploys")
		return {}
	for unit in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			unit.hp = 0
	var plan: Dictionary = rules.preview_round(state)
	var terminal: Dictionary = rules.commit_round(state, plan)
	_check(terminal.get("outcome") == "victory", "Reward fixture commits a real victory")
	return adventure.call("settle_mission", deployed, terminal)


func _test_offers() -> void:
	if defs.get("upgrades", {}).is_empty():
		_check(false, "Offer tests require the authored upgrade table")
		return
	var party := ["knight", "healer", "alchemist"]
	var run := _start(defs, party, 12345)
	if run.is_empty():
		_check(false, "Reward outing starts")
		return
	var settled := _victory(run)
	var offers: Array = settled.get("reward_offers", [])
	_check(settled.get("phase") == "reward", "Nonfinal victory waits for a reward")
	_check(offers.size() == 3, "Each deployed hero including Alchemist gets one offer")
	var seen: Array = []
	for offer in offers:
		var hero: String = offer.get("hero_id", "")
		var id: String = offer.get("upgrade_id", "")
		_check(hero in party and hero not in seen, "Offer belongs to a distinct eligible hero")
		seen.append(hero)
		_check(defs.get("upgrades", {}).get(id, {}).get("hero_id") == hero, "Offer belongs to its hero's pool")
	var again := _victory(_start(defs, party, 12345))
	_check(offers == again.get("reward_offers", []), "The same seed and run reproduce offers")
	if not adventure.has_method("choose_reward"):
		_check(false, "Adventure exposes choose_reward")
		return
	if offers.is_empty():
		return
	var offer: Dictionary = offers[0]
	var before := settled.duplicate(true)
	_check(adventure.call("choose_reward", settled, "rogue", offer.upgrade_id) == settled,
		"Unadvertised hero cannot claim an offer")
	_check(adventure.call("choose_reward", settled, offer.hero_id, "not_an_upgrade") == settled,
		"An unknown reward cannot be chosen")
	if offers.size() > 1:
		_check(adventure.call("choose_reward", settled, offers[1].hero_id, offer.upgrade_id) == settled,
			"A reward cannot be claimed for the wrong hero")
	var chosen: Dictionary = adventure.call("choose_reward", settled, offer.hero_id, offer.upgrade_id)
	_check(settled == before, "Choosing does not mutate the offered snapshot")
	_check(chosen.get("phase") == "route", "Exactly one choice allows continuation")
	_check(chosen.get("upgrades_by_id", {}).get(offer.hero_id, {}).get(offer.upgrade_id) == 1,
		"Chosen reward is granted once to its owner")
	for other in offers:
		if other != offer:
			_check(chosen.get("upgrades_by_id", {}).get(other.hero_id, {}).get(other.upgrade_id, 0) == 0,
				"Passing on another hero's offer consumes nothing")
	_check(adventure.call("choose_reward", chosen, offer.hero_id, offer.upgrade_id) == chosen,
		"A second selection is rejected")
	var next: Dictionary = adventure.call("begin_mission", _route(chosen))
	for unit in next.get("mission", {}).get("units", []):
		if unit.get("id") == offer.hero_id:
			_check(unit.get("upgrades", {}).get(offer.upgrade_id) == 1, "Chosen upgrade carries into next mission")
	var no_table := defs.duplicate(true)
	no_table.erase("upgrades")
	var legacy := _start(no_table, party, 12345)
	_check(not legacy.is_empty(), "Catalog without optional upgrades remains usable")
	if not legacy.is_empty():
		var legacy_result := _victory(legacy)
		_check(legacy_result.get("phase") == "route" and legacy_result.get("reward_offers", []).is_empty(),
			"Catalog without rewards continues without a choice")


func _test_caps_and_rarities() -> void:
	if defs.get("upgrades", {}).is_empty() or not adventure.has_method("choose_reward"):
		return
	var upgrades: Dictionary = defs.upgrades
	var available := {}
	var spent := {}
	for id in upgrades:
		var entry: Dictionary = upgrades[id]
		var hero: String = entry.hero_id
		if hero not in ["knight", "healer", "alchemist"]:
			continue
		if not spent.has(hero):
			spent[hero] = {}
		spent[hero][id] = int(entry.cap)
		if hero == "knight" and not available.has(entry.rarity):
			available[entry.rarity] = id
	_check(available.size() == 4, "Fixture has all four Knight rarities")
	var draws := {}
	for seed_value in range(1, 33):
		var sampled := _start(defs, ["knight", "healer", "alchemist"], seed_value)
		var sampled_result := _victory(sampled)
		for offer in sampled_result.get("reward_offers", []):
			if offer.get("hero_id") == "knight":
				draws[offer.get("upgrade_id")] = true
	_check(draws.size() > 1, "Different seeds can produce different draws")
	var healer_id := ""
	for id in upgrades:
		if upgrades[id].hero_id == "healer":
			healer_id = id
			break
	if not healer_id.is_empty() and available.has("common"):
		var knight_id: String = available.common
		var passing := _start(defs, ["knight", "healer", "alchemist"], 33)
		passing.upgrades_by_id = spent.duplicate(true)
		passing.upgrades_by_id.knight[knight_id] = int(upgrades[knight_id].cap) - 1
		passing.upgrades_by_id.healer[healer_id] = int(upgrades[healer_id].cap) - 1
		var first := _victory(passing)
		_check(first.get("reward_offers", []).size() == 2, "Both last available entries are offered")
		var selected: Dictionary = adventure.call("choose_reward", first, "knight", knight_id)
		if selected.get("phase") == "route":
			var next_offer := _victory(selected)
			_check(next_offer.get("reward_offers", []) == [{"hero_id": "healer", "upgrade_id": healer_id}],
				"Passed reward remains available on the next victory")
	for rarity in available:
		var id: String = available[rarity]
		var run := _start(defs, ["knight", "healer", "alchemist"], 777)
		run.upgrades_by_id = spent.duplicate(true)
		run.upgrades_by_id.knight[id] = int(upgrades[id].cap) - 1
		var settled := _victory(run)
		var offers: Array = settled.get("reward_offers", [])
		_check(offers == [{"hero_id": "knight", "upgrade_id": id}],
			"Only unspent %s reward is offered, including when other heroes are exhausted" % rarity)
		if offers.is_empty():
			continue
		var chosen: Dictionary = adventure.call("choose_reward", settled, "knight", id)
		_check(chosen.get("upgrades_by_id", {}).get("knight", {}).get(id) == int(upgrades[id].cap),
			"Last acquisition reaches its cap")
		# Replay the same first-mission setup with that inventory to isolate the draw.
		var exhausted := _start(defs, ["knight", "healer", "alchemist"], 777)
		exhausted.upgrades_by_id = chosen.upgrades_by_id.duplicate(true)
		var no_offers := _victory(exhausted)
		_check(no_offers.get("phase") == "route" and no_offers.get("reward_offers", []).is_empty(),
			"Spent rewards disappear and a fully exhausted company continues without a choice")


func _test_terminal_boundaries() -> void:
	if defs.get("upgrades", {}).is_empty() or not adventure.has_method("choose_reward"):
		return
	var party := ["knight", "healer", "wizard"]
	var run := _start(defs, party, 42)
	var settled := _victory(run)
	var offers: Array = settled.get("reward_offers", [])
	if offers.is_empty():
		_check(false, "Terminal boundary fixture has an offer")
		return
	var chosen: Dictionary = adventure.call("choose_reward", settled, offers[0].hero_id, offers[0].upgrade_id)
	for _step in range(4):
		if chosen.get("phase") != "route":
			break
		var intermediate := _victory(chosen)
		var intermediate_offers: Array = intermediate.get("reward_offers", [])
		if intermediate_offers.is_empty():
			chosen = intermediate
		else:
			chosen = adventure.call("choose_reward", intermediate, intermediate_offers[0].hero_id, intermediate_offers[0].upgrade_id)
	_check(chosen.get("phase") == "ready", "Commission reaches its final mission")
	if chosen.get("phase") != "ready":
		return
	var second: Dictionary = adventure.call("begin_mission", chosen)
	var board: Dictionary = second.get("mission", {}).duplicate(true)
	if board.is_empty():
		_check(false, "Final mission deploys")
		return
	for unit in board.units:
		if rules.entity_profile(board, unit.id).get("team") == "enemies":
			unit.hp = 0
	var terminal: Dictionary = rules.commit_round(board, rules.preview_round(board))
	_check(terminal.get("outcome") == "victory", "Final fixture commits victory")
	var won: Dictionary = adventure.call("settle_mission", second, terminal)
	_check(won.get("phase") == "finished" and won.get("reward_offers", []).is_empty(),
		"Final victory gives no offer")
	_check_reset(won, party, "Victory")
	var defeated_board: Dictionary = second.mission.duplicate(true)
	for unit in defeated_board.units:
		if unit.id in party:
			unit.hp = 0
	var defeat: Dictionary = rules.commit_round(defeated_board, rules.preview_round(defeated_board))
	_check(defeat.get("outcome") == "defeat", "Failure fixture commits defeat")
	var lost: Dictionary = adventure.call("settle_mission", second, defeat)
	_check(lost.get("phase") == "finished" and lost.get("reward_offers", []).is_empty(),
		"Defeat gives no offer")
	_check_reset(lost, party, "Defeat")
	var direct: Dictionary = rules.open_mission(defs, "goblin_mob", party)
	_check(not direct.is_empty() and direct.get("reward_offers", []).is_empty(),
		"Standalone mission opens without outing rewards")


func _test_alchemist_acquisition() -> void:
	var party := ["knight", "healer", "alchemist"]
	var run := _start(defs, party, 42)
	var settled := _victory(run)
	var offer := {}
	for candidate in settled.get("reward_offers", []):
		if candidate.get("hero_id") == "alchemist":
			offer = candidate
			break
	_check(not offer.is_empty(), "Alchemist receives a real reward offer after victory")
	if offer.is_empty():
		return
	var chosen: Dictionary = adventure.call("choose_reward", settled, "alchemist", offer.upgrade_id)
	_check(chosen.get("upgrades_by_id", {}).get("alchemist", {}).get(offer.upgrade_id) == 1,
		"Choosing Alchemist's offered upgrade records one acquisition")
	var deployed: Dictionary = adventure.call("begin_mission", _route(chosen))
	var board: Dictionary = deployed.get("mission", {}).duplicate(true)
	var brewer := {}
	for unit in board.get("units", []):
		if unit.get("id") == "alchemist":
			brewer = unit
	_check(brewer.get("upgrades", {}).get(offer.upgrade_id) == 1,
		"Alchemist's acquired upgrade carries into the next mission")
	if board.is_empty():
		return
	for outcome in ["victory", "defeat"]:
		var terminal_board := board.duplicate(true)
		for unit in terminal_board.units:
			if outcome == "defeat" and unit.id in party:
				unit.hp = 0
			elif outcome == "victory" and rules.entity_profile(terminal_board, unit.id).get("team") == "enemies":
				unit.hp = 0
		var terminal: Dictionary = rules.commit_round(terminal_board, rules.preview_round(terminal_board))
		_check(terminal.get("outcome") == outcome, "Alchemist reset fixture reaches " + outcome)
		if terminal.get("outcome") != outcome:
			continue
		var finished: Dictionary = adventure.call("settle_mission", deployed, terminal)
		for _step in range(8):
			if finished.get("phase") not in ["route", "reward"]:
				break
			if finished.phase == "reward":
				var offers: Array = finished.reward_offers
				if offers.is_empty():
					break
				finished = adventure.call("choose_reward", finished, offers[0].hero_id, offers[0].upgrade_id)
			else:
				finished = _victory(finished)
		if finished.get("phase") == "ready":
			finished = _victory(finished)
		_check_reset(finished, party, "Alchemist reward " + outcome)


func _check_reset(finished: Dictionary, party: Array, label: String) -> void:
	_check(finished.get("phase") == "finished", label + " ends the commission")
	var fresh := _start(defs, party, 42)
	_check(fresh.get("upgrades_by_id", {}).is_empty() and fresh.get("reward_offers", []).is_empty(),
		label + " starts the next outing without rewards")
