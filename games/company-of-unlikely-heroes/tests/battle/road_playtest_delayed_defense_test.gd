extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/road_playtest_delayed_defense_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Board = preload("res://rules/board.gd")

class RuntimeCatalog:
	extends RefCounted
	var defs: Dictionary

var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_borrowed_armor()
	_test_big_windup()
	_test_skipped_windup_warning()
	_test_windup_wall_contact()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: road delayed defense")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": 10, "max_hp": 10, "statuses": {}}


func _state(rider: Dictionary, units: Array) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	defs.missions.fixture.objective = {"handler": "defeat_all", "team": "enemies",
		"text": "Defeat all", "victory_text": "Victory", "defeat_text": "Defeat",
		"victory_event": "Victory"}
	defs.missions.fixture.failures = [{"handler": "party_wiped", "event": "Defeat"}]
	defs.classes.enemy.erase("behavior")
	var state: Dictionary = rules.new_game(defs, "fixture")
	_check(not state.is_empty(), "controlled fixture opens")
	if state.is_empty():
		return {}
	# Install proposed traits after validation, as in the other focused road tests.
	defs.characters.lender = {"class": "enemy", "label": "Lender", "traits": [rider]}
	var catalog := RuntimeCatalog.new()
	catalog.defs = defs
	state.catalog = catalog
	state.units = units
	state.party = ["hero"]
	state.orders = {}
	state.overrides = {}
	state.terrain = []
	state.obstacles = []
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
	committed.erase("_terminal_commit")
	_check(committed == plan.result and state == before, label + ": commit matches forecast")
	return plan


func _hit(state: Dictionary, target: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "hero", "healer_bonk", target)
	_check(plan.get("valid", false), "direct hit on " + target + " is legal")
	_check(state == before and plan == rules.preview(state, "hero", "healer_bonk", target),
		"direct hit forecast is pure and repeatable")
	if plan.get("valid", false):
		_check(rules.apply_plan(state, plan) == plan.result and state == before,
			"direct hit commit matches forecast")
	return plan


func _shows_windup_tile(plan: Dictionary) -> bool:
	for event in plan.get("events", []):
		var text := str(event.get("text", "")).to_lower()
		if ("wind" in text or "mark" in text or "smash" in text or "strike" in text) \
				and ("e5" in text or "4,4" in text):
			return true
	return false


func _test_borrowed_armor() -> void:
	var state := _state({"kind": "borrowed_armor"}, [
		_unit("hero", "healer", Vector2i(4, 3)),
		_unit("borrower", "harpooner", Vector2i(4, 4)),
		_unit("lender", "lender", Vector2i(5, 3)),
		_unit("other", "harpooner", Vector2i(9, 3))])
	if state.is_empty():
		return
	var staged: Dictionary = rules.choose_manual(state, "hero", "healer_bonk", "borrower")
	_check(staged.get("overrides", {}).has("hero"), "first borrower strike can be staged")
	var first := _round(staged, "first armor round")
	if first.is_empty():
		return
	var after: Dictionary = first.result
	_check(Board.entity(after, "borrower").hp == 10, "nearest ally's first hit is blocked in forecast")
	var second := _hit(after, "borrower")
	if second.get("valid", false):
		_check(Board.entity(second.result, "borrower").hp == Board.entity(after, "borrower").hp - 2,
			"second hit on borrower is not blocked")
	var exposed := _hit(after, "lender")
	if exposed.get("valid", false):
		_check(Board.entity(exposed.result, "lender").hp == 8, "lender is exposed")
	var next: Dictionary = rules.choose_manual(after, "hero", "healer_bonk", "borrower")
	_check(next.get("overrides", {}).has("hero"), "next-round borrower strike can be staged")
	var refreshed := _round(next, "refreshed armor round")
	if not refreshed.is_empty():
		_check(Board.entity(refreshed.result, "borrower").hp == Board.entity(after, "borrower").hp,
			"borrowed armor refreshes at the next round start")


func _test_big_windup() -> void:
	# Proposed runtime trait: no authored Big Windup schema exists yet. The
	# forecast must identify the marked tile, not merely the original target.
	var state := _state({"kind": "big_windup", "damage": 2}, [
		_unit("hero", "healer", Vector2i(4, 4)),
		_unit("lender", "lender", Vector2i(4, 5)),
		_unit("crew", "harpooner", Vector2i(6, 4))])
	if state.is_empty():
		return
	var mark := _round(state, "windup mark")
	if mark.is_empty():
		return
	_check(Board.entity(mark.result, "hero").hp == 10, "windup does not strike on the marking round")
	_check(_shows_windup_tile(mark), "forecast visibly identifies marked tile E5")
	var moved: Dictionary = mark.result.duplicate(true)
	Board.entity(moved, "hero").position = Vector2i(3, 4)
	Board.entity(moved, "crew").position = Vector2i(4, 4)
	var strike := _round(moved, "windup strike")
	if strike.is_empty():
		return
	_check(_shows_windup_tile(strike), "next-round forecast still identifies marked tile E5")
	_check(Board.entity(strike.result, "crew").hp == 8,
		"next round strikes the original tile's new enemy ally occupant")
	_check(Board.entity(strike.result, "hero").hp == 10,
		"windup does not re-aim at the original hero")


func _test_skipped_windup_warning() -> void:
	var state := _state({"kind": "big_windup", "damage": 2}, [
		_unit("hero", "healer", Vector2i(4, 4)),
		_unit("lender", "lender", Vector2i(4, 5)),
		_unit("crew", "harpooner", Vector2i(8, 4))])
	if state.is_empty():
		return
	var mark := _round(state, "skip setup")
	if mark.is_empty():
		return
	var primed: Dictionary = mark.result
	Board.entity(primed, "lender").statuses.knockdown = {"source_id": "hero"}
	var skipped := _round(primed, "skipped windup")
	if skipped.is_empty():
		return
	_check(Board.entity(skipped.result, "hero").hp == 10,
		"knocked-down windup does not strike during skipped turn")
	_check(_shows_windup_tile(skipped),
		"forecast retains the marked tile warning while windup is skipped")
	var later := _round(skipped.result, "windup after skip")
	if not later.is_empty():
		_check(Board.entity(later.result, "hero").hp == 8,
			"retained windup strikes the original tile after recovery")


func _test_windup_wall_contact() -> void:
	var state := _state({"kind": "big_windup", "damage": 2}, [
		_unit("hero", "healer", Vector2i(1, 1)),
		_unit("lender", "lender", Vector2i(3, 3))])
	if state.is_empty():
		return
	state.catalog.defs.objects["test_wall"] = {"label": "Wall", "max_hp": 1,
		"capabilities": ["blocks_movement", "damageable"]}
	state.obstacles.append({"id": "wall", "object_id": "test_wall",
		"position": Vector2i(2, 3), "footprint_offsets": [Vector2i(0, -1), Vector2i(0, 1)],
		"hp": 1, "max_hp": 1, "statuses": {}})
	Board.entity(state, "lender").windup_cell = Vector2i(2, 2)
	var strike := _round(state, "windup wall contact")
	if strike.is_empty():
		return
	var hits: Array = strike.events.filter(func(event: Dictionary) -> bool:
		return event.get("type") == "damage" and event.get("target_id") == "wall")
	_check(hits.size() == 1 and hits[0].get("impact_position") == Vector2i(2, 2),
		"windup hits the wall at the marked C3 segment, not its C4 center")
