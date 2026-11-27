extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/smith_songs_summons_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
var rules := Rules.new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = Fixture.add_fixed_escort(Catalog.read_default().duplicate(true))
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.characters.necromancer.abilities = Catalog.profile(defs, "necromancer").abilities.duplicate()
	defs.characters.necromancer.abilities.append("necro_grave_bell")
	defs.encounters.test_escort.deadline = 100
	_test_sonnet()
	_test_chorus()
	_test_melody()
	_test_recall()
	_test_play_dead()
	_test_bell()
	_test_rally()
	if failures.is_empty():
		print("PASS: smith songs and summons")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp := 10, maximum := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": hp, "max_hp": maximum, "statuses": {}}


func _state() -> Dictionary:
	var s: Dictionary = rules.new_game(defs, "test_escort")
	s.width = 12
	s.height = 12
	s.terrain = []
	s.obstacles = []
	s.units = [_unit("blacksmith", "blacksmith", Vector2i(1, 1)),
		_unit("bard", "bard", Vector2i(3, 3)),
		_unit("necromancer", "necromancer", Vector2i(6, 6)),
		_unit("enemy", "harpooner", Vector2i(10, 9)),
		_unit("civilian", "ferryman", Vector2i(11, 10))]
	s.orders = {"blacksmith": "order_hold", "bard": "order_hold", "necromancer": "order_hold"}
	s.overrides = {}
	s.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return s


func _entity(s: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in s.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _living(s: Dictionary, character: String) -> Array:
	return s.get("units", []).filter(func(u: Dictionary) -> bool:
		return u.get("character_id") == character and u.get("hp", 0) > 0)


func _ids(choices: Array) -> Array:
	return choices.map(func(choice: Dictionary): return choice.get("id"))


func _act(s: Dictionary, actor: String, ability: String, target := "") -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview(s, actor, ability, target)
	_check(s == before and plan == rules.preview(s, actor, ability, target),
		ability + ": deterministic nonmutating forecast")
	_check(plan.get("valid", false), ability + ": legal forecast for " + target)
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.apply_plan(s, plan)
	_check(s == before and result == plan.get("result"), ability + ": commit matches forecast")
	return result


func _round(s: Dictionary, label: String) -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview_round(s)
	_check(plan.get("valid", false) and s == before and plan == rules.preview_round(s),
		label + ": repeatable pure round forecast")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.commit_round(s, plan)
	_check(result == plan.get("result") and s == before, label + ": round commit matches forecast")
	return result


func _test_sonnet() -> void:
	for standing in [false, true]:
		var s := _state()
		_entity(s, "bard").fitted_by = "blacksmith"
		_entity(s, "bard").upgrades = {"bard_sharper_notes": 1}
		_entity(s, "necromancer").hp = 4
		_check(_ids(rules.targets(s, "bard", "healing_sonnet")) == ["necromancer"],
			"Direct fitted Sonnet offers the wounded hero, not the full-health heroes or opponent")
		if standing:
			s.orders.bard = "order_healing_sonnet"
			s = _round(s, "standing Sonnet")
		else:
			s = _act(s, "bard", "healing_sonnet")
		if not s.is_empty():
			_check(_entity(s, "necromancer").hp == 6 and _entity(s, "enemy").hp == 10,
				"Fitted Sonnet heals the only wounded hero with Sharper Notes, not the opponent")
			_check(not _entity(s, "bard").has("fitted_by"), "Sonnet consumes fitting")
	var seeded := _state()
	seeded.rng_state = 12345
	_entity(seeded, "bard").fitted_by = "blacksmith"
	_entity(seeded, "blacksmith").hp = 4
	_entity(seeded, "necromancer").hp = 4
	var choices := _ids(rules.targets(seeded, "bard", "healing_sonnet"))
	_check("blacksmith" in choices and "necromancer" in choices and choices.size() == 2,
		"Direct fitted Sonnet offers both wounded heroes")
	var automatic := _act(seeded, "bard", "healing_sonnet")
	if not automatic.is_empty():
		_check((_entity(automatic, "blacksmith").hp == 5 and _entity(automatic, "necromancer").hp == 4)
			or (_entity(automatic, "blacksmith").hp == 4 and _entity(automatic, "necromancer").hp == 5),
			"Seeded automatic Sonnet heals exactly one wounded hero")
		_check(automatic.rng_state != seeded.rng_state, "Automatic Sonnet consumes its seeded draw")
	var fallback := _state()
	_entity(fallback, "bard").fitted_by = "blacksmith"
	fallback = _act(fallback, "bard", "healing_sonnet")
	if not fallback.is_empty():
		_check(_entity(fallback, "enemy").hp == 9 and _entity(fallback, "bard").get("fitted_by") == "blacksmith",
			"Unwounded company falls back to hostile Sonnet and retains fitting")


func _test_chorus() -> void:
	var s := _state()
	_entity(s, "bard").fitted_by = "blacksmith"
	_entity(s, "bard").upgrades = {"bard_sharper_notes": 1, "bard_house_lights": 1}
	_entity(s, "bard").hp = 5
	_entity(s, "blacksmith").position = Vector2i(3, 2)
	_entity(s, "blacksmith").hp = 5
	_entity(s, "necromancer").hp = 10
	# Either wounded soloist is adjacent to the other, so the draw is immaterial.
	s = _act(s, "bard", "bard_take_the_stage")
	if not s.is_empty():
		_check(_entity(s, "bard").hp == 7 and _entity(s, "blacksmith").hp == 7
			and _entity(s, "enemy").hp == 10, "Company Chorus heals both adjacent patients once")
		_check(not _entity(s, "bard").has("fitted_by"), "Company Chorus consumes fitting")


func _test_melody() -> void:
	var s := _state()
	_entity(s, "bard").fitted_by = "blacksmith"
	s = _act(s, "bard", "inspiring_melody")
	if s.is_empty():
		return
	_check(_entity(s, "enemy").statuses.is_empty(), "Fitted Melody does not make the opponent laugh")
	_check(not _entity(s, "bard").has("fitted_by"), "Fitted Melody spends fitting")
	# With only one deployed hero, the next actual performance must spend
	# the token on that hero, independent of random listener selection.
	s = _state()
	_entity(s, "blacksmith").hp = 0
	s.units.erase(_entity(s, "necromancer"))
	_entity(s, "bard").fitted_by = "blacksmith"
	s = _act(s, "bard", "inspiring_melody")
	if s.is_empty():
		return
	s = _act(s, "bard", "healing_sonnet")
	if s.is_empty():
		return
	_check(_entity(s, "enemy").hp == 8, "Inspired ordinary Sonnet adds one primary damage")
	s = _act(s, "bard", "healing_sonnet")
	if not s.is_empty():
		_check(_entity(s, "enemy").hp == 7, "Inspired is consumed by exactly one performance")


func _test_recall() -> void:
	var s := _state()
	_entity(s, "necromancer").upgrades = {"necromancer_spare_ribs": 1}
	s = _act(s, "necromancer", "summon_skeleton", "7,6")
	if s.is_empty() or _living(s, "skeleton").size() != 1:
		_check(false, "Skeleton fallback creates one skeleton")
		return
	var skeleton: Dictionary = _living(s, "skeleton")[0]
	var id: String = skeleton.id
	skeleton.position = Vector2i(9, 6)
	skeleton.hp = 1
	var before := skeleton.duplicate(true)
	_entity(s, "necromancer").fitted_by = "blacksmith"
	_check("6,5" in _ids(rules.targets(s, "necromancer", "summon_skeleton")),
		"Recall offers vacant adjacent landing while skeleton slot is full")
	s = _act(s, "necromancer", "summon_skeleton", "6,5")
	if not s.is_empty():
		var recalled := _entity(s, id)
		_check(_living(s, "skeleton").size() == 1 and recalled.get("position") == Vector2i(6, 5)
			and recalled.get("hp") == 1 and recalled.get("max_hp") == before.max_hp,
			"Recall moves the original wounded upgraded skeleton without healing or duplication")
		_check(not _entity(s, "necromancer").has("fitted_by"), "Recall consumes fitting")
	var fallback := _state()
	_entity(fallback, "necromancer").fitted_by = "blacksmith"
	fallback = _act(fallback, "necromancer", "summon_skeleton", "7,6")
	if not fallback.is_empty():
		_check(_living(fallback, "skeleton").size() == 1
			and _entity(fallback, "necromancer").get("fitted_by") == "blacksmith",
			"Without a skeleton ordinary summon retains fitting")


func _test_play_dead() -> void:
	var s := _state()
	s.units.append(_unit("corpse", "harpooner", Vector2i(7, 6), 0, 9))
	_entity(s, "necromancer").upgrades = {"necromancer_good_soil": 1, "necromancer_wake_reception": 1}
	s = _act(s, "necromancer", "raise_dead", "corpse")
	if s.is_empty() or _living(s, "zombie").size() != 1:
		_check(false, "Raise Dead creates zombie from test corpse")
		return
	_entity(s, "necromancer").fitted_by = "blacksmith"
	var enemy_hp: int = _entity(s, "enemy").hp
	s = _act(s, "necromancer", "raise_dead")
	if s.is_empty():
		return
	_check(_living(s, "zombie").is_empty(), "Play Dead frees zombie slot")
	_check(_entity(s, "enemy").hp == enemy_hp, "Play Dead does not cause Wake Reception")
	_check("corpse" in _ids(rules.targets(s, "necromancer", "raise_dead")),
		"Play Dead restores the original raisable corpse")
	s = _act(s, "necromancer", "raise_dead", "corpse")
	if not s.is_empty() and _living(s, "zombie").size() == 1:
		_check(_living(s, "zombie")[0].max_hp == 6,
			"Reraising uses original maximum once, then Good Soil once")


func _test_bell() -> void:
	var s := _state()
	_entity(s, "necromancer").fitted_by = "blacksmith"
	_entity(s, "bard").position = Vector2i(8, 6)
	s = _act(s, "necromancer", "necro_grave_bell")
	if not s.is_empty():
		_check(_entity(s, "bard").position == Vector2i(7, 6),
			"Dinner Bell pulls nearest eligible friend toward Crypter")
		_check(not _entity(s, "necromancer").has("fitted_by"), "Dinner Bell spends fitting")


func _test_rally() -> void:
	var s := _state()
	_entity(s, "necromancer").upgrades = {"necromancer_say_hello_to_that_one": 1}
	s = _act(s, "necromancer", "summon_skeleton", "7,6")
	if s.is_empty():
		return
	_entity(s, "necromancer").fitted_by = "blacksmith"
	var targets := _ids(rules.targets(s, "necromancer", "necromancer_say_hello_to_that_one"))
	_check("bard" in targets and "necromancer" in targets and "enemy" not in targets
		and "civilian" not in targets, "Rally targets living heroes including Crypter, not foes or civilians")
	s = _act(s, "necromancer", "necromancer_say_hello_to_that_one", "bard")
	if not s.is_empty():
		_check(not _entity(s, "necromancer").has("fitted_by"), "Rally spends fitting")
