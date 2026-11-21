extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/three_mission_test.gd
# Integration checks use the shipped mission catalog and actual forecast/commit APIs.
const Catalog = preload("res://content/catalog.gd")
const Adventure = preload("res://adventure.gd")
const Board = preload("res://rules/board.gd")
var rules = preload("res://rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []
const MISSIONS := ["goblin_mob", "harpoon_squad", "unwelcome_guest"]


func _initialize() -> void:
	defs = Catalog.read_default()
	_test_selection()
	_test_openings()
	_test_sequence()
	_test_goblins()
	_test_goblin_pack_bonus()
	_test_squad()
	_test_troll()
	_test_persistent_sonnet_on_troll()
	if failures.is_empty():
		print("PASS: village troubles integration")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _characters(state: Dictionary, character: String) -> Array:
	return state.get("units", []).filter(func(unit: Dictionary) -> bool:
		return unit.get("character_id") == character)


func _open(mission: String, party: Array) -> Dictionary:
	return rules.open_mission(defs, mission, party)


func _round(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(state == before and plan == rules.preview_round(state) and plan.get("valid", false),
		label + ": forecast is valid, deterministic and non-mutating")
	if not plan.get("valid", false):
		return {}
	var committed: Dictionary = rules.commit_round(state, plan)
	var comparable := committed.duplicate(true)
	comparable.erase("_terminal_commit")
	_check(comparable == plan.get("result"), label + ": commit agrees with forecast")
	return {"state": committed, "events": plan.get("events", [])}


func _test_selection() -> void:
	var outing: Dictionary = defs.get("adventures", {}).get("village_troubles", {})
	_check(not outing.is_empty(), "Village Troubles outing exists")
	if outing.is_empty():
		return
	_check(outing.get("missions") == MISSIONS, "Outing has the fixed three-mission sequence")
	var roster: Array = outing.get("roster", [])
	var previous: Array = defs.get("adventures", {}).get("first_outing", {}).get("roster", []).duplicate()
	var sorted_roster := roster.duplicate()
	sorted_roster.sort()
	previous.sort()
	_check(sorted_roster == previous,
		"New outing uses the same roster")
	for first in roster:
		for second in roster:
			for third in roster:
				if first == second or first == third or second == third:
					continue
				var picks := [first, second, third]
				var run: Dictionary = Adventure.start_adventure(defs, "village_troubles", picks)
				_check(run.get("phase") == "ready" and run.get("party") == picks
					and run.get("mission_ids") == MISSIONS, "Ordered company starts: %s" % [picks])
	for picks in [[], ["knight", "wizard"], ["knight", "knight", "wizard"],
			["knight", "wizard", "missing"]]:
		_check(Adventure.start_adventure(defs, "village_troubles", picks).is_empty(),
			"Invalid company is rejected: %s" % [picks])


func _test_openings() -> void:
	for party in [["knight", "healer", "wizard"], ["necromancer", "rogue", "bard"]]:
		for mission in MISSIONS:
			var state := _open(mission, party)
			_check(not state.is_empty(), "%s opens for %s" % [mission, party])
			if state.is_empty():
				continue
			_check(state.get("party") == party and state.get("outcome") == "ongoing",
				mission + ": selected party starts ongoing")
			for index in range(party.size()):
				_check(state.units[index].id == party[index], mission + ": preserves selected action order")
			_round(state, mission + " opening")


func _test_sequence() -> void:
	var party := ["healer", "knight", "bard"]
	var run: Dictionary = Adventure.start_adventure(defs, "village_troubles", party)
	if run.is_empty():
		return
	for index in range(MISSIONS.size()):
		run = Adventure.begin_mission(run)
		var state: Dictionary = run.get("mission", {}).duplicate(true)
		_check(run.get("phase") == "mission" and state.get("mission_id") == MISSIONS[index],
			"Sequence deploys mission %d in order" % (index + 1))
		if state.is_empty():
			return
		if index < 2:
			# Controlled terminal board for expedition transitions, not a played route.
			for unit in state.units:
				if rules.entity_profile(state, unit.id).get("team") == "enemies":
					unit.hp = 0
		else:
			var trolls := _characters(state, "village_troll")
			if trolls.is_empty():
				return
			var selected: Dictionary = rules.choose_manual(state, "knight", "knight_push", trolls[0].id)
			state = selected
		var result := _round(state, "Sequence mission %d" % (index + 1))
		if result.is_empty() or result.state.get("outcome") != "victory":
			_check(false, "Sequence mission %d commits victory" % (index + 1))
			return
		run = Adventure.settle_mission(run, result.state)
		if index < 2:
			_check(run.get("phase") == "ready" and run.get("mission_index") == index + 1,
				"Victory advances exactly one mission")
			_check(run.get("party") == party, "Transition preserves selected party order")
		else:
			_check(run.get("phase") == "finished" and run.get("outcome") == "victory",
				"Third victory finishes the outing")


func _test_persistent_sonnet_on_troll() -> void:
	var party: Array = defs.missions.unwelcome_guest.default_party
	_check("bard" in party, "The guest mission's default company includes Bard")
	if "bard" not in party:
		return
	var run: Dictionary = Adventure.start_adventure(defs, "village_troubles", party)
	_check(not run.is_empty(), "Sonnet carry company starts")
	if run.is_empty():
		return
	for index in range(2):
		run = Adventure.begin_mission(run)
		var state: Dictionary = run.get("mission", {}).duplicate(true)
		if state.is_empty():
			_check(false, "Sonnet carry mission deploys")
			return
		if index == 0:
			state = rules.set_order(state, "bard", "order_healing_sonnet")
			_check(state.orders.get("bard") == "order_healing_sonnet", "Bard accepts persistent Sonnet order")
		else:
			_check(state.orders.get("bard") == "order_healing_sonnet", "Sonnet deploys into second mission")
		# Stage only terminal enemies; expedition transitions and carry use real commits.
		for unit in state.units:
			if rules.entity_profile(state, unit.id).get("team") == "enemies":
				unit.hp = 0
		var result := _round(state, "Sonnet carry mission %d" % (index + 1))
		if result.is_empty() or result.state.get("outcome") != "victory":
			_check(false, "Sonnet carry mission commits victory")
			return
		run = Adventure.settle_mission(run, result.state)
		_check(run.get("phase") == "ready"
			and run.get("carry_by_id", {}).get("bard", {}).get("order") == "order_healing_sonnet",
			"Sonnet remains active between missions")
		if run.get("phase") != "ready":
			return
	run = Adventure.begin_mission(run)
	var guest: Dictionary = run.get("mission", {})
	if guest.is_empty():
		_check(false, "Sonnet carry reaches the guest mission")
		return
	_check(guest.orders.get("bard") == "order_healing_sonnet",
		"Carried Sonnet remains active in the troll mission")
	var trolls := _characters(guest, "village_troll")
	if trolls.size() != 1:
		_check(false, "Sonnet fixture has one troll")
		return
	var troll_id: String = trolls[0].id
	var low_hp := guest.duplicate(true)
	_entity(low_hp, troll_id).hp = 1
	var lethal := _round(low_hp, "Lethal standing Sonnet")
	if not lethal.is_empty():
		_check(_sonnet_damage(lethal.events, troll_id) and _entity(lethal.state, troll_id).get("hp") == 0,
			"Standing Sonnet deals the last HP of damage to the living troll")
		_check(lethal.state.get("outcome") == "defeat", "Killing the troll with Sonnet loses the mission")
	var push_then_song: Dictionary = rules.choose_manual(low_hp, "knight", "knight_push", troll_id)
	var knight_turn: Dictionary = rules.state_before_action(push_then_song, "knight")
	_check(rules.preview(knight_turn, "knight", "knight_push", troll_id).get("valid", false),
		"Knight can push the one-HP troll on the authored board")
	var crossing := _round(push_then_song, "Lethal post-crossing Sonnet")
	if not crossing.is_empty():
		var cells: Array = defs.boards[guest.board_id].zones[guest.objective.zone]
		var pushed_at := -1
		var damaged_at := -1
		for index in range(crossing.events.size()):
			var event: Dictionary = crossing.events[index]
			if event.get("type") == "push" and event.get("unit_id") == "knight" \
					and event.get("target_id") == troll_id:
				var pos: Vector2i = event.position
				if [pos.x, pos.y] not in cells:
					pushed_at = index
			if _sonnet_damage([event], troll_id):
				damaged_at = index
		_check(pushed_at >= 0 and damaged_at > pushed_at,
			"Knight pushes troll outside the square before standing Sonnet hits")
		_check(_entity(crossing.state, troll_id).get("hp") == 0
			and crossing.state.get("outcome") == "defeat",
			"Lethal Sonnet after crossing defeats rather than wins")
	var current := guest
	for turn in range(2):
		var hp: int = _entity(current, troll_id).hp
		var result := _round(current, "Persistent troll Sonnet %d" % (turn + 1))
		if result.is_empty():
			return
		_check(_sonnet_damage(result.events, troll_id) and _entity(result.state, troll_id).get("hp") == hp - 1,
			"Standing Sonnet damages the living troll by one on round %d" % (turn + 1))
		_check(result.state.get("orders", {}).get("bard") == "order_healing_sonnet",
			"Sonnet remains the standing order after round %d" % (turn + 1))
		if result.state.get("outcome") != "ongoing":
			_check(false, "Troll survives the nonlethal Sonnet fixture")
			return
		current = result.state


func _sonnet_damage(events: Array, troll_id: String) -> bool:
	for event in events:
		if event.get("type") == "damage" and event.get("source_id") == "bard" \
				and event.get("target_id") == troll_id and event.get("amount") == 1 \
				and event.get("ability_id") == "healing_sonnet":
			return true
	return false


func _test_goblins() -> void:
	var state := _open("goblin_mob", ["necromancer", "healer", "wizard"])
	if state.is_empty():
		return
	var goblins := _characters(state, "goblin")
	_check(goblins.size() == 5, "Goblin mob contains five goblins")
	if goblins.size() != 5:
		return
	var bruiser_profile: Dictionary = Catalog.profile(defs, "bruiser")
	_check(not bruiser_profile.is_empty() and goblins[0].max_hp < int(bruiser_profile.get("max_hp", 0)),
		"Individual goblins are weaker than the squad Bruiser")
	var hero_pos: Vector2i = _entity(state, "healer").position
	var horizontal := {}
	var vertical := {}
	for goblin in goblins:
		var delta: Vector2i = goblin.position - hero_pos
		if delta.x != 0:
			horizontal[signi(delta.x)] = true
		if delta.y != 0:
			vertical[signi(delta.y)] = true
	_check(horizontal.size() == 2 or vertical.size() == 2, "Goblins begin on both sides of the company")
	var initial := {}
	for goblin in goblins:
		initial[goblin.id] = goblin.position
	var advances := {}
	var attacked := {}
	for turn in range(8):
		if state.get("outcome") != "ongoing":
			break
		var result := _round(state, "Goblin round %d" % turn)
		if result.is_empty():
			return
		for event in result.events:
			var id: String = event.get("unit_id", event.get("source_id", ""))
			if initial.has(id) and event.get("type") == "move":
				advances[id] = true
			if event.get("type") == "damage" and initial.has(event.get("source_id", "")) \
					and event.get("target_id") in state.party:
				attacked[event.source_id] = true
		state = result.state
	_check(advances.size() >= 2, "Multiple goblins advance on the party")
	_check(attacked.size() >= 2, "Multiple goblins can inflict actual pack danger")
	_test_wave()
	_test_authored_wave()


func _test_goblin_pack_bonus() -> void:
	var state := _open("goblin_mob", ["healer", "knight", "bard"])
	var goblins := _characters(state, "goblin")
	if goblins.size() < 2:
		_check(false, "Pack bonus fixture has two authored goblins")
		return
	for unit in state.units:
		if unit.id != "healer":
			unit.hp = 0
	var attacker: Dictionary = goblins[0]
	var helper: Dictionary = goblins[1]
	attacker.hp = attacker.max_hp
	attacker.position = Vector2i(2, 2)
	helper.position = Vector2i(4, 2)
	_entity(state, "healer").position = Vector2i(3, 2)
	var lone := _goblin_damage(state, attacker.id)
	helper.hp = helper.max_hp
	var packed := _goblin_damage(state, attacker.id)
	var bonus: int = defs.abilities.goblin_jab.params.surround_bonus.damage
	_check(bonus > 0 and packed == lone + bonus,
		"Same goblin deals the authored bonus when a living ally crowds its target")
	helper.position = Vector2i(5, 2)
	_check(_goblin_damage(state, attacker.id) == lone,
		"A nonadjacent living goblin gives no crowd bonus")
	helper.position = Vector2i(4, 2)
	helper.hp = 0
	_check(_goblin_damage(state, attacker.id) == lone,
		"An adjacent defeated goblin gives no crowd bonus")


func _goblin_damage(state: Dictionary, actor: String) -> int:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, actor, "goblin_jab", "healer")
	_check(plan.get("valid", false) and state == before, "Goblin jab previews without mutation")
	if not plan.get("valid", false):
		return -10000
	_check(rules.apply_plan(state, plan) == plan.result, "Goblin jab commits its forecast")
	for event in plan.events:
		if event.get("type") == "damage" and event.get("source_id") == actor \
				and event.get("target_id") == "healer":
			return int(event.amount)
	_check(false, "Goblin jab emits attacker damage against the controlled target")
	return -10000


func _test_authored_wave() -> void:
	var state := _open("goblin_mob", ["necromancer", "healer", "wizard"])
	state.rng_state = 2
	var selected: Dictionary = rules.choose_manual(state, "necromancer", "summon_skeleton", "2,2")
	_check(rules.preview(rules.state_before_action(selected, "necromancer"),
		"necromancer", "summon_skeleton", "2,2").get("valid", false),
		"Skeleton summon is legal in the authored opening")
	var first := _round(selected, "Authored goblin summon")
	if first.is_empty() or first.state.get("outcome") != "ongoing":
		_check(false, "Goblin summon opening continues")
		return
	var skeletons := _characters(first.state, "skeleton")
	_check(not skeletons.is_empty(), "Necromancer summons a skeleton in authored opening")
	if skeletons.is_empty():
		return
	var skeleton_id: String = skeletons[0].id
	var second := _round(first.state, "Authored goblin Wave")
	if second.is_empty():
		return
	var victims := {}
	for event in second.events:
		if event.get("type") == "damage" and event.get("source_id") == skeleton_id \
				and _entity(first.state, event.get("target_id", "")).get("character_id") == "goblin":
			victims[event.target_id] = true
	_check(victims.size() >= 2, "A real authored goblin round allows skeleton Wave to hit multiple goblins")


func _test_wave() -> void:
	var state := _open("goblin_mob", ["necromancer", "healer", "wizard"])
	var goblins := _characters(state, "goblin")
	if goblins.size() < 2:
		return
	# Keep the real board and authored profiles, staging a reachable local cluster
	# rather than making a permanent assertion about the opening coordinates.
	var found := false
	for y in range(state.height):
		for x in range(state.width):
			var center := Vector2i(x, y)
			var left := center + Vector2i.LEFT
			var right := center + Vector2i.RIGHT
			if Board.is_vacant(state, center) and Board.is_vacant(state, left) and Board.is_vacant(state, right):
				goblins[0].position = left
				goblins[1].position = right
				state.units.append({"id": "test_skeleton", "character_id": "skeleton",
					"position": center, "hp": 1, "max_hp": 1, "statuses": {},
					"summoner_id": "necromancer", "summon_priority": 0})
				found = true
				break
		if found:
			break
	_check(found, "Authored goblin board can stage a two-target Wave")
	if not found:
		return
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "test_skeleton", "wave")
	_check(plan.get("valid", false) and state == before, "Skeleton Wave forecasts on the goblin board")
	if not plan.get("valid", false):
		return
	var victims := {}
	for event in plan.get("events", []):
		if event.get("type") == "damage" and event.get("source_id") == "test_skeleton":
			victims[event.get("target_id")] = true
	_check(victims.has(goblins[0].id) and victims.has(goblins[1].id),
		"Skeleton Wave hits multiple goblins")
	_check(rules.apply_plan(state, plan) == plan.result, "Goblin Wave commits its forecast")


func _test_squad() -> void:
	var state := _open("harpoon_squad", ["healer", "rogue", "bard"])
	if state.is_empty():
		return
	for character in ["harpooner", "hookhand", "bruiser"]:
		_check(_characters(state, character).size() == 1, "Squad contains one " + character)
	var hooks := _characters(state, "hookhand")
	var bruisers := _characters(state, "bruiser")
	if hooks.is_empty() or bruisers.is_empty():
		return
	var hook: String = hooks[0].id
	var bruiser: String = bruisers[0].id
	var pulled := false
	var followup := false
	var disruptions := {}
	for turn in range(10):
		if state.get("outcome") != "ongoing":
			break
		var baseline := _round(state, "Squad round %d" % turn)
		if baseline.is_empty():
			return
		var hook_events := _events_by(baseline.events, "pull", hook)
		if not hook_events.is_empty():
			pulled = true
			var positions := {}
			for unit in state.units:
				positions[unit.id] = unit.position
			for event in baseline.events:
				var actor_id: String = event.get("unit_id", "")
				if event.get("type") == "move":
					positions[actor_id] = event.position
				elif event.get("type") == "pull" and actor_id == hook:
					var victim: String = event.get("target_id", "")
					_check(victim in state.party and positions.has(victim)
						and Board.distance(positions[victim], event.position) == 1,
						"Hookhand pulls a selected hero exactly one tile")
			# Search real available commands on the board at this hero's turn.
			# Different ability IDs must actually change the threatened pull.
			for actor in state.party:
				var turn_state: Dictionary = rules.state_before_action(state, actor)
				for option in rules.options(state, actor):
					if option.get("kind") != "action":
						continue
					var ability: String = option.id
					var targets: Array = rules.targets(turn_state, actor, ability)
					if option.get("target_kind") not in ["cell", "entity"]:
						targets = [{"id": ""}]
					for target in targets:
						var id: String = target.id
						if not rules.preview(turn_state, actor, ability, id).get("valid", false):
							continue
						var chosen: Dictionary = rules.choose_manual(state, actor, ability, id)
						var plan: Dictionary = rules.preview_round(chosen)
						if plan.get("valid", false) and _events_by(plan.events, "pull", hook).is_empty():
							var committed: Dictionary = rules.commit_round(chosen, plan)
							var comparable := committed.duplicate(true)
							comparable.erase("_terminal_commit")
							_check(comparable == plan.result, "Squad disruption commits its forecast")
							disruptions[ability] = true
		for event in baseline.events:
			if pulled and event.get("type") == "damage" and event.get("source_id") == bruiser \
					and event.get("target_id") in state.party:
				followup = true
		state = baseline.state
	_check(pulled, "Hookhand actually pulls a hero during the authored fight")
	_check(followup, "Bruiser lands a melee follow-up after Hookhand's pull")
	_check(not disruptions.is_empty(), "A legal action disrupts Hookhand without a Knight")
	_test_knight_disruption()


func _test_knight_disruption() -> void:
	var state := _open("harpoon_squad", ["healer", "knight", "bard"])
	var hooks := _characters(state, "hookhand")
	var bruisers := _characters(state, "bruiser")
	if hooks.is_empty() or bruisers.is_empty():
		return
	var hook: String = hooks[0].id
	var bruiser: String = bruisers[0].id
	var base: Dictionary = rules.preview_round(state)
	var selected: Dictionary = rules.choose_manual(state, "knight", "knight_push", bruiser)
	var before_knight: Dictionary = rules.state_before_action(selected, "knight")
	_check(rules.preview(before_knight, "knight", "knight_push", bruiser).get("valid", false),
		"Knight can legally push the Bruiser at its turn")
	var altered: Dictionary = rules.preview_round(selected)
	var base_hit := false
	var altered_hit := false
	for event in base.get("events", []):
		if event.get("type") == "damage" and event.get("source_id") == bruiser \
				and event.get("target_id") in state.party:
			base_hit = true
	for event in altered.get("events", []):
		if event.get("type") == "damage" and event.get("source_id") == bruiser \
				and event.get("target_id") in state.party:
			altered_hit = true
	_check(not _events_by(base.get("events", []), "pull", hook).is_empty() and base_hit,
		"Squad baseline forecasts both Hookhand pull and Bruiser hit")
	_check(base_hit and not altered_hit and not _events_by(altered.get("events", []), "push", "knight").is_empty(),
		"Knight push prevents the Bruiser follow-up")
	_round(selected, "Knight disrupts Bruiser")


func _events_by(events: Array, event_type: String, actor: String) -> Array:
	return events.filter(func(event: Dictionary) -> bool:
		return event.get("type") == event_type and event.get("unit_id") == actor)


func _test_troll() -> void:
	var state := _open("unwelcome_guest", ["necromancer", "healer", "wizard"])
	if state.is_empty():
		return
	var trolls := _characters(state, "village_troll")
	_check(trolls.size() == 1, "Village encounter has one troll")
	if trolls.size() != 1:
		return
	var troll_id: String = trolls[0].id
	var objective: Dictionary = state.get("objective", {})
	_check(objective.get("subject") == troll_id, "Troll is the objective subject")
	var board: Dictionary = defs.get("boards", {}).get(state.get("board_id"), {})
	var cells: Array = board.get("zones", {}).get("square", [])
	_check(not cells.is_empty(), "Village square is a marked authored zone")
	if cells.is_empty():
		return
	var square := {}
	for cell in cells:
		square[Vector2i(cell[0], cell[1])] = true
	var outside_found := false
	var inside_found := false
	for y in range(state.height):
		for x in range(state.width):
			var cell := Vector2i(x, y)
			if not Board.is_vacant(state, cell):
				continue
			var staged := state.duplicate(true)
			_entity(staged, troll_id).position = cell
			var plan: Dictionary = rules.preview_round(staged)
			if not plan.get("valid", false):
				continue
			var after: Dictionary = plan.result
			var troll := _entity(after, troll_id)
			if troll.get("hp", 0) <= 0:
				continue
			if not square.has(cell) and not square.has(troll.position) and after.get("outcome") == "victory":
				outside_found = true
				_round(staged, "Living troll outside square")
			if square.has(cell) and square.has(troll.position) and after.get("outcome") == "ongoing":
				inside_found = true
				_round(staged, "Living troll inside square")
			if inside_found and outside_found:
				break
		if inside_found and outside_found:
			break
	_check(outside_found, "Living troll outside marked square produces victory")
	_check(inside_found, "Living troll still inside marked square does not win")
	_test_troll_routes(square)
	var dead := state.duplicate(true)
	_entity(dead, troll_id).hp = 0
	var dead_round := _round(dead, "Dead troll")
	if not dead_round.is_empty():
		_check(dead_round.state.get("outcome") == "defeat", "Killing troll loses")
	var wiped := state.duplicate(true)
	for id in wiped.party:
		_entity(wiped, id).hp = 0
	var summon_cell := Vector2i(-1, -1)
	for y in range(wiped.height):
		for x in range(wiped.width):
			if Board.is_vacant(wiped, Vector2i(x, y)):
				summon_cell = Vector2i(x, y)
				break
		if summon_cell.x >= 0:
			break
	if summon_cell.x >= 0:
		wiped.units.append({"id": "test_skeleton", "character_id": "skeleton", "position": summon_cell,
			"hp": 1, "max_hp": 1, "statuses": {}, "summoner_id": "necromancer", "summon_priority": 0})
	var wipe_round := _round(wiped, "Wipe with living summon")
	if not wipe_round.is_empty():
		_check(wipe_round.state.get("outcome") == "defeat", "Living summon does not prevent selected party wipe")
		_check(_entity(wipe_round.state, "test_skeleton").get("hp", 0) > 0,
			"Wipe fixture actually retains a living summon")
	var pursuit := _round(state, "Troll pursuit")
	if not pursuit.is_empty():
		var positions := {}
		for unit in state.units:
			positions[unit.id] = unit.position
		for event in pursuit.events:
			var actor: String = event.get("unit_id", "")
			if event.get("type") == "move":
				if actor == troll_id:
					var from: Vector2i = positions[troll_id]
					var to: Vector2i = event.position
					var nearest := 99999
					for id in state.party:
						if _entity(state, id).hp > 0:
							nearest = mini(nearest, Board.distance(from, positions[id]))
					var after := 99999
					for id in state.party:
						if _entity(state, id).hp > 0 and Board.distance(from, positions[id]) == nearest:
							after = mini(after, Board.distance(to, positions[id]))
					_check(Board.distance(from, to) == 1 and after < nearest,
						"Troll moves exactly one step toward a nearest living hero")
				positions[actor] = event.position


func _test_troll_routes(square: Dictionary) -> void:
	# Both routes start from the unmodified authored mission.
	var push_state := _open("unwelcome_guest", ["healer", "knight", "bard"])
	var troll_id: String = _characters(push_state, "village_troll")[0].id
	var selected: Dictionary = rules.choose_manual(push_state, "knight", "knight_push", troll_id)
	var turn_state: Dictionary = rules.state_before_action(selected, "knight")
	_check(rules.preview(turn_state, "knight", "knight_push", troll_id).get("valid", false),
		"Knight's authored opening push is legal at its turn")
	var forecast: Dictionary = rules.preview_round(selected)
	var pushed := false
	for event in forecast.get("events", []):
		if event.get("type") == "push" and event.get("target_id") == troll_id \
				and not square.has(event.get("position")) \
				and forecast.get("result", {}).get("outcome") == "victory" \
				and _entity(forecast.result, troll_id).get("hp", 0) > 0:
			pushed = true
	_round(selected, "Push troll out")
	_check(pushed, "A legal Knight push can drive the living troll out and win")

	var lure_state := _open("unwelcome_guest", ["healer", "bard", "alchemist"])
	var lure_steps := [{"actor": "bard", "target": "4,2"}, {"actor": "healer", "target": "0,3"}]
	var lured := false
	for step in lure_steps:
		var chosen: Dictionary = rules.choose_manual(lure_state, step.actor, "move", step.target)
		var before_move: Dictionary = rules.state_before_action(chosen, step.actor)
		_check(rules.preview(before_move, step.actor, "move", step.target).get("valid", false),
			"Lure uses a legal direct Move by " + step.actor)
		var result := _round(chosen, "Lure by " + step.actor)
		if result.is_empty():
			break
		var positions := {}
		for unit in lure_state.units:
			positions[unit.id] = unit.position
		for event in result.events:
			_check(event.get("type") not in ["push", "pull", "repel", "swap"],
				"Lure route uses no displacement")
			if event.get("type") == "move":
				var actor: String = event.get("unit_id", "")
				if actor == troll_id:
					var from: Vector2i = positions[troll_id]
					var to: Vector2i = event.position
					var nearest := 99999
					for id in lure_state.party:
						if _entity(lure_state, id).hp > 0:
							nearest = mini(nearest, Board.distance(from, positions[id]))
					var approaches := false
					for id in lure_state.party:
						if _entity(lure_state, id).hp > 0 and Board.distance(from, positions[id]) == nearest \
								and Board.distance(to, positions[id]) < nearest:
							approaches = true
					_check(Board.distance(from, to) == 1 and approaches,
						"Lured troll takes one step toward a nearest living party hero")
					if not square.has(to) and result.state.get("outcome") == "victory" \
							and _entity(result.state, troll_id).get("hp", 0) > 0:
						lured = true
				positions[actor] = event.position
		lure_state = result.state
	_check(lured, "A hero can lure the living troll out by movement without displacement")
