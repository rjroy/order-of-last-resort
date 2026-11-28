extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/reflecting_aura_budget_test.gd
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Combat = preload("res://rules/combat.gd")
const Statuses = preload("res://rules/statuses.gd")
class RuntimeCatalog:
	extends RefCounted
	var defs: Dictionary

var rules = preload("res://rules/rules.gd").new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_shared_redirect_budget()
	_test_absorb_and_friendly_blast()
	_test_uncapped()
	_test_upgraded_budget()
	_test_split_blast_retaliates_once()
	_test_overlapping_auras()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: reflecting aura budget")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": 30, "max_hp": 30, "statuses": {}}


func _state(capped := true) -> Dictionary:
	var defs: Dictionary = Fixture.definitions()
	var state: Dictionary = rules.new_game(defs, "fixture")
	# Install after validation so the fixture also runs against the old rules.
	if capped:
		defs.statuses.aura.params["max_reflect_damage_per_round"] = 4
	var catalog := RuntimeCatalog.new()
	catalog.defs = defs
	state.catalog = catalog
	state.units = [
		_unit("k", "knight", Vector2i(2, 2)),
		_unit("ward", "healer", Vector2i(3, 2)),
		_unit("other", "wizard", Vector2i(2, 3)),
		_unit("attacker", "harpooner", Vector2i(4, 2))]
	state.obstacles = []
	state.terrain = []
	state.round = 1
	Statuses.apply(state, state.units[0], "aura", state.units[0])
	return state


func _unit_at(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _hit(state: Dictionary, source: String, target: String, amount: int, status := "") -> Array:
	var events := []
	Combat.attack(state, _unit_at(state, source), _unit_at(state, target), amount,
		{"ability_id": "wizard_blast", "source_name": "fixture", "status": status}, events)
	return events


func _test_shared_redirect_budget() -> void:
	var state := _state()
	_hit(state, "attacker", "ward", 3, "knockdown")
	_check(_unit_at(state, "ward").hp == 30 and _unit_at(state, "attacker").hp == 27,
		"first three damage transfers in full")
	_check(not _unit_at(state, "ward").statuses.has("knockdown") \
		and _unit_at(state, "attacker").statuses.has("knockdown"),
		"full reflection transfers the hit status")
	_unit_at(state, "attacker").statuses.erase("knockdown")
	var preview_input := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "attacker", "enemy_attack", "ward")
	_check(plan.get("valid", false), "budgeted attack preview is valid")
	if plan.get("valid", false):
		_check(state == preview_input and plan == rules.preview(state, "attacker", "enemy_attack", "ward"),
			"repeated previews do not spend the live budget")
		var committed: Dictionary = rules.apply_plan(state, plan)
		_check(state == preview_input and committed == plan.result,
			"committing a preview reproduces it without changing its input")
		_check(_unit_at(committed, "ward").hp == 29 and _unit_at(committed, "attacker").hp == 26,
			"preview and commit both split the remaining budget")
	Statuses.apply(state, _unit_at(state, "k"), "aura", _unit_at(state, "k"))
	var before := state.duplicate(true)
	var replay := state.duplicate(true)
	var events := _hit(state, "attacker", "other", 4, "knockdown")
	_hit(replay, "attacker", "other", 4, "knockdown")
	_check(state == replay and _unit_at(before, "other").hp == 30,
		"independent replay spends the same budget without mutating its input")
	_check(_unit_at(state, "attacker").hp == 26 and _unit_at(state, "other").hp == 27,
		"same-round reapply does not refill: second ward splits four as one reflected and three overflow")
	var statuses := int(_unit_at(state, "attacker").statuses.has("knockdown")) \
		+ int(_unit_at(state, "other").statuses.has("knockdown"))
	_check(statuses == 1, "split hit applies knockdown once, not to both recipients")
	var status_hits := 0
	for event in events:
		if event.get("type") == "damage" and event.has("status_id"):
			status_hits += 1
	_check(status_hits == 1, "split hit reports one status-bearing damage event")
	_hit(state, "attacker", "ward", 2)
	_check(_unit_at(state, "ward").hp == 28 and _unit_at(state, "attacker").hp == 26,
		"third attack at the cap hits its original ward")
	state.round = 2
	_hit(state, "attacker", "ward", 3)
	_check(_unit_at(state, "ward").hp == 28 and _unit_at(state, "attacker").hp == 23,
		"new round refreshes the protector's budget")


func _test_absorb_and_friendly_blast() -> void:
	var state := _state()
	state.units.pop_back()
	_hit(state, "other", "ward", 3)
	_check(_unit_at(state, "ward").hp == 30, "friendly Blast is absorbed when no recipient exists")
	_hit(state, "other", "ward", 4)
	_check(_unit_at(state, "ward").hp == 27,
		"absorbed friendly Blast spends the shared budget and overflow lands")
	_hit(state, "other", "ward", 2)
	_check(_unit_at(state, "ward").hp == 25, "friendly Blast at cap is not absorbed")


func _test_uncapped() -> void:
	var state := _state(false)
	_hit(state, "attacker", "ward", 3)
	_hit(state, "attacker", "other", 4)
	_check(_unit_at(state, "ward").hp == 30 and _unit_at(state, "other").hp == 30 \
		and _unit_at(state, "attacker").hp == 23, "custom aura without cap remains uncapped")


func _test_upgraded_budget() -> void:
	for capped in [true, false]:
		var state := _state(capped)
		state.catalog.defs["upgrades"] = {"fixture_shield": {
			"hero_id": "knight", "effect": "shield_damage", "amount": 2}}
		_unit_at(state, "k")["upgrades"] = {"fixture_shield": 1}
		_hit(state, "attacker", "ward", 3)
		_check(_unit_at(state, "attacker").hp == 27 and _unit_at(state, "ward").hp == 30,
			"Upgraded aura redirects exactly the incoming damage, capped=%s" % capped)
		_hit(state, "attacker", "other", 5)
		var reflected := 3 if capped else 5
		_check(_unit_at(state, "attacker").hp == 27 - reflected \
			and _unit_at(state, "other").hp == 30 - (5 - reflected),
			"Upgraded aura shares its increased budget and leaves overflow, capped=%s" % capped)
		if capped:
			state.round = 2
			_hit(state, "attacker", "ward", 6)
			_check(_unit_at(state, "ward").hp == 30 and _unit_at(state, "attacker").hp == 18,
				"Upgraded finite budget refreshes to six next round")
	var absorbed := _state()
	absorbed.catalog.defs["upgrades"] = {"fixture_shield": {
		"hero_id": "knight", "effect": "shield_damage", "amount": 2}}
	_unit_at(absorbed, "k")["upgrades"] = {"fixture_shield": 1}
	absorbed.units.pop_back()
	_hit(absorbed, "other", "ward", 5)
	_hit(absorbed, "other", "ward", 3)
	_check(_unit_at(absorbed, "ward").hp == 28,
		"Upgraded aura spends its six-point budget on absorption before overflow")


func _test_split_blast_retaliates_once() -> void:
	var state := _state()
	var defs: Dictionary = state.catalog.defs
	defs.characters.harpooner.traits = [{"kind": "retaliate", "damage": 1, "range": 1}]
	defs.abilities.wizard_blast.params.damage = 3
	defs.abilities.wizard_blast.targeting = {
		"kind": "entity", "range": 4, "objects": true, "capabilities": ["damageable"]}
	defs["upgrades"] = {"fixture_conductive": {
		"hero_id": "wizard", "effect": "conductive_personality", "amount": 1}}
	state.units = [
		_unit("k", "knight", Vector2i(4, 2)),
		_unit("wizard", "wizard", Vector2i(2, 2)),
		_unit("far", "harpooner", Vector2i(6, 2))]
	Statuses.apply(state, _unit_at(state, "k"), "aura", _unit_at(state, "k"))
	_hit(state, "wizard", "k", 2)
	_check(_unit_at(state, "far").hp == 28 and _unit_at(state, "k").hp == 30,
		"retaliation fixture primes two budget through a real reflected hit")
	var duelist := _unit("duelist", "harpooner", Vector2i(3, 2))
	duelist.hp = 4
	duelist.max_hp = 4
	state.units.append(duelist)
	_unit_at(state, "wizard")["upgrades"] = {"fixture_conductive": 1}
	var plan: Dictionary = rules.preview(state, "wizard", "wizard_blast", "k")
	_check(plan.get("valid", false), "aimed split Blast against Knight is valid")
	if not plan.get("valid", false):
		return
	var hits := []
	var counters := 0
	for event in plan.events:
		if event.get("type") == "damage" and event.get("source_id") == "wizard" \
				and event.get("target_id") == "duelist" and event.get("amount", 0) > 0:
			hits.append(event.amount)
		if event.get("type") == "retaliate" and event.get("unit_id") == "duelist" \
				and event.get("target_id") == "wizard":
			counters += 1
	_check(hits == [2, 1] and _unit_at(plan.result, "duelist").hp == 1,
		"split Blast and Conductive bolt both damage the surviving adjacent Duelist (hits %s, HP %d)" \
			% [hits, _unit_at(plan.result, "duelist").hp])
	_check(counters == 1 and _unit_at(plan.result, "wizard").hp == 29,
		"Duelist retaliates exactly once for the split Blast action (counters %d, Wizard HP %d)" \
			% [counters, _unit_at(plan.result, "wizard").hp])


func _test_overlapping_auras() -> void:
	for priming in [3, 4]:
		var state := _state()
		_hit(state, "attacker", "ward", priming)
		_check(_unit_at(state, "attacker").hp == 30 - priming,
			"overlap fixture spends %d on the first aura" % priming)
		var second := _unit("second", "knight", Vector2i(3, 3))
		state.units.append(second)
		Statuses.apply(state, second, "aura", second)
		var events := _hit(state, "attacker", "ward", 2)
		var ward_hp: int = _unit_at(state, "ward").hp
		var attacker_hp: int = _unit_at(state, "attacker").hp
		if priming == 4:
			_check(ward_hp == 30 and attacker_hp == 24,
				"fresh overlapping aura protects ward when first protector is exhausted")
			var second_reflect := false
			for event in events:
				if event.get("type") == "reflect" and event.get("unit_id") == "second":
					second_reflect = true
			_check(second_reflect, "exhausted first protector yields to fresh second protector")
		else:
			_check(ward_hp == 29 and attacker_hp == 26,
				"partial overflow lands on ward rather than chaining through second aura")
			_hit(state, "attacker", "ward", 2)
			_check(_unit_at(state, "ward").hp == 29 and _unit_at(state, "attacker").hp == 24,
				"fresh second aura retains its budget after partial overflow")
