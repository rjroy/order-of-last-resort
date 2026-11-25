extends SceneTree

# Run with: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_tactical_conversions_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
var rules := Rules.new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(Catalog.read_default())
	defs.abilities.healer_bonk.params.damage = 2
	defs.abilities.healer_heal.params.amount = 3
	defs.abilities.wizard_blast.params.damage = 4
	defs.abilities.enemy_attack.params.damage = 4
	defs.abilities.healer_field_dressing.params.amount = 2
	defs.statuses.aura.params.range = 1
	defs.characters.grunt.abilities = Catalog.profile(defs, "grunt").abilities.duplicate()
	if "enemy_attack" not in defs.characters.grunt.abilities:
		defs.characters.grunt.abilities.append("enemy_attack")
	for hero in ["healer", "wizard", "rogue", "knight", "alchemist", "bard"]:
		defs.characters[hero].abilities = Catalog.profile(defs, hero).abilities.duplicate()
	for row in [["knight", "healer_bonk"], ["healer", "wizard_blast"],
			["wizard", "rogue_confusing_dodge"], ["alchemist", "wizard_pull"],
			["bard", "knight_push"], ["healer", "healer_field_dressing"],
			["wizard", "wizard_ring_sparks"], ["rogue", "rogue_tripwire"],
			["knight", "knight_rescue_line"]]:
		if row[1] not in defs.characters[row[0]].abilities:
			defs.characters[row[0]].abilities.append(row[1])
	_test_bonk("healer")
	_test_bonk("knight")
	_test_heal()
	_test_blast("wizard")
	_test_blast("healer")
	_test_pull("wizard")
	_test_pull("alchemist")
	_test_wasnt_me()
	_test_dodge("rogue")
	_test_dodge("wizard")
	_test_rescue()
	_test_dressing()
	_test_ring()
	_test_tripwire()
	_test_throw()
	_test_bard_push()
	_test_primary_bonus_reflection()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: smith tactical conversions")
	quit(0 if failures.is_empty() else 1)


func _unit(id: String, character: String, pos: Vector2i, hp := 20) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos, "hp": hp,
		"max_hp": 20, "statuses": {}, "upgrades": {}}


func _state(hero: String) -> Dictionary:
	var s: Dictionary = rules.new_game(defs, "test_escort")
	s.width = 12
	s.height = 12
	s.default_tile = "stone"
	s.terrain = []
	s.obstacles = []
	s.units = [_unit("smith", "blacksmith", Vector2i(0, 0)),
		_unit("actor", hero, Vector2i(4, 4)),
		_unit("friend", "healer" if hero != "healer" else "knight", Vector2i(5, 4), 10),
		_unit("enemy", "grunt", Vector2i(7, 4))]
	_find(s, "actor").fitted_by = "smith"
	s.orders = {}
	s.overrides = {}
	s.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	s.rng_state = 12345
	return s


func _find(s: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in s.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _action(s: Dictionary, ability: String, target := "") -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview(s, "actor", ability, target)
	_check(s == before and plan == rules.preview(s, "actor", ability, target),
		ability + ": preview is repeatable and immutable")
	_check(plan.get("valid", false), ability + ": alternate action is legal for " + target)
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.apply_plan(s, plan)
	_check(result == plan.get("result") and s == before, ability + ": commit equals preview without mutation")
	_check(not _find(result, "actor").has("fitted_by"), ability + ": alternate consumes fitting")
	return result


func _test_bonk(hero: String) -> void:
	var s := _state(hero)
	var choices: Array = rules.targets(s, "actor", "healer_bonk")
	_check(choices.any(func(c: Dictionary): return c.id == "friend"),
		"healer_bonk (%s): offers other hero as protective tap target" % hero)
	var result := _action(s, "healer_bonk", "friend")
	if result.is_empty():
		return
	_check(_find(result, "friend").hp == 10, "healer_bonk: tap does not damage the hero")
	_find(result, "enemy").position = Vector2i(6, 4)
	var hit: Dictionary = rules.preview(result, "enemy", "enemy_attack", "friend")
	if hit.get("valid", false):
		_check(_find(hit.result, "friend").hp == 8, "healer_bonk: cover absorbs two from next hit")
	else:
		_check(false, "healer_bonk: controlled enemy hit is legal")
	var uncovered := result.duplicate(true)
	_find(uncovered, "friend").statuses.erase("keep_your_head_down")
	var plain_hit: Dictionary = rules.preview(uncovered, "enemy", "enemy_attack", "friend")
	_check(plain_hit.get("valid", false) and _find(plain_hit.get("result", {}), "friend").get("hp", -1) == 6,
		"healer_bonk: same controlled hit deals four without cover")


func _test_heal() -> void:
	var s := _state("healer")
	_find(s, "actor").upgrades = {"healer_heal_1": 1}
	var result := _action(s, "healer_heal")
	if not result.is_empty():
		_check(_find(result, "enemy").hp == 16 and _find(result, "friend").hp == 10,
			"healer_heal: Doctor's Orders damages nearest opponent for upgraded heal amount")


func _test_blast(hero: String) -> void:
	var s := _state(hero)
	var result := _action(s, "wizard_blast")
	if not result.is_empty():
		_check(_find(result, "friend").hp == 14 and _find(result, "enemy").hp == 20,
			"wizard_blast (%s): Mending Blast heals nearest wounded hero by four" % hero)
	s = _state(hero)
	_find(s, "friend").hp = 20
	var plan: Dictionary = rules.preview(s, "actor", "wizard_blast")
	_check(plan.get("valid", false), "wizard_blast: ordinary fallback is legal without patients")
	if plan.get("valid", false):
		_check(_find(plan.result, "actor").get("fitted_by") == "smith"
			and _find(plan.result, "friend").hp == 16,
			"wizard_blast: fallback hits nearest friend and retains fitting")


func _test_pull(hero: String) -> void:
	var s := _state(hero)
	var result := _action(s, "wizard_pull", "enemy")
	if not result.is_empty():
		_check(_find(result, "enemy").position == Vector2i(8, 4)
			and _find(result, "actor").position == Vector2i(4, 4)
			and _find(result, "actor").hp == 20,
			"wizard_pull (%s): Send-Off shoves without recoil" % hero)


func _test_wasnt_me() -> void:
	var s := _state("rogue")
	_find(s, "enemy").position = Vector2i(4, 5)
	_find(s, "friend").position = Vector2i(0, 3)
	var result := _action(s, "rogue_wasnt_me", "enemy")
	if not result.is_empty():
		_check(_find(result, "enemy").hp == 18, "rogue_wasnt_me: It Was Me bonks isolated opponent for two")


func _test_dodge(hero: String) -> void:
	var s := _state(hero)
	_find(s, "friend").position = Vector2i(10, 10)
	var result := _action(s, "rogue_confusing_dodge")
	if not result.is_empty():
		_check(_find(result, "enemy").position == Vector2i(7, 4)
			and _find(result, "actor").position == Vector2i(6, 4),
			"rogue_confusing_dodge (%s): Clear Jump lands next to opponent without swap" % hero)


func _test_rescue() -> void:
	var s := _state("knight")
	_find(s, "friend").position = Vector2i(6, 4)
	_find(s, "enemy").position = Vector2i(9, 4)
	var result := _action(s, "knight_rescue_line", "friend")
	if not result.is_empty():
		_check(_find(result, "friend").position == Vector2i(7, 4),
			"knight_rescue_line: Safety Distance moves friend away")


func _test_dressing() -> void:
	var s := _state("healer")
	_find(s, "enemy").position = Vector2i(4, 5)
	var result := _action(s, "healer_field_dressing", "enemy")
	if not result.is_empty():
		_check(_find(result, "enemy").hp == 18, "healer_field_dressing: Unpick the Stitch deals two")


func _test_ring() -> void:
	var s := _state("wizard")
	_find(s, "enemy").position = Vector2i(4, 5)
	var result := _action(s, "wizard_ring_sparks")
	if not result.is_empty():
		_check(_find(result, "friend").hp == 12 and _find(result, "enemy").hp == 20,
			"wizard_ring_sparks: Ring of Salve heals friend, does not damage enemy")


func _test_tripwire() -> void:
	var s := _state("rogue")
	_find(s, "friend").statuses["tripwire_tangled"] = {"remaining": 2}
	var result := _action(s, "rogue_tripwire")
	if not result.is_empty():
		_check(not _find(result, "friend").statuses.has("tripwire_tangled"),
			"rogue_tripwire: Cut the Wire removes friendly movement hold")


func _test_throw() -> void:
	var s := _state("knight")
	_find(s, "actor").upgrades = {"knight_shield_throw": 1}
	var result := _action(s, "knight_shield_throw", "friend")
	if not result.is_empty():
		_check(_find(result, "friend").hp == 10
			and _find(result, "actor").get("shield_position") == Vector2i(5, 4),
			"knight_shield_throw: Lend a Shield protects without damage and drops shield")


func _test_bard_push() -> void:
	var s := _state("bard")
	var result := _action(s, "knight_push", "enemy")
	if not result.is_empty():
		_check(_find(result, "enemy").position == Vector2i(6, 4),
			"knight_push: borrowed Bard Push converts to Pull")


func _test_primary_bonus_reflection() -> void:
	for row in [["rogue", "rogue_wasnt_me"], ["healer", "healer_field_dressing"]]:
		for bonus_kind in ["fine_adjustment", "inspired"]:
			for guarded in [false, true]:
				var hero: String = row[0]
				var ability: String = row[1]
				var label := "%s/%s/guard=%s" % [ability, bonus_kind, guarded]
				var s := _state(hero)
				_find(s, "friend").character_id = "knight"
				_find(s, "friend").position = Vector2i(5, 5)
				_find(s, "enemy").position = Vector2i(5, 4)
				s.units.append(_unit("reflection_victim", "grunt", Vector2i(6, 4)))
				if bonus_kind == "fine_adjustment":
					_find(s, "smith").upgrades = {"smith_fine_adjustment": 1}
				else:
					_find(s, "actor").statuses.inspired = {"source_id": "smith"}
				if guarded:
					var guard: Dictionary = rules.preview(s, "friend", "knight_aura")
					_check(guard.get("valid", false), label + ": ordinary Guard is legal")
					if not guard.get("valid", false):
						continue
					s = rules.apply_plan(s, guard)
					_check(_find(s, "friend").statuses.has("aura"), label + ": ordinary Guard creates aura")
				var before := s.duplicate(true)
				var attack: Dictionary = rules.preview(s, "actor", ability, "enemy")
				_check(attack.get("valid", false) and s == before
					and attack == rules.preview(s, "actor", ability, "enemy"),
					label + ": alternate attack is legal and forecast is pure")
				if not attack.get("valid", false):
					continue
				var result: Dictionary = rules.apply_plan(s, attack)
				_check(s == before and result == attack.get("result"), label + ": commit equals forecast")
				_check(not _find(result, "actor").has("fitted_by")
					and not _find(result, "actor").statuses.has("inspired"),
					label + ": successful alternate spends fitting and any Inspiration")
				if guarded:
					_check(attack.events.any(func(event: Dictionary): return event.get("type") == "reflect" \
						and event.get("ward_id") == "enemy" and event.get("target_id") == "reflection_victim"),
						label + ": Guard actually redirects the intended hit")
					_check(_find(result, "enemy").hp == 20 and _find(result, "reflection_victim").hp == 18,
						label + ": expected guarded HP 20 and reflected HP 18, got %d and %d" % [
							_find(result, "enemy").hp, _find(result, "reflection_victim").hp])
				else:
					_check(_find(result, "enemy").hp == 17 and _find(result, "reflection_victim").hp == 20,
						label + ": unreflected primary deals three")
