extends RefCounted

const Board = preload("res://rules/board.gd")


static func position(actor: Dictionary) -> Variant:
	return actor.get("shield_position")


static func available(actor: Dictionary, ability_id: String) -> bool:
	return not actor.has("shield_position") or ability_id not in ["knight_aura", "knight_shield_throw"]


static func can_retrieve(actor: Dictionary) -> bool:
	return actor.has("shield_position") and Board.distance(actor.position, actor.shield_position) <= 1


static func dropped(state: Dictionary, actor: Dictionary, impact: Vector2i, events: Array) -> void:
	actor["shield_position"] = impact
	Board.event(events, "shield_drop", "%s's shield lands at %s." % [
		Board.display_name(state, actor), Board.coordinate(impact)],
		{"unit_id": actor.id, "position": impact})


static func retrieve(state: Dictionary, actor: Dictionary, events: Array) -> void:
	if not can_retrieve(actor):
		return
	var at: Vector2i = actor.shield_position
	actor.erase("shield_position")
	Board.event(events, "shield_retrieve", "%s retrieves the shield at %s." % [
		Board.display_name(state, actor), Board.coordinate(at)], {"unit_id": actor.id, "position": at})
