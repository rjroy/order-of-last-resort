extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/smith_undead_lifecycle_test.gd
const Catalog = preload("res://content/catalog.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Rules = preload("res://rules/rules.gd")
var rules := Rules.new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = Fixture.add_fixed_escort(Catalog.read_default().duplicate(true))
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.behaviors.skeleton_greetings.params.greetings = ["wave"]
	defs.characters.zombie.traits = defs.characters.bomber.traits.duplicate(true)
	defs.encounters.test_escort.deadline = 100
	_test_recall_initiative()
	_test_play_dead_before_slot()
	_test_rally_lifecycle()
	if failures.is_empty():
		print("PASS: smith undead lifecycle")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp := 20, maximum := 20) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": hp, "max_hp": maximum, "statuses": {}, "upgrades": {}}


func _entity(s: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in s.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _living(s: Dictionary, character: String) -> Array:
	return s.get("units", []).filter(func(unit: Dictionary):
		return unit.get("character_id") == character and unit.get("hp", 0) > 0)


func _state() -> Dictionary:
	var s: Dictionary = rules.new_game(defs, "test_escort")
	s.width = 12
	s.height = 12
	s.default_tile = "stone"
	s.terrain = []
	s.obstacles = []
	s.units = [_unit("necromancer", "necromancer", Vector2i(5, 5)),
		_unit("knight", "knight", Vector2i(1, 1)),
		_unit("blacksmith", "blacksmith", Vector2i(1, 2)),
		_unit("enemy", "harpooner", Vector2i(7, 5)),
		_unit("civilian", "ferryman", Vector2i(11, 10))]
	s.party = ["necromancer", "knight", "blacksmith"]
	s.orders = {"necromancer": "order_hold", "knight": "order_hold", "blacksmith": "order_hold"}
	s.overrides = {}
	s.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	s.rng_state = 12345
	return s


func _act(s: Dictionary, actor: String, ability: String, target := "") -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview(s, actor, ability, target)
	_check(plan.get("valid", false) and s == before and plan == rules.preview(s, actor, ability, target),
		ability + " has a legal, pure, repeatable preview")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.apply_plan(s, plan)
	_check(s == before and result == plan.get("result"), ability + " commits its preview")
	return plan


func _round(s: Dictionary, label: String) -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview_round(s)
	_check(plan.get("valid", false) and s == before and plan == rules.preview_round(s),
		label + " has a legal, pure, repeatable forecast")
	if not plan.get("valid", false):
		return {}
	_check(rules.commit_round(s, plan) == plan.get("result") and s == before,
		label + " commits its forecast")
	return plan


func _events(plan: Dictionary, kind: String, id := "") -> Array:
	return plan.get("events", []).filter(func(event: Dictionary):
		return event.get("type") == kind and (id.is_empty() or event.get("unit_id") == id))


func _test_recall_initiative() -> void:
	var s := _state()
	_entity(s, "necromancer").upgrades = {"necromancer_spare_ribs": 1}
	var made := _act(s, "necromancer", "summon_skeleton", "6,5")
	if made.is_empty() or _living(made.result, "skeleton").size() != 1:
		_check(false, "Recall fixture creates its original skeleton")
		return
	s = made.result
	var skeleton: Dictionary = _living(s, "skeleton")[0]
	var id: String = skeleton.id
	skeleton.position = Vector2i(9, 5)
	skeleton.hp = 1
	_entity(s, "necromancer").fitted_by = "blacksmith"
	s = rules.choose_manual(s, "necromancer", "summon_skeleton", "6,5")
	var plan := _round(s, "Recall in captured initiative")
	if plan.is_empty():
		return
	var events: Array = plan.events
	var recall := events.find_custom(func(e: Dictionary): return e.get("type") == "recall")
	var waves := _events(plan, "wave", id)
	var wave := events.find_custom(func(e: Dictionary):
		return e.get("type") == "wave" and e.get("unit_id") == id)
	var knight := events.find_custom(func(e: Dictionary): return e.get("unit_id") == "knight")
	_check(recall >= 0 and waves.size() == 1 and wave > recall and knight > wave,
		"Original recalled skeleton greets exactly once after Crypter and before next deployed hero")
	_check(_entity(plan.result, id).get("hp") == 1 and _entity(plan.result, id).get("max_hp") == 2
		and _entity(plan.result, "enemy").hp == 19,
		"Recall retains original wounded upgraded skeleton and its Wave actually hits")
	var fresh := _state()
	fresh = rules.choose_manual(fresh, "necromancer", "summon_skeleton", "6,5")
	var spawned := _round(fresh, "New summon initiative")
	if spawned.is_empty():
		return
	_check(_living(spawned.result, "skeleton").size() == 1 and _events(spawned, "wave").is_empty()
		and _entity(spawned.result, "enemy").hp == 20,
		"New skeleton does not greet in its summoning round")
	var following := _round(spawned.result, "New summon following round")
	if not following.is_empty():
		_check(_events(following, "wave").size() == 1 and _entity(following.result, "enemy").hp == 19,
			"New skeleton enters initiative and greets on the following round")


func _test_play_dead_before_slot() -> void:
	var s := _state()
	_entity(s, "necromancer").upgrades = {"necromancer_good_soil": 1,
		"necromancer_wake_reception": 1}
	s.units.append(_unit("corpse", "bomber", Vector2i(6, 5), 0, 9))
	var raised := _act(s, "necromancer", "raise_dead", "corpse")
	if raised.is_empty() or _living(raised.result, "zombie").size() != 1:
		_check(false, "Play Dead fixture raises original bomber corpse")
		return
	s = raised.result
	var zombie: Dictionary = _living(s, "zombie")[0]
	var id: String = zombie.id
	_check(zombie.max_hp == 6, "Good Soil increases the original nine-max corpse once")
	# Positive control: this test-owned zombie can trigger both death effects.
	var control := s.duplicate(true)
	_entity(control, id).hp = 2
	var killed := _act(control, "enemy", "enemy_attack", id)
	if not killed.is_empty():
		_check(_events(killed, "death_blast", id).size() == 1
			and _living(killed.result, "skeleton").size() == 1,
			"Combat death positive control triggers zombie blast and Wake Reception")
	_entity(s, "necromancer").fitted_by = "blacksmith"
	var enemy_hp: int = _entity(s, "enemy").hp
	var actor_hp: int = _entity(s, "necromancer").hp
	s = rules.choose_manual(s, "necromancer", "raise_dead")
	var plan := _round(s, "Play Dead before zombie initiative")
	if plan.is_empty():
		return
	_check(_events(plan, "play_dead").size() == 1 and _living(plan.result, "zombie").is_empty(),
		"Play Dead retires the zombie before its captured slot")
	_check(not plan.events.any(func(e: Dictionary): return e.get("unit_id") == id)
		and _events(plan, "death_blast").is_empty() and _living(plan.result, "skeleton").is_empty()
		and not _entity(plan.result, "necromancer").get("wake_reception_used", false),
		"Voluntary retirement produces no zombie activation, death blast or Wake Reception")
	_check(_entity(plan.result, "enemy").hp == enemy_hp and _entity(plan.result, "necromancer").hp == actor_hp,
		"Play Dead causes no greeting or blast damage")
	_check(_entity(plan.result, "corpse").max_hp == 9
		and not _entity(plan.result, "corpse").get("corpse_consumed", false),
		"Play Dead restores the original raisable corpse and original maximum")
	var reraised := _act(plan.result, "necromancer", "raise_dead", "corpse")
	if not reraised.is_empty():
		var zombies := _living(reraised.result, "zombie")
		_check(zombies.size() == 1 and zombies[0].hp == 6 and zombies[0].max_hp == 6,
			"Reraising applies Good Soil once to original corpse maximum")


func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _test_rally_lifecycle() -> void:
	var s := _state()
	_entity(s, "necromancer").position = Vector2i(1, 1)
	_entity(s, "necromancer").upgrades = {"necromancer_say_hello_to_that_one": 1}
	_entity(s, "knight").position = Vector2i(9, 5)
	_entity(s, "blacksmith").position = Vector2i(2, 8)
	_entity(s, "enemy").position = Vector2i(10, 10)
	var made := _act(s, "necromancer", "summon_skeleton", "2,1")
	if made.is_empty() or _living(made.result, "skeleton").size() != 1:
		return
	s = made.result
	var id: String = _living(s, "skeleton")[0].id
	_entity(s, id).position = Vector2i(5, 5)
	_entity(s, "necromancer").fitted_by = "blacksmith"
	var rally := _act(s, "necromancer", "necromancer_say_hello_to_that_one", "knight")
	if rally.is_empty():
		return
	var plan := _round(rally.result, "First rally pursuit")
	if plan.is_empty():
		return
	_check(_dist(_entity(plan.result, id).position, Vector2i(9, 5)) < 4,
		"Summon approaches the first rally hero rather than the distant enemy")
	s = plan.result
	var adjacent := s.duplicate(true)
	_entity(adjacent, id).position = Vector2i(8, 5)
	_entity(adjacent, "enemy").position = Vector2i(8, 6)
	var enemy_hp: int = _entity(adjacent, "enemy").hp
	var knight_hp: int = _entity(adjacent, "knight").hp
	var greeting := _round(adjacent, "Greeting while rallied")
	if not greeting.is_empty():
		_check(_events(greeting, "wave", id).size() == 1
			and _entity(greeting.result, "enemy").hp == enemy_hp - 1
			and _entity(greeting.result, "knight").hp == knight_hp - 1,
			"Rallied skeleton still greets and its Wave affects adjacent friend and foe")
		adjacent = greeting.result
		_entity(adjacent, "enemy").position = Vector2i(10, 10)
		var stopped := _round(adjacent, "Adjacent rally stop")
		if not stopped.is_empty():
			_check(_entity(stopped.result, id).position == Vector2i(8, 5),
				"Rallied skeleton stops when adjacent to its hero")
	_entity(s, "necromancer").fitted_by = "blacksmith"
	rally = _act(s, "necromancer", "necromancer_say_hello_to_that_one", "blacksmith")
	if rally.is_empty():
		return
	var from: Vector2i = _entity(rally.result, id).position
	plan = _round(rally.result, "Replacement rally pursuit")
	if plan.is_empty():
		return
	_check(_dist(_entity(plan.result, id).position, Vector2i(2, 8)) < _dist(from, Vector2i(2, 8)),
		"Replacement rally changes actual pursuit toward the second hero")
	s = plan.result
	_entity(s, "blacksmith").hp = 2
	_entity(s, "enemy").position = Vector2i(3, 8)
	var killed := _act(s, "enemy", "enemy_attack", "blacksmith")
	if killed.is_empty():
		return
	s = killed.result
	_check(_entity(s, "blacksmith").hp == 0, "Controlled attack kills the rally target")
	_entity(s, "enemy").position = Vector2i(9, 5)
	_entity(s, id).position = Vector2i(5, 5)
	plan = _round(s, "Dead rally target")
	if plan.is_empty():
		return
	_check(_dist(_entity(plan.result, id).position, Vector2i(9, 5)) < 4,
		"After rally target dies summon resumes opponent pursuit")
	s = plan.result
	_entity(s, id).position = Vector2i(5, 5)
	_entity(s, "enemy").position = Vector2i(2, 5)
	var nominate := _act(s, "necromancer", "necromancer_say_hello_to_that_one", "enemy")
	if nominate.is_empty():
		return
	plan = _round(nominate.result, "Ordinary nomination after rally")
	if plan.is_empty():
		return
	_check(_dist(_entity(plan.result, id).position, Vector2i(2, 5)) < 3,
		"Ordinary nomination replaces rally and directs summon toward opponent")
	s = plan.result
	_entity(s, id).position = Vector2i(3, 5)
	var hp: int = _entity(s, "enemy").hp
	plan = _round(s, "Nominated greeting")
	if not plan.is_empty():
		_check(_events(plan, "wave", id).size() == 1 and _entity(plan.result, "enemy").hp == hp - 1,
			"Nominated summon actually greets the adjacent opponent")
