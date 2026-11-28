extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/content/road_playtest_catalog_test.gd
const Catalog = preload("res://content/catalog.gd")
const Actions = preload("res://rules/actions.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")

# The first pair anchors the batch; the rest are checked as they are registered.
const REQUIRED = ["no_room_to_swing", "last_crate_on_the_road"]
const OPTIONAL = [
	"longbows_blind_spot", "friars_last_favor", "wrong_twin", "hired_hammer",
	"very_long_spear", "empty_helmets", "borrowed_armor", "big_windup",
]

var failures: Array[String] = []


func _initialize() -> void:
	_test_bell_runtime_isolation()
	_test_bell_requires_damageable_character()
	var loaded := Catalog.read_source(Catalog.DEFAULT_PATH)
	_check(not loaded.has("error"), "stock manifest loads: " + str(loaded.get("error", "")))
	if not loaded.has("error"):
		var defs: Dictionary = loaded.definitions
		for id in REQUIRED:
			_check(defs.missions.has(id), "stock manifest contains " + id)
		for id in REQUIRED + OPTIONAL:
			if defs.missions.has(id):
				_test_candidate(defs, id)
		_test_big_windup_family(defs)
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: road playtest catalog")
	quit(0 if failures.is_empty() else 1)


func _test_bell_requires_damageable_character() -> void:
	var defs: Dictionary = Fixture.definitions()
	defs.missions.fixture.objective = {"handler": "defeat_all", "team": "enemies",
		"text": "Defeat all", "victory_text": "Victory", "defeat_text": "Defeat",
		"victory_event": "Victory", "corpse_bell": {"character": "harpooner"}}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Defeat"}]
	_check(Catalog.validate(defs).is_empty(), "damageable bell character validates")
	defs.characters.harpooner.capabilities = []
	_check(not Catalog.validate(defs).is_empty(),
		"bell rejects a same-team character that cannot be damaged")


func _test_bell_runtime_isolation() -> void:
	var defs: Dictionary = Fixture.definitions()
	defs.missions.fixture.objective = {"handler": "defeat_all", "team": "enemies",
		"text": "Defeat all", "victory_text": "Victory", "defeat_text": "Defeat",
		"victory_event": "Victory", "corpse_bell": {"character": "harpooner"}}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Defeat"}]
	_check(Catalog.validate(defs).is_empty(), "clean bell authoring fixture validates")
	defs.missions.fixture.objective.corpse_bell.merge(
		{"spent": true, "due_round": 1, "position": [4, 3]})
	var errors: PackedStringArray = Catalog.validate(defs)
	if not errors.is_empty():
		return # Rejecting runtime-only authoring is also safe.
	var state: Dictionary = Catalog.build(defs, "fixture")
	_check(not state.is_empty(), "bell authoring fixture builds if accepted")
	if not state.is_empty():
		_check(state.objective.corpse_bell == {"character": "harpooner"},
			"authored bell runtime keys do not seed the battle snapshot")


func _test_big_windup_family(defs: Dictionary) -> void:
	var expected := {
		"big_windup": [2, 1, 1],
		"big_windup_t3": [3, 1, 2],
		"big_windup_t4": [4, 2, 1],
		"big_windup_t5": [5, 2, 2],
	}
	var family: Array = []
	for id in defs.missions:
		if id == "big_windup" or id.begins_with("big_windup_") \
				or defs.missions[id].get("base_mission_id") == "big_windup":
			family.append(id)
	family.sort()
	var expected_ids := expected.keys()
	expected_ids.sort()
	_check(family == expected_ids, "Big Windup family has exactly the four expected mission IDs")
	var profile := Catalog.profile(defs, "road_windup_bruiser")
	var strikes: Array = profile.get("traits", []).filter(
		func(spec): return spec.get("kind") == "big_windup")
	_check(int(profile.get("max_hp", 0)) > 0 and strikes.size() == 1 \
		and int(strikes[0].get("damage", 0)) > 0,
		"shared Windup Bruiser profile has positive HP and one damaging windup")
	for id in expected:
		_check(defs.missions.has(id), "Big Windup family contains " + id)
		if not defs.missions.has(id):
			continue
		var mission: Dictionary = defs.missions[id]
		_check(mission.get("tier") == expected[id][0], id + " has its assigned tier")
		if id != "big_windup":
			_check(mission.get("base_mission_id") == "big_windup",
				id + " identifies big_windup as its base")
		_check(not defs.get("mission_reports", {}).has(id),
			id + " remains outside commission selection")
		# The general candidate check verifies default launch and clean restart.
		if id != "big_windup":
			_test_candidate(defs, id)
		var party: Array = mission.get("default_party", [])
		if party.is_empty():
			continue
		var state := Catalog.build(defs, id, party)
		if state.is_empty():
			continue
		var bruisers := 0
		var grunts := 0
		var other_enemies := 0
		for unit in state.units:
			var unit_profile := Catalog.profile(defs, unit.character_id)
			if unit_profile.get("team") != "enemies":
				continue
			if unit.character_id == "road_windup_bruiser":
				bruisers += 1
				_check(unit_profile == profile, id + " uses the shared Windup Bruiser profile")
				_check(unit.hp == profile.get("max_hp") and unit.max_hp == profile.get("max_hp"),
					id + " uses the shared Bruiser HP without mission overrides")
			elif unit.character_id == "grunt":
				grunts += 1
			else:
				other_enemies += 1
		_check(bruisers == expected[id][1] and grunts == expected[id][2] and other_enemies == 0,
			id + " deploys exactly %d Windup Bruisers and %d grunts" % [expected[id][1], expected[id][2]])


func _test_candidate(defs: Dictionary, id: String) -> void:
	var party: Array = defs.missions[id].get("default_party", [])
	_check(not party.is_empty(), id + " has an authored standalone party")
	if party.is_empty():
		return
	var first := Catalog.build(defs, id, party)
	var fresh := Catalog.build(defs, id, party)
	_check(not first.is_empty() and not fresh.is_empty(), id + " builds independently")
	if first.is_empty() or fresh.is_empty():
		return
	_check(first.mission_id == id and first.round == 1 and first.outcome == "ongoing",
		id + " opens as a fresh ongoing mission")
	_check(first.units.size() >= party.size(), id + " deploys its party")
	for hero in party:
		_check(first.units.any(func(unit): return unit.id == hero),
			id + " deploys default hero " + hero)
	if id == "no_room_to_swing":
		_test_friendly_fire_sweep(defs, first)
	# A restart must not inherit changes made to an earlier world.
	first.units[0].hp = 0
	first.round = 9
	_check(fresh.round == 1 and fresh.units[0].hp > 0,
		id + " rebuilds without changes to the earlier world")


func _test_friendly_fire_sweep(defs: Dictionary, state: Dictionary) -> void:
	var enemies: Array = []
	var heroes: Array = []
	for unit in state.units:
		var profile := Catalog.profile(defs, unit.character_id)
		if profile.team == "enemies":
			enemies.append(unit)
		elif profile.team == "heroes":
			heroes.append(unit)
	_check(enemies.size() >= 2 and not heroes.is_empty(),
		"no_room_to_swing places a sweeper, enemy ally and hero")
	if enemies.size() < 2 or heroes.is_empty():
		return
	var found := false
	for actor in enemies:
		var profile := Catalog.profile(defs, actor.character_id)
		var behavior: Dictionary = defs.behaviors.get(profile.get("behavior", ""), {})
		for ability_id in Catalog.behavior_ability_ids(behavior):
			var ability: Dictionary = defs.abilities.get(ability_id, {})
			if ability_id not in profile.get("abilities", []) \
					or ability.get("handler") != "sweep" \
					or ability.get("targeting", {}).get("range") != 1:
				continue
			var ally: Dictionary = enemies[0] if enemies[0].id != actor.id else enemies[1]
			actor.position = Vector2i(3, 3)
			ally.position = Vector2i(3, 4)
			heroes[0].position = Vector2i(4, 3)
			var selected := Actions.selection(state, actor, ability_id, "", "")
			var recipients: Array = selected.get("recipients", [])
			if recipients.any(func(unit): return unit.id == ally.id) \
					and recipients.any(func(unit): return unit.id == heroes[0].id):
				found = true
	_check(found, "no_room_to_swing has an enemy-used range-1 sweep that hits friend and foe")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
