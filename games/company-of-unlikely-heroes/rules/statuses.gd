extends RefCounted

const Board = preload("res://rules/board.gd")
const Upgrades = preload("res://rules/upgrades.gd")
const RECOVER_EVENT := "recover"
const REWARD_STATUSES := {
	"borrowed_courage": {"label": "Borrowed Courage", "handler": "reduce_next_hit", "expiry": "source_turn_start"},
	"body_double": {"label": "Body Double", "handler": "body_double", "expiry": "actor_turn_start"},
	"laughing_fit": {"label": "Dropped guard", "handler": "increase_next_hit", "expiry": "actor_turn_start"},
	"heckler": {"label": "Heckling the Bard", "handler": "heckler", "expiry": "consume_attack"},
}


static func definition(state: Dictionary, id: String) -> Dictionary:
	return REWARD_STATUSES.get(id, state.catalog.defs.statuses.get(id, {}))


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


static func begin_turn(state: Dictionary, actor: Dictionary) -> void:
	expire(state, actor, "actor_turn_start")
	if Upgrades.amount(state, actor, "borrowed_courage") == 0:
		return
	for unit in state.units:
		if unit.statuses.get("borrowed_courage", {}).get("source_id") == actor.id:
			unit.statuses.erase("borrowed_courage")


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
		var spec := definition(state, id)
		var params: Dictionary = spec.params
		if params.get("skip_event") == "laugh_skip":
			var bard := Board.entity(state, unit.statuses[id].source_id)
			var bonus := Upgrades.amount(state, bard, "laughing_fit")
			if bonus > 0:
				unit.statuses["laughing_fit"] = {"source_id": bard.id, "amount": bonus}
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
	if unit.statuses.has("laughing_fit"):
		Board.event(events, "status", "Laughing Fit: %s drops their guard; the next hit deals +%d damage." % [
			Board.display_name(state, unit), unit.statuses.laughing_fit.amount],
			{"unit_id": unit.id, "status_id": "laughing_fit", "amount": unit.statuses.laughing_fit.amount})


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


static func misdirection_victim(state: Dictionary, attacker: Dictionary, rogue: Dictionary,
		exclude_id := "") -> Dictionary:
	var victim := _victim_at(state, attacker, exclude_id, 1)
	if victim.is_empty() and Upgrades.amount(state, rogue, "long_finger") > 0:
		return _victim_at(state, attacker, exclude_id, 2)
	return victim


static func _victim_at(state: Dictionary, attacker: Dictionary, exclude_id: String, distance: int) -> Dictionary:
	var candidates := Board.occupants(state, {})
	candidates = candidates.filter(func(candidate: Dictionary) -> bool:
		return candidate.id != attacker.id and candidate.id != exclude_id \
			and Board.distance(attacker.position, candidate.position) == distance)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return candidates[0] if not candidates.is_empty() else {}


static func misdirect_attack(state: Dictionary, attacker: Dictionary, target: Dictionary, events: Array) -> Dictionary:
	var ids := ids_with_handler(state, attacker, "misdirect")
	if ids.is_empty():
		return {"target": target, "bonus": 0}
	ids.sort()
	var rogue := Board.entity(state, attacker.statuses[ids[0]].source_id)
	var victim := misdirection_victim(state, attacker, rogue, target.id)
	expire(state, attacker, "consume_attack")
	if victim.is_empty():
		Board.authored_event(state, events, "misdirect", "misdirect_missing",
			{"actor": Board.display_name(state, attacker), "target": Board.display_name(state, target)},
			{"unit_id": attacker.id, "target_id": target.id, "status_id": ids[0]})
		return {"target": target, "bonus": 0}
	Board.authored_event(state, events, "misdirect", "misdirect_redirect",
		{"actor": Board.display_name(state, attacker), "target": Board.display_name(state, victim)},
		{"unit_id": attacker.id, "target_id": victim.id, "status_id": ids[0]})
	var bonus := Upgrades.amount(state, rogue, "cheap_shot")
	if bonus > 0:
		Board.event(events, "misdirect", "Cheap Shot adds %d damage to the redirected hit." % bonus,
			{"unit_id": rogue.id, "target_id": victim.id, "amount": bonus})
	return {"target": victim, "bonus": bonus}


static func guarding(state: Dictionary, unit: Dictionary) -> bool:
	return not ids_with_handler(state, unit, "reflect").is_empty()


static func guard_range(state: Dictionary, unit: Dictionary, status: Dictionary) -> int:
	return int(status.params.range) + Upgrades.amount(state, unit, "wide_guard")


static func reflect_attack(state: Dictionary, ward: Dictionary, events: Array) -> Dictionary:
	if not Board.capable(state, ward, "protectable"):
		return {"target": ward, "bonus": 0}
	for protector in state.units:
		if not Board.alive(protector):
			continue
		for id in ids_with_handler(state, protector, "reflect"):
			var spec := definition(state, id)
			var params: Dictionary = spec.params
			if Board.distance(protector.position, ward.position) > guard_range(state, protector, spec):
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
			var bonus := Upgrades.amount(state, protector, "shield_damage") if not recipient.is_empty() else 0
			if bonus > 0:
				Board.event(events, "reflect", "The improved shield adds %d reflected damage." % bonus,
					{"unit_id": protector.id, "target_id": recipient.id, "amount": bonus})
			return {"target": recipient, "bonus": bonus}
	return {"target": ward, "bonus": 0}


static func double_recipient(state: Dictionary, target: Dictionary, events: Array) -> Dictionary:
	if not target.get("statuses", {}).has("body_double"):
		return target
	var partner := Board.entity(state, target.statuses.body_double.partner_id)
	target.statuses.erase("body_double")
	if not Board.alive(partner):
		return target
	Board.event(events, "body_double", "Body Double redirects the attack on %s to %s." % [
		Board.display_name(state, target), Board.display_name(state, partner)],
		{"unit_id": target.id, "target_id": partner.id})
	return partner


static func hit_amount(state: Dictionary, target: Dictionary, damage: int, events: Array) -> int:
	if damage <= 0:
		return damage
	var amount := damage
	for id in ["laughing_fit", "borrowed_courage"]:
		if not target.get("statuses", {}).has(id):
			continue
		var bonus: int = target.statuses[id].amount
		var label := "Laughing Fit" if id == "laughing_fit" else "Borrowed Courage"
		amount += bonus if id == "laughing_fit" else -bonus
		target.statuses.erase(id)
		Board.event(events, "status", "%s %s the hit on %s by %d." % [
			label, "increases" if id == "laughing_fit" else "reduces", Board.display_name(state, target), bonus],
			{"unit_id": target.id, "status_id": id, "amount": bonus})
	return maxi(0, amount)


static func heckled_target(state: Dictionary, actor: Dictionary) -> Dictionary:
	if not actor.get("statuses", {}).has("heckler"):
		return {}
	var bard := Board.entity(state, actor.statuses.heckler.source_id)
	return bard if Board.alive(bard) else {}
