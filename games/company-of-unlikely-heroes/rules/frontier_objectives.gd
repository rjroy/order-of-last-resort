extends RefCounted

const Board = preload("res://rules/board.gd")
const RitualCapacity = preload("res://rules/ritual_capacity.gd")
const Summons = preload("res://rules/summons.gd")
const FLEE_STEPS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


## Objective effects run once after the initiative pass and before outcomes.
static func finish_round(state: Dictionary, events: Array) -> void:
	match state.objective.handler:
		"herd_sheep":
			_flee_sheep(state, events)
		"collapsing_bridge":
			_collapse_due_spans(state, events)
		"ritual":
			_hold_circles(state, events)
		"wagon":
			_advance_wagon(state, events)


## Only an ongoing battle prepares the upcoming round.
static func prepare_next_round(state: Dictionary, events: Array) -> void:
	if state.objective.handler == "survive":
		_admit_reserves(state, events)


## Outcome queries are read-only so a commit can recheck the forecast result.
static func met(state: Dictionary) -> bool:
	var objective: Dictionary = state.objective
	match objective.handler:
		"pressure_gate", "collapsing_bridge":
			return _hero_at(state, objective.exit)
		"survive":
			return state.round >= objective.turns
		"herd_sheep":
			return _penned_count(state) == objective.subjects.size()
		"treasure_noise":
			return _hero_at(state, objective.treasure)
		"ritual":
			return objective.held_turns >= objective.required_turns
		"wagon":
			var wagon := Board.entity(state, objective.subject)
			return Board.alive(wagon) and wagon.position == objective.destination
	return false


static func failure(state: Dictionary) -> String:
	var objective: Dictionary = state.objective
	match objective.handler:
		"herd_sheep":
			for id in objective.subjects:
				var sheep := Board.entity(state, id)
				if not Board.alive(sheep):
					var name: String = Board.display_name(state, sheep) if not sheep.is_empty() else id
					return "%s was lost; the flock cannot be brought home." % name
		"treasure_noise":
			if objective.noise > objective.threshold:
				return "The giant wakes: noise reached %d, above the limit of %d." % [
					objective.noise, objective.threshold]
		"ritual":
			if not RitualCapacity.has_enough_occupants(state, objective.circles.size()):
				return "The ritual fails: there are not enough characters left to occupy every circle."
		"wagon":
			if not Board.alive(Board.entity(state, objective.subject)):
				return "The supply wagon was destroyed."
	return ""


static func report_gate_change(state: Dictionary, actor: Dictionary, was_open: bool, events: Array) -> void:
	var opened := Board.pressure_gate_open(state)
	if opened == was_open:
		return
	var gate: Vector2i = state.objective.gate
	Board.event(events, "pressure_gate", "The gate at %s %s." % [
		Board.coordinate(gate), "opens: the plate is occupied" if opened else "closes: the plate is empty"],
		{"unit_id": actor.id, "position": gate, "open": opened})


static func add_noise(state: Dictionary, actor: Dictionary, handler: String, events: Array) -> void:
	if handler == "hold":
		return
	var amount := 2
	match handler:
		"move":
			amount = 1
		"perform":
			amount = 3
	var objective: Dictionary = state.objective
	objective.noise += amount
	Board.event(events, "objective_noise", "%s makes %d noise (%d / %d)." % [
		Board.display_name(state, actor), amount, objective.noise, objective.threshold],
		{"unit_id": actor.id, "amount": amount, "noise": objective.noise, "threshold": objective.threshold})


static func progress(state: Dictionary) -> Dictionary:
	var objective: Dictionary = state.objective
	match objective.handler:
		"pressure_gate":
			return {"text": "%s · Get a hero to %s" % [_gate_label(state), Board.coordinate(objective.exit)]}
		"survive":
			var completed: int = state.round if state.outcome == "victory" else state.round - 1
			var text := "%d / %d rounds survived" % [completed, objective.turns]
			var reserves: Array = objective.get("reserves", [])
			if state.outcome == "ongoing" and not reserves.is_empty():
				var entries := PackedStringArray()
				for reserve in reserves:
					entries.append(Board.coordinate(reserve.position))
				text += " · Enemy reserves: round %d at %s if clear" % [objective.reserve_round, ", ".join(entries)] \
					if state.round < objective.reserve_round \
					else " · Enemy reserves waiting for %s to clear" % ", ".join(entries)
			return {"text": text}
		"herd_sheep":
			return {"text": "%d / %d living sheep penned" % [_penned_count(state), objective.subjects.size()]}
		"collapsing_bridge":
			var due := _next_collapse(state)
			var status := "Next collapse: end of round %d" % due if due > 0 else "No collapses remaining"
			return {"text": "%s · Exit %s" % [status, Board.coordinate(objective.exit)]}
		"treasure_noise":
			return {"text": "Noise %d / %d · Treasure %s" % [
				objective.noise, objective.threshold, Board.coordinate(objective.treasure)]}
		"ritual":
			return {"text": "%d / %d circles occupied · %d / %d consecutive rounds" % [
				_occupied_circles(state), objective.circles.size(), objective.held_turns, objective.required_turns]}
		"wagon":
			var wagon := Board.entity(state, objective.subject)
			if wagon.is_empty():
				return {}
			var line := "%d / %d HP · %s → %s" % [
				wagon.hp, wagon.max_hp, Board.coordinate(wagon.position), Board.coordinate(objective.destination)]
			if Board.alive(wagon) and _enemy_adjacent(state, wagon):
				line += " · Stalled: enemy adjacent"
			return {"text": line}
	return {}


## Map board cells to objective marker labels and presentation kinds.
static func markers(state: Dictionary) -> Dictionary:
	var objective: Dictionary = state.objective
	var result: Dictionary = {}
	match objective.handler:
		"pressure_gate":
			var open := Board.pressure_gate_open(state)
			result[objective.plate] = _marker("plate", "Pressure plate — held" if open else "Pressure plate — empty")
			result[objective.gate] = _marker("gate", _gate_label(state))
			result[objective.exit] = _marker("exit", "Exit")
		"herd_sheep":
			for cell in objective.pen:
				result[cell] = _marker("pen", "Sheep pen")
		"collapsing_bridge":
			for span in objective.collapses:
				for cell in span.cells:
					var label := "Collapses after round %d" % span.round if Board.passable(state, cell) else "Collapsed"
					result[cell] = _marker("collapse", label)
			result[objective.exit] = _marker("exit", "Far bank")
		"treasure_noise":
			result[objective.treasure] = _marker("treasure", "Treasure")
		"ritual":
			for cell in objective.circles:
				var label := "Ritual circle — occupied" if Board.living_character_at(state, cell) else "Ritual circle — empty"
				result[cell] = _marker("ritual", label)
		"wagon":
			result[objective.destination] = _marker("destination", "Village")
	return result


static func _marker(kind: String, label: String) -> Dictionary:
	return {"kind": kind, "label": label}


static func _gate_label(state: Dictionary) -> String:
	return "Gate open" if Board.pressure_gate_open(state) else "Gate closed"


static func _hero_at(state: Dictionary, cell: Vector2i) -> bool:
	for unit in state.units:
		if unit.position == cell and Board.alive(unit) and Board.deployed_hero(state, unit):
			return true
	return false


static func _admit_reserves(state: Dictionary, events: Array) -> void:
	var objective: Dictionary = state.objective
	var reserves: Array = objective.get("reserves", [])
	if reserves.is_empty() or state.round < objective.reserve_round:
		return
	# Join the next round's initiative only; an occupied entry does not displace its occupant.
	var waiting: Array = []
	var arriving: Array = []
	for reserve in reserves:
		if Board.is_vacant(state, reserve.position):
			state.units.append(reserve)
			arriving.append(reserve)
			var profile := Board.profile(state, reserve)
			if profile.has("default_order"):
				state.orders[reserve.id] = profile.default_order
		else:
			waiting.append(reserve)
	objective.reserves = waiting
	for reserve in arriving:
		Board.event(events, "reserve_arrival", "%s enters at %s for round %d." % [
			Board.display_name(state, reserve), Board.coordinate(reserve.position), state.round],
			{"unit_id": reserve.id, "position": reserve.position, "round": state.round})


static func _penned_count(state: Dictionary) -> int:
	var count := 0
	for id in state.objective.subjects:
		var sheep := Board.entity(state, id)
		if Board.alive(sheep) and sheep.position in state.objective.pen:
			count += 1
	return count


static func _flee_sheep(state: Dictionary, events: Array) -> void:
	var objective: Dictionary = state.objective
	var threats := Board.turn_order(state).filter(func(unit: Dictionary) -> bool:
		return Board.alive(unit) and unit.id not in objective.subjects)
	for id in objective.subjects:
		var sheep := Board.entity(state, id)
		if not Board.alive(sheep) or sheep.position in objective.pen:
			continue
		var threat := Board.nearest(sheep, threats)
		if threat.is_empty() or Board.distance(sheep.position, threat.position) > 2:
			continue
		var best: Vector2i = sheep.position
		var distance := Board.distance(best, threat.position)
		for direction in FLEE_STEPS:
			var cell: Vector2i = sheep.position + direction
			var reach := Board.distance(cell, threat.position)
			if reach > distance and Board.is_vacant(state, cell):
				best = cell
				distance = reach
		var sidestepping: bool = best == sheep.position
		if sidestepping:
			best = _sheep_sidestep(state, sheep.position, objective.pen)
		if best != sheep.position:
			sheep.position = best
			var sheep_name := Board.display_name(state, sheep)
			var cell_name := Board.coordinate(best)
			var text := "%s sidesteps toward the pen at %s." % [sheep_name, cell_name] if sidestepping \
				else "%s flees from %s to %s." % [sheep_name, Board.display_name(state, threat), cell_name]
			Board.event(events, "move", text, {"unit_id": id, "target_id": threat.id, "position": best})


static func _sheep_sidestep(state: Dictionary, position: Vector2i, pen: Array) -> Vector2i:
	var best := position
	var best_distance := _distance_to_pen(position, pen)
	for direction in FLEE_STEPS:
		var cell: Vector2i = position + direction
		if not Board.is_vacant(state, cell):
			continue
		var distance := _distance_to_pen(cell, pen)
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best


static func _distance_to_pen(position: Vector2i, pen: Array) -> int:
	var distance := 2147483647
	for cell in pen:
		distance = mini(distance, Board.distance(position, cell))
	return distance


static func _next_collapse(state: Dictionary) -> int:
	var due := 0
	for span in state.objective.collapses:
		if (due == 0 or span.round < due) and span.cells.any(func(cell: Vector2i) -> bool:
				return Board.passable(state, cell)):
			due = span.round
	return due


static func _collapse_due_spans(state: Dictionary, events: Array) -> void:
	for span in state.objective.collapses:
		if span.round != state.round:
			continue
		var labels := PackedStringArray()
		for cell in span.cells:
			labels.append(Board.coordinate(cell))
			Board.set_tile(state, cell, "void")
		Board.event(events, "terrain_collapse", "The bridge collapses at %s." % ", ".join(labels),
			{"round": state.round, "cells": span.cells.duplicate()})
		# Resolve falls after the terrain changes so no reaction can spawn onto a gap.
		for occupant in state.units + state.obstacles:
			if Board.alive(occupant) and occupant.position in span.cells:
				occupant.hp = 0
				Board.event(events, "collapse_fall", "%s falls with the bridge at %s." % [
					Board.display_name(state, occupant), Board.coordinate(occupant.position)],
					{"unit_id": occupant.id, "position": occupant.position})
				Summons.on_fall(state, occupant, events)


static func _occupied_circles(state: Dictionary) -> int:
	var count := 0
	for cell in state.objective.circles:
		if Board.living_character_at(state, cell):
			count += 1
	return count


static func _hold_circles(state: Dictionary, events: Array) -> void:
	var objective: Dictionary = state.objective
	if _occupied_circles(state) == objective.circles.size():
		objective.held_turns += 1
		Board.event(events, "ritual_progress", "All circles held: %d / %d consecutive rounds." % [
			objective.held_turns, objective.required_turns], {"held_turns": objective.held_turns})
	elif objective.held_turns > 0:
		objective.held_turns = 0
		Board.event(events, "ritual_progress", "A circle is empty. Ritual progress resets.", {"held_turns": 0})


static func _enemy_adjacent(state: Dictionary, wagon: Dictionary) -> bool:
	for unit in state.units:
		if Board.alive(unit) and Board.distance(unit.position, wagon.position) == 1 \
				and Board.team(state, unit) == "enemies":
			return true
	return false


static func _advance_wagon(state: Dictionary, events: Array) -> void:
	var objective: Dictionary = state.objective
	var wagon := Board.entity(state, objective.subject)
	if not Board.alive(wagon) or wagon.position == objective.destination:
		return
	var data := {"unit_id": wagon.id, "position": wagon.position}
	if _enemy_adjacent(state, wagon):
		Board.event(events, "wait", "An adjacent enemy stalls the wagon.", data)
		return
	var step := Board.step_toward(state, wagon, objective.destination, 0)
	if step == wagon.position:
		Board.event(events, "wait", "The wagon's route is blocked.", data)
		return
	wagon.position = step
	data.position = step
	Board.event(events, "move", "The wagon advances to %s." % Board.coordinate(step), data)
