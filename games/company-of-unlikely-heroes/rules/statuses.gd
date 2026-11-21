extends RefCounted

const Board = preload("res://rules/board.gd")
const RECOVER_EVENT := "recover"


static func definition(state: Dictionary, id: String) -> Dictionary:
	return state.catalog.defs.statuses.get(id, {})


static func ids_with_handler(state: Dictionary, unit: Dictionary, handler: String) -> Array[String]:
	var result: Array[String] = []
	var statuses: Dictionary = unit.get("statuses", {})
	for id in statuses:
		if definition(state, id).get("handler", "") == handler and not statuses[id].has("immune_through_round"):
			result.append(id)
	return result


static func is_knockdown(state: Dictionary, id: String) -> bool:
	var spec := definition(state, id)
	# The default recovery event means getting up. A different skip event can leave a unit upright.
	return spec.get("handler") == "skip_action" and spec.params.get("skip_event", RECOVER_EVENT) == RECOVER_EVENT


static func knocked_down(state: Dictionary, unit: Dictionary) -> bool:
	for id in ids_with_handler(state, unit, "skip_action"):
		if is_knockdown(state, id):
			return true
	return false


static func labels(state: Dictionary, unit: Dictionary, active_handler := "") -> PackedStringArray:
	var result: PackedStringArray = []
	var statuses: Dictionary = unit.get("statuses", {})
	var ids: Array = statuses.keys() if active_handler.is_empty() else ids_with_handler(state, unit, active_handler)
	for id in ids:
		var spec := definition(state, id)
		if not spec.is_empty():
			result.append(spec.params.immune_label if statuses[id].has("immune_through_round") else spec.label)
	return result


static func expire(state: Dictionary, unit: Dictionary, timing: String) -> void:
	for id in unit.statuses.keys():
		if definition(state, id).get("expiry", "") == timing:
			unit.statuses.erase(id)


static func expire_rounds(state: Dictionary) -> void:
	for unit in state.units:
		for id in unit.statuses.keys():
			var entry: Dictionary = unit.statuses[id]
			if entry.has("immune_through_round") and state.round > entry.immune_through_round:
				unit.statuses.erase(id)


static func consume_skips(state: Dictionary, unit: Dictionary, events: Array) -> void:
	var ids := ids_with_handler(state, unit, "skip_action")
	var event := RECOVER_EVENT
	for id in ids:
		var params: Dictionary = definition(state, id).params
		var rounds: int = int(params.get("immunity_rounds", 0))
		if rounds > 0:
			# Immunity starts on the lost action and lasts through the next N entire rounds.
			unit.statuses[id]["immune_through_round"] = state.round + rounds
		else:
			unit.statuses.erase(id)
		if event == RECOVER_EVENT:
			event = params.get("skip_event", RECOVER_EVENT)
	Board.authored_event(state, events, "recover", event, {"actor": Board.display_name(state, unit)},
		{"unit_id": unit.id, "status_ids": ids})


static func accepts(state: Dictionary, target: Dictionary, id: String, source: Dictionary) -> bool:
	# These statuses run and expire on character turns; objects do not take turns.
	if not target.has("character_id") or target.has("object_id") or not Board.alive(target):
		return false
	var spec := definition(state, id)
	match spec.get("handler", ""):
		"skip_action":
			return Board.capable(state, target, "recoverable") \
				and (not spec.params.has("immunity_rounds") or not target.statuses.has(id))
		"retarget":
			return Board.capable(state, target, "tauntable") and _accepts_source(state, source, spec.params)
		"reflect", "misdirect", "stop_move":
			return true
	return false


static func apply(state: Dictionary, target: Dictionary, id: String, source: Dictionary) -> bool:
	if not accepts(state, target, id, source):
		return false
	target.statuses[id] = {"source_id": source.id}
	return true


static func _accepts_source(state: Dictionary, source: Dictionary, params: Dictionary) -> bool:
	return Board.alive(source) and (not params.has("teams") or Board.team(state, source) in params.teams)


static func retarget(state: Dictionary, unit: Dictionary, id: String) -> Dictionary:
	if not unit.statuses.has(id):
		return {}
	var spec := definition(state, id)
	if spec.get("handler", "") != "retarget":
		return {}
	var source := Board.entity(state, unit.statuses[id].source_id)
	return source if source != unit and _accepts_source(state, source, spec.params) else {}


static func adjacent_victim(state: Dictionary, attacker: Dictionary, exclude_id := "") -> Dictionary:
	var candidates := Board.occupants(state, {})
	candidates = candidates.filter(func(candidate: Dictionary) -> bool:
		return candidate.id != attacker.id and candidate.id != exclude_id \
			and Board.distance(attacker.position, candidate.position) == 1)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return candidates[0] if not candidates.is_empty() else {}


static func misdirect_attack(state: Dictionary, attacker: Dictionary, target: Dictionary, events: Array) -> Dictionary:
	var ids := ids_with_handler(state, attacker, "misdirect")
	if ids.is_empty():
		return target
	ids.sort()
	var victim := adjacent_victim(state, attacker, target.id)
	expire(state, attacker, "consume_attack")
	if victim.is_empty():
		Board.authored_event(state, events, "misdirect", "misdirect_missing",
			{"actor": Board.display_name(state, attacker), "target": Board.display_name(state, target)},
			{"unit_id": attacker.id, "target_id": target.id, "status_id": ids[0]})
		return target
	Board.authored_event(state, events, "misdirect", "misdirect_redirect",
		{"actor": Board.display_name(state, attacker), "target": Board.display_name(state, victim)},
		{"unit_id": attacker.id, "target_id": victim.id, "status_id": ids[0]})
	return victim


static func attack_recipient(state: Dictionary, ward: Dictionary, events: Array) -> Dictionary:
	if not Board.capable(state, ward, "protectable"):
		return ward
	for protector in state.units:
		if not Board.alive(protector):
			continue
		for id in ids_with_handler(state, protector, "reflect"):
			var params: Dictionary = definition(state, id).params
			if Board.distance(protector.position, ward.position) > int(params.range):
				continue
			var candidates := Board.occupants(state, params)
			candidates = candidates.filter(func(candidate: Dictionary) -> bool:
				return Board.capable(state, candidate, "damageable"))
			var recipient := Board.nearest(ward, candidates)
			var data := {"unit_id": protector.id, "ward_id": ward.id, "status_id": id,
				"source_id": protector.statuses[id].source_id}
			var name := Board.display_name(state, protector)
			var ward_name := Board.display_name(state, ward)
			if recipient.is_empty():
				Board.authored_event(state, events, "reflect", "reflect_absorb",
					{"protector": name, "ward": ward_name}, data)
			else:
				data["target_id"] = recipient.id
				Board.authored_event(state, events, "reflect", "reflect_redirect",
					{"protector": name, "ward": ward_name, "target": Board.display_name(state, recipient)}, data)
			return recipient
	return ward
