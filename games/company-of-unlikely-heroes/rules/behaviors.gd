extends RefCounted

const Actions = preload("res://rules/actions.gd")
const Board = preload("res://rules/board.gd")
const EncounterRandom = preload("res://rules/encounter_random.gd")
const Statuses = preload("res://rules/statuses.gd")


static func decide(state: Dictionary, actor: Dictionary, behavior_id: String) -> Dictionary:
	var behavior: Dictionary = state.catalog.defs.behaviors.get(behavior_id, {})
	var params: Dictionary = behavior.get("params", {})
	match behavior.get("handler", ""):
		"use_ability":
			return _action(params.ability)
		"pursue":
			var enemy := Board.nearest(actor, Board.occupants(state, {"teams": [params.team]}))
			if not enemy.is_empty():
				if _legal_target(state, actor, params.ability, enemy.id):
					return _action(params.ability, enemy.id)
				return _move(state, actor, params.move_ability, enemy.position, 1)
		"greet":
			return _greet(state, actor, params)
		"rescue":
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
			var enemies := Board.occupants(state, {"teams": [params.team]})
			enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
			var enemy := Board.nearest(actor, enemies)
			if not enemy.is_empty():
				var best: Vector2i = actor.position
				var best_distance := Board.distance(best, enemy.position)
				var best_alignment := -2147483647
				for direction in Board.DIRECTIONS:
					var position: Vector2i = actor.position + direction
					var distance := Board.distance(position, enemy.position)
					var away: Vector2i = actor.position - enemy.position
					var alignment: int = direction.x * away.x + direction.y * away.y
					if distance > Board.distance(actor.position, enemy.position) \
							and (distance > best_distance or (distance == best_distance and alignment > best_alignment)) \
							and Board.can_enter(state, position) \
							and _legal_target(state, actor, params.move_ability, Board.cell_id(position)):
						best = position
						best_distance = distance
						best_alignment = alignment
				if best != actor.position:
					return _action(params.move_ability, Board.cell_id(best))
			return {"wait": "hold"}
	return {}


static func _greet(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var enemy := Board.nearest(actor, Board.occupants(state, {"teams": [params.team]}))
	if enemy.is_empty():
		return {"wait": "hold"}
	var reach: int = params.greeting_range
	if Board.distance(actor.position, enemy.position) <= reach:
		var options := _greeting_options(state, actor, params.greetings)
		if not options.is_empty():
			state.rng_state = EncounterRandom.step(state.rng_state)
			return options[state.rng_state % options.size()]
	if Actions.targets(state, actor, params.move_ability).is_empty():
		return {"wait": "cannot_advance"}
	var start: Vector2i = actor.position
	var step := _step_to_greet(state, actor, enemy.position, reach, params.greetings)
	return _action(params.move_ability, Board.cell_id(step)) if step != start else {"wait": "cannot_advance"}


static func _greeting_options(state: Dictionary, actor: Dictionary, greetings: Array) -> Array:
	var options: Array = []
	for id in greetings:
		var ability := Actions.owned_ability(state, actor, id)
		if ability.targeting.kind == "entity":
			var target := Board.nearest(actor, Actions.targets(state, actor, id))
			if not target.is_empty():
				options.append(_action(id, target.id))
		elif not Actions.selection(state, actor, ability, "").is_empty():
			options.append(_action(id))
	return options


static func _step_to_greet(state: Dictionary, actor: Dictionary, opponent: Vector2i, reach: int,
		greetings: Array) -> Vector2i:
	# Project only this actor onto potential destinations. Reuse actual targeting policy
	# without advancing the RNG or modifying the running forecast.
	var projected := state.duplicate()
	var walker := actor.duplicate()
	projected.units = state.units.duplicate()
	projected.units[state.units.find(actor)] = walker
	return Board.step_to(state, actor.position, func(cell: Vector2i) -> bool:
		if cell == actor.position or Board.distance(cell, opponent) > reach:
			return false
		walker.position = cell
		return not _greeting_options(projected, walker, greetings).is_empty())


static func _threat(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var target := Statuses.retarget(state, actor, params.taunt_status)
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
	var ready := candidates.filter(func(target: Dictionary) -> bool:
		return _legal_target(state, actor, params.ability, target.id))
	var target := taunter if not taunter.is_empty() else Board.nearest(actor, ready)
	if not target.is_empty() and _legal_target(state, actor, params.ability, target.id):
		return _action(params.ability, target.id)
	# Without an escort there is no position to guard. Look for a route into firing range.
	var reach := int(Actions.owned_ability(state, actor, params.ability).get("targeting", {}).get("range", 1))
	if not taunter.is_empty():
		return _move(state, actor, params.move_ability, taunter.position, reach)
	var remaining := candidates.filter(func(candidate: Dictionary) -> bool: return candidate.id != actor.id)
	while not remaining.is_empty():
		target = Board.nearest(actor, remaining)
		var intent := _move(state, actor, params.move_ability, target.position, reach)
		if intent.has("ability_id"):
			return intent
		remaining.erase(target)
	return {"wait": "cannot_advance"}


static func _action(ability_id: String, target_id := "") -> Dictionary:
	return {"ability_id": ability_id, "target_id": target_id}


static func _legal_target(state: Dictionary, actor: Dictionary, ability_id: String, target_id: String) -> bool:
	var ability := Actions.owned_ability(state, actor, ability_id)
	return not Actions.selection(state, actor, ability, target_id).is_empty()


static func _move(state: Dictionary, actor: Dictionary, ability_id: String, goal: Vector2i, reach: int) -> Dictionary:
	if Board.capable(state, actor, "mobile") and not Actions.owned_ability(state, actor, ability_id).is_empty():
		var position := Board.step_toward(state, actor, goal, reach)
		var id := Board.cell_id(position)
		if position != actor.position and _legal_target(state, actor, ability_id, id):
			return _action(ability_id, id)
	return {"wait": "cannot_advance"}
