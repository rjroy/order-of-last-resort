extends RefCounted

const Board = preload("res://rules/board.gd")


static func heal(state: Dictionary, actor: Dictionary, target: Dictionary, amount: int, events: Array) -> void:
	var restored := mini(amount, target.max_hp - target.hp)
	target.hp += restored
	_heal_event(state, actor, target, restored, events)


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


static func _heal_event(state: Dictionary, actor: Dictionary, target: Dictionary, amount: int, events: Array) -> void:
	Board.authored_event(state, events, "heal", "heal" if amount > 0 else "heal_full",
		{"actor": Board.display_name(state, actor), "target": Board.display_name(state, target), "amount": amount},
		{"unit_id": actor.id, "target_id": target.id, "amount": amount})
