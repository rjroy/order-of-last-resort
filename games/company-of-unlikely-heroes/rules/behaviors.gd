extends RefCounted

const Actions = preload("res://rules/actions.gd")
const Board = preload("res://rules/board.gd")
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
				return _move(state, actor, params.move_ability, enemy.position, true)
		"rescue":
			var subject := Board.entity(state, state.objective.subject)
			if Board.alive(subject) and _legal_target(state, actor, params.ability, subject.id):
				var destination: Vector2i = state.objective.destination
				if Board.distance(actor.position, destination) < Board.distance(subject.position, destination):
					return _action(params.ability, subject.id)
		"threat":
			return _threat(state, actor, params)
		"escort":
			if actor.id == state.objective.subject:
				return _move(state, actor, params.move_ability, state.objective.destination, false)
	return {}


static func _threat(state: Dictionary, actor: Dictionary, params: Dictionary) -> Dictionary:
	var target := Statuses.retarget(state, actor, params.taunt_status)
	if not Board.alive(target):
		target = Board.entity(state, state.objective.subject)
	if not Board.alive(target) or target.id == actor.id:
		target = Board.nearest(actor, Board.occupants(state, {"teams": params.fallback_teams}))
	if target.is_empty():
		return {}
	if _legal_target(state, actor, params.ability, target.id):
		return _action(params.ability, target.id)
	if Board.distance(actor.position, target.position) <= int(params.pursue_range):
		return _move(state, actor, params.move_ability, target.position, true)
	return {"wait": "watches"}


static func _action(ability_id: String, target_id := "") -> Dictionary:
	return {"ability_id": ability_id, "target_id": target_id}


static func _legal_target(state: Dictionary, actor: Dictionary, ability_id: String, target_id: String) -> bool:
	var ability := Actions.owned_ability(state, actor, ability_id)
	return not Actions.selection(state, actor, ability, target_id).is_empty()


static func _move(state: Dictionary, actor: Dictionary, ability_id: String, goal: Vector2i, adjacent: bool) -> Dictionary:
	if Board.capable(state, actor, "mobile") and not Actions.owned_ability(state, actor, ability_id).is_empty():
		var position := Board.step_toward(state, actor, goal, adjacent)
		var id := Board.cell_id(position)
		if position != actor.position and _legal_target(state, actor, ability_id, id):
			return _action(ability_id, id)
	return {"wait": "cannot_advance"}
