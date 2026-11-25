extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/alchemist_test.gd
# Test-owned geometry, through the same public rules API used by play.
var rules = preload("res://rules/rules.gd").new()
var catalog = preload("res://content/catalog.gd")
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(catalog.read_default())
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	var state := _state()
	var potion := _option(state, "action", "healing potion")
	var acid := _option(state, "action", "acid")
	_check(not potion.is_empty(), "Alchemist offers a Healing Potion action")
	_check(not acid.is_empty(), "Alchemist offers an Acid action")
	_test_reaction_pool()
	_test_ball_bearings_pull()
	if not potion.is_empty() and not acid.is_empty():
		_test_targets(state, potion, acid)
		_test_forecasts(state, potion, acid)
		_test_orders(state, potion, acid)
		_test_pursuit()
		_test_reaction_effects(acid)
		_test_jelly_knees_wagon(potion)
		_test_reward_actions(potion, acid)
		_test_numeric_upgrades(potion, acid)
		_test_heal_modifiers()
		_test_reaction_movement()
		_test_round_end_reactions()
		_test_nearest_self(potion)
		_test_authored_status_collision(potion)
	_test_upgrade_pool()
	if failures.is_empty():
		print("PASS: Alchemist integration")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": hp, "max_hp": 20, "statuses": {}}


func _state(fixture_defs := {}) -> Dictionary:
	var state: Dictionary = rules.new_game(defs if fixture_defs.is_empty() else fixture_defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(5, 6),
		"hp": 10, "max_hp": 10, "statuses": {}}]
	state.units = [
		_unit("alchemist", "alchemist", Vector2i(5, 5)),
		_unit("ally", "knight", Vector2i(4, 5)),
		_unit("civilian", "ferryman", Vector2i(5, 4)),
		_unit("summon", "skeleton", Vector2i(6, 5)),
		_unit("far_ally", "wizard", Vector2i(3, 5)),
		_unit("enemy", "harpooner", Vector2i(8, 5)),
		_unit("far_enemy", "harpooner", Vector2i(9, 5))]
	state.orders = {"ally": "order_hold", "far_ally": "order_hold"}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	state.rng_state = 12345
	state.dose_seed = 12345
	return state


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _option(state: Dictionary, kind: String, label: String) -> String:
	for option in rules.options(state, "alchemist"):
		if option.get("kind") == kind and label in str(option.get("label", "")).to_lower():
			return str(option.get("id", ""))
	return ""


func _ids(options: Array) -> Array:
	return options.map(func(option: Dictionary) -> Variant: return option.get("id"))


func _test_targets(state: Dictionary, potion: String, acid: String) -> void:
	var targets := _ids(rules.targets(state, "alchemist", potion))
	for id in ["alchemist", "ally", "civilian", "summon"]:
		_check(id in targets, "Healing Potion can select adjacent friendly " + id)
	for id in ["far_ally", "enemy", "crate"]:
		_check(id not in targets and not rules.preview(state, "alchemist", potion, id).get("valid", false),
			"Healing Potion rejects " + id)
	targets = _ids(rules.targets(state, "alchemist", acid))
	_check("enemy" in targets, "Acid reaches a hostile at range three")
	for id in ["far_enemy", "ally", "civilian", "summon", "crate"]:
		_check(id not in targets and not rules.preview(state, "alchemist", acid, id).get("valid", false),
			"Acid rejects " + id)


func _test_forecasts(state: Dictionary, potion: String, acid: String) -> void:
	for action in [[potion, "ally", "heal"], [acid, "enemy", "damage"]]:
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview(state, "alchemist", action[0], action[1])
		_check(plan.get("valid", false) and state == before
			and plan == rules.preview(state, "alchemist", action[0], action[1]),
			action[0] + " forecast is valid, pure and repeatable")
		if not plan.get("valid", false):
			continue
		_check(rules.apply_plan(state, plan) == plan.get("result"),
			action[0] + " commits the complete forecast")
		var base := false
		for event in plan.get("events", []):
			if event.get("type") == action[2] and event.get("target_id") == action[1] \
					and event.get("ability_id") == action[0] and event.get("amount") == 1:
				base = true
		_check(base, action[0] + " applies its one-point primary effect to the chosen recipient")
	# Recipient selection must not reroll the actual reaction, not just RNG consumption.
	var a: Dictionary = rules.preview(state, "alchemist", potion, "ally")
	var b: Dictionary = rules.preview(state, "alchemist", potion, "civilian")
	if a.get("valid", false) and b.get("valid", false):
		var first := _reaction(a)
		var second := _reaction(b)
		_check(not first.is_empty() and not second.is_empty(), "Both potion forecasts expose a reaction")
		if not first.is_empty() and not second.is_empty():
			_check(first.get("reaction_id") == second.get("reaction_id")
				and first.get("category") == second.get("category"),
				"Choosing another recipient preserves the actual reaction")
			_check(first.get("target_id") == "ally" and second.get("target_id") == "civilian",
				"The same reaction identifies the chosen recipient")
			_check(_reaction(rules.preview(state, "alchemist", potion, "ally")) == first
				and rules.apply_plan(state, a) == a.get("result"),
				"The revealed reaction repeats in the forecast and its result commits")


func _test_orders(state: Dictionary, potion: String, acid: String) -> void:
	var order_ids := _ids(rules.options(state, "alchemist"))
	var potion_order := "order_make_rounds"
	var acid_order := "order_throw_samples"
	_check(potion_order in order_ids and acid_order in order_ids,
		"Alchemist exposes persistent potion and acid orders")
	if potion_order not in order_ids or acid_order not in order_ids:
		return
	# Remove the summon's autonomous action and hold all other units.
	state.units.erase(_entity(state, "summon"))
	_entity(state, "ally").hp = 4
	_entity(state, "civilian").hp = 8
	_entity(state, "far_ally").hp = 9
	for pair in [[potion_order, potion, "ally"], [acid_order, acid, "enemy"]]:
		var ordered: Dictionary = rules.set_order(state, "alchemist", pair[0])
		var before := ordered.duplicate(true)
		var plan: Dictionary = rules.preview_round(ordered)
		_check(plan.get("valid", false) and before == ordered and plan == rules.preview_round(ordered),
			pair[0] + " forecasts repeatably without mutation")
		if not plan.get("valid", false):
			continue
		_check(rules.commit_round(ordered, plan) == plan.get("result"),
			pair[0] + " commits the forecast")
		var found := false
		for event in plan.get("events", []):
			if event.get("ability_id") == pair[1] and event.get("target_id") == pair[2]:
				found = true
		_check(found, pair[0] + " selects the intended recipient " + pair[2])


func _test_upgrade_pool() -> void:
	var entries := []
	for upgrade in defs.get("upgrades", {}).values():
		if upgrade.get("hero_id") == "alchemist":
			entries.append(upgrade)
	_check(not entries.is_empty(), "Alchemist has an adventure upgrade pool")
	var adventure = preload("res://expedition/adventure.gd")
	var board: Array = preload("res://expedition/commissions.gd").board(defs, 12345)
	var fresh: Dictionary = adventure.start_commission(defs, board[0],
		["alchemist", "healer", "wizard"], 12345)
	_check(fresh.get("phase") == "route" and fresh.get("upgrades_by_id", {}).get("alchemist", {}).is_empty(),
		"Fresh commissions recruit Alchemist without carried upgrades")


func _test_pursuit() -> void:
	var state := _state()
	state.obstacles = []
	state.units = [_unit("alchemist", "alchemist", Vector2i(5, 5)),
		_unit("near", "knight", Vector2i(8, 5)),
		_unit("far", "wizard", Vector2i(1, 5)),
		_unit("enemy", "harpooner", Vector2i(5, 1)),
		_unit("civilian", "ferryman", Vector2i(11, 11))]
	state.orders = {"near": "order_hold", "far": "order_hold"}
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), "Alchemist pursuit round is valid")
	if not plan.get("valid", false):
		return
	var position: Vector2i = _entity(plan.get("result", {}), "alchemist").get("position", Vector2i(-1, -1))
	_check(position.x > 5 and position.y == 5,
		"Alchemist moves toward the closest other ally rather than self or a hostile")
	_check(rules.commit_round(state, plan) == plan.get("result"),
		"Alchemist pursuit commits its forecast")


func _reaction(plan: Dictionary) -> Dictionary:
	for event in plan.get("events", []):
		if event.get("type") == "alchemy_reaction":
			return event
	return {}


func _test_reaction_pool() -> void:
	var path := "res://rules/alchemy_reactions.gd"
	_check(ResourceLoader.exists(path), "Alchemy reaction catalog exists")
	if not ResourceLoader.exists(path):
		return
	var reactions: Script = load(path)
	var pools: Dictionary = reactions.get_script_constant_map().get("POOLS", {})
	for category in ["beneficial", "harmful", "cosmetic"]:
		var expected := 4 if category == "cosmetic" else 8
		var entries: Dictionary = pools.get(category, {})
		_check(entries.size() == expected, "%s pool contains %d distinct reactions" % [category, expected])
		for id in entries:
			var entry: Dictionary = entries[id]
			_check(not str(entry.get("label", "")).is_empty()
				and not str(entry.get("description", "")).is_empty(),
				"Reaction %s has a label and description" % id)
	if not reactions.has_method("draw"):
		_check(false, "Reaction catalog exposes seeded drawing")
		return
	for is_acid in [false, true]:
		var counts := {"beneficial": 0, "harmful": 0, "cosmetic": 0}
		var seed_value := 12345
		for index in range(5000):
			var draw: Dictionary = reactions.call("draw", seed_value, is_acid)
			var category: String = draw.get("category", "")
			var id: String = draw.get("id", "")
			if not counts.has(category) or not pools.get(category, {}).has(id) or not draw.has("seed"):
				_check(false, "Seeded draw selects an authored reaction and returns its next seed")
				return
			counts[category] += 1
			seed_value = int(draw.seed)
		var intended := "harmful" if is_acid else "beneficial"
		var contrary := "beneficial" if is_acid else "harmful"
		_check(absf(float(counts[intended]) / 5000.0 - 0.7) < 0.05
			and absf(float(counts[contrary]) / 5000.0 - 0.2) < 0.05
			and absf(float(counts.cosmetic) / 5000.0 - 0.1) < 0.05,
			"%s draws approximate 70/20/10 weighting: %s" % ["Acid" if is_acid else "Potion", counts])


func _test_reaction_effects(acid: String) -> void:
	# Freeze a controlled hit in the fixture catalog before creating the state.
	var fixture_defs := defs.duplicate(true)
	fixture_defs.abilities.healer_bonk.params.damage = 2
	var state := _state(fixture_defs)
	state.obstacles = []
	state.units = [_unit("alchemist", "alchemist", Vector2i(3, 3)),
		_unit("victim", "harpooner", Vector2i(4, 3)),
		_unit("healer", "healer", Vector2i(5, 3))]
	for case in [["emergency_crust", 1], ["thin_skinned", 3], ["upward_rain", 2]]:
		var dose := _find_dose(state, acid, case[0])
		_check(not dose.is_empty(), "Seeded Acid can produce " + case[0])
		if dose.is_empty():
			continue
		var reaction := _reaction(dose.plan)
		_check(reaction.get("target_id") == "victim" and reaction.get("unit_id") == "alchemist",
			case[0] + " is forecast on the nonhero recipient")
		var after: Dictionary = rules.apply_plan(dose.state, dose.plan)
		_check(after == dose.plan.get("result"), case[0] + " dose commits its forecast")
		_check(_entity(after, "victim").get("hp") == 9, case[0] + " retains Acid's one-point damage")
		if case[0] == "upward_rain":
			var before_victim := _entity(state, "victim").duplicate(true)
			before_victim.hp = 9
			_check(_entity(after, "victim") == before_victim,
				"Upward Rain has no mechanical effect beyond Acid's damage")
		var first: Dictionary = rules.preview(after, "healer", "healer_bonk", "victim")
		_check(first.get("valid", false), case[0] + " permits the controlled next hit")
		if not first.get("valid", false):
			continue
		var once: Dictionary = rules.apply_plan(after, first)
		_check(once == first.get("result") and _entity(once, "victim").get("hp") == 9 - case[1],
			case[0] + " modifies the next hit by the specified amount")
		var second: Dictionary = rules.preview(once, "healer", "healer_bonk", "victim")
		_check(second.get("valid", false), case[0] + " permits a second controlled hit")
		if second.get("valid", false):
			var twice: Dictionary = rules.apply_plan(once, second)
			_check(_entity(twice, "victim").get("hp") == 9 - case[1] - 2,
				case[0] + " does not modify the second hit")


func _find_dose(source: Dictionary, acid: String, reaction_id: String) -> Dictionary:
	# Discover seeds through the public forecast, not the reaction implementation.
	for seed_value in range(1, 2001):
		var state := source.duplicate(true)
		state.dose_seed = seed_value
		var plan: Dictionary = rules.preview(state, "alchemist", acid, "victim")
		if plan.get("valid", false) and _reaction(plan).get("reaction_id") == reaction_id:
			return {"state": state, "plan": plan}
	return {}


func _test_jelly_knees_wagon(potion: String) -> void:
	var state := _state()
	state.obstacles = []
	state.units = [_unit("alchemist", "alchemist", Vector2i(3, 4)),
		_unit("wagon", "ferryman", Vector2i(3, 5)),
		_unit("enemy", "harpooner", Vector2i(10, 10))]
	state.party = ["alchemist"]
	state.orders = {"alchemist": "order_hold"}
	state.objective = {"handler": "wagon", "subject": "wagon", "destination": Vector2i(8, 5)}
	var dose := {}
	for seed_value in range(1, 2001):
		var candidate := state.duplicate(true)
		candidate.dose_seed = seed_value
		var plan: Dictionary = rules.preview(candidate, "alchemist", potion, "wagon")
		if plan.get("valid", false) and _reaction(plan).get("reaction_id") == "jelly_knees":
			dose = {"state": candidate, "plan": plan}
			break
	_check(not dose.is_empty(), "Potion can apply Jelly Knees to the friendly wagon")
	if dose.is_empty():
		return
	var given: Dictionary = rules.apply_plan(dose.state, dose.plan)
	_check(given == dose.plan.get("result")
		and _entity(given, "wagon").get("alchemy_statuses", {}).has("jelly_knees"),
		"Jelly Knees forecasts and commits on the objective-controlled civilian")
	var before := given.duplicate(true)
	var first: Dictionary = rules.preview_round(given)
	_check(first.get("valid", false) and given == before and first == rules.preview_round(given),
		"Knocked-down wagon round forecasts purely and repeatably")
	if not first.get("valid", false):
		return
	var recovered: Dictionary = rules.commit_round(given, first)
	_check(recovered == first.get("result"), "Knocked-down wagon round commits the forecast")
	_check(_entity(recovered, "wagon").position == Vector2i(3, 5),
		"Jelly Knees prevents the wagon's actual next objective movement")
	_check(not _entity(recovered, "wagon").get("alchemy_statuses", {}).has("jelly_knees"),
		"Wagon consumes Jelly Knees on the skipped movement")
	var second: Dictionary = rules.preview_round(recovered)
	_check(second.get("valid", false), "Recovered wagon can take another round")
	if second.get("valid", false):
		var resumed: Dictionary = rules.commit_round(recovered, second)
		_check(resumed == second.get("result")
			and _entity(resumed, "wagon").position == Vector2i(4, 5),
			"Wagon resumes objective movement after the single skipped activation")


func _test_reward_actions(potion: String, acid: String) -> void:
	var state := _state()
	state.obstacles = []
	state.units = [_unit("alchemist", "alchemist", Vector2i(3, 3)),
		_unit("victim", "harpooner", Vector2i(4, 3)),
		_unit("ally", "knight", Vector2i(5, 3)),
		_unit("neighbor", "harpooner", Vector2i(4, 4)),
		_unit("other", "harpooner", Vector2i(3, 5))]
	_entity(state, "alchemist")["upgrades"] = {"alchemist_spare_vial": 1,
		"alchemist_stronger_dose": 1, "alchemist_brittle_glass": 1, "alchemist_keep_the_culture": 1}
	var tonic: Dictionary = rules.preview(state, "alchemist", "alchemist_plain_tonic", "alchemist")
	_check(tonic.get("valid", false), "Spare Vial grants a usable Plain Tonic")
	if tonic.get("valid", false):
		var treated: Dictionary = rules.apply_plan(state, tonic)
		_check(treated == tonic.get("result") and _entity(treated, "alchemist").hp == 11
			and _reaction(tonic).is_empty(),
			"Plain Tonic heals one without a reaction despite Stronger Dose")
		_check(_ids(rules.targets(treated, "alchemist", "alchemist_repeat_batch")).is_empty(),
			"Plain Tonic does not bottle a recipe")
	var dose := _find_dose(state, acid, "upward_rain")
	_check(not dose.is_empty(), "Controlled Acid dose can produce a cosmetic reaction")
	if dose.is_empty():
		return
	var plan: Dictionary = dose.plan
	var after: Dictionary = rules.apply_plan(dose.state, plan)
	_check(after == plan.get("result") and _entity(after, "victim").hp == 9
		and _entity(after, "ally").hp == 9 and _entity(after, "neighbor").hp == 9,
		"Brittle Glass damages the primary target and adjacent friends and foes")
	var reactions := 0
	for event in plan.get("events", []):
		if event.get("type") == "alchemy_reaction":
			reactions += 1
	_check(reactions == 1 and _reaction(plan).get("target_id") == "victim",
		"Only Acid's primary target receives a reaction")
	var choices := _ids(rules.targets(after, "alchemist", "alchemist_repeat_batch"))
	_check("other" in choices and "victim" not in choices,
		"Repeat Batch requires a different legal recipient")
	var repeat: Dictionary = rules.preview(after, "alchemist", "alchemist_repeat_batch", "other")
	_check(repeat.get("valid", false) and repeat == rules.preview(after, "alchemist", "alchemist_repeat_batch", "other"),
		"Repeat Batch reveals a repeatable forecast")
	if repeat.get("valid", false):
		var repeated: Dictionary = rules.apply_plan(after, repeat)
		_check(repeated == repeat.get("result") and _entity(repeated, "other").hp == 9
			and _reaction(repeat).get("reaction_id") == _reaction(plan).get("reaction_id")
			and _reaction(repeat).get("target_id") == "other",
			"Repeat Batch commits the same reaction and recipe on the new recipient")
		_check(_ids(rules.targets(repeated, "alchemist", "alchemist_repeat_batch")).is_empty(),
			"Repeat Batch empties its bottle without refilling it")


func _test_nearest_self(potion: String) -> void:
	var fixture := defs.duplicate(true)
	fixture.orders["fixture_nearest"] = {"label": "Nearest potion"}
	fixture.behaviors["fixture_nearest"] = {"handler": "nearest_target", "params": {"ability": potion}}
	fixture.characters.alchemist.habits = catalog.profile(fixture, "alchemist").habits.duplicate()
	fixture.characters.alchemist.habits["fixture_nearest"] = "fixture_nearest"
	var errors: PackedStringArray = catalog.validate(fixture)
	_check(errors.is_empty(), "Nearest-self fixture validates: " + str(errors))
	if not errors.is_empty():
		return
	var state := _state(fixture)
	if state.is_empty():
		_check(false, "Nearest-self fixture opens")
		return
	state.obstacles = []
	state.units = [_unit("alchemist", "alchemist", Vector2i(3, 3), 10),
		_unit("enemy", "harpooner", Vector2i(10, 10)),
		_unit("civilian", "ferryman", Vector2i(11, 10))]
	state.orders = {"alchemist": "fixture_nearest"}
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), "Nearest-self order forecasts a valid round")
	if not plan.get("valid", false):
		return
	var self_dose := false
	for event in plan.get("events", []):
		if event.get("type") == "alchemy_reaction" and event.get("unit_id") == "alchemist" \
				and event.get("target_id") == "alchemist":
			self_dose = true
	_check(self_dose, "Nearest-target behavior selects self when self is the only legal recipient")
	_check(rules.commit_round(state, plan) == plan.get("result"), "Nearest-self order commits its forecast")


func _test_authored_status_collision(potion: String) -> void:
	var fixture := defs.duplicate(true)
	fixture.statuses["emergency_crust"] = fixture.statuses.knockdown.duplicate(true)
	fixture.abilities.wizard_blast.params.status = "emergency_crust"
	fixture.abilities.enemy_attack.params.damage = 2
	var errors: PackedStringArray = catalog.validate(fixture)
	_check(errors.is_empty(), "Same-ID authored status fixture validates: " + str(errors))
	if not errors.is_empty():
		return
	var state := _state(fixture)
	if state.is_empty():
		_check(false, "Same-ID authored status fixture opens")
		return
	state.obstacles = []
	state.units = [_unit("wizard", "wizard", Vector2i(1, 1)),
		_unit("enemy", "harpooner", Vector2i(2, 1)),
		_unit("alchemist", "alchemist", Vector2i(6, 5)),
		_unit("ally", "knight", Vector2i(6, 6)),
		_unit("attacker", "harpooner", Vector2i(7, 6))]
	var blast: Dictionary = rules.preview(state, "wizard", "wizard_blast")
	_check(blast.get("valid", false), "Authored same-ID status can be applied")
	if not blast.get("valid", false):
		return
	var affected: Dictionary = rules.apply_plan(state, blast)
	_check(rules.has_status_handler(affected, "enemy", "skip_action"),
		"Authored same-ID status retains its own skip-action behavior")
	var dose := {}
	for seed_value in range(1, 2001):
		var candidate := affected.duplicate(true)
		candidate.dose_seed = seed_value
		var plan: Dictionary = rules.preview(candidate, "alchemist", potion, "ally")
		if plan.get("valid", false) and _reaction(plan).get("reaction_id") == "emergency_crust":
			dose = {"state": candidate, "plan": plan}
			break
	_check(not dose.is_empty(), "Reaction with the same authored status ID can be drawn")
	if dose.is_empty():
		return
	var result: Dictionary = rules.apply_plan(dose.state, dose.plan)
	_check(result == dose.plan.get("result") and rules.has_status_handler(result, "enemy", "skip_action"),
		"Reaction commits without replacing the unrelated authored status")
	var hit: Dictionary = rules.preview(result, "attacker", "enemy_attack", "ally")
	_check(hit.get("valid", false), "Attacker can test the same-ID reaction")
	if hit.get("valid", false):
		var struck: Dictionary = rules.apply_plan(result, hit)
		_check(struck == hit.get("result") and _entity(struck, "ally").hp == 10
			and rules.has_status_handler(struck, "enemy", "skip_action"),
			"Emergency Crust reduces one hit without changing the authored skip status")


func _test_ball_bearings_pull() -> void:
	var fixture := defs.duplicate(true)
	fixture.abilities.wizard_pull.params.recoil_damage = 2
	var base := _state(fixture)
	if base.is_empty():
		_check(false, "Ball Bearings pull fixture opens")
		return
	base.obstacles = []
	base.units = [_unit("wizard", "wizard", Vector2i(3, 3)),
		_unit("target", "harpooner", Vector2i(6, 3))]
	# The caster also slides in the clear case, vacating the tile beyond its
	# original position. Without that slide, the caster blocks the extra tile.
	for variant in ["clear", "blocked", "plain"]:
		var state := base.duplicate(true)
		if variant != "plain":
			_entity(state, "target")["alchemy_statuses"] = {"ball_bearings": {
				"source_id": "target", "expires_after_round": state.round + 1}}
		if variant == "clear":
			_entity(state, "wizard")["alchemy_statuses"] = {"ball_bearings": {
				"source_id": "wizard", "expires_after_round": state.round + 1}}
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview(state, "wizard", "wizard_pull", "target")
		_check(plan.get("valid", false) and state == before
			and plan == rules.preview(state, "wizard", "wizard_pull", "target"),
			variant + " pull forecasts purely and repeatably")
		if not plan.get("valid", false):
			continue
		var result: Dictionary = rules.apply_plan(state, plan)
		_check(result == plan.get("result"), variant + " pull commits its forecast")
		var wizard_pos := Vector2i(1, 3) if variant == "clear" else Vector2i(2, 3)
		var target_pos := Vector2i(2, 3) if variant == "clear" else Vector2i(3, 3)
		_check(_entity(result, "wizard").get("position") == wizard_pos
			and _entity(result, "target").get("position") == target_pos,
			variant + " pull preserves recoil and slides the target only along the pull when clear")
		_check(_entity(result, "wizard").get("hp") == 8
			and rules.has_status_handler(result, "wizard", "skip_action"),
			variant + " pull preserves recoil damage and knockdown")
		if variant != "plain":
			_check(_entity(result, "target").get("alchemy_statuses", {}).get("ball_bearings", {}).is_empty(),
				variant + " target consumes Ball Bearings even if the extra tile is blocked")


func _test_numeric_upgrades(potion: String, acid: String) -> void:
	var state := _state()
	state.obstacles = []
	state.units = [_unit("alchemist", "alchemist", Vector2i(3, 3)),
		_unit("ally", "knight", Vector2i(5, 3)),
		_unit("enemy", "harpooner", Vector2i(3, 6))]
	_entity(state, "alchemist")["upgrades"] = {"alchemist_stronger_dose": 2,
		"alchemist_concentrate": 2, "alchemist_long_ladle": 1, "alchemist_spare_vial": 1}
	_check("ally" in _ids(rules.targets(state, "alchemist", potion))
		and "ally" not in _ids(rules.targets(state, "alchemist", "alchemist_plain_tonic")),
		"Long Ladle extends Potion to range two, not Plain Tonic")
	for action in [[potion, "ally", 13], [acid, "enemy", 7]]:
		var plan: Dictionary = rules.preview(state, "alchemist", action[0], action[1])
		_check(plan.get("valid", false), action[0] + " upgraded action is legal")
		if plan.get("valid", false):
			var result: Dictionary = rules.apply_plan(state, plan)
			_check(result == plan.get("result") and _entity(result, action[1]).get("hp") == action[2],
				action[0] + " applies both stacked one-point upgrades")


func _test_heal_modifiers() -> void:
	for sample in [["medicinal_aftertaste", 12], ["no_refills", 10]]:
		var state := _state()
		state.obstacles = []
		state.units = [_unit("alchemist", "alchemist", Vector2i(3, 3)),
			_unit("ally", "knight", Vector2i(4, 3))]
		_entity(state, "alchemist")["upgrades"] = {"alchemist_spare_vial": 1}
		_entity(state, "ally")["alchemy_statuses"] = {sample[0]: {
			"source_id": "alchemist", "expires_after_round": state.round + 1}}
		var first: Dictionary = rules.preview(state, "alchemist", "alchemist_plain_tonic", "ally")
		_check(first.get("valid", false), sample[0] + " allows the first heal")
		if not first.get("valid", false):
			continue
		var result: Dictionary = rules.apply_plan(state, first)
		_check(result == first.get("result") and _entity(result, "ally").hp == sample[1]
			and not _entity(result, "ally").get("alchemy_statuses", {}).has(sample[0]),
			sample[0] + " modifies and is consumed by the next heal")
		var second: Dictionary = rules.preview(result, "alchemist", "alchemist_plain_tonic", "ally")
		if not second.get("valid", false):
			_check(false, sample[0] + " permits the following heal")
			continue
		var next: Dictionary = rules.apply_plan(result, second)
		_check(_entity(next, "ally").hp == sample[1] + 1, sample[0] + " does not modify a second heal")


func _test_reaction_movement() -> void:
	for reaction in ["boot_toffee", "cork_soles"]:
		var state := _state()
		state.obstacles = []
		state.units = [_unit("wizard", "wizard", Vector2i(3, 3)),
			_unit("target", "knight", Vector2i(6, 3))]
		_entity(state, "target")["alchemy_statuses"] = {reaction: {
			"source_id": "wizard", "expires_after_round": state.round + 1}}
		var voluntary: Dictionary = rules.preview(state, "target", "move", "6,4")
		_check(voluntary.get("valid", false), reaction + " permits a voluntary move attempt")
		if voluntary.get("valid", false):
			var moved: Dictionary = rules.apply_plan(state, voluntary)
			_check(_entity(moved, "target").position == (Vector2i(6, 3) if reaction == "boot_toffee" else Vector2i(6, 4))
				and _entity(moved, "target").get("alchemy_statuses", {}).has(reaction) == (reaction == "cork_soles"),
				reaction + " blocks only its matching movement type")
		var forced: Dictionary = rules.preview(state, "wizard", "wizard_pull", "target")
		_check(forced.get("valid", false), reaction + " permits a forced pull attempt")
		if forced.get("valid", false):
			var pulled: Dictionary = rules.apply_plan(state, forced)
			_check(_entity(pulled, "target").position == (Vector2i(6, 3) if reaction == "cork_soles" else Vector2i(3, 3))
				and _entity(pulled, "target").get("alchemy_statuses", {}).has(reaction) == (reaction == "boot_toffee"),
				reaction + " blocks only its matching forced movement")


func _test_round_end_reactions() -> void:
	for sample in [["good_company", true, 11], ["good_company", false, 10],
			["stage_fright", true, 9], ["stage_fright", false, 10]]:
		var state := _state()
		state.obstacles = []
		var near: bool = sample[1]
		var neighbor_character := "wizard" if sample[0] == "good_company" else "harpooner"
		state.units = [_unit("alchemist", "alchemist", Vector2i(1, 1)),
			_unit("ally", "knight", Vector2i(5, 5)),
			_unit("neighbor", neighbor_character, Vector2i(6, 5) if near else Vector2i(9, 9)),
			_unit("civilian", "ferryman", Vector2i(10, 10))]
		state.orders = {"alchemist": "order_hold", "ally": "order_hold", "neighbor": "order_cautious"}
		_entity(state, "ally")["alchemy_statuses"] = {sample[0]: {
			"source_id": "alchemist", "expires_after_round": state.round}}
		var plan: Dictionary = rules.preview_round(state)
		_check(plan.get("valid", false), sample[0] + " end-of-round fixture is valid")
		if not plan.get("valid", false):
			continue
		var result: Dictionary = rules.commit_round(state, plan)
		_check(result == plan.get("result") and _entity(result, "ally").hp == sample[2]
			and not _entity(result, "ally").get("alchemy_statuses", {}).has(sample[0]),
			"%s resolves once only when adjacency qualifies, then expires" % sample[0])
		var next: Dictionary = rules.preview_round(result)
		if next.get("valid", false):
			var next_result: Dictionary = rules.commit_round(result, next)
			_check(_entity(next_result, "ally").hp == sample[2], sample[0] + " does not recur next round")
		else:
			_check(false, sample[0] + " fixture remains playable")
	var state := _state()
	state.obstacles = []
	state.units = [_unit("alchemist", "alchemist", Vector2i(1, 1)),
		_unit("ally", "knight", Vector2i(5, 5)),
		_unit("enemy", "harpooner", Vector2i(9, 9)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	state.orders = {"alchemist": "order_hold", "ally": "order_hold"}
	_entity(state, "ally")["alchemy_statuses"] = {"emergency_crust": {
		"source_id": "alchemist", "expires_after_round": state.round + 1}}
	var first: Dictionary = rules.preview_round(state)
	_check(first.get("valid", false), "Unused protection expiry fixture is valid")
	if not first.get("valid", false):
		return
	var retained: Dictionary = rules.commit_round(state, first)
	_check(_entity(retained, "ally").get("alchemy_statuses", {}).has("emergency_crust"),
		"Unused protection persists through the next round")
	var second: Dictionary = rules.preview_round(retained)
	_check(second.get("valid", false), "Unused protection reaches its expiry boundary")
	if second.get("valid", false):
		var expired: Dictionary = rules.commit_round(retained, second)
		_check(not _entity(expired, "ally").get("alchemy_statuses", {}).has("emergency_crust"),
			"Unused protection expires after the next round")
