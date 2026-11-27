extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/guild_variant_fittings_test.gd
const Catalog = preload("res://content/catalog.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Rules = preload("res://rules/rules.gd")
const Board = preload("res://rules/board.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")

var rules := Rules.new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = Fixture.add_fixed_escort(Catalog.read_default().duplicate(true))
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.behaviors.skeleton_greetings.params.greetings = ["wave"]
	for row in [["knight", "knight_shield_wall"], ["healer", "healer_apply_padding"],
			["wizard", "wizard_through_shot"], ["rogue", "rogue_blame_furniture"],
			["necromancer", "necro_stay_friend"], ["alchemist", "alchemist_shared_sample"],
			["blacksmith", "blacksmith_sweep"]]:
		if defs.abilities.has(row[1]):
			var kit: Array = Catalog.profile(defs, row[0]).abilities.duplicate()
			kit.append(row[1])
			defs.characters[row[0]].abilities = kit
		else:
			_check(false, row[1] + ": variant must be authored")
	_wall()
	_padding()
	_through()
	_blame()
	_blame_invalidated_draft()
	_recall()
	_tonic()
	_smith()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: guild variant fittings")
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, pos: Vector2i, hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": hp, "max_hp": 10, "statuses": {}}


func _state(hero: String) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	if state.is_empty():
		_check(false, "Controlled mission opens")
		return {}
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [_unit("smith", "blacksmith", Vector2i(0, 0)),
		_unit("actor", hero, Vector2i(4, 4)),
		_unit("enemy", "harpooner", Vector2i(9, 9)),
		_unit("civilian", "ferryman", Vector2i(11, 11))]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 0)}
	state.rng_state = 12345
	state.dose_seed = 12345
	return state


func _entity(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.get("units", []) + state.get("obstacles", []):
		if entity.get("id") == id:
			return entity
	return {}


func _ids(state: Dictionary, actor: String, ability: String) -> Array:
	return rules.targets(state, actor, ability).map(func(c: Dictionary): return c.get("id", ""))


func _act(state: Dictionary, ability: String, target := "", direct := false) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "actor", ability, target, direct)
	_check(plan.get("valid", false), ability + ": controlled action is valid")
	_check(state == before and plan == rules.preview(state, "actor", ability, target, direct),
		ability + ": preview is pure and repeatable")
	if not plan.get("valid", false):
		return {}
	_check(rules.apply_plan(state, plan) == plan.get("result") and state == before,
		ability + ": commit matches forecast")
	return plan


func _spent(plan: Dictionary, label: String) -> void:
	_check(not _entity(plan.get("result", {}), "actor").has("fitted_by"),
		label + ": successful alternate consumes fitting")


func _wall() -> void:
	var ability := "knight_shield_wall"
	if not defs.abilities.has(ability):
		return
	var s := _state("knight")
	if s.is_empty():
		return
	_entity(s, "actor").fitted_by = "smith"
	_check("6,4" in _ids(s, "actor", ability), "Thrown Wall offers center two tiles away")
	var plan := _act(s, ability, "6,4", true)
	if not plan.is_empty():
		_spent(plan, "Thrown Wall")
		var result: Dictionary = plan.result
		for cell in [Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5)]:
			_check(not Board.can_enter(result, cell), "Thrown Wall blocks " + Board.cell_id(cell))
		_check(result.obstacles.size() == 1 and result.obstacles[0].get("hp") == 1,
			"Thrown Wall has one obstacle with one shared HP")
	var fallback := s.duplicate(true)
	for cell in [Vector2i(6, 4), Vector2i(2, 4), Vector2i(4, 6), Vector2i(4, 2)]:
		fallback.obstacles.append({"id": Board.cell_id(cell), "object_id": "crate",
			"position": cell, "hp": 10, "max_hp": 10, "statuses": {}})
	_check("5,4" in _ids(fallback, "actor", ability), "Blocked throws offer ordinary adjacent wall")
	var ordinary := _act(fallback, ability, "5,4", true)
	if not ordinary.is_empty():
		_check(_entity(ordinary.result, "actor").get("fitted_by") == "smith"
			and not Board.can_enter(ordinary.result, Vector2i(5, 3))
			and not Board.can_enter(ordinary.result, Vector2i(5, 5)),
			"Unavailable throw falls back to adjacent span without spending fitting")


func _padding() -> void:
	var ability := "healer_apply_padding"
	if not defs.abilities.has(ability):
		return
	var s := _state("healer")
	if s.is_empty():
		return
	_entity(s, "actor").fitted_by = "smith"
	_entity(s, "enemy").position = Vector2i(5, 4)
	s.units.append(_unit("patient", "knight", Vector2i(4, 5), 5))
	var plan := _act(s, ability, "enemy", true)
	if not plan.is_empty():
		_spent(plan, "Crash Padding")
		_check(_entity(plan.result, "enemy").get("hp") == 8
			and _entity(plan.result, "patient").get("hp") == 5
			and not _entity(plan.result, "patient").get("statuses", {}).has("padding"),
			"Crash Padding damages adjacent opponent for two and grants no padding")


func _through() -> void:
	var ability := "wizard_through_shot"
	if not defs.abilities.has(ability):
		return
	var s := _state("wizard")
	if s.is_empty():
		return
	_entity(s, "enemy").position = Vector2i(7, 4)
	s.units.append(_unit("patient", "knight", Vector2i(5, 4), 5))
	_check("enemy" in _ids(s, "actor", ability),
		"Ordinary Through Shot offers its normal hostile target")
	_entity(s, "actor").fitted_by = "smith"
	_check("patient" in _ids(s, "actor", ability), "Fitted Through Shot offers a wounded patient")
	var plan := _act(s, ability, "patient", true)
	if not plan.is_empty():
		_spent(plan, "Mending Blast")
		_check(_entity(plan.result, "patient").get("hp") == 7
			and _entity(plan.result, "enemy").get("hp") == 10,
			"Mending Through Shot heals one patient by primary damage without a secondary hit")


func _blame() -> void:
	var ability := "rogue_blame_furniture"
	if not defs.abilities.has(ability):
		return
	var s := _state("rogue")
	if s.is_empty():
		return
	_entity(s, "enemy").position = Vector2i(5, 4)
	var normal := _act(s, ability, "enemy", true)
	if not normal.is_empty():
		_check(_entity(normal.result, "enemy").get("hp") == 10,
			"Ordinary Blame marks without the fitted bonk")
	_entity(s, "actor").fitted_by = "smith"
	var plan := _act(s, ability, "enemy", true)
	if not plan.is_empty():
		_spent(plan, "It Was Me")
		_check(_entity(plan.result, "enemy").get("hp") == 8
			and _entity(plan.result, "enemy").get("statuses", {}).has("taunt"),
			"Fitted Blame uses the It Was Me bonk and taunt")


func _blame_invalidated_draft() -> void:
	var ability := "rogue_blame_furniture"
	if not defs.abilities.has(ability):
		return
	var s := _state("rogue")
	if s.is_empty():
		return
	s.orders = {"smith": "order_hold", "actor": "order_hold"}
	_entity(s, "actor").fitted_by = "smith"
	_entity(s, "enemy").position = Vector2i(5, 4)
	var aimed: Dictionary = rules.preview(s, "actor", ability, "enemy", true)
	_check(aimed.get("valid", false) and aimed.get("events", []).any(func(event: Dictionary) -> bool:
		return event.get("type") == "fitted_conversion" and event.get("target_id") == "enemy"),
		"Invalidated Blame: adjacent target initially selects fitted It Was Me")
	var staged: Dictionary = rules.choose_manual(s, "actor", ability, "enemy")
	_check(staged.get("overrides", {}).get("actor", {}).get("target_id") == "enemy",
		"Invalidated Blame: fitted target stages")
	if not staged.get("overrides", {}).has("actor"):
		return
	# Model an earlier action moving the chosen target after staging, retaining the draft.
	_entity(staged, "enemy").position = Vector2i(7, 4)
	var ordinary := staged.duplicate(true)
	_entity(ordinary, "actor").erase("fitted_by")
	var ordinary_plan: Dictionary = rules.preview(ordinary, "actor", ability, "enemy", true)
	_check(ordinary_plan.get("valid", false)
		and _entity(ordinary_plan.get("result", {}), "enemy").get("statuses", {}).has("furniture_misdirected"),
		"Invalidated Blame: ordinary mark remains legal at the moved position")
	var before := staged.duplicate(true)
	var plan: Dictionary = rules.preview_round(staged)
	_check(plan.get("valid", false) and staged == before and plan == rules.preview_round(staged),
		"Invalidated Blame: round forecast is valid, pure and repeatable")
	if not plan.get("valid", false):
		return
	_check(rules.commit_round(staged, plan) == plan.get("result") and staged == before,
		"Invalidated Blame: commit matches forecast")
	_check(plan.get("events", []).any(func(event: Dictionary) -> bool:
		return event.get("unit_id") == "actor" and event.get("type") == "wait"),
		"Invalidated fitted draft waits instead of falling through to ordinary Blame")
	_check(not _entity(plan.result, "enemy").get("statuses", {}).has("furniture_misdirected")
		and _entity(plan.result, "enemy").get("hp") == 10
		and _entity(plan.result, "actor").get("fitted_by") == "smith",
		"Invalidated fitted draft neither marks nor damages and retains fitting")


func _recall() -> void:
	var ability := "necro_stay_friend"
	if not defs.abilities.has(ability):
		return
	var s := _state("necromancer")
	if s.is_empty():
		return
	var summoned := _act(s, ability, "5,4", true)
	if summoned.is_empty():
		return
	var ready: Dictionary = summoned.result
	var minions: Array = ready.units.filter(func(u: Dictionary): return u.get("character_id") == "skeleton" and u.get("hp", 0) > 0)
	_check(minions.size() == 1, "Ordinary Stay Friend summons one skeleton")
	if minions.size() != 1:
		return
	var id: String = minions[0].id
	minions[0].position = Vector2i(8, 4)
	minions[0].hp = 1
	_check(_ids(ready, "actor", ability).is_empty(), "Ordinary Stay Friend cannot summon beyond cap")
	_entity(ready, "actor").fitted_by = "smith"
	_check("4,5" in _ids(ready, "actor", ability), "Fitted Stay Friend offers recall despite cap")
	_recall_invalidated_draft(ready, id)
	var plan := _act(ready, ability, "4,5", true)
	if plan.is_empty():
		return
	_spent(plan, "Recall Skeleton")
	var result: Dictionary = plan.result
	_check(_entity(result, id).get("position") == Vector2i(4, 5)
		and _entity(result, id).get("hp") == 1, "Recall moves the same wounded skeleton without healing")
	result.orders = {"actor": "order_hold"}
	var round_plan: Dictionary = rules.preview_round(result)
	_check(round_plan.get("valid", false), "Recalled skeleton round is valid")
	if round_plan.get("valid", false):
		_check(_entity(round_plan.result, id).get("position") == Vector2i(4, 5),
			"Recalled Stay Friend skeleton remains stationary")


func _recall_invalidated_draft(ready: Dictionary, skeleton_id: String) -> void:
	var ability := "necro_stay_friend"
	var s := ready.duplicate(true)
	s.orders = {"smith": "order_hold", "actor": "order_hold"}
	var aimed: Dictionary = rules.preview(s, "actor", ability, "4,5", true)
	_check(aimed.get("valid", false), "Invalidated Recall: fitted landing is initially legal")
	var staged: Dictionary = rules.choose_manual(s, "actor", ability, "4,5")
	_check(staged.get("overrides", {}).get("actor", {}).get("target_id") == "4,5",
		"Invalidated Recall: fitted landing stages")
	if not staged.get("overrides", {}).has("actor"):
		return
	# Model the existing skeleton being removed by an earlier action, retaining the draft.
	staged.units.erase(_entity(staged, skeleton_id))
	var ordinary := staged.duplicate(true)
	_entity(ordinary, "actor").erase("fitted_by")
	var ordinary_plan: Dictionary = rules.preview(ordinary, "actor", ability, "4,5", true)
	_check(ordinary_plan.get("valid", false)
		and ordinary_plan.get("result", {}).get("units", []).any(func(unit: Dictionary) -> bool:
			return unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0),
		"Invalidated Recall: ordinary summon remains legal at the landing")
	var before := staged.duplicate(true)
	var plan: Dictionary = rules.preview_round(staged)
	_check(plan.get("valid", false) and staged == before and plan == rules.preview_round(staged),
		"Invalidated Recall: round forecast is valid, pure and repeatable")
	if not plan.get("valid", false):
		return
	_check(rules.commit_round(staged, plan) == plan.get("result") and staged == before,
		"Invalidated Recall: commit matches forecast")
	_check(plan.get("events", []).any(func(event: Dictionary) -> bool:
		return event.get("unit_id") == "actor" and event.get("type") == "wait"),
		"Invalidated Recall waits instead of falling through to ordinary summon")
	_check(not plan.result.get("units", []).any(func(unit: Dictionary) -> bool:
			return unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0)
		and _entity(plan.result, "actor").get("fitted_by") == "smith",
		"Invalidated Recall does not summon and retains fitting")


func _tonic() -> void:
	var ability := "alchemist_shared_sample"
	if not defs.abilities.has(ability):
		return
	var s := _state("alchemist")
	if s.is_empty():
		return
	_entity(s, "actor").fitted_by = "smith"
	_entity(s, "enemy").position = Vector2i(6, 4)
	s.units.append(_unit("patient", "knight", Vector2i(5, 4), 5))
	s.units.append(_unit("neighbor", "wizard", Vector2i(5, 5), 5))
	_check("patient" in _ids(s, "actor", ability), "Shared Tonic offers friendly primary")
	for cosmetic in [false, true]:
		var seed_value := -1
		for candidate in range(1, 10000):
			var potion: Dictionary = Reactions.draw(candidate, false)
			var acid: Dictionary = Reactions.draw(candidate, true)
			if (cosmetic and potion.category == "cosmetic") or (not cosmetic and potion.category != acid.category):
				seed_value = candidate
				break
		_check(seed_value >= 0, "Controlled potion seed exists")
		if seed_value < 0:
			continue
		s.dose_seed = seed_value
		var plan := _act(s, ability, "patient", true)
		if plan.is_empty():
			continue
		_spent(plan, "Shared Tonic")
		var recipients := []
		var expected: Dictionary = Reactions.draw(seed_value, false)
		for event: Dictionary in plan.get("events", []):
			if event.get("type") == "alchemy_reaction":
				recipients.append(event.get("target_id"))
				_check(event.get("reaction_id") == expected.id and event.get("category") == expected.category,
					"Each Shared Tonic recipient gets the same potion-pool reaction")
		recipients.sort()
		_check(recipients == ["actor", "enemy", "neighbor", "patient"],
			"Shared Tonic reacts exactly once on primary and adjacent living friends and foe")
		if cosmetic:
			_check(_entity(plan.result, "patient").get("hp") == 5
				and _entity(plan.result, "neighbor").get("hp") == 5,
				"Cosmetic Shared Tonic has no built-in healing")
		_check(_entity(plan.result, "actor").get("dose_rng_state") == expected.seed,
			"Shared Tonic draws its reaction once")


func _smith() -> void:
	var s := _state("blacksmith")
	if s.is_empty():
		return
	_check("actor" not in _ids(s, "actor", "blacksmith_try_this"),
		"Stock Try This cannot fit its Smith")
	if defs.abilities.has("blacksmith_sweep"):
		_entity(s, "enemy").position = Vector2i(5, 4)
		_entity(s, "actor").fitted_by = "smith"
		var plan := _act(s, "blacksmith_sweep", "enemy", true)
		if not plan.is_empty():
			_check(_entity(plan.result, "enemy").get("hp") == 9
				and _entity(plan.result, "actor").get("fitted_by") == "smith",
				"Sweep has no fitted alternate and does not consume a fitting")
