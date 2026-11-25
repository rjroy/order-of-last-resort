extends RefCounted

const Board = preload("res://rules/board.gd")
const FittingState = preload("res://rules/fitting_state.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")
const Upgrades = preload("res://rules/upgrades.gd")
const RECOVER_EVENT := "recover"
const JELLY_KNEES := "jelly_knees"
const INSPIRED := "inspired"
const STEADY_HANDS := "steady_hands"
const NEXT_HIT := ["laughing_fit", "borrowed_courage", FittingState.RIVETS,
	"keep_your_head_down", "lend_a_shield", STEADY_HANDS]
enum Application { REJECTED, APPLIED, RESISTED }
const REWARD_STATUSES := {
	"borrowed_courage": {"label": "Borrowed Courage", "handler": "reduce_next_hit", "expiry": "source_turn_start"},
	"body_double": {"label": "Body Double", "handler": "body_double", "expiry": "actor_turn_start"},
	"laughing_fit": {"label": "Dropped guard", "handler": "increase_next_hit", "expiry": "actor_turn_start"},
	"heckler": {"label": "Heckling the Bard", "handler": "heckler", "expiry": "consume_attack"},
	FittingState.RIVETS: {"label": "Reinforced Rivets", "handler": "reduce_next_hit", "expiry": "fitting_end"},
	INSPIRED: {"label": "Inspired", "handler": "improve_next_ability"},
	"keep_your_head_down": {"label": "Keep Your Head Down", "handler": "reduce_next_hit", "expiry": "actor_turn_end"},
	"lend_a_shield": {"label": "Lend a Shield", "handler": "reduce_next_hit", "expiry": "actor_turn_end"},
	STEADY_HANDS: {"label": "Steady Hands", "handler": "reduce_next_hit", "expiry": "actor_turn_start"},
}


static func definition(state: Dictionary, id: String) -> Dictionary:
	return REWARD_STATUSES.get(id, state.catalog.defs.statuses.get(id, {}))


static func alchemy_status(unit: Dictionary, id: String) -> Dictionary:
	return unit.get("alchemy_statuses", {}).get(id, {})


static func has_skip(state: Dictionary, unit: Dictionary) -> bool:
	return not alchemy_status(unit, JELLY_KNEES).is_empty() or not ids_with_handler(state, unit, "skip_action").is_empty()


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
	if not alchemy_status(unit, JELLY_KNEES).is_empty():
		return true
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
			if statuses[id].has("immune_through_round"):
				result.append(spec.params.immune_label)
			else:
				result.append(spec.label)
	if active_handler in ["", "skip_action"] and not alchemy_status(unit, JELLY_KNEES).is_empty():
		result.append("Jelly Knees: Down")
	if active_handler.is_empty():
		for id in unit.get("alchemy_statuses", {}):
			if id == JELLY_KNEES:
				continue
			var spec := _alchemy_definition(id)
			result.append("%s: %s (through round %d)" % [spec.label, spec.description, alchemy_status(unit, id).expires_after_round])
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
			if state.round > int(entry.get("immune_through_round", state.round)):
				unit.statuses.erase(id)
		for id in unit.get("alchemy_statuses", {}).keys():
			if state.round > int(alchemy_status(unit, id).get("expires_after_round", state.round)):
				clear_alchemy(unit, id)


static func consume_skips(state: Dictionary, unit: Dictionary, events: Array) -> void:
	var ids := ids_with_handler(state, unit, "skip_action")
	var jelly := clear_alchemy(unit, JELLY_KNEES)
	_consume_skips(state, unit, events, ids, jelly)


static func consume_voluntary_move_block(state: Dictionary, unit: Dictionary, events: Array) -> bool:
	var ids := ids_with_handler(state, unit, "block_voluntary_move")
	if ids.is_empty():
		return false
	var id := ids[0]
	unit.statuses.erase(id)
	Board.event(events, "status", "%s cannot move (%s)." % [Board.display_name(state, unit), definition(state, id).label],
		{"unit_id": unit.id, "target_id": unit.id, "status_id": id, "consumed": true})
	return true


static func _consume_skips(state: Dictionary, unit: Dictionary, events: Array,
		ids: Array[String], jelly: bool) -> void:
	if ids.is_empty() and not jelly:
		return
	var event := RECOVER_EVENT
	var granted_laughing_fit := false
	var presentation_cause := ""
	var presentation_facing := 0
	for id in ids:
		var spec := definition(state, id)
		var params: Dictionary = spec.params
		if is_knockdown(state, id) and unit.statuses[id].get("presentation_cause") == "pull_recoil":
			presentation_cause = "pull_recoil"
			var direction: Variant = unit.statuses[id].get("presentation_facing")
			if (direction is int or direction is float) and absf(float(direction)) == 1.0:
				presentation_facing = int(direction)
		if params.get("skip_event") == "laugh_skip":
			var bard := Board.entity(state, unit.statuses[id].source_id)
			var bonus := Upgrades.amount(state, bard, "laughing_fit")
			if bonus > 0:
				unit.statuses["laughing_fit"] = {"source_id": bard.id, "amount": bonus}
				granted_laughing_fit = true
		var rounds: int = int(params.get("immunity_rounds", 0))
		if rounds > 0:
			# Immunity starts on the lost action and lasts through the next N entire rounds.
			unit.statuses[id]["immune_through_round"] = state.round + rounds
		else:
			unit.statuses.erase(id)
		if event == RECOVER_EVENT:
			event = params.get("skip_event", RECOVER_EVENT)
	_recover(state, unit, events, event, ids, jelly, presentation_cause, presentation_facing)
	if granted_laughing_fit:
		Board.event(events, "status", "Laughing Fit: %s drops their guard; the next hit deals +%d damage." % [
			Board.display_name(state, unit), unit.statuses.laughing_fit.amount],
			{"unit_id": unit.id, "status_id": "laughing_fit", "amount": unit.statuses.laughing_fit.amount})


static func consume_objective_skip(state: Dictionary, unit: Dictionary, events: Array) -> bool:
	if not has_skip(state, unit):
		return false
	consume_skips(state, unit, events)
	return true


static func _recover(state: Dictionary, unit: Dictionary, events: Array, event: String,
		ids: Array[String], jelly: bool, presentation_cause: String, presentation_facing: int) -> void:
	var data := {"unit_id": unit.id, "status_ids": ids}
	if jelly:
		data["reaction_id"] = JELLY_KNEES
	if not presentation_cause.is_empty():
		data["presentation_cause"] = presentation_cause
		if presentation_facing != 0:
			data["presentation_facing"] = presentation_facing
	Board.authored_event(state, events, "recover", event, {"actor": Board.display_name(state, unit)}, data)


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
		"reflect", "misdirect", "stop_move", "block_voluntary_move":
			return true
	return false


static func apply(state: Dictionary, target: Dictionary, id: String, source: Dictionary,
		events: Array = []) -> bool:
	return apply_result(state, target, id, source, events) == Application.APPLIED


static func apply_result(state: Dictionary, target: Dictionary, id: String, source: Dictionary,
		events: Array) -> Application:
	if not accepts(state, target, id, source):
		return Application.REJECTED
	if is_knockdown(state, id) and _resists_knockdown(state, target, events):
		return Application.RESISTED
	# Reapplying knockdown while already prone replaces its rules source, but
	# does not produce a second physical fall. Keep the existing optional pose
	# provenance so the eventual rise starts from the pose actually held.
	var presentation := {}
	if is_knockdown(state, id) and knocked_down(state, target):
		for previous in ids_with_handler(state, target, "skip_action"):
			var old: Dictionary = target.statuses[previous]
			if is_knockdown(state, previous) and old.get("presentation_cause") == "pull_recoil":
				presentation["presentation_cause"] = "pull_recoil"
				var direction: Variant = old.get("presentation_facing")
				if (direction is int or direction is float) and absf(float(direction)) == 1.0:
					presentation["presentation_facing"] = int(direction)
				break
	target.statuses[id] = {"source_id": source.id}
	target.statuses[id].merge(presentation)
	return Application.APPLIED


static func apply_alchemy(state: Dictionary, target: Dictionary, id: String, source: Dictionary, events: Array) -> bool:
	if not Board.alive(target) or (id == JELLY_KNEES and _resists_knockdown(state, target, events)):
		return false
	var entry := {"source_id": source.id}
	if id != JELLY_KNEES:
		entry["expires_after_round"] = state.round + int(not Reactions.ROUND_END.has(id))
	if not target.has("alchemy_statuses"):
		target["alchemy_statuses"] = {}
	target.alchemy_statuses[id] = entry
	return true


static func _resists_knockdown(state: Dictionary, target: Dictionary, events: Array) -> bool:
	return not knocked_down(state, target) and consume_alchemy(state, target, "stiff_upper_lip", "stays upright", events)


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


static func inspired(actor: Dictionary) -> bool:
	return actor.get("statuses", {}).has(INSPIRED)


static func grant_inspiration(state: Dictionary, source: Dictionary, target: Dictionary, events: Array) -> void:
	if inspired(target) or not Board.alive(target):
		return
	target.statuses[INSPIRED] = {"source_id": source.id}
	Board.event(events, "status", "%s inspires %s (improves their next performed ability)." % [
		Board.display_name(state, source), Board.display_name(state, target)],
		{"unit_id": source.id, "target_id": target.id, "status_id": INSPIRED})


static func grant_cover(state: Dictionary, source: Dictionary, target: Dictionary, status_id: String,
		amount: int, events: Array) -> void:
	target.statuses[status_id] = {"source_id": source.id, "amount": amount}
	var label: String = definition(state, status_id).label
	Board.event(events, "status", "%s: %s can absorb %d damage on their next hit through their next turn." % [
		label, Board.display_name(state, target), amount],
		{"unit_id": source.id, "target_id": target.id, "status_id": status_id, "amount": amount})


static func clear_fitting_effects(unit: Dictionary) -> void:
	for id in [INSPIRED, "keep_your_head_down", "lend_a_shield", STEADY_HANDS]:
		unit.statuses.erase(id)


static func grant_steady_hands(state: Dictionary, actor: Dictionary, reason: String, events: Array) -> void:
	actor.statuses[STEADY_HANDS] = {"source_id": actor.id, "amount": 1}
	Board.event(events, "status", "%s: %s gains Steady Hands (1 less damage on the next hit before their next turn)." % [
		reason, Board.display_name(state, actor)],
		{"unit_id": actor.id, "status_id": STEADY_HANDS, "amount": 1})


static func hit_amount(state: Dictionary, target: Dictionary, damage: int, events: Array,
		unimproved: Dictionary = {}) -> int:
	if damage <= 0:
		return damage
	var amount := damage
	for id in NEXT_HIT:
		if not target.get("statuses", {}).has(id):
			continue
		var increases: bool = id == "laughing_fit"
		var bonus: int = target.statuses[id].amount
		var applied := bonus if increases else mini(bonus, amount)
		var label: String = "Laughing Fit" if increases else definition(state, id).label
		amount += applied if increases else -applied
		if not unimproved.is_empty() and unimproved.amount > 0:
			unimproved.amount = maxi(0, int(unimproved.amount) + (bonus if increases else -bonus))
		target.statuses.erase(id)
		Board.event(events, "status", "%s %s the hit on %s by %d." % [
			label, "increases" if increases else "reduces", Board.display_name(state, target), applied],
			{"unit_id": target.id, "status_id": id, "amount": applied, "consumed": true})
	return amount


static func alchemy_hit_amount(state: Dictionary, source: Dictionary, target: Dictionary,
		damage: int, events: Array, unimproved: Dictionary = {}) -> int:
	if damage <= 0:
		return damage
	var range_to_source := Board.distance(source.position, target.position)
	var amount := damage
	var baseline: int = unimproved.get("amount", 0)
	var compare := baseline > 0
	if consume_alchemy(state, target, "thin_skinned", "takes 1 extra damage", events):
		amount += 1
		baseline += 1
	if range_to_source == 1 and consume_alchemy(state, target, "handle_with_care", "takes 1 extra damage", events):
		amount += 1
		baseline += 1
	if consume_alchemy(state, target, "emergency_crust", "absorbs 1 damage", events):
		amount -= 1
		baseline -= 1
	if amount > 0 and range_to_source > 1 and consume_alchemy(state, target, "duck", "avoids 1 damage", events):
		amount -= 1
		baseline -= 1
	if amount >= target.hp and consume_alchemy(state, target, "pocket_paramedic", "survives at 1 HP", events):
		amount = target.hp - 1
		baseline = mini(baseline, amount)
	if compare:
		unimproved.amount = maxi(0, baseline)
	return amount


static func healing_amount(state: Dictionary, target: Dictionary, amount: int, events: Array) -> int:
	if amount <= 0 or target.hp >= target.max_hp:
		return amount
	if consume_alchemy(state, target, "medicinal_aftertaste", "gets 1 extra healing", events):
		amount += 1
	if consume_alchemy(state, target, "no_refills", "gets 1 less healing", events):
		amount -= 1
	return amount


static func consume_alchemy(state: Dictionary, target: Dictionary, id: String, effect: String,
		events: Array) -> bool:
	if not clear_alchemy(target, id):
		return false
	Board.event(events, "status", "%s: %s %s." % [_alchemy_definition(id).label,
		Board.display_name(state, target), effect],
		{"unit_id": target.id, "target_id": target.id, "status_id": id, "reaction_id": id, "consumed": true})
	return true


static func clear_alchemy(unit: Dictionary, id: String) -> bool:
	var statuses: Dictionary = unit.get("alchemy_statuses", {})
	if not statuses.erase(id):
		return false
	if statuses.is_empty():
		unit.erase("alchemy_statuses")
	return true


static func _alchemy_definition(id: String) -> Dictionary:
	return Reactions.POOLS.beneficial.get(id, Reactions.POOLS.harmful.get(id, {}))


static func heckled_target(state: Dictionary, actor: Dictionary) -> Dictionary:
	if not actor.get("statuses", {}).has("heckler"):
		return {}
	var bard := Board.entity(state, actor.statuses.heckler.source_id)
	return bard if Board.alive(bard) else {}
