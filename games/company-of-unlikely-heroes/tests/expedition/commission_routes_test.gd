extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/expedition/commission_routes_test.gd
# Route transitions use test-owned mission reports and cloned, easily staged
# combat missions. The catalog smoke test separately exercises authored data.
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const PARTY := ["wizard", "knight", "healer"]

var failures: Array[String] = []
var commissions: Script
var adventure: Script
var rules = Rules.new()


func _initialize() -> void:
	if not ResourceLoader.exists("res://expedition/commissions.gd"):
		_check(false, "Missing commissions.gd")
	else:
		commissions = load("res://expedition/commissions.gd")
		adventure = load("res://expedition/adventure.gd")
		if not commissions.has_method("board") or not adventure.has_method("start_commission") \
				or not adventure.has_method("choose_route"):
			_check(false, "Commission board and adventure route APIs are available")
		else:
			var fixture := _fixture()
			if not fixture.is_empty():
				_test_board(fixture, "controlled")
				for seed_value in [11, 9182]:
					for length_index in [0, 2]:
						for branch in [0, 1]:
							_test_route(fixture, seed_value, length_index, branch)
				_test_branch_promises(fixture)
				_test_legacy_ignores_mission_tiers()
				_test_tiered_routes()
				_test_exhausted_kind_avoids_last_base()
			if "--controlled-only" not in OS.get_cmdline_user_args():
				var source := Catalog.read_source(Catalog.DEFAULT_PATH)
				if source.has("error"):
					_check(false, "authored catalog failed to load: " + str(source.error))
				else:
					var stock: Dictionary = source.definitions
					_test_board(stock, "authored")
					_test_authored_opening(stock)
					_test_stock_tiered_catalog(stock)
	if failures.is_empty():
		print("PASS: commission routes")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _fixture() -> Dictionary:
	var source := Catalog.read_source("res://content/practice/catalog.json")
	if source.has("error"):
		_check(false, "practice combat source failed to load: " + str(source.error))
		return {}
	var defs: Dictionary = source.definitions
	var combat: Dictionary = defs.missions.shield_wall.duplicate(true)
	defs.upgrades = {}
	for hero in PARTY:
		defs.upgrades["test_hp_" + hero] = {"hero_id": hero, "rarity": "common",
			"cap": 20, "effect": "max_hp", "amount": 1,
			"label": "Test HP", "description": "Test reward"}
	defs.mission_reports = {}
	defs.mission_kinds = {}
	# Four test-owned types with three transit missions each.
	for kind_index in range(4):
		var kind := "test_kind_%d" % kind_index
		defs.mission_kinds[kind] = {"label": kind, "descriptors": ["test hint %d" % kind_index]}
		for mission_index in range(3):
			var id := "test_transit_%d_%d" % [kind_index, mission_index]
			defs.missions[id] = combat.duplicate(true)
			defs.missions[id].title = id
			defs.mission_reports[id] = {"kind": kind, "descriptors": ["test immediate " + id]}
	for index in range(8):
		var id := "test_destination_%d" % index
		defs.missions[id] = combat.duplicate(true)
		defs.missions[id].title = id
		defs.mission_reports[id] = {
			"kind": "test_kind_%d" % (index % 4),
			"descriptors": ["test immediate " + id],
			"destination_descriptors": ["test destination %d" % index]
		}
	defs.erase("adventures")
	defs["commission_settings"] = {"recruitment_roster": PARTY.duplicate()}
	return defs


func _test_board(defs: Dictionary, label: String) -> void:
	var before := defs.duplicate(true)
	for seed_value in [1, 11, 9182, 123456]:
		var board: Array = commissions.call("board", defs, seed_value)
		_check(board == commissions.call("board", defs, seed_value),
			label + ": same board seed reproduces offers")
		_check(board.size() == 3, label + ": board contains three offers")
		if board.size() != 3:
			continue
		var seen: Array = []
		for index in range(3):
			var offer: Dictionary = board[index]
			var id: String = offer.get("destination_id", "")
			_check(id not in seen and defs.get("mission_reports", {}).get(id, {}).has("destination_descriptors"),
				label + ": offer names a distinct eligible destination")
			seen.append(id)
			_check(offer.get("length") == [5, 5, 10][index],
				label + ": offers have ordered lengths 5/5/10")
			_check(offer.get("seed") is int, label + ": offer carries an integer seed")
			_check(not str(offer.get("description", "")).strip_edges().is_empty(),
				label + ": offer has destination description")
			_check(offer.get("description") in defs.get("mission_reports", {}).get(id, {}).get("destination_descriptors", []),
				label + ": offer description belongs to that destination")
	_check(defs == before, label + ": board generation leaves definitions unchanged")


func _test_route(defs: Dictionary, seed_value: int, length_index: int, branch: int) -> void:
	var board: Array = commissions.call("board", defs, seed_value)
	if board.size() != 3:
		return
	var offer: Dictionary = board[length_index]
	var label := "seed %d length %d branch %d" % [seed_value, offer.length, branch]
	var run: Dictionary = adventure.call("start_commission", defs, offer, PARTY, 444)
	var replay: Dictionary = adventure.call("start_commission", defs, offer, PARTY, 444)
	_check(run.get("phase") == "route" and run.get("party") == PARTY,
		label + ": ordered company starts at route selection")
	_check(run.get("mission_count") == offer.length, label + ": fixed mission count includes destination")
	if run.get("phase") != "route":
		return
	var visited: Array = []
	var expected_kind := ""
	for step in range(offer.length):
		var final: bool = step == int(offer.length) - 1
		var chosen_id := str(offer.destination_id)
		if not final:
			var reports: Array = run.get("reports", [])
			_check(run.get("phase") == "route" and reports.size() == 2,
				label + ": each transit stop offers a pair")
			_check(reports == replay.get("reports", []), label + ": chosen path reproduces reports")
			if reports.size() != 2:
				return
			_check(reports[0].get("mission_id") != reports[1].get("mission_id"),
				label + ": pair contains distinct missions")
			var first_kind := str(defs.mission_reports.get(reports[0].get("mission_id", ""), {}).get("kind", ""))
			var second_kind := str(defs.mission_reports.get(reports[1].get("mission_id", ""), {}).get("kind", ""))
			_check(first_kind != second_kind, label + ": pair presents two different kinds")
			var matching_hint := 0
			for report in reports:
				var id := str(report.get("mission_id", ""))
				var info: Dictionary = defs.mission_reports.get(id, {})
				var kind := str(info.get("kind", ""))
				_check(not info.is_empty() and not info.has("destination_descriptors"),
					label + ": route option is an eligible transit mission")
				if id in visited:
					for alternative in defs.mission_reports:
						var candidate: Dictionary = defs.mission_reports[alternative]
						_check(candidate.has("destination_descriptors") or candidate.get("kind") != kind
							or alternative in visited,
							label + ": repeated type uses an unvisited mission when available")
				_check(report.get("description") in info.get("descriptors", []),
					label + ": immediate descriptor belongs to offered mission")
				_check(not str(report.get("hint_text", "")).strip_edges().is_empty()
					and defs.mission_kinds.has(report.get("hint_kind")),
					label + ": option advertises a next type")
				if step != offer.length - 2:
					_check(report.get("hint_text") in defs.mission_kinds.get(report.get("hint_kind"), {}).get("descriptors", []),
						label + ": hint text belongs to its advertised type")
				if kind == expected_kind:
					matching_hint += 1
				if step == offer.length - 2:
					_check(report.get("hint_kind") == defs.mission_reports[offer.destination_id].kind,
						label + ": both penultimate options point to the destination type")
					_check(str(report.get("hint_text", "")).to_lower().contains(
						str(defs.missions[offer.destination_id].title).to_lower()),
						label + ": both penultimate hints name the destination")
			if not expected_kind.is_empty():
				_check(matching_hint == 1, label + ": previous hint matches exactly one next option")
			var selected: Dictionary = reports[branch]
			chosen_id = str(selected.mission_id)
			expected_kind = str(selected.get("hint_kind", ""))
			var source := run
			var prior := source.duplicate(true)
			run = adventure.call("choose_route", run, chosen_id)
			replay = adventure.call("choose_route", replay, chosen_id)
			_check(source == prior,
				label + ": selection preserves its source snapshot")
		else:
			_check(run.get("phase") == "ready", label + ": destination deploys without another fork")
		_check(run.get("phase") == "ready", label + ": selection makes mission ready")
		if run.get("phase") != "ready":
			return
		visited.append(chosen_id)
		var deployed: Dictionary = adventure.call("begin_mission", run)
		var deployed_replay: Dictionary = adventure.call("begin_mission", replay)
		_check(deployed.get("mission", {}).get("mission_id") == chosen_id,
			label + ": deployment matches selected mission")
		if deployed.get("phase") != "mission" or deployed_replay.get("phase") != "mission":
			return
		run = _victory(deployed, label)
		replay = _victory(deployed_replay, label + " replay")
		if final:
			_check(run.get("phase") == "finished" and run.get("outcome") == "victory",
				label + ": destination victory finishes commission")
			_check(run.get("reward_offers", []).is_empty(), label + ": no commission-completion reward")
			continue
		_check(run.get("phase") == "reward", label + ": victory gives reward before next route")
		var rewards: Array = run.get("reward_offers", [])
		if run.get("phase") != "reward" or rewards.is_empty():
			return
		_check(rewards == replay.get("reward_offers", []), label + ": reward seed is reproducible")
		_check(adventure.call("begin_mission", run) == run, label + ": reward cannot be skipped by deploying")
		var reward: Dictionary = rewards[0]
		run = adventure.call("choose_reward", run, reward.hero_id, reward.upgrade_id)
		replay = adventure.call("choose_reward", replay, reward.hero_id, reward.upgrade_id)
	_check(visited.size() == offer.length and visited.count(offer.destination_id) == 1
		and visited.back() == offer.destination_id, label + ": named special occurs exactly once, last")


func _test_branch_promises(defs: Dictionary) -> void:
	# Enumerate branch combinations at the scouting boundary rather than
	# executing thousands of combat rounds to exercise route generation.
	if not commissions.has_method("draw_reports") or not commissions.has_method("starting_rng_state"):
		_check(false, "Commission scouting exposes deterministic report generation")
		return
	for seed_value in [11, 9182]:
		var offers: Array = commissions.call("board", defs, seed_value)
		if offers.size() != 3:
			continue
		for index in [0, 2]:
			var offer: Dictionary = offers[index]
			var rng_state: int = commissions.call("starting_rng_state", offer.seed)
			_enumerate_forks(defs, offer, [], "", rng_state, 0, str(seed_value))


func _test_legacy_ignores_mission_tiers() -> void:
	var original := _fixture()
	var changed := original.duplicate(true)
	for kind_index in range(4):
		for mission_index in range(3):
			var id := "test_transit_%d_%d" % [kind_index, mission_index]
			original.missions[id].erase("tier")
			changed.missions[id].tier = 1 if kind_index < 2 else 5
	_check(Catalog.validate(original).is_empty() and Catalog.validate(changed).is_empty(),
		"legacy fixtures validate with missing or varying mission tiers")
	var seen_tiers: Array = []
	for seed_value in range(16):
		var rng_state: int = commissions.call("starting_rng_state", seed_value)
		var before: Dictionary = commissions.call("draw_reports", original, "test_destination_0",
			false, [], "", rng_state)
		var after: Dictionary = commissions.call("draw_reports", changed, "test_destination_0",
			false, [], "", rng_state)
		_check(before == after, "legacy route draw ignores mission tier at seed %d" % seed_value)
		var reports: Array = after.get("reports", [])
		_check(reports.size() == 2, "legacy route yields two reports at seed %d" % seed_value)
		for report in reports:
			var tier: Variant = changed.missions[report.mission_id].tier
			if tier not in seen_tiers:
				seen_tiers.append(tier)
	_check(1 in seen_tiers and 5 in seen_tiers, "legacy routes can offer either mission tier")


func _enumerate_forks(defs: Dictionary, offer: Dictionary, visited: Array,
		promised: String, rng_state: int, depth: int, path: String) -> void:
	var penultimate: bool = depth == int(offer.length) - 2
	var draw: Dictionary = commissions.call("draw_reports", defs, offer.destination_id,
		penultimate, visited, promised, rng_state)
	var reports: Array = draw.get("reports", [])
	_check(reports.size() == 2, "branch %s: fork has two reports" % path)
	if reports.size() != 2:
		return
	var kinds: Array = []
	for report in reports:
		kinds.append(defs.mission_reports.get(report.get("mission_id", ""), {}).get("kind", ""))
	_check(not kinds[0].is_empty() and not kinds[1].is_empty() and kinds[0] != kinds[1],
		"branch %s: fork has two known distinct kinds" % path)
	if not promised.is_empty():
		_check(kinds.count(promised) == 1, "branch %s: previous hint appears exactly once" % path)
	if penultimate:
		for report in reports:
			_check(report.get("hint_kind") == defs.mission_reports[offer.destination_id].kind
				and str(report.get("hint_text", "")).contains(defs.missions[offer.destination_id].title),
				"branch %s: final hints name destination" % path)
		return
	for index in range(2):
		var report: Dictionary = reports[index]
		_enumerate_forks(defs, offer, visited + [report.get("mission_id", "")],
			str(report.get("hint_kind", "")), int(draw.get("rng_state", 0)), depth + 1,
			path + str(index))


func _victory(deployed: Dictionary, label: String) -> Dictionary:
	var state: Dictionary = deployed.get("mission", {}).duplicate(true)
	for unit in state.get("units", []):
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			unit.hp = 0
	var terminal: Dictionary = rules.commit_round(state, rules.preview_round(state))
	_check(terminal.get("outcome") == "victory", label + ": controlled combat commits victory")
	return adventure.call("settle_mission", deployed, terminal)


func _test_authored_opening(defs: Dictionary) -> void:
	var offers: Array = commissions.call("board", defs, 101)
	if offers.is_empty():
		return
	var run: Dictionary = adventure.call("start_commission", defs, offers[0], PARTY, 42)
	_check(run.get("phase") == "route" and run.get("reports", []).size() == 2,
		"Authored catalog supports a commission opening and route pair")


func _tiered_fixture() -> Dictionary:
	var defs := _fixture()
	var combat: Dictionary = defs.missions.shield_wall.duplicate(true)
	defs.mission_reports = {}
	defs.mission_kinds = {}
	defs.commission_settings.tiered = true
	# Neighboring tiers have disjoint kinds. T5 deliberately has one base per
	# kind, so its second slot must repeat a base, even though variants exist.
	for tier in range(1, 6):
		for kind_index in range(2):
			var kind := "tier_%d_kind_%d" % [tier, kind_index]
			defs.mission_kinds[kind] = {"label": kind, "descriptors": ["hint " + kind]}
			var base_count := 1 if tier == 5 else 2
			for base_index in range(base_count):
				var base := "tier_%d_kind_%d_base_%d" % [tier, kind_index, base_index]
				defs.missions[base] = combat.duplicate(true)
				defs.missions[base].title = base
				defs.missions[base].tier = tier
				defs.mission_reports[base] = {
					"kind": kind, "descriptors": ["report " + base]}
				if base_index == 0:
					var variant := base + "_variant"
					defs.missions[variant] = combat.duplicate(true)
					defs.missions[variant].title = variant
					defs.missions[variant].tier = tier
					defs.missions[variant].base_mission_id = base
					defs.mission_reports[variant] = {
						"kind": kind, "descriptors": ["report " + variant]}
	for index in range(3):
		var id := "tier_destination_%d" % index
		defs.missions[id] = combat.duplicate(true)
		defs.missions[id].title = id
		defs.mission_reports[id] = {"kind": "tier_1_kind_0",
			"descriptors": ["report " + id], "destination_descriptors": ["destination " + id]}
	return defs


func _base_id(defs: Dictionary, id: String) -> String:
	return str(defs.missions.get(id, {}).get("base_mission_id", id))


func _test_tiered_routes() -> void:
	var defs := _tiered_fixture()
	var seen := {"fresh": 0, "repeat": 0, "variant": 0}
	for seed_value in [11, 9182]:
		var board: Array = commissions.call("board", defs, seed_value)
		_check(board.size() == 3, "tiered fixture: valid catalog supplies a board")
		if board.size() != 3:
			continue
		for length_index in [0, 2]:
			for branch in [0, 1]:
				_test_tiered_route(defs, board[length_index], branch, seen)
	_check(seen.fresh > 0, "tiered routes exercise fresh base preference")
	_check(seen.repeat > 0, "tiered routes exercise unavoidable tier-local repeats")
	_check(seen.variant > 0, "tiered routes offer a variant with a shared base")


func _test_tiered_route(defs: Dictionary, offer: Dictionary, branch: int, seen: Dictionary) -> void:
	var label := "tiered seed %s length %s branch %d" % [offer.seed, offer.length, branch]
	var run: Dictionary = adventure.call("start_commission", defs, offer, PARTY, 444)
	var other: Dictionary = adventure.call("start_commission", defs, offer, PARTY, 999)
	_check(run.get("phase") == "route" and other.get("phase") == "route",
		label + ": valid tiered commission starts")
	if run.get("phase") != "route" or other.get("phase") != "route":
		return
	var tiers := [1, 1, 2, 2] if offer.length == 5 else [1, 1, 2, 2, 3, 4, 4, 5, 5]
	var visited: Array = []
	var promised := ""
	for step in range(tiers.size()):
		var reports: Array = run.get("reports", [])
		_check(run.get("phase") == "route" and reports.size() == 2,
			label + ": slot %d has two reports" % (step + 1))
		_check(reports == other.get("reports", []),
			label + ": route is independent of reward seed, choice and party wounds")
		if reports.size() != 2 or other.get("reports", []).size() != 2:
			return
		var kinds: Array = []
		for report in reports:
			var id := str(report.get("mission_id", ""))
			var info: Dictionary = defs.mission_reports.get(id, {})
			var kind := str(info.get("kind", ""))
			kinds.append(kind)
			_check(defs.missions.get(id, {}).get("tier") == tiers[step] and not info.has("road_tier"),
				label + ": slot %d offers tier %d, got %s" % [step + 1, tiers[step], id])
			var base := _base_id(defs, id)
			if id != base:
				seen.variant += 1
			var visited_bases: Array = visited.map(func(old_id): return _base_id(defs, old_id))
			var fresh_available := false
			for candidate in defs.mission_reports:
				var entry: Dictionary = defs.mission_reports[candidate]
				if entry.has("destination_descriptors") or defs.missions[candidate].get("tier") != tiers[step] or entry.get("kind") != kind:
					continue
				var candidate_base := _base_id(defs, candidate)
				if candidate_base not in visited_bases:
					fresh_available = true
			if base in visited_bases:
				seen.repeat += 1
				_check(not fresh_available, label + ": repeat only after eligible kind exhausts fresh bases")
			elif fresh_available:
				seen.fresh += 1
			if step + 1 < tiers.size():
				var hint := str(report.get("hint_kind", ""))
				_check(hint.begins_with("tier_%d_kind_" % tiers[step + 1]),
					label + ": slot %d promises a kind in the next tier" % (step + 1))
			else:
				_check(report.get("hint_kind") == defs.mission_reports[offer.destination_id].kind
					and str(report.get("hint_text", "")).contains(defs.missions[offer.destination_id].title),
					label + ": last road points to selected destination")
		_check(not kinds[0].is_empty() and kinds[0] != kinds[1],
			label + ": fork has two distinct kinds")
		if not promised.is_empty():
			_check(kinds.count(promised) == 1, label + ": previous promise appears exactly once")
		var selected: Dictionary = reports[branch]
		var id := str(selected.mission_id)
		promised = str(selected.get("hint_kind", ""))
		visited.append(id)
		run = adventure.call("choose_route", run, id)
		other = adventure.call("choose_route", other, id)
		var deployed: Dictionary = adventure.call("begin_mission", run)
		var other_deployed: Dictionary = adventure.call("begin_mission", other)
		_check(deployed.get("mission", {}).get("mission_id") == id,
			label + ": exact selected base or variant deploys")
		if deployed.get("phase") != "mission" or other_deployed.get("phase") != "mission":
			return
		run = _victory(deployed, label)
		other = _victory(other_deployed, label + " alternate")
		if run.get("phase") != "reward" or other.get("phase") != "reward":
			_check(false, label + ": road victory offers rewards")
			return
		# Change carried wounds independently of rewards before preparing the fork.
		var wounded: Dictionary = other.carry_by_id.duplicate(true)
		for hero in wounded:
			wounded[hero].hp = 1
		other.carry_by_id = wounded
		var reward: Dictionary = run.reward_offers[0]
		var alternate: Dictionary = other.reward_offers.back()
		run = adventure.call("choose_reward", run, reward.hero_id, reward.upgrade_id)
		other = adventure.call("choose_reward", other, alternate.hero_id, alternate.upgrade_id)
	_check(run.get("phase") == "ready" and other.get("phase") == "ready",
		label + ": destination follows the last road")
	if run.get("phase") != "ready" or other.get("phase") != "ready":
		return
	var finale: Dictionary = adventure.call("begin_mission", run)
	_check(finale.get("mission", {}).get("mission_id") == offer.destination_id,
		label + ": selected destination is deployed as finale")
	if finale.get("phase") == "mission":
		var finished := _victory(finale, label + " finale")
		_check(finished.get("phase") == "finished" and finished.get("outcome") == "victory",
			label + ": finale victory finishes commission")


func _test_exhausted_kind_avoids_last_base() -> void:
	var defs := _tiered_fixture()
	var kind := "tier_2_kind_0"
	for id in defs.mission_reports.keys():
		if not defs.mission_reports[id].has("destination_descriptors") and defs.missions[id].get("tier") == 2 and defs.mission_reports[id].get("kind") == kind:
			defs.mission_reports.erase(id)
	var first := "tier_1_kind_0_base_0"
	var second := "tier_1_kind_0_base_1"
	# All eligible bases were visited in T1, and the first base was just played
	# in T2. An unplayed variant of that last base is not a fresh base.
	for entry in [["repeat_a", first], ["repeat_a_unplayed", first], ["repeat_b", second]]:
		var id: String = entry[0]
		defs.missions[id] = defs.missions[entry[1]].duplicate(true)
		defs.missions[id].title = id
		defs.missions[id].tier = 2
		defs.missions[id].base_mission_id = entry[1]
		defs.mission_reports[id] = {"kind": kind, "descriptors": ["report " + id]}
	_check(Catalog.validate(defs).is_empty(), "repeat fixture is a valid tiered catalog")
	var traversed := [first, second, "repeat_a"]
	for seed_value in range(16):
		var state: int = commissions.call("starting_rng_state", seed_value)
		var draw: Dictionary = commissions.call("draw_reports", defs, "tier_destination_0",
			true, traversed, kind, state, 3)
		var reports: Array = draw.get("reports", [])
		_check(reports.size() == 2, "exhausted promised kind still yields a fork")
		if reports.size() != 2:
			continue
		var matching: Array = reports.filter(func(report):
			return defs.mission_reports[report.mission_id].kind == kind)
		_check(matching.size() == 1, "exhausted promised kind appears exactly once")
		if matching.size() == 1:
			_check(matching[0].mission_id == "repeat_b",
				"exhausted promised kind avoids the last base even when another variant is unplayed")


func _test_stock_tiered_catalog(defs: Dictionary) -> void:
	_check(defs.get("commission_settings", {}).get("tiered") == true,
		"stock catalog opts into tiered commissions")
	# Preserve the shipped roads and their base identities without pinning tuning.
	var roster := {
		"bridge_patrol": "bridge_patrol",
		"goblin_mob": "goblin_mob",
		"light_hook_pair": "harpoon_squad",
		"harpoon_squad": "harpoon_squad",
		"explosive_situation": "explosive_situation",
		"duelists": "duelists",
		"cowardly_captain": "cowardly_captain",
		"shield_wall": "shield_wall",
		"last_one_standing": "last_one_standing",
		"veteran_shield_wall": "shield_wall",
		"veteran_explosive_situation": "explosive_situation",
		"unfortunate_healer": "unfortunate_healer",
		"odd_couple": "odd_couple",
		"mirror_company": "mirror_company",
		"veteran_mirror_company": "mirror_company",
		"veteran_unfortunate_healer": "unfortunate_healer",
		"veteran_odd_couple": "odd_couple",
		"crossfire_blast_lane": "crossfire_blast_lane",
	}
	for id in roster:
		var report: Dictionary = defs.get("mission_reports", {}).get(id, {})
		_check(defs.get("missions", {}).has(id) and not report.is_empty()
			and not report.has("destination_descriptors") and _base_id(defs, id) == roster[id],
			"stock road %s remains reportable with its base identity" % id)

	# Every destination is provisionally eligible for both finale positions.
	for id in defs.get("mission_reports", {}):
		var report: Dictionary = defs.mission_reports[id]
		if not report.has("destination_descriptors"):
			continue
		for length in [5, 10]:
			var offer := {"destination_id": id, "description": report.destination_descriptors[0],
				"length": length, "seed": 123}
			_check(commissions.call("valid_offer", defs, offer),
				"stock destination %s is eligible for the T%d finale" % [id, 3 if length == 5 else 6])

	for seed_value in [11, 9182]:
		var board: Array = commissions.call("board", defs, seed_value)
		_check(board.size() == 3, "stock tiered board is valid")
		if board.size() != 3:
			continue
		for index in [0, 2]:
			for branch in [0, 1]:
				_test_stock_path(defs, board[index], branch)


func _test_stock_path(defs: Dictionary, offer: Dictionary, branch: int) -> void:
	var label := "stock seed %s length %s branch %d" % [offer.seed, offer.length, branch]
	var run: Dictionary = adventure.call("start_commission", defs, offer, PARTY, 444)
	_check(run.get("phase") == "route", label + ": commission starts")
	if run.get("phase") != "route":
		return
	var tiers := [1, 1, 2, 2] if offer.length == 5 else [1, 1, 2, 2, 3, 4, 4, 5, 5]
	var visited_bases: Array = []
	var promised := ""
	for step in range(tiers.size()):
		var reports: Array = run.get("reports", [])
		_check(run.get("phase") == "route" and reports.size() == 2,
			label + ": slot %d offers a fork" % (step + 1))
		if reports.size() != 2:
			return
		var kinds: Array = []
		var fresh := false
		var fresh_available := false
		for candidate in defs.mission_reports:
			var entry: Dictionary = defs.mission_reports[candidate]
			if not entry.has("destination_descriptors") \
					and defs.missions[candidate].get("tier") == tiers[step] \
					and _base_id(defs, candidate) not in visited_bases:
				fresh_available = true
		for report in reports:
			var id := str(report.get("mission_id", ""))
			var info: Dictionary = defs.mission_reports.get(id, {})
			kinds.append(str(info.get("kind", "")))
			_check(defs.missions.get(id, {}).get("tier") == tiers[step] and not info.has("destination_descriptors"),
				label + ": slot %d offers tier %d road %s" % [step + 1, tiers[step], id])
			if _base_id(defs, id) not in visited_bases:
				fresh = true
			else:
				for candidate in defs.mission_reports:
					var entry: Dictionary = defs.mission_reports[candidate]
					if not entry.has("destination_descriptors") \
							and defs.missions[candidate].get("tier") == tiers[step] \
							and entry.get("kind") == info.get("kind"):
						_check(_base_id(defs, candidate) in visited_bases,
							label + ": slot %d repeats %s despite a fresh base of its kind" % [step + 1, id])
			if step == tiers.size() - 1:
				_check(report.get("hint_kind") == defs.mission_reports[offer.destination_id].kind
					and str(report.get("hint_text", "")).contains(defs.missions[offer.destination_id].title),
					label + ": both last-road clues name the selected finale")
		_check(not kinds[0].is_empty() and kinds[0] != kinds[1],
			label + ": slot %d offers different kinds" % (step + 1))
		_check(not fresh_available or fresh,
			label + ": slot %d offers a fresh base when one is available" % (step + 1))
		if not promised.is_empty():
			_check(kinds.count(promised) == 1,
				label + ": prior clue matches exactly one next option")
		var selected: Dictionary = reports[branch]
		var selected_id := str(selected.mission_id)
		promised = str(selected.get("hint_kind", ""))
		visited_bases.append(_base_id(defs, selected_id))
		run = adventure.call("choose_route", run, selected_id)
		var deployed: Dictionary = adventure.call("begin_mission", run)
		_check(deployed.get("mission", {}).get("mission_id") == selected_id,
			label + ": selected road deploys by exact mission ID")
		if deployed.get("phase") != "mission":
			return
		run = _victory(deployed, label)
		if run.get("phase") == "reward":
			var rewards: Array = run.get("reward_offers", [])
			if rewards.is_empty():
				_check(false, label + ": reward phase has a choice")
				return
			run = adventure.call("choose_reward", run, rewards[0].hero_id, rewards[0].upgrade_id)
	_check(run.get("phase") == "ready", label + ": selected destination follows the final road")
	if run.get("phase") != "ready":
		return
	var finale: Dictionary = adventure.call("begin_mission", run)
	_check(finale.get("phase") == "mission"
		and finale.get("mission", {}).get("mission_id") == offer.destination_id
		and run.get("mission_index") == offer.length - 1,
		label + ": selected destination deploys at the T%d finale" % [3 if offer.length == 5 else 6])
