extends RefCounted
## Reads authored JSON and builds independent encounters without embedding definitions in snapshots.

const DEFAULT_PATH := "res://content/catalog.json"
const TABLES := ["missions", "encounters", "boards", "tiles", "classes", "characters",
	"capabilities", "objects", "abilities", "orders", "behaviors", "statuses", "events", "presentation"]
const REQUIRED_EVENTS := ["move", "damage", "knockdown_suffix", "reflect_absorb", "reflect_redirect",
	"push", "collision_suffix", "aura", "taunt", "heal", "heal_full", "blast_suffix", "pull",
	"recoil_source", "cannot_advance", "recover", "hold", "invalid", "watches", "gain_status"]
const ABILITY_TARGETING := {
	"move": ["cell"], "apply_status": ["none"],
	"push": ["entity", "automatic"], "bonk": ["entity", "automatic"], "heal": ["entity", "automatic"],
	"blast": ["entity", "automatic"], "pull": ["entity", "automatic"], "attack": ["entity", "automatic"],
}
const STATUS_EXPIRY := {"reflect": "actor_turn_start", "skip_action": "consume_action", "retarget": "actor_turn_end"}


class FrozenCatalog extends RefCounted:
	var defs: Dictionary:
		get:
			return _defs
		set(_value):
			push_error("A running encounter's catalog cannot be replaced.")

	var _defs: Dictionary

	func _init(source: Dictionary) -> void:
		_defs = source.duplicate(true)
		_freeze(_defs)

	static func _freeze(value: Variant) -> void:
		if value is Dictionary:
			for child in value.values():
				_freeze(child)
			value.make_read_only()
		elif value is Array:
			for child in value:
				_freeze(child)
			value.make_read_only()


## The returned authored tables are editable; build detaches and freezes its own copy.
static func read_default() -> Dictionary:
	var result := read_source(DEFAULT_PATH)
	if result.has("error"):
		push_error(result.error)
		return {}
	return result.definitions


## Use for explicit content files as well, so built-in and injected JSON share diagnostics.
static func read_source(path: String) -> Dictionary:
	var source := _read_json(path)
	if source.has("error"):
		return source
	var defs: Dictionary = source.definitions
	if defs.has("parts"):
		if defs.size() != 1 or not defs.parts is Array or defs.parts.is_empty():
			return {"error": "Invalid content manifest \"%s\": expected only a nonempty parts array." % path}
		defs = {}
		for part in source.definitions.parts:
			if not part is String or part.strip_edges().is_empty() or part.is_absolute_path():
				return {"error": "Invalid content manifest \"%s\": part paths must be nonempty relative paths." % path}
			var part_path := path.get_base_dir().path_join(part)
			var loaded := _read_json(part_path)
			if loaded.has("error"):
				return loaded
			for table in loaded.definitions:
				var records: Variant = loaded.definitions[table]
				if not records is Dictionary:
					return {"error": "Invalid content part \"%s\": table '%s' must be a dictionary." % [part_path, table]}
				if not defs.has(table):
					defs[table] = {}
				for id in records:
					if defs[table].has(id):
						return {"error": "Duplicate %s ID '%s' in content part \"%s\"." % [table, id, part_path]}
					defs[table][id] = records[id]
	var errors := validate(defs)
	if not errors.is_empty():
		return {"error": "Invalid content in \"%s\":\n%s" % [path, "\n".join(errors)]}
	return {"definitions": defs}


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Could not open the content file \"%s\": %s" % [
			path, error_string(FileAccess.get_open_error())]}
	var text := file.get_as_text()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"error": "Invalid JSON in \"%s\", line %d: %s" % [
			path, parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Dictionary:
		return {"error": "The content file \"%s\" must contain a JSON object." % path}
	# Godot's JSON parser keeps only the last value for a repeated object key.
	var duplicate := _duplicate_key(text)
	if not duplicate.is_empty():
		return {"error": "Invalid JSON in \"%s\": %s" % [path, duplicate]}
	return {"definitions": parser.data}


static func validate(defs: Dictionary) -> PackedStringArray:
	return Validator.new(defs).check()


static func profile(defs: Dictionary, character_id: String) -> Dictionary:
	var character: Dictionary = defs.get("characters", {}).get(character_id, {})
	if character.is_empty():
		return {}
	var defaults: Dictionary = defs.get("classes", {}).get(character.get("class", ""), {})
	return defaults.merged(character, true)


static func build(defs: Dictionary, mission_id: String, chosen_ids: Array = []) -> Dictionary:
	if not _report_errors("Catalog", validate(defs)):
		return {}
	if not defs.missions.has(mission_id):
		push_error("Catalog: unknown mission '%s'" % mission_id)
		return {}
	var mission: Dictionary = defs.missions[mission_id]
	var encounter: Dictionary = defs.encounters[mission.encounter]
	var board: Dictionary = defs.boards[encounter.board]
	var objective := {"handler": mission.objective.handler}
	if mission.objective.handler == "escort":
		objective["subject"] = mission.objective.subject
		objective["destination"] = Validator.position(board.locations[mission.objective.destination])
	elif mission.objective.handler == "defeat_all":
		objective["team"] = mission.objective.get("team", "enemies")
	var units: Array = []
	var obstacles: Array = []
	var orders: Dictionary = {}
	var slots: Array = encounter.get("party_slots", [])
	if chosen_ids.size() != slots.size():
		push_error("Catalog: mission '%s' requires exactly %d selected characters; received %d" % [
			mission_id, slots.size(), chosen_ids.size()])
		return {}
	var used: Dictionary = {}
	for i in chosen_ids.size():
		var id: Variant = chosen_ids[i]
		if not id is String or not defs.characters.has(id) or used.has(id):
			push_error("Catalog: unknown or duplicate selected character '%s'" % str(id))
			return {}
		var unit_profile := profile(defs, id)
		if unit_profile.team != "heroes" or not "commandable" in unit_profile.capabilities:
			push_error("Catalog: selected character '%s' is not a commandable hero" % id)
			return {}
		for placement in encounter.placements:
			if placement.id == id:
				push_error("Catalog: selected character ID '%s' collides with a placement" % id)
				return {}
		used[id] = true
		units.append({"id": id, "character_id": id, "position": Validator.position(slots[i]),
			"statuses": {}, "hp": int(unit_profile.max_hp), "max_hp": int(unit_profile.max_hp)})
		if unit_profile.has("default_order"):
			orders[id] = unit_profile.default_order
	for placement in encounter.placements:
		var instance := {"id": placement.id, "position": Validator.position(placement.at), "statuses": {}}
		if placement.has("character"):
			var unit_profile := profile(defs, placement.character)
			instance.merge({"character_id": placement.character,
				"hp": int(unit_profile.max_hp), "max_hp": int(unit_profile.max_hp)})
			units.append(instance)
			if unit_profile.has("default_order"):
				orders[placement.id] = unit_profile.default_order
		else:
			var hp := int(defs.objects[placement.object].max_hp)
			instance.merge({"object_id": placement.object, "hp": hp, "max_hp": hp})
			obstacles.append(instance)
	var terrain: Array = []
	for tile in board.tiles:
		terrain.append({"position": Validator.position(tile.at), "type": tile.type})
	return {"catalog": FrozenCatalog.new(defs),
		"mission_id": mission_id, "encounter_id": mission.encounter, "board_id": encounter.board,
		"objective": objective,
		"width": int(board.width), "height": int(board.height), "default_tile": board.default_tile,
		"units": units, "obstacles": obstacles, "terrain": terrain,
		"round": 1, "orders": orders, "overrides": {}, "outcome": "ongoing"}


static func _report_errors(source: String, errors: PackedStringArray) -> bool:
	if errors.is_empty():
		return true
	push_error("%s:\n%s" % [source, "\n".join(errors)])
	return false


static func _duplicate_key(text: String) -> String:
	# Tokenize entire strings before inspecting delimiters, so braces/colons inside copy are inert.
	var tokens := RegEx.create_from_string("\"(?:\\\\.|[^\"\\\\])*\"\\s*:?|[{}]")
	var keys: Array[Dictionary] = []
	for token in tokens.search_all(text):
		var value := token.get_string()
		match value:
			"{":
				keys.append({})
			"}":
				keys.pop_back()
			_:
				if not value.ends_with(":") or keys.is_empty():
					continue
				var key: Variant = JSON.parse_string(value.trim_suffix(":"))
				if keys.back().has(key):
					var line := 1 + text.count("\n", 0, token.get_start())
					return "duplicate object key '%s' at line %d" % [str(key), line]
				keys.back()[key] = true
	return ""


class Validator:
	var _defs: Dictionary
	var _errors := PackedStringArray()

	func _init(defs: Dictionary) -> void:
		_defs = defs

	func check() -> PackedStringArray:
		_check_json_shape(_defs, "catalog", [])
		if not _errors.is_empty():
			return _errors
		for table in TABLES:
			var records := _dictionary(_defs.get(table), table)
			for id in records:
				_text(str(id), table + " ID")
				_dictionary(records[id], "%s.%s" % [table, id])
		if not _errors.is_empty():
			return _errors
		_check_simple_tables()
		_each("abilities", _check_ability)
		_each("behaviors", _check_behavior)
		_each("statuses", _check_status)
		_each("classes", _check_profile)
		_each("characters", _check_character)
		_each("objects", _check_object)
		_each("boards", _check_board)
		_each("encounters", _check_encounter)
		_each("missions", _check_mission)
		if _defs.has("adventures"):
			var adventures := _dictionary(_defs.adventures, "adventures")
			for id in adventures:
				_text(str(id), "adventures ID")
				_check_adventure(_dictionary(adventures[id], "adventures." + str(id)), "adventures." + str(id))
		return _errors

	func _check_json_shape(value: Variant, path: String, ancestors: Array) -> void:
		# Injected data must also be JSON-shaped; object instances cannot be detached by duplicate().
		if value is Dictionary or value is Array:
			for ancestor in ancestors:
				if is_same(value, ancestor):
					_error(path, "cyclic reference")
					return
			ancestors.append(value)
		if value is Dictionary:
			for key in value:
				if not (key is String or key is StringName):
					_error(path, "expected string keys")
					continue
				_check_json_shape(value[key], path + "." + str(key), ancestors)
			ancestors.pop_back()
		elif value is Array:
			for i in value.size():
				_check_json_shape(value[i], "%s[%d]" % [path, i], ancestors)
			ancestors.pop_back()
		elif not (typeof(value) == TYPE_NIL or value is String or value is bool or value is int
				or (value is float and is_finite(value))):
			_error(path, "expected a JSON value")

	func _each(table: String, check_record: Callable) -> void:
		for id in _defs[table]:
			check_record.call(_defs[table][id], "%s.%s" % [table, id])

	func _check_simple_tables() -> void:
		for table in ["capabilities", "orders", "presentation", "tiles"]:
			for id in _defs[table]:
				var record: Dictionary = _defs[table][id]
				var path := "%s.%s" % [table, id]
				_text(record.get("label"), path + ".label")
				if table == "presentation" and record.has("color"):
					_color(record.color, path + ".color")
				if table == "tiles":
					_text(record.get("art_key"), path + ".art_key")
					_boolean(record.get("passable"), path + ".passable")
					if record.has("collapse_to"):
						_ref(record.collapse_to, "tiles", path + ".collapse_to")
		for id in _defs.events:
			_text(_defs.events[id].get("text"), "events.%s.text" % id)
		for id in REQUIRED_EVENTS:
			_ref(id, "events", "events." + id)

	func _check_ability(ability: Dictionary, path: String) -> void:
		_text(ability.get("label"), path + ".label")
		_text(ability.get("help"), path + ".help")
		var handler: Variant = ability.get("handler")
		if not _choice(handler, ABILITY_TARGETING.keys(), path + ".handler"):
			return
		var targeting := _dictionary(ability.get("targeting"), path + ".targeting")
		_choice(targeting.get("kind"), ABILITY_TARGETING[handler], path + ".targeting.kind")
		if targeting.has("range"):
			if handler == "move":
				if not _is_integer(targeting.range, 1) or int(targeting.range) != 1:
					_error(path + ".targeting.range", "move supports only a one-cell step")
			elif handler == "apply_status":
				_error(path + ".targeting.range", "apply_status has no target range")
			else:
				_integer(targeting.range, path + ".targeting.range", 1)
		if handler in ["move", "apply_status"]:
			for filter in ["teams", "objects", "capabilities"]:
				if targeting.has(filter):
					_error(path + ".targeting." + filter, "requires entity or automatic targeting")
		else:
			_check_target_filters(targeting, path + ".targeting")
		var params := _dictionary(ability.get("params"), path + ".params")
		var param_path := path + ".params."
		match handler:
			"move":
				pass
			"push":
				_integer(params.get("collision_damage"), param_path + "collision_damage")
			"apply_status":
				_ref(params.get("status"), "statuses", param_path + "status")
			"bonk", "blast":
				_integer(params.get("damage"), param_path + "damage")
				_ref(params.get("status"), "statuses", param_path + "status")
			"heal":
				_integer(params.get("amount"), param_path + "amount")
			"pull":
				_integer(params.get("recoil_damage"), param_path + "recoil_damage")
				_ref(params.get("status"), "statuses", param_path + "status")
			"attack":
				_integer(params.get("damage"), param_path + "damage")
				if params.has("status"):
					_ref(params.status, "statuses", param_path + "status")
		if handler in ["bonk", "blast", "attack"] and params.has("source_suffix"):
			_text(params.source_suffix, param_path + "source_suffix", true)

	func _check_target_filters(filters: Dictionary, path: String) -> void:
		if filters.has("teams"):
			_id_list(filters.teams, path + ".teams")
		if filters.has("objects"):
			_boolean(filters.objects, path + ".objects")
		if filters.has("capabilities"):
			_id_list(filters.capabilities, path + ".capabilities", "capabilities")

	func _check_behavior(behavior: Dictionary, path: String) -> void:
		var handler: Variant = behavior.get("handler")
		var params := _dictionary(behavior.get("params"), path + ".params")
		if not _choice(handler, ["use_ability", "pursue", "hold", "rescue", "threat", "escort"], path + ".handler"):
			return
		path += ".params."
		if handler in ["use_ability", "pursue", "rescue", "threat"]:
			_check_behavior_ability(handler, params, path + "ability")
		if handler in ["pursue", "threat", "escort"]:
			var move: Variant = params.get("move_ability")
			if _ref(move, "abilities", path + "move_ability") and not is_same(_defs.abilities[move].get("handler"), "move"):
				_error(path + "move_ability", "ability must use the move handler")
		if handler == "pursue":
			_text(params.get("team"), path + "team")
		elif handler == "threat":
			_integer(params.get("pursue_range"), path + "pursue_range", 1)
			_id_list(params.get("fallback_teams"), path + "fallback_teams")
			var status: Variant = params.get("taunt_status")
			if _ref(status, "statuses", path + "taunt_status") and not is_same(_defs.statuses[status].get("handler"), "retarget"):
				_error(path + "taunt_status", "status must use the retarget handler")

	func _check_behavior_ability(handler: String, params: Dictionary, path: String) -> void:
		var id: Variant = params.get("ability")
		if not _ref(id, "abilities", path):
			return
		var ability: Dictionary = _defs.abilities[id]
		var targeting: Variant = ability.get("targeting")
		if not targeting is Dictionary:
			return
		if handler == "use_ability":
			if targeting.get("kind") not in ["none", "automatic"]:
				_error(path, "use_ability requires an ability without an explicit target")
			return
		if not is_same(targeting.get("kind"), "entity"):
			_error(path, "%s requires entity targeting" % handler)
		if handler == "rescue" and not is_same(ability.get("handler"), "pull"):
			_error(path, "rescue requires an ability with the pull handler")
		if handler == "threat" and ability.get("handler") not in ["attack", "bonk", "blast"]:
			_error(path, "threat requires a damaging attack ability (attack, bonk, or blast)")
		if handler == "pursue":
			var teams: Variant = targeting.get("teams")
			if teams is Array and not teams.is_empty() and params.get("team") not in teams:
				_error(path, "ability cannot target the pursued team '%s'" % str(params.get("team")))

	func _check_status(status: Dictionary, path: String) -> void:
		_text(status.get("label"), path + ".label")
		var handler: Variant = status.get("handler")
		if not _choice(handler, STATUS_EXPIRY.keys(), path + ".handler"):
			return
		_choice(status.get("expiry"), [STATUS_EXPIRY[handler]], path + ".expiry")
		var params := _dictionary(status.get("params"), path + ".params")
		match handler:
			"reflect":
				_integer(params.get("range"), path + ".params.range")
				_check_target_filters(params, path + ".params")
			"retarget":
				if params.has("teams"):
					_id_list(params.teams, path + ".params.teams")
			"skip_action":
				pass

	func _check_profile(data: Dictionary, path: String) -> void:
		_text(data.get("team"), path + ".team")
		_text(data.get("art_key"), path + ".art_key")
		_integer(data.get("max_hp"), path + ".max_hp", 1)
		_id_list(data.get("capabilities"), path + ".capabilities", "capabilities")
		var abilities := _id_list(data.get("abilities"), path + ".abilities", "abilities")
		var habits := _dictionary(data.get("habits"), path + ".habits")
		for order in habits:
			var habit_path := "%s.habits.%s" % [path, order]
			_ref(str(order), "orders", habit_path + " order ID")
			_behavior_for_kit(habits[order], abilities, habit_path)
		if data.has("default_order"):
			if _ref(data.default_order, "orders", path + ".default_order") and not habits.has(data.default_order):
				_error(path + ".default_order", "order is not in habits")
		if data.has("behavior"):
			_behavior_for_kit(data.behavior, abilities, path + ".behavior")
		if data.has("color"):
			_color(data.color, path + ".color")
		if data.has("art_variant"):
			_text(data.art_variant, path + ".art_variant")

	func _behavior_for_kit(behavior: Variant, abilities: Array, path: String) -> void:
		if not _ref(behavior, "behaviors", path):
			return
		var params: Variant = _defs.behaviors[behavior].get("params")
		if not params is Dictionary:
			return
		for field in ["ability", "move_ability"]:
			var ability: Variant = params.get(field)
			if ability is String and ability not in abilities:
				_error(path, "behavior '%s' requires '%s' in the effective ability kit" % [behavior, ability])

	func _check_character(character: Dictionary, path: String) -> void:
		_text(character.get("label"), path + ".label")
		if _ref(character.get("class"), "classes", path + ".class"):
			_check_profile(_defs.classes[character["class"]].merged(character, true), path)

	func _check_object(object: Dictionary, path: String) -> void:
		_text(object.get("label"), path + ".label")
		_text(object.get("art_key"), path + ".art_key")
		_integer(object.get("max_hp"), path + ".max_hp", 1)
		_id_list(object.get("capabilities"), path + ".capabilities", "capabilities")

	func _check_board(board: Dictionary, path: String) -> void:
		_integer(board.get("width"), path + ".width", 1)
		_integer(board.get("height"), path + ".height", 1)
		_ref(board.get("default_tile"), "tiles", path + ".default_tile")
		var tiles := _array(board.get("tiles"), path + ".tiles")
		var occupied: Dictionary = {}
		for i in tiles.size():
			var tile_path := "%s.tiles[%d]" % [path, i]
			var tile := _dictionary(tiles[i], tile_path)
			var at: Variant = _board_position(tile.get("at"), board, tile_path + ".at")
			if at != null:
				if occupied.has(at):
					_error(tile_path + ".at", "duplicate tile at %s" % str(at))
				occupied[at] = tile.get("type")
			_ref(tile.get("type"), "tiles", tile_path + ".type")
		var locations := _dictionary(board.get("locations"), path + ".locations")
		for id in locations:
			_text(str(id), path + ".locations ID")
			var at: Variant = _board_position(locations[id], board, "%s.locations.%s" % [path, id])
			if at != null and _blocked(occupied.get(at, board.get("default_tile"))):
				_error("%s.locations.%s" % [path, id], "named location is on impassable terrain")
		if board.has("shore_cells"):
			var shore := _array(board.shore_cells, path + ".shore_cells")
			var seen: Dictionary = {}
			for i in shore.size():
				var cell_path := "%s.shore_cells[%d]" % [path, i]
				var at: Variant = _board_position(shore[i], board, cell_path)
				if at != null:
					if seen.has(at):
						_error(cell_path, "duplicate shore cell at %s" % str(at))
					seen[at] = true

	func _check_encounter(encounter: Dictionary, path: String) -> void:
		var board: Dictionary = {}
		if _ref(encounter.get("board"), "boards", path + ".board"):
			board = _defs.boards[encounter.board]
		if encounter.has("deadline"):
			_integer(encounter.deadline, path + ".deadline")
		var placements := _array(encounter.get("placements"), path + ".placements")
		var terrain := _terrain_index(board)
		var occupied: Dictionary = {}
		var ids: Dictionary = {}
		for i in placements.size():
			var place_path := "%s.placements[%d]" % [path, i]
			var placement := _dictionary(placements[i], place_path)
			var id: Variant = placement.get("id")
			if _text(id, place_path + ".id"):
				if ids.has(id):
					_error(place_path + ".id", "duplicate placement ID '%s'" % id)
				ids[id] = true
			if placement.has("character") == placement.has("object"):
				_error(place_path, "expected exactly one of character or object")
			elif placement.has("character"):
				_ref(placement.character, "characters", place_path + ".character")
			else:
				_ref(placement.object, "objects", place_path + ".object")
			var at: Variant = _board_position(placement.get("at"), board, place_path + ".at")
			if at != null:
				if occupied.has(at):
					_error(place_path + ".at", "placement overlaps '%s'" % occupied[at])
				if _blocked(terrain.get(at, board.get("default_tile"))):
					_error(place_path + ".at", "placement is on impassable terrain")
				occupied[at] = str(id)
		var slots := _array(encounter.get("party_slots", []), path + ".party_slots")
		for i in slots.size():
			var slot_path := "%s.party_slots[%d]" % [path, i]
			var at: Variant = _board_position(slots[i], board, slot_path)
			if at != null:
				if occupied.has(at):
					_error(slot_path, "slot overlaps '%s'" % occupied[at])
				if _blocked(terrain.get(at, board.get("default_tile"))):
					_error(slot_path, "slot is on impassable terrain")
				occupied[at] = "party slot"

	func _check_mission(mission: Dictionary, path: String) -> void:
		_text(mission.get("title"), path + ".title")
		if mission.has("tier"):
			_integer(mission.tier, path + ".tier", 1)
		var encounter: Dictionary = {}
		if _ref(mission.get("encounter"), "encounters", path + ".encounter"):
			encounter = _defs.encounters[mission.encounter]
		var objective := _dictionary(mission.get("objective"), path + ".objective")
		var objective_handler := ""
		if _choice(objective.get("handler"), ["escort", "defeat_all"], path + ".objective.handler"):
			objective_handler = objective.handler
		if objective_handler == "defeat_all" and objective.has("team"):
			_text(objective.team, path + ".objective.team")
		for field in ["text", "victory_text", "defeat_text", "victory_event"]:
			_text(objective.get(field), path + ".objective." + field)
		var subject: Variant = objective.get("subject")
		if objective_handler == "escort" and _text(subject, path + ".objective.subject") and not encounter.is_empty():
			var found := false
			var placements: Variant = encounter.get("placements")
			if placements is Array:
				for placement in placements:
					if placement is Dictionary and is_same(placement.get("id"), subject) and placement.has("character"):
						found = true
						break
			if not found:
				_error(path + ".objective.subject", "no character placement has ID '%s'" % subject)
		var destination: Variant = objective.get("destination")
		if objective_handler == "escort" and _text(destination, path + ".objective.destination") and not encounter.is_empty():
			var board: Dictionary = _defs.boards.get(encounter.get("board"), {})
			var locations: Variant = board.get("locations")
			if locations is Dictionary and not locations.has(destination):
				_error(path + ".objective.destination", "unknown board location '%s'" % destination)
		var failures := _array(mission.get("failures"), path + ".failures")
		var seen: Dictionary = {}
		for i in failures.size():
			var failure_path := "%s.failures[%d]" % [path, i]
			var failure := _dictionary(failures[i], failure_path)
			var handler: Variant = failure.get("handler")
			if _choice(handler, ["subject_dead", "deadline", "party_wiped"], failure_path + ".handler"):
				if seen.has(handler):
					_error(failure_path + ".handler", "duplicate failure '%s'" % handler)
				seen[handler] = true
				if handler == "deadline" and not _is_integer(encounter.get("deadline"), 1):
					_error(failure_path, "deadline failure requires a positive encounter deadline")
				if handler == "subject_dead" and objective_handler != "escort":
					_error(failure_path, "subject_dead requires an escort objective")
			_text(failure.get("event"), failure_path + ".event")

	func _check_adventure(adventure: Dictionary, path: String) -> void:
		_text(adventure.get("label"), path + ".label")
		_integer(adventure.get("party_size"), path + ".party_size", 1)
		var roster := _id_list(adventure.get("roster"), path + ".roster", "characters")
		var missions := _id_list(adventure.get("missions"), path + ".missions", "missions")
		if missions.is_empty():
			_error(path + ".missions", "requires at least one mission")
		var party_size: Variant = adventure.get("party_size")
		if not _is_integer(party_size, 1):
			return
		if roster.size() < int(party_size):
			_error(path + ".roster", "roster is smaller than party size")
		for id in roster:
			if id is String and _defs.characters.has(id):
				var character: Dictionary = _defs.characters[id]
				var hero: Dictionary = _defs.classes.get(character.get("class"), {}).merged(character, true)
				var capabilities: Variant = hero.get("capabilities")
				if hero.get("team") != "heroes" or not capabilities is Array or not "commandable" in capabilities:
					_error(path + ".roster", "character '%s' is not a commandable hero" % id)
		for id in missions:
			if not id is String or not _defs.missions.has(id):
				continue
			var encounter: Dictionary = _defs.encounters.get(_defs.missions[id].get("encounter"), {})
			var slots: Variant = encounter.get("party_slots", [])
			if not slots is Array or slots.size() != int(party_size):
				_error(path + ".missions", "mission '%s' must have exactly %d party slots" % [id, int(party_size)])
			var placements: Variant = encounter.get("placements", [])
			if placements is Array:
				for placement in placements:
					if placement is Dictionary and placement.get("id") in roster:
						_error(path + ".missions", "mission '%s' placement collides with roster ID" % id)

	func _terrain_index(board: Dictionary) -> Dictionary:
		var result: Dictionary = {}
		var tiles: Variant = board.get("tiles")
		if tiles is Array:
			for tile in tiles:
				if tile is Dictionary and _is_coordinate(tile.get("at")):
					result[position(tile.at)] = tile.get("type")
		return result

	func _blocked(tile_id: Variant) -> bool:
		return tile_id is String and is_same(_defs.tiles.get(tile_id, {}).get("passable"), false)

	func _board_position(value: Variant, board: Dictionary, path: String) -> Variant:
		if not _is_coordinate(value):
			_error(path, "expected [x, y] with nonnegative integers")
			return null
		var at := position(value)
		if _is_integer(board.get("width"), 1) and _is_integer(board.get("height"), 1):
			if at.x >= int(board.width) or at.y >= int(board.height):
				_error(path, "coordinate %s lies outside the board" % str(at))
				return null
		return at

	static func _is_coordinate(value: Variant) -> bool:
		return value is Array and value.size() == 2 and _is_integer(value[0]) and _is_integer(value[1])

	static func position(value: Array) -> Vector2i:
		return Vector2i(int(value[0]), int(value[1]))

	func _id_list(value: Variant, path: String, table := "") -> Array:
		var items := _array(value, path)
		var seen: Dictionary = {}
		for i in items.size():
			var item_path := "%s[%d]" % [path, i]
			var item: Variant = items[i]
			var valid := _text(item, item_path) if table.is_empty() else _ref(item, table, item_path)
			if valid:
				if seen.has(item):
					_error(item_path, "duplicate ID '%s'" % item)
				seen[item] = true
		return items

	func _ref(value: Variant, table: String, path: String) -> bool:
		if not _text(value, path):
			return false
		if not _defs[table].has(value):
			_error(path, "unknown %s ID '%s'" % [table, value])
			return false
		return true

	func _choice(value: Variant, choices: Array, path: String) -> bool:
		if not value is String or value not in choices:
			_error(path, "expected one of %s" % str(choices))
			return false
		return true

	func _dictionary(value: Variant, path: String) -> Dictionary:
		if value is Dictionary:
			return value
		_error(path, "expected a dictionary")
		return {}

	func _array(value: Variant, path: String) -> Array:
		if value is Array:
			return value
		_error(path, "expected an array")
		return []

	func _text(value: Variant, path: String, allow_empty := false) -> bool:
		if value is String and (allow_empty or not value.strip_edges().is_empty()):
			return true
		_error(path, "expected a string" if allow_empty else "expected a nonempty string")
		return false

	func _color(value: Variant, path: String) -> void:
		if not value is String or not Color.html_is_valid(value):
			_error(path, "expected a hexadecimal color")

	func _boolean(value: Variant, path: String) -> void:
		if not value is bool:
			_error(path, "expected a boolean")

	func _integer(value: Variant, path: String, minimum := 0) -> void:
		if not _is_integer(value, minimum):
			_error(path, "expected a whole number from %d to 2147483647" % minimum)

	static func _is_integer(value: Variant, minimum := 0) -> bool:
		# JSON.parse produces floats even when the authored number is integral.
		return (value is int or value is float) and value >= minimum and value <= 2147483647 and floorf(value) == value

	func _error(path: String, message: String) -> void:
		_errors.append("%s: %s" % [path, message])
