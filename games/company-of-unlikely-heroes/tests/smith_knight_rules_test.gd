extends SceneTree

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_knight_rules_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
var rules := Rules.new()
var failures: Array[String] = []
var base: Dictionary


func _initialize() -> void:
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	# Own the relevant tuning and the actors' habits. The rest of the stock
	# catalog supplies the actual ability handlers and their public contracts.
	defs.statuses.aura.params.range = 2
	defs.abilities.knight_push.params.collision_damage = 2
	# A test-owned negative control reproduces the pre-conversion ability
	# definitions without changing the production catalog or assertions.
	if "--pre-slice-control" in OS.get_cmdline_user_args():
		defs.abilities.knight_aura.erase("fitted_form")
		defs.abilities.knight_push.erase("fitted_form")
	defs.characters.test_enemy = defs.characters.grunt.duplicate(true)
	defs.characters.test_enemy.behavior = "hold"
	var healer_habits: Dictionary = Catalog.profile(defs, "healer").habits.duplicate()
	healer_habits["order_hold"] = "hold"
	defs.characters.healer.habits = healer_habits
	defs.characters.healer.default_order = "order_hold"
	defs.encounters.smith_rules_fixture = {"board": "road", "seed": 7,
		"party_slots": [[0, 0], [1, 0], [2, 0]],
		"placements": [{"id": "enemy", "character": "test_enemy", "at": [4, 2]}]}
	defs.missions.smith_rules_fixture = defs.missions.shield_wall.duplicate(true)
	defs.missions.smith_rules_fixture.encounter = "smith_rules_fixture"
	defs.missions.smith_rules_fixture.erase("default_party")
	base = Rules.open_mission(defs, "smith_rules_fixture", ["blacksmith", "knight", "healer"])
	if base.is_empty():
		_check(false, "Test-owned battle opens")
	else:
		_test_clear_floor(false)
		_test_clear_floor(true)
		_test_guard_fallback()
		_test_push_fallback()
		_test_fitting_selection()
		_test_shield_away()
	if failures.is_empty():
		print("PASS: smith knight rules")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _state() -> Dictionary:
	var s := base.duplicate(true)
	s.width = 10
	s.height = 10
	s.terrain = []
	s.obstacles = []
	s.orders.blacksmith = "order_hold"
	s.orders.knight = "order_guard"
	s.orders.healer = "order_hold"
	_unit(s, "blacksmith").position = Vector2i(0, 0)
	_unit(s, "knight").position = Vector2i(4, 4)
	_unit(s, "healer").position = Vector2i(5, 4)
	_unit(s, "enemy").position = Vector2i(6, 4)
	_unit(s, "knight").fitted_by = "blacksmith"
	return s


func _unit(s: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in s.get("units", []) + s.get("obstacles", []):
		if entry.id == id:
			return entry
	return {}


func _crate(id: String, at: Vector2i) -> Dictionary:
	return {"id": id, "object_id": "crate", "position": at, "statuses": {}, "hp": 10, "max_hp": 10}


func _round(s: Dictionary, label: String) -> Dictionary:
	var before := s.duplicate(true)
	var forecast: Dictionary = rules.preview_round(s)
	_check(s == before, label + ": forecast does not mutate source")
	_check(forecast.get("valid", false), label + ": forecast is valid")
	var committed: Dictionary = rules.commit_round(s, forecast)
	_check(s == before, label + ": commit does not mutate source")
	_check(committed == forecast.get("result"), label + ": commit equals forecast")
	return committed


func _test_clear_floor(direct: bool) -> void:
	var s := _state()
	# Farthest foe must leave first, freeing the adjacent friend's landing.
	# A blocked landing stays put; an occupant outside radius is untouched.
	s.units.append({"id": "blocked", "character_id": "test_enemy", "position": Vector2i(3, 4),
		"statuses": {}, "hp": 10, "max_hp": 10})
	s.units.append({"id": "outside", "character_id": "test_enemy", "position": Vector2i(4, 1),
		"statuses": {}, "hp": 10, "max_hp": 10})
	s.obstacles = [_crate("prop", Vector2i(4, 3)), _crate("wall", Vector2i(2, 4)),
		_crate("anchor", Vector2i(1, 4))]
	if direct:
		s = rules.choose_manual(s, "knight", "knight_aura")
	_check(s.overrides.size() == (1 if direct else 0), "Guard uses only the intended direct command")
	var result := _round(s, "direct Guard" if direct else "standing Guard")
	_check(_unit(result, "enemy").position == Vector2i(7, 4), "Clear the Floor moves the farthest foe first")
	_check(_unit(result, "healer").position == Vector2i(6, 4), "Friend enters the foe's vacated tile")
	_check(_unit(result, "prop").position == Vector2i(4, 2), "Clear the Floor moves the prop")
	_check(_unit(result, "blocked").position == Vector2i(3, 4), "Blocked shove is skipped")
	_check(_unit(result, "outside").position == Vector2i(4, 1), "Outside Guard radius is untouched")
	for id in ["healer", "enemy", "blocked", "outside", "prop", "wall", "anchor"]:
		_check(_unit(result, id).hp == _unit(s, id).hp, id + " takes no shove or collision damage")
	_check(not _unit(result, "knight").has("fitted_by"), "Successful Clear the Floor spends fitting")
	_check(not _unit(result, "knight").statuses.has("aura"), "Clear the Floor does not create a reflecting aura")


func _test_guard_fallback() -> void:
	var s := _state()
	_unit(s, "blacksmith").position = Vector2i(0, 0)
	_unit(s, "healer").position = Vector2i(9, 9)
	_unit(s, "knight").position = Vector2i(8, 4)
	_unit(s, "enemy").position = Vector2i(9, 4)
	var result := _round(s, "ordinary Guard fallback")
	_check(_unit(result, "enemy").position == Vector2i(9, 4), "Blocked alternate does not displace enemy")
	_check(_unit(result, "knight").statuses.has("aura"), "No legal shove performs ordinary Guard")
	_check(_unit(result, "knight").get("fitted_by") == "blacksmith", "Ordinary Guard fallback retains fitting")


func _test_push_fallback() -> void:
	var s := _state()
	_unit(s, "healer").position = Vector2i(9, 9)
	_unit(s, "knight").position = Vector2i(8, 4)
	_unit(s, "enemy").position = Vector2i(9, 4)
	var options: Array = rules.targets(s, "knight", "knight_push")
	_check(options.any(func(c: Dictionary): return c.id == "enemy"), "Adjacent enemy remains an ordinary Push target")
	s = rules.choose_manual(s, "knight", "knight_push", "enemy")
	var result := _round(s, "ordinary Push fallback")
	_check(_unit(result, "enemy").position == Vector2i(9, 4), "Blocked ordinary Push keeps target in place")
	_check(_unit(result, "enemy").hp == _unit(s, "enemy").hp - 2, "Ordinary Push deals controlled collision damage to selected target")
	_check(_unit(result, "knight").get("fitted_by") == "blacksmith", "Ordinary Push fallback retains fitting")


func _test_fitting_selection() -> void:
	var s := _state()
	_unit(s, "blacksmith").position = Vector2i(4, 3)
	_unit(s, "healer").position = Vector2i(5, 3)
	_unit(s, "enemy").position = Vector2i(9, 9)
	_unit(s, "knight").shield_position = Vector2i(0, 9)
	s.orders.blacksmith = "order_try_this"
	var unfitted := s.duplicate(true)
	_unit(unfitted, "knight").erase("fitted_by")
	var selected := _round(unfitted, "nearest unfitted tie")
	_check(_unit(selected, "knight").get("fitted_by") == "blacksmith"
		and not _unit(selected, "healer").has("fitted_by"), "Nearest tie fits the earlier deployed Knight")
	# Knight and Healer are equally near; Knight's earlier deployment wins.
	# Because Knight already has the fitting, standing Try This must hold.
	var waiting := _round(s, "nearest fitted tie")
	_check(_unit(waiting, "knight").get("fitted_by") == "blacksmith"
		and not _unit(waiting, "healer").has("fitted_by"), "Nearest tie selects the already-fitted earlier hero, not runner-up")
	s.orders.knight = "order_guard"
	s = rules.choose_manual(s, "blacksmith", "blacksmith_try_this", "healer")
	var replaced := _round(s, "manual replacement")
	_check(not _unit(replaced, "knight").has("fitted_by")
		and _unit(replaced, "healer").get("fitted_by") == "blacksmith", "Manual fitting moves the single mark to the selected hero")


func _test_shield_away() -> void:
	var s := _state()
	_unit(s, "knight").shield_position = Vector2i(9, 0)
	var result := _round(s, "shield away")
	_check(_unit(result, "enemy").position == Vector2i(6, 4), "Shield away prevents converted Guard")
	_check(not _unit(result, "knight").statuses.has("aura"), "Shield away prevents ordinary Guard")
	_check(_unit(result, "knight").get("fitted_by") == "blacksmith", "Shield-away wait retains fitting")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
