extends RefCounted

const Board = preload("res://rules/board.gd")
const Statuses = preload("res://rules/statuses.gd")


static func owned_ability(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	if id not in Board.profile(state, actor).get("abilities", []):
		return {}
	return state.catalog.defs.abilities[id]


static func can_act(state: Dictionary, actor: Dictionary) -> bool:
	return Board.alive(actor) and Statuses.ids_with_handler(state, actor, "skip_action").is_empty()


static func _pull_step(actor: Dictionary, target: Dictionary) -> Vector2i:
	var delta: Vector2i = target.position - actor.position
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		return Vector2i(-signi(delta.x), 0)
	return Vector2i(0, -signi(delta.y))


static func _in_reach(actor: Dictionary, position: Vector2i, targeting: Dictionary) -> bool:
	var reach := Board.distance(actor.position, position)
	return not targeting.has("range") or (reach > 0 and reach <= int(targeting.range))


static func _entity_allowed(state: Dictionary, actor: Dictionary, candidate: Dictionary, ability: Dictionary) -> bool:
	if candidate.id == actor.id:
		return ability.handler == "heal" and ability.targeting.kind == "automatic" \
			and ability.params.get("prefer_wounded_self", false) == true \
			and actor.hp < actor.max_hp and Board.capable(state, actor, "healable")
	if not _in_reach(actor, candidate.position, ability.targeting):
		return false
	match ability.handler:
		"push":
			return actor.position != candidate.position and Board.capable(state, candidate, "pushable")
		"pull":
			return actor.position != candidate.position \
				and Board.capable(state, actor, "mobile") and Board.capable(state, candidate, "pullable") \
				and Board.can_enter(state, actor.position + _pull_step(actor, candidate)) \
				and Board.can_enter(state, actor.position, actor.id)
		"bonk", "blast", "attack":
			return Board.capable(state, candidate, "damageable")
		"heal":
			return Board.capable(state, candidate, "healable")
		"swap_furthest":
			return candidate.has("character_id")
		"misdirect":
			return Board.team(state, candidate) != Board.team(state, actor) \
				and not Statuses.adjacent_victim(state, candidate).is_empty() \
				and Statuses.accepts(state, candidate, ability.params.status, actor)
	return false


# The picker, behaviors and action execution all use these exact choices.
static func _legal_choices(state: Dictionary, actor: Dictionary, ability: Dictionary) -> Array:
	var result: Array = []
	if ability.is_empty() or not can_act(state, actor):
		return result
	var targeting: Dictionary = ability.targeting
	match targeting.kind:
		"cell":
			if ability.handler != "move" or not Board.capable(state, actor, "mobile"):
				return result
			for direction in Board.DIRECTIONS:
				var position: Vector2i = actor.position + direction
				if _in_reach(actor, position, targeting) and Board.can_enter(state, position):
					var id := Board.cell_id(position)
					result.append({"id": id, "label": Board.coordinate(position), "position": position})
		"entity", "automatic":
			for candidate in Board.occupants(state, targeting):
				if _entity_allowed(state, actor, candidate, ability):
					result.append({"id": candidate.id, "label": Board.display_name(state, candidate),
						"position": candidate.position})
		"none":
			if ability.handler == "apply_status" and Statuses.accepts(state, actor, ability.params.status, actor):
				result.append({"id": "", "position": actor.position})
	return result


static func targets(state: Dictionary, actor: Dictionary, ability_id: String) -> Array:
	var ability := owned_ability(state, actor, ability_id)
	if ability.is_empty() or ability.targeting.kind not in ["cell", "entity"]:
		return []
	return _legal_choices(state, actor, ability)


static func selection(state: Dictionary, actor: Dictionary, ability: Dictionary, target_id: String) -> Dictionary:
	var choices := _legal_choices(state, actor, ability)
	if choices.is_empty():
		return {}
	if ability.targeting.kind == "automatic":
		if not target_id.is_empty():
			return {}
		for choice in choices:
			if choice.id == actor.id:
				return choice
		if ability.handler == "swap_furthest":
			choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var da := Board.distance(actor.position, a.position)
				var db := Board.distance(actor.position, b.position)
				return a.id < b.id if da == db else da > db)
			return choices[0]
		return Board.nearest(actor, choices)
	for choice in choices:
		if choice.id == target_id:
			return choice
	return {}


static func execute(state: Dictionary, actor: Dictionary, action: Dictionary, events: Array) -> bool:
	var ability := owned_ability(state, actor, action.ability_id)
	var choice := selection(state, actor, ability, action.get("target_id", ""))
	if choice.is_empty():
		return false
	var target := Board.entity(state, choice.id)
	var params: Dictionary = ability.params
	var name := Board.display_name(state, actor)
	var target_name := Board.display_name(state, target) if not target.is_empty() else ""
	var first_event := events.size()
	match ability.handler:
		"move":
			actor.position = choice.position
			Board.authored_event(state, events, "move", "move", {"actor": name, "position": actor.position},
				{"unit_id": actor.id, "position": actor.position})
		"push":
			var destination: Vector2i = target.position - _pull_step(actor, target)
			if Board.can_enter(state, destination):
				target.position = destination
				Board.authored_event(state, events, "push", "push",
					{"actor": name, "target": target_name, "position": destination},
					{"unit_id": actor.id, "target_id": target.id, "position": destination})
			elif Board.capable(state, target, "damageable"):
				_damage(state, actor, Statuses.attack_recipient(state, target, events), int(params.collision_damage),
					name + Board.text(state, "collision_suffix"), "", events)
			else:
				Board.authored_event(state, events, "wait", "cannot_advance",
					{"actor": target_name}, {"unit_id": actor.id, "target_id": target.id})
		"apply_status":
			var id: String = params.status
			if not Statuses.apply(state, actor, id, actor):
				return false
			var status := Statuses.definition(state, id)
			var data := {"unit_id": actor.id, "target_id": actor.id, "source_id": actor.id, "status_id": id}
			if status.handler == "reflect":
				Board.authored_event(state, events, "aura", "aura",
					{"actor": name, "range": int(status.params.range)}, data)
			else:
				Board.authored_event(state, events, "status", "gain_status",
					{"actor": name, "status": status.label}, data)
		"bonk", "blast", "attack":
			var suffix: String = params.get("source_suffix", "")
			if ability.handler == "blast" and not params.has("source_suffix"):
				suffix = Board.text(state, "blast_suffix")
			target = Statuses.misdirect_attack(state, actor, target, events)
			_damage(state, actor, Statuses.attack_recipient(state, target, events), int(params.damage),
				name + suffix, params.get("status", ""), events)
		"swap_furthest":
			var old: Vector2i = actor.position
			actor.position = target.position
			target.position = old
			Board.authored_event(state, events, "swap", "swap",
				{"actor": name, "target": target_name, "position": actor.position},
				{"unit_id": actor.id, "target_id": target.id, "position": actor.position, "target_position": old})
		"misdirect":
			if not Statuses.apply(state, target, params.status, actor):
				return false
			var victim := Statuses.adjacent_victim(state, target)
			Board.authored_event(state, events, "misdirect", "misdirect_mark",
				{"actor": name, "target": target_name, "victim": Board.display_name(state, victim)},
				{"unit_id": actor.id, "target_id": target.id, "victim_id": victim.id, "status_id": params.status})
		"heal":
			var amount := mini(int(params.amount), target.max_hp - target.hp)
			target.hp += amount
			Board.authored_event(state, events, "heal", "heal" if amount > 0 else "heal_full",
				{"actor": name, "target": target_name, "amount": amount},
				{"unit_id": actor.id, "target_id": target.id, "amount": amount})
		"pull":
			var old: Vector2i = actor.position
			actor.position = old + _pull_step(actor, target)
			target.position = old
			Board.authored_event(state, events, "pull", "pull",
				{"actor": name, "target": target_name, "position": old, "recoil": actor.position},
				{"unit_id": actor.id, "target_id": target.id, "position": old, "recoil_position": actor.position})
			_damage(state, actor, actor, int(params.recoil_damage), Board.text(state, "recoil_source"), params.status, events)
		_:
			return false
	for index in range(first_event, events.size()):
		events[index]["ability_id"] = action.ability_id
	return true


static func _damage(state: Dictionary, source: Dictionary, target: Dictionary, amount: int,
		source_name: String, status_id: String, events: Array) -> void:
	if not Board.alive(target) or not Board.capable(state, target, "damageable"):
		return
	target.hp = maxi(0, target.hp - amount)
	var applied := not status_id.is_empty() and Statuses.apply(state, target, status_id, source)
	var handler = Statuses.definition(state, status_id).get("handler", "") if applied else ""
	var suffix := Board.text(state, "knockdown_suffix") if handler == "skip_action" else ""
	var target_name := Board.display_name(state, target)
	var data := {"source_id": source.id, "target_id": target.id, "amount": amount}
	if applied:
		data["status_id"] = status_id
	Board.authored_event(state, events, "damage", "damage",
		{"source": source_name, "amount": amount, "target": target_name, "effect": suffix}, data)
	if handler == "retarget":
		Board.authored_event(state, events, "taunt", "taunt",
			{"actor": Board.display_name(state, source), "target": target_name},
			{"source_id": source.id, "target_id": target.id, "status_id": status_id})
