extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/necromancer_test.gd
# Authored kit on test-owned geometry, exercised through the public rules API.
var failures: Array[String] = []
var rules = preload("res://rules.gd").new()
var catalog = preload("res://content/catalog.gd")
var defs: Dictionary


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(catalog.read_default())
	if not defs.get("characters", {}).has("necromancer"):
		_check(false, "Necromancer must be authored")
	else:
		_test_kit()
		_test_summons()
		_test_greetings()
		_test_rounds()
		_test_greeting_random_replay()
		_test_zombie_reaches_flower_range()
		_test_healer_escapes_wave()
		_test_adventure_boundaries()
	if failures.is_empty():
		print("PASS: Necromancer integration")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i, hp := 10, max_hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": hp, "max_hp": max_hp, "statuses": {}}


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
	return state


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _character(state: Dictionary, character: String) -> Array:
	var found := []
	for unit in state.get("units", []):
		if unit.get("character_id") == character and unit.get("hp", 0) > 0:
			found.append(unit)
	return found


func _ids(choices: Array) -> Array:
	var ids := []
	for choice in choices:
		ids.append(choice.get("id", ""))
	return ids


func _action(state: Dictionary, actor: String, ability: String, target := "") -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, actor, ability, target)
	_check(state == before, ability + " forecast does not mutate the board")
	_check(plan.get("valid", false), ability + " is valid in its fixture")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.apply_plan(state, plan)
	_check(result == plan.get("result"), ability + " commit matches forecast")
	return result


func _summon(state: Dictionary) -> Dictionary:
	var targets: Array = rules.targets(state, "necromancer", "summon_skeleton")
	var target := str(targets[0].get("id", "")) if not targets.is_empty() else ""
	return _action(state, "necromancer", "summon_skeleton", target)


func _test_kit() -> void:
	var state := _state([_unit("necromancer", "necromancer", Vector2i(3, 3))])
	var options: Array = rules.options(state, "necromancer")
	var ids := _ids(options)
	_check("move" in ids and "raise_dead" in ids and "summon_skeleton" in ids,
		"Necromancer offers Move and both summons")
	var hold := false
	for option in options:
		if option.get("kind") == "order" and str(option.get("label", "")).to_lower() == "hold":
			hold = true
	_check(hold, "Necromancer offers Hold")


func _test_summons() -> void:
	var state := _state([
		_unit("necromancer", "necromancer", Vector2i(3, 3)),
		_unit("corpse", "harpooner", Vector2i(4, 3), 0, 9),
		_unit("other_corpse", "harpooner", Vector2i(3, 4), 0, 12),
		_unit("living", "harpooner", Vector2i(2, 3)),
		_unit("ally_dead", "knight", Vector2i(3, 2), 0)
	])
	var choices := _ids(rules.targets(state, "necromancer", "raise_dead"))
	_check("corpse" in choices and "other_corpse" in choices, "Raise Dead offers defeated opponents")
	_check("living" not in choices and "ally_dead" not in choices, "Raise Dead excludes living units and defeated allies")
	var raised := _action(state, "necromancer", "raise_dead", "corpse")
	if not raised.is_empty():
		var zombies := _character(raised, "zombie")
		_check(zombies.size() == 1, "Raise Dead creates one living zombie")
		if zombies.size() == 1:
			_check(zombies[0].get("hp") == 5 and zombies[0].get("max_hp") == 5,
				"Zombie receives ceiling half of selected opponent maximum HP")
		_check(not _entity(raised, "other_corpse").is_empty(), "Raise Dead leaves other corpses intact")
		_check(not rules.preview(raised, "necromancer", "raise_dead", "other_corpse").get("valid", false),
			"A second living zombie cannot be raised")
		if zombies.size() == 1:
			zombies[0].hp = 0
			_check("corpse" not in _ids(rules.targets(raised, "necromancer", "raise_dead"))
				and not rules.preview(raised, "necromancer", "raise_dead", "corpse").get("valid", false),
				"Consumed corpse cannot be raised again after the zombie dies")
	var no_corpse := _state([_unit("necromancer", "necromancer", Vector2i(5, 5)),
		_unit("enemy", "harpooner", Vector2i(9, 9))])
	var skeleton_state := _summon(no_corpse)
	if skeleton_state.is_empty():
		return
	var skeletons := _character(skeleton_state, "skeleton")
	_check(skeletons.size() == 1, "Skeleton needs no corpse")
	if skeletons.size() == 1:
		_check(skeletons[0].get("hp") == 1 and skeletons[0].get("max_hp") == 1, "Skeleton has one HP")
	var remaining: Array = rules.targets(skeleton_state, "necromancer", "summon_skeleton")
	var next_target := str(remaining[0].get("id", "")) if not remaining.is_empty() else ""
	_check(not rules.preview(skeleton_state, "necromancer", "summon_skeleton", next_target).get("valid", false),
		"A second living skeleton cannot be summoned")


func _test_greetings() -> void:
	var state := _state([
		_unit("minion", "skeleton", Vector2i(5, 5), 1, 1),
		_unit("ally", "knight", Vector2i(4, 5)),
		_unit("enemy", "harpooner", Vector2i(6, 5)),
		_unit("far", "harpooner", Vector2i(8, 5)),
		_unit("necromancer", "necromancer", Vector2i(5, 6))
	])
	var waved := _action(state, "minion", "wave")
	if not waved.is_empty():
		for id in ["ally", "enemy", "necromancer"]:
			_check(_entity(waved, id).get("hp") == 9, "Wave damages adjacent " + id + " by one")
		_check(_entity(waved, "minion").get("hp") == 1 and _entity(waved, "far").get("hp") == 10,
			"Wave excludes its user and nonadjacent characters")
	var zombie_state := _state([
		_unit("zombie", "zombie", Vector2i(5, 5), 5, 5),
		_unit("enemy", "harpooner", Vector2i(6, 5))
	])
	var flower := _action(zombie_state, "zombie", "offer_flower", "enemy")
	if not flower.is_empty():
		_check(_entity(flower, "enemy").get("hp") == 9, "Flower deals one damage")
	var ranged := zombie_state.duplicate(true)
	_entity(ranged, "enemy").position = Vector2i(7, 5)
	_check("enemy" in _ids(rules.targets(ranged, "zombie", "offer_flower")), "Flower reaches range two")
	_entity(ranged, "enemy").position = Vector2i(8, 5)
	_check("enemy" not in _ids(rules.targets(ranged, "zombie", "offer_flower")), "Flower does not exceed range two")
	var hello_state := _state([_unit("zombie", "zombie", Vector2i(5, 5), 5, 5),
		_unit("near", "knight", Vector2i(6, 5)), _unit("far", "harpooner", Vector2i(9, 5))])
	var hello := _action(hello_state, "zombie", "say_hello")
	if not hello.is_empty():
		_check(_entity(hello, "near").get("position") == Vector2i(7, 5)
			and _entity(hello, "far").get("position") == Vector2i(9, 5),
			"Say Hello makes the closest other character back one tile")
	var stop_state := _state([
		_unit("minion", "skeleton", Vector2i(5, 5), 1, 1),
		_unit("ally", "knight", Vector2i(4, 5)),
		_unit("enemy", "harpooner", Vector2i(7, 5)),
		_unit("necromancer", "necromancer", Vector2i(2, 2)),
		_unit("civilian", "ferryman", Vector2i(10, 10))
	])
	var stopped := _action(stop_state, "minion", "dont_go")
	if not stopped.is_empty():
		_check(not rules.preview(stopped, "ally", "move", "3,5").get("valid", false),
			"Don't Go blocks the closest other character, even when friendly")
		_check(rules.preview(stopped, "enemy", "move", "8,5").get("valid", false),
			"Don't Go does not block the more distant opponent")
		_check(rules.preview(stopped, "ally", "knight_push", "minion").get("valid", false),
			"Don't Go does not block other actions")
		# Prevent a second autonomous greeting from renewing the effect.
		_entity(stopped, "minion").hp = 0
		var round_plan: Dictionary = rules.preview_round(stopped)
		var after_turn: Dictionary = rules.commit_round(stopped, round_plan)
		if _entity(after_turn, "ally").get("hp", 0) > 0:
			var pos: Vector2i = _entity(after_turn, "ally").position
			var legal_steps := _ids(rules.targets(after_turn, "ally", "move"))
			_check(not legal_steps.is_empty(), "Don't Go expires after the affected character's next turn at %s" % pos)


func _test_rounds() -> void:
	var state := _state([_unit("necromancer", "necromancer", Vector2i(2, 2)),
		_unit("enemy", "harpooner", Vector2i(9, 9)),
		_unit("civilian", "ferryman", Vector2i(10, 10))])
	var targets: Array = rules.targets(state, "necromancer", "summon_skeleton")
	_check(not targets.is_empty(), "Summoning round offers a legal skeleton placement")
	if targets.is_empty():
		return
	var target: String = targets[0].get("id", "")
	var selected: Dictionary = rules.choose_manual(state, "necromancer", "summon_skeleton", target)
	_check(selected.get("overrides", {}).get("necromancer", {}) == {
		"ability_id": "summon_skeleton", "target_id": target
	}, "Summoning round queues the chosen legal placement")
	var before := selected.duplicate(true)
	var first: Dictionary = rules.preview_round(selected)
	_check(first.get("valid", false) and selected == before, "Summoning round forecasts without mutation")
	if not first.get("valid", false):
		return
	var committed: Dictionary = rules.commit_round(selected, first)
	_check(committed == first.get("result"), "Summoning round commits its forecast")
	var skeletons := _character(committed, "skeleton")
	_check(skeletons.size() == 1, "Round summons skeleton")
	if skeletons.is_empty():
		return
	var id: String = skeletons[0].id
	var acted := false
	for event in first.get("events", []):
		if event.get("unit_id") == id:
			acted = true
	_check(not acted, "New skeleton does not act in its summoning round")
	var forecast: Dictionary = rules.preview_round(committed)
	var repeat: Dictionary = rules.preview_round(committed)
	_check(forecast == repeat, "Repeated minion forecasts preserve random choice")
	_check(rules.commit_round(committed, forecast) == forecast.get("result"),
		"Minion round commits exactly the forecast, including random greeting")
	var after := _entity(forecast.get("result", {}), id)
	_check(not after.is_empty() and after.get("position") != skeletons[0].get("position"),
		"Skeleton pursues a distant opponent on its next round")
	var order_state := _state([_unit("necromancer", "necromancer", Vector2i(2, 2)),
		_unit("corpse", "harpooner", Vector2i(3, 2), 0, 9),
		_unit("enemy", "harpooner", Vector2i(9, 9)),
		_unit("civilian", "ferryman", Vector2i(10, 10))])
	var zombie_first := _action(order_state, "necromancer", "raise_dead", "corpse")
	if zombie_first.is_empty():
		return
	var both := _summon(zombie_first)
	if both.is_empty() or _character(both, "skeleton").is_empty() or _character(both, "zombie").is_empty():
		return
	var skeleton_id: String = _character(both, "skeleton")[0].id
	var zombie_id: String = _character(both, "zombie")[0].id
	var order_plan: Dictionary = rules.preview_round(both)
	var acted_ids := []
	for event in order_plan.get("events", []):
		var actor: String = event.get("unit_id", event.get("source_id", ""))
		if actor in ["necromancer", skeleton_id, zombie_id] and actor not in acted_ids:
			acted_ids.append(actor)
	_check(acted_ids == ["necromancer", skeleton_id, zombie_id],
		"Existing minions act after their caster, skeleton before zombie even when raised first")


func _test_greeting_random_replay() -> void:
	var fixture := defs.duplicate(true)
	fixture.characters.harpooner.behavior = "hold"
	var errors: PackedStringArray = catalog.validate(fixture)
	_check(errors.is_empty(), "Random greeting fixture validates: " + str(errors))
	if not errors.is_empty():
		return
	var state: Dictionary = rules.new_game(fixture, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	# The enemy acts before the skeleton, so Don't Go remains observable at round end.
	state.units = [
		_unit("necromancer", "necromancer", Vector2i(1, 1)),
		_unit("enemy", "harpooner", Vector2i(6, 5)),
		_unit("minion", "skeleton", Vector2i(5, 5), 1, 1),
		_unit("civilian", "ferryman", Vector2i(10, 10))
	]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(0, 0)}
	_check(rules.preview(state, "minion", "wave").get("valid", false)
		and rules.preview(state, "minion", "dont_go").get("valid", false),
		"Both normal skeleton greetings are legal on the random-choice board")
	var observed := {}
	for seed_value in range(1, 33):
		state.rng_state = seed_value
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview_round(state)
		var repeat: Dictionary = rules.preview_round(state)
		_check(plan.get("valid", false) and state == before and plan == repeat,
			"Seed %d repeats the actual greeting forecast without mutation" % seed_value)
		if not plan.get("valid", false):
			return
		var result: Dictionary = rules.commit_round(state, plan)
		_check(result == plan.get("result"), "Seed %d commits its greeting forecast" % seed_value)
		var damage: bool = _entity(result, "enemy").get("hp") == 9
		var stopped: bool = not rules.preview(result, "enemy", "move", "7,5").get("valid", false)
		_check(damage != stopped, "Seed %d produces exactly one normal greeting" % seed_value)
		if damage:
			observed["wave"] = true
		if stopped:
			observed["dont_go"] = true
	_check(observed.has("wave") and observed.has("dont_go"),
		"Deterministic seeds exercise both legal normal greetings")


func _test_zombie_reaches_flower_range() -> void:
	var fixture := defs.duplicate(true)
	var profile: Dictionary = catalog.profile(fixture, "zombie")
	var behavior: String = profile.get("behavior", "")
	if not fixture.get("behaviors", {}).has(behavior):
		_check(false, "Zombie has an authored autonomous behavior")
		return
	fixture.behaviors[behavior].params.greetings = ["offer_flower"]
	# Keep the road target stationary without changing its team or capabilities.
	fixture.characters.harpooner.behavior = "hold"
	var errors: PackedStringArray = catalog.validate(fixture)
	_check(errors.is_empty(), "Flower pursuit catalog fixture validates: " + str(errors))
	if not errors.is_empty():
		return
	var state: Dictionary = rules.new_game(fixture, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		_unit("necromancer", "necromancer", Vector2i(9, 9)),
		_unit("blocker_a", "wizard", Vector2i(0, 1)),
		_unit("blocker_b", "wizard", Vector2i(1, 0)),
		_unit("zombie", "zombie", Vector2i(4, 1), 5, 5),
		_unit("enemy", "harpooner", Vector2i(0, 0)),
		_unit("civilian", "ferryman", Vector2i(11, 10))
	]
	state.orders = {"blocker_a": "order_cautious", "blocker_b": "order_cautious"}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(0, 0)}
	var start: Vector2i = _entity(state, "zombie").position
	var moved := false
	var greeted := false
	for round_index in range(8):
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview_round(state)
		_check(plan.get("valid", false) and state == before, "Flower pursuit round previews without mutation")
		if not plan.get("valid", false):
			return
		var next: Dictionary = rules.commit_round(state, plan)
		_check(next == plan.get("result"), "Flower pursuit round commits its forecast")
		var zombie := _entity(next, "zombie")
		if zombie.get("position") != start:
			moved = true
		if _entity(next, "enemy").get("hp", 10) < 10:
			greeted = true
			_check(round_index > 0 and moved, "Zombie advances before offering the flower")
			_check(_entity(next, "enemy").get("hp") == 9, "Flower deals one damage to the road target")
			break
		state = next
	_check(moved, "Zombie progresses toward reachable flower range despite blocked adjacent tiles")
	_check(greeted, "Zombie eventually offers a flower from reachable range two")


func _test_healer_escapes_wave() -> void:
	var fixture := defs.duplicate(true)
	var profile: Dictionary = catalog.profile(fixture, "skeleton")
	var behavior: String = profile.get("behavior", "")
	if not fixture.get("behaviors", {}).has(behavior):
		_check(false, "Skeleton has an authored autonomous behavior")
		return
	fixture.behaviors[behavior].params.greetings = ["wave"]
	var errors: PackedStringArray = catalog.validate(fixture)
	_check(errors.is_empty(), "Forced-Wave catalog fixture validates: " + str(errors))
	if not errors.is_empty():
		return
	var state: Dictionary = rules.new_game(fixture, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		_unit("healer", "healer", Vector2i(4, 4)),
		_unit("necromancer", "necromancer", Vector2i(2, 2)),
		_unit("minion", "skeleton", Vector2i(5, 4), 1, 1),
		_unit("enemy", "harpooner", Vector2i(6, 4)),
		_unit("civilian", "ferryman", Vector2i(10, 10))
	]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	var stay: Dictionary = rules.choose_manual(state, "healer", "healer_heal")
	var escape: Dictionary = rules.choose_manual(state, "healer", "move", "3,4")
	var stay_plan: Dictionary = rules.preview_round(stay)
	var before := escape.duplicate(true)
	var escape_plan: Dictionary = rules.preview_round(escape)
	_check(stay_plan.get("valid", false) and escape_plan.get("valid", false) and escape == before,
		"Wave comparison forecasts both rounds without mutation")
	_check(_wave_hits(stay_plan, "healer") and not _wave_hits(escape_plan, "healer"),
		"Healer moving first escapes the later skeleton Wave shown in the forecast")
	_check(_wave_hits(escape_plan, "enemy"), "Skeleton still Waves an adjacent opponent after Healer escapes")
	_check(rules.commit_round(escape, escape_plan) == escape_plan.get("result"),
		"Healer escape and subsequent Wave commit exactly as forecast")


func _wave_hits(plan: Dictionary, target: String) -> bool:
	for event in plan.get("events", []):
		if event.get("type") == "damage" and event.get("source_id") == "minion" and event.get("target_id") == target:
			return true
	return false


func _test_adventure_boundaries() -> void:
	var adventure = preload("res://adventure.gd")
	var picks := ["necromancer", "healer", "wizard"]
	var ready: Dictionary = adventure.start_adventure(defs, "first_outing", picks, 12345)
	_check(ready.get("phase") == "ready" and ready.get("party") == picks,
		"Necromancer occupies one ordinary company slot")
	if ready.is_empty():
		return
	var run: Dictionary = adventure.begin_mission(ready)
	var state: Dictionary = run.get("mission", {}).duplicate(true)
	if state.is_empty():
		_check(false, "Necromancer company deploys")
		return
	state.units.append(_unit("test_skeleton", "skeleton", Vector2i(7, 7), 1, 1))
	for id in picks:
		_entity(state, id).hp = 0
	var plan: Dictionary = rules.preview_round(state)
	var terminal: Dictionary = rules.commit_round(state, plan)
	_check(terminal.get("outcome") == "defeat", "Living minion does not prevent a party wipe")
	var victory_state: Dictionary = run.get("mission", {}).duplicate(true)
	victory_state.units.append(_unit("test_skeleton", "skeleton", Vector2i(7, 7), 1, 1))
	for unit in victory_state.units:
		if rules.entity_profile(victory_state, unit.id).get("team") == "enemies":
			unit.hp = 0
	var victory_plan: Dictionary = rules.preview_round(victory_state)
	var victory: Dictionary = rules.commit_round(victory_state, victory_plan)
	_check(victory.get("outcome") == "victory", "Controlled minion carryover fixture wins")
	if victory.get("outcome") != "victory":
		return
	var settled: Dictionary = adventure.settle_mission(run, victory)
	_check(settled.get("party") == picks and not settled.get("carry_by_id", {}).has("test_skeleton"),
		"Minion is not a party member or carryover entry")
	if settled.get("phase") == "reward":
		var offers: Array = settled.get("reward_offers", [])
		if offers.is_empty():
			_check(false, "Reward transition provides a selectable offer")
			return
		settled = adventure.choose_reward(settled, offers[0].hero_id, offers[0].upgrade_id)
	var next: Dictionary = adventure.begin_mission(settled)
	_check(_character(next.get("mission", {}), "skeleton").is_empty(),
		"Minion does not carry into the next mission")
