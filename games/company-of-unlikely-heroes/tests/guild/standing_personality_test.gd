extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/standing_personality_test.gd
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")

var rules = preload("res://rules/rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = Catalog.read_default()
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	_test_starting_kits()
	_test_training_and_preference()
	_test_purchased_order_does_not_change_default()
	_test_knight_move_only()
	_test_caster()
	_test_dodger()
	_test_crypter()
	_test_raise_dead()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: standing order personalities")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _profile() -> Dictionary:
	return {"guild_id": "personality-test", "board_seed": 147258, "board_generation": 0,
		"points": 1000000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": ["knight", "healer", "wizard", "rogue", "necromancer",
			"bard", "alchemist", "blacksmith"]}


func _ids(rows: Array) -> Array:
	var result := []
	for row in rows:
		result.append(row.get("id", ""))
	return result


func _test_starting_kits() -> void:
	var expected := {
		"knight": ["order_guard", "order_knight_advance_move", "knight_push", "knight_aura"],
		"healer": ["order_support", "order_hold", "healer_bonk", "healer_heal"],
		"wizard": ["order_blast", "order_cautious", "wizard_blast", "wizard_pull"],
		"rogue": ["order_confusing_dodge", "order_retreat", "rogue_wasnt_me", "rogue_confusing_dodge"],
		"necromancer": ["order_make_a_friend", "order_hold", "summon_skeleton", "raise_dead"],
		"bard": ["order_inspiring_melody", "order_hold", "healing_sonnet", "inspiring_melody"],
		"alchemist": ["order_make_rounds", "order_follow_ally", "alchemist_acid", "alchemist_potion"],
		"blacksmith": ["order_try_this", "order_hold", "blacksmith_hammer_time", "blacksmith_try_this"]
	}
	var profile := _profile()
	for hero in expected:
		var loadout: Dictionary = Progression.default_loadout(defs, profile, hero)
		var rows: Array = Progression.order_options(defs, profile, hero, loadout)
		var kit: Dictionary = Progression.effective_kit(defs, profile, hero, loadout)
		_check(loadout.get("order_id") == expected[hero][0], hero + " equips its personality order")
		var ids := _ids(rows)
		_check(rows.size() == 2 and expected[hero][0] in ids and expected[hero][1] in ids \
			and rows.all(func(row: Dictionary) -> bool: return row.get("compatible", false)),
			hero + " starts with exactly its compatible ability and movement orders")
		var habits: Dictionary = kit.get("habits", {})
		var ability_behavior: String = habits.get(expected[hero][0], "")
		var movement_behavior: String = habits.get(expected[hero][1], "")
		_check(not ability_behavior.is_empty() and not movement_behavior.is_empty() \
			and ability_behavior != movement_behavior,
			hero + " ability and movement orders resolve to distinct behaviors")
		var movement: Dictionary = defs.get("behaviors", {}).get(movement_behavior, {})
		var movement_abilities := Catalog.behavior_ability_ids(movement)
		_check(not movement.is_empty() and movement_abilities.all(func(id): return id == "move"),
			hero + " movement order does not delegate a non-movement ability")
		_check(expected[hero][2] in kit.get("abilities", []) and expected[hero][3] in kit.get("abilities", []),
			hero + " retains both native direct abilities")
		var state := _state(hero, [_unit("enemy", "harpooner", Vector2i(8, 3))])
		if not state.is_empty():
			var actions := _ids(rules.options(state, hero))
			_check(expected[hero][2] in actions and expected[hero][3] in actions,
				hero + " offers both native abilities as direct actions in battle")


func _buy(profile: Dictionary, id: String) -> Dictionary:
	var result: Dictionary = Progression.purchased_profile(defs, profile, id)
	_check(not result.has("error"), "Purchase succeeds: " + id)
	return result


func _test_training_and_preference() -> void:
	var profile := _profile()
	var second := ""
	for id in defs.guild_progression.petitions:
		var grant: Dictionary = defs.guild_progression.petitions[id].get("grant", {})
		if grant.get("hero_id") == "healer" and grant.get("kind") == "order" \
				and grant.get("order_id") == "order_aggressive":
			second = id
	_check(not second.is_empty(), "Healer's native second ability order is separately purchasable")
	if not second.is_empty():
		var trained := _buy(profile, second)
		if not trained.has("error"):
			var loadout: Dictionary = Progression.default_loadout(defs, trained, "healer")
			_check("order_aggressive" in _ids(Progression.order_options(defs, trained, "healer", loadout)),
				"Purchased native second ability order becomes available")
	profile = _buy(profile, "teach_healer_blast")
	if profile.has("error"):
		return
	var loadout: Dictionary = Progression.default_loadout(defs, profile, "healer")
	loadout.slots.offense = "wizard_blast"
	_check("order_healer_blast" not in _ids(Progression.order_options(defs, profile, "healer", loadout)),
		"Buying Blast alone does not grant its standing order")
	profile = _buy(profile, "healer_blast_order")
	if profile.has("error"):
		return
	_check("order_healer_blast" in _ids(Progression.order_options(defs, profile, "healer", loadout)),
		"Buying the separate Blast order makes it available")
	# This was a valid old preference before Bonk was replaced by a learned ability.
	if not second.is_empty():
		profile = _buy(profile, second)
		if profile.has("error"):
			return
		loadout.order_id = "order_aggressive"
		profile.preferred_loadouts.healer = loadout.duplicate(true)
		var fallback: Dictionary = Progression.default_loadout(defs, profile, "healer")
		_check(not Progression.effective_kit(defs, profile, "healer", fallback).is_empty(),
			"Incompatible old preference falls back to a usable kit")
		_check(second in profile.purchased_ids and "teach_healer_blast" in profile.purchased_ids \
			and "healer_blast_order" in profile.purchased_ids,
			"Preference fallback preserves all owned purchases")
		var bonk: Dictionary = fallback.duplicate(true)
		bonk.slots.offense = "healer_bonk"
		_check("order_aggressive" in _ids(Progression.order_options(defs, profile, "healer", bonk)),
			"Previously owned order remains available when compatible again")


func _test_purchased_order_does_not_change_default() -> void:
	var profile := _profile()
	profile.recruited_ids.erase("rogue")
	profile = _buy(profile, "recruit_rogue")
	if profile.has("error"):
		return
	_check(not profile.preferred_loadouts.has("rogue"), "New Dodger has no saved preference")
	var before: Dictionary = Progression.default_loadout(defs, profile, "rogue")
	profile = _buy(profile, "order_rogue_blame")
	if profile.has("error"):
		return
	var after: Dictionary = Progression.default_loadout(defs, profile, "rogue")
	_check(before.get("order_id") == "order_confusing_dodge" and after == before,
		"Buying Pass the Blame before first deployment leaves Confusing Dodge equipped")
	_check("order_pass_the_blame" in _ids(Progression.order_options(defs, profile, "rogue", after)),
		"Purchased Pass the Blame remains available as an explicit choice")
	var board: Array = Commissions.board(defs, profile.board_seed)
	if board.is_empty():
		_check(false, "Dodger training fixture has a commission")
		return
	var run: Dictionary = Adventure.start_guild_commission(defs, board[0],
		["rogue", "knight", "healer"], profile, {}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, "Dodger training fixture starts an outing")
		return
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	_check(run.get("mission", {}).get("orders", {}).get("rogue") == "order_confusing_dodge",
		"First deployment retains the Dodger's personality order after buying Pass the Blame")


func _test_knight_move_only() -> void:
	for distance in [1, 4]:
		var enemy_pos := Vector2i(3 + distance, 3)
		var state := _state("knight", [_unit("enemy", "harpooner", enemy_pos)])
		state = rules.set_order(state, "knight", "order_knight_advance_move")
		_check(state.get("orders", {}).get("knight") == "order_knight_advance_move",
			"Knight's move-only order is selectable")
		var result := _round(state, "Knight move-only distance %d" % distance)
		if not result.is_empty():
			_check(_entity(result, "enemy").get("position") == enemy_pos \
				and _entity(result, "enemy").get("hp") == 20,
				"Knight's move-only advance never Pushes or damages the opponent")
			_check(_entity(result, "knight").get("position") == (Vector2i(3, 3) if distance == 1 else Vector2i(4, 3)),
				"Knight steps toward an opponent, stopping when adjacent")
	var profile := _profile()
	var loadout: Dictionary = Progression.default_loadout(defs, profile, "knight")
	_check("order_advance" not in _ids(Progression.order_options(defs, profile, "knight", loadout)),
		"Knight's automatic Push order remains separately paid")
	profile = _buy(profile, "order_knight_advance")
	if profile.has("error"):
		return
	var rows: Array = Progression.order_options(defs, profile, "knight", loadout)
	var labels := {}
	for row in rows:
		if row.get("id") in ["order_advance", "order_knight_advance_move"]:
			labels[row.id] = row.label
	_check(labels.size() == 2 and labels.get("order_advance") != labels.get("order_knight_advance_move"),
		"Purchased Push pursuit and free move-only advance have distinct labels")


func _unit(id: String, character: String, pos: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": 20, "max_hp": 20, "statuses": {}, "upgrades": {}}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _state(hero: String, others: Array, profile := {}) -> Dictionary:
	if profile.is_empty():
		profile = _profile()
	var board: Array = Commissions.board(defs, profile.board_seed)
	var party := [hero, "knight", "healer"] if hero not in ["knight", "healer"] else [hero, "wizard", "bard"]
	var run: Dictionary = Adventure.start_guild_commission(defs, board[0], party, profile, {}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, "Commission fixture starts for " + hero)
		return {}
	run = Adventure.choose_route(run, run.reports[0].mission_id)
	run = Adventure.begin_mission(run)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		_check(false, "Commission fixture deploys " + hero)
		return {}
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [_unit(hero, hero, Vector2i(3, 3))]
	state.units.append_array(others)
	state.units.append(_unit("civilian", "ferryman", Vector2i(3, 4)))
	state.party = [hero]
	var loadout: Dictionary = Progression.default_loadout(defs, profile, hero)
	state.orders = {hero: loadout.get("order_id", "")}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	state.rng_state = 12345
	return state


func _round(state: Dictionary, label: String) -> Dictionary:
	if state.is_empty():
		return {}
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and state == before and plan == rules.preview_round(state),
		label + " forecast is valid, stable and non-mutating")
	if not plan.get("valid", false):
		return {}
	_check(rules.commit_round(state, plan) == plan.get("result") and state == before,
		label + " commit matches forecast")
	return plan.get("result", {})


func _test_caster() -> void:
	var state := _state("wizard", [_unit("friend", "knight", Vector2i(4, 3)),
		_unit("enemy", "harpooner", Vector2i(8, 3))])
	_entity(state, "civilian").position = Vector2i(2, 2)
	state = rules.set_order(state, "wizard", "order_blast")
	var result := _round(state, "Caster Blast")
	if not result.is_empty():
		_check(_entity(result, "friend").get("hp", 20) < 20 and _entity(result, "enemy").get("hp") == 20,
			"Caster's nearest Blast hits the closer friend rather than the enemy")


func _test_dodger() -> void:
	var state := _state("rogue", [_unit("enemy", "harpooner", Vector2i(4, 3)),
		_unit("friend", "knight", Vector2i(8, 3))])
	var result := _round(state, "Dodger friendly swap")
	if not result.is_empty():
		_check(_entity(result, "rogue").get("position") == Vector2i(8, 3) \
			and _entity(result, "friend").get("position") == Vector2i(3, 3),
			"Dodger escapes by swapping with the farthest legal friend")
	var enemy_swap := _state("rogue", [_unit("near", "harpooner", Vector2i(4, 3)),
		_unit("enemy", "harpooner", Vector2i(8, 3))])
	result = _round(enemy_swap, "Dodger enemy swap")
	if not result.is_empty():
		_check(_entity(result, "rogue").get("position") == Vector2i(8, 3) \
			and _entity(result, "enemy").get("position") == Vector2i(3, 3),
			"Enemy swap compares distance after the enemy moves to Dodger's old tile")
	var no_escape := _state("rogue", [_unit("enemy", "harpooner", Vector2i(4, 3)),
		_unit("friend", "knight", Vector2i(5, 3))])
	_entity(no_escape, "civilian").position = Vector2i(4, 4)
	result = _round(no_escape, "Dodger no improvement")
	if not result.is_empty():
		_check(_entity(result, "rogue").get("position") == Vector2i(3, 3),
			"Dodger holds when no legal swap increases distance to the nearest opponent")
	var tied := _state("rogue", [_unit("enemy", "harpooner", Vector2i(4, 3)),
		_unit("a_friend", "knight", Vector2i(1, 3)), _unit("b_friend", "healer", Vector2i(3, 5))])
	# Both destinations are distance two from the Dodger and improve safety.
	var first := _round(tied, "Dodger tie")
	var reversed := tied.duplicate(true)
	reversed.units.reverse()
	var again := _round(reversed, "Dodger reversed tie")
	if not first.is_empty() and not again.is_empty():
		_check(_entity(first, "rogue").get("position") == Vector2i(1, 3) \
			and _entity(again, "rogue").get("position") == Vector2i(1, 3),
			"Dodger breaks equal-distance swaps by lowest instance ID")


func _test_crypter() -> void:
	var state := _state("necromancer", [_unit("enemy", "harpooner", Vector2i(8, 3)),
		_unit("friend", "knight", Vector2i(5, 3))])
	var result := _round(state, "Make a Friend")
	if result.is_empty():
		return
	var skeletons: Array = result.units.filter(func(unit): return unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0)
	_check(skeletons.size() == 1 and skeletons[0].position == Vector2i(4, 3),
		"Crypter summons closest to the enemy even when it blocks a friend's path")


func _test_raise_dead() -> void:
	var profile := _buy(_profile(), "order_necro_raise")
	if profile.has("error"):
		return
	var near := _unit("near_corpse", "harpooner", Vector2i(4, 3))
	near.hp = 0
	var far := _unit("far_corpse", "harpooner", Vector2i(5, 3))
	far.hp = 0
	var state := _state("necromancer", [near, _unit("occupant", "knight", Vector2i(4, 3)),
		far, _unit("enemy", "harpooner", Vector2i(8, 3))], profile)
	state = rules.set_order(state, "necromancer", "order_raise_dead")
	var result := _round(state, "Raise Dead skips occupied corpse")
	if result.is_empty():
		return
	var zombies: Array = result.units.filter(func(unit): return unit.get("character_id") == "zombie" and unit.get("hp", 0) > 0)
	_check(zombies.size() == 1 and zombies[0].position == Vector2i(5, 3) \
		and not _entity(result, "near_corpse").is_empty(),
		"Raise Dead skips the nearer occupied corpse and raises the first legal corpse")
	_entity(result, "occupant").position = Vector2i(4, 4)
	var next := _round(result, "Raise Dead with living zombie")
	if not next.is_empty():
		_check(not _entity(next, "near_corpse").is_empty() \
			and next.units.filter(func(unit): return unit.get("character_id") == "zombie" and unit.get("hp", 0) > 0).size() == 1,
			"Raise Dead leaves another legal corpse alone while its zombie lives")
