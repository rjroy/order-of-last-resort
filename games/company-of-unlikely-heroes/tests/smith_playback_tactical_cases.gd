extends SceneTree
## Playback fixtures plus a headless Rules forecast check. Import this script
## and call cases(); running it directly checks each returned opening.
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild_progression.gd")
const Adventure = preload("res://adventure.gd")
const Commissions = preload("res://commissions.gd")
const Rules = preload("res://rules.gd")

# Source, wearer, fitted form, petition (empty for native kit / outing reward).
const ROWS := [
	["knight_push", "knight", "fitted_pull", ""],
	["knight_aura", "knight", "clear_the_floor", ""],
	["healer_bonk", "healer", "keep_your_head_down", ""],
	["healer_heal", "healer", "doctors_orders", ""],
	["wizard_blast", "wizard", "mending_blast", ""],
	["wizard_pull", "wizard", "send_off", ""],
	["rogue_wasnt_me", "rogue", "it_was_me", ""],
	["rogue_confusing_dodge", "rogue", "clear_jump", ""],
	["knight_rescue_line", "knight", "safety_distance", "knight_rescue_line"],
	["healer_field_dressing", "healer", "unpick_the_stitch", "healer_field_dressing"],
	["wizard_ring_sparks", "wizard", "ring_of_salve", "wizard_ring_sparks"],
	["rogue_tripwire", "rogue", "cut_the_wire", "rogue_tripwire"],
	["knight_shield_throw", "knight", "lend_a_shield", ""],
]


static func cases() -> Array[Dictionary]:
	var definitions: Dictionary = Catalog.read_default()
	var out: Array[Dictionary] = []
	for row: Array in ROWS:
		out.append(_case(definitions, row))
	return out


static func _case(defs: Dictionary, row: Array) -> Dictionary:
	var ability: String = row[0]
	var hero: String = row[1]
	var profile := {"guild_id": "tactical-playback-fixture", "board_seed": 147258, "board_generation": 0,
		"points": 1000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": ["knight", "healer", "wizard"]}
	var purchases := ["recruit_blacksmith", "recruit_alchemist"]
	if hero == "rogue":
		purchases.append("recruit_rogue")
	if not row[3].is_empty():
		purchases.append(row[3])
	for petition: String in purchases:
		profile = Progression.purchased_profile(defs, profile, petition)
		if profile.has("error"):
			push_error("Playback fixture purchase failed: %s: %s" % [petition, profile])
			return {"id": ability, "state": {}}
	var loadout := Progression.default_loadout(defs, profile, hero)
	if not row[3].is_empty():
		var grant: Dictionary = defs.guild_progression.petitions[row[3]].grant
		loadout.slots[grant.slot_id] = ability
		for option: Dictionary in Progression.order_options(defs, profile, hero, loadout):
			if option.compatible:
				loadout.order_id = option.id
				break
	var board := Commissions.board(defs, profile.board_seed)
	var run := Adventure.start_guild_commission(defs, board[0], ["blacksmith", hero, "alchemist"],
		profile, {hero: loadout}, 444)
	if run.get("reports", []).is_empty():
		push_error("Playback fixture commission failed: " + ability)
		return {"id": ability, "state": {}}
	run = Adventure.choose_route(run, run.reports[0].mission_id)
	# A real stock defeat-all board avoids objective-specific side effects.
	run.mission_ids[0] = "shield_wall"
	run = Adventure.begin_mission(run)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		push_error("Playback fixture mission failed: " + ability)
		return {"id": ability, "state": {}}
	var rules := Rules.new()
	var enemy := ""
	for unit: Dictionary in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			if enemy.is_empty():
				enemy = unit.id
			else:
				unit.hp = 0
	state.obstacles = []
	_unit(state, "blacksmith").position = Vector2i(2, 1)
	_unit(state, hero).position = Vector2i(3, 1)
	_unit(state, "alchemist").position = Vector2i(3, 2)
	_unit(state, "alchemist").hp = 3
	_unit(state, enemy).position = Vector2i(4, 1)
	_unit(state, enemy).hp = 20
	_unit(state, enemy).max_hp = 20
	state.orders.blacksmith = "order_try_this"
	state.orders.alchemist = "order_hold"
	var target := ""
	match ability:
		"knight_push":
			_unit(state, enemy).position = Vector2i(5, 1)
			target = enemy
		"healer_bonk", "knight_shield_throw":
			target = "alchemist"
		"wizard_pull", "rogue_wasnt_me", "healer_field_dressing":
			target = enemy
		"knight_rescue_line":
			_unit(state, "alchemist").position = Vector2i(5, 1)
			_unit(state, enemy).position = Vector2i(6, 3)
			target = "alchemist"
		"rogue_tripwire":
			_unit(state, "alchemist").statuses.tripwire_tangled = {"remaining": 2}
	if ability == "knight_shield_throw":
		_unit(state, hero).upgrades = {"knight_shield_throw": 1}
	return {"id": ability, "state": state, "actor": hero, "ability": ability,
		"target": target, "effective": row[2]}


static func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


func _initialize() -> void:
	var rules := Rules.new()
	var failures: Array[String] = []
	var all := cases()
	var ids: Array[String] = []
	for entry: Dictionary in all:
		var id: String = entry.id
		if id in ids:
			failures.append(id + ": duplicate ID")
		ids.append(id)
		var state: Dictionary = entry.state
		if state.is_empty():
			failures.append(id + ": empty opening")
			continue
		var actor: String = entry.actor
		var before := state.duplicate(true)
		var slot: Dictionary = rules.state_before_action(state, actor)
		if state != before or _unit(state, actor).has("fitted_by") \
				or _unit(slot, actor).get("fitted_by") != "blacksmith":
			failures.append(id + ": Smith must fit wearer in earlier slot")
		if entry.ability not in rules.entity_profile(state, actor).get("abilities", []):
			failures.append(id + ": source ability not in deployed kit")
		var planned: Dictionary = rules.choose_manual(state, actor, entry.ability, entry.target)
		var forecast: Dictionary = rules.preview_round(planned)
		if not forecast.get("valid", false) or planned.overrides.get(actor, {}).get("ability_id") != id:
			failures.append(id + ": forecast or selected source invalid")
			continue
		var found: bool = forecast.events.any(func(event: Dictionary) -> bool:
			var action: Dictionary = event.get("resolved_action", {})
			return action.get("unit_id") == actor and action.get("ability_id") == entry.effective \
				and action.get("source_ability_id") == id)
		if not found:
			failures.append(id + ": forecast did not perform " + entry.effective)
		if state != before:
			failures.append(id + ": forecast changed opening")
	if all.size() != 13:
		failures.append("Expected 13 cases, got %d" % all.size())
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: 13 tactical playback fixture forecasts")
	quit(0 if failures.is_empty() else 1)
