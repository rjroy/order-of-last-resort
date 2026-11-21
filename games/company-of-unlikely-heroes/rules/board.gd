extends RefCounted

const Catalog = preload("res://content/catalog.gd")
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT]


static func entity(state: Dictionary, id: String) -> Dictionary:
	for candidate in state.units:
		if candidate.id == id:
			return candidate
	for candidate in state.obstacles:
		if candidate.id == id:
			return candidate
	return {}


static func profile(state: Dictionary, subject: Dictionary) -> Dictionary:
	if subject.has("character_id"):
		return Catalog.profile(state.catalog.defs, subject.character_id)
	if subject.has("object_id"):
		return state.catalog.defs.objects.get(subject.object_id, {})
	return {}


static func capable(state: Dictionary, subject: Dictionary, capability: String) -> bool:
	return capability in profile(state, subject).get("capabilities", [])


static func team(state: Dictionary, subject: Dictionary) -> String:
	return profile(state, subject).get("team", "")


static func display_name(state: Dictionary, subject: Dictionary) -> String:
	var name: String = profile(state, subject).get("label", subject.get("id", ""))
	for other in state.units + state.obstacles:
		if other.id != subject.get("id", "") and profile(state, other).get("label", "") == name:
			return "%s (%s)" % [name, subject.id]
	return name


static func alive(subject: Dictionary) -> bool:
	return subject.get("hp", 0) > 0


static func corpses(state: Dictionary, filters: Dictionary) -> Array:
	var result: Array = []
	for unit in state.units:
		if not alive(unit) and not unit.has("summoner_id") and not unit.get("corpse_consumed", false) \
				and not capable(state, unit, "minion") and _qualifies(state, unit, filters):
			result.append(unit)
	return result


## The order is captured before resolving a round, so new summons wait until the next one.
static func turn_order(state: Dictionary) -> Array:
	var order: Array = []
	var minions_by_summoner: Dictionary = {}
	for unit in state.units:
		if unit.has("summoner_id"):
			if alive(unit):
				var caster: String = unit.summoner_id
				if not minions_by_summoner.has(caster):
					minions_by_summoner[caster] = []
				minions_by_summoner[caster].append(unit)
	for unit in state.units:
		if unit.has("summoner_id"):
			continue
		order.append(unit)
		var minions: Array = minions_by_summoner.get(unit.id, [])
		minions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.summon_priority < b.summon_priority if a.summon_priority != b.summon_priority else a.id < b.id)
		order.append_array(minions)
	return order


static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func in_zone(state: Dictionary, zone_id: String, position: Vector2i) -> bool:
	var cells: Array = state.catalog.defs.boards[state.board_id].zones[zone_id]
	for cell in cells:
		if Catalog.Validator.position(cell) == position:
			return true
	return false


static func tile(state: Dictionary, position: Vector2i) -> Dictionary:
	var kind: String = state.default_tile
	for entry in state.terrain:
		if entry.position == position:
			kind = entry.type
			break
	return state.catalog.defs.tiles[kind]


static func _passable(state: Dictionary, position: Vector2i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.x < state.width and position.y < state.height \
		and tile(state, position).passable


static func can_enter(state: Dictionary, position: Vector2i, ignore := "") -> bool:
	if not _passable(state, position):
		return false
	for candidate in state.units + state.obstacles:
		if candidate.id != ignore and candidate.position == position and alive(candidate) \
				and capable(state, candidate, "blocks_movement"):
			return false
	return true


static func is_vacant(state: Dictionary, position: Vector2i) -> bool:
	if not _passable(state, position):
		return false
	for candidate in state.units + state.obstacles:
		if alive(candidate) and candidate.position == position:
			return false
	return true


static func occupants(state: Dictionary, filters: Dictionary) -> Array:
	var result: Array = []
	for unit in state.units:
		if alive(unit) and _qualifies(state, unit, filters):
			result.append(unit)
	if filters.get("objects", false):
		for obstacle in state.obstacles:
			if alive(obstacle) and _qualifies(state, obstacle, filters, true):
				result.append(obstacle)
	return result


static func _qualifies(state: Dictionary, subject: Dictionary, filters: Dictionary, ignore_team := false) -> bool:
	var spec := profile(state, subject)
	if not ignore_team and filters.has("teams") and spec.get("team", "") not in filters.teams:
		return false
	var capabilities: Array = spec.get("capabilities", [])
	for id in filters.get("capabilities", []):
		if id not in capabilities:
			return false
	return true


# Strict comparison preserves the supplied candidate order on ties.
static func nearest(origin: Dictionary, candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 2147483647
	for candidate in candidates:
		if candidate.id == origin.id:
			continue
		var reach := distance(origin.position, candidate.position)
		if reach < best_distance:
			best = candidate
			best_distance = reach
	return best


static func cell_id(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]


@warning_ignore("integer_division")
static func coordinate(position: Vector2i) -> String:
	if position.x < 0 or position.y < 0:
		return cell_id(position)
	var column := ""
	var index := position.x + 1
	while index > 0:
		index -= 1
		column = String.chr(65 + index % 26) + column
		index /= 26
	return "%s%d" % [column, position.y + 1]


# Breadth-first search with fixed neighbor order, bounded by the authored board.
static func step_toward(state: Dictionary, unit: Dictionary, goal: Vector2i, reach: int) -> Vector2i:
	return step_to(state, unit.position, func(cell: Vector2i) -> bool: return distance(cell, goal) <= reach)


static func step_to(state: Dictionary, start: Vector2i, is_goal: Callable) -> Vector2i:
	var queue: Array[Vector2i] = [start]
	var previous := {start: start}
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		if is_goal.call(current):
			while previous[current] != start:
				current = previous[current]
			return current
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if not previous.has(next) and can_enter(state, next):
				previous[next] = current
				queue.append(next)
	return start


static func event(events: Array, type: String, text: String, data: Dictionary = {}) -> void:
	var entry := data.duplicate()
	entry["type"] = type
	entry["text"] = text
	events.append(entry)


static func format_text(template: String, substitutions: Dictionary) -> String:
	var values := substitutions.duplicate()
	for key in values:
		if values[key] is Vector2i:
			values[key] = coordinate(values[key])
	return template.format(values)


static func text(state: Dictionary, id: String, substitutions: Dictionary = {}) -> String:
	return format_text(state.catalog.defs.events[id].text, substitutions)


static func authored_event(state: Dictionary, events: Array, type: String, template_id: String,
		substitutions: Dictionary, data: Dictionary) -> void:
	event(events, type, text(state, template_id, substitutions), data)
