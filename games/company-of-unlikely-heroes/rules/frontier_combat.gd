extends RefCounted

const Board = preload("res://rules/board.gd")
const BONUS_LABELS := {"damage": "attack damage", "reduction": "damage reduction", "movement": "movement steps"}


static func traits(state: Dictionary, actor: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trait_spec in Board.profile(state, actor).get("traits", []):
		if trait_spec.kind == kind:
			result.append(trait_spec)
	return result


static func lend_armor(state: Dictionary, events: Array) -> void:
	for unit in state.units:
		unit.erase("borrowed_armor")
	for lender in state.units:
		if not Board.alive(lender) or traits(state, lender, "borrowed_armor").is_empty():
			continue
		var allies := Board.occupants(state, {"teams": [Board.team(state, lender)]})
		var borrower := Board.nearest(lender, allies)
		if not borrower.is_empty():
			borrower["borrowed_armor"] = lender.id
			Board.event(events, "borrowed_armor", "%s lends armor to %s for the first hit this round." % [
				Board.display_name(state, lender), Board.display_name(state, borrower)],
				{"unit_id": lender.id, "target_id": borrower.id})


static func mark_corpse_bell(state: Dictionary, fallen: Dictionary, events: Array) -> void:
	var bell: Dictionary = state.objective.get("corpse_bell", {})
	if bell.is_empty() or bell.has("due_round") or bell.get("spent", false) \
			or Board.team(state, fallen) != state.objective.get("team", "enemies"):
		return
	if not Board.corpses(state, {}).any(func(corpse: Dictionary) -> bool: return corpse.id == fallen.id):
		return
	bell["corpse_id"] = fallen.id
	bell["position"] = fallen.position
	bell["due_round"] = state.round + 1
	Board.event(events, "corpse_bell_marked", "The bell will raise a soldier at %s at the end of round %d if clear." % [
		Board.coordinate(fallen.position), bell.due_round], {"position": fallen.position, "round": bell.due_round})


static func ring_corpse_bell(state: Dictionary, events: Array) -> void:
	var bell: Dictionary = state.objective.get("corpse_bell", {})
	if bell.get("due_round", -1) != state.round:
		return
	bell["spent"] = true
	var cell: Vector2i = bell.position
	var corpse := Board.entity(state, bell.get("corpse_id", ""))
	if corpse.get("position") != cell \
			or not Board.corpses(state, {}).any(func(candidate: Dictionary) -> bool: return candidate.id == corpse.get("id", "")):
		Board.event(events, "corpse_bell_blocked", "The bell cannot raise the lost corpse at %s." % Board.coordinate(cell),
			{"position": cell})
		return
	if not Board.is_vacant(state, cell):
		Board.event(events, "corpse_bell_blocked", "The bell is blocked at %s." % Board.coordinate(cell), {"position": cell})
		return
	var character: String = bell.character
	var profile := Board.profile(state, {"character_id": character})
	var maximum := int(profile.get("max_hp", 1))
	var id := "corpse_bell_risen"
	while not Board.entity(state, id).is_empty():
		id += "_"
	corpse["corpse_consumed"] = true
	state.units.append({"id": id, "character_id": character, "position": cell,
		"statuses": {}, "hp": maximum, "max_hp": maximum})
	Board.event(events, "corpse_bell_raised", "The bell raises a soldier at %s." % Board.coordinate(cell),
		{"unit_id": id, "position": cell})


static func attack_damage(state: Dictionary, actor: Dictionary, damage: int, events: Array) -> int:
	var amount := damage + ally_death_bonus(state, actor, "damage")
	if Board.alive(actor):
		for trait_spec in traits(state, actor, "health_damage_bonus"):
			var full: bool = actor.hp == actor.max_hp
			if (trait_spec.condition == "full" and full) \
					or (trait_spec.condition == "wounded" and actor.hp < actor.max_hp):
				var bonus := int(trait_spec.damage)
				amount += bonus
				Board.event(events, "health_damage_bonus", "%s gains +%d attack damage while %s." % [
					Board.display_name(state, actor), bonus, trait_spec.condition],
					{"unit_id": actor.id, "amount": bonus, "condition": trait_spec.condition})
	for ally in _adjacent_allies(state, actor):
		for trait_spec in traits(state, ally, "adjacent_damage_bonus"):
			if trait_spec.benefits != actor.character_id:
				continue
			var bonus := int(trait_spec.damage)
			amount += bonus
			Board.event(events, "adjacent_damage_bonus", "%s adds %d damage to %s’s attack." % [
				Board.display_name(state, ally), bonus, Board.display_name(state, actor)],
				{"unit_id": ally.id, "target_id": actor.id, "amount": bonus})
	return amount


static func heal_on_death(state: Dictionary, fallen: Dictionary, events: Array) -> void:
	for trait_spec in traits(state, fallen, "death_heal"):
		for ally in state.units:
			if ally.id == fallen.id or not Board.alive(ally) \
					or Board.team(state, ally) != Board.team(state, fallen) or ally.hp >= ally.max_hp:
				continue
			var restored := mini(int(trait_spec.amount), int(ally.max_hp) - int(ally.hp))
			ally.hp += restored
			Board.event(events, "heal", "%s's last favor restores %d HP to %s." % [
				Board.display_name(state, fallen), restored, Board.display_name(state, ally)],
				{"unit_id": fallen.id, "source_id": fallen.id, "target_id": ally.id, "amount": restored})


static func reduce_damage(state: Dictionary, target: Dictionary, damage: int, events: Array,
		unimproved: Dictionary = {}) -> int:
	if damage <= 0:
		return 0
	var amount := damage
	for ally in _adjacent_allies(state, target):
		for trait_spec in traits(state, ally, "adjacent_guard"):
			if trait_spec.protects != target.character_id:
				continue
			var prevented := mini(amount, int(trait_spec.reduction))
			amount -= prevented
			if not unimproved.is_empty():
				unimproved.amount = maxi(0, int(unimproved.amount) - int(trait_spec.reduction))
			Board.event(events, "adjacent_guard", "%s shields %s from %d damage." % [
				Board.display_name(state, ally), Board.display_name(state, target), prevented],
				{"unit_id": ally.id, "target_id": target.id, "amount": prevented})
			if amount == 0:
				return 0
	# Bandit armor blunts heavier hits but must not make a party with only
	# one-damage attacks unable to finish the survivor. Shieldbearers can
	# still absorb a hit completely because their formation can be broken.
	var protection := ally_death_bonus(state, target, "reduction")
	if not unimproved.is_empty() and unimproved.amount > 0:
		unimproved.amount = maxi(1, int(unimproved.amount) - protection)
	var armor := mini(amount - 1, protection)
	if armor > 0:
		Board.event(events, "ally_death_guard", "%s’s fallen allies harden their guard, preventing %d damage." % [
			Board.display_name(state, target), armor],
			{"unit_id": target.id, "target_id": target.id, "amount": armor})
	return amount - armor


static func ally_death_bonus(state: Dictionary, actor: Dictionary, stat: String) -> int:
	var total := 0
	for trait_spec in traits(state, actor, "ally_death_bonus"):
		if trait_spec.has(stat):
			total += _scaled_bonus(trait_spec, stat, _fallen_count(state, actor, trait_spec))
	return total


static func announce_ally_death(state: Dictionary, fallen: Dictionary, events: Array) -> void:
	var team := Board.team(state, fallen)
	for survivor in state.units:
		if not Board.alive(survivor) or Board.team(state, survivor) != team:
			continue
		for trait_spec in traits(state, survivor, "ally_death_bonus"):
			if fallen.get("character_id", "") not in trait_spec.allies:
				continue
			var count := _fallen_count(state, survivor, trait_spec)
			for stat: String in BONUS_LABELS:
				if not trait_spec.has(stat):
					continue
				var total := _scaled_bonus(trait_spec, stat, count)
				var gain := total - _scaled_bonus(trait_spec, stat, count - 1)
				if gain > 0:
					Board.event(events, "ally_death_bonus", "%s falls. %s gains +%d %s (+%d total)." % [
						Board.display_name(state, fallen), Board.display_name(state, survivor),
						gain, BONUS_LABELS[stat], total], {"unit_id": survivor.id, "target_id": survivor.id,
						"source_id": fallen.id, "stat": stat, "amount": gain, "total": total})


static func _adjacent_allies(state: Dictionary, actor: Dictionary) -> Array:
	if not actor.has("character_id") or not Board.alive(actor):
		return []
	var team := Board.team(state, actor)
	return Board.occupants(state, {"teams": [team]}).filter(func(ally: Dictionary) -> bool:
		return ally.id != actor.id and Board.distance(actor.position, ally.position) == 1)


static func _fallen_count(state: Dictionary, actor: Dictionary, trait_spec: Dictionary) -> int:
	var count := 0
	var team := Board.team(state, actor)
	for ally in state.units:
		if ally.id != actor.id and not Board.alive(ally) and ally.character_id in trait_spec.allies \
				and Board.team(state, ally) == team:
			count += 1
	return count


static func _scaled_bonus(trait_spec: Dictionary, stat: String, fallen_count: int) -> int:
	var amount := int(trait_spec[stat]) * fallen_count
	if stat == "reduction" and trait_spec.has("max_reduction"):
		amount = mini(amount, int(trait_spec.max_reduction))
	return amount
