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
const ShieldWall = preload("res://rules/shield_wall.gd")
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
	return (not targeting.has("min_range") or reach >= int(targeting.min_range)) \
		and (not targeting.has("range") or (reach > 0 and reach <= int(targeting.range)))


static func _clear_lane(state: Dictionary, origin: Vector2i, destination: Vector2i) -> bool:
	var delta := destination - origin
	if (delta.x != 0 and delta.y != 0) or delta == Vector2i.ZERO:
		return false
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var cell := origin + step
	while cell != destination:
		for obstacle in state.obstacles:
			if Board.alive(obstacle) and Board.occupies_cell(obstacle, cell):
				return false
		cell += step
	return true


static func _target_position_allowed(state: Dictionary, actor: Dictionary, position: Vector2i,
		targeting: Dictionary) -> bool:
	return _in_reach(actor, position, targeting) \
		and (not targeting.get("straight_line_clear", false) or _clear_lane(state, actor.position, position))


static func _footprint_contact(state: Dictionary, actor: Dictionary, target: Dictionary,
		targeting: Dictionary) -> Dictionary:
	if not targeting.has("min_range") and not targeting.get("straight_line_clear", false):
		return ShieldWall.attack_contact(actor.position, target, int(targeting.get("range", -1)))
	var cells: Array[Vector2i] = []
	var closest := 2147483647
	var result := {}
	for cell in Board.occupied_cells(target):
		if not _target_position_allowed(state, actor, cell, targeting):
			continue
		cells.append(cell)
		var distance := Board.distance(actor.position, cell)
		if distance < closest:
			closest = distance
			result["position"] = cell
	if not result.is_empty():
		result["target_cells"] = cells
	return result


static func _swap_cells_open(state: Dictionary, actor: Dictionary, candidate: Dictionary) -> bool:
	return actor.position != candidate.position \
		and Board.can_enter(state, candidate.position, candidate.id) \
		and Board.can_enter(state, actor.position, actor.id)


static func _entity_allowed(state: Dictionary, actor: Dictionary, candidate: Dictionary, ability: Dictionary) -> bool:
	if ability.handler in ["healing_potion", "acid", "plain_tonic"]:
		return Alchemy.can_target(state, actor, candidate, ability)
	if ability.params.get("opponents_only", false) and not Board.opponents(state, actor, candidate):
		return false
	if candidate.id == actor.id:
		return ability.handler in ["heal", "padding"] and Board.capable(state, actor, "healable") \
			and ((ability.targeting.kind == "entity" and ability.params.get("allow_self", false)) \
				or (ability.targeting.kind == "automatic" and ability.params.get("prefer_wounded_self", false) \
					and actor.hp < actor.max_hp))
	if candidate.has("footprint_offsets") and ability.handler in ["bonk", "blast", "attack"]:
		return Board.capable(state, candidate, "damageable") \
			and not _footprint_contact(state, actor, candidate, ability.targeting).is_empty()
	if not _target_position_allowed(state, actor, candidate.position, ability.targeting):
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
		"heal", "padding":
			return Board.capable(state, candidate, "healable") \
				and (ability.targeting.kind != "entity" or Board.allied(state, actor, candidate))
		"enemy_heal":
			return candidate.has("character_id") and candidate.hp < candidate.max_hp \
				and Board.team(state, candidate) == Board.team(state, actor)
		"swap_ally":
			return candidate.get("character_id") == ability.params.character \
				and Board.team(state, candidate) == Board.team(state, actor) \
				and Board.distance(actor.position, candidate.position) <= int(ability.params.range) \
				and _swap_cells_open(state, actor, candidate)
		"swap_furthest":
			return candidate.has("character_id") \
				and (ability.targeting.kind == "automatic" or _swap_cells_open(state, actor, candidate))
		"misdirect":
			return Board.team(state, candidate) != Board.team(state, actor) \
				and (Statuses.definition(state, ability.params.status).params.get("obstacles_only", false) \
					or not Statuses.misdirection_victim(state, candidate, actor).is_empty()) \
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
			var hp := Summons.starting_hp(state, actor, ability.params.character, corpse, int(Statuses.inspired(actor)))
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
			return int(ability.params.get("charges", -1))
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
	if ability.handler == "shield_wall":
		return ShieldWall.choices(state, actor)
	if ability.handler == "repeat_batch":
		return Alchemy.repeat_choices(state, actor)
	var targeting: Dictionary = ability.targeting
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
				if not _entity_allowed(state, actor, candidate, ability):
					continue
				var choice := {"id": candidate.id, "label": Board.display_name(state, candidate),
					"position": candidate.position}
				if candidate.has("footprint_offsets") and ability.handler in ["bonk", "blast", "attack"]:
					choice.merge(_footprint_contact(state, actor, candidate, targeting), true)
				if ability.handler == "hook" and not _digs_in(state, actor, candidate):
					choice["destination"] = candidate.position + _pull_step(actor, candidate)
				elif ability.handler == "repel" and targeting.kind == "entity":
					choice = _repel_choice(state, actor, choice, ability_id)
				if not choice.is_empty():
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
static func action_form(state: Dictionary, actor: Dictionary, id: String, direct := false) -> Dictionary:
	var base := owned_ability(state, actor, id)
	var alternate := Fittings.alternate(state, actor, id, base, direct) \
		if base.has("fitted_form") and can_act(state, actor) else {}
	return {"base": base, "alternate": alternate, "converted": not alternate.get("choices", []).is_empty()}


static func command_ability(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var form := action_form(state, actor, id, true)
	var alternate: Dictionary = form.alternate
	if form.converted:
		var reason := _improvement_reason(actor, _fine_adjustment(state, actor))
		var help: String = alternate.help
		if not reason.is_empty():
			var benefit := "adds 1 to the primary amount" if alternate.primary == "amount" else "grants Steady Hands"
			help += " %s %s." % [reason, benefit]
		return alternate.merged({"label": "%s → %s" % [form.base.label, alternate.label], "help": help}, true)
	var base := _command_base(state, actor, id, form.base)
	if base.is_empty():
		return {}
	var unavailable := Shield.blocked_reason(state, actor, id)
	if base.handler == "shield_wall":
		unavailable = ShieldWall.blocked_reason(state, actor)
	var wall_blocked: bool = not unavailable.is_empty() \
		and (base.handler == "shield_wall" or unavailable == "wall already standing")
	var blocked: bool = wall_blocked
	if base.targeting.kind in ["automatic", "none"]:
		blocked = blocked or _base_preflight(state, actor, {"ability_id": id, "direct": true}, form.base).is_empty()
	if not alternate.is_empty():
		var reason: String = alternate.unavailable_reason
		var denied: bool = blocked or not unavailable.is_empty()
		var label := " (%s; Fitted stays)" % reason if denied else " (ordinary; Fitted stays)"
		return base.merged({"label": base.label + label, "command_blocked": denied,
			"help": "%s unavailable: %s. %s" % [alternate.label, reason, base.help]}, true)
	if blocked:
		var help: String = "%s: %s." % [base.label, unavailable] if wall_blocked else base.help
		return base.merged({"command_blocked": true, "help": help}, true)
	return base


## Project only the ordinary Direct form; an available fitting takes precedence.
static func _command_base(state: Dictionary, actor: Dictionary, id: String, base: Dictionary) -> Dictionary:
	if base.is_empty():
		return {}
	if _has_split_heal(state, actor, id):
		return base.merged({"label": "Heal self or split among allies",
			"targeting": {"kind": "none"},
			"help": "If hurt, heal self; otherwise split among other living deployed heroes, unused shares lost."}, true)
	var aimed: Dictionary = base.targeting.get("direct", {})
	if aimed.is_empty():
		return base
	return base.merged({"label": aimed.get("label", base.label), "help": aimed.help,
		"targeting": base.targeting.merged({"kind": "entity"}, true)}, true)


static func _has_split_heal(state: Dictionary, actor: Dictionary, id: String) -> bool:
	return id == "healer_heal" and Upgrades.amount(state, actor, "me_or_you") > 0


## Me or You replaces recipient selection with the base action's own split policy.
## The caller must first give an available fitted alternate its normal precedence.
static func standing_split_heal(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	if not _has_split_heal(state, actor, id):
		return {}
	var action := {"ability_id": id}
	var base := owned_ability(state, actor, id)
	return action if not _base_preflight(state, actor, action, base).is_empty() else {}


static func standing_alternate(state: Dictionary, actor: Dictionary, id: String, policy := "") -> Dictionary:
	if FittingState.source(actor).is_empty():
		return {}
	var form := action_form(state, actor, id)
	if not form.converted:
		return {}
	var alternate: Dictionary = form.alternate
	var intent := {"ability_id": id, "target_id": "", "form": form}
	if alternate.targeting.kind in ["none", "automatic"]:
		return intent
	var choices: Array = alternate.choices
	if policy == "pursue" and alternate.id == "fitted_pull":
		var opponents := choices.filter(func(choice: Dictionary) -> bool:
			return Board.opponents(state, actor, Board.entity(state, choice.id)))
		if not opponents.is_empty():
			choices = opponents
	var choice := _standing_choice(state, actor, alternate, choices, policy)
	intent.target_id = choice.id
	return intent


static func _standing_choice(state: Dictionary, actor: Dictionary, alternate: Dictionary,
		choices: Array, policy: String) -> Dictionary:
	match policy:
		"shield_wall":
			return choices[0]
		"make_friend":
			var opponents := Board.occupants(state, {}).filter(func(unit: Dictionary) -> bool:
				return Board.opponents(state, actor, unit))
			if opponents.is_empty():
				return choices[0]
			var best: Dictionary = choices[0]
			var distance := 2147483647
			for candidate in choices:
				var nearest := Board.nearest(candidate, opponents, true)
				var reach := Board.distance(candidate.position, nearest.position)
				if reach < distance:
					best = candidate
					distance = reach
			return best
		"most_injured", "nearest_target":
			# Unpick the Stitch already supplies all candidates in Triage priority order.
			if alternate.get("selection") == "first":
				return choices[0]
			if policy == "nearest_target" and alternate.get("standing_policy") == "most_injured":
				var best: Dictionary = {}
				var most_missing := 0
				for candidate in choices:
					var unit := Board.entity(state, candidate.id)
					var missing := int(candidate.get("missing_hp", unit.max_hp - unit.hp))
					if missing > most_missing:
						best = candidate
						most_missing = missing
				if not best.is_empty():
					return best
	return Board.nearest(actor, choices, true)


static func targets(state: Dictionary, actor: Dictionary, ability_id: String, direct := false) -> Array:
	var form := action_form(state, actor, ability_id, direct)
	if form.converted:
		return form.alternate.choices if form.alternate.targeting.kind in ["cell", "entity"] else []
	var ability: Dictionary = _command_base(state, actor, ability_id, form.base) if direct else form.base
	if ability.is_empty() or ability.targeting.kind not in ["cell", "entity"] \
			or not Shield.available(state, actor, ability_id):
		return []
	return _legal_choices(state, actor, ability, ability_id)


## Escape needs legal partners before ranking them; the legacy automatic swap still ranks first.
static func escape_swap_partners(state: Dictionary, actor: Dictionary, id: String) -> Array:
	var ability := owned_ability(state, actor, id)
	if ability.get("handler") != "swap_furthest" or not Shield.available(state, actor, id):
		return []
	return _legal_choices(state, actor, ability, id).filter(func(choice: Dictionary) -> bool:
		return _swap_cells_open(state, actor, choice))


## Check a target against the form the actor will actually use, not against both forms.
static func selection(state: Dictionary, actor: Dictionary, id: String, target_id: String,
		automatic_target_id := "", form: Dictionary = {}) -> Dictionary:
	var resolved := action_form(state, actor, id) if form.is_empty() else form
	if resolved.converted:
		return _alternate_selection(state, actor, resolved.alternate, target_id)
	return _base_selection(state, actor, resolved.base, target_id, id, automatic_target_id)


static func _alternate_selection(state: Dictionary, actor: Dictionary, alternate: Dictionary,
		target_id: String) -> Dictionary:
	if not accepts_target_argument(alternate, target_id):
		return {}
	var choices: Array = alternate.choices
	if alternate.targeting.kind == "automatic":
		match alternate.get("selection", ""):
			"random":
				var draw := EncounterRandom.uniform_draw(state.rng_state, choices.size())
				return choices[draw.index].merged({"rng_seed": draw.seed}, true)
			"first":
				return choices[0]
		return Board.nearest(actor, choices, true)
	return _target_choice(choices, target_id)


static func _base_selection(state: Dictionary, actor: Dictionary, ability: Dictionary, target_id: String,
		ability_id: String, automatic_target_id := "") -> Dictionary:
	if ability.is_empty() or not accepts_target_argument(ability, target_id) \
			or not Shield.available(state, actor, ability_id):
		return {}
	var choices := _legal_choices(state, actor, ability, ability_id)
	if choices.is_empty():
		return {}
	if ability.handler == "sweep":
		if ability.params.get("opponents_only", false) and not choices.any(
				func(candidate: Dictionary) -> bool: return Board.opponents(state, actor, candidate)):
			return {}
		return {"id": "", "recipients": choices}
	if ability.handler == "perform" and ability.targeting.kind == "automatic":
		# Front Row Seats restricts the autonomous draw, not who can hear the song.
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
			# Autonomous repel checks the nearest recipient first and never tries another.
			return _repel_choice(state, actor, nearest, ability_id)
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


static func _repel_choice(state: Dictionary, actor: Dictionary, choice: Dictionary, id: String) -> Dictionary:
	var destination := _step_away(state, actor, choice, id)
	if destination == choice.position:
		return {}
	choice["destination"] = destination
	return choice


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
		var alternate: Dictionary = form.alternate
		var choice := _alternate_selection(state, actor, alternate, target_id)
		# A stale manual target must not retarget, even if ordinary use on it would work.
		if choice.is_empty():
			return false
		var fine_adjustment := _fine_adjustment(state, actor)
		var primary: String = alternate.get("primary", "steady")
		Fittings.consume(state, actor, id, ability, alternate, choice, events)
		var improvement := _spend_improvement(state, actor, primary, fine_adjustment, events)
		var first := events.size()
		Fittings.apply(state, actor, id, ability, alternate, choice,
			int(not improvement.is_empty() and primary == "amount"), events)
		for index in range(first, events.size()):
			events[index]["ability_id"] = alternate.id
			events[index]["source_ability_id"] = id
		_finish_improvement(state, actor, primary, improvement, events)
		_weave(state, actor, id, events)
		return true
	var performed := _execute_base(state, actor, action, ability, events)
	if performed and not form.alternate.is_empty():
		var stays := "" if FittingState.source(actor).is_empty() else " Fitted stays."
		Board.event(events, "fitted_fallback", "%s uses ordinary %s: %s unavailable (%s).%s" % [
			Board.display_name(state, actor), ability.label, form.alternate.label, form.alternate.unavailable_reason, stays],
			{"unit_id": actor.id, "ability_id": id, "status_id": "fitted"})
	return performed


## An empty choice can mean a legal dry song or a non-aimed special branch, not an invalid use.
static func _base_preflight(state: Dictionary, actor: Dictionary, action: Dictionary,
		ability: Dictionary) -> Dictionary:
	var id: String = action.ability_id
	var target_id: String = action.get("target_id", "")
	var selection_form := _command_base(state, actor, id, ability) if action.get("direct", false) else ability
	if selection_form.is_empty() or not can_act(state, actor) or not accepts_target_argument(selection_form, target_id) \
			or not Shield.available(state, actor, id):
		return {}
	if ability.handler == "move" and action.get("retrieve_shield", false) and Shield.can_retrieve(actor):
		return {"kind": "retrieve", "choice": {}}
	if _has_split_heal(state, actor, id):
		return {"kind": "split", "choice": {}}
	var choice := _base_selection(state, actor, selection_form, target_id, id, action.get("automatic_target_id", ""))
	if ability.handler == "perform" and (selection_form.targeting.kind == "automatic" or not choice.is_empty()):
		return {"kind": "song", "choice": choice}
	return {"kind": "choice", "choice": choice} if not choice.is_empty() else {}


static func _execute_base(state: Dictionary, actor: Dictionary, action: Dictionary,
		ability: Dictionary, events: Array) -> bool:
	var use := _base_preflight(state, actor, action, ability)
	if use.is_empty():
		return false
	var id: String = action.ability_id
	var primary := _base_primary(ability, use)
	var improvement := _spend_improvement(state, actor, primary, false, events)
	var bonus := int(not improvement.is_empty() and primary == "amount")
	var first_event := events.size()
	match use.kind:
		"song":
			Performances.perform(state, actor, ability, id, use.choice, events, false, bonus)
			_finish_improvement(state, actor, primary, improvement, events)
			_weave(state, actor, id, events)
			return true
		"retrieve":
			Shield.retrieve(state, actor, events)
		"split":
			var amount := int(ability.params.amount) + bonus
			if actor.hp < actor.max_hp:
				Support.heal(state, actor, actor, amount, events)
			else:
				Support.split_heal(state, actor, amount, events)
		_:
			_execute_choice(state, actor, action, ability, use.choice, bonus, events)
	if ability.has("variant_of") and events.size() > first_event:
		var event: Dictionary = events[first_event]
		if not str(event.get("text", "")).contains(str(ability.label)):
			event["text"] = "%s: %s" % [ability.label, event.get("text", "")]
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
	_finish_improvement(state, actor, primary, improvement, events)
	return true


static func _base_primary(ability: Dictionary, use: Dictionary) -> String:
	if ability.params.get("shared_reaction", false):
		return "steady"
	match ability.handler:
		"move", "quick_release":
			return ""
		"attack", "bonk", "blast", "sweep", "heal", "enemy_heal", "healing_potion", "acid", \
				"plain_tonic", "repeat_batch", "summon":
			return "amount"
		"perform":
			if ability.params.has("damage"):
				return "dry" if use.choice.is_empty() else "amount"
	return "steady"


static func _spend_improvement(state: Dictionary, actor: Dictionary, primary: String,
		fine_adjustment: bool, events: Array) -> String:
	if primary.is_empty():
		return ""
	var reason := _improvement_reason(actor, fine_adjustment)
	if reason.is_empty():
		return ""
	var inspired := Statuses.inspired(actor)
	if inspired:
		actor.statuses.erase(Statuses.INSPIRED)
	var effect := "adds 1 to the primary amount"
	if primary == "steady":
		effect = "provides Steady Hands after the action"
	elif primary == "dry":
		effect = "has no listener to improve"
	Board.event(events, "primary_improvement", "%s: %s %s." % [reason, Board.display_name(state, actor), effect],
		{"unit_id": actor.id, "status_id": Statuses.INSPIRED if inspired else "fine_adjustment",
			"consumed": inspired, "amount": int(primary == "amount")})
	return reason


static func _fine_adjustment(state: Dictionary, actor: Dictionary) -> bool:
	return Upgrades.amount(state, Board.entity(state, FittingState.source(actor)), "fine_adjustment") > 0


static func _improvement_reason(actor: Dictionary, fine_adjustment: bool) -> String:
	if Statuses.inspired(actor):
		return "Inspired and Fine Adjustment" if fine_adjustment else "Inspired"
	return "Fine Adjustment" if fine_adjustment else ""


static func _finish_improvement(state: Dictionary, actor: Dictionary, primary: String,
		improvement: String, events: Array) -> void:
	if primary == "steady" and not improvement.is_empty() and Board.alive(actor):
		Statuses.grant_steady_hands(state, actor, improvement, events)


static func _weave(state: Dictionary, actor: Dictionary, id: String, events: Array) -> void:
	if id not in BASE_SONGS or "song_weaving" not in Board.profile(state, actor).get("guild_techniques", []):
		return
	var previous: Dictionary = actor.get("last_base_song", {})
	# A dry performance still counts. Only the live song writes history.
	actor["last_base_song"] = {"ability_id": id, "round": state.round}
	var prior_id: String = previous.get("ability_id", "")
	if previous.get("round", 0) != state.round - 1 or prior_id == id or prior_id not in BASE_SONGS \
			or not can_act(state, actor):
		return
	var echo := owned_ability(state, actor, prior_id)
	if echo.get("handler") == "perform":
		# The live performance may have changed the legal listeners and committed a draw.
		var listener := _base_selection(state, actor, echo, "", prior_id)
		Performances.perform(state, actor, echo, prior_id, listener, events, true)


static func _execute_choice(state: Dictionary, actor: Dictionary, action: Dictionary, ability: Dictionary,
		choice: Dictionary, bonus: int, events: Array) -> void:
	var target := Board.entity(state, choice.id)
	var params: Dictionary = ability.params
	var name := Board.display_name(state, actor)
	var target_name := Board.display_name(state, target) if not target.is_empty() else ""
	match ability.handler:
		"move":
			_move(state, actor, action, choice.get("route", [choice.position]), events)
		"shield_wall":
			ShieldWall.place(state, actor, choice.position, events)
		"quick_release":
			Fittings.release(state, actor, events)
			_move_step(state, actor, {}, choice.position, events)
		"summon":
			Summons.summon(state, actor, ability, choice.position, target, events, bonus)
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
				Combat.hurt(state, actor, recipient, int(params.damage) + bonus, name, "", events, {}, retaliation)
			Combat.flush_retaliation(state, actor, events, retaliation)
		"stop_target":
			Statuses.apply(state, target, params.status, actor)
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
				return
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
					return
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
			if application != Statuses.Application.APPLIED:
				return
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
			_attack(state, actor, target, choice.position, action.ability_id, ability, bonus, events)
		"swap_furthest", "swap_ally":
			_swap(state, actor, target, events)
		"misdirect":
			Statuses.apply(state, target, params.status, actor)
			if Statuses.definition(state, params.status).params.get("obstacles_only", false):
				Board.event(events, "misdirect", "%s marks %s to blame adjacent furniture on their next attack." % [
					name, target_name], {"unit_id": actor.id, "target_id": target.id, "status_id": params.status})
			else:
				var victim := Statuses.misdirection_victim(state, target, actor)
				Board.authored_event(state, events, "misdirect", "misdirect_mark",
					{"actor": name, "target": target_name, "victim": Board.display_name(state, victim)},
					{"unit_id": actor.id, "target_id": target.id, "victim_id": victim.id, "status_id": params.status})
		"heal", "enemy_heal":
			Support.heal(state, actor, target, int(params.amount) + bonus, events)
		"padding":
			Statuses.grant_padding(state, actor, target, int(params.amount), events)
		"healing_potion", "acid", "plain_tonic", "repeat_batch":
			Alchemy.administer(state, actor, target, ability, action.ability_id, events, bonus)
		"pull", "hook":
			_pull(state, actor, target, action.ability_id, ability, choice, events)


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


static func _attack(state: Dictionary, actor: Dictionary, target: Dictionary, contact: Vector2i,
		id: String, ability: Dictionary, bonus: int, events: Array) -> void:
	var heckler := heckler_target(state, actor, ability)
	actor.statuses.erase("heckler")
	if not heckler.is_empty():
		target = heckler
		contact = target.position
		Board.event(events, "taunt", "Heckler draws %s's attack to %s." % [
			Board.display_name(state, actor), Board.display_name(state, target)],
			{"unit_id": actor.id, "target_id": target.id, "status_id": "heckler"})
	var recipients := [target]
	if id == "healer_bonk" and Upgrades.amount(state, actor, "strong_swing") > 0:
		for candidate in Board.occupants(state, ability.targeting):
			if target.id != candidate.id and Board.opponents(state, actor, candidate) \
					and _entity_allowed(state, actor, candidate, ability):
				recipients.append(candidate)
	elif id == "blacksmith_sweep":
		for candidate in Board.occupants(state, ability.targeting):
			if candidate.id != target.id and _entity_allowed(state, actor, candidate, ability):
				recipients.append(candidate)
				break
	if ability.params.get("spear_followthrough", false) and Board.distance(actor.position, contact) == 1:
		var rear: Vector2i = contact + (contact - actor.position)
		for candidate in Board.occupants(state, {"objects": true, "capabilities": ["damageable"]}):
			if candidate.id != target.id and Board.occupies_cell(candidate, rear):
				recipients.append(candidate)
	var through := _through_target(state, actor, target.id, contact, ability) if id == "wizard_through_shot" else {}
	var params: Dictionary = ability.params
	var suffix: String = params.get("source_suffix", "")
	if ability.handler == "blast" and not params.has("source_suffix"):
		suffix = Board.text(state, "blast_suffix")
	var strike := {"source_name": Board.display_name(state, actor) + suffix,
		"status": params.get("status", ""), "ability_id": id, "primary_bonus": bonus}
	if params.has("surround_bonus"):
		strike["surround_bonus"] = params.surround_bonus
	var retaliation := Combat.RetaliationBatch.new() if recipients.size() > 1 or not through.is_empty() else null
	var defeated_target := false
	for recipient in recipients:
		if Board.alive(recipient):
			if recipient.id == target.id and recipient.has("footprint_offsets"):
				strike["impact_position"] = contact
			else:
				strike.erase("impact_position")
			if id == "blacksmith_sweep" and recipient.id != target.id:
				strike["primary_bonus"] = 0
			var defeated := Combat.attack(state, actor, recipient, int(params.damage), strike, events, retaliation)
			if recipient.id == target.id:
				defeated_target = defeated
	if not through.is_empty() and Board.alive(through.target):
		var presentation := {"data": {"impact_position": through.position}, "copy": {}} \
			if through.target.has("footprint_offsets") else {}
		Combat.hurt(state, actor, through.target, 1, ability.label, "", events, presentation, retaliation)
	Combat.flush_retaliation(state, actor, events, retaliation)
	if defeated_target and id == "blacksmith_hammer_time" and Upgrades.amount(state, actor, "follow_through") > 0:
		# The hit and its defeat effects can kill the Smith or change the landing.
		var landing := contact
		if can_act(state, actor) and can_move(state, actor) and Board.distance(actor.position, landing) == 1 \
				and Board.can_enter(state, landing) and not Movement.blocks_voluntary(state, actor, events):
			_move_step(state, actor, {}, landing, events, true)


static func _through_target(state: Dictionary, actor: Dictionary, primary_id: String, contact: Vector2i,
		ability: Dictionary) -> Dictionary:
	var delta: Vector2i = contact - actor.position
	if (delta.x == 0) == (delta.y == 0):
		return {}
	var nearest: Dictionary = {}
	var nearest_distance := 2147483647
	var primary_distance := Board.distance(actor.position, contact)
	for candidate in Board.occupants(state, ability.targeting):
		if candidate.id == primary_id or not _entity_allowed(state, actor, candidate, ability):
			continue
		for cell in Board.occupied_cells(candidate):
			var offset: Vector2i = cell - actor.position
			var aligned := (delta.x == 0 and offset.x == 0 and signi(offset.y) == signi(delta.y)) \
				or (delta.y == 0 and offset.y == 0 and signi(offset.x) == signi(delta.x))
			var distance := Board.distance(actor.position, cell)
			if aligned and distance > primary_distance and distance < nearest_distance \
					and _in_reach(actor, cell, ability.targeting):
				nearest = {"target": candidate, "position": cell}
				nearest_distance = distance
	return nearest


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
