extends RefCounted

## Open, unmarked scene states. Smith's earlier standing order supplies the
## actual fitting during the scene driver's pre-actor forecast.
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Rules = preload("res://rules/rules.gd")


static func cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec in [
		["healing_sonnet", "bard", "healing_sonnet_in_tune"],
		["inspiring_melody", "bard", "inspiring_melody_in_tune"],
		["bard_take_the_stage", "bard", "company_chorus"],
		["summon_skeleton", "necromancer", "recall_skeleton"],
		["raise_dead", "necromancer", "play_dead"],
		["necro_grave_bell", "necromancer", "dinner_bell"],
		["necromancer_say_hello_to_that_one", "necromancer", "stay_close_to_that_one"],
	]:
		var ability: String = spec[0]
		var actor: String = spec[1]
		var state := _opening(actor, ability == "necro_grave_bell")
		if state.is_empty():
			push_error("Playback case could not open: " + ability)
			continue
		var target := ""
		match ability:
			"healing_sonnet", "bard_take_the_stage":
				_unit(state, "bard").hp -= 2
				_unit(state, "blacksmith").hp -= 1
				# The old seeded choice was the Smith; Company Chorus also heals the Bard.
				target = "blacksmith"
				if ability == "bard_take_the_stage":
					_unit(state, "bard").upgrades = {"bard_house_lights": 1}
			"inspiring_melody":
				target = "necromancer"
			"summon_skeleton":
				state = _summon(state)
				target = "2,1"
			"raise_dead":
				_unit(state, "corpse").hp = 0
				state = _perform(state, "raise_dead", "corpse")
			"necro_grave_bell":
				target = "enemy"
			"necromancer_say_hello_to_that_one":
				_unit(state, "necromancer").upgrades = {"necromancer_say_hello_to_that_one": 1}
				state = _summon(state)
				target = "bard"
		if state.is_empty():
			push_error("Playback case setup failed: " + ability)
			continue
		var entry := {"id": ability, "state": state, "actor": actor,
			"ability": ability, "target": target, "effective": spec[2]}
		if ability == "summon_skeleton":
			entry["target_position"] = Vector2i(2, 1)
		result.append(entry)
	return result


static func _opening(actor: String, equip_bell: bool) -> Dictionary:
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	defs.characters.playback_enemy = defs.characters.grunt.duplicate(true)
	defs.characters.playback_enemy.behavior = "hold"
	defs.encounters.smith_performance_playback = {"board": "road", "seed": 12345,
		"party_slots": [[0, 1], [1, 1], [5, 3]], "placements": [
			{"id": "enemy", "character": "playback_enemy", "at": [4, 1]},
			{"id": "corpse", "character": "playback_enemy", "at": [6, 2]}]}
	defs.missions.smith_performance_playback = defs.missions.shield_wall.duplicate(true)
	defs.missions.smith_performance_playback.encounter = "smith_performance_playback"
	defs.missions.smith_performance_playback.erase("default_party")
	var other := "necromancer" if actor == "bard" else "bard"
	var state: Dictionary = Rules.open_mission(defs, "smith_performance_playback",
		["blacksmith", actor, other])
	if state.is_empty():
		return {}
	state.orders.blacksmith = "order_try_this"
	state.orders[actor] = "order_hold"
	state.orders[other] = "order_hold"
	if equip_bell:
		var profile := {"guild_id": "playback-fixture", "board_seed": 12345,
			"board_generation": 0, "points": 100000, "purchased_ids": [],
			"preferred_loadouts": {}, "recruited_ids": ["knight", "healer", "wizard"]}
		for petition in ["recruit_necromancer", "necro_grave_bell"]:
			profile = Progression.purchased_profile(defs, profile, petition)
			if profile.has("error"):
				return {}
		var loadout: Dictionary = Progression.default_loadout(defs, profile, "necromancer")
		loadout.slots.utility = "necro_grave_bell"
		for order: Dictionary in Progression.order_options(defs, profile, "necromancer", loadout):
			if order.get("compatible", false):
				loadout.order_id = order.id
				break
		var kit := Progression.effective_kit(defs, profile, "necromancer", loadout)
		if kit.is_empty():
			return {}
		state["_guild"] = Catalog.FrozenCatalog.new({"guild_id": profile.guild_id,
			"board_seed": profile.board_seed, "board_generation": 0, "kits": {"necromancer": kit}})
	return state


static func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


static func _perform(state: Dictionary, ability: String, target: String) -> Dictionary:
	var rules := Rules.new()
	var plan: Dictionary = rules.preview(state, "necromancer", ability, target)
	return rules.apply_plan(state, plan) if plan.get("valid", false) else {}


static func _summon(state: Dictionary) -> Dictionary:
	state = _perform(state, "summon_skeleton", "1,2")
	if state.is_empty():
		return {}
	for unit: Dictionary in state.units:
		if unit.get("character_id") == "skeleton" and unit.get("summoner_id") == "necromancer":
			unit.position = Vector2i(3, 3)
			return state
	return {}
