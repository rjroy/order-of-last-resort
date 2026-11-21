extends RefCounted

const Catalog = preload("res://content/catalog.gd")
const Board = preload("res://rules/board.gd")
const EncounterRandom = preload("res://rules/encounter_random.gd")
const Statuses = preload("res://rules/statuses.gd")


static func owned_ability(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	if id not in Board.profile(state, actor).get("abilities", []):
		return {}
	return state.catalog.defs.abilities[id]


static func can_act(state: Dictionary, actor: Dictionary) -> bool:
	return Board.alive(actor) and Statuses.ids_with_handler(state, actor, "skip_action").is_empty()


static func accepts_target_argument(ability: Dictionary, target_id: String) -> bool:
	return target_id.is_empty() or ability.targeting.kind in ["cell", "entity"]


static func _can_move(state: Dictionary, actor: Dictionary) -> bool:
	return Board.capable(state, actor, "mobile") and Statuses.ids_with_handler(state, actor, "stop_move").is_empty()


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
		"repel":
			return candidate.has("character_id")
		"stop_target":
			return Statuses.accepts(state, candidate, ability.params.status, actor)
		"perform":
			if not candidate.has("character_id") \
					or Board.team(state, candidate) in ["", "civilian", Board.team(state, actor)]:
				return false
			return Statuses.accepts(state, candidate, ability.params.status, actor) if ability.params.has("status") \
				else Board.capable(state, candidate, "damageable")
	return false


static func summon_capped(state: Dictionary, actor: Dictionary, ability: Dictionary) -> bool:
	for unit in state.units:
		if unit.get("summoner_id") == actor.id and unit.character_id == ability.params.character \
				and Board.alive(unit):
			return true
	return false


static func _summon_choices(state: Dictionary, actor: Dictionary, ability: Dictionary) -> Array:
	var result: Array = []
	if actor.has("summoner_id") or Board.capable(state, actor, "minion") or summon_capped(state, actor, ability):
		return result
	if ability.targeting.kind == "cell":
		for direction in Board.DIRECTIONS:
			var position: Vector2i = actor.position + direction
			if Board.is_vacant(state, position):
				result.append({"id": Board.cell_id(position), "label": Board.coordinate(position), "position": position})
	else:
		var minion_name: String = Catalog.profile(state.catalog.defs, ability.params.character).label
		for corpse in raisable_corpses(state, actor, ability):
			if not Board.is_vacant(state, corpse.position):
				continue
			var hp := _raised_hp(corpse)
			result.append({"id": corpse.id,
				"label": "%s corpse (%d HP %s)" % [Board.display_name(state, corpse), hp, minion_name.to_lower()],
				"position": corpse.position})
	return result


static func raisable_corpses(state: Dictionary, actor: Dictionary, ability: Dictionary) -> Array:
	return Board.corpses(state, ability.targeting).filter(func(corpse: Dictionary) -> bool:
		return Board.team(state, corpse) not in ["", "civilian", Board.team(state, actor)] \
			and _in_reach(actor, corpse.position, ability.targeting))


@warning_ignore("integer_division")
static func _raised_hp(corpse: Dictionary) -> int:
	return (int(corpse.max_hp) + 1) / 2


# The picker, behaviors and action execution all use these exact choices.
static func _legal_choices(state: Dictionary, actor: Dictionary, ability: Dictionary) -> Array:
	var result: Array = []
	if ability.is_empty() or not can_act(state, actor):
		return result
	if ability.handler == "summon":
		return _summon_choices(state, actor, ability)
	var targeting: Dictionary = ability.targeting
	match targeting.kind:
		"cell":
			if not _can_move(state, actor):
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
			elif ability.handler == "sweep":
				for candidate in Board.occupants(state, {}):
					if _in_reach(actor, candidate.position, targeting) \
							and candidate.id != actor.id and Board.capable(state, candidate, "damageable"):
						result.append(candidate)
	return result


static func targets(state: Dictionary, actor: Dictionary, ability_id: String) -> Array:
	var ability := owned_ability(state, actor, ability_id)
	if ability.is_empty() or ability.targeting.kind not in ["cell", "entity"]:
		return []
	return _legal_choices(state, actor, ability)


static func selection(state: Dictionary, actor: Dictionary, ability: Dictionary, target_id: String) -> Dictionary:
	if ability.is_empty() or not accepts_target_argument(ability, target_id):
		return {}
	var choices := _legal_choices(state, actor, ability)
	if choices.is_empty():
		return {}
	if ability.handler == "sweep":
		return {"id": "", "recipients": choices}
	if ability.handler == "perform":
		var draw := EncounterRandom.uniform_draw(state.rng_state, choices.size())
		var choice: Dictionary = choices[draw.index]
		choice["rng_seed"] = draw.seed
		return choice
	if ability.targeting.kind == "automatic":
		for choice in choices:
			if choice.id == actor.id:
				return choice
		if ability.handler == "swap_furthest":
			choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var da := Board.distance(actor.position, a.position)
				var db := Board.distance(actor.position, b.position)
				return a.id < b.id if da == db else da > db)
			return choices[0]
		var nearest := Board.nearest(actor, choices)
		if ability.handler == "repel" and not nearest.is_empty():
			var destination := _step_away(state, actor, nearest)
			if destination == nearest.position:
				return {}
			nearest["destination"] = destination
		return nearest
	for choice in choices:
		if choice.id == target_id:
			return choice
	return {}


static func _step_away(state: Dictionary, actor: Dictionary, target: Dictionary) -> Vector2i:
	var position: Vector2i = target.position
	var destination := position - _pull_step(actor, target)
	return destination if Board.can_enter(state, destination) else position


static func _summon(state: Dictionary, actor: Dictionary, ability: Dictionary,
		choice: Dictionary, corpse: Dictionary, events: Array) -> void:
	var character: String = ability.params.character
	var profile := Catalog.profile(state.catalog.defs, character)
	var raising: bool = ability.targeting.kind == "entity"
	var hp := _raised_hp(corpse) if raising else int(profile.max_hp)
	var base_id := "%s_%s" % [actor.id, character]
	var id := base_id
	var index := 2
	while not Board.entity(state, id).is_empty():
		id = "%s_%d" % [base_id, index]
		index += 1
	var minion := {"id": id, "character_id": character, "position": choice.position,
		"hp": hp, "max_hp": hp, "statuses": {}, "summoner_id": actor.id,
		"summon_priority": int(ability.params.priority)}
	var data := {"unit_id": actor.id, "summon_id": id, "position": choice.position, "hp": hp}
	var copy := {"actor": Board.display_name(state, actor), "minion": profile.label,
		"position": choice.position, "hp": hp}
	if raising:
		corpse["corpse_consumed"] = true
		data["target_id"] = corpse.id
		copy["corpse"] = Board.display_name(state, corpse)
	state.units.append(minion)
	Board.authored_event(state, events, "summon", "raise" if raising else "summon", copy, data)


static func _perform(state: Dictionary, actor: Dictionary, ability: Dictionary, ability_id: String,
		choice: Dictionary, events: Array) -> bool:
	var name := Board.display_name(state, actor)
	var copy := {"actor": name, "ability": ability.label}
	var data := {"unit_id": actor.id, "ability_id": ability_id}
	if choice.is_empty():
		Board.authored_event(state, events, "performance", "performance_dry", copy, data)
		return true
	var listener := Board.entity(state, choice.id)
	data["target_id"] = listener.id
	data["target_label"] = choice.label
	copy["target"] = choice.label
	var params: Dictionary = ability.params
	if params.has("status"):
		if not Statuses.apply(state, listener, params.status, actor):
			return false
		data["status_id"] = params.status
		Board.authored_event(state, events, "performance", params.listener_event, copy, data)
	else:
		# A performance affects its listener directly; it isn't a redirectable attack.
		var amount := int(params.damage)
		_hurt(listener, amount)
		data.merge({"source_id": actor.id, "amount": amount})
		copy["amount"] = amount
		Board.authored_event(state, events, "damage", params.listener_event, copy, data)
	state.rng_state = choice.rng_seed
	return true


static func execute(state: Dictionary, actor: Dictionary, action: Dictionary, events: Array) -> bool:
	var ability := owned_ability(state, actor, action.ability_id)
	var target_id: String = action.get("target_id", "")
	if ability.is_empty() or not can_act(state, actor) or not accepts_target_argument(ability, target_id):
		return false
	var choice := selection(state, actor, ability, target_id)
	if ability.handler == "perform":
		return _perform(state, actor, ability, action.ability_id, choice, events)
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
		"summon":
			_summon(state, actor, ability, choice, target, events)
		"sweep":
			Board.authored_event(state, events, "wave", "sweep", {"actor": name}, {"unit_id": actor.id})
			for recipient in choice.recipients:
				_damage(state, actor, recipient, int(params.damage), name, "", events)
		"stop_target":
			if not Statuses.apply(state, target, params.status, actor):
				return false
			Board.authored_event(state, events, "status", "stop_target", {"actor": name, "target": target_name},
				{"unit_id": actor.id, "target_id": target.id, "status_id": params.status})
		"repel":
			target.position = choice.destination
			Board.authored_event(state, events, "repel", "repel",
				{"actor": name, "target": target_name, "position": target.position},
				{"unit_id": actor.id, "target_id": target.id, "position": target.position})
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


static func _hurt(target: Dictionary, amount: int) -> void:
	target.hp = maxi(0, target.hp - amount)


static func _damage(state: Dictionary, source: Dictionary, target: Dictionary, amount: int,
		source_name: String, status_id: String, events: Array) -> void:
	if not Board.alive(target) or not Board.capable(state, target, "damageable"):
		return
	_hurt(target, amount)
	var applied := not status_id.is_empty() and Statuses.apply(state, target, status_id, source)
	var handler = Statuses.definition(state, status_id).get("handler", "") if applied else ""
	var suffix := Board.text(state, "knockdown_suffix") if applied and Statuses.is_knockdown(state, status_id) else ""
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
