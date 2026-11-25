extends RefCounted

const Alchemy = preload("res://rules/alchemy.gd")
const Board = preload("res://rules/board.gd")
const Combat = preload("res://rules/combat.gd")
const EncounterRandom = preload("res://rules/encounter_random.gd")
const FittingState = preload("res://rules/fitting_state.gd")
const Fittings = preload("res://rules/fittings.gd")
const Frontier = preload("res://rules/frontier_combat.gd")
const Movement = preload("res://rules/movement.gd")
const Performances = preload("res://rules/performances.gd")
const Shield = preload("res://rules/shield.gd")
const Statuses = preload("res://rules/statuses.gd")
const Summons = preload("res://rules/summons.gd")
const Support = preload("res://rules/support.gd")
const Upgrades = preload("res://rules/upgrades.gd")
const BASE_SONGS := ["inspiring_melody", "healing_sonnet"]


static func owned_ability(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var abilities: Array = Board.profile(state, actor).get("abilities", [])
	if id == Fittings.QUICK_RELEASE:
		return Upgrades.ability(state, actor, id) if "move" in abilities and Fittings.can_release(state, actor) else {}
	if id not in abilities:
		return {}
	return Upgrades.ability(state, actor, id)


static func can_act(state: Dictionary, actor: Dictionary) -> bool:
	return Board.alive(actor) and not Statuses.has_skip(state, actor)


static func accepts_target_argument(ability: Dictionary, target_id: String) -> bool:
	return target_id.is_empty() or ability.targeting.kind in ["cell", "entity"]


static func can_move(state: Dictionary, actor: Dictionary) -> bool:
	return Board.capable(state, actor, "mobile") and Statuses.ids_with_handler(state, actor, "stop_move").is_empty()


static func _pull_step(actor: Dictionary, target: Dictionary) -> Vector2i:
	return Combat.toward(target.position, actor.position)


static func _digs_in(state: Dictionary, actor: Dictionary, target: Dictionary) -> bool:
	return Board.opponents(state, target, actor) and Statuses.guarding(state, target) \
		and Upgrades.amount(state, target, "dig_in") > 0


static func _in_reach(actor: Dictionary, position: Vector2i, targeting: Dictionary) -> bool:
	var reach := Board.distance(actor.position, position)
	return not targeting.has("range") or (reach > 0 and reach <= int(targeting.range))


static func _entity_allowed(state: Dictionary, actor: Dictionary, candidate: Dictionary, ability: Dictionary) -> bool:
	if ability.handler in ["healing_potion", "acid", "plain_tonic"]:
		return Alchemy.can_target(state, actor, candidate, ability)
	if ability.params.get("opponents_only", false) and not Board.opponents(state, actor, candidate):
		return false
	if candidate.id == actor.id:
		return ability.handler == "heal" and Board.capable(state, actor, "healable") \
			and ((ability.targeting.kind == "entity" and ability.params.get("allow_self", false)) \
				or (ability.targeting.kind == "automatic" and ability.params.get("prefer_wounded_self", false) \
					and actor.hp < actor.max_hp))
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
		"hook":
			return Board.distance(actor.position, candidate.position) > 1 \
				and Board.capable(state, candidate, "pullable") \
				and (not ability.params.get("allied_only", false) \
					or (candidate.has("character_id") and Board.allied(state, actor, candidate))) \
				and Board.is_vacant(state, candidate.position + _pull_step(actor, candidate))
		"bonk", "blast", "attack":
			return Board.capable(state, candidate, "damageable")
		"heal":
			return Board.capable(state, candidate, "healable") \
				and (ability.targeting.kind != "entity" or Board.allied(state, actor, candidate))
		"enemy_heal":
			return candidate.has("character_id") and candidate.hp < candidate.max_hp \
				and Board.team(state, candidate) == Board.team(state, actor)
		"swap_ally":
			return candidate.get("character_id") == ability.params.character \
				and Board.team(state, candidate) == Board.team(state, actor) \
				and actor.position != candidate.position \
				and Board.distance(actor.position, candidate.position) <= int(ability.params.range) \
				and Board.can_enter(state, candidate.position, candidate.id) \
				and Board.can_enter(state, actor.position, actor.id)
		"swap_furthest":
			return candidate.has("character_id")
		"misdirect":
			return Board.team(state, candidate) != Board.team(state, actor) \
				and not Statuses.misdirection_victim(state, candidate, actor).is_empty() \
				and Statuses.accepts(state, candidate, ability.params.status, actor)
		"nominate":
			return Board.opponents(state, actor, candidate)
		"fit":
			return Fittings.eligible(state, actor, candidate) and FittingState.source(candidate).is_empty()
		"repel":
			return candidate.has("character_id")
		"stop_target":
			return (not ability.params.get("hostile_only", false) or Board.hostile(state, actor, candidate)) \
				and Statuses.accepts(state, candidate, ability.params.status, actor)
		"perform":
			if not Board.opponents(state, actor, candidate):
				return false
			return Statuses.accepts(state, candidate, ability.params.status, actor) if ability.params.has("status") \
				else Board.capable(state, candidate, "damageable")
	return false


static func summon_capped(state: Dictionary, actor: Dictionary, ability: Dictionary) -> bool:
	return Summons.capped(state, actor, ability.params.character)


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
		var minion_name: String = Board.profile(state, {"character_id": ability.params.character}).label
		for corpse in raisable_corpses(state, actor, ability):
			if not Board.is_vacant(state, corpse.position):
				continue
			var hp := Summons.starting_hp(state, actor, ability.params.character, corpse)
			result.append({"id": corpse.id,
				"label": "%s corpse (%d HP %s)" % [Board.display_name(state, corpse), hp, minion_name.to_lower()],
				"position": corpse.position})
	return result


static func raisable_corpses(state: Dictionary, actor: Dictionary, ability: Dictionary) -> Array:
	return Board.corpses(state, ability.targeting).filter(func(corpse: Dictionary) -> bool:
		return Board.team(state, corpse) not in ["", "civilian", Board.team(state, actor)] \
			and _in_reach(actor, corpse.position, ability.targeting))


static func _use_limit(ability: Dictionary) -> int:
	match ability.handler:
		"swap_ally":
			return 1
		"enemy_heal":
			return int(ability.params.charges)
	return -1


static func _uses(actor: Dictionary, ability_id: String) -> int:
	return actor.get("ability_uses", {}).get(ability_id, 0)


# The picker, behaviors and action execution all use these exact choices.
static func _legal_choices(state: Dictionary, actor: Dictionary, ability: Dictionary, ability_id: String) -> Array:
	var result: Array = []
	if ability.is_empty() or not can_act(state, actor):
		return result
	var limit := _use_limit(ability)
	if limit >= 0 and _uses(actor, ability_id) >= limit:
		return result
	if ability.handler == "summon":
		return _summon_choices(state, actor, ability)
	var target_ability := ability
	var prior_recipient := ""
	if ability.handler == "repeat_batch":
		target_ability = Alchemy.bottled_recipe(state, actor)
		if target_ability.is_empty():
			return result
		prior_recipient = actor.bottled_reaction.recipient
	var targeting: Dictionary = target_ability.targeting
	match targeting.kind:
		"cell":
			if not can_move(state, actor):
				return result
			if ability.handler == "quick_release" and (ability_id != Fittings.QUICK_RELEASE \
					or Movement.voluntary_blocked(state, actor)):
				return result
			if ability.handler == "move" and int(targeting.get("range", 1)) > 0:
				var extra := Frontier.ally_death_bonus(state, actor, "movement")
				if extra > 0:
					return _move_routes(state, actor, 1 + extra)
			for direction in Board.DIRECTIONS:
				var position: Vector2i = actor.position + direction
				if _in_reach(actor, position, targeting) and Board.can_enter(state, position):
					var id := Board.cell_id(position)
					result.append({"id": id, "label": Board.coordinate(position), "position": position})
		"entity", "automatic":
			for candidate in Board.occupants(state, targeting):
				if candidate.id != prior_recipient and _entity_allowed(state, actor, candidate, target_ability):
					var choice := {"id": candidate.id, "label": Board.display_name(state, candidate),
						"position": candidate.position}
					if ability.handler == "hook" and not _digs_in(state, actor, candidate):
						choice["destination"] = candidate.position + _pull_step(actor, candidate)
					result.append(choice)
		"none":
			if ability.handler == "apply_status" and Statuses.accepts(state, actor, ability.params.status, actor):
				result.append({"id": "", "position": actor.position})
			elif ability.handler == "sweep":
				for candidate in Board.occupants(state, {}):
					if candidate.id != actor.id and Board.capable(state, candidate, "damageable") \
							and (_in_reach(actor, candidate.position, targeting) \
								or extra_sweep_reaches(state, actor, candidate, ability_id)):
						result.append(candidate)
	return result


# Each destination has a deterministic shortest route; execution walks all
# intermediate cells instead of jumping over obstacles or occupants.
static func _move_routes(state: Dictionary, actor: Dictionary, steps: int) -> Array:
	var origin: Vector2i = actor.position
	var queue: Array[Vector2i] = [origin]
	var routes := {origin: []}
	var choices: Array = []
	var index := 0
	while index < queue.size():
		var position := queue[index]
		var prefix: Array = routes[position]
		index += 1
		if prefix.size() >= steps:
			continue
		for direction in Board.DIRECTIONS:
			var next: Vector2i = position + direction
			if routes.has(next) or not Board.can_enter(state, next):
				continue
			var route := prefix + [next]
			routes[next] = route
			queue.append(next)
			choices.append({"id": Board.cell_id(next), "label": Board.coordinate(next),
				"position": next, "route": route})
	return choices


static func extra_sweep_reaches(state: Dictionary, actor: Dictionary, candidate: Dictionary, id: String) -> bool:
	var delta: Vector2i = candidate.position - actor.position
	return id == "wave" and absi(delta.x) == 1 and absi(delta.y) == 1 \
		and Board.capable(state, candidate, "damageable") \
		and Upgrades.amount(state, Summons.owner(state, actor), "broad_wave") > 0


## Resolve the form at the actor's slot, before selecting any manual or standing target.
static func action_form(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var base := owned_ability(state, actor, id)
	var alternate := Fittings.alternate(state, actor, base) if base.has("fitted_form") and can_act(state, actor) else {}
	return {"base": base, "alternate": alternate, "converted": not alternate.get("choices", []).is_empty()}


static func command_ability(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var form := action_form(state, actor, id)
	var alternate: Dictionary = form.alternate
	if form.converted:
		return alternate.merged({"label": "%s → %s" % [form.base.label, alternate.label]}, true)
	if not alternate.is_empty():
		var reason: String = alternate.unavailable_reason
		var blocked := reason == "shield away"
		var label := " (shield away; Fitted stays)" if blocked else " (ordinary; Fitted stays)"
		return form.base.merged({"label": form.base.label + label, "command_blocked": blocked,
			"help": "%s unavailable: %s. %s" % [alternate.label, reason, form.base.help]}, true)
	return form.base


static func standing_alternate(state: Dictionary, actor: Dictionary, id: String, prefer_opponents := false) -> Dictionary:
	if FittingState.source(actor).is_empty():
		return {}
	var form := action_form(state, actor, id)
	if not form.converted:
		return {}
	var alternate: Dictionary = form.alternate
	if alternate.targeting.kind == "none":
		return {"ability_id": id, "target_id": ""}
	var choices: Array = alternate.choices
	if prefer_opponents:
		var opponents := choices.filter(func(choice: Dictionary) -> bool:
			return Board.opponents(state, actor, Board.entity(state, choice.id)))
		if not opponents.is_empty():
			choices = opponents
	return {"ability_id": id, "target_id": Board.nearest(actor, choices, true).id}


static func targets(state: Dictionary, actor: Dictionary, ability_id: String) -> Array:
	var form := action_form(state, actor, ability_id)
	if form.converted:
		return form.alternate.choices if form.alternate.targeting.kind in ["cell", "entity"] else []
	var ability: Dictionary = form.base
	if ability.is_empty() or ability.targeting.kind not in ["cell", "entity"] or not Shield.available(actor, ability_id):
		return []
	return _legal_choices(state, actor, ability, ability_id)


## Check a target against the form the actor will actually use, not against both forms.
static func selection(state: Dictionary, actor: Dictionary, id: String, target_id: String,
		automatic_target_id := "", form: Dictionary = {}) -> Dictionary:
	var resolved := action_form(state, actor, id) if form.is_empty() else form
	if resolved.converted:
		return _target_choice(resolved.alternate.choices, target_id)
	return _base_selection(state, actor, resolved.base, target_id, id, automatic_target_id)


static func _base_selection(state: Dictionary, actor: Dictionary, ability: Dictionary, target_id: String,
		ability_id: String, automatic_target_id := "") -> Dictionary:
	if ability.is_empty() or not accepts_target_argument(ability, target_id) or not Shield.available(actor, ability_id):
		return {}
	var choices := _legal_choices(state, actor, ability, ability_id)
	if choices.is_empty():
		return {}
	if ability.handler == "sweep":
		if ability.params.get("opponents_only", false) and not choices.any(
				func(candidate: Dictionary) -> bool: return Board.opponents(state, actor, candidate)):
			return {}
		return {"id": "", "recipients": choices}
	if ability.handler == "perform":
		if ability_id == "healing_sonnet" and Upgrades.amount(state, actor, "front_row_seats") > 0:
			choices = _front_row(state, choices)
		var draw := EncounterRandom.uniform_draw(state.rng_state, choices.size())
		var choice: Dictionary = choices[draw.index]
		choice["rng_seed"] = draw.seed
		return choice
	if ability.targeting.kind == "automatic":
		if not automatic_target_id.is_empty():
			choices = choices.filter(func(choice: Dictionary) -> bool: return choice.id == automatic_target_id)
			if choices.is_empty():
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
		var nearest := Board.nearest(actor, choices)
		if ability.handler == "repel" and not nearest.is_empty():
			var destination := _step_away(state, actor, nearest, ability_id)
			if destination == nearest.position:
				return {}
			nearest["destination"] = destination
		return nearest
	return _target_choice(choices, target_id)


static func _target_choice(choices: Array, target_id: String) -> Dictionary:
	for choice in choices:
		if choice.id == target_id:
			return choice
	return {}


static func _front_row(state: Dictionary, choices: Array) -> Array:
	if choices.size() <= 2:
		return choices
	var health := choices.map(func(choice: Dictionary) -> int: return Board.entity(state, choice.id).hp)
	health.sort()
	return choices.filter(func(choice: Dictionary) -> bool: return Board.entity(state, choice.id).hp <= health[1])


static func _step_away(state: Dictionary, actor: Dictionary, target: Dictionary, id: String) -> Vector2i:
	var position: Vector2i = target.position
	var direction := -_pull_step(actor, target)
	if direction == Vector2i.ZERO:
		return position
	var steps := 1
	if id == "say_hello":
		steps = maxi(steps, Upgrades.amount(state, Summons.owner(state, actor), "warm_welcome"))
	for index in range(steps):
		if not Board.can_enter(state, position + direction):
			break
		position += direction
	return position


static func execute(state: Dictionary, actor: Dictionary, action: Dictionary, form: Dictionary, events: Array) -> bool:
	var id: String = action.ability_id
	var ability: Dictionary = form.base
	var target_id: String = action.get("target_id", "")
	if form.converted:
		var choice := selection(state, actor, id, target_id, "", form)
		# A stale manual target must not retarget, even if ordinary use on it would work.
		if choice.is_empty():
			return false
		Fittings.perform(state, actor, id, ability, form.alternate, choice, events)
		return true
	var performed := _execute_base(state, actor, action, ability, events)
	if performed and not form.alternate.is_empty():
		var stays := "" if FittingState.source(actor).is_empty() else " Fitted stays."
		Board.event(events, "fitted_fallback", "%s uses ordinary %s: %s unavailable (%s).%s" % [
			Board.display_name(state, actor), ability.label, form.alternate.label, form.alternate.unavailable_reason, stays],
			{"unit_id": actor.id, "ability_id": id, "status_id": "fitted"})
	return performed


static func _execute_base(state: Dictionary, actor: Dictionary, action: Dictionary,
		ability: Dictionary, events: Array) -> bool:
	var id: String = action.ability_id
	var target_id: String = action.get("target_id", "")
	if ability.is_empty() or not can_act(state, actor) or not accepts_target_argument(ability, target_id) \
			or not Shield.available(actor, id):
		return false
	var choice := _base_selection(state, actor, ability, target_id, id, action.get("automatic_target_id", ""))
	var first_event := events.size()
	if ability.handler == "perform":
		return _perform(state, actor, ability, id, choice, events)
	if ability.handler == "move" and action.get("retrieve_shield", false) and Shield.can_retrieve(actor):
		Shield.retrieve(state, actor, events)
	elif id == "healer_heal" and Upgrades.amount(state, actor, "me_or_you") > 0:
		var amount := int(ability.params.amount)
		if actor.hp < actor.max_hp:
			Support.heal(state, actor, actor, amount, events)
		else:
			Support.split_heal(state, actor, amount, events)
	elif choice.is_empty() or not _execute_choice(state, actor, action, ability, choice, events):
		return false
	var limit := _use_limit(ability)
	if limit >= 0:
		var used := _uses(actor, id) + 1
		var usage: Dictionary = actor.get("ability_uses", {})
		usage[id] = used
		actor["ability_uses"] = usage
		var event: Dictionary = events[first_event]
		event["remaining_uses"] = limit - used
		if limit == used:
			event.text += " No uses left this battle."
		else:
			event.text += " Uses left this battle: %d." % (limit - used)
	for index in range(first_event, events.size()):
		events[index]["ability_id"] = id
	return true


static func _perform(state: Dictionary, actor: Dictionary, ability: Dictionary, id: String,
		choice: Dictionary, events: Array) -> bool:
	if not Performances.perform(state, actor, ability, id, choice, events):
		return false
	if id not in BASE_SONGS or "song_weaving" not in Board.profile(state, actor).get("guild_techniques", []):
		return true
	var previous: Dictionary = actor.get("last_base_song", {})
	# A dry performance still counts. Only the live song writes history.
	actor["last_base_song"] = {"ability_id": id, "round": state.round}
	var prior_id: String = previous.get("ability_id", "")
	if previous.get("round", 0) != state.round - 1 or prior_id == id or prior_id not in BASE_SONGS \
			or not can_act(state, actor):
		return true
	var echo := owned_ability(state, actor, prior_id)
	if echo.get("handler") == "perform":
		# The live performance may have changed the legal listeners and committed a draw.
		var listener := _base_selection(state, actor, echo, "", prior_id)
		Performances.perform(state, actor, echo, prior_id, listener, events, true)
	return true


static func _execute_choice(state: Dictionary, actor: Dictionary, action: Dictionary, ability: Dictionary,
		choice: Dictionary, events: Array) -> bool:
	var target := Board.entity(state, choice.id)
	var params: Dictionary = ability.params
	var name := Board.display_name(state, actor)
	var target_name := Board.display_name(state, target) if not target.is_empty() else ""
	match ability.handler:
		"move":
			_move(state, actor, action, choice.get("route", [choice.position]), events)
		"quick_release":
			Fittings.release(state, actor, events)
			_move_step(state, actor, {}, choice.position, events)
		"summon":
			Summons.summon(state, actor, ability, choice.position, target, events)
		"nominate":
			Summons.nominate(state, actor, target, events)
		"fit":
			Fittings.fit(state, actor, target, events)
		"sweep":
			var event_type := "wave" if action.ability_id == "wave" else "sweep"
			Board.authored_event(state, events, event_type, "sweep",
				{"actor": name, "ability": ability.label}, {"unit_id": actor.id})
			var retaliation := Combat.RetaliationBatch.new() if choice.recipients.size() > 1 else null
			for recipient in choice.recipients:
				Combat.hurt(state, actor, recipient, int(params.damage), name, "", events, {}, retaliation)
			Combat.flush_retaliation(state, actor, events, retaliation)
		"stop_target":
			if not Statuses.apply(state, target, params.status, actor):
				return false
			var data := {"unit_id": actor.id, "target_id": target.id, "status_id": params.status}
			var status := Statuses.definition(state, params.status)
			if status.handler == "block_voluntary_move":
				Board.event(events, "status", "%s uses %s. %s's next voluntary movement is blocked." % [
					name, ability.label, target_name], data)
			else:
				Board.authored_event(state, events, "status", "stop_target",
					{"actor": name, "target": target_name, "ability": ability.label, "movement": "use Move"}, data)
		"repel":
			if Movement.blocks_forced(state, target, events):
				return true
			target.position = Movement.forced_destination(state, target, choice.destination,
				-_pull_step(actor, target), events)
			Board.authored_event(state, events, "repel", "repel",
				{"actor": name, "target": target_name, "ability": ability.label, "position": target.position},
				{"unit_id": actor.id, "target_id": target.id, "position": target.position})
			Shield.retrieve(state, target, events)
		"push":
			var direction := -_pull_step(actor, target)
			var destination: Vector2i = target.position + direction
			if Board.can_enter(state, destination):
				if _blocks_aimed_shift(state, target, target, events):
					return true
				destination = Movement.forced_destination(state, target, destination, direction, events)
				target.position = destination
				Board.authored_event(state, events, "push", "push",
					{"actor": name, "target": target_name, "position": destination},
					{"unit_id": actor.id, "target_id": target.id, "position": destination})
				Shield.retrieve(state, target, events)
			elif Board.capable(state, target, "damageable"):
				Combat.attack(state, actor, target, int(params.collision_damage),
					{"source_name": name + Board.text(state, "collision_suffix"), "misdirect": false}, events)
			else:
				Board.authored_event(state, events, "wait", "cannot_advance",
					{"actor": target_name}, {"unit_id": actor.id, "target_id": target.id})
		"apply_status":
			var id: String = params.status
			var application := Statuses.apply_result(state, actor, id, actor, events)
			if application == Statuses.Application.RESISTED:
				return true
			if application != Statuses.Application.APPLIED:
				return false
			var status := Statuses.definition(state, id)
			var data := {"unit_id": actor.id, "target_id": actor.id, "source_id": actor.id, "status_id": id}
			if status.handler == "reflect":
				var guard_range := Statuses.guard_range(state, actor, status)
				data["range"] = guard_range
				if Upgrades.amount(state, actor, "dig_in") > 0:
					var guard_text := "%s guards at range %d and redirects incoming attacks. Dig In also reverses enemy pulls aimed at %s."
					Board.event(events, "aura", guard_text % [name, guard_range, name], data)
				else:
					Board.authored_event(state, events, "aura", "aura", {"actor": name, "range": guard_range}, data)
			else:
				Board.authored_event(state, events, "status", "gain_status",
					{"actor": name, "status": status.label}, data)
		"bonk", "blast", "attack":
			_attack(state, actor, target, action.ability_id, ability, events)
		"swap_furthest", "swap_ally":
			_swap(state, actor, target, events)
		"misdirect":
			if not Statuses.apply(state, target, params.status, actor):
				return false
			var victim := Statuses.misdirection_victim(state, target, actor)
			Board.authored_event(state, events, "misdirect", "misdirect_mark",
				{"actor": name, "target": target_name, "victim": Board.display_name(state, victim)},
				{"unit_id": actor.id, "target_id": target.id, "victim_id": victim.id, "status_id": params.status})
		"heal", "enemy_heal":
			Support.heal(state, actor, target, int(params.amount), events)
		"healing_potion", "acid", "plain_tonic", "repeat_batch":
			Alchemy.administer(state, actor, target, ability, action.ability_id, events)
		"pull", "hook":
			_pull(state, actor, target, action.ability_id, ability, choice, events)
		_:
			return false
	return true


static func _move(state: Dictionary, actor: Dictionary, action: Dictionary, route: Array, events: Array) -> void:
	if Movement.blocks_voluntary(state, actor, events):
		return
	for position: Vector2i in route:
		_move_step(state, actor, action, position, events)
	if action.has("retreat_second"):
		var second: Vector2i = action.retreat_second
		if Board.distance(actor.position, second) == 1 and Board.can_enter(state, second):
			actor.position = second
			Board.event(events, "move", "Exit Strategy: %s retreats again to %s." % [
				Board.display_name(state, actor), Board.coordinate(second)], {"unit_id": actor.id, "position": second})


static func _move_step(state: Dictionary, actor: Dictionary, action: Dictionary, position: Vector2i, events: Array,
		follow_through := false) -> void:
	var origin: Vector2i = actor.position
	actor.position = position
	var copy := {"actor": Board.display_name(state, actor), "position": position}
	var data := {"unit_id": actor.id, "position": position}
	var template := "move"
	if action.has("follow_target_id"):
		var followed := Board.entity(state, action.follow_target_id)
		copy["target"] = Board.display_name(state, followed)
		data["target_id"] = followed.id
		template = action.get("follow_event", "follow_party")
	if follow_through:
		data.merge({"from_position": origin, "follow_through": true})
		Board.event(events, "move", "Follow Through: %s steps onto %s." % [
			copy.actor, Board.coordinate(position)], data)
	elif action.get("tactical_retreat", false):
		actor["last_retreat_round"] = state.round
		data["tactical_retreat"] = true
		Board.event(events, "move", "%s retreats to %s and cannot retreat next round." % [
			copy.actor, Board.coordinate(position)], data)
	else:
		Board.authored_event(state, events, "move", template, copy, data)
	Shield.retrieve(state, actor, events)


static func _attack(state: Dictionary, actor: Dictionary, target: Dictionary, id: String, ability: Dictionary,
		events: Array) -> void:
	var heckler := heckler_target(state, actor, ability)
	actor.statuses.erase("heckler")
	if not heckler.is_empty():
		target = heckler
		Board.event(events, "taunt", "Heckler draws %s's attack to %s." % [
			Board.display_name(state, actor), Board.display_name(state, target)],
			{"unit_id": actor.id, "target_id": target.id, "status_id": "heckler"})
	var recipients := [target]
	if id == "healer_bonk" and Upgrades.amount(state, actor, "strong_swing") > 0:
		for candidate in Board.occupants(state, ability.targeting):
			if target.id != candidate.id and Board.opponents(state, actor, candidate) \
					and _entity_allowed(state, actor, candidate, ability):
				recipients.append(candidate)
	var params: Dictionary = ability.params
	var suffix: String = params.get("source_suffix", "")
	if ability.handler == "blast" and not params.has("source_suffix"):
		suffix = Board.text(state, "blast_suffix")
	var strike := {"source_name": Board.display_name(state, actor) + suffix,
		"status": params.get("status", ""), "ability_id": id}
	if params.has("surround_bonus"):
		strike["surround_bonus"] = params.surround_bonus
	var retaliation := Combat.RetaliationBatch.new() if recipients.size() > 1 else null
	var defeated_target := false
	for recipient in recipients:
		if Board.alive(recipient):
			var defeated := Combat.attack(state, actor, recipient, int(params.damage), strike, events, retaliation)
			if recipient.id == target.id:
				defeated_target = defeated
	Combat.flush_retaliation(state, actor, events, retaliation)
	if defeated_target and id == "blacksmith_hammer_time" and Upgrades.amount(state, actor, "follow_through") > 0:
		# The hit and its defeat effects can kill the Smith or change the landing.
		var landing: Vector2i = target.position
		if can_act(state, actor) and can_move(state, actor) and Board.distance(actor.position, landing) == 1 \
				and Board.can_enter(state, landing) and not Movement.blocks_voluntary(state, actor, events):
			_move_step(state, actor, {}, landing, events, true)


static func heckler_target(state: Dictionary, actor: Dictionary, ability: Dictionary) -> Dictionary:
	if ability.get("handler", "") not in ["attack", "blast", "bonk"]:
		return {}
	var bard := Statuses.heckled_target(state, actor)
	if bard.is_empty() or bard not in Board.occupants(state, ability.targeting) \
			or not _entity_allowed(state, actor, bard, ability):
		return {}
	return bard


static func _pull(state: Dictionary, actor: Dictionary, target: Dictionary, id: String, ability: Dictionary,
		choice: Dictionary, events: Array) -> void:
	var name := Board.display_name(state, actor)
	var target_name := Board.display_name(state, target)
	var move_from: Vector2i = target.position
	if _digs_in(state, actor, target):
		var origin: Vector2i = actor.position
		var direction := -_pull_step(actor, target)
		var destination := origin + direction
		if Board.capable(state, actor, "pullable") and Board.is_vacant(state, destination):
			if _blocks_aimed_shift(state, actor, target, events):
				return
			actor.position = Movement.forced_destination(state, actor, destination, direction, events)
		Board.event(events, "pull", "Dig In: %s reverses %s's pull%s." % [target_name, name,
			", pulling them to %s" % Board.coordinate(actor.position) if actor.position != origin else " and holds position"],
			{"unit_id": target.id, "target_id": actor.id, "from_position": origin, "position": actor.position})
		if actor.position != origin:
			Shield.retrieve(state, actor, events)
	elif ability.handler == "hook":
		if _blocks_aimed_shift(state, target, target, events):
			return
		target.position = Movement.forced_destination(state, target, choice.destination, _pull_step(actor, target), events)
		Board.authored_event(state, events, "pull", "hook_pull",
			{"actor": name, "target": target_name, "ability": ability.label,
				"from": move_from, "position": target.position},
			{"unit_id": actor.id, "target_id": target.id, "from_position": move_from, "position": target.position})
		Shield.retrieve(state, target, events)
	else:
		var old: Vector2i = actor.position
		var direction := _pull_step(actor, target)
		if _blocks_aimed_shift(state, target, target, events) \
				or _blocks_aimed_shift(state, actor, target, events):
			return
		actor.position = Movement.forced_destination(state, actor, old + direction, direction, events)
		# Continue in the pull direction, using the caster's resolved recoil position for occupancy.
		target.position = Movement.forced_destination(state, target, old, direction, events)
		Board.authored_event(state, events, "pull", "pull",
			{"actor": name, "target": target_name, "position": target.position, "recoil": actor.position},
			{"unit_id": actor.id, "target_id": target.id, "position": target.position, "recoil_position": actor.position})
		Shield.retrieve(state, target, events)
		var status_id: String = ability.params.status
		if id == "wizard_pull" and Upgrades.amount(state, actor, "braced_casting") > 0 \
				and not Board.passable(state, actor.position + direction):
			status_id = ""
			Board.event(events, "status", "Braced Casting keeps %s upright." % name, {"unit_id": actor.id})
		var first_recoil_event := events.size()
		Combat.hurt(state, actor, actor, int(ability.params.recoil_damage),
			Board.text(state, "recoil_source"), status_id, events)
		# Optional presentation provenance. It does not change status behavior:
		# recovery can distinguish a Pull's seated fall from other knockdowns.
		for event in events.slice(first_recoil_event):
			if id == "wizard_pull" and event.get("type") == "damage" and event.get("target_id") == actor.id \
					and event.get("status_id") == status_id and Statuses.is_knockdown(state, status_id):
				actor.statuses[status_id]["presentation_cause"] = "pull_recoil"
				event["presentation_cause"] = "pull_recoil"
				var horizontal := signi(move_from.x - old.x)
				if horizontal != 0:
					actor.statuses[status_id]["presentation_facing"] = horizontal


static func _blocks_aimed_shift(state: Dictionary, mover: Dictionary, intended: Dictionary, events: Array) -> bool:
	if not Movement.blocks_forced(state, mover, events):
		return false
	# The resistance belongs to the would-be mover. The gesture still aims
	# at the action's selected target, even when Dig In reversed the pull.
	events.back()["resisted_target_id"] = intended.id
	return true


static func _swap(state: Dictionary, actor: Dictionary, target: Dictionary, events: Array) -> void:
	if Movement.blocks_voluntary(state, actor, events, target):
		return
	var old: Vector2i = actor.position
	actor.position = target.position
	target.position = Movement.forced_destination(state, target, old, Combat.toward(target.position, old), events)
	var name := Board.display_name(state, actor)
	var target_name := Board.display_name(state, target)
	Board.authored_event(state, events, "swap", "swap",
		{"actor": name, "target": target_name, "position": actor.position},
		{"unit_id": actor.id, "target_id": target.id, "position": actor.position, "target_position": target.position})
	Shield.retrieve(state, actor, events)
	Shield.retrieve(state, target, events)
	if Upgrades.amount(state, actor, "body_double") > 0:
		actor.statuses["body_double"] = {"source_id": actor.id, "partner_id": target.id}
		Board.event(events, "status", "Body Double: %s stands in for %s until their next turn." % [target_name, name],
			{"unit_id": actor.id, "target_id": target.id, "status_id": "body_double"})
	if Board.team(state, target) == Board.team(state, actor):
		var amount := Upgrades.amount(state, actor, "borrowed_courage")
		if amount > 0:
			target.statuses["borrowed_courage"] = {"source_id": actor.id, "amount": amount}
			Board.event(events, "status", "Borrowed Courage protects %s from %d damage on their next hit." % [
				target_name, amount], {"unit_id": actor.id, "target_id": target.id,
					"status_id": "borrowed_courage", "amount": amount})
	elif Board.opponents(state, actor, target):
		if Upgrades.amount(state, actor, "pocket_sand") > 0 and Statuses.apply(state, target, "held_in_place", actor):
			Board.event(events, "status", "Pocket Sand keeps %s from moving next turn." % target_name,
				{"unit_id": actor.id, "target_id": target.id, "status_id": "held_in_place"})
		if Upgrades.amount(state, actor, "pass_the_buck") > 0:
			_pass_mark(state, actor, target, events)


static func _pass_mark(state: Dictionary, rogue: Dictionary, partner: Dictionary, events: Array) -> void:
	var ids := Statuses.ids_with_handler(state, partner, "misdirect")
	if ids.is_empty():
		return
	ids.sort()
	var id: String = ids[0]
	var candidates := Board.occupants(state, {}).filter(func(candidate: Dictionary) -> bool:
		return Board.opponents(state, rogue, candidate) and Board.distance(partner.position, candidate.position) == 1)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var recipient: Dictionary = candidates[0]
	recipient.statuses[id] = partner.statuses[id]
	partner.statuses.erase(id)
	Board.event(events, "misdirect", "Pass the Buck moves the mark from %s to %s." % [
		Board.display_name(state, partner), Board.display_name(state, recipient)],
		{"unit_id": rogue.id, "from_id": partner.id, "target_id": recipient.id, "status_id": id})
