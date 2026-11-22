extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/hero_upgrade_effects_test.gd
# Every combat value used here is test-owned. Forecasts and commits use the public rules API.
var rules = preload("res://rules.gd").new()
var catalog = preload("res://content/catalog.gd")
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(catalog.read_default())
	defs.abilities.healer_bonk.params.damage = 2
	defs.abilities.healer_heal.params.amount = 4
	defs.abilities.wizard_blast.params.damage = 4
	defs.abilities.wizard_pull.params.recoil_damage = 2
	defs.abilities.enemy_attack.params.damage = 2
	defs.abilities.enemy_harpoon.params.damage = 2
	defs.abilities.offer_flower.params.damage = 1
	defs.abilities.goblin_jab.params.damage = 3
	defs.abilities.goblin_jab.params.surround_bonus.damage = 2
	defs.characters.harpooner.behavior = "hold"
	defs.characters.harpooner.abilities = catalog.profile(defs, "harpooner").abilities.duplicate()
	defs.characters.harpooner.abilities.append("wizard_pull")
	defs.characters.ferryman.behavior = "hold"
	_test_healer()
	_test_wizard()
	_test_rogue()
	_test_bard()
	_test_necromancer()
	_test_knight()
	_test_rogue_control_upgrades()
	_test_goblin_redirect_surround()
	_test_bard_control_upgrades()
	_test_necromancer_control_upgrades()
	_test_autonomous_broad_wave()
	_test_broad_wave_equal_distance_choice()
	_test_long_stemmed_greeting_roll()
	if failures.is_empty():
		print("PASS: hero upgrade effects")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp := 20, upgrades := {}) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos, "hp": hp,
		"max_hp": 20, "statuses": {}, "upgrades": upgrades.duplicate(true)}


func _state(units: Array) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = units
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	state.rng_state = 12345
	return state


func _find(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _ids(options: Array) -> Array:
	var result := []
	for option in options:
		result.append(option.get("id", ""))
	return result


func _action(state: Dictionary, actor: String, ability: String, target := "") -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, actor, ability, target)
	_check(state == before and plan == rules.preview(state, actor, ability, target),
		ability + " forecast is pure and repeatable")
	_check(plan.get("valid", false), ability + " must be legal in the fixture")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.apply_plan(state, plan)
	_check(state == before and result == plan.get("result"), ability + " commits its forecast")
	return result


func _round(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and state == before and plan == rules.preview_round(state),
		label + " round forecast is legal, pure and repeatable")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.commit_round(state, plan)
	_check(state == before and result == plan.get("result"), label + " round commits its forecast")
	return result


func _test_healer() -> void:
	var upgrades := {"healer_bonk_damage_1": 2, "healer_bonk_damage_2": 1,
		"healer_long_staff": 1, "healer_strong_swing": 1}
	var state := _state([_unit("h", "healer", Vector2i(3, 3), 20, upgrades),
		_unit("a", "harpooner", Vector2i(5, 3)),
		_unit("b", "harpooner", Vector2i(3, 4)),
		_unit("far", "harpooner", Vector2i(6, 3)),
		_unit("ally", "knight", Vector2i(3, 2))])
	var result := _action(state, "h", "healer_bonk", "a")
	if not result.is_empty():
		_check(_find(result, "a").hp == 14 and _find(result, "b").hp == 14,
			"Long Staff and Strong Swing bonk each in-range opponent for stacked damage")
		_check(_find(result, "far").hp == 20 and _find(result, "ally").hp == 20,
			"Strong Swing excludes out-of-range opponents and allies")
	var healing := {"healer_me_or_you": 1, "healer_heal_1": 2, "healer_heal_2": 1}
	state = _state([_unit("h", "healer", Vector2i(3, 3), 10, healing),
		_unit("a", "knight", Vector2i(4, 3), 10), _unit("b", "wizard", Vector2i(3, 4), 10)])
	result = _action(state, "h", "healer_heal")
	if not result.is_empty():
		_check(_find(result, "h").hp == 18 and _find(result, "a").hp == 10 and _find(result, "b").hp == 10,
			"Me or You sends the whole stacked heal to wounded Healer")
	_find(state, "h").hp = 20
	result = _action(state, "h", "healer_heal")
	if not result.is_empty():
		_check(_find(result, "a").hp == 14 and _find(result, "b").hp == 14,
			"Full Healer divides an evenly divisible stacked heal among teammates")
	state = _state([_unit("h", "healer", Vector2i(3, 3), 20, {"healer_me_or_you": 1}),
		_unit("full", "knight", Vector2i(4, 3)),
		_unit("hurt", "wizard", Vector2i(3, 4), 10),
		_unit("summon", "skeleton", Vector2i(2, 3), 1)])
	# A summon mistakenly present in party bookkeeping must still be excluded.
	state.party = ["h", "full", "summon", "hurt"]
	_find(state, "summon").summoner_id = "h"
	result = _action(state, "h", "healer_heal")
	if not result.is_empty():
		_check(_find(result, "full").hp == 20 and _find(result, "hurt").hp == 12,
			"Full teammate receives and loses its equal heal share rather than redistributing it")
		_check(_find(result, "summon").hp == 1, "Summons do not receive a share of split healing")
	defs.abilities.healer_heal.params.amount = 5
	state = _state([_unit("h", "healer", Vector2i(3, 3), 20, {"healer_me_or_you": 1}),
		_unit("a", "knight", Vector2i(4, 3), 10), _unit("b", "wizard", Vector2i(3, 4), 10)])
	state.party = ["h", "b", "a"]
	result = _action(state, "h", "healer_heal")
	if not result.is_empty():
		_check(_find(result, "a").hp == 12 and _find(result, "b").hp == 13,
			"Split heal distributes remainder in party order, not unit-array order")
	defs.abilities.healer_heal.params.amount = 4


func _test_wizard() -> void:
	var state := _state([_unit("w", "wizard", Vector2i(3, 3), 20,
		{"wizard_more_powder": 2, "wizard_duck": 1, "wizard_conductive_personality": 1}),
		_unit("ally", "knight", Vector2i(4, 3)),
		_unit("enemy", "harpooner", Vector2i(9, 9))])
	var result := _action(state, "w", "wizard_blast")
	if not result.is_empty():
		_check(_find(result, "ally").hp == 14 and not rules.has_status_handler(result, "ally", "skip_action"),
			"Duck preserves ally footing but stacked Blast still damages")
		_check(_find(result, "w").hp == 17 and not rules.has_status_handler(result, "w", "skip_action"),
			"Conductive Personality can hit the Wizard for half damage without knockdown")
	state = _state([_unit("w", "wizard", Vector2i(2, 1), 20,
		{"wizard_padded_landing": 2, "wizard_braced_casting": 1}),
		_unit("enemy", "harpooner", Vector2i(5, 1))])
	result = _action(state, "w", "wizard_pull", "enemy")
	if not result.is_empty():
		_check(_find(result, "w").hp == 20 and rules.has_status_handler(result, "w", "skip_action"),
			"Padded Landing floors recoil at zero but does not prevent falling in open space")
	_find(state, "w").position = Vector2i(1, 1)
	result = _action(state, "w", "wizard_pull", "enemy")
	if not result.is_empty():
		_check(not rules.has_status_handler(result, "w", "skip_action"),
			"Braced Casting prevents falling when recoil hits board edge")
	state = _state([_unit("w", "wizard", Vector2i(1, 1), 20,
		{"wizard_parting_gift": 1, "wizard_more_powder": 1}),
		_unit("enemy", "harpooner", Vector2i(2, 1))])
	result = _action(state, "w", "wizard_blast")
	if not result.is_empty():
		_check(_find(result, "enemy").hp == 15 and _find(result, "enemy").position == Vector2i(3, 1),
			"Parting Gift pushes the surviving primary target after Blast")
	state = _state([_unit("w", "wizard", Vector2i(1, 1), 20,
		{"wizard_demolition_practice": 2, "wizard_more_powder": 1})])
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(2, 1),
		"hp": 20, "max_hp": 20, "statuses": {}}]
	result = _action(state, "w", "wizard_blast")
	if not result.is_empty():
		_check(result.obstacles[0].hp == 11, "Demolition Practice stacks with powder against obstacles")


func _test_rogue() -> void:
	var state := _state([_unit("r", "rogue", Vector2i(1, 1), 20,
		{"rogue_long_finger": 1, "rogue_cheap_shot": 2}),
		_unit("attacker", "harpooner", Vector2i(4, 4)),
		_unit("victim", "harpooner", Vector2i(4, 6)),
		_unit("hero", "knight", Vector2i(3, 4))])
	var marked := _action(state, "r", "rogue_wasnt_me", "attacker")
	if not marked.is_empty():
		var result := _action(marked, "attacker", "enemy_attack", "hero")
		if not result.is_empty():
			_check(_find(result, "hero").hp == 20 and _find(result, "victim").hp == 16,
				"Long Finger redirects to range-two alternate with stacked Cheap Shot")
	state = _state([_unit("r", "rogue", Vector2i(2, 2), 20, {"rogue_body_double": 1}),
		_unit("partner", "knight", Vector2i(8, 2)),
		_unit("attacker", "harpooner", Vector2i(7, 2))])
	var swapped := _action(state, "r", "rogue_confusing_dodge")
	if not swapped.is_empty():
		var result := _action(swapped, "attacker", "enemy_attack", "r")
		if not result.is_empty():
			_check(_find(result, "r").hp == 20 and _find(result, "partner").hp == 18,
				"Body Double redirects the first attack to the living ally at its distant landing tile")
			var next := _action(result, "attacker", "enemy_attack", "r")
			if not next.is_empty():
				_check(_find(next, "r").hp == 18, "Body Double is consumed after one attack")


func _test_bard() -> void:
	var state := _state([_unit("bard", "bard", Vector2i(1, 1), 20,
		{"bard_house_lights": 1, "bard_sharper_notes": 2}),
		_unit("a", "harpooner", Vector2i(7, 7)),
		_unit("b", "harpooner", Vector2i(7, 8)),
		_unit("ally", "knight", Vector2i(6, 7))])
	_check("bard_take_the_stage" in _ids(rules.options(state, "bard"))
		and "order_take_the_stage" in _ids(rules.options(state, "bard")),
		"House Lights exposes direct action and standing order")
	var result := _action(state, "bard", "bard_take_the_stage")
	if not result.is_empty():
		_check(_find(result, "a").hp == 17 and _find(result, "b").hp == 17
			and _find(result, "ally").hp == 20,
			"Take the Stage applies stacked Sonnet damage to adjacent opponents only")
	state = _state([_unit("bard", "bard", Vector2i(1, 1), 10, {"bard_buskers_hat": 2})])
	result = _action(state, "bard", "inspiring_melody")
	if not result.is_empty():
		_check(_find(result, "bard").hp == 12, "Dry Melody heals once per Busker's Hat stack")


func _test_necromancer() -> void:
	var state := _state([_unit("n", "necromancer", Vector2i(3, 3), 20,
		{"necromancer_spare_ribs": 3, "necromancer_good_soil": 2,
		"necromancer_say_hello_to_that_one": 1}),
		_unit("corpse", "harpooner", Vector2i(4, 3), 0),
		_unit("enemy", "harpooner", Vector2i(9, 9))])
	_check("necromancer_say_hello_to_that_one" in _ids(rules.options(state, "n")),
		"Say Hello to That One grants a direct order")
	var raised := _action(state, "n", "raise_dead", "corpse")
	if raised.is_empty():
		return
	var zombies := []
	for unit in raised.units:
		if unit.get("character_id") == "zombie" and unit.get("hp", 0) > 0:
			zombies.append(unit)
	_check(zombies.size() == 1 and zombies[0].get("max_hp") == 12,
		"Good Soil adds stacks after calculating half the corpse maximum")
	var targets: Array = rules.targets(raised, "n", "summon_skeleton")
	_check(not targets.is_empty(), "Skeleton has an open summon tile")
	if targets.is_empty():
		return
	var both := _action(raised, "n", "summon_skeleton", str(targets[0].id))
	if both.is_empty():
		return
	var skeletons := []
	for unit in both.units:
		if unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0:
			skeletons.append(unit)
	_check(skeletons.size() == 1 and skeletons[0].get("max_hp") == 4,
		"Spare Ribs stacks on skeleton starting HP")
	if skeletons.is_empty() or zombies.is_empty():
		return
	_find(both, "n").upgrades.merge({"necromancer_broad_wave": 1,
		"necromancer_heavy_bouquet": 2, "necromancer_long_stemmed": 1,
		"necromancer_warm_welcome": 1})
	var skeleton_id: String = skeletons[0].id
	var zombie_id: String = zombies[0].id
	_find(both, skeleton_id).position = Vector2i(5, 5)
	_find(both, zombie_id).position = Vector2i(1, 1)
	_find(both, "enemy").position = Vector2i(6, 6)
	_find(both, "n").position = Vector2i(4, 4)
	var waved := _action(both, skeleton_id, "wave")
	if not waved.is_empty():
		_check(_find(waved, "enemy").hp == 19 and _find(waved, "n").hp == 19,
			"Broad Wave hits diagonal opponents and friends")
	_find(both, "enemy").position = Vector2i(4, 1)
	var flower := _action(both, zombie_id, "offer_flower", "enemy")
	if not flower.is_empty():
		_check(_find(flower, "enemy").hp == 17,
			"Long-Stemmed reaches three and Heavy Bouquet stacks on Flower")
	_find(both, "enemy").position = Vector2i(2, 1)
	var hello := _action(both, zombie_id, "say_hello")
	if not hello.is_empty():
		_check(_find(hello, "enemy").position == Vector2i(4, 1),
			"Warm Welcome moves the nearest recipient two tiles")


func _test_knight() -> void:
	var state := _state([_unit("k", "knight", Vector2i(2, 2), 20,
		{"knight_shield_throw": 1, "knight_shield_damage_1": 3, "knight_shield_damage_3": 1}),
		_unit("enemy", "harpooner", Vector2i(5, 2))])
	var no_upgrade := state.duplicate(true)
	_find(no_upgrade, "k").upgrades = {}
	_check("knight_shield_throw" not in _ids(rules.options(no_upgrade, "k")),
		"Shield Throw is not available without the reward")
	_check("knight_shield_throw" in _ids(rules.options(state, "k")), "Shield Throw grants a direct action")
	var thrown := _action(state, "k", "knight_shield_throw", "enemy")
	if not thrown.is_empty():
		_check(_find(thrown, "enemy").hp == 11, "Shield Throw uses range three and stacked shield damage")
		_check(not rules.preview(thrown, "k", "knight_aura").get("valid", false)
			and not rules.preview(thrown, "k", "knight_shield_throw", "enemy").get("valid", false),
			"Knight cannot guard or throw again while shield is away")
		var moved := _action(thrown, "k", "move", "3,2")
		if not moved.is_empty():
			_check(not rules.preview(moved, "k", "knight_aura").get("valid", false),
				"Moving outside retrieval range does not pick up shield")
			var retrieved := _action(moved, "k", "move", "4,2")
			if not retrieved.is_empty():
				_check(rules.preview(retrieved, "k", "knight_aura").get("valid", false),
					"Movement ending adjacent to impact tile retrieves shield despite occupying enemy")
		var ordered: Dictionary = rules.set_order(thrown, "k", "order_advance")
		var advanced := _round(ordered, "Advance toward shield")
		if not advanced.is_empty():
			_check(_find(advanced, "k").position.distance_to(Vector2i(5, 2)) < 3.0,
				"Advance moves toward the dropped shield rather than remaining stuck")
	state = _state([_unit("k", "knight", Vector2i(3, 3), 20, {"knight_dig_in": 1}),
		_unit("attacker", "harpooner", Vector2i(5, 3))])
	var guarding := _action(state, "k", "knight_aura")
	if not guarding.is_empty():
		var pulled := _action(guarding, "attacker", "wizard_pull", "k")
		if not pulled.is_empty():
			_check(_find(pulled, "k").position == Vector2i(3, 3)
				and _find(pulled, "attacker").position != Vector2i(5, 3),
				"Dig In reverses a pull while guarding")
	_test_dig_in_hook_legality()


func _test_dig_in_hook_legality() -> void:
	var state := _state([_unit("k", "knight", Vector2i(3, 3), 20, {"knight_dig_in": 1}),
		_unit("hookhand", "hookhand", Vector2i(5, 3)),
		_unit("blocker", "wizard", Vector2i(4, 3))])
	var guarded := _action(state, "k", "knight_aura")
	if guarded.is_empty():
		return
	var before := guarded.duplicate(true)
	_check("k" not in _ids(rules.targets(guarded, "hookhand", "hook_pull"))
		and not rules.preview(guarded, "hookhand", "hook_pull", "k").get("valid", false)
		and guarded == before, "Dig In must not make a blocked Hook Pull legal")
	var ordinary := guarded.duplicate(true)
	_find(ordinary, "k").upgrades = {}
	_check("k" not in _ids(rules.targets(ordinary, "hookhand", "hook_pull"))
		and not rules.preview(ordinary, "hookhand", "hook_pull", "k").get("valid", false),
		"Blocked Hook Pull is also illegal without Dig In")
	_find(guarded, "blocker").position = Vector2i(4, 4)
	var reversed := _action(guarded, "hookhand", "hook_pull", "k")
	if not reversed.is_empty():
		_check(_find(reversed, "hookhand").position == Vector2i(4, 3)
			and _find(reversed, "k").position == Vector2i(3, 3),
			"An unblocked Hook Pull still reverses toward the guarded Knight")
	var adjacent := _state([_unit("wizard", "wizard", Vector2i(4, 3)),
		_unit("target", "harpooner", Vector2i(3, 3))])
	var pulled := _action(adjacent, "wizard", "wizard_pull", "target")
	if not pulled.is_empty():
		_check(_find(pulled, "target").position == Vector2i(4, 3)
			and _find(pulled, "wizard").position == Vector2i(5, 3)
			and rules.has_status_handler(pulled, "wizard", "skip_action"),
			"Adjacent ordinary Wizard Pull remains legal and causes its normal recoil and knockdown")


func _test_rogue_control_upgrades() -> void:
	# The marked, furthest enemy lands beside the recipient when Dodge swaps it.
	var state := _state([_unit("r", "rogue", Vector2i(2, 2), 20,
		{"rogue_pass_the_buck": 1, "rogue_pocket_sand": 1}),
		_unit("marked", "harpooner", Vector2i(8, 2)),
		_unit("original_alternate", "harpooner", Vector2i(8, 3)),
		_unit("recipient", "harpooner", Vector2i(2, 3))])
	var marked := _action(state, "r", "rogue_wasnt_me", "marked")
	if not marked.is_empty():
		# Make the marked enemy unambiguously furthest while retaining its mark.
		_find(marked, "original_alternate").position = Vector2i(6, 3)
		var dodged := _action(marked, "r", "rogue_confusing_dodge")
		if not dodged.is_empty():
			_check(not rules.has_status_handler(dodged, "marked", "misdirect")
				and rules.has_status_handler(dodged, "recipient", "misdirect"),
				"Pass the Buck transfers an unspent mark to an enemy next to the swap landing")
			_check(not rules.preview(dodged, "marked", "move", "1,2").get("valid", false)
				and rules.preview(dodged, "marked", "enemy_attack", "recipient").get("valid", false),
				"Pocket Sand prevents the swapped enemy moving without preventing attack")

	state = _state([_unit("r", "rogue", Vector2i(2, 2), 20, {"rogue_borrowed_courage": 2}),
		_unit("ally", "knight", Vector2i(8, 2)),
		_unit("attacker", "harpooner", Vector2i(2, 3))])
	var swapped := _action(state, "r", "rogue_confusing_dodge")
	if not swapped.is_empty():
		var hit := _action(swapped, "attacker", "enemy_attack", "ally")
		if not hit.is_empty():
			_check(_find(hit, "ally").hp == 20, "Borrowed Courage stacks to reduce the next hit by two")
			var second := _action(hit, "attacker", "enemy_attack", "ally")
			if not second.is_empty():
				_check(_find(second, "ally").hp == 18, "Borrowed Courage protects only one hit")

	state = _state([_unit("r", "rogue", Vector2i(4, 4), 20, {"rogue_exit_strategy": 1}),
		_unit("enemy", "harpooner", Vector2i(5, 4)),
		_unit("civilian", "ferryman", Vector2i(10, 10))])
	var direct := _action(state, "r", "move", "3,4")
	if not direct.is_empty():
		_check(_find(direct, "r").position == Vector2i(3, 4)
			and not rules.preview(state, "r", "move", "2,4").get("valid", false),
			"Exit Strategy does not extend direct Move")
	var ordered: Dictionary = rules.set_order(state, "r", "order_retreat")
	var retreated := _round(ordered, "Exit Strategy")
	if not retreated.is_empty():
		_check(_find(retreated, "r").position == Vector2i(2, 4),
			"Exit Strategy takes a second retreat step that increases distance: %s" % _find(retreated, "r").position)


func _test_goblin_redirect_surround() -> void:
	# Only the alternate is adjacent to the attacker. Move a separate goblin
	# between adjacency to the original and adjacency to the actual victim.
	for crowd_actual in [false, true]:
		var helper := Vector2i(6, 4) if crowd_actual else Vector2i(3, 3)
		var state := _state([_unit("rogue", "rogue", Vector2i(1, 1)),
			_unit("attacker", "goblin", Vector2i(4, 4)),
			_unit("original", "knight", Vector2i(3, 4)),
			_unit("alternate", "goblin", Vector2i(5, 4)),
			_unit("helper", "goblin", helper)])
		var marked := _action(state, "rogue", "rogue_wasnt_me", "attacker")
		if marked.is_empty():
			continue
		var before := marked.duplicate(true)
		var plan: Dictionary = rules.preview(marked, "attacker", "goblin_jab", "original")
		_check(plan.get("valid", false) and marked == before
			and plan == rules.preview(marked, "attacker", "goblin_jab", "original"),
			"Redirected goblin Jab forecasts without mutation")
		if not plan.get("valid", false):
			continue
		var result: Dictionary = rules.apply_plan(marked, plan)
		_check(result == plan.get("result") and marked == before, "Redirected Jab commits its forecast")
		var damage := 5 if crowd_actual else 3
		_check(_find(result, "original").hp == 20 and _find(result, "alternate").hp == 20 - damage,
			"Surround bonus follows the redirected victim, not the original (actual crowded=%s)" % crowd_actual)
		var surround_targets := []
		for event in plan.get("events", []):
			if event.get("type") == "surround":
				surround_targets.append(event.get("target_id", ""))
		_check(surround_targets == (["alternate"] if crowd_actual else []),
			"Surround forecast names only the actual crowded victim")
		_check(not rules.has_status_handler(result, "attacker", "misdirect"),
			"Redirected Jab consumes the Wasn't Me mark")


func _test_bard_control_upgrades() -> void:
	# The second-lowest HP is tied; all three weak candidates are eligible.
	var seen := {}
	for seed_value in range(1, 65):
		var state := _state([_unit("bard", "bard", Vector2i(1, 1), 20,
			{"bard_front_row_seats": 1}),
			_unit("a", "harpooner", Vector2i(7, 7), 5),
			_unit("b", "harpooner", Vector2i(8, 7), 8),
			_unit("c", "harpooner", Vector2i(9, 7), 8),
			_unit("strong", "harpooner", Vector2i(10, 7), 15)])
		state.rng_state = seed_value
		var result := _action(state, "bard", "healing_sonnet")
		if result.is_empty():
			return
		_check(_find(result, "strong").hp == 15, "Front Row excludes opponents above the tied cutoff")
		for id in ["a", "b", "c"]:
			if _find(result, id).hp < _find(state, id).hp:
				seen[id] = true
	_check(seen.size() == 3, "Front Row includes both opponents tied at the second-lowest HP")

	var state := _state([_unit("bard", "bard", Vector2i(1, 1), 20, {"bard_laughing_fit": 1}),
		_unit("enemy", "harpooner", Vector2i(5, 5)),
		_unit("attacker", "wizard", Vector2i(5, 4)),
		_unit("civilian", "ferryman", Vector2i(10, 10))])
	state = rules.set_order(state, "bard", "order_inspiring_melody")
	var laughed := _round(state, "Laughing Fit")
	if not laughed.is_empty():
		# Push collision is not needed: use a controlled adjacent Bonk to observe the next hit.
		_find(laughed, "attacker").character_id = "healer"
		var hit := _action(laughed, "attacker", "healer_bonk", "enemy")
		if not hit.is_empty():
			_check(_find(hit, "enemy").hp == 16, "Laughing Fit adds two to the first hit after a lost turn")
			var second := _action(hit, "attacker", "healer_bonk", "enemy")
			if not second.is_empty():
				_check(_find(second, "enemy").hp == 14, "Laughing Fit bonus is consumed after one hit")

	# Direct enemy attacks test legal-target redirection without coupling to autonomous target policy.
	state = _state([_unit("bard", "bard", Vector2i(3, 3), 20, {"bard_heckler": 1}),
		_unit("enemy", "harpooner", Vector2i(4, 3)),
		_unit("ally", "knight", Vector2i(4, 4))])
	var sung := _action(state, "bard", "healing_sonnet")
	if not sung.is_empty():
		var attack := _action(sung, "enemy", "enemy_attack", "ally")
		if not attack.is_empty():
			_check(_find(attack, "bard").hp == 18 and _find(attack, "ally").hp == 20,
				"Heckler directs the surviving listener's next legal attack to Bard")


func _test_necromancer_control_upgrades() -> void:
	var state := _state([_unit("n", "necromancer", Vector2i(2, 2), 20,
		{"necromancer_wake_reception": 1, "necromancer_spare_ribs": 2,
		"necromancer_say_hello_to_that_one": 1}),
		_unit("corpse", "harpooner", Vector2i(3, 2), 0),
		_unit("corpse2", "harpooner", Vector2i(2, 3), 0),
		_unit("attacker", "harpooner", Vector2i(4, 2)),
		_unit("target", "harpooner", Vector2i(9, 8)),
		_unit("civilian", "ferryman", Vector2i(10, 10))])
	var raised := _action(state, "n", "raise_dead", "corpse")
	if raised.is_empty():
		return
	var zombie := {}
	for unit in raised.units:
		if unit.get("character_id") == "zombie" and unit.get("hp", 0) > 0:
			zombie = unit
	if zombie.is_empty():
		_check(false, "Wake Reception fixture raises a zombie")
		return
	zombie.hp = 2
	var fallen := _action(raised, "attacker", "enemy_attack", zombie.id)
	if fallen.is_empty():
		return
	var skeletons := []
	for unit in fallen.units:
		if unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0:
			skeletons.append(unit)
	_check(skeletons.size() == 1, "Wake Reception produces a skeleton when the raised zombie falls")
	if skeletons.is_empty():
		return
	_check(skeletons[0].position == Vector2i(3, 2) and skeletons[0].hp == 3,
		"Wake Reception uses the zombie's tile and improved skeleton HP")
	var with_zombie := _action(fallen, "n", "raise_dead", "corpse2")
	if with_zombie.is_empty():
		return
	var zombie_id := ""
	for unit in with_zombie.units:
		if unit.get("character_id") == "zombie" and unit.get("hp", 0) > 0:
			zombie_id = unit.id
	if zombie_id.is_empty():
		_check(false, "Nominee fixture has a second living zombie")
		return
	# The named distant enemy must draw both summons away from the nearer attacker.
	var targets: Array = rules.targets(with_zombie, "n", "necromancer_say_hello_to_that_one")
	_check("target" in _ids(targets), "Nomination offers a living opponent")
	var nominated := _action(with_zombie, "n", "necromancer_say_hello_to_that_one", "target")
	if nominated.is_empty():
		return
	var skeleton_id: String = skeletons[0].id
	_find(nominated, skeleton_id).position = Vector2i(5, 5)
	_find(nominated, zombie_id).position = Vector2i(5, 7)
	_find(nominated, "attacker").position = Vector2i(3, 6)
	var before: Vector2i = _find(nominated, skeleton_id).position
	var zombie_before: Vector2i = _find(nominated, zombie_id).position
	var after := _round(nominated, "Nominee pursuit")
	if not after.is_empty():
		var position: Vector2i = _find(after, skeleton_id).get("position", before)
		_check(position.distance_to(Vector2i(9, 8)) < before.distance_to(Vector2i(9, 8)),
			"Skeleton pursues the nominated distant opponent rather than the nearer attacker")
		var zombie_after: Vector2i = _find(after, zombie_id).get("position", zombie_before)
		_check(zombie_after.distance_to(Vector2i(9, 8)) < zombie_before.distance_to(Vector2i(9, 8)),
			"Zombie also pursues the nominated distant opponent: %s -> %s" % [zombie_before, zombie_after])


func _test_autonomous_broad_wave() -> void:
	var greetings: Array = defs.behaviors.skeleton_greetings.params.greetings.duplicate()
	defs.behaviors.skeleton_greetings.params.greetings = ["wave"]
	for broad in [false, true]:
		var upgrades := {"necromancer_broad_wave": 1} if broad else {}
		var state := _state([_unit("n", "necromancer", Vector2i(1, 1), 20, upgrades),
			_unit("enemy", "harpooner", Vector2i(5, 5)),
			_unit("civilian", "ferryman", Vector2i(10, 10))])
		var placements: Array = rules.targets(state, "n", "summon_skeleton")
		_check(not placements.is_empty(), "Autonomous Wave fixture can summon a skeleton")
		if placements.is_empty():
			continue
		var spawned := _action(state, "n", "summon_skeleton", str(placements[0].id))
		if spawned.is_empty():
			continue
		var skeleton := {}
		for unit in spawned.units:
			if unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0:
				skeleton = unit
		if skeleton.is_empty():
			_check(false, "Autonomous Wave fixture has a living spawned skeleton")
			continue
		var id: String = skeleton.id
		skeleton.position = Vector2i(4, 4)
		_check(rules.options(spawned, id).is_empty(), "Skeleton cannot receive player commands")
		var attempted: Dictionary = rules.choose_manual(spawned, id, "wave")
		_check(attempted == spawned, "Player cannot reserve a skeleton Wave override")
		var next := _round(spawned, "Autonomous diagonal Wave broad=%s" % broad)
		if next.is_empty():
			continue
		if broad:
			_check(_find(next, id).position == Vector2i(4, 4) and _find(next, "enemy").hp == 19,
				"Broad Wave skeleton autonomously Waves the diagonal enemy without moving")
		else:
			var moved: Vector2i = _find(next, id).position
			_check(_find(next, "enemy").hp == 20 and moved != Vector2i(4, 4)
				and absi(moved.x - 5) + absi(moved.y - 5) == 1,
				"Ordinary skeleton pursues to cardinal Wave range instead of hitting diagonally")
			var greeted := _round(next, "Ordinary skeleton reaches Wave range")
			if not greeted.is_empty():
				_check(_find(greeted, "enemy").hp == 19,
					"Ordinary skeleton Waves on the next activation after pursuing")
	defs.behaviors.skeleton_greetings.params.greetings = greetings


func _test_long_stemmed_greeting_roll() -> void:
	var greetings: Array = defs.behaviors.zombie_greetings.params.greetings.duplicate()
	defs.behaviors.zombie_greetings.params.greetings = ["say_hello", "offer_flower"]
	for upgraded in [false, true]:
		for seed_value in range(1, 17):
			var upgrades := {"necromancer_long_stemmed": 1} if upgraded else {}
			var state := _state([_unit("n", "necromancer", Vector2i(1, 1), 20, upgrades),
				_unit("corpse", "harpooner", Vector2i(2, 1), 0),
				_unit("enemy", "harpooner", Vector2i(7, 4)),
				_unit("civilian", "ferryman", Vector2i(10, 10))])
			var raised := _action(state, "n", "raise_dead", "corpse")
			if raised.is_empty():
				continue
			var zombie := {}
			for unit in raised.units:
				if unit.get("character_id") == "zombie" and unit.get("hp", 0) > 0:
					zombie = unit
			if zombie.is_empty():
				_check(false, "Long-Stemmed fixture raises a zombie")
				continue
			var id: String = zombie.id
			zombie.position = Vector2i(4, 4)
			raised.rng_state = seed_value
			var before := raised.duplicate(true)
			var plan: Dictionary = rules.preview_round(raised)
			_check(plan.get("valid", false) and raised == before and plan == rules.preview_round(raised),
				"Long-Stemmed greeting forecast is pure and repeatable")
			if not plan.get("valid", false):
				continue
			var result: Dictionary = rules.commit_round(raised, plan)
			_check(result == plan.get("result") and raised == before,
				"Long-Stemmed greeting commits the exact RNG forecast")
			var attacks := []
			for event in plan.get("events", []):
				if event.get("source_id") == id and event.get("type") == "damage":
					attacks.append(event.get("target_id", ""))
			if upgraded:
				_check(_find(result, id).position == Vector2i(4, 4)
					and _find(result, "enemy").position == Vector2i(7, 4)
					and _find(result, "enemy").hp == 19 and attacks == ["enemy"],
					"At range three Long-Stemmed rolls only Flower, not Say Hello (seed %d)" % seed_value)
				_check(result.rng_state != seed_value,
					"An eligible Flower advances the actual greeting RNG")
			else:
				_check(_find(result, id).position != Vector2i(4, 4)
					and _find(result, "enemy").hp == 20 and attacks.is_empty()
					and result.rng_state == seed_value,
					"Without Long-Stemmed zombie pursues without rolling a range-three greeting")
	defs.behaviors.zombie_greetings.params.greetings = greetings


func _test_broad_wave_equal_distance_choice() -> void:
	var greetings: Array = defs.behaviors.skeleton_greetings.params.greetings.duplicate()
	defs.behaviors.skeleton_greetings.params.greetings = ["wave"]
	for reverse_order in [false, true]:
		var cardinal := _unit("a_cardinal", "harpooner", Vector2i(6, 4))
		var diagonal := _unit("z_diagonal", "harpooner", Vector2i(5, 5))
		var opponents := [diagonal, cardinal] if reverse_order else [cardinal, diagonal]
		var units := [_unit("n", "necromancer", Vector2i(1, 1), 20,
			{"necromancer_broad_wave": 1, "necromancer_say_hello_to_that_one": 1})]
		units.append_array(opponents)
		units.append(_unit("civilian", "ferryman", Vector2i(10, 10)))
		var state := _state(units)
		var placements: Array = rules.targets(state, "n", "summon_skeleton")
		if placements.is_empty():
			_check(false, "Equal-distance Wave fixture has a summon placement")
			continue
		var spawned := _action(state, "n", "summon_skeleton", str(placements[0].id))
		if spawned.is_empty():
			continue
		var skeleton := {}
		for unit in spawned.units:
			if unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0:
				skeleton = unit
		if skeleton.is_empty():
			_check(false, "Equal-distance Wave fixture summons a skeleton")
			continue
		var id: String = skeleton.id
		skeleton.position = Vector2i(4, 4)
		var next := _round(spawned, "Equal-distance Wave order reversed=%s" % reverse_order)
		if not next.is_empty():
			_check(_find(next, id).position == Vector2i(4, 4)
				and _find(next, "z_diagonal").hp == 19 and _find(next, "a_cardinal").hp == 20,
				"Broad Wave uses an already hittable tied opponent regardless of unit order")
		var nominated := _action(spawned, "n", "necromancer_say_hello_to_that_one", "a_cardinal")
		if not nominated.is_empty():
			var focused := _round(nominated, "Equal-distance Wave with nomination")
			if not focused.is_empty():
				_check(_find(focused, id).position != Vector2i(4, 4)
					and _find(focused, "z_diagonal").hp == 20,
					"Explicit nomination still directs skeleton toward the unhittable opponent")
	defs.behaviors.skeleton_greetings.params.greetings = greetings
