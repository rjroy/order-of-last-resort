extends RefCounted

const Board = preload("res://rules/board.gd")

# Register this object with art_key "shield_wall", max_hp 1, and the
# blocks_movement and damageable capabilities. It is not pushable or pullable.
const OBJECT_ID := "shield_wall"
const FITTED_FORM_ID := "thrown_shield_wall"
const FITTED_LABEL := "Thrown Shield Wall"
const SHARED_HP := 1


static func has_live_wall(state: Dictionary, knight: Dictionary) -> bool:
	for obstacle: Dictionary in state.obstacles:
		if obstacle.object_id == OBJECT_ID and obstacle.get("wall_owner_id") == knight.id \
				and Board.alive(obstacle):
			return true
	return false


## A blocker applies to both forms. An empty string still requires an open span.
static func blocked_reason(state: Dictionary, knight: Dictionary) -> String:
	if not Board.alive(knight):
		return "Knight has fallen"
	if has_live_wall(state, knight):
		return "wall already standing"
	if knight.has("shield_position"):
		return "shield away"
	if not state.catalog.defs.objects.has(OBJECT_ID):
		return "wall object is not defined"
	return ""


## Only center cells are selectable. Enumeration follows the usual board direction order.
static func choices(state: Dictionary, knight: Dictionary, thrown := false) -> Array:
	var result: Array = []
	if not blocked_reason(state, knight).is_empty():
		return result
	var reach := 2 if thrown else 1
	for direction: Vector2i in Board.DIRECTIONS:
		var center: Vector2i = knight.position + direction * reach
		var span := _open_span(state, knight.position, center, reach)
		if not span.is_empty():
			span["id"] = Board.cell_id(center)
			span["label"] = Board.coordinate(center)
			result.append(span)
	return result


static func fitted_form(state: Dictionary, knight: Dictionary) -> Dictionary:
	var legal := choices(state, knight, true)
	var reason := ""
	if legal.is_empty():
		reason = blocked_reason(state, knight)
		if reason.is_empty():
			reason = "no open three-tile landing"
	return {"id": FITTED_FORM_ID, "label": FITTED_LABEL,
		"help": "Throw the wall two orthogonal tiles away. All three cells across the landing must be open.",
		"targeting": {"kind": "cell"}, "choices": legal, "unavailable_reason": reason, "primary": "steady"}


## Recheck the chosen center before changing state. Fitting consumption belongs to the caller.
static func place(state: Dictionary, knight: Dictionary, center: Vector2i, events: Array,
		thrown := false) -> bool:
	if not blocked_reason(state, knight).is_empty():
		return false
	var wall := _open_span(state, knight.position, center, 2 if thrown else 1)
	if wall.is_empty():
		return false
	var id := _wall_id(state, knight.id)
	var delta: Vector2i = center - knight.position
	var facing := Vector2i(signi(delta.x), signi(delta.y))
	wall.merge({"id": id, "object_id": OBJECT_ID, "wall_owner_id": knight.id,
		"hp": SHARED_HP, "max_hp": SHARED_HP, "statuses": {}, "facing": facing})
	state.obstacles.append(wall)
	var cells := Board.occupied_cells(wall)
	var coordinates := PackedStringArray()
	for cell in cells:
		coordinates.append(Board.coordinate(cell))
	Board.event(events, "shield_wall_placed", "%s uses %s, blocking %s (%d shared HP)." % [
		Board.display_name(state, knight), FITTED_LABEL if thrown else "Shield Wall",
		", ".join(coordinates), SHARED_HP],
		{"unit_id": knight.id, "wall_id": id, "position": center, "cells": cells,
			"hp": SHARED_HP, "facing": facing})
	return true


## Merge into a single entity choice. The closest legal cell is the rule contact;
## ties retain footprint order. Negative reach means no range filter.
static func attack_contact(origin: Vector2i, target: Dictionary, reach := -1) -> Dictionary:
	var result := {}
	var cells: Array[Vector2i] = []
	var nearest := 2147483647
	for cell in Board.occupied_cells(target):
		var distance := Board.distance(origin, cell)
		if reach >= 0 and (distance == 0 or distance > reach):
			continue
		cells.append(cell)
		if distance < nearest:
			nearest = distance
			result["position"] = cell
	if not result.is_empty():
		result["target_cells"] = cells
	return result


static func _open_span(state: Dictionary, origin: Vector2i, center: Vector2i, reach: int) -> Dictionary:
	var delta := center - origin
	if (delta.x != 0 and delta.y != 0) or Board.distance(origin, center) != reach:
		return {}
	var across := Vector2i.DOWN if delta.x != 0 else Vector2i.RIGHT
	var offsets: Array[Vector2i] = [-across, across]
	var span := {"position": center, "footprint_offsets": offsets}
	for cell in Board.occupied_cells(span):
		if not Board.is_vacant(state, cell):
			return {}
	return span


static func _wall_id(state: Dictionary, knight_id: String) -> String:
	var stem := "%s_%s" % [knight_id, OBJECT_ID]
	var id := stem
	var suffix := 2
	var reserves: Array = state.objective.get("reserves", [])
	# Dead walls remain in the result so a forecast can show same-round placement and destruction.
	while not Board.entity(state, id).is_empty() or reserves.any(func(unit: Dictionary) -> bool: return unit.id == id):
		id = "%s_%d" % [stem, suffix]
		suffix += 1
	return id
