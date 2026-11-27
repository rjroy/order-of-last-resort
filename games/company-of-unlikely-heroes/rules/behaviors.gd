extends RefCounted

const Actions = preload("res://rules/actions.gd")
const Board = preload("res://rules/board.gd")
const Catalog = preload("res://content/catalog.gd")
const EncounterRandom = preload("res://rules/encounter_random.gd")
const FittingState = preload("res://rules/fitting_state.gd")
const Fittings = preload("res://rules/fittings.gd")
const Frontier = preload("res://rules/frontier_combat.gd")
const Shield = preload("res://rules/shield.gd")
const ShieldWall = preload("res://rules/shield_wall.gd")
const Statuses = preload("res://rules/statuses.gd")
const Summons = preload("res://rules/summons.gd")
const Upgrades = preload("res://rules/upgrades.gd")


static func decide(state: Dictionary, actor: Dictionary, behavior_id: String) -> Dictionary:
	var behavior: Dictionary = state.catalog.defs.behaviors.get(behavior_id, {})
	var params: Dictionary = behavior.get("params", {})
	if params.has("ability"):
		params = params.duplicate()
		params.ability = Catalog.behavior_equipped_ability(state.catalog.defs,
			Board.profile(state, actor).get("abilities", []), behavior)
	match behavior.get("handler", ""):
		"use_ability":
			var blocked := Shield.blocked_reason(state, actor, params.ability)
			if not blocked.is_empty():
				return {"wait": "shield_away"} if blocked == "shield away" \
					else {"wait": "shield_wall", "wall_reason": blocked}
			var wall: bool = params.ability == params.get("wall_ability")
			var alternate := Actions.standing_alternate(state, actor, params.ability, "shield_wall" if wall else "")
			if not alternate.is_empty():
				return alternate
			if wall:
				var choices := Actions.targets(state, actor, params.ability)
				if not choices.is_empty():
					return _action(params.ability, choices[0].id)
				var reason := ShieldWall.blocked_reason(state, actor)
				return {"wait": "shield_wall", "wall_reason": "no open three-tile span" if reason.is_empty() else reason}
			return _action(params.ability)
		"fit_nearest":
			var heroes := Board.turn_order(state).filter(func(hero: Dictionary) -> bool:
				return Fittings.eligible(state, actor, hero))
			var nearest := Board.nearest(actor, heroes)
			if not nearest.is_empty() and _legal_target(state, actor, params.ability, nearest.id):
				return _action(params.ability, nearest.id)
			if not nearest.is_empty() and not FittingState.source(nearest).is_empty():
				return {"wait": "already_fitted", "target_id": nearest.id}
		"pursue":
			var ability_id: String = Board.profile(state, actor).get("equipped_slots", {}).get(
				params.get("ability_slot", ""), params.ability)
			if behavior_id == "advance" and actor.has("shield_position"):
				if Shield.can_retrieve(actor):
					return {"ability_id": params.move_ability, "retrieve_shield": true}
				return _move(state, actor, params.move_ability, actor.shield_position, 1)
			var alternate := Actions.standing_alternate(state, actor, ability_id, "pursue")
			if not alternate.is_empty():
				return alternate
			var heckler := Actions.heckler_target(state, actor, Actions.owned_ability(state, actor, ability_id))
			if not heckler.is_empty():
				return _action(ability_id, heckler.id)
			var enemy := Board.nearest(actor, Board.occupants(state, {"teams": [params.team]}))
			if not enemy.is_empty():
				if _legal_target(state, actor, ability_id, enemy.id):
					return _action(ability_id, enemy.id)
				var ability := Actions.owned_ability(state, actor, ability_id)
				var reach := int(ability.get("targeting", {}).get("range", 1))
				return _move(state, actor, params.move_ability, enemy.position, reach)
		"advance_move":
			if actor.has("shield_position"):
				if Shield.can_retrieve(actor):
					return {"ability_id": params.move_ability, "retrieve_shield": true}
				return _move(state, actor, params.move_ability, actor.shield_position, 1)
			var opponents := Board.occupants(state, {"teams": [params.team]}).filter(func(unit: Dictionary) -> bool:
				return Board.opponents(state, actor, unit))
			var enemy := Board.nearest(actor, opponents)
			if not enemy.is_empty():
				return _move(state, actor, params.move_ability, enemy.position, 1)
			return {"wait": "hold"}
		"greet":
			return _greet(state, actor, params)
		"hook_and_seek":
			return _hook_and_seek(state, actor, params)
		"follow_party":
			return _follow_party(state, actor, params.move_ability)
		"follow_ally":
			var allies := Board.occupants(state, {}).filter(func(unit: Dictionary) -> bool:
				return Board.allied(state, actor, unit))
			return _follow(state, actor, params.move_ability, allies, "follow_ally")
		"most_injured":
			var alternate := Actions.standing_alternate(state, actor, params.ability, "most_injured")
			if not alternate.is_empty():
				return alternate
			var split_heal := Actions.standing_split_heal(state, actor, params.ability)
			if not split_heal.is_empty():
				return split_heal
			return _most_injured(state, actor, params.ability)
		"pass_blame":
			var alternate := Actions.standing_alternate(state, actor, params.ability)
			if not alternate.is_empty():
				return alternate
			return _pass_blame(state, actor, params.ability)
		"make_friend", "personality_summon_skeleton":
			var alternate := Actions.standing_alternate(state, actor, params.ability, "make_friend")
			if not alternate.is_empty():
				return alternate
			return _make_friend(state, actor, params.ability)
		"personality_escape_swap":
			var alternate := Actions.standing_alternate(state, actor, params.ability)
			if not alternate.is_empty():
				return alternate
			return _escape_swap(state, actor, params.ability)
		"personality_raise_dead":
			var alternate := Actions.standing_alternate(state, actor, params.ability)
			if not alternate.is_empty():
				return alternate
			var corpse := Board.nearest(actor, Actions.targets(state, actor, params.ability))
			return _action(params.ability, corpse.id) if not corpse.is_empty() else {"wait": "hold"}
		"personality_targeted":
			return _personality_targeted(state, actor, params.ability, params.policy)
		"nearest_target":
			var alternate := Actions.standing_alternate(state, actor, params.ability, "nearest_target")
			if not alternate.is_empty():
				return alternate
			var target := Board.nearest(actor, Actions.targets(state, actor, params.ability), true)
			if not target.is_empty():
				return _action(params.ability, target.id)
		"rescue":
			var alternate := Actions.standing_alternate(state, actor, params.ability)
			if not alternate.is_empty():
				return alternate
			if state.objective.handler != "escort":
				return {}
			var subject := Board.entity(state, state.objective.subject)
			if Board.alive(subject) and _legal_target(state, actor, params.ability, subject.id):
				var destination: Vector2i = state.objective.destination
				if Board.distance(actor.position, destination) < Board.distance(subject.position, destination):
					return _action(params.ability, subject.id)
		"threat":
			return _threat(state, actor, params)
		"escort":
			if state.objective.handler == "escort" and actor.id == state.objective.subject:
				return _move(state, actor, params.move_ability, state.objective.destination, 0)
		"retreat":
			return _retreat(state, actor, params)
		"retreat_attack":
			return _retreat_attack(state, actor, params)
		"finite_healer":
			if Board.team(state, actor) == params.team and _legal_target(state, actor, params.heal_ability, ""):
				return _action(params.heal_ability)
			var targeting: Dictionary = Actions.owned_ability(state, actor, params.ability).get("targeting", {})
			var opponents := Board.occupants(state, targeting).filter(func(unit: Dictionary) -> bool:
				return Board.opponents(state, actor, unit))
			return _frontier_engage(state, actor, params, opponents)
		"swap_ally":
			return _swap_or_attack(state, actor, params)
	return {}


static func _retreat_attack(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var enemies := Board.occupants(state, {"teams": [params.team]})
	var enemy := Board.nearest(actor, enemies)
	if enemy.is_empty():
		return {"wait": "hold"}
	if Board.distance(actor.position, enemy.position) == 1 \
			and state.round > int(actor.get("last_retreat_round", -1)) + 1:
		var best_distance := 1
		var best: Dictionary = {}
		for choice in Actions.targets(state, actor, params.move_ability):
			var threat := Board.nearest({"id": actor.id, "position": choice.position}, enemies)
			var distance := Board.distance(choice.position, threat.position)
			if distance > best_distance:
				best_distance = distance
				best = choice
		if not best.is_empty():
			var action := _action(params.move_ability, best.id)
			action["tactical_retreat"] = true
			return action
	return _frontier_engage(state, actor, params, enemies)


static func _swap_or_attack(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var enemies := Board.occupants(state, {"teams": [params.team]})
	var nearest := Board.nearest(actor, enemies)
	if nearest.is_empty():
		return {"wait": "hold"}
	var choice := Actions.selection(state, actor, params.swap_ability, "")
	var ally := Board.entity(state, choice.id) if not choice.is_empty() else {}
	if ally.get("character_id") == params.ally:
		var ally_threat := Board.nearest(ally, enemies)
		if Board.distance(actor.position, nearest.position) < Board.distance(ally.position, ally_threat.position):
			return _action(params.swap_ability)
	return _frontier_engage(state, actor, params, enemies)


static func _frontier_engage(state: Dictionary, actor: Dictionary, params: Dictionary,
		candidates: Array) -> Dictionary:
	var heckler := Actions.heckler_target(state, actor, Actions.owned_ability(state, actor, params.ability))
	if not heckler.is_empty():
		return _action(params.ability, heckler.id)
	return _engage(state, actor, params, Statuses.retarget(state, actor, "taunt"), candidates)


static func _retreat(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var enemies := Board.occupants(state, {"teams": [params.team]})
	if enemies.is_empty() or not Actions.can_move(state, actor):
		return {"wait": "hold"}
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var origin: Vector2i = actor.position
	var first := _retreat_step(state, actor, params.move_ability, enemies, origin, false)
	if first == origin:
		return {"wait": "hold"}
	var intent := _action(params.move_ability, Board.cell_id(first))
	if Upgrades.amount(state, actor, "exit_strategy") > 0:
		var second := _retreat_step(state, actor, params.move_ability, enemies, first, true)
		if second != first:
			intent["retreat_second"] = second
	return intent


static func _retreat_step(state: Dictionary, actor: Dictionary, move_ability: String, enemies: Array,
		start: Vector2i, second: bool) -> Vector2i:
	var from := {"id": actor.id, "position": start}
	var enemy := Board.nearest(from, enemies)
	if enemy.is_empty():
		return start
	var best := start
	var best_distance := Board.distance(start, enemy.position)
	var best_alignment := -2147483647
	for direction in Board.DIRECTIONS:
		var position: Vector2i = start + direction
		var threat := Board.nearest({"id": actor.id, "position": position}, enemies) if second else enemy
		var distance := Board.distance(position, threat.position)
		var away: Vector2i = start - enemy.position
		var alignment: int = direction.x * away.x + direction.y * away.y
		if distance > Board.distance(start, enemy.position) \
				and (distance > best_distance or (distance == best_distance and alignment > best_alignment)) \
				and Board.can_enter(state, position, actor.id) \
				and (second or _legal_target(state, actor, move_ability, Board.cell_id(position))):
			best = position
			best_distance = distance
			best_alignment = alignment
	return best


static func _hook_and_seek(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var target := Statuses.retarget(state, actor, params.taunt_status)
	if not target.is_empty():
		if _legal_target(state, actor, params.ability, target.id):
			return _action(params.ability, target.id)
		return _move(state, actor, params.move_ability, target.position, 1)
	target = Board.nearest(actor, Actions.targets(state, actor, params.ability))
	if not target.is_empty():
		return _action(params.ability, target.id)
	target = Board.nearest(actor, Board.occupants(state, {"teams": [params.team]}))
	if not target.is_empty():
		return _move(state, actor, params.move_ability, target.position, 1)
	return {"wait": "hold"}


static func _follow_party(state: Dictionary, actor: Dictionary, move_ability: String) -> Dictionary:
	var heroes := Board.occupants(state, {"teams": ["heroes"], "capabilities": ["commandable"]})
	var party: Array = state.get("party", [])
	heroes = heroes.filter(func(hero: Dictionary) -> bool:
		return not Board.capable(state, hero, "minion") and (party.is_empty() or hero.id in party))
	return _follow(state, actor, move_ability, heroes, "follow_party")


static func _follow(state: Dictionary, actor: Dictionary, move_ability: String,
		allies: Array, template: String) -> Dictionary:
	var target := Board.nearest(actor, allies)
	if target.is_empty() or Board.distance(actor.position, target.position) <= 1:
		return {"wait": "hold"}
	var action := _move(state, actor, move_ability, target.position, 1)
	if action.has("ability_id"):
		action["follow_target_id"] = target.id
		action["follow_event"] = template
	return action


static func _most_injured(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var recipient := ""
	var most_missing := 0
	var ability := Actions.owned_ability(state, actor, id)
	var aimed: bool = ability.get("targeting", {}).get("kind") == "automatic"
	for choice in Actions.targets(state, actor, id, aimed):
		var candidate := Board.entity(state, choice.id)
		var missing: int = candidate.max_hp - candidate.hp
		if missing > most_missing:
			most_missing = missing
			recipient = candidate.id
	if recipient.is_empty():
		return {"wait": "hold"}
	if aimed:
		return {"ability_id": id, "target_id": recipient, "direct": true}
	return _action(id, recipient)


static func _pass_blame(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var legal := {}
	for choice in Actions.targets(state, actor, id):
		legal[choice.id] = true
	var candidates := Board.turn_order(state).filter(func(target: Dictionary) -> bool:
		return legal.has(target.id) and Board.opponents(state, actor, target) \
			and Statuses.ids_with_handler(state, target, "misdirect").is_empty())
	var target := Board.nearest(actor, candidates)
	return _action(id, target.id) if not target.is_empty() else {"wait": "hold"}


static func _make_friend(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	# The summon picker already enforces the per-summoner cap and returns cells in board-direction order.
	var choices := Actions.targets(state, actor, id)
	if choices.is_empty():
		return {"wait": "hold"}
	var opponents := Board.occupants(state, {}).filter(func(unit: Dictionary) -> bool:
		return Board.opponents(state, actor, unit))
	if opponents.is_empty():
		return {"wait": "hold"}
	var cell := ""
	var best_distance := 2147483647
	for choice in choices:
		var opponent := Board.nearest(choice, opponents, true)
		var distance := Board.distance(choice.position, opponent.position)
		if distance < best_distance:
			cell = choice.id
			best_distance = distance
	return _action(id, cell)


static func _escape_swap(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var opponents := Board.occupants(state, {}).filter(func(unit: Dictionary) -> bool:
		return Board.opponents(state, actor, unit))
	if opponents.is_empty():
		return {"wait": "hold"}
	var origin: Vector2i = actor.position
	var danger := _nearest_foe_distance(origin, opponents)
	var partner_id := ""
	var longest := -1
	for choice: Dictionary in Actions.escape_swap_partners(state, actor, id):
		var reach := Board.distance(origin, choice.position)
		if reach < longest or (reach == longest and choice.id >= partner_id):
			continue
		# A swapped enemy threatens from the Dodger's old cell, not its current cell.
		if _nearest_foe_distance(choice.position, opponents, choice.id, origin) > danger:
			partner_id = choice.id
			longest = reach
	if partner_id.is_empty():
		return {"wait": "hold"}
	return {"ability_id": id, "automatic_target_id": partner_id}


static func _nearest_foe_distance(position: Vector2i, opponents: Array,
		swapped_id := "", displaced_to := Vector2i.ZERO) -> int:
	var nearest := 2147483647
	for opponent: Dictionary in opponents:
		var foe_position: Vector2i = displaced_to if opponent.id == swapped_id else opponent.position
		nearest = mini(nearest, Board.distance(position, foe_position))
	return nearest


static func _personality_targeted(state: Dictionary, actor: Dictionary, id: String, policy: String) -> Dictionary:
	# A fitting can invert a move's purpose. Its own candidates, not the base
	# order's allegiance filter, govern the fitted move.
	var alternate := Actions.standing_alternate(state, actor, id, "nearest_target")
	if not alternate.is_empty():
		return alternate
	var choices := Actions.targets(state, actor, id).filter(func(choice: Dictionary) -> bool:
		var unit := Board.entity(state, choice.id)
		if policy == "nearest_ally":
			return Board.allied(state, actor, unit)
		if policy == "nearest_enemy":
			return Board.opponents(state, actor, unit)
		return policy == "nearest_character" and unit.has("character_id"))
	var target := Board.nearest(actor, choices, true)
	return _action(id, target.id) if not target.is_empty() else {"wait": "hold"}


static func _greet(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var enemy := Summons.nominated_target(state, actor)
	var opponents: Array = []
	if not enemy.is_empty() and not Board.opponents(state, actor, enemy):
		enemy = {}
	if not enemy.is_empty():
		opponents = [enemy]
	else:
		opponents = Board.occupants(state, {"teams": [params.team]}).filter(func(unit: Dictionary) -> bool:
			return Board.opponents(state, actor, unit))
		enemy = Board.nearest(actor, opponents)
	var reach: int = params.greeting_range
	var options: Array = []
	var best_distance := 2147483647
	for opponent in opponents:
		var distance := Board.distance(actor.position, opponent.position)
		if distance >= best_distance:
			continue
		var candidate_options := _greeting_options(state, actor, opponent, reach, params.greetings)
		if not candidate_options.is_empty():
			options = candidate_options
			best_distance = distance
	if not options.is_empty():
		state.rng_state = EncounterRandom.step(state.rng_state)
		return options[state.rng_state % options.size()]
	if actor.get("stationary", false):
		return {"wait": "hold"}
	var rally := Summons.rally_target(state, actor)
	if not rally.is_empty():
		return _move(state, actor, params.move_ability, rally.position, 1)
	if enemy.is_empty():
		return {"wait": "hold"}
	if Actions.targets(state, actor, params.move_ability).is_empty():
		return {"wait": "cannot_advance"}
	var start: Vector2i = actor.position
	var step := _step_to_greet(state, actor, enemy, reach, params.greetings)
	return _action(params.move_ability, Board.cell_id(step)) if step != start else {"wait": "cannot_advance"}


static func _greeting_options(state: Dictionary, actor: Dictionary, opponent: Dictionary,
		reach: int, greetings: Array) -> Array:
	var options: Array = []
	var distance := Board.distance(actor.position, opponent.position)
	for id in greetings:
		var form := Actions.action_form(state, actor, id)
		var ability: Dictionary = form.alternate if form.converted else form.base
		if distance > reach:
			# Only the upgraded greeting can go beyond the usual pursuit radius.
			if ability.get("handler") == "sweep" and Actions.extra_sweep_reaches(state, actor, opponent, id):
				options.append(_action(id))
			elif id == "offer_flower" and distance <= int(ability.get("targeting", {}).get("range", reach)) \
					and Upgrades.amount(state, Summons.owner(state, actor), "long_stemmed") > 0:
				for choice in Actions.targets(state, actor, id):
					if choice.id == opponent.id:
						options.append(_action(id, choice.id))
						break
			continue
		if ability.targeting.kind == "entity":
			if not Actions.selection(state, actor, id, opponent.id, "", form).is_empty():
				options.append(_action(id, opponent.id))
		elif ability.targeting.kind == "automatic":
			if not Actions.selection(state, actor, id, "", opponent.id, form).is_empty():
				options.append({"ability_id": id, "automatic_target_id": opponent.id})
		else:
			var selected := Actions.selection(state, actor, id, "", "", form)
			if ability.get("handler") == "sweep":
				if selected.get("recipients", []).any(func(recipient: Dictionary) -> bool:
						return recipient.id == opponent.id):
					options.append(_action(id))
			elif not selected.is_empty():
				options.append(_action(id))
	return options


static func _step_to_greet(state: Dictionary, actor: Dictionary, opponent: Dictionary, reach: int,
		greetings: Array) -> Vector2i:
	# Project only this actor onto potential destinations. Reuse actual targeting policy
	# without advancing the RNG or modifying the running forecast.
	var projected := state.duplicate()
	var walker := actor.duplicate()
	projected.units = state.units.duplicate()
	projected.units[state.units.find(actor)] = walker
	return Board.step_to(state, actor.position, func(cell: Vector2i) -> bool:
		if cell == actor.position:
			return false
		walker.position = cell
		return not _greeting_options(projected, walker, opponent, reach, greetings).is_empty())


static func _threat(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var heckler := Actions.heckler_target(state, actor, Actions.owned_ability(state, actor, params.ability))
	if not heckler.is_empty():
		return _action(params.ability, heckler.id)
	var target := Statuses.retarget(state, actor, params.taunt_status)
	if not Frontier.traits(state, actor, "last_damager_pursuit").is_empty():
		var damager := Board.entity(state, actor.get("last_damager_id", ""))
		if Board.alive(damager) and damager.id != actor.id:
			target = damager
	var candidates := Board.occupants(state, {"teams": params.fallback_teams})
	if state.objective.handler != "escort":
		return _engage(state, actor, params, target, candidates)
	if not Board.alive(target):
		target = Board.entity(state, state.objective.subject)
	if not Board.alive(target) or target.id == actor.id:
		target = Board.nearest(actor, candidates)
	if target.is_empty():
		return {}
	if _legal_target(state, actor, params.ability, target.id):
		return _action(params.ability, target.id)
	if Board.distance(actor.position, target.position) <= int(params.pursue_range):
		return _move(state, actor, params.move_ability, target.position, 1)
	return {"wait": "watches"}


static func _engage(state: Dictionary, actor: Dictionary, params: Dictionary, taunter: Dictionary,
		candidates: Array) -> Dictionary:
	var ability_id: String = params.ability
	var form := Actions.action_form(state, actor, ability_id)
	if not taunter.is_empty():
		if not Actions.selection(state, actor, ability_id, taunter.id, "", form).is_empty():
			return _action(ability_id, taunter.id)
	else:
		var ready := candidates.filter(func(target: Dictionary) -> bool:
			return not Actions.selection(state, actor, ability_id, target.id, "", form).is_empty())
		var nearest := Board.nearest(actor, ready)
		if not nearest.is_empty():
			return _action(ability_id, nearest.id)
	# Without an escort there is no position to guard. Look for a route into firing range.
	var targeting: Dictionary = form.base.get("targeting", {})
	if targeting.has("min_range") or targeting.get("straight_line_clear", false):
		var targets := [taunter] if not taunter.is_empty() else candidates
		return _move_to_firing_position(state, actor, params.move_ability, ability_id, targets)
	var reach := int(form.base.get("targeting", {}).get("range", 1))
	if not taunter.is_empty():
		return _move(state, actor, params.move_ability, taunter.position, reach)
	var remaining := candidates.filter(func(candidate: Dictionary) -> bool: return candidate.id != actor.id)
	while not remaining.is_empty():
		var target := Board.nearest(actor, remaining)
		var intent := _move(state, actor, params.move_ability, target.position, reach)
		if intent.has("ability_id"):
			return intent
		remaining.erase(target)
	return {"wait": "cannot_advance"}


static func _move_to_firing_position(state: Dictionary, actor: Dictionary, move_id: String,
		ability_id: String, candidates: Array) -> Dictionary:
	if not Actions.can_move(state, actor) or Actions.owned_ability(state, actor, move_id).is_empty():
		return {"wait": "cannot_advance"}
	# Project this actor without modifying the live forecast or its shared catalog.
	var projected := state.duplicate()
	var walker := actor.duplicate()
	projected.units = state.units.duplicate()
	projected.units[state.units.find(actor)] = walker
	var step := Board.step_to(state, actor.position, func(cell: Vector2i) -> bool:
		if cell == actor.position:
			return false
		walker.position = cell
		for candidate in candidates:
			if candidate.id != actor.id and _legal_target(projected, walker, ability_id, candidate.id):
				return true
		return false)
	var target_id := Board.cell_id(step)
	if step != actor.position and _legal_target(state, actor, move_id, target_id):
		return _action(move_id, target_id)
	return {"wait": "cannot_advance"}


static func _action(ability_id: String, target_id := "") -> Dictionary:
	return {"ability_id": ability_id, "target_id": target_id}


static func _legal_target(state: Dictionary, actor: Dictionary, ability_id: String, target_id: String) -> bool:
	return not Actions.selection(state, actor, ability_id, target_id).is_empty()


static func _move(state: Dictionary, actor: Dictionary, ability_id: String, goal: Vector2i, reach: int) -> Dictionary:
	if Actions.can_move(state, actor) and not Actions.owned_ability(state, actor, ability_id).is_empty():
		var position := Board.step_toward(state, actor, goal, reach)
		if position == actor.position:
			return {"wait": "cannot_advance"}
		var extra := Frontier.ally_death_bonus(state, actor, "movement")
		if extra > 0:
			position = _continue_move(state, actor, position, goal, reach, extra)
		var target_id := Board.cell_id(position)
		if _legal_target(state, actor, ability_id, target_id):
			return _action(ability_id, target_id)
	return {"wait": "cannot_advance"}


static func _continue_move(state: Dictionary, actor: Dictionary, first: Vector2i,
		goal: Vector2i, reach: int, extra: int) -> Vector2i:
	# Project the actor only. The route uses the same deterministic search
	# each step, and must stay legal under Actions' move selection.
	var projected := state.duplicate()
	var walker := actor.duplicate()
	projected.units = state.units.duplicate()
	projected.units[state.units.find(actor)] = walker
	walker.position = first
	for index in range(extra):
		var step := Board.step_toward(projected, walker, goal, reach)
		if step == walker.position:
			break
		walker.position = step
	return walker.position
