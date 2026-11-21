extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_routes_test.gd
# Route transitions use test-owned mission reports and cloned, easily staged
# combat missions. The catalog smoke test separately exercises authored data.
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
const PARTY := ["wizard", "knight", "healer"]

var failures: Array[String] = []
var commissions: Script
var adventure: Script
var rules = Rules.new()


func _initialize() -> void:
	if not ResourceLoader.exists("res://commissions.gd"):
		_check(false, "Missing commissions.gd")
	else:
		commissions = load("res://commissions.gd")
		adventure = load("res://adventure.gd")
		if not commissions.has_method("board") or not adventure.has_method("start_commission") \
				or not adventure.has_method("choose_route"):
			_check(false, "Commission board and adventure route APIs are available")
		else:
			var fixture := _fixture()
			_test_board(fixture, "controlled")
			_test_board(Catalog.read_default(), "authored")
			for seed_value in [11, 9182]:
				for length_index in [0, 2]:
					for branch in [0, 1]:
						_test_route(fixture, seed_value, length_index, branch)
			_test_branch_promises(fixture)
			_test_authored_opening()
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
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	var combat: Dictionary = defs.missions.shield_wall.duplicate(true)
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
	defs["commission_settings"] = {"roster_adventure": "first_outing"}
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


func _test_authored_opening() -> void:
	var defs: Dictionary = Catalog.read_default()
	var offers: Array = commissions.call("board", defs, 101)
	if offers.is_empty():
		return
	var run: Dictionary = adventure.call("start_commission", defs, offers[0], PARTY, 42)
	_check(run.get("phase") == "route" and run.get("reports", []).size() == 2,
		"Authored catalog supports a commission opening and route pair")
