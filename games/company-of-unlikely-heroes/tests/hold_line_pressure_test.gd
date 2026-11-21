extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/hold_line_pressure_test.gd
const Catalog = preload("res://content/catalog.gd")
const Board = preload("res://rules/board.gd")
const Rules = preload("res://rules.gd")
const PASSIVE_TRIO := ["healer", "knight", "wizard"]

var rules := Rules.new()
var failures: Array[String] = []


func _initialize() -> void:
	var definitions: Dictionary = Catalog.read_default()
	_test_passive_trio(definitions)
	_test_reserve_lifecycle(definitions)
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: Hold the Line pressure")
	quit(0 if failures.is_empty() else 1)


func _test_passive_trio(definitions: Dictionary) -> void:
	# No manual commands or order changes: this deployment used to end the fight in round three.
	var state := Rules.open_mission(definitions, "hold_the_line", PASSIVE_TRIO)
	_check(not state.is_empty(), "Hold the Line opens with the passive trio")
	if state.is_empty():
		return
	var opening_ids: Array = Board.occupants(state, {"teams": ["enemies"]}).map(
		func(unit: Dictionary) -> String: return unit.id)
	for round_number in range(1, 7):
		var plan := rules.preview_round(state)
		_check(plan.valid, "Valid forecast for round %d" % round_number)
		if not plan.valid:
			return
		var next := rules.commit_round(state, plan)
		if round_number == 3:
			_check(opening_ids.all(func(id: String) -> bool: return not Board.alive(Board.entity(next, id))),
				"This standing-orders trio still clears the initial attackers by round three")
		if round_number >= 4:
			_check(plan.events.any(func(event: Dictionary) -> bool:
				return event.type == "damage" and event.get("amount", 0) > 0 \
					and Board.team(next, Board.entity(next, event.get("source_id", ""))) == "enemies" \
					and event.get("target_id") in PASSIVE_TRIO),
				"An enemy actually damages the company in round %d" % round_number)
		_check(next.outcome == ("victory" if round_number == 6 else "ongoing"),
			"The passive trio survives to round six, not ending early (round %d)" % round_number)
		if next.outcome != "ongoing":
			return
		state = next


func _test_reserve_lifecycle(definitions: Dictionary) -> void:
	var custom := definitions.duplicate(true)
	var encounter: Dictionary = custom.encounters.frontier_line
	encounter.placements = [
		{"id": "necromancer_skeleton", "character": "archer", "at": [2, 1]},
		{"id": "unblocked_archer", "character": "archer", "at": [4, 3]},
	]
	var objective: Dictionary = custom.missions.hold_the_line.objective
	objective.reserve_placements = ["necromancer_skeleton", "unblocked_archer"]
	objective.reserve_round = 2
	var state := Rules.open_mission(custom, "hold_the_line", ["necromancer", "knight", "wizard"])
	_check(not state.is_empty(), "Controlled survival encounter with custom reserve IDs opens")
	if state.is_empty():
		return
	var reserve_id := "necromancer_skeleton"
	var entry := Vector2i(2, 1)
	_check(Board.entity(state, reserve_id).is_empty() and not rules.can_act(state, reserve_id),
		"A reserve is off-board and cannot act before arrival")
	_check(Board.occupants(state, {"teams": ["enemies"]}).is_empty()
		and Board.corpses(state, {"teams": ["enemies"]}).is_empty()
		and not rules.preview(state, "wizard", "wizard_pull", "unblocked_archer").valid,
		"Off-board reserves are neither living targets nor raiseable corpses")
	_check(Board.is_vacant(state, entry), "A waiting reserve does not block its entry cell")
	_check("round 2 at C2, E4" in str(rules.objective_progress(state).get("text", "")),
		"Opening progress telegraphs the authored arrival round and entry cells")
	var summon := rules.preview(state, "necromancer", "summon_skeleton", "2,1")
	_check(summon.valid and not Board.entity(summon.result, reserve_id + "_2").is_empty(),
		"Summon may occupy the waiting reserve's tile, but must not reuse its custom ID")

	# The Necromancer uses the entry tile, then vacates it on the following round.
	state = rules.choose_manual(state, "necromancer", "move", "2,1")
	var before := state.duplicate(true)
	var plan := rules.preview_round(state)
	_check(state == before and plan == rules.preview_round(state), "Reserve forecast leaves source state unchanged")
	_check(_arrivals(plan) == ["unblocked_archer"], "Only the vacant entry receives a reserve for round two")
	_check(not _acted(plan, "unblocked_archer"), "The arriving enemy cannot act in the previous round")
	state = rules.commit_round(state, plan)
	_check(Board.entity(state, "necromancer").position == entry and Board.entity(state, reserve_id).is_empty(),
		"A blocked reserve waits without displacing the hero")
	_check(rules.preview(state, "wizard", "wizard_pull", "unblocked_archer").valid,
		"An arrived reserve becomes a normal action target")
	_check("waiting for C2 to clear" in str(rules.objective_progress(state).get("text", "")),
		"Progress identifies which entry is still blocked")
	state = rules.choose_manual(state, "necromancer", "move", "3,1")
	plan = rules.preview_round(state)
	_check(_arrivals(plan) == [reserve_id], "The deferred reserve enters once its tile is clear")
	_check(_acted(plan, "unblocked_archer") and not _acted(plan, reserve_id),
		"Only the reserve already on the board takes a turn")
	state = rules.commit_round(state, plan)
	_check(Board.alive(Board.entity(state, reserve_id)) and state.objective.reserves.is_empty(),
		"Each admitted actor moves from the reserve roster to the active roster exactly once")

	var wipe := before.duplicate(true)
	for id in wipe.party:
		Board.entity(wipe, id).hp = 0
	plan = rules.preview_round(wipe)
	_check(plan.result.outcome == "defeat" and _arrivals(plan).is_empty(),
		"Party wipe resolves without announcing reserves for a round that never starts")


func _arrivals(plan: Dictionary) -> Array:
	return plan.events.filter(func(event: Dictionary) -> bool: return event.type == "reserve_arrival").map(
		func(event: Dictionary) -> String: return event.unit_id)


func _acted(plan: Dictionary, actor: String) -> bool:
	return plan.events.any(func(event: Dictionary) -> bool:
		return event.has("ability_id") and actor in [event.get("unit_id"), event.get("source_id")])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
