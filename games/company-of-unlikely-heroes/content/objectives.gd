extends RefCounted
## Objective fields shared by catalog validation and snapshot construction.

const FIELDS := {
	"escort": {"subject": "subject", "destination": "location"},
	"leave_zone": {"subject": "subject", "zone": "start_zone"},
	"defeat_all": {"team": "optional_team"},
	"pressure_gate": {"plate": "location", "gate": "location", "exit": "location"},
	"survive": {"turns": "positive_integer"},
	"herd_sheep": {"subjects": "subjects", "pen": "zone"},
	"collapsing_bridge": {"exit": "location", "collapses": "collapse_schedule"},
	"treasure_noise": {"treasure": "location", "threshold": "nonnegative_integer"},
	"ritual": {"circles": "zone", "required_turns": "positive_integer"},
	"wagon": {"subject": "subject", "destination": "location"},
}


static func build(objective: Dictionary, board: Dictionary) -> Dictionary:
	var result := {"handler": objective.handler}
	var schema: Dictionary = FIELDS[objective.handler]
	for field in schema:
		match schema[field]:
			"location":
				result[field] = position(board.locations[objective[field]])
			"zone":
				result[field] = _zone(board, objective[field])
			"collapse_schedule":
				var schedule: Array = []
				for entry in objective[field]:
					schedule.append({"round": int(entry.round), "cells": _zone(board, entry.cells)})
				result[field] = schedule
			"positive_integer", "nonnegative_integer":
				result[field] = int(objective[field])
			"subjects":
				result[field] = objective[field].duplicate()
			"optional_team":
				result[field] = objective.get(field, "enemies")
			"subject", "start_zone":
				# leave_zone retains its zone ID.
				result[field] = objective[field]
	match objective.handler:
		"survive":
			# The catalog resolves reserve placement IDs into off-board actors.
			if objective.has("reserve_round"):
				result["reserve_round"] = int(objective.reserve_round)
		"treasure_noise":
			result["noise"] = 0
		"ritual":
			result["held_turns"] = 0
	return result


static func _zone(board: Dictionary, id: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in board.zones[id]:
		cells.append(position(cell))
	return cells


static func position(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))
