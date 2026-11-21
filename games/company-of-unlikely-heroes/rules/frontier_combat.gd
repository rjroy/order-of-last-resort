extends RefCounted

const Board = preload("res://rules/board.gd")
const BONUS_LABELS := {"damage": "attack damage", "reduction": "damage reduction", "movement": "movement steps"}


static func traits(state: Dictionary, actor: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trait_spec in Board.profile(state, actor).get("traits", []):
		if trait_spec.kind == kind:
			result.append(trait_spec)
	return result


static func attack_damage(state: Dictionary, actor: Dictionary, damage: int, events: Array) -> int:
	var amount := damage + ally_death_bonus(state, actor, "damage")
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


static func reduce_damage(state: Dictionary, target: Dictionary, damage: int, events: Array) -> int:
	if damage <= 0:
		return 0
	var amount := damage
	for ally in _adjacent_allies(state, target):
		for trait_spec in traits(state, ally, "adjacent_guard"):
			if trait_spec.protects != target.character_id:
				continue
			var prevented := mini(amount, int(trait_spec.reduction))
			amount -= prevented
			Board.event(events, "adjacent_guard", "%s shields %s from %d damage." % [
				Board.display_name(state, ally), Board.display_name(state, target), prevented],
				{"unit_id": ally.id, "target_id": target.id, "amount": prevented})
			if amount == 0:
				return 0
	# Bandit armor blunts heavier hits but must not make a party with only
	# one-damage attacks unable to finish the survivor. Shieldbearers can
	# still absorb a hit completely because their formation can be broken.
	var armor := mini(amount - 1, ally_death_bonus(state, target, "reduction"))
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
