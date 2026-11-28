extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/combat_encounters_test.gd
# These are controlled integration boards built from the shipped missions and profiles.
const Catalog = preload("res://content/catalog.gd")
const Board = preload("res://rules/board.gd")
var rules = preload("res://rules/rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []
const PARTY := ["healer", "knight", "wizard"]


func _initialize() -> void:
	defs = Catalog.read_default()
	_test_shield_wall()
	_test_authored_shield_wall()
	_test_captain()
	_test_bombers()
	_test_healer()
	_test_heal_charges_with_use_ability()
	_test_unlimited_heal()
	_test_duelists()
	_test_odd_couple()
	_test_mirror()
	_test_mirror_authored_healer_activation()
	_test_authored_healer_limits()
	_test_bandits()
	_test_guard_whittled_down()
	if failures.is_empty():
		print("PASS: combat encounter interactions")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _open(id: String, composition: Dictionary, party: Array = PARTY, fixture_defs: Dictionary = {}) -> Dictionary:
	var content := fixture_defs if not fixture_defs.is_empty() else defs
	if not content.get("missions", {}).has(id):
		_check(false, id + ": mission exists")
		return {}
	var state: Dictionary = rules.open_mission(content, id, party)
	_check(not state.is_empty(), id + ": opens for a selected party")
	if state.is_empty():
		return {}
	_check(state.get("objective", {}).get("handler") == "defeat_all", id + ": defeat-all objective")
	var counts := {}
	for unit in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			counts[unit.character_id] = counts.get(unit.character_id, 0) + 1
	_check(counts == composition, "%s: expected composition %s, got %s" % [id, composition, counts])
	# Own the local geometry and health, preserving the actual authored abilities.
	state.width = 12
	state.height = 12
	state.terrain = []
	state.obstacles = []
	var index := 0
	for unit in state.units:
		unit.position = Vector2i(index, 10)
		unit.hp = 30
		unit.max_hp = 30
		unit.statuses = {}
		index += 1
	return state


func _units(state: Dictionary, character: String) -> Array:
	return state.get("units", []).filter(func(unit: Dictionary) -> bool:
		return unit.get("character_id") == character)


func _one(state: Dictionary, character: String) -> Dictionary:
	var found := _units(state, character)
	if found.is_empty():
		_check(false, "%s: missing %s" % [state.get("mission_id", "fixture"), character])
		return {}
	return found[0]


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _plan(state: Dictionary, actor: String, ability: String, target: String = "") -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, actor, ability, target)
	_check(state == before, ability + ": preview does not mutate input")
	if plan.get("valid", false):
		_check(rules.apply_plan(state, plan) == plan.result, ability + ": commit matches forecast")
	return plan


# Find an owned ability by observable result, not by internal implementation name.
func _effect(state: Dictionary, actor: String, target: String, kind: String) -> Dictionary:
	for ability in rules.entity_profile(state, actor).get("abilities", []):
		if ability == "move":
			continue
		var definition: Dictionary = rules.ability_definition(state, ability, actor)
		var argument := target if definition.get("targeting", {}).get("kind") == "entity" else ""
		var plan := _plan(state, actor, ability, argument)
		if not plan.get("valid", false):
			continue
		var after := _entity(plan.result, target)
		var before := _entity(state, target)
		if kind == "damage" and after.get("hp", 0) < before.get("hp", 0):
			return plan
		if kind == "heal" and after.get("hp", 0) > before.get("hp", 0):
			return plan
		if kind == "move" and after.get("position") != before.get("position"):
			return plan
	_check(false, "%s: %s can %s %s" % [state.mission_id, actor, kind, target])
	return {}


func _damage(state: Dictionary, actor: String, target: String, ability := "") -> int:
	var plan := _plan(state, actor, ability, target) if not ability.is_empty() else _effect(state, actor, target, "damage")
	if not plan.get("valid", false):
		_check(false, "%s: attack is legal" % state.mission_id)
		return -1
	return int(_entity(state, target).hp) - int(_entity(plan.result, target).hp)


func _round(state: Dictionary) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and state == before and plan == rules.preview_round(state),
		state.mission_id + ": round is deterministic and non-mutating")
	if plan.get("valid", false):
		var committed: Dictionary = rules.commit_round(state, plan)
		committed.erase("_terminal_commit")
		_check(committed == plan.result, state.mission_id + ": round commit matches forecast")
	return plan


func _test_shield_wall() -> void:
	var state := _open("shield_wall", {"shieldbearer": 2, "archer": 1})
	if state.is_empty():
		return
	var archer := _one(state, "archer")
	var shields := _units(state, "shieldbearer")
	if archer.is_empty() or shields.size() != 2:
		return
	_one(state, "healer").position = Vector2i(3, 4)
	archer.position = Vector2i(4, 4)
	shields[0].position = Vector2i(4, 5)
	shields[1].position = Vector2i(10, 0)
	var protected := _damage(state, "healer", archer.id, "healer_bonk")
	var exposed := state.duplicate(true)
	_entity(exposed, shields[0].id).position = Vector2i(8, 4)
	var unprotected := _damage(exposed, "healer", archer.id, "healer_bonk")
	_check(protected >= 0 and unprotected > protected,
		"Shieldbearer protects adjacent Archer; separation exposes it")
	var push := state.duplicate(true)
	_one(push, "knight").position = Vector2i(3, 5)
	var shove := _plan(push, "knight", "knight_push", shields[0].id)
	_check(shove.get("valid", false) and _entity(shove.get("result", {}), shields[0].id).get("position") == Vector2i(5, 5),
		"Knight can disrupt a shieldbearer by displacement")


func _test_authored_shield_wall() -> void:
	# A reproducible route on the untouched board. The standing aggressive order
	# lets the same Healer attack in both branches while Knight is commanded.
	if not defs.get("missions", {}).has("shield_wall"):
		_check(false, "Authored Shield Wall mission exists")
		return
	var state: Dictionary = rules.open_mission(defs, "shield_wall", ["knight", "healer", "wizard"])
	if state.is_empty():
		_check(false, "Authored Shield Wall opens")
		return
	var archer := _one(state, "archer")
	if archer.is_empty():
		return
	for step in [["knight", "2,1"], ["knight", "3,1"], ["healer", "2,2"], ["healer", "3,2"]]:
		var chosen: Dictionary = rules.choose_manual(state, step[0], "move", step[1])
		var turn: Dictionary = rules.state_before_action(chosen, step[0])
		var legal: Dictionary = rules.preview(turn, step[0], "move", step[1])
		_check(legal.get("valid", false), "Authored Shield Wall route: %s moves to %s" % step)
		if not legal.get("valid", false):
			return
		var plan := _round(chosen)
		if not plan.get("valid", false) or plan.result.get("outcome") != "ongoing":
			_check(false, "Authored Shield Wall route remains playable")
			return
		state = rules.commit_round(chosen, plan)
	state = rules.set_order(state, "healer", "order_aggressive")
	_check(state.orders.get("healer") == "order_aggressive", "Healer accepts aggressive standing order")
	var guard_id := "shieldbearer_1"
	var knight_turn: Dictionary = rules.state_before_action(state, "knight")
	var shove: Dictionary = rules.preview(knight_turn, "knight", "knight_push", guard_id)
	_check(shove.get("valid", false), "Knight can push the authored Shieldbearer")
	if not shove.get("valid", false):
		return
	var chosen: Dictionary = rules.choose_manual(state, "knight", "knight_push", guard_id)
	var baseline := _round(state)
	var changed := _round(chosen)
	var protected := false
	for event in baseline.get("events", []):
		if event.get("type") == "adjacent_guard" and event.get("unit_id") == guard_id \
				and event.get("target_id") == archer.id and event.get("amount", 0) > 0 \
				and event.get("ability_id") == "healer_bonk":
			protected = true
	var pushed := false
	for event in changed.get("events", []):
		if event.get("type") == "push" and event.get("unit_id") == "knight" \
				and event.get("target_id") == guard_id:
			pushed = true
	var before_damage := _event_damage(baseline.get("events", []), "healer", archer.id)
	var after_damage := _event_damage(changed.get("events", []), "healer", archer.id)
	_check(protected, "Authored Shieldbearer protects Archer from Healer's attack")
	_check(pushed and before_damage >= 0 and after_damage > before_damage,
		"Knight breaks authored cover and increases Healer's damage to Archer")


func _event_damage(events: Array, source: String, target: String) -> int:
	var total := -1
	for event in events:
		if event.get("type") == "damage" and event.get("source_id") == source \
				and event.get("target_id") == target:
			total = maxi(total, 0) + int(event.get("amount", 0))
	return total


func _test_captain() -> void:
	var fixture := defs.duplicate(true)
	var encounter_id: String = fixture.missions.cowardly_captain.encounter
	fixture.encounters[encounter_id].placements = [
		{"id": "test_grunt_1", "character": "grunt", "at": [4, 1]},
		{"id": "test_grunt_2", "character": "grunt", "at": [4, 3]},
		{"id": "test_captain", "character": "captain", "at": [5, 2]}
	]
	var state := _open("cowardly_captain", {"captain": 1, "grunt": 2}, PARTY, fixture)
	if state.is_empty():
		return
	var captain := _one(state, "captain")
	var grunts := _units(state, "grunt")
	if captain.is_empty() or grunts.size() != 2:
		return
	_one(state, "healer").position = Vector2i(4, 4)
	grunts[0].position = Vector2i(5, 4)
	grunts[1].position = Vector2i(10, 0)
	captain.position = Vector2i(5, 5)
	var supported := _damage(state, grunts[0].id, "healer")
	var separated := state.duplicate(true)
	_entity(separated, captain.id).position = Vector2i(9, 5)
	var unsupported := _damage(separated, grunts[0].id, "healer")
	_check(unsupported > 0 and supported > unsupported, "Captain strengthens an adjacent Grunt")
	var retreat := state.duplicate(true)
	_entity(retreat, grunts[0].id).hp = 0
	_entity(retreat, grunts[1].id).hp = 0
	_one(retreat, "healer").position = Vector2i(4, 5)
	var plan := _round(retreat)
	var moved := false
	for event in plan.get("events", []):
		if event.get("type") == "move" and event.get("unit_id") == captain.id:
			moved = Board.distance(event.position, Vector2i(4, 5)) > 1
	_check(moved, "Captain retreats from an adjacent hero when space permits")


func _test_bombers() -> void:
	var state := _open("explosive_situation", {"bomber": 2, "harpooner": 1})
	if state.is_empty():
		return
	var bombs := _units(state, "bomber")
	if bombs.size() != 2:
		return
	_one(state, "healer").position = Vector2i(3, 4)
	bombs[0].position = Vector2i(4, 4)
	bombs[1].position = Vector2i(5, 4)
	bombs[0].hp = 1
	bombs[1].hp = 1
	var plan := _plan(state, "healer", "healer_bonk", bombs[0].id)
	_check(plan.get("valid", false), "Bomber trigger attack is legal")
	if plan.get("valid", false):
		var result: Dictionary = plan.result
		_check(_entity(result, bombs[0].id).hp == 0 and _entity(result, bombs[1].id).hp == 0,
			"Defeating one Bomber detonates its neighbor and chains")
		_check(_one(result, "healer").hp < _one(state, "healer").hp,
			"Bomber explosion also damages nearby heroes")


func _test_healer() -> void:
	var state := _open("unfortunate_healer", {"enemy_healer": 1, "bruiser": 2})
	if state.is_empty():
		return
	var healer := _one(state, "enemy_healer")
	var bruisers := _units(state, "bruiser")
	if healer.is_empty() or bruisers.size() != 2:
		return
	healer.position = Vector2i(4, 4)
	bruisers[0].position = Vector2i(5, 4)
	bruisers[0].hp = 10
	var plan := _effect(state, healer.id, bruisers[0].id, "heal")
	if not plan.is_empty():
		_check(_entity(plan.result, bruisers[0].id).hp > 10, "Enemy Healer restores an injured Bruiser")


func _test_heal_charges_with_use_ability() -> void:
	var fixture := defs.duplicate(true)
	if not fixture.get("abilities", {}).has("frontier_heal"):
		_check(false, "Finite-healing fixture needs frontier_heal")
		return
	fixture.abilities.frontier_heal.params = {"amount": 2, "charges": 2}
	fixture.characters.enemy_healer.abilities = ["move", "rival_bonk", "frontier_heal"]
	fixture.characters.enemy_healer.erase("cast_presentation")
	fixture.behaviors["test_standing_heal"] = {
		"handler": "use_ability", "params": {"ability": "frontier_heal"}}
	fixture.characters.enemy_healer.behavior = "test_standing_heal"
	fixture.characters.bruiser.behavior = "hold"
	var state := _open("unfortunate_healer", {"enemy_healer": 1, "bruiser": 2}, PARTY, fixture)
	if state.is_empty():
		return
	var medic := _one(state, "enemy_healer")
	var bruisers := _units(state, "bruiser")
	if medic.is_empty() or bruisers.size() != 2:
		return
	medic.position = Vector2i(4, 4)
	bruisers[0].position = Vector2i(5, 4)
	bruisers[0].hp = 10
	bruisers[1].position = Vector2i(10, 0)
	var medic_id: String = medic.id
	var target_id: String = bruisers[0].id
	for use in range(2):
		var hp: int = _entity(state, target_id).hp
		var direct := _plan(state, medic_id, "frontier_heal")
		_check(direct.get("valid", false), "Finite heal use %d previews as legal" % (use + 1))
		var round_plan := _round(state)
		if not round_plan.get("valid", false):
			return
		var heal_event := false
		for event in round_plan.events:
			if event.get("type") == "heal" and event.get("unit_id") == medic_id \
					and event.get("target_id") == target_id and event.get("ability_id") == "frontier_heal" \
					and event.get("remaining_uses") == 1 - use:
				heal_event = true
		_check(heal_event and _entity(round_plan.result, target_id).hp > hp,
			"use_ability heals the wounded in-range ally and reports remaining charge %d" % (1 - use))
		state = rules.commit_round(state, round_plan)
	var still_wounded: bool = _entity(state, target_id).hp < _entity(state, target_id).max_hp
	_check(still_wounded, "Finite-healing exhaustion fixture retains an eligible wounded ally")
	var exhausted := _plan(state, medic_id, "frontier_heal")
	_check(not exhausted.get("valid", false), "Finite heal preview rejects a third use")
	var final_round := _round(state)
	if final_round.get("valid", false):
		var another_heal := false
		for event in final_round.events:
			if event.get("type") == "heal" and event.get("unit_id") == medic_id:
				another_heal = true
		_check(not another_heal and _entity(final_round.result, target_id).hp == _entity(state, target_id).hp,
			"use_ability cannot heal on its third activation after charges are exhausted")


func _test_unlimited_heal() -> void:
	for behavior in ["frontier_medic", "test_standing_heal"]:
		var fixture := defs.duplicate(true)
		fixture.abilities.frontier_heal.params = {"amount": 3}
		fixture.characters.enemy_healer.abilities = ["move", "rival_bonk", "frontier_heal"]
		fixture.characters.enemy_healer.erase("cast_presentation")
		fixture.behaviors["test_standing_heal"] = {
			"handler": "use_ability", "params": {"ability": "frontier_heal"}}
		fixture.characters.enemy_healer.behavior = behavior
		fixture.characters.bruiser.behavior = "hold"
		var state := _open("unfortunate_healer", {"enemy_healer": 1, "bruiser": 2}, PARTY, fixture)
		if state.is_empty():
			return
		var medic := _one(state, "enemy_healer")
		var bruisers := _units(state, "bruiser")
		if medic.is_empty() or bruisers.size() != 2:
			return
		medic.position = Vector2i(4, 4)
		bruisers[0].position = Vector2i(5, 4)
		bruisers[0].hp = 10
		bruisers[1].position = Vector2i(10, 0)
		var medic_id: String = medic.id
		var target_id: String = bruisers[0].id
		for use in range(3):
			var hp: int = _entity(state, target_id).hp
			var direct := _plan(state, medic_id, "frontier_heal")
			_check(direct.get("valid", false), "%s unlimited heal %d previews as legal" % [behavior, use + 1])
			var round_plan := _round(state)
			if not round_plan.get("valid", false):
				break
			var healed := false
			for event in round_plan.events:
				if event.get("type") == "heal" and event.get("unit_id") == medic_id \
						and event.get("target_id") == target_id and event.get("ability_id") == "frontier_heal":
					healed = true
					_check(not event.has("remaining_uses") and not str(event.get("text", "")).contains("uses left"),
						"%s unlimited heal does not display charges" % behavior)
			_check(healed and _entity(round_plan.result, target_id).hp == hp + 3,
				"%s unlimited heal %d restores exactly 3 HP" % [behavior, use + 1])
			_check(not _entity(round_plan.result, medic_id).get("ability_uses", {}).has("frontier_heal"),
				"%s unlimited heal does not consume charges" % behavior)
			state = rules.commit_round(state, round_plan)


func _test_duelists() -> void:
	var state := _open("duelists", {"duelist": 2})
	if state.is_empty():
		return
	var duelists := _units(state, "duelist")
	if duelists.size() != 2:
		return
	duelists[0].position = Vector2i(4, 4)
	_one(state, "healer").position = Vector2i(3, 4)
	var melee := _plan(state, "healer", "healer_bonk", duelists[0].id)
	_check(melee.get("valid", false), "Adjacent bonk against Duelist is legal")
	if melee.get("valid", false):
		_check(_one(melee.result, "healer").hp < _one(state, "healer").hp,
			"Duelist retaliates against an adjacent attacker")
	var ranged := state.duplicate(true)
	_one(ranged, "wizard").position = Vector2i(4, 6)
	_one(ranged, "healer").position = Vector2i(0, 0)
	var blast := _plan(ranged, "wizard", "wizard_blast")
	_check(blast.get("valid", false), "Ranged blast against Duelist is legal")
	if blast.get("valid", false):
		_check(_entity(blast.result, duelists[0].id).hp < duelists[0].hp
			and _one(blast.result, "wizard").hp == _one(ranged, "wizard").hp,
			"Ranged attack damages Duelist without adjacent retaliation")


func _test_odd_couple() -> void:
	var state := _open("odd_couple", {"ogre": 1, "trickster": 1})
	if state.is_empty():
		return
	var ogre := _one(state, "ogre")
	var trickster := _one(state, "trickster")
	if ogre.is_empty() or trickster.is_empty():
		return
	ogre.position = Vector2i(5, 4)
	trickster.position = Vector2i(4, 4)
	var plan := _effect(state, trickster.id, ogre.id, "move")
	if not plan.is_empty():
		_check(_entity(plan.result, ogre.id).position == trickster.position
			and _entity(plan.result, trickster.id).position == ogre.position,
			"Trickster swaps places with Ogre")


func _test_mirror() -> void:
	var state := _open("mirror_company", {"rival_knight": 1, "rival_wizard": 1, "rival_healer": 1})
	if state.is_empty():
		return
	var knight := _one(state, "rival_knight")
	var wizard := _one(state, "rival_wizard")
	var healer := _one(state, "rival_healer")
	if knight.is_empty() or wizard.is_empty() or healer.is_empty():
		return
	knight.position = Vector2i(4, 4)
	_one(state, "healer").position = Vector2i(5, 4)
	var push := _effect(state, knight.id, "healer", "move")
	if not push.is_empty():
		_check(_one(push.result, "healer").position == Vector2i(6, 4), "Rival Knight pushes a hero")
	var cast := state.duplicate(true)
	_entity(cast, wizard.id).position = Vector2i(5, 6)
	_check(_damage(cast, wizard.id, "healer") > 0, "Rival Wizard damages a hero at range")
	var heal := state.duplicate(true)
	_entity(heal, healer.id).position = Vector2i(4, 5)
	_entity(heal, knight.id).hp = 10
	_effect(heal, healer.id, knight.id, "heal")


func _test_mirror_authored_healer_activation() -> void:
	if not defs.get("missions", {}).has("mirror_company"):
		_check(false, "Authored Mirror Company mission exists")
		return
	var party: Array = defs.missions.mirror_company.default_party
	var state: Dictionary = rules.open_mission(defs, "mirror_company", party)
	if state.is_empty():
		_check(false, "Authored Mirror Company opens with its default party")
		return
	var healer := _one(state, "rival_healer")
	if healer.is_empty():
		return
	var plan := _round(state)
	var activated := false
	for event in plan.get("events", []):
		if event.get("type") in ["move", "heal", "damage", "push", "pull", "wait"] \
				and event.get("unit_id", event.get("source_id", "")) == healer.id \
				and not (event.get("type") == "wait" and event.has("ability_id")):
			activated = true
			break
	_check(activated, "Rival Healer gets a live first activation on the untouched default opening")


func _test_authored_healer_limits() -> void:
	for mission in ["mirror_company", "veteran_mirror_company", "veteran_unfortunate_healer"]:
		var veteran: bool = mission == "veteran_unfortunate_healer"
		var composition := {"enemy_healer": 1, "bruiser": 2} if veteran \
			else {"rival_knight": 1, "rival_wizard": 1, "rival_healer": 1}
		var state := _open(mission, composition)
		if state.is_empty():
			continue
		var medic := _one(state, "enemy_healer" if veteran else "rival_healer")
		var patient := _one(state, "bruiser" if veteran else "rival_knight")
		var other: Dictionary = _one(state, "rival_wizard") if not veteran else _units(state, "bruiser")[1]
		medic.position = Vector2i(4, 4)
		patient.position = Vector2i(6, 4)
		patient.hp = 10
		other.position = Vector2i(10, 0)
		var medic_id: String = medic.id
		var patient_id: String = patient.id
		var ability := "unfortunate_healer_heal" if veteran else "frontier_heal"
		var amount := 3 if veteran else 2
		for use in range(3):
			var plan := _plan(state, medic_id, ability)
			_check(plan.get("valid", false), "%s: heal %d is available" % [mission, use + 1])
			if not plan.get("valid", false):
				break
			_check(_entity(plan.result, patient_id).hp == 10 + amount * (use + 1),
				"%s: heal %d restores its authored amount at range 2" % [mission, use + 1])
			var healed := false
			for event in plan.get("events", []):
				if event.get("type") == "heal" and event.get("unit_id") == medic_id:
					healed = true
					_check(not event.has("remaining_uses"), mission + ": heal has no use counter")
			_check(healed, mission + ": heal event emitted")
			_check(not _entity(plan.result, medic_id).get("ability_uses", {}).has(ability),
				mission + ": heal does not consume uses")
			state = plan.result


func _test_bandits() -> void:
	var state := _open("last_one_standing", {"bandit_damage": 1, "bandit_guard": 1, "bandit_swift": 1})
	if state.is_empty():
		return
	var attacker := _one(state, "bandit_damage")
	var guard := _one(state, "bandit_guard")
	var swift := _one(state, "bandit_swift")
	if attacker.is_empty() or guard.is_empty() or swift.is_empty():
		return
	attacker.position = Vector2i(4, 4)
	guard.position = Vector2i(9, 0)
	swift.position = Vector2i(10, 0)
	_one(state, "healer").position = Vector2i(3, 4)
	var baseline := _damage(state, attacker.id, "healer")
	var alone := state.duplicate(true)
	_entity(alone, guard.id).hp = 0
	_entity(alone, swift.id).hp = 0
	_check(_damage(alone, attacker.id, "healer") > baseline and baseline > 0,
		"Damage Bandit hits harder after allies fall")
	var defense := state.duplicate(true)
	_entity(defense, guard.id).position = Vector2i(4, 4)
	_entity(defense, attacker.id).position = Vector2i(9, 0)
	var normal := _damage(defense, "healer", guard.id, "healer_bonk")
	_entity(defense, attacker.id).hp = 0
	_entity(defense, swift.id).hp = 0
	var last := _damage(defense, "healer", guard.id, "healer_bonk")
	_check(normal > last and last >= 0, "Guard Bandit takes less damage after allies fall")
	var movement := state.duplicate(true)
	_entity(movement, swift.id).position = Vector2i(7, 5)
	_entity(movement, attacker.id).position = Vector2i(10, 0)
	_entity(movement, guard.id).position = Vector2i(11, 0)
	_one(movement, "healer").position = Vector2i(1, 5)
	_one(movement, "knight").position = Vector2i(0, 4)
	_one(movement, "wizard").position = Vector2i(0, 6)
	var full := _round(movement)
	_entity(movement, attacker.id).hp = 0
	_entity(movement, guard.id).hp = 0
	var survivor := _round(movement)
	if full.get("valid", false) and survivor.get("valid", false):
		var origin: Vector2i = _entity(movement, swift.id).position
		var ordinary: int = Board.distance(origin, _entity(full.result, swift.id).position)
		var faster: int = Board.distance(origin, _entity(survivor.result, swift.id).position)
		_check(faster > ordinary, "Swift Bandit moves farther after allies fall")


func _test_guard_whittled_down() -> void:
	# The party has no upgrades; fix Sonnet at one damage independent of tuning.
	var fixture_defs := defs.duplicate(true)
	if not fixture_defs.get("abilities", {}).has("healing_sonnet"):
		_check(false, "Guard whittling fixture needs Healing Sonnet")
		return
	fixture_defs.abilities.healing_sonnet.params.damage = 1
	var state := _open("last_one_standing",
		{"bandit_damage": 1, "bandit_guard": 1, "bandit_swift": 1},
		["bard", "rogue", "necromancer"], fixture_defs)
	if state.is_empty():
		return
	var guard := _one(state, "bandit_guard")
	var attacker := _one(state, "bandit_damage")
	var swift := _one(state, "bandit_swift")
	if guard.is_empty() or attacker.is_empty() or swift.is_empty():
		return
	attacker.hp = 0
	swift.hp = 0
	guard.hp = 2
	var first := _plan(state, "bard", "healing_sonnet")
	_check(first.get("valid", false), "One-damage Sonnet can target the last Guard")
	if not first.get("valid", false):
		return
	_check(_entity(first.result, guard.id).hp == 1,
		"Last Guard's mitigation still permits one-damage Sonnet to whittle it down")
	var second := _plan(first.result, "bard", "healing_sonnet")
	_check(second.get("valid", false), "A second Sonnet can target the surviving Guard")
	if second.get("valid", false):
		_check(_entity(second.result, guard.id).hp == 0,
			"Repeated one-damage Sonnet can defeat the last Guard at two HP")
