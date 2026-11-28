extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtest_bell_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Board = preload("res://rules/board.gd")
const FittedSummons = preload("res://rules/fitted_summons.gd")
class RuntimeCatalog:
	extends RefCounted
	var defs: Dictionary

var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_unoccupied()
	_test_occupied()
	_test_wipe_before_bell()
	_test_opt_in()
	_test_corpse_consumption()
	_test_displaced_corpse()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: corpse bell")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": hp, "max_hp": 10, "statuses": {}}


func _state(enabled := true) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.missions.fixture.objective = {"handler": "defeat_all", "team": "enemies",
		"text": "Defeat all", "victory_text": "Victory", "defeat_text": "Defeat",
		"victory_event": "Victory"}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Party lost"}]
	# Hold the enemy crew still; use a separate enemy profile for the new undead.
	defs.classes.enemy.erase("behavior")
	defs.characters.bell_undead = {"class": "enemy", "label": "Bell undead"}
	var state: Dictionary = rules.new_game(defs, "fixture")
	_check(not state.is_empty(), "controlled fixture opens")
	if state.is_empty():
		return {}
	state.units = [_unit("healer", "healer", Vector2i(3, 3), 10),
		_unit("first", "harpooner", Vector2i(4, 3), 2),
		_unit("crew", "harpooner", Vector2i(5, 3), 2)]
	state.party = ["healer"]
	state.orders = {}
	state.overrides = {}
	state.terrain = []
	state.obstacles = []
	# Install the proposed raw rider after validation, so the test is independent
	# of whether catalog authoring support has landed yet.
	if enabled:
		state.objective["corpse_bell"] = {"character": "bell_undead"}
	return state


func _round(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), label + ": forecast is valid")
	_check(state == before and plan == rules.preview_round(state),
		label + ": forecast is pure and repeatable")
	if not plan.get("valid", false):
		return {}
	var committed: Dictionary = rules.commit_round(state, plan)
	var comparable := committed.duplicate(true)
	comparable.erase("_terminal_commit")
	_check(comparable == plan.result and state == before, label + ": commit matches forecast")
	return plan


func _events(plan: Dictionary, event_type: String) -> Array:
	return plan.get("events", []).filter(func(event: Dictionary) -> bool:
		return event.get("type", "") == event_type)


func _living_undead(state: Dictionary) -> Array:
	return state.get("units", []).filter(func(unit: Dictionary) -> bool:
		return unit.get("character_id") == "bell_undead" and unit.get("hp", 0) > 0)


func _first_fall(enabled := true) -> Dictionary:
	var state := _state(enabled)
	if state.is_empty():
		return {}
	var staged: Dictionary = rules.choose_manual(state, "healer", "healer_bonk", "first")
	_check(staged.get("overrides", {}).has("healer"), "first strike can be staged")
	var plan := _round(staged, "first fall")
	if plan.is_empty():
		return {}
	var result: Dictionary = plan.result
	_check(Board.entity(result, "first").get("hp", 1) <= 0
		and Board.entity(result, "crew").get("hp", 0) > 0,
		"actual first enemy falls while another crew member survives")
	_check(result.outcome == "ongoing", "surviving crew keeps battle ongoing")
	if enabled:
		var marked := _events(plan, "corpse_bell_marked")
		_check(marked.size() == 1, "forecast announces exactly one marked corpse")
		if marked.size() == 1:
			var text := str(marked[0].get("text", "")).to_lower()
			_check("2" in text and ("e4" in text or "4,3" in text),
				"announcement names due round 2 and corpse tile E4")
		_check(_living_undead(result).is_empty(), "nothing rises on the first fall round")
	return result


func _test_unoccupied() -> void:
	var state := _first_fall()
	if state.is_empty():
		return
	var plan := _round(state, "unoccupied bell")
	if plan.is_empty():
		return
	var raised := _living_undead(plan.result)
	_check(raised.size() == 1, "one fresh enemy undead rises at the next round end")
	if raised.size() == 1:
		_check(raised[0].get("position") == Vector2i(4, 3)
			and raised[0].get("id") != "first", "fresh undead occupies the original corpse tile")
	_check(_events(plan, "corpse_bell_raised").size() == 1, "forecast announces the raise once")
	_check(_events(plan, "corpse_bell_marked").is_empty(), "bell does not announce a second corpse")


func _test_occupied() -> void:
	var state := _first_fall()
	if state.is_empty():
		return
	var staged: Dictionary = rules.choose_manual(state, "healer", "move", "4,3")
	_check(staged.get("overrides", {}).has("healer"), "move onto the actual corpse is legal")
	var plan := _round(staged, "occupied bell")
	if plan.is_empty():
		return
	_check(Board.entity(plan.result, "healer").get("position") == Vector2i(4, 3),
		"hero occupies the actual corpse tile at bell time")
	_check(_living_undead(plan.result).is_empty(), "occupied corpse does not spawn an undead")
	_check(_events(plan, "corpse_bell_blocked").size() == 1, "forecast announces the blocked bell")
	var clear: Dictionary = rules.choose_manual(plan.result, "healer", "move", "3,3")
	var later := _round(clear, "vacated after bell")
	if not later.is_empty():
		_check(Board.entity(later.result, "healer").get("position") == Vector2i(3, 3),
			"hero vacates the corpse tile")
		_check(_living_undead(later.result).is_empty()
			and _events(later, "corpse_bell_raised").is_empty()
			and _events(later, "corpse_bell_marked").is_empty(),
			"blocked opportunity is spent and never retried")


func _test_wipe_before_bell() -> void:
	var state := _state()
	if state.is_empty():
		return
	Board.entity(state, "crew").position = Vector2i(3, 4)
	var staged: Dictionary = rules.choose_manual(state, "healer", "healer_bonk", "first")
	var first := _round(staged, "wipe setup")
	if first.is_empty():
		return
	_check(Board.entity(first.result, "first").get("hp", 1) <= 0
		and Board.entity(first.result, "crew").get("hp", 0) > 0,
		"wipe setup falls one enemy with crew surviving")
	staged = rules.choose_manual(first.result, "healer", "healer_bonk", "crew")
	_check(staged.get("overrides", {}).has("healer"), "last crew strike is reachable")
	var plan := _round(staged, "wipe before bell")
	if not plan.is_empty():
		_check(plan.result.outcome == "victory", "wiping the original crew before bell end wins")
		_check(_living_undead(plan.result).is_empty(), "bell does not prevent a crew wipe victory")


func _test_opt_in() -> void:
	var state := _first_fall(false)
	if state.is_empty():
		return
	var plan := _round(state, "no rider")
	if not plan.is_empty():
		_check(_living_undead(plan.result).is_empty()
			and _events(plan, "corpse_bell_marked").is_empty()
			and _events(plan, "corpse_bell_raised").is_empty(),
			"ordinary defeat-all has no corpse bell")


func _enable_raise(state: Dictionary) -> void:
	var defs: Dictionary = state.catalog.defs.duplicate(true)
	defs.characters.crypter = {"class": "healer", "label": "Crypter",
		"abilities": ["move", "raise_dead"]}
	defs.characters.zombie = {"class": "healer", "label": "Zombie"}
	defs.abilities.raise_dead = {"label": "Raise Dead", "help": "Raise a corpse",
		"handler": "summon", "params": {"character": "zombie", "priority": 1},
		"targeting": {"kind": "entity", "teams": ["enemies"]}}
	defs.events.raise = {"text": "Raise"}
	var catalog := RuntimeCatalog.new()
	catalog.defs = defs
	state.catalog = catalog
	Board.entity(state, "healer").character_id = "crypter"


func _test_corpse_consumption() -> void:
	var first := _first_fall()
	if first.is_empty():
		return
	_enable_raise(first)
	var plan: Dictionary = rules.preview(first, "healer", "raise_dead", "first")
	_check(plan.get("valid", false), "Crypter can raise the marked corpse before the bell")
	if plan.get("valid", false):
		var raised: Dictionary = rules.apply_plan(first, plan)
		_check(raised == plan.result, "Raise Dead commits as forecast")
		for unit in raised.units:
			if unit.get("character_id") == "zombie":
				unit.hp = 0
		var bell := _round(raised, "bell after Crypter")
		if not bell.is_empty():
			_check(_living_undead(bell.result).is_empty(),
				"bell cannot raise a corpse already consumed by Crypter")
	var second := _first_fall()
	if second.is_empty():
		return
	_enable_raise(second)
	var rung := _round(second, "bell before Crypter")
	if rung.is_empty():
		return
	var after: Dictionary = rung.result
	for unit in _living_undead(after):
		unit.hp = 0
	var choices: Array = rules.targets(after, "healer", "raise_dead")
	_check(not choices.any(func(choice: Dictionary) -> bool: return choice.get("id") == "first"),
		"bell consumes its original corpse so Crypter cannot raise it again")


func _test_displaced_corpse() -> void:
	var state := _first_fall()
	if state.is_empty():
		return
	_enable_raise(state)
	var raised: Dictionary = rules.preview(state, "healer", "raise_dead", "first")
	_check(raised.get("valid", false), "displaced corpse setup can raise marked corpse")
	if not raised.get("valid", false):
		return
	var after: Dictionary = rules.apply_plan(state, raised)
	var zombies: Array = after.units.filter(func(unit: Dictionary) -> bool:
		return unit.get("character_id") == "zombie" and unit.get("hp", 0) > 0)
	_check(zombies.size() == 1, "displaced corpse setup has a living zombie")
	if zombies.size() != 1:
		return
	zombies[0].position = Vector2i(3, 4)
	FittedSummons.apply(after, Board.entity(after, "healer"), "", {}, {"id": "play_dead"},
		{"zombie_id": zombies[0].id, "corpse_id": "first"}, 0, [])
	_check(Board.entity(after, "first").position == Vector2i(3, 4)
		and not Board.entity(after, "first").get("corpse_consumed", false),
		"Play Dead returns the original corpse on a different tile")
	var bell := _round(after, "bell after displaced corpse")
	if not bell.is_empty():
		_check(_living_undead(bell.result).is_empty()
			and _events(bell, "corpse_bell_raised").is_empty(),
			"bell cannot raise the displaced corpse from its former tile")
