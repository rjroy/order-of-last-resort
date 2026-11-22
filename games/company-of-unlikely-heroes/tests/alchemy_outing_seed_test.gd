extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/alchemy_outing_seed_test.gd
# Deployment and settlement use the real adventure path; the board, missions,
# occurrence sequence, and outing seeds belong to this test.
const Catalog = preload("res://content/catalog.gd")
const Adventure = preload("res://adventure.gd")
var rules = preload("res://rules.gd").new()
var failures: Array[String] = []
const PARTY := ["alchemist", "healer", "wizard"]


func _initialize() -> void:
	var defs := _fixture()
	var errors: PackedStringArray = Catalog.validate(defs)
	_check(errors.is_empty(), "Seed fixture catalog validates: " + str(errors))
	if errors.is_empty():
		_test_unseeded_outings(defs)
		_test_authored_seed(defs)
	if failures.is_empty():
		print("PASS: alchemy outing seed")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _fixture() -> Dictionary:
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	defs.erase("upgrades")
	defs.boards["seed_fixture"] = {"width": 7, "height": 7, "default_tile": "stone",
		"tiles": [], "locations": {}}
	defs.encounters["seed_fixture"] = {"board": "seed_fixture",
		"party_slots": [[1, 1], [2, 1], [1, 2]],
		"placements": [{"id": "foe", "character": "harpooner", "at": [5, 5]}]}
	for id in ["seed_first", "seed_second"]:
		defs.missions[id] = {"title": "Seed fixture", "encounter": "seed_fixture",
			"objective": {"handler": "defeat_all", "text": "Defeat the foe.",
				"victory_text": "Won.", "defeat_text": "Lost.", "victory_event": "Won."},
			"failures": [{"handler": "party_wiped", "event": "Lost."}], "tier": 1}
	defs.adventures["seed_outing"] = {"label": "Seed fixture", "party_size": 3,
		"roster": PARTY.duplicate(), "missions": ["seed_first", "seed_second"]}
	return defs


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _reaction(plan: Dictionary) -> String:
	for event in plan.get("events", []):
		if event.get("type") == "alchemy_reaction":
			return str(event.get("category", "")) + "/" + str(event.get("reaction_id", ""))
	return ""


func _dose_sequence(opening: Dictionary, label: String) -> Array:
	var state := opening.duplicate(true)
	var alchemist := _entity(state, "alchemist")
	var patient := _entity(state, "healer")
	if alchemist.is_empty() or patient.is_empty():
		_check(false, label + ": deployed Alchemist and adjacent patient exist")
		return []
	# Avoid full-health behavior obscuring the primary effect.
	patient.hp = maxi(1, patient.max_hp - 2)
	var sequence := []
	for index in range(2):
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview(state, "alchemist", "alchemist_potion", "healer")
		_check(plan.get("valid", false) and state == before
			and plan == rules.preview(state, "alchemist", "alchemist_potion", "healer"),
			"%s: dose %d forecasts purely and repeats" % [label, index + 1])
		if not plan.get("valid", false):
			return []
		var reaction := _reaction(plan)
		_check(not reaction.is_empty(), label + ": dose reveals its reaction")
		if reaction.is_empty():
			return []
		sequence.append(reaction)
		var committed: Dictionary = rules.apply_plan(state, plan)
		_check(committed == plan.get("result") and state == before,
			"%s: dose %d commits exactly its forecast" % [label, index + 1])
		state = committed
	return sequence


func _run_outing(defs: Dictionary, seed_value: int) -> Array:
	var run: Dictionary = Adventure.start_adventure(defs, "seed_outing", PARTY, seed_value)
	_check(run.get("phase") == "ready", "Outing %d starts" % seed_value)
	if run.get("phase") != "ready":
		return []
	var sequences := []
	for index in range(2):
		run = Adventure.begin_mission(run)
		var state: Dictionary = run.get("mission", {})
		_check(run.get("phase") == "mission" and not state.is_empty(),
			"Outing %d occurrence %d deploys" % [seed_value, index + 1])
		if state.is_empty() or run.get("phase") != "mission":
			return []
		var sequence := _dose_sequence(state, "Outing %d occurrence %d" % [seed_value, index + 1])
		if sequence.size() != 2:
			return []
		sequences.append(sequence)
		if index == 0:
			var board := state.duplicate(true)
			_entity(board, "foe").hp = 0
			var plan: Dictionary = rules.preview_round(board)
			var terminal: Dictionary = rules.commit_round(board, plan)
			_check(terminal.get("outcome") == "victory", "Controlled first occurrence wins")
			if terminal.get("outcome") != "victory":
				return []
			run = Adventure.settle_mission(run, terminal)
			_check(run.get("phase") == "ready", "Victory advances to the next occurrence")
			if run.get("phase") != "ready":
				return []
	return sequences


func _test_unseeded_outings(defs: Dictionary) -> void:
	var first_occurrences := {}
	var second_occurrences := {}
	var different_occurrences := false
	for seed_value in [101, 202, 303, 404, 505, 606, 707, 808]:
		var actual := _run_outing(defs, seed_value)
		var replay := _run_outing(defs, seed_value)
		_check(actual.size() == 2 and actual == replay,
			"Same outing seed reproduces both occurrence dose sequences")
		if actual.size() != 2:
			continue
		first_occurrences[str(actual[0])] = true
		second_occurrences[str(actual[1])] = true
		if actual[0] != actual[1]:
			different_occurrences = true
	_check(first_occurrences.size() > 1 and second_occurrences.size() > 1,
		"Different outing seeds produce observably different dose sequences in each occurrence")
	_check(different_occurrences,
		"Repeated use of the same unseeded encounter does not always restart the dose sequence")


func _test_authored_seed(source: Dictionary) -> void:
	var defs := source.duplicate(true)
	defs.encounters.seed_fixture.seed = 47291
	var a := _run_outing(defs, 101)
	var b := _run_outing(defs, 808)
	_check(a.size() == 2 and b.size() == 2, "Explicitly seeded outings deploy both occurrences")
	if a.size() == 2 and b.size() == 2:
		_check(a[0] == a[1] and a == b,
			"Authored encounter seed preserves its exact dose sequence across occurrences and outings")
