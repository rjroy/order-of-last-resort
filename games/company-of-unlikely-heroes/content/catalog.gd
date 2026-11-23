extends RefCounted
## Reads authored JSON and builds independent encounters without embedding definitions in snapshots.

const DEFAULT_PATH := "res://content/catalog.json"
const Rewards = preload("res://rewards.gd")
const Objectives = preload("res://content/objectives.gd")
const TABLES := ["missions", "encounters", "boards", "tiles", "classes", "characters",
	"capabilities", "objects", "abilities", "orders", "behaviors", "statuses", "events", "presentation"]
const COMMISSION_TABLES := ["commission_settings", "mission_kinds", "mission_reports"]
const REQUIRED_EVENTS := ["move", "damage", "knockdown_suffix", "reflect_absorb", "reflect_redirect",
	"push", "collision_suffix", "aura", "taunt", "heal", "heal_full", "blast_suffix", "pull",
	"recoil_source", "cannot_advance", "recover", "hold", "invalid", "watches", "gain_status"]
const ABILITY_TARGETING := {
	"move": ["cell"], "apply_status": ["none"],
	"push": ["entity", "automatic"], "bonk": ["entity", "automatic"], "heal": ["entity", "automatic"],
	"enemy_heal": ["automatic"],
	"blast": ["entity", "automatic"], "pull": ["entity", "automatic"], "attack": ["entity", "automatic"],
	"swap_furthest": ["automatic"], "swap_ally": ["automatic"], "misdirect": ["entity"],
	"summon": ["cell", "entity"], "sweep": ["none"], "repel": ["automatic"], "stop_target": ["automatic"],
	"perform": ["automatic"], "hook": ["entity", "automatic"], "nominate": ["entity"],
	"healing_potion": ["entity"], "acid": ["entity"], "plain_tonic": ["entity"], "repeat_batch": ["entity"],
}
const ABILITY_EVENTS := {"swap_furthest": ["swap"], "swap_ally": ["swap"], "misdirect": ["misdirect_mark"],
	"sweep": ["sweep"], "stop_target": ["stop_target"], "repel": ["repel"],
	"perform": ["performance_dry"], "hook": ["hook_pull"]}
const CAST_ACTION_HANDLERS := ["move", "attack", "hook", "push", "blast", "enemy_heal", "swap_ally", "perform"]
const CAST_EVENTS := ["recover", "adjacent_guard", "adjacent_damage_bonus", "ally_death_guard",
	"retaliate", "swapped", "displaced", "reserve_arrival", "tactical_retreat",
	"sheep_flee", "sheep_entry", "wagon_advance", "wagon_stall", "leave_zone"]
const CAST_HOLDS := ["sheep_penned", "wagon_wreck"]
const CAST_BONUS_STATS := {"attack": "damage", "move": "movement"}
const STATUS_EXPIRY := {"reflect": "actor_turn_start", "skip_action": "consume_action",
	"retarget": "actor_turn_end", "misdirect": "consume_attack", "stop_move": "actor_turn_end",
	"block_voluntary_move": "consume_move"}
const REWARD_EFFECTS := ["max_hp", "shield_damage", "dig_in", "shield_throw", "wide_guard",
	"bonk_damage", "heal_amount", "long_staff", "strong_swing", "me_or_you",
	"blast_damage", "padded_landing", "demolition_practice", "duck", "braced_casting", "parting_gift", "conductive_personality",
	"cheap_shot", "exit_strategy", "borrowed_courage", "pass_the_buck", "pocket_sand", "long_finger", "body_double",
	"sonnet_damage", "buskers_hat", "front_row_seats", "laughing_fit", "heckler", "house_lights",
	"spare_ribs", "good_soil", "heavy_bouquet", "broad_wave", "long_stemmed", "warm_welcome",
	"say_hello_to_that_one", "wake_reception", "stronger_dose", "concentrate", "long_ladle",
	"spare_vial", "brittle_glass", "keep_the_culture"]
const REWARD_FIELDS := ["hero_id", "rarity", "cap", "label", "description", "effect", "amount",
	"ability", "order", "behavior", "requires_abilities", "requires_any_ability"]
const REWARD_GRANTS := {
	"shield_throw": {"ability": "knight_shield_throw", "handler": "attack", "kind": "entity"},
	"house_lights": {"ability": "bard_take_the_stage", "handler": "perform", "kind": "automatic"},
	"say_hello_to_that_one": {"ability": "necromancer_say_hello_to_that_one", "handler": "nominate", "kind": "entity"},
	"spare_vial": {"ability": "alchemist_plain_tonic", "handler": "plain_tonic", "kind": "entity"},
	"keep_the_culture": {"ability": "alchemist_repeat_batch", "handler": "repeat_batch", "kind": "entity"},
}


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
				# Merge keys regardless of value shape: settings map keys to scalars.
				for id in records:
					if defs[table].has(id):
						return {"error": "Duplicate %s ID '%s' in content part \"%s\"." % [table, id, part_path]}
					defs[table][id] = records[id]
	var errors := validate(defs)
	if errors.is_empty() and path == DEFAULT_PATH:
		errors = validate_guild_progression(defs)
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


## Guild appointments are opted in separately from ordinary catalog play.
## External practice fixtures may retain this section without using its kits.
static func validate_guild_progression(defs: Dictionary) -> PackedStringArray:
	return Validator.new(defs).check_guild_progression()


## Standalone playtests have no guild roster; the authored kit owners are the
## relevant roster for validating the same progression tables.
static func validate_playtest_progression(defs: Dictionary) -> PackedStringArray:
	var guild: Variant = defs.get("guild_progression")
	if not guild is Dictionary:
		return PackedStringArray(["guild_progression: expected a dictionary"])
	var kits: Variant = guild.get("kits")
	if not kits is Dictionary:
		return PackedStringArray(["guild_progression.kits: expected a dictionary"])
	return Validator.new(defs).check_guild_progression(kits.keys())


static func behavior_ability_ids(behavior: Dictionary) -> Array[String]:
	return Validator.behavior_ability_ids(behavior)


static func profile(defs: Dictionary, character_id: String) -> Dictionary:
	var character: Dictionary = defs.get("characters", {}).get(character_id, {})
	if character.is_empty():
		return {}
	var defaults: Dictionary = defs.get("classes", {}).get(character.get("class", ""), {})
	return defaults.merged(character, true)


static func build(defs: Dictionary, mission_id: String, chosen_ids: Array = [], fallback_dose_seed := 1) -> Dictionary:
	if not _report_errors("Catalog", validate(defs)):
		return {}
	if not defs.missions.has(mission_id):
		push_error("Catalog: unknown mission '%s'" % mission_id)
		return {}
	var mission: Dictionary = defs.missions[mission_id]
	var encounter: Dictionary = defs.encounters[mission.encounter]
	var board: Dictionary = defs.boards[encounter.board]
	var objective := Objectives.build(mission.objective, board)
	var reserve_ids: Array = mission.objective.get("reserve_placements", []) if objective.handler == "survive" else []
	var reserves: Array = []
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
		units.append({"id": id, "character_id": id, "position": Objectives.position(slots[i]),
			"statuses": {}, "hp": int(unit_profile.max_hp), "max_hp": int(unit_profile.max_hp)})
		if unit_profile.has("default_order"):
			orders[id] = unit_profile.default_order
	for placement in encounter.placements:
		var instance := {"id": placement.id, "position": Objectives.position(placement.at), "statuses": {}}
		if placement.has("character"):
			var unit_profile := profile(defs, placement.character)
			instance.merge({"character_id": placement.character,
				"hp": int(placement.get("hp", unit_profile.max_hp)), "max_hp": int(unit_profile.max_hp)})
			if placement.id in reserve_ids:
				reserves.append(instance)
				continue
			units.append(instance)
			if unit_profile.has("default_order"):
				orders[placement.id] = unit_profile.default_order
		else:
			var hp := int(defs.objects[placement.object].max_hp)
			instance.merge({"object_id": placement.object, "hp": int(placement.get("hp", hp)), "max_hp": hp})
			obstacles.append(instance)
	if not reserves.is_empty():
		objective["reserves"] = reserves
	var terrain: Array = []
	for tile in board.tiles:
		terrain.append({"position": Objectives.position(tile.at), "type": tile.type})
	return {"catalog": FrozenCatalog.new(defs),
		"mission_id": mission_id, "encounter_id": mission.encounter, "board_id": encounter.board,
		"objective": objective,
		"width": int(board.width), "height": int(board.height), "default_tile": board.default_tile,
		"units": units, "obstacles": obstacles, "terrain": terrain,
		"round": 1, "orders": orders, "overrides": {}, "outcome": "ongoing",
		"rng_state": int(encounter.get("seed", 1)), "dose_seed": int(encounter.get("seed", fallback_dose_seed))}


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
		if COMMISSION_TABLES.any(func(table: String) -> bool: return _defs.has(table)):
			_check_commissions()
		if _defs.has("reward_weights"):
			_check_reward_weights(_dictionary(_defs.reward_weights, "reward_weights"))
		if _defs.has("upgrades"):
			var upgrades := _dictionary(_defs.upgrades, "upgrades")
			for id in upgrades:
				var path := "upgrades." + str(id)
				_text(str(id), path)
				if upgrades[id] is Dictionary:
					_check_reward(upgrades[id], path)
				else:
					_error(path, "expected a dictionary")
		return _errors

	func check_guild_progression(playtest_roster: Variant = null) -> PackedStringArray:
		var path := "guild_progression"
		var guild := _dictionary(_defs.get(path), path)
		if not _errors.is_empty():
			return _errors
		_guild_fields(guild, ["kits", "petitions", "starting_habits"], path)
		var kits := _dictionary(guild.get("kits"), path + ".kits")
		var petitions := _dictionary(guild.get("petitions"), path + ".petitions")
		var starting := _dictionary(guild.get("starting_habits", {}), path + ".starting_habits")
		var roster_id: Variant = _record(_defs, "commission_settings").get("roster_adventure")
		var roster: Variant = playtest_roster if playtest_roster != null else \
			_record(_record(_defs, "adventures"), roster_id if roster_id is String else "").get("roster")
		if not roster is Array:
			_error(path, "requires a commission roster")
			return _errors
		for hero_id in kits:
			var kit_path := path + ".kits." + str(hero_id)
			if hero_id not in roster:
				_error(kit_path, "hero is not in the commission roster")
				continue
			var hero := _character_profile(hero_id)
			var abilities: Variant = hero.get("abilities")
			var slots := _dictionary(kits[hero_id], kit_path)
			if slots.is_empty():
				_error(kit_path, "requires at least one ability slot")
			var defaults := []
			for slot_id in slots:
				var slot_path := kit_path + "." + str(slot_id)
				_text(slot_id, slot_path)
				var id: Variant = slots[slot_id]
				if not id is String or not abilities is Array or id not in abilities or id in defaults \
						or _record(_record(_defs, "abilities"), id).get("handler") == "move":
					_error(slot_path, "expected a distinct non-Move ability from the hero's base kit")
				defaults.append(id)
		for hero_id in roster:
			if not kits.has(hero_id):
				_error(path + ".kits", "missing ability slots for '%s'" % hero_id)
		for hero_id in starting:
			var habit_path := path + ".starting_habits." + str(hero_id)
			if not kits.has(hero_id):
				_error(habit_path, "expected a hero with a guild kit")
				continue
			var hero := _character_profile(hero_id)
			var habits := _dictionary(starting[hero_id], habit_path)
			for order in habits:
				_ref(order, "orders", habit_path + "." + str(order))
				_behavior_for_kit(habits[order], hero.get("abilities", []), habit_path + "." + str(order))
			if hero.has("default_order") and not habits.has(hero.default_order):
				_error(habit_path, "must include the hero's default order")
		for id in petitions:
			_check_petition(kits, petitions, id)
		var benefits := {}
		for id in petitions:
			var grant := _record(_record(petitions, id), "grant")
			if not grant.is_empty():
				var benefit := JSON.stringify(grant)
				if benefits.has(benefit):
					_error(path + ".petitions." + str(id), "duplicates the benefit of '%s'" % benefits[benefit])
				benefits[benefit] = id
		if _errors.is_empty():
			var visited := {}
			for id in petitions:
				_check_petition_cycle(petitions, id, [], visited)
		return _errors

	func _check_petition(kits: Dictionary, petitions: Dictionary, id: String) -> void:
		var path := "guild_progression.petitions." + id
		var spec := _dictionary(petitions[id], path)
		_text(id, path)
		_guild_fields(spec, ["label", "description", "cost", "prerequisites", "grant", "teaser"], path)
		_text(spec.get("label"), path + ".label")
		_text(spec.get("description"), path + ".description")
		if spec.has("teaser"):
			_boolean(spec.teaser, path + ".teaser")
		var deps := _id_list(spec.get("prerequisites", []), path + ".prerequisites")
		for dep in deps:
			if dep is String and (not petitions.has(dep) or _record(petitions, dep).get("teaser", false)):
				_error(path + ".prerequisites", "unknown or unavailable dependency '%s'" % dep)
		if spec.get("teaser", false) == true:
			if spec.has("grant") or spec.has("cost"):
				_error(path, "a teaser cannot grant anything or have a cost")
			return
		_integer(spec.get("cost"), path + ".cost", 1)
		var grant := _dictionary(spec.get("grant"), path + ".grant")
		var hero_id: Variant = grant.get("hero_id")
		if not hero_id is String or not kits.has(hero_id):
			_error(path + ".grant.hero_id", "expected a hero with a guild kit")
			return
		match grant.get("kind"):
			"recruit":
				_guild_fields(grant, ["kind", "hero_id"], path + ".grant")
			"ability":
				_guild_fields(grant, ["kind", "hero_id", "slot_id", "ability_id"], path + ".grant")
				var slot: Variant = grant.get("slot_id")
				if not slot is String or not _record(kits, hero_id).has(slot):
					_error(path + ".grant.slot_id", "unknown slot for '%s'" % hero_id)
				var ability: Variant = grant.get("ability_id")
				var action := _record(_record(_defs, "abilities"), ability if ability is String else "")
				if action.is_empty() or action.get("handler") == "move" \
						or ability in _character_profile(hero_id).get("abilities", []):
					_error(path + ".grant.ability_id", "expected a new non-Move ability for this hero")
			"order":
				_guild_fields(grant, ["kind", "hero_id", "order_id", "behavior_id"], path + ".grant")
				_ref(grant.get("order_id"), "orders", path + ".grant.order_id")
				_ref(grant.get("behavior_id"), "behaviors", path + ".grant.behavior_id")
				var starting: Dictionary = _record(_record(_defs, "guild_progression"), "starting_habits")
				var habits: Dictionary = _character_profile(hero_id).get("habits", {})
				if starting.has(hero_id):
					habits = _record(starting, hero_id)
				if grant.get("order_id") in habits:
					_error(path + ".grant.order_id", "already in this hero's base orders")
			"effect":
				_guild_fields(grant, ["kind", "hero_id", "effect_id"], path + ".grant")
				_choice(grant.get("effect_id"), ["song_weaving"], path + ".grant.effect_id")
			_:
				_error(path + ".grant.kind", "expected recruit, ability, order or effect")

	func _check_petition_cycle(petitions: Dictionary, id: String, active: Array, visited: Dictionary) -> void:
		if id in active:
			_error("guild_progression.petitions." + id + ".prerequisites", "cyclic petition dependency")
			return
		if visited.has(id):
			return
		active.append(id)
		for dependency in petitions[id].get("prerequisites", []):
			_check_petition_cycle(petitions, dependency, active, visited)
		active.pop_back()
		visited[id] = true

	func _guild_fields(record: Dictionary, fields: Array, path: String) -> void:
		for field in record:
			if field not in fields:
				_error(path + "." + str(field), "unknown guild progression field")

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
		for ability in _defs.abilities.values():
			for id in ABILITY_EVENTS.get(ability.get("handler", ""), []):
				_ref(id, "events", "events." + id)
		for status in _defs.statuses.values():
			if is_same(status.get("handler", ""), "misdirect"):
				for id in ["misdirect_redirect", "misdirect_missing"]:
					_ref(id, "events", "events." + id)

	func _check_ability(ability: Dictionary, path: String) -> void:
		_text(ability.get("label"), path + ".label")
		_text(ability.get("help"), path + ".help")
		var handler: Variant = ability.get("handler")
		if not _choice(handler, ABILITY_TARGETING.keys(), path + ".handler"):
			return
		var targeting := _dictionary(ability.get("targeting"), path + ".targeting")
		var authored_kind: Variant = targeting.get("kind")
		var kind := ""
		if _choice(authored_kind, ABILITY_TARGETING[handler], path + ".targeting.kind"):
			kind = authored_kind
		if targeting.has("range"):
			if handler == "move" or (handler == "summon" and kind == "cell"):
				if not _is_integer(targeting.range, 1) or int(targeting.range) != 1:
					_error(path + ".targeting.range", "supports only an adjacent cell")
			elif handler == "apply_status":
				_error(path + ".targeting.range", "apply_status has no target range")
			else:
				_integer(targeting.range, path + ".targeting.range", 2 if handler == "hook" else 1)
		if kind == "cell" or handler in ["apply_status", "sweep"]:
			for filter in ["teams", "objects", "capabilities"]:
				if targeting.has(filter):
					_error(path + ".targeting." + filter, "requires entity or automatic targeting")
		else:
			_check_target_filters(targeting, path + ".targeting")
		var params := _dictionary(ability.get("params"), path + ".params")
		var param_path := path + ".params."
		for flag in ["allied_only", "hostile_only", "allow_self"]:
			if params.has(flag):
				_boolean(params[flag], param_path + flag)
				var expected := {"allied_only": "hook", "hostile_only": "stop_target", "allow_self": "heal"}
				if handler != expected[flag]:
					_error(param_path + flag, "not supported by this ability handler")
		if params.has("opponents_only"):
			_boolean(params.opponents_only, param_path + "opponents_only")
			if handler not in ["attack", "repel", "stop_target", "sweep"]:
				_error(param_path + "opponents_only", "not supported by this ability handler")
		if params.has("damage_ability") and handler != "perform":
			_error(param_path + "damage_ability", "requires the perform handler")
		if params.has("prefer_wounded_self"):
			_boolean(params.prefer_wounded_self, param_path + "prefer_wounded_self")
			if handler != "heal" or kind != "automatic":
				_error(param_path + "prefer_wounded_self", "requires automatic heal targeting")
		match handler:
			"move":
				pass
			"push":
				_integer(params.get("collision_damage"), param_path + "collision_damage")
			"apply_status":
				_ref(params.get("status"), "statuses", param_path + "status")
			"misdirect":
				var status: Variant = params.get("status")
				if _ref(status, "statuses", param_path + "status") and not is_same(_defs.statuses[status].get("handler"), "misdirect"):
					_error(param_path + "status", "status must use the misdirect handler")
			"bonk", "blast":
				_integer(params.get("damage"), param_path + "damage")
				_ref(params.get("status"), "statuses", param_path + "status")
			"heal":
				_integer(params.get("amount"), param_path + "amount")
			"healing_potion", "plain_tonic", "acid":
				var field := "damage" if handler == "acid" else "amount"
				_integer(params.get(field), param_path + field, 1)
				_integer(targeting.get("range"), path + ".targeting.range", 1)
				if is_same(targeting.get("objects"), true):
					_error(path + ".targeting.objects", "doses only target living characters")
			"repeat_batch":
				for field in ["range", "teams", "objects", "capabilities"]:
					if targeting.has(field):
						_error(path + ".targeting." + field, "repeat_batch takes its targeting from the bottled recipe")
			"enemy_heal":
				_integer(params.get("amount"), param_path + "amount", 1)
				_integer(params.get("charges"), param_path + "charges", 1)
				var teams: Variant = targeting.get("teams")
				if not teams is Array or teams.size() != 1 or not is_same(teams[0], "enemies"):
					_error(path + ".targeting.teams", "enemy_heal targets only the enemies team")
				if is_same(targeting.get("objects"), true):
					_error(path + ".targeting.objects", "enemy_heal only targets characters")
			"pull":
				_integer(params.get("recoil_damage"), param_path + "recoil_damage")
				_ref(params.get("status"), "statuses", param_path + "status")
			"attack":
				_integer(params.get("damage"), param_path + "damage")
				if params.has("status"):
					_ref(params.status, "statuses", param_path + "status")
				if params.has("surround_bonus"):
					var bonus := _dictionary(params.surround_bonus, param_path + "surround_bonus")
					_ref(bonus.get("character"), "characters", param_path + "surround_bonus.character")
					_integer(bonus.get("damage"), param_path + "surround_bonus.damage", 1)
					_ref("surround_bonus", "events", param_path + "surround_bonus event")
			"swap_ally":
				_ref(params.get("character"), "characters", param_path + "character")
				_integer(params.get("range"), param_path + "range", 1)
			"summon":
				var id: Variant = params.get("character")
				if _ref(id, "characters", param_path + "character"):
					var spec := _effective_profile(_defs.characters[id])
					var capabilities: Variant = spec.get("capabilities")
					if not capabilities is Array or not "minion" in capabilities or "commandable" in capabilities:
						_error(param_path + "character", "summoned character must be a non-commandable minion")
				_integer(params.get("priority"), param_path + "priority")
				if not kind.is_empty():
					var event := "raise" if kind == "entity" else "summon"
					_ref(event, "events", "events." + event)
			"sweep":
				_integer(params.get("damage"), param_path + "damage", 1)
				_integer(targeting.get("range"), path + ".targeting.range", 1)
			"stop_target":
				var status: Variant = params.get("status")
				if _ref(status, "statuses", param_path + "status") \
						and _defs.statuses[status].get("handler") not in ["stop_move", "block_voluntary_move"]:
					_error(param_path + "status", "status must use a movement-blocking handler")
			"perform":
				_check_performance(params, targeting, path)
			"nominate":
				if is_same(targeting.get("objects"), true):
					_error(path + ".targeting.objects", "nominate only targets living opponents")
		if handler in ["bonk", "blast", "attack"] and params.has("source_suffix"):
			_text(params.source_suffix, param_path + "source_suffix", true)

	func _check_performance(params: Dictionary, targeting: Dictionary, path: String) -> void:
		if is_same(targeting.get("objects"), true):
			_error(path + ".targeting.objects", "perform only targets living opponents")
		var param_path := path + ".params."
		if params.has("status"):
			for field in ["damage", "damage_ability"]:
				if params.has(field):
					_error(param_path + field, "a status performance cannot also deal damage")
			_ref(params.status, "statuses", param_path + "status")
		elif params.has("damage_ability"):
			if params.has("damage"):
				_error(param_path + "damage", "cannot specify damage when using damage_ability")
			var source: Variant = params.damage_ability
			if _ref(source, "abilities", param_path + "damage_ability"):
				var spec: Dictionary = _defs.abilities[source]
				var source_params: Variant = spec.get("params")
				if not is_same(spec.get("handler"), "perform") or not source_params is Dictionary \
						or source_params.has("status") or source_params.has("damage_ability") \
						or not _is_integer(source_params.get("damage"), 1):
					_error(param_path + "damage_ability", "must refer to a performance with its own damage")
		else:
			_integer(params.get("damage"), param_path + "damage", 1)
		_ref(params.get("listener_event"), "events", param_path + "listener_event")

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
		if not _choice(handler, ["use_ability", "pursue", "hold", "rescue", "threat", "escort",
				"retreat", "greet", "hook_and_seek", "follow_party", "retreat_attack",
				"finite_healer", "swap_ally", "follow_ally", "most_injured", "nearest_target",
				"pass_blame", "make_friend"], path + ".handler"):
			return
		path += ".params."
		if handler in ["use_ability", "pursue", "rescue", "threat", "hook_and_seek",
				"retreat_attack", "finite_healer", "swap_ally", "nearest_target", "most_injured"]:
			_check_behavior_ability(handler, params, path + "ability")
		if handler == "pass_blame":
			_check_behavior_action(params.get("ability"), "misdirect", "entity", path + "ability")
		if handler == "make_friend":
			_check_behavior_action(params.get("ability"), "summon", "cell", path + "ability")
		if handler in ["pursue", "threat", "escort", "retreat", "greet", "hook_and_seek",
				"follow_ally", "follow_party", "retreat_attack", "finite_healer", "swap_ally"]:
			var move: Variant = params.get("move_ability")
			if _ref(move, "abilities", path + "move_ability") and not is_same(_defs.abilities[move].get("handler"), "move"):
				_error(path + "move_ability", "ability must use the move handler")
		if handler in ["pursue", "retreat", "greet", "hook_and_seek", "retreat_attack", "finite_healer", "swap_ally"]:
			_text(params.get("team"), path + "team")
		if handler == "finite_healer":
			_check_behavior_action(params.get("heal_ability"), "enemy_heal", "automatic", path + "heal_ability")
			if not is_same(params.get("team"), "enemies"):
				_error(path + "team", "finite_healer supports healing the enemies team")
		if handler == "swap_ally":
			var ally: Variant = params.get("ally")
			var valid_ally := _ref(ally, "characters", path + "ally")
			var swap := _check_behavior_action(params.get("swap_ability"), "swap_ally", "automatic", path + "swap_ability")
			if valid_ally and not swap.is_empty() and not is_same(_record(swap, "params").get("character"), ally):
				_error(path + "swap_ability", "ability must target the behavior's ally '%s'" % ally)
		if handler in ["follow_party", "follow_ally"]:
			_ref(handler, "events", "events." + handler)
		if handler == "greet":
			_integer(params.get("greeting_range"), path + "greeting_range", 1)
			var greetings := _id_list(params.get("greetings"), path + "greetings", "abilities")
			if greetings.is_empty():
				_error(path + "greetings", "requires at least one greeting")
			for id in greetings:
				var targeting: Variant = _defs.abilities.get(id, {}).get("targeting")
				if targeting is Dictionary and targeting.get("kind") not in ["entity", "automatic", "none"]:
					_error(path + "greetings", "greeting '%s' cannot require a cell target" % str(id))
		if handler == "threat":
			_integer(params.get("pursue_range"), path + "pursue_range", 1)
			_id_list(params.get("fallback_teams"), path + "fallback_teams")
		if handler in ["threat", "hook_and_seek"]:
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
		if handler == "most_injured" and ability.get("handler") not in ["heal", "healing_potion", "plain_tonic"]:
			_error(path, "most_injured requires a healing ability")
		if handler == "hook_and_seek" and not is_same(ability.get("handler"), "hook"):
			_error(path, "hook_and_seek requires an ability with the hook handler")
		if handler == "threat" and ability.get("handler") not in ["attack", "bonk", "blast", "push"]:
			_error(path, "threat requires an attack, bonk, blast, or push ability")
		if handler in ["retreat_attack", "finite_healer", "swap_ally"] \
				and ability.get("handler") not in ["attack", "bonk", "blast"]:
			_error(path, "%s requires a damaging attack ability (attack, bonk, or blast)" % handler)
		if handler in ["pursue", "hook_and_seek", "retreat_attack", "swap_ally"]:
			var teams: Variant = targeting.get("teams")
			if teams is Array and not teams.is_empty() and params.get("team") not in teams:
				_error(path, "ability cannot target the pursued team '%s'" % str(params.get("team")))

	func _check_behavior_action(id: Variant, handler: String, kind: String, path: String) -> Dictionary:
		if not _ref(id, "abilities", path):
			return {}
		var ability: Dictionary = _defs.abilities[id]
		if not is_same(ability.get("handler"), handler) or not is_same(_record(ability, "targeting").get("kind"), kind):
			_error(path, "ability must use the %s handler with %s targeting" % [handler, kind])
			return {}
		return ability

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
				if params.has("immunity_rounds"):
					_integer(params.immunity_rounds, path + ".params.immunity_rounds", 1)
					_text(params.get("immune_label"), path + ".params.immune_label")
				if params.has("skip_event"):
					_ref(params.skip_event, "events", path + ".params.skip_event")
			"misdirect", "stop_move", "block_voluntary_move":
				pass

	func _check_profile(data: Dictionary, path: String) -> void:
		_text(data.get("team"), path + ".team")
		_text(data.get("art_key"), path + ".art_key")
		_integer(data.get("max_hp"), path + ".max_hp", 1)
		var capabilities := _id_list(data.get("capabilities"), path + ".capabilities", "capabilities")
		var abilities := _id_list(data.get("abilities"), path + ".abilities", "abilities")
		if "minion" in capabilities:
			for id in abilities:
				if is_same(_defs.abilities.get(id, {}).get("handler"), "summon"):
					_error(path + ".abilities", "minions cannot use summon ability '%s'" % id)
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
		if data.has("description"):
			_text(data.description, path + ".description", true)
		if data.has("traits"):
			_check_traits(data.traits, path + ".traits")

	func _check_traits(value: Variant, path: String) -> void:
		var traits := _array(value, path)
		for i in traits.size():
			var trait_path := "%s[%d]" % [path, i]
			var entry := _dictionary(traits[i], trait_path)
			var kind: Variant = entry.get("kind")
			if not _choice(kind, ["adjacent_guard", "adjacent_damage_bonus", "death_blast",
					"retaliate", "ally_death_bonus"], trait_path + ".kind"):
				continue
			match kind:
				"adjacent_guard":
					_ref(entry.get("protects"), "characters", trait_path + ".protects")
					_integer(entry.get("reduction"), trait_path + ".reduction", 1)
				"adjacent_damage_bonus":
					_ref(entry.get("benefits"), "characters", trait_path + ".benefits")
					_integer(entry.get("damage"), trait_path + ".damage", 1)
				"death_blast", "retaliate":
					_integer(entry.get("damage"), trait_path + ".damage", 1)
					_integer(entry.get("range"), trait_path + ".range", 1)
				"ally_death_bonus":
					var allies := _id_list(entry.get("allies"), trait_path + ".allies", "characters")
					if allies.is_empty():
						_error(trait_path + ".allies", "requires at least one allied character ID")
					var bonus_count := 0
					for field in ["damage", "reduction", "movement"]:
						if entry.has(field):
							bonus_count += 1
							_integer(entry[field], trait_path + "." + field, 1)
					if bonus_count != 1:
						_error(trait_path, "requires exactly one of damage, reduction, or movement")
					if entry.has("max_reduction"):
						_integer(entry.max_reduction, trait_path + ".max_reduction", 1)
						if not entry.has("reduction"):
							_error(trait_path + ".max_reduction", "requires a reduction bonus")

	func _behavior_for_kit(behavior: Variant, abilities: Array, path: String) -> void:
		if not _ref(behavior, "behaviors", path):
			return
		for ability in behavior_ability_ids(_defs.behaviors[behavior]):
			if ability not in abilities:
				_error(path, "behavior '%s' requires '%s' in the effective ability kit" % [behavior, ability])

	static func behavior_ability_ids(behavior: Dictionary) -> Array[String]:
		var result: Array[String] = []
		var params: Variant = behavior.get("params")
		if not params is Dictionary:
			return result
		var fields := ["ability", "move_ability"]
		match behavior.get("handler"):
			"finite_healer":
				fields.append("heal_ability")
			"swap_ally":
				fields.append("swap_ability")
		for field in fields:
			var id: Variant = params.get(field)
			if id is String and id not in result:
				result.append(id)
		var greetings: Variant = params.get("greetings")
		if greetings is Array:
			for id in greetings:
				if id is String and id not in result:
					result.append(id)
		return result

	func _check_character(character: Dictionary, path: String) -> void:
		_text(character.get("label"), path + ".label")
		if _ref(character.get("class"), "classes", path + ".class"):
			var profile := _effective_profile(character)
			_check_profile(profile, path)
			if character.has("cast_presentation"):
				_check_cast_presentation(character, profile, path)

	func _check_cast_presentation(character: Dictionary, profile: Dictionary, path: String) -> void:
		_text(character.get("cast_key"), path + ".cast_key")
		_text(character.get("cast_art_key"), path + ".cast_art_key")
		var capabilities: Variant = profile.get("capabilities", [])
		if not capabilities is Array:
			capabilities = []
		var abilities: Variant = profile.get("abilities", [])
		if not abilities is Array:
			abilities = []
		if character.has("cast_team"):
			_text(character.cast_team, path + ".cast_team")
		if character.has("cast_variant"):
			_text(character.cast_variant, path + ".cast_variant", true)
		var presentation := _dictionary(character.cast_presentation, path + ".cast_presentation")
		for field in presentation:
			if field not in ["actions", "hit", "defeat", "events", "holds"]:
				_error(path + ".cast_presentation." + str(field), "unknown presentation field")
		_check_cast_clips(presentation.get("events", {}), CAST_EVENTS, path + ".cast_presentation.events")
		_check_cast_clips(presentation.get("holds", {}), CAST_HOLDS, path + ".cast_presentation.holds")
		var actions := _dictionary(presentation.get("actions", {}), path + ".cast_presentation.actions")
		for id in actions:
			var action_path := path + ".cast_presentation.actions." + str(id)
			if _ref(id, "abilities", action_path) and id not in abilities:
				_error(action_path, "ability is not in the character's effective kit")
			var binding := _dictionary(actions[id], action_path)
			for field in binding:
				if field not in ["handler", "clip", "impact_frame", "bonus"]:
					_error(action_path + "." + str(field), "unknown binding field")
			_choice(binding.get("handler"), CAST_ACTION_HANDLERS, action_path + ".handler")
			if binding.get("handler") == "move" and "mobile" not in capabilities:
				_error(action_path, "move presentation requires the mobile capability")
			if _text(binding.get("clip"), action_path + ".clip") and binding.clip == "ready":
				_error(action_path + ".clip", "ready is reserved for idle presentation")
			if binding.has("impact_frame"):
				_integer(binding.impact_frame, action_path + ".impact_frame", 1)
			if binding.has("bonus"):
				var bonus_path := action_path + ".bonus"
				var bonus := _dictionary(binding.bonus, bonus_path)
				for field in bonus:
					if field not in ["stat", "clip"]:
						_error(bonus_path + "." + str(field), "unknown bonus field")
				var stat: String = CAST_BONUS_STATS.get(binding.get("handler"), "")
				if stat.is_empty() or bonus.get("stat") != stat:
					_error(bonus_path + ".stat", "stat does not apply to this handler")
				_check_cast_clip(bonus.get("clip"), bonus_path + ".clip")
		for field in ["hit", "defeat"]:
			if presentation.has(field):
				if "damageable" not in capabilities:
					_error(path + ".cast_presentation." + field, "requires the damageable capability")
				_check_cast_clip(presentation[field], path + ".cast_presentation." + field)

	func _check_cast_clips(value: Variant, kinds: Array, path: String) -> void:
		var clips := _dictionary(value, path)
		for kind in clips:
			var clip_path := path + "." + str(kind)
			_choice(kind, kinds, clip_path)
			_check_cast_clip(clips[kind], clip_path)

	func _check_cast_clip(value: Variant, path: String) -> void:
		if _text(value, path) and value == "ready":
			_error(path, "ready is reserved for idle presentation")

	func _effective_profile(character: Dictionary) -> Dictionary:
		return _defs.classes.get(character.get("class"), {}).merged(character, true)

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
			_check_board_cells(board.shore_cells, board, path + ".shore_cells", "shore cell")
		if board.has("zones"):
			var zones := _dictionary(board.zones, path + ".zones")
			for id in zones:
				_text(str(id), path + ".zones ID")
				var zone_path := "%s.zones.%s" % [path, id]
				var cells := _check_board_cells(zones[id], board, zone_path)
				if cells.is_empty():
					_error(zone_path, "requires at least one valid cell")
				for at in cells:
					if _blocked(occupied.get(at, board.get("default_tile"))):
						_error(zone_path, "zone cell %s is on impassable terrain" % str(at))

	func _check_board_cells(value: Variant, board: Dictionary, path: String, label := "cell") -> Dictionary:
		var cells := _array(value, path)
		var seen: Dictionary = {}
		for i in cells.size():
			var cell_path := "%s[%d]" % [path, i]
			var at: Variant = _board_position(cells[i], board, cell_path)
			if at != null:
				if seen.has(at):
					_error(cell_path, "duplicate %s at %s" % [label, str(at)])
				seen[at] = true
		return seen

	func _check_encounter(encounter: Dictionary, path: String) -> void:
		var board: Dictionary = {}
		if _ref(encounter.get("board"), "boards", path + ".board"):
			board = _defs.boards[encounter.board]
		if encounter.has("deadline"):
			_integer(encounter.deadline, path + ".deadline")
		if encounter.has("seed"):
			var seed_value: Variant = encounter.seed
			if not _is_integer(seed_value, 1) or int(seed_value) > 2147483646:
				_error(path + ".seed", "expected a whole number from 1 to 2147483646")
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
			var maximum: Variant = null
			if placement.has("character") == placement.has("object"):
				_error(place_path, "expected exactly one of character or object")
			elif placement.has("character"):
				if _ref(placement.character, "characters", place_path + ".character"):
					maximum = _effective_profile(_defs.characters[placement.character]).get("max_hp")
			else:
				if _ref(placement.object, "objects", place_path + ".object"):
					maximum = _defs.objects[placement.object].get("max_hp")
			if placement.has("hp"):
				_integer(placement.hp, place_path + ".hp")
				if _is_integer(placement.hp) and _is_integer(maximum, 1) and placement.hp > maximum:
					_error(place_path + ".hp", "cannot exceed maximum health")
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
		if mission.has("default_party"):
			_check_default_party(mission.default_party, encounter, path + ".default_party")
		var objective_path := path + ".objective"
		var objective := _dictionary(mission.get("objective"), objective_path)
		var objective_handler := ""
		if _choice(objective.get("handler"), Objectives.FIELDS.keys(), objective_path + ".handler"):
			objective_handler = objective.handler
			_check_objective_fields(objective, encounter, objective_path)
		for field in ["text", "victory_text", "defeat_text", "victory_event"]:
			_text(objective.get(field), objective_path + "." + field)
		_check_mission_failures(mission.get("failures"), encounter, objective_handler, path + ".failures")

	func _check_objective_fields(objective: Dictionary, encounter: Dictionary, path: String) -> void:
		var board: Dictionary = _defs.boards.get(encounter.get("board"), {})
		var schema: Dictionary = Objectives.FIELDS[objective.handler]
		var subject: Dictionary = {}
		if schema.has("subject"):
			subject = _check_objective_subject(objective.get("subject"), encounter, path + ".subject")
		for field in schema:
			var value: Variant = objective.get(field)
			var field_path := path + "." + str(field)
			match schema[field]:
				"location":
					_check_board_name(value, board, "locations", "location", field_path)
				"zone":
					_check_board_name(value, board, "zones", "zone", field_path)
				"start_zone":
					_check_objective_zone(value, board, subject, field_path)
				"positive_integer":
					_integer(value, field_path, 1)
				"nonnegative_integer":
					_integer(value, field_path)
				"subjects":
					var subjects := _id_list(value, field_path)
					if subjects.is_empty():
						_error(field_path, "requires at least one subject placement ID")
					for i in subjects.size():
						var id: Variant = subjects[i]
						if id is String and not id.strip_edges().is_empty():
							_check_objective_subject(id, encounter, "%s[%d]" % [field_path, i])
				"collapse_schedule":
					_check_collapse_schedule(value, board, field_path)
				"optional_team":
					if objective.has(field):
						_text(value, field_path)
		match objective.handler:
			"pressure_gate":
				_check_pressure_gate_cells(objective, board, path)
			"herd_sheep":
				_check_pen_capacity(objective, board, path + ".pen")
			"survive":
				_check_survival_reserves(objective, encounter, path)

	func _check_pressure_gate_cells(objective: Dictionary, board: Dictionary, path: String) -> void:
		var locations := _record(board, "locations")
		var gate_id: Variant = objective.get("gate")
		var plate_id: Variant = objective.get("plate")
		if gate_id is not String or plate_id is not String:
			return
		var gate: Variant = locations.get(gate_id)
		var plate: Variant = locations.get(plate_id)
		if _is_coordinate(gate) and _is_coordinate(plate) and Objectives.position(gate) == Objectives.position(plate):
			_error(path + ".gate", "gate and plate must occupy different cells")

	func _check_pen_capacity(objective: Dictionary, board: Dictionary, path: String) -> void:
		var pen_id: Variant = objective.get("pen")
		if pen_id is not String:
			return
		var cells: Variant = _record(board, "zones").get(pen_id)
		var subjects: Variant = objective.get("subjects")
		if cells is Array and subjects is Array and cells.size() < subjects.size():
			_error(path, "pen requires at least one cell per sheep")

	func _check_survival_reserves(objective: Dictionary, encounter: Dictionary, path: String) -> void:
		var has_round := objective.has("reserve_round")
		var has_placements := objective.has("reserve_placements")
		if not has_round and not has_placements:
			return
		var round_path := path + ".reserve_round"
		var placements_path := path + ".reserve_placements"
		if not has_round:
			_error(round_path, "required with reserve_placements")
		else:
			var reserve_round: Variant = objective.reserve_round
			var turns: Variant = objective.get("turns")
			_integer(reserve_round, round_path, 2)
			if _is_integer(reserve_round, 2) and _is_integer(turns, 1) and reserve_round > turns:
				_error(round_path, "cannot exceed the survival turn count")
		if not has_placements:
			_error(placements_path, "required with reserve_round")
			return
		var ids := _id_list(objective.reserve_placements, placements_path)
		if ids.is_empty():
			_error(placements_path, "requires at least one enemy placement ID")
		for i in ids.size():
			var id: Variant = ids[i]
			if id is not String or id.strip_edges().is_empty():
				continue
			var id_path := "%s[%d]" % [placements_path, i]
			var placement := _check_objective_subject(id, encounter, id_path)
			var character: Variant = placement.get("character")
			if character is String and _defs.characters.has(character):
				var reserve_profile := _effective_profile(_defs.characters[character])
				if not is_same(reserve_profile.get("team"), "enemies"):
					_error(id_path, "reserve '%s' must be an enemy character placement" % id)

	func _check_collapse_schedule(value: Variant, board: Dictionary, path: String) -> void:
		if _ref("void", "tiles", path) and not _blocked("void"):
			_error(path, "collapse tile 'void' must be impassable")
		var schedule := _array(value, path)
		if schedule.is_empty():
			_error(path, "requires at least one collapse entry")
		var scheduled_cells := {}
		for i in schedule.size():
			var entry_path := "%s[%d]" % [path, i]
			var entry := _dictionary(schedule[i], entry_path)
			_integer(entry.get("round"), entry_path + ".round", 1)
			var zone_id: Variant = entry.get("cells")
			var cells_path := entry_path + ".cells"
			if not _check_board_name(zone_id, board, "zones", "zone", cells_path):
				continue
			var cells: Variant = board.zones[zone_id]
			if cells is not Array:
				continue
			for cell in cells:
				if not _is_coordinate(cell):
					continue
				var at := Objectives.position(cell)
				if scheduled_cells.has(at):
					_error(cells_path, "cell %s is already scheduled in %s" % [at, scheduled_cells[at]])
				else:
					scheduled_cells[at] = cells_path

	func _check_default_party(value: Variant, encounter: Dictionary, path: String) -> void:
		var party := _id_list(value, path, "characters")
		var slots: Variant = encounter.get("party_slots", [])
		if not encounter.is_empty() and slots is Array and party.size() != slots.size():
			_error(path, "expected %d characters for this encounter" % slots.size())
		for id in party:
			if id is not String or not _defs.characters.has(id):
				continue
			var profile := _effective_profile(_defs.characters[id])
			var capabilities: Variant = profile.get("capabilities")
			if not is_same(profile.get("team"), "heroes") or not capabilities is Array or "commandable" not in capabilities:
				_error(path, "character '%s' is not a commandable hero" % id)
			if encounter.get("placements") is Array and encounter.placements.any(func(placement: Variant) -> bool:
					return placement is Dictionary and is_same(placement.get("id"), id)):
				_error(path, "character '%s' collides with a placement" % id)

	func _check_objective_subject(id: Variant, encounter: Dictionary, path: String) -> Dictionary:
		if not _text(id, path) or encounter.is_empty():
			return {}
		var placements: Variant = encounter.get("placements")
		if placements is Array:
			for placement in placements:
				if placement is Dictionary and is_same(placement.get("id"), id) and placement.has("character"):
					return placement
		_error(path, "no character placement has ID '%s'" % id)
		return {}

	func _check_board_name(id: Variant, board: Dictionary, field: String, kind: String, path: String) -> bool:
		if not _text(id, path) or board.is_empty():
			return false
		var entries: Variant = board.get(field, {})
		if not entries is Dictionary or not entries.has(id):
			_error(path, "unknown board %s '%s'" % [kind, id])
			return false
		return true

	func _check_objective_zone(id: Variant, board: Dictionary, subject: Dictionary, path: String) -> void:
		if not _check_board_name(id, board, "zones", "zone", path):
			return
		var cells: Variant = board.zones[id]
		if cells is Array and _is_coordinate(subject.get("at")):
			var start := Objectives.position(subject.at)
			if not cells.any(func(cell: Variant) -> bool: return _is_coordinate(cell) and Objectives.position(cell) == start):
				_error(path, "subject must start inside zone '%s'" % id)

	func _check_mission_failures(value: Variant, encounter: Dictionary, objective_handler: String, path: String) -> void:
		var failures := _array(value, path)
		var seen: Dictionary = {}
		for i in failures.size():
			var failure_path := "%s[%d]" % [path, i]
			var failure := _dictionary(failures[i], failure_path)
			var handler: Variant = failure.get("handler")
			if _choice(handler, ["subject_dead", "deadline", "party_wiped"], failure_path + ".handler"):
				if seen.has(handler):
					_error(failure_path + ".handler", "duplicate failure '%s'" % handler)
				seen[handler] = true
				if handler == "deadline" and not _is_integer(encounter.get("deadline"), 1):
					_error(failure_path, "deadline failure requires a positive encounter deadline")
				if handler == "subject_dead" and objective_handler not in ["escort", "leave_zone", "wagon"]:
					_error(failure_path, "subject_dead requires an escort, leave_zone, or wagon objective")
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
				var hero := _effective_profile(_defs.characters[id])
				var capabilities: Variant = hero.get("capabilities")
				if not is_same(hero.get("team"), "heroes") or not capabilities is Array or "commandable" not in capabilities:
					_error(path + ".roster", "character '%s' is not a commandable hero" % id)
		for index in missions.size():
			var id: Variant = missions[index]
			if not id is String or not _defs.missions.has(id):
				continue
			_check_deployment(id, int(party_size), roster, "%s.missions[%d]" % [path, index])

	func _check_deployment(id: String, party_size: int, roster: Array, path: String) -> void:
		var mission: Dictionary = _defs.missions[id]
		var failures: Variant = mission.get("failures")
		if failures is Array and not failures.any(func(failure: Variant) -> bool:
				return failure is Dictionary and is_same(failure.get("handler"), "party_wiped")):
			_error(path, "missions.%s.failures requires a party_wiped failure" % id)
		var encounter_id: Variant = mission.get("encounter")
		var encounter: Dictionary = _defs.encounters.get(encounter_id, {})
		if encounter.is_empty():
			return
		var slots: Variant = encounter.get("party_slots", [])
		if not slots is Array or slots.size() != party_size:
			_error(path, "encounters.%s.party_slots must have exactly %d party slots for mission '%s'" % [
				encounter_id, party_size, id])
		var placements: Variant = encounter.get("placements")
		if placements is Array:
			for index in placements.size():
				var placement: Variant = placements[index]
				if placement is Dictionary and placement.get("id") in roster:
					_error(path, "encounters.%s.placements[%d].id '%s' collides with roster ID" % [
						encounter_id, index, placement.id])

	func _check_commissions() -> void:
		var start_errors := _errors.size()
		var settings := _dictionary(_defs.get("commission_settings"), "commission_settings")
		var kinds := _dictionary(_defs.get("mission_kinds"), "mission_kinds")
		var reports := _dictionary(_defs.get("mission_reports"), "mission_reports")
		if _errors.size() != start_errors:
			return

		var adventure := _check_commission_settings(settings)
		for id in kinds:
			var path := "mission_kinds." + str(id)
			_text(id, path)
			if kinds[id] is not Dictionary:
				_error(path, "expected a dictionary")
				continue
			var kind: Dictionary = kinds[id]
			_check_commission_fields(kind, ["label", "descriptors"], path)
			_text(kind.get("label"), path + ".label")
			_check_descriptors(kind.get("descriptors"), path + ".descriptors")

		var transit_kinds: Dictionary = {}
		var destination_count := 0
		for id in reports:
			var path := "mission_reports." + str(id)
			var known_mission := _ref(id, "missions", path)
			if reports[id] is not Dictionary:
				_error(path, "expected a dictionary")
				continue
			var report: Dictionary = reports[id]
			_check_commission_fields(report, ["kind", "descriptors", "destination_descriptors"], path)
			var kind: Variant = report.get("kind")
			if _text(kind, path + ".kind") and not kinds.has(kind):
				_error(path + ".kind", "unknown mission_kinds ID '%s'" % kind)
			_check_descriptors(report.get("descriptors"), path + ".descriptors")
			if report.has("destination_descriptors"):
				_check_descriptors(report.destination_descriptors, path + ".destination_descriptors")
				destination_count += 1
			elif kind is String:
				transit_kinds[kind] = true
			if known_mission and _is_integer(adventure.get("party_size"), 1) and adventure.get("roster") is Array:
				_check_deployment(id, int(adventure.party_size), adventure.roster, path)

		if _errors.size() != start_errors:
			return
		if destination_count < 3:
			_error("mission_reports", "requires at least three distinct destinations for the commission board")
		# Repeat visits are allowed whenever the unplayed pool cannot supply a fork.
		if transit_kinds.size() < 2:
			_error("mission_reports", "requires transit missions from at least two different kinds")

	func _check_commission_settings(settings: Dictionary) -> Dictionary:
		_check_commission_fields(settings, ["roster_adventure"], "commission_settings")
		var path := "commission_settings.roster_adventure"
		var id: Variant = settings.get("roster_adventure")
		if not _text(id, path):
			return {}
		var adventures := _record(_defs, "adventures")
		if not adventures.has(id):
			_error(path, "unknown adventures ID '%s'" % id)
			return {}
		return _record(adventures, id)

	func _check_commission_fields(record: Dictionary, fields: Array, path: String) -> void:
		for field in record:
			if field not in fields:
				_error(path + "." + str(field), "unknown commission field")

	func _check_descriptors(value: Variant, path: String) -> void:
		if value is not Array or value.is_empty():
			_error(path, "expected a nonempty array of descriptors")
			return
		for index in value.size():
			_text(value[index], "%s[%d]" % [path, index])

	func _check_reward_weights(weights: Dictionary) -> void:
		var total := 0
		for tier in Rewards.DEFAULT_WEIGHTS:
			var weight: Variant = weights.get(tier)
			var path := "reward_weights." + str(tier)
			_integer(weight, path, 1)
			if _is_integer(weight, 1):
				total += int(weight)
		for tier in weights:
			if not Rewards.DEFAULT_WEIGHTS.has(tier):
				_error("reward_weights." + str(tier), "unknown rarity")
		if total > 2147483647:
			_error("reward_weights", "sum of rarity weights cannot exceed 2147483647")

	func _check_reward(upgrade: Dictionary, path: String) -> void:
		for field in upgrade:
			if field not in REWARD_FIELDS:
				_error(path + "." + str(field), "unknown upgrade field")
		var id: Variant = upgrade.get("hero_id")
		var profile: Dictionary = {}
		if _ref(id, "characters", path + ".hero_id"):
			profile = _effective_profile(_defs.characters[id])
			var capabilities: Variant = profile.get("capabilities")
			if not is_same(profile.get("team"), "heroes") or not capabilities is Array \
					or "commandable" not in capabilities or "minion" in capabilities:
				_error(path + ".hero_id", "character must be a commandable hero, not a minion")
		_choice(upgrade.get("rarity"), Rewards.DEFAULT_WEIGHTS.keys(), path + ".rarity")
		_integer(upgrade.get("cap"), path + ".cap", 1)
		_integer(upgrade.get("amount"), path + ".amount", 1)
		_text(upgrade.get("label"), path + ".label")
		_text(upgrade.get("description"), path + ".description")
		for field in ["requires_abilities", "requires_any_ability"]:
			if upgrade.has(field) and _id_list(upgrade[field], path + "." + field, "abilities").is_empty():
				_error(path + "." + field, "requires a nonempty ability list")
		var effect: Variant = upgrade.get("effect")
		if _choice(effect, REWARD_EFFECTS, path + ".effect"):
			_check_reward_grants(upgrade, profile, path, effect)
			if not profile.is_empty():
				_check_reward_kit(effect, str(id), profile, path + ".effect")

	func _check_reward_grants(upgrade: Dictionary, profile: Dictionary, path: String, effect: String) -> void:
		var grant: Dictionary = REWARD_GRANTS.get(effect, {})
		var ability: Variant = upgrade.get("ability")
		if not grant.is_empty():
			if _ref(ability, "abilities", path + ".ability"):
				var spec: Dictionary = _defs.abilities[ability]
				var targeting: Variant = spec.get("targeting")
				if ability != grant.ability or not is_same(spec.get("handler"), grant.handler) \
						or not targeting is Dictionary or not is_same(targeting.get("kind"), grant.kind):
					_error(path + ".ability", "expected '%s' with %s targeting and the %s handler" % [
						grant.ability, grant.kind, grant.handler])
				if effect == "shield_throw":
					if not targeting is Dictionary or not _is_integer(targeting.get("range"), 1):
						_error(path + ".ability", "Shield Throw requires a finite positive targeting range")
				var params: Variant = spec.get("params")
				if effect == "house_lights" and (not params is Dictionary
						or not is_same(params.get("damage_ability"), "healing_sonnet")):
					_error(path + ".ability", "House Lights must use healing_sonnet as its damage_ability")
				var abilities: Variant = profile.get("abilities")
				if abilities is Array and ability in abilities:
					_error(path + ".ability", "ability is already in the hero's base kit")
		elif upgrade.has("ability"):
			_error(path + ".ability", "effect does not grant an ability")

		if effect != "house_lights":
			for field in ["order", "behavior"]:
				if upgrade.has(field):
					_error(path + "." + field, "effect does not grant a standing order")
			return

		var order: Variant = upgrade.get("order")
		if _ref(order, "orders", path + ".order"):
			var habits: Variant = profile.get("habits")
			if habits is Dictionary and habits.has(order):
				_error(path + ".order", "order is already in the hero's base habits")
		var behavior: Variant = upgrade.get("behavior")
		if _ref(behavior, "behaviors", path + ".behavior"):
			var spec: Dictionary = _defs.behaviors[behavior]
			var params: Variant = spec.get("params")
			if not is_same(spec.get("handler"), "use_ability") or not params is Dictionary \
					or not is_same(params.get("ability"), grant.ability):
				_error(path + ".behavior", "expected use_ability with '%s'" % grant.ability)

	func _check_reward_kit(effect: String, hero_id: String, hero: Dictionary, path: String) -> void:
		var damage_handlers := ["bonk", "blast", "attack"]
		match effect:
			"dig_in", "wide_guard":
				_require_reward(_kit_has_status(hero, "apply_status", "reflect"), path,
					"the hero to be able to apply a reflecting guard")
				if effect == "dig_in":
					_require_reward(_has_capability(hero, "pullable"), path, "a pullable hero for Dig In")
			"shield_damage":
				_require_reward(_kit_has_status(hero, "apply_status", "reflect") \
					or not _kit_ability(hero, "knight_shield_throw", ["attack"]).is_empty() \
					or _has_shield_throw_reward(hero_id), path, "reflecting guard or access to knight_shield_throw")
			"shield_throw":
				_require_reward(_has_capability(hero, "mobile") and _kit_has_handler(hero, "move"), path,
					"a mobile hero with a Move ability to retrieve the shield")
			"bonk_damage", "long_staff", "strong_swing":
				var bonk := _kit_ability(hero, "healer_bonk", damage_handlers)
				_require_reward(not bonk.is_empty(), path, "healer_bonk in the hero's ability kit")
				if effect == "long_staff" and not bonk.is_empty():
					_require_reward(_has_finite_range(bonk), path, "healer_bonk to have a finite positive range")
			"heal_amount", "me_or_you":
				var heal := _kit_ability(hero, "healer_heal", ["heal"])
				_require_reward(not heal.is_empty(), path, "healer_heal in the hero's ability kit")
				if effect == "me_or_you" and not heal.is_empty():
					_require_reward(is_same(_record(heal, "targeting").get("kind"), "automatic") \
						and is_same(_record(heal, "params").get("prefer_wounded_self"), true) \
						and _has_capability(hero, "healable"), path, "healer_heal to support wounded self-healing")
			"blast_damage", "demolition_practice", "duck", "parting_gift", "conductive_personality":
				var blast := _kit_ability(hero, "wizard_blast", damage_handlers)
				_require_reward(not blast.is_empty(), path, "wizard_blast in the hero's ability kit")
				if not blast.is_empty() and effect == "demolition_practice":
					_require_reward(is_same(_record(blast, "targeting").get("objects"), true), path,
						"wizard_blast to target obstacles")
				if not blast.is_empty() and effect == "duck":
					_require_reward(_knocks_down(blast), path, "wizard_blast to knock down its target")
			"padded_landing", "braced_casting":
				var pull := _kit_ability(hero, "wizard_pull", ["pull"])
				_require_reward(_has_capability(hero, "mobile") and not pull.is_empty(), path,
					"a mobile hero with wizard_pull")
				if effect == "braced_casting" and not pull.is_empty():
					_require_reward(_knocks_down(pull), path, "wizard_pull to knock down the caster in recoil")
			"cheap_shot", "long_finger":
				_require_reward(_kit_has_handler(hero, "misdirect"), path, "a misdirect ability in the hero's kit")
			"exit_strategy":
				_require_reward(_has_capability(hero, "mobile") and not _kit_behavior(hero, "retreat").is_empty(),
					path, "a mobile hero with a retreat behavior")
			"borrowed_courage", "pass_the_buck", "pocket_sand", "body_double":
				_require_reward(_kit_has_handler(hero, "swap_furthest"), path, "a swap_furthest ability in the hero's kit")
				if effect == "pocket_sand":
					_require_reward(is_same(_defs.statuses.get("held_in_place", {}).get("handler"), "stop_move"),
						path, "statuses.held_in_place with the stop_move handler")
				if effect == "pass_the_buck":
					_require_reward(_defs.abilities.values().any(func(ability: Dictionary) -> bool:
						return is_same(ability.get("handler"), "misdirect")), path, "an authored ability able to mark an opponent")
			"sonnet_damage", "front_row_seats", "heckler":
				var sonnet := _kit_ability(hero, "healing_sonnet", ["perform"])
				var params := _record(sonnet, "params")
				_require_reward(not sonnet.is_empty() and not params.has("status") \
					and (_is_integer(params.get("damage"), 1) or params.has("damage_ability")), path,
					"healing_sonnet as a damage performance in the hero's ability kit")
			"buskers_hat":
				_require_reward(not _kit_ability(hero, "inspiring_melody", ["perform"]).is_empty(), path,
					"inspiring_melody in the hero's ability kit")
			"laughing_fit":
				_require_reward(_kit_has_status(hero, "", "skip_action", "laugh_skip"), path,
					"an ability that makes opponents skip a turn with the laugh_skip event")
			"spare_ribs", "good_soil", "broad_wave", "heavy_bouquet", "long_stemmed", "warm_welcome", \
			"say_hello_to_that_one", "wake_reception":
				_check_summon_reward(effect, hero, path)
			"stronger_dose", "long_ladle", "spare_vial", "keep_the_culture", "concentrate", "brittle_glass":
				if effect not in ["concentrate", "brittle_glass"]:
					_require_reward(not _kit_ability(hero, "alchemist_potion", ["healing_potion"]).is_empty(),
						path, "alchemist_potion in the hero's ability kit")
				if effect in ["concentrate", "brittle_glass", "keep_the_culture"]:
					_require_reward(not _kit_ability(hero, "alchemist_acid", ["acid"]).is_empty(),
						path, "alchemist_acid in the hero's ability kit")

	func _check_summon_reward(effect: String, hero: Dictionary, path: String) -> void:
		var skeletons := _kit_summons(hero, "cell", "skeleton")
		var zombies := _kit_summons(hero, "entity", "zombie")
		var skeleton := _reward_profile("skeleton")
		var zombie := _reward_profile("zombie")
		match effect:
			"spare_ribs", "broad_wave":
				_require_reward(not skeletons.is_empty(), path, "a cell summon for the skeleton in the hero's kit")
				if effect == "broad_wave":
					_require_reward(_kit_has_handler(skeleton, "sweep"), path, "a sweep ability in the skeleton's kit")
			"good_soil":
				_require_reward(not _kit_summons(hero, "entity").is_empty(), path, "a corpse-raising ability in the hero's kit")
			"heavy_bouquet", "long_stemmed", "warm_welcome":
				_require_reward(not zombies.is_empty(), path, "a corpse summon for the zombie in the hero's kit")
				if effect == "warm_welcome":
					_require_reward(_kit_has_handler(zombie, "repel"), path, "a repel ability in the zombie's kit")
				else:
					var flower := _kit_ability(zombie, "offer_flower", ["attack", "bonk", "blast"])
					_require_reward(not flower.is_empty(), path, "offer_flower in the zombie's ability kit")
					if effect == "long_stemmed" and not flower.is_empty():
						_require_reward(_has_finite_range(flower), path, "offer_flower to have a finite positive range")
						var greet := _kit_behavior(zombie, "greet")
						var greetings: Variant = _record(greet, "params").get("greetings")
						_require_reward(greetings is Array and "offer_flower" in greetings, path,
							"the zombie to use offer_flower in its greeting behavior")
			"say_hello_to_that_one":
				_require_reward(_has_greeting_summon(hero), path, "a summon with a greet behavior to pursue the nominee")
			"wake_reception":
				_require_reward(not zombies.is_empty(), path, "a corpse summon for the zombie in the hero's kit")
				_require_reward("summon_skeleton" in skeletons, path,
					"summon_skeleton in the hero's kit as a cell summon for the skeleton")

	func _require_reward(valid: bool, path: String, requirement: String) -> void:
		if not valid:
			_error(path, "requires " + requirement)

	func _record(parent: Dictionary, field: String) -> Dictionary:
		var value: Variant = parent.get(field)
		return value if value is Dictionary else {}

	func _reward_profile(id: String) -> Dictionary:
		return _character_profile(id)

	func _character_profile(id: String) -> Dictionary:
		var character := _record(_record(_defs, "characters"), id)
		return _effective_profile(character) if not character.is_empty() else {}

	func _has_capability(profile: Dictionary, id: String) -> bool:
		var kit: Variant = profile.get("capabilities")
		return kit is Array and id in kit

	func _kit_ability(profile: Dictionary, id: String, handlers: Array) -> Dictionary:
		var kit: Variant = profile.get("abilities")
		var ability: Dictionary = _defs.abilities.get(id, {})
		return ability if kit is Array and id in kit and ability.get("handler") in handlers else {}

	func _kit_has_handler(profile: Dictionary, handler: String) -> bool:
		var kit: Variant = profile.get("abilities")
		return kit is Array and kit.any(func(id: Variant) -> bool:
			return is_same(_defs.abilities.get(id, {}).get("handler"), handler))

	func _kit_has_status(profile: Dictionary, ability_handler: String, status_handler: String,
			skip_event := "") -> bool:
		var kit: Variant = profile.get("abilities")
		if not kit is Array:
			return false
		for id in kit:
			var ability: Dictionary = _defs.abilities.get(id, {})
			if not ability_handler.is_empty() and not is_same(ability.get("handler"), ability_handler):
				continue
			var status := _ability_status(ability)
			if is_same(status.get("handler"), status_handler) and (skip_event.is_empty() \
					or is_same(_record(status, "params").get("skip_event"), skip_event)):
				return true
		return false

	func _ability_status(ability: Dictionary) -> Dictionary:
		return _defs.statuses.get(_record(ability, "params").get("status"), {})

	func _knocks_down(ability: Dictionary) -> bool:
		var status := _ability_status(ability)
		return is_same(status.get("handler"), "skip_action") \
			and is_same(_record(status, "params").get("skip_event", "recover"), "recover")

	func _has_finite_range(ability: Dictionary) -> bool:
		return _is_integer(_record(ability, "targeting").get("range"), 1)

	func _kit_behavior(profile: Dictionary, handler: String) -> Dictionary:
		var ids := _record(profile, "habits").values()
		ids.append(profile.get("behavior"))
		for id in ids:
			var behavior: Dictionary = _defs.behaviors.get(id, {})
			if is_same(behavior.get("handler"), handler):
				return behavior
		return {}

	func _has_shield_throw_reward(hero_id: String) -> bool:
		for value in _defs.upgrades.values():
			if value is Dictionary and is_same(value.get("hero_id"), hero_id) \
					and is_same(value.get("effect"), "shield_throw"):
				return true
		return false

	func _kit_summons(profile: Dictionary, kind := "", character := "") -> Array:
		var result: Array = []
		var kit: Variant = profile.get("abilities")
		if kit is Array:
			for id in kit:
				var ability: Dictionary = _defs.abilities.get(id, {})
				if is_same(ability.get("handler"), "summon") \
						and (kind.is_empty() or is_same(_record(ability, "targeting").get("kind"), kind)) \
						and (character.is_empty() or is_same(_record(ability, "params").get("character"), character)):
					result.append(id)
		return result

	func _has_greeting_summon(profile: Dictionary) -> bool:
		for id in _kit_summons(profile):
			var character: Variant = _record(_defs.abilities[id], "params").get("character")
			if character is String and not _kit_behavior(_reward_profile(character), "greet").is_empty():
				return true
		return false

	func _terrain_index(board: Dictionary) -> Dictionary:
		var result: Dictionary = {}
		var tiles: Variant = board.get("tiles")
		if tiles is Array:
			for tile in tiles:
				if tile is Dictionary and _is_coordinate(tile.get("at")):
					result[Objectives.position(tile.at)] = tile.get("type")
		return result

	func _blocked(tile_id: Variant) -> bool:
		return tile_id is String and is_same(_defs.tiles.get(tile_id, {}).get("passable"), false)

	func _board_position(value: Variant, board: Dictionary, path: String) -> Variant:
		if not _is_coordinate(value):
			_error(path, "expected [x, y] with nonnegative integers")
			return null
		var at := Objectives.position(value)
		if _is_integer(board.get("width"), 1) and _is_integer(board.get("height"), 1):
			if at.x >= int(board.width) or at.y >= int(board.height):
				_error(path, "coordinate %s lies outside the board" % str(at))
				return null
		return at

	static func _is_coordinate(value: Variant) -> bool:
		return value is Array and value.size() == 2 and _is_integer(value[0]) and _is_integer(value[1])

	static func position(value: Array) -> Vector2i:
		return Objectives.position(value)

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
