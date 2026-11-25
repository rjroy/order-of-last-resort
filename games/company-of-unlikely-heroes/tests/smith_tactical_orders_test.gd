extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_tactical_orders_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
var rules := Rules.new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = Catalog.read_default().duplicate(true)
	defs.abilities.healer_bonk.params.damage = 2
	defs.abilities.healer_heal.params.amount = 3
	defs.abilities.wizard_blast.params.damage = 4
	defs.abilities.enemy_attack.params.damage = 4
	defs.characters.test_enemy = defs.characters.grunt.duplicate(true)
	defs.characters.test_enemy.behavior = "hold"
	defs.characters.test_enemy.abilities = Catalog.profile(defs, "grunt").abilities.duplicate()
	if "enemy_attack" not in defs.characters.test_enemy.abilities:
		defs.characters.test_enemy.abilities.append("enemy_attack")
	for hero in ["knight", "healer", "wizard", "rogue", "alchemist", "bard"]:
		var profile := Catalog.profile(defs, hero)
		defs.characters[hero].abilities = profile.abilities.duplicate()
		defs.characters[hero].habits = profile.habits.duplicate()
		defs.characters[hero].habits.order_hold = "hold"
		defs.characters[hero].default_order = "order_hold"
	for row in [["knight", "healer_bonk"], ["healer", "wizard_blast"],
			["wizard", "rogue_confusing_dodge"], ["alchemist", "wizard_pull"],
			["bard", "knight_push"], ["knight", "knight_rescue_line"],
			["healer", "healer_field_dressing"], ["wizard", "wizard_ring_sparks"],
			["rogue", "rogue_tripwire"]]:
		if row[1] not in defs.characters[row[0]].abilities:
			defs.characters[row[0]].abilities.append(row[1])
	defs.characters.healer.habits.order_healer_triage = "guild_healer_triage"
	defs.characters.rogue.habits.order_pass_the_blame = "guild_pass_blame"
	defs.encounters.smith_tactical_orders_fixture = {"board": "road", "seed": 17,
		"party_slots": [[2, 3], [3, 3], [4, 3]],
		"placements": [{"id": "foe", "character": "test_enemy", "at": [3, 4]}]}
	defs.missions.smith_tactical_orders_fixture = defs.missions.shield_wall.duplicate(true)
	defs.missions.smith_tactical_orders_fixture.encounter = "smith_tactical_orders_fixture"
	defs.missions.smith_tactical_orders_fixture.erase("default_party")
	_direct_rows()
	_standing_rows()
	_triage_multiple_opponents()
	_fallback_blast()
	_invalid_selected_target()
	_strong_swing()
	_conductive()
	_wide_guard()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: smith tactical contextual orders")
	quit(0 if failures.is_empty() else 1)


func _unit(s: Dictionary, id: String) -> Dictionary:
	for u: Dictionary in s.get("units", []):
		if u.id == id:
			return u
	return {}


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _state(hero: String) -> Dictionary:
	var friend := "knight" if hero != "knight" else "healer"
	var s: Dictionary = Rules.open_mission(defs, "smith_tactical_orders_fixture", ["blacksmith", hero, friend])
	if s.is_empty():
		_check(false, hero + ": fixture must open")
		return {}
	s.width = 10
	s.height = 10
	s.terrain = []
	s.obstacles = []
	_unit(s, "foe").hp = 20
	_unit(s, "foe").max_hp = 20
	_unit(s, friend).max_hp = 20
	_unit(s, friend).hp = 10
	_unit(s, hero).max_hp = 20
	_unit(s, hero).hp = 20
	return s


func _round(s: Dictionary, label: String) -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview_round(s)
	_check(plan.get("valid", false) and s == before and rules.preview_round(s) == plan,
		label + ": repeatable pure forecast")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.commit_round(s, plan)
	_check(s == before and result == plan.get("result"), label + ": commit equals forecast, source unchanged")
	return result


func _direct_rows() -> void:
	# The Smith stands first and applies the fitting; nothing is pre-seeded on
	# the initial board. Selection is checked on the real board at the hero slot.
	var rows := [
		["healer", "healer_bonk", "friend"], ["healer", "healer_heal", ""],
		["wizard", "wizard_blast", ""], ["wizard", "wizard_pull", "foe"],
		["rogue", "rogue_wasnt_me", "foe"], ["rogue", "rogue_confusing_dodge", ""],
		["knight", "knight_rescue_line", "friend"], ["healer", "healer_field_dressing", "foe"],
		["wizard", "wizard_ring_sparks", ""], ["rogue", "rogue_tripwire", ""],
		["knight", "knight_shield_throw", "friend"],
		["knight", "healer_bonk", "friend"], ["healer", "wizard_blast", ""],
		["wizard", "rogue_confusing_dodge", ""], ["alchemist", "wizard_pull", "foe"],
		["bard", "knight_push", "foe"],
	]
	for row: Array in rows:
		var hero: String = row[0]
		var ability: String = row[1]
		var friend := "knight" if hero != "knight" else "healer"
		var target: String = friend if row[2] == "friend" else row[2]
		var s := _state(hero)
		if s.is_empty():
			continue
		if ability == "knight_rescue_line":
			_unit(s, friend).position = Vector2i(5, 3)
		if ability == "rogue_tripwire":
			_unit(s, friend).statuses.tripwire_tangled = {"remaining": 2}
			_unit(s, "foe").position = Vector2i(8, 8)
		if ability == "knight_shield_throw":
			_unit(s, hero).upgrades = {"knight_shield_throw": 1}
		if ability == "knight_push":
			_unit(s, "foe").position = Vector2i(3, 6)
		var before := s.duplicate(true)
		var slot: Dictionary = rules.state_before_action(s, hero)
		var label := "%s/%s" % [hero, ability]
		_check(s == before and _unit(slot, hero).get("fitted_by") == "blacksmith",
			label + ": earlier standing Smith fits actor on pre-slot board")
		if not target.is_empty():
			var choices: Array = rules.targets(slot, hero, ability)
			_check(choices.any(func(choice: Dictionary): return choice.id == target),
				label + ": alternate target offered at actual slot")
		s = rules.choose_manual(s, hero, ability, target)
		_check(s.overrides.has(hero), label + ": known source ability accepted as command")
		var result := _round(s, label)
		if result.is_empty():
			continue
		_check(not _unit(result, hero).has("fitted_by"), label + ": performed alternate consumes fitting")
		match ability:
			"healer_bonk", "knight_shield_throw":
				_check(_unit(result, friend).hp == 10, label + ": protects rather than damages friend")
			"healer_heal":
				_check(_unit(result, "foe").hp == 17, label + ": Doctor's Orders deals three")
			"wizard_blast":
				_check(_unit(result, friend).hp == 14, label + ": Mending Blast heals four")
			"wizard_pull":
				_check(_unit(result, "foe").position == Vector2i(3, 5), label + ": Send-Off moves target away")
			"rogue_wasnt_me", "healer_field_dressing":
				_check(_unit(result, "foe").hp == 18, label + ": alternate hits opponent for two")
			"rogue_confusing_dodge":
				_check(_unit(result, "foe").position == Vector2i(3, 4)
					and _unit(result, hero).position != Vector2i(3, 3), label + ": jumps without swap")
			"knight_rescue_line":
				_check(_unit(result, friend).position == Vector2i(6, 3), label + ": sends friend away")
			"wizard_ring_sparks":
				_check(_unit(result, friend).hp == 12 and _unit(result, "foe").hp == 20,
					label + ": heals friend without damaging opponent")
			"rogue_tripwire":
				_check(not _unit(result, friend).statuses.has("tripwire_tangled"), label + ": frees friend")
			"knight_push":
				_check(_unit(result, "foe").position == Vector2i(3, 5), label + ": borrowed Push pulls")


func _standing_rows() -> void:
	for row in [["healer", "order_aggressive", "bonk"], ["wizard", "order_blast", "blast"],
			["rogue", "order_pass_the_blame", "blame"], ["healer", "order_healer_triage", "triage"]]:
		var hero: String = row[0]
		var friend := "knight"
		var s := _state(hero)
		if s.is_empty():
			continue
		s.orders[hero] = row[1]
		if row[2] == "triage":
			_unit(s, "foe").hp = 15
		var result := _round(s, "standing " + row[2])
		if result.is_empty():
			continue
		_check(not _unit(result, hero).has("fitted_by"), "standing " + row[2] + ": alternate consumed fitting")
		match row[2]:
			"bonk": _check(_unit(result, friend).hp == 10, "standing bonk: cover does not hurt friend")
			"blast": _check(_unit(result, friend).hp == 14, "standing blast: heals nearest wounded hero")
			"blame": _check(_unit(result, "foe").hp == 18, "standing blame: bonks isolated enemy")
			"triage": _check(_unit(result, "foe").hp == 13, "standing triage: damages injured opponent")


func _triage_multiple_opponents() -> void:
	var s := _state("healer")
	var other := _unit(s, "foe").duplicate(true)
	other.id = "other"
	other.position = Vector2i(3, 2)
	other.hp = 12
	_unit(s, "foe").hp = 19
	s.units.append(other)
	s.orders.healer = "order_healer_triage"
	var result := _round(s, "Triage prioritizes wounds")
	if not result.is_empty():
		_check(_unit(result, "foe").hp == 19 and _unit(result, "other").hp == 10,
			"Triage chooses the more wounded of two adjacent opponents, not first in encounter order")

	var tied := s.duplicate(true)
	_unit(tied, "foe").hp = 15
	_unit(tied, "other").hp = 15
	result = _round(tied, "Triage wound tie")
	if not result.is_empty():
		_check(_unit(result, "foe").hp == 13 and _unit(result, "other").hp == 15,
			"Triage breaks equal missing-HP ties by encounter order")

	var direct := rules.choose_manual(s, "healer", "healer_field_dressing", "foe")
	var slot: Dictionary = rules.state_before_action(direct, "healer")
	var targets: Array = rules.targets(slot, "healer", "healer_field_dressing")
	_check(targets.any(func(target: Dictionary): return target.id == "foe")
		and targets.any(func(target: Dictionary): return target.id == "other"),
		"Direct Unpick offers both adjacent opponents")
	result = _round(direct, "Direct Unpick selected opponent")
	if not result.is_empty():
		_check(_unit(result, "foe").hp == 17 and _unit(result, "other").hp == 12,
			"Direct Unpick honors the chosen opponent over the more wounded opponent")


func _fallback_blast() -> void:
	var s := _state("wizard")
	_unit(s, "knight").hp = 20
	_unit(s, "blacksmith").position = Vector2i(1, 3)
	s.orders.wizard = "order_blast"
	var result := _round(s, "standing Blast fallback")
	if not result.is_empty():
		_check(_unit(result, "wizard").get("fitted_by") == "blacksmith"
			and _unit(result, "knight").hp == 16,
			"standing Blast fallback: ordinary nearest friend hit retains fitting")


func _invalid_selected_target() -> void:
	var s := _state("healer")
	_unit(s, "foe").hp = 0
	var other := _unit(s, "foe").duplicate(true)
	other.id = "other"
	other.hp = 20
	other.position = Vector2i(3, 2)
	s.units.append(other)
	s = rules.choose_manual(s, "healer", "healer_field_dressing", "foe")
	var result := _round(s, "invalid selected target")
	if not result.is_empty():
		_check(_unit(result, "other").hp == 20
			and _unit(result, "healer").get("fitted_by") == "blacksmith",
			"invalid chosen target: do not retarget and retain fitting")


func _strong_swing() -> void:
	var s := _state("healer")
	_unit(s, "healer").upgrades = {"healer_strong_swing": 1}
	# Smith is also an adjacent deployed hero; both should receive cover.
	s = rules.choose_manual(s, "healer", "healer_bonk", "knight")
	var result := _round(s, "Strong Swing protective tap")
	if not result.is_empty():
		_check(_unit(result, "knight").hp == 10 and _unit(result, "blacksmith").hp > 0
			and not _unit(result, "healer").has("fitted_by"),
			"Strong Swing: protective tap performs without friendly damage")
	var slot: Dictionary = rules.state_before_action(s, "healer")
	var tap: Dictionary = rules.preview(slot, "healer", "healer_bonk", "knight")
	_check(tap.get("valid", false), "Strong Swing: tap legal on actual pre-slot board")
	if tap.get("valid", false):
		for recipient in ["blacksmith", "knight"]:
			var hit_state: Dictionary = tap.result.duplicate(true)
			_unit(hit_state, "foe").position = _unit(hit_state, recipient).position + Vector2i(0, -1)
			var hp: int = _unit(hit_state, recipient).hp
			var hit: Dictionary = rules.preview(hit_state, "foe", "enemy_attack", recipient)
			_check(hit.get("valid", false), "Strong Swing: controlled hit on " + recipient + " is legal")
			_check(hit.get("valid", false) and _unit(hit.get("result", {}), recipient).get("hp", -1) == hp - 2,
				"Strong Swing: " + recipient + " absorbs two of a four-damage hit")
			_unit(hit_state, recipient).statuses.erase("keep_your_head_down")
			var plain_hit: Dictionary = rules.preview(hit_state, "foe", "enemy_attack", recipient)
			_check(plain_hit.get("valid", false)
				and _unit(plain_hit.get("result", {}), recipient).get("hp", -1) == hp - 4,
				"Strong Swing: same hit deals four to " + recipient + " without cover")


func _conductive() -> void:
	var s := _state("wizard")
	_unit(s, "wizard").upgrades = {"wizard_conductive_personality": 1}
	_unit(s, "blacksmith").max_hp = 20
	_unit(s, "blacksmith").hp = 10
	# Knight is nearer than Smith; the secondary heal reaches Smith.
	_unit(s, "blacksmith").position = Vector2i(1, 3)
	var result := _round(rules.choose_manual(s, "wizard", "wizard_blast"), "Conductive Mending")
	if not result.is_empty():
		_check(_unit(result, "knight").hp == 14 and _unit(result, "blacksmith").hp == 12,
			"Conductive Personality: secondary wounded hero heals half rounded up")


func _wide_guard() -> void:
	var s := _state("knight")
	_unit(s, "knight").upgrades = {"knight_wide_guard": 1}
	_unit(s, "foe").position = Vector2i(3, 5)
	_unit(s, "healer").position = Vector2i(8, 8)
	var result := _round(rules.choose_manual(s, "knight", "knight_aura"), "Wide Guard")
	if not result.is_empty():
		_check(_unit(result, "foe").position == Vector2i(3, 6),
			"Wide Guard: Clear the Floor reaches an occupant two tiles away")
