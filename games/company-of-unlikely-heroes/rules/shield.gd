extends RefCounted

const Board = preload("res://rules/board.gd")
const ShieldWall = preload("res://rules/shield_wall.gd")


static func position(actor: Dictionary) -> Variant:
	return actor.get("shield_position")


static func blocked_reason(state: Dictionary, actor: Dictionary, ability_id: String) -> String:
	if ability_id not in ["knight_aura", "knight_shield_throw"]:
		return ""
	if actor.has("shield_position"):
		return "shield away"
	return "wall already standing" if ShieldWall.has_live_wall(state, actor) else ""


static func available(state: Dictionary, actor: Dictionary, ability_id: String) -> bool:
	return blocked_reason(state, actor, ability_id).is_empty()


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
