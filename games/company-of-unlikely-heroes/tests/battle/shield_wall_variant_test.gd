extends SceneTree

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/shield_wall_variant_test.gd
const Catalog = preload("res://content/catalog.gd")
const Board = preload("res://rules/board.gd")
const Rules = preload("res://rules/rules.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")
const CastCues = preload("res://presentation/cast/cast_cues.gd")
const WALL := "knight_shield_wall"

var rules := Rules.new()
var base: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	_test_guild()
	var defs: Dictionary = Fixture.add_fixed_escort(Catalog.read_default().duplicate(true))
	# Missing production content is a behavior failure, not a fixture error.
	if not defs.abilities.has(WALL):
		_check(false, "Shield Wall is available as an equipped ability")
	else:
		defs.characters.harpooner.behavior = "hold"
		defs.characters.ferryman.behavior = "hold"
		defs.abilities.healer_bonk.params.damage = 1
		defs.tiles.test_blocked = defs.tiles.stone.duplicate(true)
		defs.tiles.test_blocked.passable = false
		base = rules.new_game(defs, "test_escort")
		_check(not base.is_empty(), "Test-owned battle opens")
		if not base.is_empty():
			# Equip only this deployed Knight, leaving the authored catalog
			# profile intact for validation of its existing upgrades.
			var abilities: Array = Catalog.profile(defs, "knight").abilities.duplicate()
			abilities.erase("knight_aura")
			abilities.append(WALL)
			base["_guild"] = Catalog.FrozenCatalog.new({"kits": {"knight": {"abilities": abilities}}})
			_test_footprints()
			_test_bad_spans()
			_test_edge_attack()
			_test_wall_playback_cues()
	if failures.is_empty():
		print("PASS: Shield Wall variant")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _unit(id: String, character: String, position: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": position,
		"hp": 20, "max_hp": 20, "statuses": {}}


func _state() -> Dictionary:
	var state := base.duplicate(true)
	state.width = 10
	state.height = 10
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		_unit("knight", "knight", Vector2i(4, 4)),
		_unit("healer", "healer", Vector2i(8, 8)),
		_unit("enemy", "harpooner", Vector2i(9, 9)),
		_unit("civilian", "ferryman", Vector2i(0, 9))]
	state.orders = {"knight": "order_hold", "healer": "order_hold"}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(9, 0)}
	return state


func _ids(state: Dictionary, actor: String, ability: String) -> Array:
	return rules.targets(state, actor, ability).map(func(choice: Dictionary): return choice.get("id", ""))


func _round(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false), label + ": valid round forecast")
	_check(state == before and plan == rules.preview_round(state), label + ": forecast is pure and repeatable")
	if not plan.get("valid", false):
		return {}
	var committed: Dictionary = rules.commit_round(state, plan)
	_check(committed == plan.result and state == before, label + ": commit matches forecast")
	return committed


func _test_footprints() -> void:
	var cases := [
		[Vector2i(5, 4), [Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5)]],
		[Vector2i(3, 4), [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5)]],
		[Vector2i(4, 3), [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]],
		[Vector2i(4, 5), [Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)]]]
	for sample in cases:
		var state := _state()
		var center: Vector2i = sample[0]
		var cells: Array = sample[1]
		var target := Board.cell_id(center)
		var choices := _ids(state, "knight", WALL)
		_check(target in choices, "Open adjacent center %s is offered" % target)
		_check("5,5" not in choices and "6,4" not in choices,
			"Diagonal and non-adjacent centers are unavailable")
		var staged: Dictionary = rules.choose_manual(state, "knight", WALL, target)
		_check(staged.overrides.get("knight", {}).get("target_id") == target,
			"Shield Wall stages the chosen center %s" % target)
		var result := _round(staged, "Shield Wall at " + target)
		if result.is_empty():
			continue
		for cell: Vector2i in cells:
			_check(Board.can_enter(state, cell) and not Board.can_enter(result, cell),
				"Forecast and commit block wall cell %s" % Board.cell_id(cell))
		_check(Board.can_enter(result, center + (center - Vector2i(4, 4))),
			"Wall does not extend in the aiming direction")


func _test_bad_spans() -> void:
	var occupied := _state()
	occupied.units[1].position = Vector2i(5, 3)
	_check("5,4" not in _ids(occupied, "knight", WALL),
		"A character on an end prevents the whole span")
	var obstacle := _state()
	obstacle.obstacles.append({"id": "crate", "object_id": "crate", "position": Vector2i(5, 5),
		"hp": 10, "max_hp": 10, "statuses": {}})
	_check("5,4" not in _ids(obstacle, "knight", WALL),
		"An obstacle on an end prevents the whole span")
	var terrain := _state()
	terrain.terrain.append({"position": Vector2i(5, 3), "type": "test_blocked"})
	_check("5,4" not in _ids(terrain, "knight", WALL),
		"Impassable terrain on an end prevents the whole span")
	var edge := _state()
	edge.units[0].position = Vector2i(4, 0)
	_check("5,0" not in _ids(edge, "knight", WALL),
		"A span extending off the board is unavailable")


func _test_edge_attack() -> void:
	var state := _state()
	state.units[1].position = Vector2i(6, 3)
	var staged: Dictionary = rules.choose_manual(state, "knight", WALL, "5,4")
	var wall := _round(staged, "Create wall before edge attack")
	if wall.is_empty():
		return
	var cells := [Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5)]
	for cell: Vector2i in cells:
		_check(not Board.can_enter(wall, cell), "Wall occupies %s before attack" % Board.cell_id(cell))
	var targets := _ids(wall, "healer", "healer_bonk")
	_check(targets.size() == 1, "Melee attacker can target the wall's in-range end, not its out-of-range center")
	if targets.size() != 1:
		return
	var attack: Dictionary = rules.choose_manual(wall, "healer", "healer_bonk", targets[0])
	_check(attack.overrides.get("healer", {}).get("target_id") == targets[0],
		"Edge attack stages the shared wall entity")
	var destroyed := _round(attack, "One-damage edge attack")
	if destroyed.is_empty():
		return
	for cell: Vector2i in cells:
		_check(Board.can_enter(destroyed, cell), "One damage removes wall cell %s" % Board.cell_id(cell))
	_check(targets[0] not in _ids(destroyed, "healer", "healer_bonk"),
		"Destroyed shared wall is no longer an attack target")


func _test_wall_playback_cues() -> void:
	# Use real action events in turn order: an end can be hit even though the
	# wall did not exist on the opening board or survive on the final board.
	var opening := _state()
	opening.units[1].position = Vector2i(6, 3)
	var placement: Dictionary = rules.preview(opening, "knight", WALL, "5,4", true)
	_check(placement.get("valid", false), "Playback fixture places a wall")
	if not placement.get("valid", false):
		return
	var placed: Dictionary = rules.apply_plan(opening, placement)
	var events: Array = placement.events.duplicate(true)
	var placements: Array = events.filter(func(event: Dictionary) -> bool:
		return event.get("type") == "shield_wall_placed")
	_check(placements.size() == 1, "Playback fixture emits one wall placement event")
	if placements.size() != 1:
		return
	var wall_id: String = placements[0].get("wall_id", "")
	var cells: Array = [Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5)]
	_check(not wall_id.is_empty() and placements[0].get("cells", []).size() == 3
		and cells.all(func(cell: Vector2i) -> bool: return cell in placements[0].get("cells", [])),
		"Placement event identifies one wall and all three cells")
	var hit: Dictionary = rules.preview(placed, "healer", "healer_bonk", wall_id, true)
	_check(hit.get("valid", false), "Playback fixture attacks the wall's end")
	if not hit.get("valid", false):
		return
	var after: Dictionary = rules.apply_plan(placed, hit)
	events.append_array(hit.events)
	_check(after.obstacles.any(func(obstacle: Dictionary) -> bool:
		return obstacle.get("id") == wall_id and obstacle.get("hp", 1) <= 0),
		"Playback fixture destroys the same wall before the final board")
	var cues: Array = CastCues.build(opening, after, events, true)
	var appearance := {}
	var damage := {}
	var appearance_cue := -1
	var damage_cue := -1
	for cue_index in range(cues.size()):
		for effect: Dictionary in cues[cue_index].get("performance", {}).get("effects", []):
			if effect.get("kind") == "shield_wall_placed" and effect.get("target_id") == wall_id:
				appearance = effect
				appearance_cue = cue_index
			if effect.get("kind") == "damage" and effect.get("target_id") == wall_id:
				damage = effect
				damage_cue = cue_index
	_check(not appearance.is_empty(), "Committed playback has an appearance effect for the placed wall")
	_check(not damage.is_empty(), "Committed playback has a damage effect for the same wall")
	if appearance.is_empty() or damage.is_empty():
		return
	var shown: Array = appearance.get("cells", [])
	_check(shown.size() == 3 and cells.all(func(cell: Vector2i) -> bool: return cell in shown),
		"Appearance effect carries all three cells of the shared wall")
	_check(appearance_cue < damage_cue and int(appearance.get("event_index", -1)) >= 0
		and int(appearance.get("event_index", -1)) < int(damage.get("event_index", -1)),
		"Wall appears in playback before the hit that removes it")


func _test_guild() -> void:
	var defs: Dictionary = Fixture.add_fixed_escort(Catalog.read_default().duplicate(true))
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.tiles.test_blocked = defs.tiles.stone.duplicate(true)
	defs.tiles.test_blocked.passable = false
	var profile := {"guild_id": "shield-wall-test", "board_seed": 147258, "board_generation": 0,
		"points": 1000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": ["knight", "healer", "wizard"]}
	var before := Progression.default_loadout(defs, profile, "knight")
	profile = Progression.purchased_profile(defs, profile, WALL)
	_check(not profile.has("error"), "Stock Shield Wall petition can be purchased")
	if profile.has("error"):
		return
	_check(WALL in profile.purchased_ids, "Shield Wall purchase is recorded")
	var default_kit := Progression.default_loadout(defs, profile, "knight")
	_check(default_kit == before and default_kit.get("slots", {}).get("utility") != WALL,
		"Purchase does not silently equip Shield Wall")
	var choices := Progression.slot_options(defs, profile, "knight")
	_check(WALL in choices.get("utility", []), "Purchased Shield Wall is a utility choice")
	if WALL not in choices.get("utility", []):
		return
	for offense in ["knight_push", "knight_rescue_line"]:
		var owned := profile
		if offense == "knight_rescue_line":
			owned = Progression.purchased_profile(defs, profile, "knight_rescue_line")
			_check(not owned.has("error"), "Rescue Line can be purchased alongside Shield Wall")
			if owned.has("error"):
				continue
		var loadout := Progression.default_loadout(defs, owned, "knight")
		loadout.slots.offense = offense
		loadout.slots.utility = WALL
		loadout.order_id = "order_guard"
		var compatible := false
		for row: Dictionary in Progression.order_options(defs, owned, "knight", loadout):
			if row.id == "order_guard":
				compatible = row.compatible
		_check(compatible, "Guard remains compatible with Shield Wall and " + offense)
		if not compatible:
			continue
		var board := Commissions.board(defs, owned.board_seed)
		if board.is_empty():
			_check(false, "Stock guild commission board exists")
			continue
		var run := Adventure.start_guild_commission(defs, board[0], ["knight", "healer", "wizard"],
			owned, {"knight": loadout}, 444)
		if run.get("phase") != "route" or run.get("reports", []).is_empty():
			_check(false, "Guild company starts with Shield Wall and " + offense)
			continue
		run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
		var deployed: Dictionary = run.get("mission", {})
		if deployed.is_empty() or not deployed.has("_guild"):
			_check(false, "Guild company deploys Shield Wall and " + offense)
			continue
		var kit: Dictionary = rules.entity_profile(deployed, "knight")
		_check(WALL in kit.get("abilities", []) and offense in kit.get("abilities", [])
			and kit.get("habits", {}).has("order_guard"),
			"Deployed guild kit retains Guard and both selected abilities with " + offense)
		_guild_guard_round(defs, deployed._guild, offense)


func _guild_guard_round(defs: Dictionary, guild: Variant, label: String) -> void:
	# Preserve the actual deployed guild kit on a fixed escort board. Three
	# impassable center cells leave only the east-facing span available.
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state["_guild"] = guild
	state.width = 10
	state.height = 10
	state.default_tile = "stone"
	state.terrain = []
	for cell in [Vector2i(3, 4), Vector2i(4, 3), Vector2i(4, 5), Vector2i(5, 4)]:
		state.terrain.append({"position": cell, "type": "test_blocked"})
	state.obstacles = []
	state.units = [_unit("knight", "knight", Vector2i(4, 4)),
		_unit("healer", "healer", Vector2i(8, 8)),
		_unit("wizard", "wizard", Vector2i(8, 7)),
		_unit("enemy", "harpooner", Vector2i(9, 9)),
		_unit("civilian", "ferryman", Vector2i(0, 9))]
	state.orders = {"knight": "order_guard", "healer": "order_hold", "wizard": "order_hold"}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(9, 0)}
	_check(_ids(state, "knight", WALL).is_empty(), label + ": blocked board has no legal wall")
	var waiting: Dictionary = rules.preview_round(state)
	_check(waiting.get("events", []).any(func(event: Dictionary) -> bool:
		return event.get("unit_id") == "knight" and event.get("type") == "wait"),
		label + ": Guard waits when every span is blocked")
	var blocked := _round(state, label + " blocked Guard")
	if blocked.is_empty():
		return
	_check(blocked.obstacles.is_empty(), label + ": blocked Guard creates no wall")
	blocked.terrain = blocked.terrain.filter(func(tile: Dictionary) -> bool:
		return tile.position != Vector2i(5, 4))
	var choices := _ids(blocked, "knight", WALL)
	_check(choices == ["5,4"], label + ": exactly one placement becomes available")
	var placed := _round(blocked, label + " unblocked Guard")
	if placed.is_empty():
		return
	var cells := [Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5)]
	for cell: Vector2i in cells:
		_check(not Board.can_enter(placed, cell),
			label + ": Guard creates the available wall after waiting")
	var first_obstacles: Array = placed.obstacles.duplicate(true)
	# Open a second complete span so keeping one wall is not just a result of
	# the initial terrain restriction.
	placed.terrain = []
	for cell in [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5)]:
		_check(Board.can_enter(placed, cell), label + ": second span is open apart from the live-wall limit")
	var live_forecast: Dictionary = rules.preview_round(placed)
	_check(live_forecast.get("events", []).any(func(event: Dictionary) -> bool:
		return event.get("unit_id") == "knight" and event.get("type") == "wait"),
		label + ": Guard waits while its wall is alive")
	var again := _round(placed, label + " Guard with live wall")
	if not again.is_empty():
		_check(again.obstacles == first_obstacles, label + ": Guard does not create a second live wall")
		for cell: Vector2i in cells:
			_check(not Board.can_enter(again, cell), label + ": existing wall stays in place")
