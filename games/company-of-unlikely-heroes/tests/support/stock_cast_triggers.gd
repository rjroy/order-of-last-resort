extends RefCounted
## Interpret committed stock events by their subject, not by the action span
## which happens to contain them. Conditions use only the two committed states.
const Board = preload("res://rules/board.gd")


static func matches(trigger: Dictionary, event: Dictionary, before: Dictionary, after: Dictionary,
		enclosing_action: Dictionary = {}, positions: Dictionary = {}, later_events: Array = [],
		prior_events: Array = []) -> bool:
	var kind := str(trigger.type)
	var id := event_actor(trigger, event)
	var subject := _unit(before, id)
	var result := _unit(after, id)
	match kind:
		"action":
			var action: Dictionary = event.get("resolved_action", enclosing_action)
			return action.get("ability_id") == trigger.get("ability") \
				and action.get("unit_id") == id and _fallen_present(trigger, before) \
				and (not trigger.has("min_amount") or event.get("amount", 0) >= trigger.min_amount)
		"event":
			return event.get("type") == trigger.get("event") \
				and (not trigger.has("stat") or event.get("stat") == trigger.stat) \
				and (not trigger.has("action_ability") or enclosing_action.get("ability_id") == trigger.action_ability) \
				and (not trigger.has("action_character") or _unit(before, str(enclosing_action.get("unit_id", ""))).get("character_id") == trigger.action_character)
		"reserve_arrival":
			return event.get("type") == "reserve_arrival" and subject.is_empty() \
				and not result.is_empty()
		"sheep_flee", "sheep_entry":
			if event.get("type") != "move" or not enclosing_action.is_empty() \
					or event.get("position") == null or subject.is_empty():
				return false
			if kind == "sheep_flee":
				return true
			var pen: Array = before.get("objective", {}).get("pen", [])
			return positions.get(id) not in pen and event.position in pen
		"sheep_held":
			var pen: Array = before.get("objective", {}).get("pen", [])
			return event.get("type") == "wait" and not subject.is_empty() and not result.is_empty() \
				and positions.get(id) in pen and result.get("position") == positions.get(id) \
				and not later_events.any(func(later): return _changes_position(later, id))
		"wagon_advance":
			return event.get("type") == "move" and enclosing_action.is_empty() \
				and event.has("position") and not subject.is_empty() \
				and event.position != positions.get(id)
		"wagon_stall":
			return event.get("type") == "wait" and enclosing_action.is_empty() and event.has("position") \
				and not subject.is_empty() and not result.is_empty() \
				and event.position == positions.get(id) and result.get("position") == event.position
		"wagon_destroy":
			return event.get("type") == "defeat" and before.get("objective", {}).get("handler") == "wagon" \
				and before.objective.get("subject") == id and not result.is_empty() \
				and int(subject.get("hp", 0)) > 0 and int(result.get("hp", 0)) <= 0
		"troll_exit":
			return event.get("type") == "victory" and before.get("objective", {}).get("handler") == "leave_zone" \
				and before.objective.get("subject") == id and not result.is_empty() \
				and int(result.get("hp", 0)) > 0 and event.get("position") == result.get("position") \
				and not Board.in_zone(after, after.objective.zone, result.position)
		"captain_retreat":
			return event.get("type") == "move" and enclosing_action.get("unit_id") == id \
				and enclosing_action.get("ability_id") == "move" and not result.is_empty() \
				and int(result.get("last_retreat_round", -1)) == int(before.get("round", 0))
		"swift_quick_step":
			var source: Variant = enclosing_action.get("source_cell")
			var destination: Variant = enclosing_action.get("actor_cell")
			var bonus := _fallen_present({"requires_fallen": ["bandit_damage", "bandit_guard"]}, before)
			bonus = bonus or prior_events.any(func(previous): return previous.get("type") == "ally_death_bonus" \
				and previous.get("unit_id") == id and previous.get("stat") == "movement" \
				and int(previous.get("amount", 0)) > 0)
			return event.get("type") == "move" and enclosing_action.get("unit_id") == id \
				and enclosing_action.get("ability_id") == "move" and bonus \
				and source is Vector2i and destination is Vector2i and Board.distance(source, destination) > 1
		"chain_blast":
			if event.get("type") != "death_blast" or subject.is_empty() or int(subject.get("hp", 0)) <= 0:
				return false
			for index in later_events.size():
				var damage: Dictionary = later_events[index]
				var victim := str(damage.get("target_id", ""))
				if damage.get("type") != "damage" or damage.get("source_id") != id or victim == id \
						or _unit(before, victim).get("character_id") != "bomber" \
						or int(damage.get("amount", 0)) <= 0:
					continue
				for later: Dictionary in later_events.slice(index + 1):
					if later.get("type") == "death_blast" and later.get("unit_id") == victim:
						return true
			return false
	return false


static func event_actor(trigger: Dictionary, event: Dictionary) -> String:
	var id := str(event.get(trigger.actor_field, ""))
	if id.is_empty() and trigger.type == "action":
		id = str(event.get("source_id", event.get("unit_id", "")))
	return id


static func trace(event: Dictionary, positions: Dictionary) -> void:
	match event.get("type", ""):
		"move":
			positions[event.get("unit_id", "")] = event.get("position")
		"push", "pull", "repel":
			positions[event.get("target_id", "")] = event.get("position")
			if event.has("recoil_position"):
				positions[event.get("unit_id", "")] = event.recoil_position
		"swap":
			positions[event.get("unit_id", "")] = event.get("position")
			positions[event.get("target_id", "")] = event.get("target_position")
		"reserve_arrival":
			positions[event.get("unit_id", "")] = event.get("position")


static func _changes_position(event: Dictionary, id: String) -> bool:
	if event.get("type") == "move":
		return event.get("unit_id") == id
	if event.get("type") in ["push", "pull", "repel"]:
		return event.get("target_id") == id or (event.get("unit_id") == id and event.has("recoil_position"))
	if event.get("type") == "swap":
		return event.get("unit_id") == id or event.get("target_id") == id
	return false


static func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


static func _fallen_present(trigger: Dictionary, state: Dictionary) -> bool:
	var roles: Array = trigger.get("requires_fallen", [])
	if roles.is_empty():
		return true
	for unit: Dictionary in state.get("units", []):
		if unit.get("character_id") in roles and int(unit.get("hp", 0)) <= 0:
			return true
	return false
