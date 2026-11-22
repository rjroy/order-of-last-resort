extends RefCounted

const Board = preload("res://rules/board.gd")
const Statuses = preload("res://rules/statuses.gd")


static func heal(state: Dictionary, actor: Dictionary, target: Dictionary, amount: int, events: Array,
		cause := "") -> void:
	amount = Statuses.healing_amount(state, target, amount, events)
	var restored := mini(amount, target.max_hp - target.hp)
	target.hp += restored
	_heal_event(state, actor, target, restored, events, cause)


@warning_ignore("integer_division")
static func split_heal(state: Dictionary, actor: Dictionary, amount: int, events: Array) -> void:
	var party: Array = state.get("party", [])
	if party.is_empty():
		party = state.units.map(func(unit: Dictionary) -> String: return unit.id)
	var teammates: Array = []
	for id in party:
		var unit := Board.entity(state, id)
		if id != actor.id and Board.alive(unit) \
				and Board.team(state, unit) == Board.team(state, actor) \
				and Board.capable(state, unit, "commandable") \
				and not Board.capable(state, unit, "minion") and not unit.has("summoner_id"):
			teammates.append(unit)
	if teammates.is_empty():
		Board.event(events, "heal", "Me or You: there are no other living teammates to heal.",
			{"unit_id": actor.id, "amount": 0})
		return
	var share: int = amount / teammates.size()
	var remainder := amount % teammates.size()
	for index in range(teammates.size()):
		var unit: Dictionary = teammates[index]
		var allocation := share + int(index < remainder)
		if allocation > 0:
			heal(state, actor, unit, allocation, events)


static func _heal_event(state: Dictionary, actor: Dictionary, target: Dictionary, amount: int, events: Array,
		cause: String) -> void:
	var actor_name := Board.display_name(state, actor)
	var target_name := Board.display_name(state, target)
	var data := {"unit_id": actor.id, "target_id": target.id, "amount": amount}
	if not cause.is_empty() or (amount == 0 and target.hp < target.max_hp):
		Board.event(events, "heal", "%s restores %d HP to %s." % [
			cause if not cause.is_empty() else actor_name, amount, target_name], data)
	else:
		Board.authored_event(state, events, "heal", "heal" if amount > 0 else "heal_full",
			{"actor": actor_name, "target": target_name, "amount": amount}, data)
