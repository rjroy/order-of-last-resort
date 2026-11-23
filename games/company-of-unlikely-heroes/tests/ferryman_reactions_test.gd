extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/ferryman_reactions_test.gd
## Controlled positions; actions, damage and recovery events come from the rules.

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Fixtures = preload("res://tests/fixtures/rules_catalog.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")

var failures: Array[String] = []
var rules := Rules.new()


func _initialize() -> void:
	var art := Sprites.new()
	art.load_manifest()
	for name in ["ready", "travel", "safe_bank", "flinch", "down", "recover"]:
		var clip = art.clip_for("ferryman", name)
		_check(clip != null and Sprites.load_texture(clip.path) != null if clip != null else false,
			"Packaged " + name + " is loadable")
	var hit := _state("harpooner", 10)
	_attack(hit, "enemy_harpoon", "civilian", "flinch")
	var lethal := _state("harpooner", 2)
	_attack(lethal, "enemy_harpoon", "civilian", "down")
	var knockdown := _state("wizard", 10)
	var plan: Dictionary = rules.preview(knockdown, "attacker", "wizard_blast")
	_check(plan.get("valid", false), "Real Wizard Blast resolves")
	if plan.get("valid", false):
		_check(plan.events.any(func(event): return event.get("type") == "damage" \
			and event.get("target_id") == "civilian" and event.get("status_id") == "knockdown"),
			"Blast actually knocks down the living Ferryman")
		_check(_has(Cues.build(knockdown, plan.result, plan.events), "down"), "Knockdown plays down")
		var recovery: Dictionary = rules.preview_round(plan.result)
		_check(recovery.get("valid", false), "Following real round resolves")
		if recovery.get("valid", false):
			_check(recovery.events.any(func(event): return event.get("type") == "recover" \
				and event.get("unit_id") == "civilian" and "knockdown" in event.get("status_ids", [])),
				"Rules emit the civilian's actual knockdown recovery")
			_check(_has(Cues.build(plan.result, recovery.result, recovery.events), "recover"),
				"Real knockdown recovery plays recover")
	_test_jelly_knees()
	_test_blocked_move()
	_test_zero_damage_knockdown()
	_test_prone_hit(5)
	_test_prone_hit(1)
	_test_initially_prone_hit(5)
	_test_initially_prone_hit(1)
	var defs := Catalog.read_default()
	for field in ["art_key", "art_variant"]:
		var custom: Dictionary = defs.duplicate(true)
		custom.characters.ferryman[field] = "custom"
		var state: Dictionary = Rules.open_mission(custom, "company_rescue", ["knight", "healer", "wizard"])
		_check(Cues.cast_key_for(state, _unit(state, "civilian")).is_empty(),
			"Customized " + field + " preserves fallback")
	if failures.is_empty():
		print("PASS: Ferryman rule-emitted reactions and custom identity")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _state(attacker: String, hp: int) -> Dictionary:
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		{"id": "attacker", "character_id": attacker, "position": Vector2i(3, 3),
			"hp": 10, "max_hp": 10, "statuses": {}},
		{"id": "civilian", "character_id": "ferryman", "position": Vector2i(4, 3),
			"hp": hp, "max_hp": 10, "statuses": {}}]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return state


func _attack(state: Dictionary, ability: String, target: String, expected: String) -> void:
	var plan: Dictionary = rules.preview(state, "attacker", ability, target)
	_check(plan.get("valid", false), "Actual Harpoon attack resolves")
	if not plan.get("valid", false):
		return
	_check(plan.events.any(func(event): return event.get("type") == "damage" \
		and event.get("target_id") == "civilian" and event.get("amount", 0) > 0),
		"Actual damage reaches the Ferryman")
	_check(_has(Cues.build(state, plan.result, plan.events), expected), "Actual damage plays " + expected)


func _test_jelly_knees() -> void:
	var state := _state("alchemist", 10)
	var seed_value := -1
	for candidate in range(1, 10000):
		if Reactions.draw(candidate, false).id == "jelly_knees":
			seed_value = candidate
			break
	_check(seed_value >= 0, "Controlled dose seed can produce Jelly Knees")
	if seed_value < 0:
		return
	state.units[0]["dose_rng_state"] = seed_value
	var plan: Dictionary = rules.preview(state, "attacker", "alchemist_potion", "civilian")
	_check(plan.get("valid", false), "Potion can target the stock civilian")
	if not plan.get("valid", false):
		return
	_check(plan.events.any(func(event): return event.get("type") == "alchemy_reaction" \
		and event.get("target_id") == "civilian" and event.get("reaction_id") == "jelly_knees" \
		and event.get("applied", false)), "Actual dose applies Jelly Knees")
	_check(_has(Cues.build(state, plan.result, plan.events), "down"), "Jelly Knees plays down")
	var recovery: Dictionary = rules.preview_round(plan.result)
	_check(recovery.get("valid", false), "Jelly Knees recovery round resolves")
	if recovery.get("valid", false):
		_check(recovery.events.any(func(event): return event.get("type") == "recover" \
			and event.get("unit_id") == "civilian" and event.get("reaction_id") == "jelly_knees"),
			"Rules emit Jelly Knees recovery")
		_check(_has(Cues.build(plan.result, recovery.result, recovery.events), "recover"),
			"Actual Jelly Knees recovery plays recover")


func _dose(state: Dictionary, reaction: String) -> Dictionary:
	for candidate in range(1, 10000):
		if Reactions.draw(candidate, false).id == reaction:
			state.units[0]["dose_rng_state"] = candidate
			var plan: Dictionary = rules.preview(state, "attacker", "alchemist_potion", "civilian")
			_check(plan.get("valid", false), reaction + ": potion resolves")
			if plan.get("valid", false):
				_check(plan.events.any(func(event): return event.get("type") == "alchemy_reaction" \
					and event.get("target_id") == "civilian" and event.get("reaction_id") == reaction \
					and event.get("applied", false)), reaction + ": real dose applies reaction")
			return plan
	_check(false, "Could not find controlled seed for " + reaction)
	return {}


func _test_blocked_move() -> void:
	var dose := _dose(_state("alchemist", 10), "boot_toffee")
	if not dose.get("valid", false):
		return
	var before: Dictionary = dose.result
	var plan: Dictionary = rules.preview(before, "civilian", "move", "5,3")
	_check(plan.get("valid", false), "Boot Toffee permits a legal attempted move")
	if not plan.get("valid", false):
		return
	_check(plan.events.any(func(event): return event.get("type") == "status" \
		and event.get("unit_id") == "civilian" and event.get("status_id") == "boot_toffee" \
		and event.get("consumed", false)), "Real move consumes Boot Toffee")
	_check(not plan.events.any(func(event): return event.get("type") == "move" \
		and event.get("unit_id") == "civilian"), "Blocked move emits no movement")
	_check(_unit(plan.result, "civilian").position == _unit(before, "civilian").position,
		"Blocked Ferryman remains in place")
	_check(not _has(Cues.build(before, plan.result, plan.events), "travel"),
		"Consumed move without movement must not play travel")


func _test_zero_damage_knockdown() -> void:
	var state := _state("alchemist", 1)
	state.units[1].max_hp = 1
	state.units.append({"id": "wizard", "character_id": "wizard", "position": Vector2i(4, 4),
		"hp": 10, "max_hp": 10, "statuses": {}})
	var dose := _dose(state, "pocket_paramedic")
	if not dose.get("valid", false):
		return
	var before: Dictionary = dose.result
	var plan: Dictionary = rules.preview(before, "wizard", "wizard_blast")
	_check(plan.get("valid", false), "Blast against protected Ferryman resolves")
	if not plan.get("valid", false):
		return
	_check(plan.events.any(func(event): return event.get("type") == "damage" \
		and event.get("target_id") == "civilian" and event.get("amount") == 0 \
		and event.get("status_id") == "knockdown"), "Pocket Paramedic emits zero-damage knockdown")
	_check(_unit(plan.result, "civilian").hp == 1 and rules.knocked_down(plan.result, "civilian"),
		"Protected Ferryman stays alive but is actually knocked down")
	_check(_has(Cues.build(before, plan.result, plan.events), "down"),
		"Applied knockdown plays down even when mitigated damage is zero")


func _test_prone_hit(hp: int) -> void:
	var state := _state("alchemist", hp)
	state.units[1].max_hp = hp
	state.units.insert(1, {"id": "harpooner", "character_id": "harpooner", "position": Vector2i(6, 3),
		"hp": 10, "max_hp": 10, "statuses": {}})
	var dose := _dose(state, "jelly_knees")
	if not dose.get("valid", false):
		return
	state = rules.choose_manual(state, "attacker", "alchemist_potion", "civilian")
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), "Prone-hit round is valid at %d HP" % hp)
	if not plan.get("valid", false):
		return
	var events: Array = plan.events
	var down_index := -1
	var hit_index := -1
	var recover_index := -1
	for i in events.size():
		var event: Dictionary = events[i]
		if event.get("type") == "alchemy_reaction" and event.get("target_id") == "civilian" \
				and event.get("reaction_id") == "jelly_knees" and event.get("applied", false):
			down_index = i
		if event.get("type") == "damage" and event.get("source_id") == "harpooner" \
				and event.get("target_id") == "civilian" and event.get("amount", 0) > 0:
			hit_index = i
		if event.get("type") == "recover" and event.get("unit_id") == "civilian" \
				and event.get("reaction_id") == "jelly_knees":
			recover_index = i
	_check(down_index >= 0 and hit_index > down_index, "Jelly Knees precedes actual Harpooner hit at %d HP" % hp)
	var clips: Array = []
	for cue: Dictionary in Cues.build(state, plan.result, events):
		if cue.get("unit_id") == "civilian" and cue.get("cast_key") == "ferryman":
			clips.append(cue.get("clip"))
	if hp > 2:
		_check(recover_index > hit_index and _unit(plan.result, "civilian").hp > 0 \
			and not rules.knocked_down(plan.result, "civilian"), "Surviving Ferryman actually recovers")
		_check(clips == ["down", "recover"],
			"Already-prone survivor must not restart upright flinch: %s" % [clips])
	else:
		_check(recover_index < 0 and _unit(plan.result, "civilian").hp == 0,
			"Lethal hit leaves the Ferryman down without recovery")
		_check(clips == ["down"],
			"Already-prone fatal victim must not restart the upright down clip: %s" % [clips])


func _test_initially_prone_hit(hp: int) -> void:
	var state := _state("alchemist", hp)
	state.units[1].max_hp = hp
	state.units.append({"id": "harpooner", "character_id": "harpooner", "position": Vector2i(6, 3),
		"hp": 10, "max_hp": 10, "statuses": {}})
	var dose := _dose(state, "jelly_knees")
	if not dose.get("valid", false):
		return
	var before: Dictionary = dose.result
	_check(rules.knocked_down(before, "civilian"), "Ferryman begins the attack already prone")
	var attack: Dictionary = rules.preview(before, "harpooner", "enemy_harpoon", "civilian")
	_check(attack.get("valid", false), "Harpooner can attack an initially prone civilian")
	if not attack.get("valid", false):
		return
	_check(attack.events.any(func(event): return event.get("type") == "damage" \
		and event.get("target_id") == "civilian" and event.get("amount", 0) > 0),
		"Actual attack damages the initially prone civilian")
	var cues: Array = Cues.build(before, attack.result, attack.events)
	_check(not _has(cues, "flinch") and not _has(cues, "down") and not _has(cues, "recover"),
		"Initially prone victim does not replay an upright reaction or invent recovery at %d HP" % hp)
	_check((_unit(attack.result, "civilian").hp <= 0) == (hp <= 2),
		"Initially prone victim has the expected survival outcome")


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.units:
		if unit.id == id:
			return unit
	return {}


func _has(cues: Array, clip: String) -> bool:
	return cues.any(func(cue): return cue.get("unit_id") == "civilian" \
		and cue.get("cast_key") == "ferryman" and cue.get("clip") == clip)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
