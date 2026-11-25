extends RefCounted
## Fitting lifecycle shared by combat, objectives, and the alternate effects.

const Board = preload("res://rules/board.gd")
const RIVETS := "reinforced_rivets"


static func source(wearer: Dictionary) -> String:
	return wearer.get("fitted_by", "") if Board.alive(wearer) else ""


static func apply(wearer: Dictionary, smith_id: String, rivets: int) -> void:
	wearer["fitted_by"] = smith_id
	if rivets > 0:
		wearer.statuses[RIVETS] = {"source_id": smith_id, "amount": rivets}


static func clear(wearer: Dictionary) -> void:
	wearer.erase("fitted_by")
	var statuses: Dictionary = wearer.get("statuses", {})
	statuses.erase(RIVETS)
