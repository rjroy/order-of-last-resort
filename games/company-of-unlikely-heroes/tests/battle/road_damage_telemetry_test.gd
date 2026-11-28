extends SceneTree

const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Rules = preload("res://rules/rules.gd")
const Runner = preload("res://tools/road_balance/road_playtester.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_committed_overkill()
	_test_received_and_cap()
	if failures.is_empty():
		print("PASS: road damage telemetry")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _state(enemy_hp: int, hero_hp: int, skip_action := true) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.missions.fixture.objective = {"handler": "defeat_all", "team": "enemies",
		"text": "Defeat enemies", "victory_text": "Victory", "defeat_text": "Defeat",
		"victory_event": "Victory"}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Wiped"}]
	defs.encounters.fixture.deadline = 0
	defs.abilities.wizard_blast.targeting.merge({"range": 4, "direct": {"help": "Aim"}}, true)
	if not skip_action:
		defs.abilities.wizard_blast.params.status = "taunt"
	var rules := Rules.new()
	var state: Dictionary = rules.new_game(defs, "fixture")
	state.units = [
		{"id": "w", "character_id": "wizard", "position": Vector2i(1, 1),
			"hp": hero_hp, "max_hp": 10, "statuses": {}},
		{"id": "e", "character_id": "harpooner", "position": Vector2i(2, 1),
			"hp": enemy_hp, "max_hp": 10, "statuses": {}},
	]
	state.terrain = []
	state.obstacles = []
	state.orders = {}
	state.objective = {"handler": "defeat_all", "team": "enemies"}
	return state


func _test_committed_overkill() -> void:
	var result: Dictionary = Runner.new().run_case(Rules.new(), _state(1, 10), "wizard_first", 1)
	var rounds: Array = result.get("rounds", [])
	if rounds.size() != 1:
		failures.append("overkill fixture must commit one round")
		return
	var hits: Array = rounds[0].events.filter(func(event): return event.get("type") == "damage" and event.get("target_id") == "e")
	if hits.size() != 1:
		failures.append("overkill fixture must hit the enemy exactly once")
		return
	var standing_hits: Array = rounds[0].standing_events.filter(func(event): return event.get("type") == "damage" and event.get("target_id") == "w")
	_check(standing_hits.size() == 1,
		"standing forecast has an incoming hit that the committed blast prevents")
	_check(hits[0].get("amount") == 4, "legacy amount stays uncapped")
	_check(hits[0].get("hp_lost") == 1 and hits[0].get("target_team") == "enemies",
		"damage event reports capped HP removed and actual enemy faction")
	var metrics: Dictionary = result.get("metrics", {})
	_check(metrics.get("damage_dealt") == 1 and metrics.get("damage_received") == 0,
		"victory counts committed overkill once, not forecasts")


func _test_received_and_cap() -> void:
	# Keep the enemy alive and active; avoid the Blast's skip-action status.
	var state := _state(10, 1, false)
	var result: Dictionary = Runner.new().run_case(Rules.new(), state, "wizard_first", 1)
	var rounds: Array = result.get("rounds", [])
	if rounds.size() != 1:
		failures.append("incoming fixture must commit one round")
		return
	var hits: Array = rounds[0].events.filter(func(event): return event.get("type") == "damage" and event.get("target_id") == "w")
	if hits.size() != 1:
		failures.append("incoming fixture must hit hero exactly once")
		return
	_check(hits[0].get("amount") == 2 and hits[0].get("hp_lost") == 1 \
		and hits[0].get("target_team") == "heroes",
		"incoming overkill reports capped loss to actual hero faction")
	var metrics: Dictionary = result.get("metrics", {})
	_check(metrics.get("damage_dealt") == 4 and metrics.get("damage_received") == 1,
		"non-victory counts both committed damage totals")
