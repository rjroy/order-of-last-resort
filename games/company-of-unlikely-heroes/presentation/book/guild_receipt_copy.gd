extends RefCounted
## Shared text for the outing receipt, board, debrief, and petitions.

const DESTINATION_OUTCOMES := {"victory": "won", "defeat": "lost", "forfeit": "forfeited"}


static func rows(receipt: Dictionary) -> Array[Dictionary]:
	if receipt.is_empty():
		return []
	var outcome: String = DESTINATION_OUTCOMES.get(receipt.get("destination_outcome", ""), "not reached")
	return [
		{"id": "Road", "note": " (%s)" % _count(int(receipt.get("road_wins", 0)), "win"),
			"value": _count(int(receipt.get("road_points", 0)), "point")},
		{"id": "Destination", "note": " (%s)" % outcome,
			"value": _count(int(receipt.get("destination_points", 0)), "point")},
		{"id": "Total", "note": "", "value": _count(int(receipt.get("points", 0)), "point")},
	]


static func summary(receipt: Dictionary) -> String:
	var segments := PackedStringArray()
	for item in rows(receipt):
		segments.append("%s: %s%s" % [item.id, item.value, item.note])
	return "  ·  ".join(segments)


static func _count(amount: int, unit: String) -> String:
	return "%d %s%s" % [amount, unit, "" if amount == 1 else "s"]
