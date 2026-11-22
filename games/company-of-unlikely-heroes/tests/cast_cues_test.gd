extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/cast_cues_test.gd
var failures: Array[String] = []
var rules = preload("res://rules.gd").new()
var defs: Dictionary
var mapper


func _initialize() -> void:
	var path := "res://presentation/cast_cues.gd"
	if not ResourceLoader.exists(path):
		failures.append("Missing behavior: " + path)
	else:
		mapper = load(path)
		if mapper == null or not mapper.has_method("build"):
			failures.append("Missing behavior: cast_cues.build(before, after, events)")
	if failures.is_empty():
		defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(preload("res://content/catalog.gd").read_default())
		_test_direct_actions()
		_test_healing()
		_test_summons_and_minions()
		_test_repeated_performers_and_reactions()
		_test_reflection()
		_test_committed_round()
		_test_non_actions_and_aliases()
		_test_custom_ability_handlers()
		_test_mixologist_recipes()
	if failures.is_empty():
		print("PASS: resolved cast cues")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, at: Vector2i, hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": at,
		"hp": hp, "max_hp": 10, "statuses": {}}


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


func _build(before: Dictionary, after: Dictionary, events: Array) -> Array:
	var before_copy := before.duplicate(true)
	var after_copy := after.duplicate(true)
	var events_copy := events.duplicate(true)
	var cues: Array = mapper.build(before, after, events)
	_check(before == before_copy and after == after_copy and events == events_copy,
		"Cue mapping must not mutate states or events")
	return cues


func _action(state: Dictionary, actor: String, ability: String, target := "") -> Array:
	var plan: Dictionary = rules.preview(state, actor, ability, target)
	_check(plan.get("valid", false), "Fixture must resolve " + ability)
	if not plan.get("valid", false):
		return []
	return _build(state, plan.result, plan.events)


func _cue(cues: Array, actor: String, role: String, clip: String, target := "") -> Dictionary:
	for cue in cues:
		if cue.get("unit_id") == actor and cue.get("cast_key") == role \
				and cue.get("clip") == clip and cue.get("target_id", "") == target:
			return cue
	failures.append("Missing %s/%s cue for %s targeting %s: %s" % [role, clip, actor, target, cues])
	return {}


func _test_direct_actions() -> void:
	var cases := [
		["knight", "knight_aura", "", "guard"],
		["healer", "healer_bonk", "foe", "bonk"],
		["wizard", "wizard_blast", "", "blast"],
		["wizard", "wizard_pull", "foe", "pull"],
		["rogue", "rogue_confusing_dodge", "", "swap"],
		["rogue", "rogue_wasnt_me", "foe", "misdirect"],
	]
	for entry in cases:
		var role: String = entry[0]
		var units := [_unit("actor_instance", role, Vector2i(3, 3)),
			_unit("foe", "harpooner", Vector2i(4, 3))]
		if role == "rogue":
			units.append(_unit("friend", "knight", Vector2i(3, 7)))
		var state := _state(units)
		var cues := _action(state, "actor_instance", entry[1], entry[2])
		# Autonomous-targeting actions report the resolved target rather than the empty command.
		var expected_target: String = entry[2]
		if entry[1] == "rogue_confusing_dodge":
			expected_target = "friend"
		elif entry[1] == "wizard_blast":
			expected_target = "foe"
		var cue := _cue(cues, "actor_instance", role, entry[3], expected_target)
		if entry[1] == "knight_aura" and not cue.is_empty():
			_check({"id": "actor_instance", "cell": Vector2i(3, 3), "kind": "guard"} in cue.get("recipients", []),
				"Guard effect is attached to the acting knight's cell")
		if entry[1] == "rogue_wasnt_me" and not cue.is_empty():
			_check(cue.recipients == [{"id": "foe", "cell": Vector2i(4, 3), "kind": "status"}],
				"Wasn't Me marks the affected opponent, not their future victim")


func _test_healing() -> void:
	var state := _state([_unit("medic_2", "healer", Vector2i(3, 3)),
		_unit("injured", "knight", Vector2i(3, 4), 4)])
	_cue(_action(state, "medic_2", "healer_heal"), "medic_2", "healer", "ally_heal", "injured")
	state.units[0].hp = 4
	state.units[1].hp = 10
	_cue(_action(state, "medic_2", "healer_heal"), "medic_2", "healer", "self_heal", "medic_2")

	# Canonical split events keep all affected recipients, not an arbitrary one.
	state = _state([_unit("medic_2", "healer", Vector2i(3, 3)),
		_unit("a", "knight", Vector2i(3, 4), 4), _unit("b", "wizard", Vector2i(4, 4), 4)])
	var after := state.duplicate(true)
	after.units[1].hp = 6
	after.units[2].hp = 5
	var events := [
		{"type": "heal", "unit_id": "medic_2", "target_id": "a", "amount": 2, "ability_id": "healer_heal",
			"resolved_action": {"unit_id": "medic_2", "ability_id": "healer_heal", "event_count": 2,
				"source_cell": Vector2i(3, 3), "actor_cell": Vector2i(3, 3)}},
		{"type": "heal", "unit_id": "medic_2", "target_id": "b", "amount": 1, "ability_id": "healer_heal"},
	]
	var cues := _build(state, after, events)
	_check(cues.size() == 1, "Split heal is one performance, not one cast per recipient")
	if cues.size() == 1:
		var cue: Dictionary = cues[0]
		_check(cue.get("unit_id") == "medic_2" and cue.get("clip") == "ally_heal", "Split uses ally heal")
		var recipients: Array = cue.get("recipients", [])
		for unit in [state.units[1], state.units[2]]:
			_check(recipients.any(func(item): return item.get("id") == unit.id \
				and item.get("cell") == unit.position and item.get("kind") == "heal"),
				"Split heal retains recipient " + unit.id)


func _test_summons_and_minions() -> void:
	var state := _state([_unit("nec_2", "necromancer", Vector2i(3, 3)),
		_unit("corpse", "harpooner", Vector2i(4, 3), 0)])
	_cue(_action(state, "nec_2", "raise_dead", "corpse"), "nec_2", "necromancer", "raise_dead", "corpse")
	var choices: Array = rules.targets(state, "nec_2", "summon_skeleton")
	_check(not choices.is_empty(), "Skeleton summon fixture has a target")
	if not choices.is_empty():
		var target: String = choices[0].id
		var cue := _cue(_action(state, "nec_2", "summon_skeleton", target),
			"nec_2", "necromancer", "summon_skeleton")
		if not cue.is_empty():
			_check(cue.get("target_cell") == choices[0].position, "Summon cue identifies the spawn cell")
			_check(cue.get("recipients", []).any(func(item): return item.get("id") == "nec_2_skeleton" \
				and item.get("cell") == choices[0].position and item.get("kind") == "summon"),
				"Summon cue identifies the new skeleton at its spawn cell")
	for entry in [["skeleton", "wave", ""], ["skeleton", "dont_go", "foe"],
			["zombie", "say_hello", "foe"], ["zombie", "offer_flower", "foe"]]:
		state = _state([_unit("minion_instance", entry[0], Vector2i(3, 3)),
			_unit("foe", "harpooner", Vector2i(4, 3))])
		var command_target := "foe" if entry[1] == "offer_flower" else ""
		var cue := _cue(_action(state, "minion_instance", entry[1], command_target),
			"minion_instance", entry[0], entry[1], entry[2])
		if entry[1] == "offer_flower" and not cue.is_empty():
			_check(cue.get("source_cell") == Vector2i(3, 3) and cue.get("target_cell") == Vector2i(4, 3),
				"Zombie throw uses resolved source and target cells")
		if entry[1] == "dont_go" and not cue.is_empty():
			_check(cue.recipients == [{"id": "foe", "cell": Vector2i(4, 3), "kind": "status"}],
				"Don't Go marks the held unit as status feedback, not damage or movement")


func _test_repeated_performers_and_reactions() -> void:
	var state := _state([_unit("bard_one", "bard", Vector2i(1, 1)),
		_unit("bard_two", "bard", Vector2i(2, 1)), _unit("foe", "harpooner", Vector2i(4, 1))])
	var events := [
		{"type": "performance", "unit_id": "bard_one", "target_id": "foe", "ability_id": "inspiring_melody",
			"resolved_action": {"unit_id": "bard_one", "ability_id": "inspiring_melody", "event_count": 1,
				"source_cell": Vector2i(1, 1), "actor_cell": Vector2i(1, 1)}},
		{"type": "performance", "unit_id": "bard_two", "target_id": "foe", "ability_id": "inspiring_melody",
			"resolved_action": {"unit_id": "bard_two", "ability_id": "inspiring_melody", "event_count": 1,
				"source_cell": Vector2i(2, 1), "actor_cell": Vector2i(2, 1)}},
		{"type": "performance", "unit_id": "bard_one", "target_id": "foe", "ability_id": "inspiring_melody",
			"resolved_action": {"unit_id": "bard_one", "ability_id": "inspiring_melody", "event_count": 1,
				"source_cell": Vector2i(1, 1), "actor_cell": Vector2i(1, 1)}},
		{"type": "damage", "unit_id": "bard_two", "source_id": "bard_two", "target_id": "foe", "ability_id": "healing_sonnet",
			"resolved_action": {"unit_id": "bard_two", "ability_id": "healing_sonnet", "event_count": 1,
				"source_cell": Vector2i(2, 1), "actor_cell": Vector2i(2, 1)}},
	]
	var cues := _build(state, state.duplicate(true), events)
	_check(cues.size() == 4, "Repeated performances by the same actor remain distinct")
	if cues.size() == 4:
		_check(cues[0].get("unit_id") == "bard_one" and cues[1].get("unit_id") == "bard_two" \
			and cues[2].get("unit_id") == "bard_one", "Performance order and instance identity are preserved")
	_cue(cues, "bard_two", "bard", "healing_sonnet", "foe")
	var dry := [{"type": "performance", "unit_id": "bard_one", "ability_id": "inspiring_melody",
		"resolved_action": {"unit_id": "bard_one", "ability_id": "inspiring_melody", "event_count": 1,
			"source_cell": Vector2i(1, 1), "actor_cell": Vector2i(1, 1)}}]
	var dry_cue := _cue(_build(state, state.duplicate(true), dry), "bard_one", "bard", "inspiring_melody")
	if not dry_cue.is_empty():
		_check(dry_cue.recipients.is_empty() and not dry_cue.has("target_cell"),
			"Dry melody plays without recipient feedback")

	state = _state([_unit("caster", "wizard", Vector2i(3, 3)),
		_unit("foe", "harpooner", Vector2i(4, 3)), _unit("other_wizard", "wizard", Vector2i(5, 3))])
	events = [
		{"type": "damage", "source_id": "caster", "target_id": "foe", "ability_id": "wizard_blast",
			"resolved_action": {"unit_id": "caster", "ability_id": "wizard_blast", "event_count": 5,
				"source_cell": Vector2i(3, 3), "actor_cell": Vector2i(3, 3)}},
		{"type": "retaliate", "unit_id": "foe", "source_id": "foe", "target_id": "caster", "ability_id": "wizard_blast"},
		{"type": "damage", "source_id": "foe", "target_id": "caster", "ability_id": "wizard_blast"},
		{"type": "death_blast", "unit_id": "foe", "source_id": "foe", "position": Vector2i(4, 3), "ability_id": "wizard_blast"},
		{"type": "damage", "source_id": "foe", "target_id": "other_wizard", "ability_id": "wizard_blast"},
	]
	cues = _build(state, state.duplicate(true), events)
	_check(cues.size() == 1, "Reactive damage and cascaded ability tags do not create extra casts")
	_cue(cues, "caster", "wizard", "blast", "foe")


func _test_reflection() -> void:
	var state := _state([_unit("guard", "knight", Vector2i(2, 2)),
		_unit("ward", "healer", Vector2i(3, 2)), _unit("caster", "wizard", Vector2i(4, 2)),
		_unit("recipient", "harpooner", Vector2i(1, 2))])
	var guard: Dictionary = rules.preview(state, "guard", "knight_aura")
	_check(guard.get("valid", false), "Reflection guard fixture resolves")
	if not guard.get("valid", false):
		return
	var protected: Dictionary = guard.result
	var plan: Dictionary = rules.preview(protected, "caster", "wizard_blast")
	_check(plan.get("valid", false), "Reflected blast fixture resolves")
	if not plan.get("valid", false):
		return
	_check(plan.events.any(func(event): return event.get("type") == "reflect"), "Fixture actually reflects")
	var cues := _build(protected, plan.result, plan.events)
	_check(cues.size() == 1, "Reflection creates only the original caster's cue")
	_cue(cues, "caster", "wizard", "blast", "recipient")


func _test_committed_round() -> void:
	var state := _state([_unit("wizard_instance", "wizard", Vector2i(3, 3)),
		_unit("foe", "harpooner", Vector2i(4, 3)),
		_unit("civilian", "ferryman", Vector2i(10, 10))])
	var selected: Dictionary = rules.choose_manual(state, "wizard_instance", "wizard_blast")
	var plan: Dictionary = rules.preview_round(selected)
	_check(plan.get("valid", false), "Direct action round is valid")
	if not plan.get("valid", false):
		return
	var result: Dictionary = rules.commit_round(selected, plan)
	_check(result == plan.result, "Round commit agrees with forecast")
	_cue(_build(selected, result, plan.events), "wizard_instance", "wizard", "blast", "foe")


func _test_non_actions_and_aliases() -> void:
	var state := _state([_unit("mage", "wizard", Vector2i(1, 1)),
		_unit("alchemist", "healer", Vector2i(2, 1))])
	var events := [
		{"type": "move", "unit_id": "mage", "position": Vector2i(2, 2), "ability_id": "wizard_blast"},
		{"type": "wait", "unit_id": "mage", "ability_id": "wizard_blast"},
		{"type": "wait", "unit_id": "mage"},
	]
	_check(_build(state, state.duplicate(true), events).is_empty(), "Pursuit and invalid waits do not animate casts")
	var alias := defs.duplicate(true)
	alias.characters["alias_healer"] = alias.characters.healer.duplicate(true)
	alias.characters.alias_healer.erase("cast_key")
	alias.characters.alias_healer.erase("cast_art_key")
	var old_defs := defs
	defs = alias
	var alias_state := _state([_unit("alchemist", "alias_healer", Vector2i(3, 3)),
		_unit("foe", "harpooner", Vector2i(4, 3))])
	_check(_action(alias_state, "alchemist", "healer_bonk", "foe").is_empty(),
		"An unmodeled character sharing a kit or art does not borrow a cast")
	defs = old_defs


func _test_custom_ability_handlers() -> void:
	var original := defs
	defs = defs.duplicate(true)
	defs.upgrades.erase("necromancer_warm_welcome")
	defs.abilities.say_hello = {"handler": "attack", "label": "Shout", "help": "Damage the nearest opponent.",
		"params": {"damage": 2}, "targeting": {"kind": "automatic", "teams": ["enemies"]}}
	var state := _state([_unit("recast_zombie", "zombie", Vector2i(3, 3)),
		_unit("foe", "harpooner", Vector2i(4, 3))])
	var plan: Dictionary = rules.preview(state, "recast_zombie", "say_hello")
	_check(plan.get("valid", false), "Catalog accepts custom Say Hello as an automatic attack")
	if plan.get("valid", false):
		_check(plan.result.units[1].hp == 8 and plan.result.units[1].position == Vector2i(4, 3),
			"Custom Say Hello resolves as damage instead of movement")
		_check(_build(state, plan.result, plan.events).is_empty(),
			"A custom attack must not play the stock repel-only greeting")
	defs = original


func _test_mixologist_recipes() -> void:
	for recipe in [["alchemist_potion", "ally", "other_ally", "potion"],
			["alchemist_acid", "foe", "other_foe", "acid"]]:
		var state := _state([_unit("mix", "alchemist", Vector2i(3, 3)),
			_unit("ally", "knight", Vector2i(3, 4), 4),
			_unit("other_ally", "healer", Vector2i(3, 2), 4),
			_unit("foe", "harpooner", Vector2i(4, 3)),
			_unit("other_foe", "harpooner", Vector2i(2, 3))])
		state.units[0]["upgrades"] = {"alchemist_spare_vial": 1, "alchemist_keep_the_culture": 1}
		var tonic: Dictionary = rules.preview(state, "mix", "alchemist_plain_tonic", "ally")
		_check(tonic.get("valid", false), "Plain Tonic fixture resolves")
		if tonic.get("valid", false):
			_cue(_build(state, tonic.result, tonic.events), "mix", "alchemist", "potion", "ally")
		var plan: Dictionary = rules.preview(state, "mix", recipe[0], recipe[1])
		_check(plan.get("valid", false), "Origin recipe fixture resolves: " + recipe[0])
		if not plan.get("valid", false):
			continue
		var after: Dictionary = rules.apply_plan(state, plan)
		_cue(_build(state, after, plan.events), "mix", "alchemist", recipe[3], recipe[1])
		var repeat: Dictionary = rules.preview(after, "mix", "alchemist_repeat_batch", recipe[2])
		_check(repeat.get("valid", false), "Repeat Batch fixture resolves after " + recipe[0])
		if repeat.get("valid", false):
			var repeated: Dictionary = rules.apply_plan(after, repeat)
			var cues := _build(after, repeated, repeat.events)
			_cue(cues, "mix", "alchemist", recipe[3], recipe[2])
			_check(cues.all(func(cue): return cue.get("unit_id") == "mix"),
				"Repeat Batch does not animate another hero")
