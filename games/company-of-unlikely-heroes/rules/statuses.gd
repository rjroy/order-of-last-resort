extends RefCounted

const Board = preload("res://rules/board.gd")


static func definition(state: Dictionary, id: String) -> Dictionary:
	return state.catalog.defs.statuses.get(id, {})


static func ids_with_handler(state: Dictionary, unit: Dictionary, handler: String) -> Array[String]:
	var result: Array[String] = []
	for id in unit.get("statuses", {}):
		if definition(state, id).get("handler", "") == handler:
			result.append(id)
	return result


static func expire(state: Dictionary, unit: Dictionary, timing: String) -> void:
	for id in unit.statuses.keys():
		if definition(state, id).get("expiry", "") == timing:
			unit.statuses.erase(id)


static func accepts(state: Dictionary, target: Dictionary, id: String, source: Dictionary) -> bool:
	# These statuses run and expire on character turns; objects do not take turns.
	if not target.has("character_id") or target.has("object_id") or not Board.alive(target):
		return false
	var spec := definition(state, id)
	match spec.get("handler", ""):
		"skip_action":
			return Board.capable(state, target, "recoverable")
		"retarget":
			return Board.capable(state, target, "tauntable") and _accepts_source(state, source, spec.params)
		"reflect":
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
