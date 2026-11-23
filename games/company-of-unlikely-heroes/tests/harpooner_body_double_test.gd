extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/harpooner_body_double_test.gd

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Fixtures = preload("res://tests/fixtures/rules_catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
var failures: Array[String] = []


func _initialize() -> void:
	for distance in [1, 2]:
		_case(distance)
		_reflected_bomber_case(distance)
	if failures.is_empty():
		print("PASS: Body Double preserves the Harpooner's intended target")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _case(distance: int) -> void:
	var rules := Rules.new()
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		_unit("r", "rogue", Vector2i(2, 2), {"rogue_body_double": 1}),
		_unit("partner", "knight", Vector2i(8, 2)),
		_unit("attacker", "harpooner", Vector2i(8 - distance, 2))]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	var swap: Dictionary = rules.preview(state, "r", "rogue_confusing_dodge")
	if not swap.get("valid", false):
		_check(false, "Distance %d: stock Body Double swap resolves" % distance)
		return
	var before: Dictionary = swap.result
	var attack: Dictionary = rules.preview(before, "attacker", "enemy_harpoon", "r")
	if not attack.get("valid", false):
		_check(false, "Distance %d: stock Harpoon attack resolves" % distance)
		return
	_check(attack.events.any(func(event): return event.get("type") == "body_double" \
		and event.get("unit_id") == "r" and event.get("target_id") == "partner"),
		"Distance %d: Body Double redirects the intended Rogue to the distant partner" % distance)
	_check(attack.events.any(func(event): return event.get("type") == "damage" \
		and event.get("target_id") == "partner" and event.get("amount", 0) > 0),
		"Distance %d: actual damage reaches the distant partner" % distance)
	var cues: Array = Cues.build(before, attack.result, attack.events)
	var found := {}
	for cue: Dictionary in cues:
		if cue.get("unit_id") == "attacker":
			found = cue
			break
	_check(not found.is_empty(), "Distance %d: committed attack has a cue" % distance)
	if found.is_empty():
		return
	_check(found.get("clip") == ("close_thrust" if distance == 1 else "ranged_cast"),
		"Distance %d: clip follows distance to original target, not partner" % distance)
	_check(found.get("target_id") == "r" and found.get("target_cell") == Vector2i(8, 2),
		"Distance %d: aim and projectile impact stay on the original Rogue" % distance)
	_check(found.get("recipients", []).any(func(recipient): return recipient.get("id") == "partner" \
		and recipient.get("cell") == Vector2i(2, 2) and recipient.get("kind") == "hit"),
		"Distance %d: feedback still names the true damage recipient" % distance)


func _reflected_bomber_case(distance: int) -> void:
	var rules := Rules.new()
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		_unit("r", "rogue", Vector2i(2, 2), {"rogue_body_double": 1}),
		_unit("partner", "knight", Vector2i(8, 2)),
		_unit("attacker", "harpooner", Vector2i(8 - distance, 2)),
		_unit("bystander", "healer", Vector2i(3, 3)),
		_unit("bomber", "bomber", Vector2i(3, 2)).merged({"hp": 1}, true)]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	var swap: Dictionary = rules.preview(state, "r", "rogue_confusing_dodge")
	if not swap.get("valid", false):
		_check(false, "Distance %d: reflected case resolves the actual Body Double swap" % distance)
		return
	var guard: Dictionary = rules.preview(swap.result, "partner", "knight_aura")
	if not guard.get("valid", false):
		_check(false, "Distance %d: reflected case resolves the partner's guard" % distance)
		return
	var before: Dictionary = guard.result
	var attack: Dictionary = rules.preview(before, "attacker", "enemy_harpoon", "r")
	if not attack.get("valid", false):
		_check(false, "Distance %d: reflected case resolves the actual harpoon attack" % distance)
		return
	_check(attack.events.any(func(event): return event.get("type") == "body_double" \
		and event.get("unit_id") == "r" and event.get("target_id") == "partner"),
		"Distance %d: Body Double substitutes the distant partner" % distance)
	_check(attack.events.any(func(event): return event.get("type") == "reflect" \
		and event.get("ward_id") == "partner" and event.get("target_id") == "bomber"),
		"Distance %d: partner's guard reflects the attack to Bomber" % distance)
	_check(attack.events.any(func(event): return event.get("type") == "damage" \
		and event.get("source_id") == "attacker" and event.get("target_id") == "bomber" \
		and event.get("amount", 0) > 0),
		"Distance %d: reflected harpoon actually damages Bomber" % distance)
	_check(attack.events.any(func(event): return event.get("type") == "death_blast" \
		and event.get("unit_id") == "bomber"),
		"Distance %d: Bomber actually detonates" % distance)
	_check(attack.events.any(func(event): return event.get("type") == "damage" \
		and event.get("source_id") == "bomber" and event.get("target_id") == "bystander" \
		and event.get("amount", 0) > 0),
		"Distance %d: Bomber's separate death blast actually damages bystander" % distance)
	var cues: Array = Cues.build(before, attack.result, attack.events)
	var found := {}
	for cue: Dictionary in cues:
		if cue.get("unit_id") == "attacker":
			found = cue
			break
	_check(not found.is_empty(), "Distance %d: reflected attack has a cue" % distance)
	if found.is_empty():
		return
	_check(found.get("clip") == ("close_thrust" if distance == 1 else "ranged_cast"),
		"Distance %d: reflected attack retains the original target's distance" % distance)
	_check(found.get("target_id") == "r" and found.get("target_cell") == Vector2i(8, 2),
		"Distance %d: reflected attack aims at the original Rogue" % distance)
	_check(found.get("recipients", []).any(func(recipient): return recipient.get("id") == "partner" \
		and recipient.get("cell") == Vector2i(2, 2) and recipient.get("kind") == "guard"),
		"Distance %d: guard feedback names the substituted partner" % distance)
	var hits: Array = found.get("recipients", []).filter(
		func(recipient): return recipient.get("kind") == "hit")
	_check(hits.size() == 1 and hits[0].get("id") == "bomber" \
		and hits[0].get("cell") == Vector2i(3, 2),
		"Distance %d: only the reflected Bomber receives harpoon hit feedback, not blast victims: %s" \
			% [distance, hits])


func _unit(id: String, character: String, position: Vector2i, upgrades := {}) -> Dictionary:
	return {"id": id, "character_id": character, "position": position, "hp": 20,
		"max_hp": 20, "statuses": {}, "upgrades": upgrades}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
