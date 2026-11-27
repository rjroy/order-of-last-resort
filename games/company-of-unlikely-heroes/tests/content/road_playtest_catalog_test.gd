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
