extends RefCounted
## Tactical fitted forms reuse ordinary hits, healing, movement reactions and shield state.

const Board = preload("res://rules/board.gd")
const Combat = preload("res://rules/combat.gd")
const Movement = preload("res://rules/movement.gd")
const Shield = preload("res://rules/shield.gd")
const Statuses = preload("res://rules/statuses.gd")
const Support = preload("res://rules/support.gd")
const Upgrades = preload("res://rules/upgrades.gd")

const BOOT_TOFFEE := "boot_toffee"


static func describe(state: Dictionary, actor: Dictionary, _source_id: String, base: Dictionary,
		direct := false) -> Dictionary:
	var id: String = base.get("fitted_form", "")
	match id:
		"keep_your_head_down":
			var reach := int(base.targeting.get("range", -1))
			var amount := int(base.params.damage)
			var candidates := _heroes(state, actor, false).filter(func(hero: Dictionary) -> bool:
				return reach < 0 or Board.distance(actor.position, hero.position) <= reach)
			var span := "anywhere" if reach < 0 else "within %d tile(s)" % reach
			var help := "Cover another hero %s for %d less damage on their next hit, through their next turn." % [span, amount]
			if Upgrades.amount(state, actor, "strong_swing") > 0:
				help += " Strong Swing also covers the other heroes in reach."
			return _form(id, "Keep Your Head Down", help, "entity", _entity_choices(state, candidates),
				"no other hero in staff reach", amount)
		"doctors_orders":
			var amount := int(base.params.amount)
			var choices := _entity_choices(state, _damageable_opponents(state, actor))
			var help := "Deal %d damage to a chosen living opponent." if direct \
				else "Deal %d damage to the nearest living opponent."
			return _form(id, "Doctor's Orders", help % amount, _primary_kind(direct),
				_nearest_primary_choices(actor, choices, direct), "no damageable opponent", amount)
		"mending_blast":
			return _mending_blast(state, actor, id, int(base.params.damage), direct)
		"send_off":
			return _form(id, "Send-Off",
				"Push a character or movable obstacle one open step away. No recoil or collision damage.",
				"entity", _shove_choices(state, actor, false), "no open shove")
		"it_was_me":
			var candidates := _damageable_opponents(state, actor).filter(func(target: Dictionary) -> bool:
				return Board.distance(actor.position, target.position) == 1)
			return _form(id, "It Was Me", "Bonk an adjacent opponent for 2 damage and taunt them if they survive.",
				"entity", _entity_choices(state, candidates), "no adjacent damageable opponent", 2)
		"clear_jump":
			return _clear_jump(state, actor, id, direct)
		"safety_distance":
			return _form(id, "Safety Distance", "Send a friendly character exactly two tiles away one open step farther.",
				"entity", _shove_choices(state, actor, true), "no friendly character with an open shove at range two")
		"unpick_the_stitch":
			return _unpick_the_stitch(state, actor, id, int(base.params.amount))
		"ring_of_salve":
			var amount := int(base.params.damage)
			var patients := Board.occupants(state, {"capabilities": ["healable"]}).filter(
				func(target: Dictionary) -> bool:
					return target.id != actor.id and target.hp < target.max_hp and Board.allied(state, actor, target) \
						and Board.distance(actor.position, target.position) == 1)
			var choices := [{"id": "", "recipients": _entity_choices(state, patients)}] if not patients.is_empty() else []
			return _form(id, "Ring of Salve", "Heal every adjacent wounded friendly character for %d HP." % amount,
				"none", choices, "no adjacent wounded friendly character", amount)
		"cut_the_wire":
			return _cut_the_wire(state, actor, id, direct)
		"lend_a_shield":
			var amount := int(base.params.damage)
			var available := Shield.position(actor) == null
			var candidates := _heroes(state, actor, false).filter(func(hero: Dictionary) -> bool:
				return Board.distance(actor.position, hero.position) <= 3) if available else []
			return _form(id, "Lend a Shield",
				"Cover another hero within three tiles for %d less damage on their next hit, through their next turn. The shield lands on their tile." % amount,
				"entity", _entity_choices(state, candidates),
				"no other hero in shield reach" if available else "shield away", amount)
	return {}


static func apply(state: Dictionary, actor: Dictionary, _source_id: String, _base: Dictionary,
		form: Dictionary, choice: Dictionary, bonus: int, events: Array) -> void:
	var target := Board.entity(state, choice.id)
	var base_amount := int(form.get("amount", 0))
	var amount := base_amount + bonus
	match form.id:
		"keep_your_head_down":
			Statuses.grant_cover(state, actor, target, form.id, amount, events)
			if Upgrades.amount(state, actor, "strong_swing") > 0:
				for other: Dictionary in form.choices:
					if other.id != choice.id:
						Statuses.grant_cover(state, actor, Board.entity(state, other.id), form.id, amount, events)
		"doctors_orders":
			Combat.hurt(state, actor, target, amount, form.label, "", events)
			_report_idle(state, actor, "me_or_you", "Me or You", "no company heal", events)
		"mending_blast":
			var secondary := Board.nearest(target, _wounded_heroes(state, actor)) \
				if Upgrades.amount(state, actor, "conductive_personality") > 0 else {}
			Support.heal(state, actor, target, amount, events, form.label)
			if not secondary.is_empty():
				# The bolt inherits More Powder, not the one-time primary bonus or actual healed HP.
				Support.heal(state, actor, secondary, ceili(base_amount * 0.5), events, "Conductive Personality")
			_report_idle(state, actor, "demolition_practice", "Demolition Practice", "no obstacle hit", events)
			_report_idle(state, actor, "duck", "Duck!", "no knockdown", events)
			_report_idle(state, actor, "parting_gift", "Parting Gift", "no hostile shove", events)
		"send_off", "safety_distance":
			_shove(state, actor, target, choice, form.label, events)
			if form.id == "send_off":
				_report_idle(state, actor, "padded_landing", "Padded Landing", "no recoil", events)
				_report_idle(state, actor, "braced_casting", "Braced Casting", "no recoil", events)
		"it_was_me":
			Combat.attack(state, actor, target, base_amount,
				{"source_name": form.label, "status": "taunt", "ability_id": form.id, "primary_bonus": bonus}, events)
			_report_idle(state, actor, "cheap_shot", "Cheap Shot", "no blame mark", events)
			_report_idle(state, actor, "long_finger", "Long Finger", "no blame mark", events)
			_report_idle(state, actor, "pass_the_buck", "Pass the Buck", "no blame mark", events)
		"clear_jump":
			_jump(state, actor, target, choice.destination, events)
			_report_idle(state, actor, "body_double", "Body Double", "no swap", events)
			_report_idle(state, actor, "pocket_sand", "Pocket Sand", "no swap", events)
			_report_idle(state, actor, "borrowed_courage", "Borrowed Courage", "no swap", events)
			_report_idle(state, actor, "pass_the_buck", "Pass the Buck", "no swap", events)
		"unpick_the_stitch":
			Combat.attack(state, actor, target, base_amount,
				{"source_name": form.label, "ability_id": form.id, "primary_bonus": bonus}, events)
		"ring_of_salve":
			for recipient: Dictionary in choice.recipients:
				Support.heal(state, actor, Board.entity(state, recipient.id), amount, events, form.label)
		"cut_the_wire":
			_release_holds(state, actor, target, choice, events)
		"lend_a_shield":
			for active in Statuses.ids_with_handler(state, actor, "reflect"):
				actor.statuses.erase(active)
			Statuses.grant_cover(state, actor, target, form.id, amount, events)
			Shield.dropped(state, actor, target.position, events)


static func _form(id: String, label: String, help: String, kind: String, choices: Array,
		unavailable_reason: String, amount := -1) -> Dictionary:
	var form := {"id": id, "label": label, "help": help, "targeting": {"kind": kind}, "choices": choices,
		"unavailable_reason": unavailable_reason, "primary": "steady" if amount < 0 else "amount"}
	if amount >= 0:
		form["amount"] = amount
	if kind == "automatic":
		form["selection"] = "first"
	return form


static func _heroes(state: Dictionary, actor: Dictionary, include_self: bool) -> Array:
	return Board.occupants(state, {"teams": ["heroes"]}).filter(func(hero: Dictionary) -> bool:
		return (include_self or hero.id != actor.id) and Board.allied(state, actor, hero) \
			and Board.deployed_hero(state, hero) and not hero.has("summoner_id") \
			and not Board.capable(state, hero, "minion"))


static func _damageable_opponents(state: Dictionary, actor: Dictionary) -> Array:
	return Board.occupants(state, {"capabilities": ["damageable"]}).filter(func(target: Dictionary) -> bool:
		return Board.opponents(state, actor, target))


static func _choice(state: Dictionary, target: Dictionary) -> Dictionary:
	return {"id": target.id, "label": Board.display_name(state, target), "position": target.position}


static func _entity_choices(state: Dictionary, candidates: Array) -> Array:
	return candidates.map(func(target: Dictionary) -> Dictionary: return _choice(state, target))


static func _primary_kind(direct: bool) -> String:
	return "entity" if direct else "automatic"


static func _nearest_primary_choices(actor: Dictionary, choices: Array, direct: bool) -> Array:
	if direct:
		return choices
	var nearest := Board.nearest(actor, choices, true)
	return [] if nearest.is_empty() else [nearest]


static func _wounded_heroes(state: Dictionary, actor: Dictionary) -> Array:
	return _heroes(state, actor, true).filter(func(hero: Dictionary) -> bool:
		return hero.hp < hero.max_hp and Board.capable(state, hero, "healable"))


static func _mending_blast(state: Dictionary, actor: Dictionary, id: String, amount: int, direct: bool) -> Dictionary:
	var choices := _entity_choices(state, _wounded_heroes(state, actor))
	var help := "Heal a chosen wounded hero (including yourself) for %d HP." if direct \
		else "Heal the nearest wounded hero (including yourself) for %d HP."
	return _form(id, "Mending Blast", help % amount, _primary_kind(direct),
		_nearest_primary_choices(actor, choices, direct), "no wounded hero", amount)


static func _shove_choices(state: Dictionary, actor: Dictionary, safety_distance: bool) -> Array:
	var choices: Array = []
	for target: Dictionary in Board.occupants(state, {"objects": not safety_distance}):
		if target.id == actor.id or target.position == actor.position:
			continue
		if safety_distance:
			if Board.distance(actor.position, target.position) != 2 or not Board.allied(state, actor, target) \
					or not Board.capable(state, target, "pullable"):
				continue
		elif not Board.capable(state, target, "pushable"):
			continue
		var direction := Board.dominant_step(actor.position, target.position)
		var destination: Vector2i = target.position + direction
		if Board.can_enter(state, destination):
			var choice := _choice(state, target)
			choice["direction"] = direction
			choice["destination"] = destination
			choices.append(choice)
	return choices


static func _clear_jump(state: Dictionary, actor: Dictionary, id: String, direct: bool) -> Dictionary:
	var help := "Jump to the nearest open tile beside a chosen opponent, without swapping." if direct \
		else "Jump to the nearest open neighbor of the furthest opponent, without swapping."
	var form := _form(id, "Clear Jump", help, _primary_kind(direct), [], "movement blocked")
	if not Board.capable(state, actor, "mobile") or Movement.voluntary_blocked(state, actor) \
			or not Statuses.ids_with_handler(state, actor, "stop_move").is_empty():
		return form
	var opponents := Board.occupants(state, {}).filter(func(target: Dictionary) -> bool:
		return Board.opponents(state, actor, target))
	form["unavailable_reason"] = "no living opponent"
	if opponents.is_empty():
		return form
	form["unavailable_reason"] = "no open landing beside an opponent" if direct \
		else "no open landing beside the furthest opponent"
	# The autonomous form checks the furthest opponent even if another has a landing.
	if not direct:
		opponents = [_furthest_opponent(actor, opponents)]
	for opponent: Dictionary in opponents:
		var choice := _jump_choice(state, actor, opponent)
		if not choice.is_empty():
			form.choices.append(choice)
	return form


static func _furthest_opponent(actor: Dictionary, opponents: Array) -> Dictionary:
	var furthest: Dictionary = {}
	var furthest_distance := -1
	for target: Dictionary in opponents:
		var distance := Board.distance(actor.position, target.position)
		if distance > furthest_distance or (distance == furthest_distance and target.id < furthest.id):
			furthest = target
			furthest_distance = distance
	return furthest


static func _jump_choice(state: Dictionary, actor: Dictionary, opponent: Dictionary) -> Dictionary:
	var shortest := 2147483647
	var destination: Vector2i = actor.position
	for direction: Vector2i in Board.DIRECTIONS:
		var landing: Vector2i = opponent.position + direction
		var distance := Board.distance(actor.position, landing)
		if distance > 0 and distance < shortest and Board.can_enter(state, landing):
			shortest = distance
			destination = landing
	if destination == actor.position:
		return {}
	var choice := _choice(state, opponent)
	choice["destination"] = destination
	return choice


static func _unpick_the_stitch(state: Dictionary, actor: Dictionary, id: String, amount: int) -> Dictionary:
	var choices: Array = []
	for target: Dictionary in _damageable_opponents(state, actor):
		if Board.distance(actor.position, target.position) == 1:
			var choice := _choice(state, target)
			choice["missing_hp"] = target.max_hp - target.hp
			choice["encounter_index"] = choices.size()
			choices.append(choice)
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.encounter_index < b.encounter_index if a.missing_hp == b.missing_hp else a.missing_hp > b.missing_hp)
	var form := _form(id, "Unpick the Stitch", "Deal %d damage to an adjacent opponent instead of healing." % amount,
		"entity", choices, "no adjacent damageable opponent", amount)
	form["selection"] = "first"
	return form


static func _cut_the_wire(state: Dictionary, actor: Dictionary, id: String, direct: bool) -> Dictionary:
	var choices: Array = []
	for target: Dictionary in Board.occupants(state, {}):
		if not Board.allied(state, actor, target) or Board.distance(actor.position, target.position) > 2:
			continue
		var holds := Statuses.ids_with_handler(state, target, "block_voluntary_move")
		holds.append_array(Statuses.ids_with_handler(state, target, "stop_move"))
		var sticky := not Statuses.alchemy_status(target, BOOT_TOFFEE).is_empty()
		if not holds.is_empty() or sticky:
			var choice := _choice(state, target)
			choice["holds"] = holds
			choice["sticky"] = sticky
			choices.append(choice)
	var help := "Free a chosen friendly character within two tiles from movement holds, including yourself." if direct \
		else "Free the nearest friendly character within two tiles from movement holds, including yourself."
	return _form(id, "Cut the Wire", help, _primary_kind(direct),
		_nearest_primary_choices(actor, choices, direct), "no friendly character held in reach")


static func _release_holds(state: Dictionary, actor: Dictionary, target: Dictionary, choice: Dictionary,
		events: Array) -> void:
	var cleared: Array[String] = []
	for id: String in choice.holds:
		if target.statuses.erase(id):
			cleared.append(id)
	if choice.sticky and Statuses.clear_alchemy(target, BOOT_TOFFEE):
		cleared.append(BOOT_TOFFEE)
	Board.event(events, "status", "Cut the Wire frees %s from movement holds." % Board.display_name(state, target),
		{"unit_id": actor.id, "target_id": target.id, "status_ids": cleared, "removed": true})


static func _shove(state: Dictionary, actor: Dictionary, target: Dictionary, choice: Dictionary, label: String,
		events: Array) -> void:
	if Movement.blocks_forced(state, target, events):
		events.back()["resisted_target_id"] = target.id
		return
	var origin: Vector2i = target.position
	target.position = Movement.forced_destination(state, target, choice.destination, choice.direction, events)
	Board.event(events, "push", "%s pushes %s from %s to %s." % [label, Board.display_name(state, target),
		Board.coordinate(origin), Board.coordinate(target.position)],
		{"unit_id": actor.id, "target_id": target.id, "from_position": origin, "position": target.position})
	Shield.retrieve(state, target, events)


static func _jump(state: Dictionary, actor: Dictionary, opponent: Dictionary, landing: Vector2i,
		events: Array) -> void:
	var origin: Vector2i = actor.position
	actor.position = landing
	Board.event(events, "move", "Clear Jump: %s jumps from %s to %s, beside %s." % [
		Board.display_name(state, actor), Board.coordinate(origin), Board.coordinate(landing),
		Board.display_name(state, opponent)], {"unit_id": actor.id, "target_id": opponent.id,
		"from_position": origin, "position": landing})
	Shield.retrieve(state, actor, events)


static func _report_idle(state: Dictionary, actor: Dictionary, effect: String, label: String, reason: String,
		events: Array) -> void:
	if Upgrades.amount(state, actor, effect) > 0:
		Board.event(events, "perk_idle", "%s: %s." % [label, reason], {"unit_id": actor.id, "upgrade_effect": effect})
