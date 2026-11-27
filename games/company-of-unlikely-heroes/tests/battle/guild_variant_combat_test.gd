extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/guild_variant_combat_test.gd
const Catalog = preload("res://content/catalog.gd")
var rules = preload("res://rules/rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(Catalog.read_default())
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	_through_shot()
	_blame_furniture()
	_stay_friend()
	_shared_sample()
	_sweep()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: guild variant combat")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": hp, "max_hp": 10, "statuses": {}}


func _state(hero: String, ability: String, units: Array) -> Dictionary:
	if not defs.get("abilities", {}).has(ability):
		_check(false, ability + ": variant ability must be authored")
		return {}
	var fixture := defs.duplicate(true)
	var kit: Array = Catalog.profile(fixture, hero).abilities.duplicate()
	if ability not in kit:
		kit.append(ability)
	fixture.characters[hero]["abilities"] = kit
	# Force one ordinary greeting to isolate autonomous behavior from RNG.
	fixture.behaviors.skeleton_greetings.params.greetings = ["wave"]
	var state: Dictionary = rules.new_game(fixture, "test_escort")
	if state.is_empty():
		_check(false, ability + ": controlled mission opens")
		return {}
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
	state.dose_seed = 12345
	return state


func _entity(state: Dictionary, id: String) -> Dictionary:
	for entity in state.get("units", []) + state.get("obstacles", []):
		if entity.get("id") == id:
			return entity
	return {}


func _action(state: Dictionary, actor: String, ability: String, target := "", direct := false) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, actor, ability, target, direct)
	_check(state == before and plan == rules.preview(state, actor, ability, target, direct),
		ability + ": repeated forecasts are pure and identical")
	_check(plan.get("valid", false), ability + ": action accepts the controlled target")
	if plan.get("valid", false):
		_check(rules.apply_plan(state, plan) == plan.get("result"), ability + ": commit matches forecast")
	return plan


func _forecast_names(plan: Dictionary, label: String, context: String) -> void:
	if not plan.get("valid", false):
		return
	var named := false
	for event in plan.get("events", []):
		if label.to_lower() in str(event.get("text", "")).to_lower():
			named = true
	_check(named, context + ": player-facing forecast names " + label)


func _through_shot() -> void:
	var ability := "wizard_through_shot"
	var state := _state("wizard", ability, [
		_unit("wizard", "wizard", Vector2i(2, 2)),
		_unit("primary", "harpooner", Vector2i(4, 2)),
		_unit("friend", "knight", Vector2i(5, 2)),
		_unit("far", "harpooner", Vector2i(6, 2))])
	if state.is_empty():
		return
	var plan := _action(state, "wizard", ability, "primary", true)
	if plan.get("valid", false):
		var result: Dictionary = plan.result
		_check(_entity(result, "primary").get("hp") == 8
			and _entity(result, "friend").get("hp") == 9
			and _entity(result, "far").get("hp") == 10,
			"Through Shot deals 2 to primary and 1 to first eligible character behind, including a friend")
	var diagonal := state.duplicate(true)
	_entity(diagonal, "primary").position = Vector2i(3, 3)
	_entity(diagonal, "friend").position = Vector2i(4, 3)
	var angled := _action(diagonal, "wizard", ability, "primary", true)
	_forecast_names(angled, "Through Shot", "Non-aligned single-hit Through Shot")
	if angled.get("valid", false):
		_check(_entity(angled.result, "primary").get("hp") == 8
			and _entity(angled.result, "friend").get("hp") == 10,
			"Through Shot has no secondary for a non-aligned primary")
	var beyond := state.duplicate(true)
	_entity(beyond, "primary").position = Vector2i(6, 2)
	_entity(beyond, "friend").position = Vector2i(7, 2)
	_entity(beyond, "far").position = Vector2i(8, 2)
	var edge := _action(beyond, "wizard", ability, "primary", true)
	_forecast_names(edge, "Through Shot", "Range-edge single-hit Through Shot")
	if edge.get("valid", false):
		_check(_entity(edge.result, "friend").get("hp") == 10,
			"Through Shot does not hit beyond normal Blast range")


func _blame_furniture() -> void:
	var ability := "rogue_blame_furniture"
	var state := _state("rogue", ability, [
		_unit("rogue", "rogue", Vector2i(1, 1)),
		_unit("attacker", "harpooner", Vector2i(4, 4)),
		_unit("victim", "knight", Vector2i(3, 4))])
	if state.is_empty():
		return
	# Mark before furniture arrives: eligibility is resolved when the attack happens.
	var mark := _action(state, "rogue", ability, "attacker")
	if not mark.get("valid", false):
		return
	var marked: Dictionary = mark.result
	marked.obstacles = [{"id": "crate", "object_id": "crate", "position": Vector2i(4, 5),
		"hp": 10, "max_hp": 10, "statuses": {}}]
	var hit := _action(marked, "attacker", "enemy_attack", "victim")
	if hit.get("valid", false):
		_check(_entity(hit.result, "victim").get("hp") == 10
			and _entity(hit.result, "crate").get("hp", 10) < 10,
			"Marked attack damages adjacent furniture instead of its intended victim")
	var absent := marked.duplicate(true)
	absent.obstacles = []
	var fallback := _action(absent, "attacker", "enemy_attack", "victim")
	if fallback.get("valid", false):
		_check(_entity(fallback.result, "victim").get("hp", 10) < 10,
			"Marked attack proceeds normally when furniture is absent at resolution")


func _stay_friend() -> void:
	var ability := "necro_stay_friend"
	var state := _state("necromancer", ability, [
		_unit("necromancer", "necromancer", Vector2i(2, 2)),
		_unit("enemy", "harpooner", Vector2i(9, 9)),
		_unit("civilian", "ferryman", Vector2i(10, 10))])
	if state.is_empty():
		return
	var choices: Array = rules.targets(state, "necromancer", ability)
	_check(not choices.is_empty(), "Stay Friend offers a legal summon cell")
	if choices.is_empty():
		return
	var summon := _action(state, "necromancer", ability, str(choices[0].get("id", "")))
	_forecast_names(summon, "Stay, Friend", "Skeleton summon")
	if not summon.get("valid", false):
		return
	var spawned: Dictionary = summon.result
	var minions: Array = spawned.units.filter(func(unit: Dictionary) -> bool:
		return unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0)
	_check(minions.size() == 1, "Stay Friend summons one living skeleton")
	if minions.size() != 1:
		return
	var id: String = minions[0].id
	var start: Vector2i = minions[0].position
	var remaining: Array = rules.targets(spawned, "necromancer", ability)
	_check(remaining.is_empty(), "Stay Friend retains the living skeleton cap despite other open cells")
	spawned.orders = {"necromancer": "order_hold"}
	var before := spawned.duplicate(true)
	var plan: Dictionary = rules.preview_round(spawned)
	_check(plan.get("valid", false) and spawned == before and plan == rules.preview_round(spawned),
		"Stay Friend autonomous round previews purely and repeatably")
	if plan.get("valid", false):
		_check(rules.commit_round(spawned, plan) == plan.result
			and _entity(plan.result, id).get("position") == start,
			"Stay Friend does not pursue a distant opponent")
	var greeting := spawned.duplicate(true)
	_entity(greeting, id).position = Vector2i(5, 5)
	_entity(greeting, "enemy").position = Vector2i(6, 5)
	_entity(greeting, "necromancer").position = Vector2i(4, 5)
	var hello: Dictionary = rules.preview_round(greeting)
	if hello.get("valid", false):
		_check(rules.commit_round(greeting, hello) == hello.result
			and _entity(hello.result, id).get("position") == Vector2i(5, 5)
			and _entity(hello.result, "enemy").get("hp") == 9
			and _entity(hello.result, "necromancer").get("hp") == 9,
			"Stationary skeleton still Waves both adjacent opponent and ally")
	else:
		_check(false, "Stay Friend greeting round is valid")


func _shared_sample() -> void:
	var ability := "alchemist_shared_sample"
	var state := _state("alchemist", ability, [
		_unit("alchemist", "alchemist", Vector2i(2, 2)),
		_unit("primary", "harpooner", Vector2i(4, 2)),
		_unit("friend", "knight", Vector2i(4, 3)),
		_unit("enemy", "harpooner", Vector2i(5, 2)),
		_unit("dead", "harpooner", Vector2i(4, 1), 0),
		_unit("far", "harpooner", Vector2i(7, 2))])
	if state.is_empty():
		return
	var ordinary: Dictionary = rules.preview(state, "alchemist", ability, "primary")
	_forecast_names(ordinary, "Shared Sample", "Shared Sample")
	# A cosmetic reaction makes the absence of guaranteed Acid damage observable.
	var selected := {}
	for seed_value in range(1, 2001):
		state.dose_seed = seed_value
		var candidate: Dictionary = rules.preview(state, "alchemist", ability, "primary")
		if candidate.get("valid", false) and candidate.get("events", []).any(func(event: Dictionary) -> bool:
				return event.get("type") == "alchemy_reaction" and event.get("category") == "cosmetic"):
			selected = candidate
			break
	_check(not selected.is_empty(), "Shared Sample can select a cosmetic reaction on its legal target")
	if selected.is_empty():
		return
	var plan := _action(state, "alchemist", ability, "primary")
	var recipients := []
	var reaction_id := ""
	for event in plan.get("events", []):
		if event.get("type") == "alchemy_reaction":
			recipients.append(event.get("target_id"))
			if reaction_id.is_empty():
				reaction_id = str(event.get("reaction_id", ""))
			_check(event.get("reaction_id") == reaction_id, "Shared Sample locks the same reaction for every recipient")
	recipients.sort()
	_check(recipients == ["enemy", "friend", "primary"],
		"Shared Sample applies exactly once to primary and adjacent living friend and foe")
	for id in ["primary", "friend", "enemy", "far"]:
		_check(_entity(plan.get("result", {}), id).get("hp") == 10,
			"Cosmetic Shared Sample does not deal guaranteed Acid damage to " + id)


func _sweep() -> void:
	var ability := "blacksmith_sweep"
	var state := _state("blacksmith", ability, [
		_unit("smith", "blacksmith", Vector2i(5, 5)),
		_unit("first", "harpooner", Vector2i(6, 5)),
		_unit("second", "harpooner", Vector2i(5, 6)),
		_unit("friend", "knight", Vector2i(4, 5))])
	if state.is_empty():
		return
	var plan := _action(state, "smith", ability, "first")
	_forecast_names(plan, "Sweep", "Two-opponent Sweep")
	if plan.get("valid", false):
		_check(_entity(plan.result, "first").get("hp") == 9
			and _entity(plan.result, "second").get("hp") == 9
			and _entity(plan.result, "friend").get("hp") == 10,
			"Sweep deals one to each of two adjacent opponents, not a friend")
	var one := state.duplicate(true)
	_entity(one, "second").position = Vector2i(9, 9)
	var single := _action(one, "smith", ability, "first")
	_forecast_names(single, "Sweep", "Single-opponent Sweep")
	if single.get("valid", false):
		_check(_entity(single.result, "first").get("hp") == 9,
			"Sweep deals one, not Hammer Time's two, to a lone opponent")
