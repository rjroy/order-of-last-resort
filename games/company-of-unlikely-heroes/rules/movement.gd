extends RefCounted
## Movement reactions are consumed only when the original move could happen.

const Board = preload("res://rules/board.gd")
const Statuses = preload("res://rules/statuses.gd")


static func blocks_voluntary(state: Dictionary, unit: Dictionary, events: Array, forced_recipient := {}) -> bool:
	# Keep existing movement reactions ahead of a persistent block. A swap can
	# also fail when the other unit resists its forced half of the move.
	if Statuses.consume_alchemy(state, unit, "boot_toffee", "sticks in place instead of moving", events):
		return true
	if not forced_recipient.is_empty() and blocks_forced(state, forced_recipient, events):
		return true
	return Statuses.consume_voluntary_move_block(state, unit, events)


static func blocks_forced(state: Dictionary, unit: Dictionary, events: Array) -> bool:
	return Statuses.consume_alchemy(state, unit, "cork_soles", "resists the forced move", events)


static func forced_destination(state: Dictionary, unit: Dictionary, destination: Vector2i,
		direction: Vector2i, events: Array) -> Vector2i:
	if Statuses.alchemy_status(unit, "ball_bearings").is_empty():
		return destination
	var extra := destination + direction
	var can_extend := direction != Vector2i.ZERO and Board.is_vacant(state, extra)
	var effect := "slides an extra tile to " + Board.coordinate(extra) if can_extend \
		else "cannot slide an extra tile"
	Statuses.consume_alchemy(state, unit, "ball_bearings", effect, events)
	return extra if can_extend else destination
