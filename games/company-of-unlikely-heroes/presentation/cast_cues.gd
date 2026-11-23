extends RefCounted
## Turns the successful action groups of one committed round into board cues.
## The caller owns the commit boundary; inspecting a forecast never plays it.

const Catalog = preload("res://content/catalog.gd")
const Statuses = preload("res://rules/statuses.gd")
# [expected rules handler, clip]. Catalog authors can redefine an ability ID.
const CLIPS := {
	"knight": {"knight_aura": ["apply_status", "guard"], "knight_shield_throw": ["attack", "shield_away"]},
	"healer": {"healer_heal": ["heal", "ally_heal"], "healer_field_dressing": ["heal", "ally_heal"],
		"healer_bonk": ["bonk", "bonk"]},
	"wizard": {"wizard_blast": ["blast", "blast"], "wizard_pull": ["pull", "pull"]},
	"rogue": {"move": ["move", "retreat"], "rogue_confusing_dodge": ["swap_furthest", "swap"],
		"rogue_wasnt_me": ["misdirect", "misdirect"]},
	"bard": {"inspiring_melody": ["perform", "inspiring_melody"], "healing_sonnet": ["perform", "healing_sonnet"],
		"bard_take_the_stage": ["perform", "healing_sonnet"]},
	"necromancer": {"summon_skeleton": ["summon", "summon_skeleton"], "raise_dead": ["summon", "raise_dead"]},
	"skeleton": {"wave": ["sweep", "wave"], "dont_go": ["stop_target", "dont_go"]},
	"zombie": {"say_hello": ["repel", "say_hello"], "offer_flower": ["attack", "offer_flower"]},
	"alchemist": {"alchemist_potion": ["healing_potion", "potion"],
		"alchemist_acid": ["acid", "acid"], "alchemist_plain_tonic": ["plain_tonic", "potion"],
		"alchemist_repeat_batch": ["repeat_batch", "potion"]},
	"harpooner": {"move": ["move", "pursue"], "enemy_attack": ["attack", "close_thrust"],
		"enemy_harpoon": ["attack", "ranged_cast"]},
	"ferryman": {"move": ["move", "travel"]},
}
const STRIKES := ["bonk", "blast", "shield_away", "offer_flower", "healing_sonnet", "wave"]


static func cast_key_for(state: Dictionary, unit: Dictionary, profile := {}) -> String:
	var definitions: Dictionary = state.catalog.defs
	var character_id: String = unit.get("character_id", "")
	var character: Dictionary = definitions.characters.get(character_id, {})
	var key: Variant = character.get("cast_key")
	if not key is String or not CLIPS.has(key):
		return ""
	if profile.is_empty():
		profile = Catalog.profile(definitions, character_id)
	# Metadata is per character, not inherited. A newly authored art key or
	# variant takes precedence even if a custom bundle copies the stock record.
	if profile.get("team") != character.get("cast_team", "heroes") \
			or character.get("cast_art_key") != profile.get("art_key") \
			or profile.get("art_variant", "") != character.get("cast_variant", ""):
		return ""
	return key


static func build(before: Dictionary, after: Dictionary, events: Array) -> Array:
	if events.is_empty():
		return []
	var positions := {}
	var actors := {}
	for unit in after.units:
		actors[unit.id] = unit
	for entity in before.units + before.obstacles:
		positions[entity.id] = entity.position
	var health := {}
	var prone := {}
	for unit in before.units:
		health[unit.id] = int(unit.hp)
		prone[unit.id] = int(unit.hp) <= 0 or Statuses.knocked_down(before, unit)
	var cues := []
	var index := 0
	while index < events.size():
		var action: Dictionary = events[index].get("resolved_action", {})
		var actor: Dictionary = actors.get(action.get("unit_id", ""), {})
		var cue := _start_cue(after, actor, action)
		var end := index + int(action.get("event_count", 1))
		if end <= index or end > events.size():
			push_error("Invalid resolved action span at event %d." % index)
			return []
		var echo_started := false
		var reactions := []
		var travelled := false
		while index < end:
			var event: Dictionary = events[index]
			if event.get("type") == "move" and event.get("unit_id") == action.get("unit_id") \
					and event.get("position") is Vector2i \
					and event.get("position") != positions.get(action.get("unit_id")):
				travelled = true
			if not echo_started and event.get("song_echo", false):
				# Weaving is one rules action, but the two songs have distinct poses and recipients.
				if not cue.is_empty():
					cues.append(cue)
				var echo_action := action.duplicate()
				echo_action["ability_id"] = event.ability_id
				cue = _start_cue(after, actor, echo_action)
				echo_started = true
			if not cue.is_empty():
				_observe(cue, event, positions)
			if event.get("type") == "damage":
				var victim: String = event.get("target_id", "")
				if health.has(victim):
					var amount := int(event.get("amount", 0))
					health[victim] = maxi(0, int(health[victim]) - amount)
					var target: Dictionary = actors.get(victim, {})
					var key := cast_key_for(after, target)
					var knocked := key == "ferryman" and Statuses.is_knockdown(after, event.get("status_id", ""))
					if key in ["harpooner", "ferryman"] and (amount > 0 or knocked) \
							and (key != "ferryman" or not prone.get(victim, false)):
						var down: bool = health[victim] <= 0 or (key == "ferryman" \
							and knocked)
						reactions.append({"unit_id": victim, "cast_key": key,
							"clip": ("defeat" if down else "hit") if key == "harpooner" else ("down" if down else "flinch"),
							"source_cell": positions.get(victim), "actor_cell": positions.get(victim),
							"target_id": "", "recipients": []})
					if key == "ferryman" and (knocked or health[victim] <= 0):
						prone[victim] = true
			elif event.get("type") == "heal":
				var healed: String = event.get("target_id", "")
				if health.has(healed):
					health[healed] += int(event.get("amount", 0))
			elif (event.get("type") == "status" and Statuses.is_knockdown(after, event.get("status_id", ""))) \
					or (event.get("type") == "alchemy_reaction" and event.get("reaction_id") == "jelly_knees" \
					and event.get("applied", false)):
				var victim: String = event.get("target_id", "")
				var target: Dictionary = actors.get(victim, {})
				if cast_key_for(after, target) == "ferryman":
					if not prone.get(victim, false):
						reactions.append({"unit_id": victim, "cast_key": "ferryman", "clip": "down",
							"source_cell": positions.get(victim), "actor_cell": positions.get(victim),
							"target_id": "", "recipients": []})
					prone[victim] = true
			elif event.get("type") == "recover":
				var recovered: String = event.get("unit_id", "")
				var target: Dictionary = actors.get(recovered, {})
				var knocked: bool = event.get("reaction_id") == "jelly_knees"
				for status_id in event.get("status_ids", []):
					knocked = knocked or Statuses.is_knockdown(after, status_id)
				if knocked and cast_key_for(after, target) == "ferryman" and prone.get(recovered, false):
					reactions.append({"unit_id": recovered, "cast_key": "ferryman", "clip": "recover",
						"source_cell": positions.get(recovered), "actor_cell": positions.get(recovered),
						"target_id": "", "recipients": []})
					prone[recovered] = false
			elif event.get("type") == "victory" and after.get("outcome") == "victory":
				var objective: Dictionary = after.get("objective", {})
				var subject: String = event.get("target_id", "")
				var target: Dictionary = actors.get(subject, {})
				if objective.get("handler") == "escort" and objective.get("subject") == subject \
						and event.get("position") == objective.get("destination") \
						and target.get("position") == objective.get("destination") \
						and cast_key_for(after, target) == "ferryman":
					reactions.append({"unit_id": subject, "cast_key": "ferryman", "clip": "safe_bank",
						"source_cell": target.position, "actor_cell": target.position,
						"target_id": "", "recipients": []})
			_trace_position(event, positions)
			index += 1
		if not cue.is_empty() and cue.clip == "travel" and not travelled:
			cue.clear()
		if not cue.is_empty() and cue.cast_key == "harpooner" and cue.clip == "ranged_cast" \
				and cue.get("target_cell") is Vector2i:
			var offset: Vector2i = cue.target_cell - cue.source_cell
			if absi(offset.x) + absi(offset.y) <= 1:
				cue.clip = "close_thrust"
		var parent_index := -1
		if not cue.is_empty():
			parent_index = cues.size()
			cues.append(cue)
		for reaction in reactions:
			if parent_index >= 0:
				reaction["after_cue"] = parent_index
			cues.append(reaction)
	return cues


static func _start_cue(state: Dictionary, actor: Dictionary, action: Dictionary) -> Dictionary:
	if actor.is_empty():
		return {}
	var key := cast_key_for(state, actor)
	var binding: Array = CLIPS.get(key, {}).get(action.ability_id, [])
	if binding.is_empty():
		return {}
	var definitions: Dictionary = state.catalog.defs
	var ability: Dictionary = definitions.abilities.get(action.ability_id, {})
	var clip: String = binding[1]
	if ability.get("handler", "") != binding[0] or not _supports_shape(definitions, ability, clip):
		return {}
	if ability.get("handler") == "repeat_batch":
		var recipe: Dictionary = definitions.abilities.get(action.get("recipe_id", ""), {})
		if recipe.get("handler") == "acid":
			clip = "acid"
		elif recipe.get("handler") != "healing_potion":
			return {}
	var cue := {"unit_id": actor.id, "cast_key": key, "clip": clip, "target_id": "",
		"source_cell": action.source_cell, "actor_cell": action.actor_cell, "recipients": []}
	if clip == "retreat":
		cue["target_cell"] = action.actor_cell
	elif clip in ["pursue", "travel"]:
		cue["target_cell"] = action.actor_cell
	return cue


static func _supports_shape(definitions: Dictionary, ability: Dictionary, clip: String) -> bool:
	var params: Dictionary = ability.params
	var status: Dictionary = definitions.statuses.get(params.get("status", ""), {})
	match clip:
		"guard":
			return status.get("handler") == "reflect"
		"inspiring_melody":
			return status.get("handler") == "skip_action"
		"healing_sonnet":
			return not params.has("status")
		"summon_skeleton":
			return ability.targeting.kind == "cell" and params.get("character") == "skeleton"
		"raise_dead":
			return ability.targeting.kind == "entity" and params.get("character") == "zombie"
		_:
			return true


static func _observe(cue: Dictionary, event: Dictionary, positions: Dictionary) -> void:
	var id: String = event.get("target_id", "")
	var cell: Variant = positions.get(id)
	var actor: String = cue.unit_id
	var clip: String = cue.clip
	var own_action: bool = event.get("unit_id") == actor
	match event.type:
		"heal":
			if own_action and clip == "ally_heal":
				_observe_heal(cue, event, cell)
			elif own_action and clip == "potion":
				_aim(cue, id, cell)
				if event.amount > 0:
					_recipient(cue, id, cell, "heal")
			elif own_action and clip == "inspiring_melody" and event.amount > 0:
				_recipient(cue, id, cell, "heal")
		"performance":
			if own_action and clip == "inspiring_melody":
				_aim(cue, id, cell)
		"aura":
			if own_action and clip == "guard":
				_recipient(cue, actor, cue.source_cell, "guard")
		"reflect":
			if clip in ["close_thrust", "ranged_cast"]:
				var ward: String = event.get("ward_id", "")
				if not cue.has("target_cell"):
					_aim(cue, ward, positions.get(ward))
				_recipient(cue, ward, positions.get(ward), "guard")
			if clip in STRIKES and not cue.has("target_cell"):
				# A fully absorbed strike still took place. Use the ward as
				# the aiming point; only an actual damage event overrides it.
				var ward: String = event.get("ward_id", "")
				_aim(cue, ward, positions.get(ward))
		"body_double":
			if clip in ["close_thrust", "ranged_cast"]:
				var original: String = event.get("unit_id", "")
				_aim(cue, original, positions.get(original))
		"damage":
			if clip in ["close_thrust", "ranged_cast"] \
					and event.get("source_id") == actor:
				if not cue.has("target_cell"):
					_aim(cue, id, cell)
				_recipient(cue, id, cell, "hit")
			elif clip in STRIKES and event.get("source_id") == actor:
				if clip != "wave" and not _has_recipient(cue, "hit"):
					_aim(cue, id, cell)
				_recipient(cue, id, cell, "hit")
			elif clip == "acid" and event.get("source_id") == actor:
				if not cue.has("target_cell"):
					_aim(cue, id, cell)
				_recipient(cue, id, cell, "hit")
		"alchemy_reaction":
			if own_action and clip in ["potion", "acid"]:
				_aim(cue, id, event.get("position", cell))
		"shield_drop":
			if own_action and clip == "shield_away":
				cue["target_cell"] = event.position
		"pull":
			if clip == "pull":
				# Dig In reverses the geometry and names the defender as
				# the event's unit, not as the initiator of the cast.
				if own_action:
					_aim(cue, id, cell)
				else:
					var defender: String = event.unit_id
					_aim(cue, defender, positions.get(defender))
				_recipient(cue, id, event.position, "shift")
		"repel", "push":
			if own_action and clip == "say_hello":
				_aim(cue, id, cell)
				_recipient(cue, id, event.position, "shift")
			elif own_action and clip == "blast":
				_recipient(cue, id, event.position, "shift")
		"swap":
			if own_action and clip == "swap":
				_aim(cue, id, cell)
				_recipient(cue, id, event.target_position, "shift")
		"misdirect":
			if own_action and clip == "misdirect" and event.has("victim_id"):
				_aim(cue, id, cell)
				_recipient(cue, id, cell, "status")
		"status":
			if own_action and clip == "dont_go":
				_aim(cue, id, cell)
				_recipient(cue, id, cell, "status")
		"summon":
			if own_action and clip in ["summon_skeleton", "raise_dead"]:
				_aim(cue, id, event.position)
				_recipient(cue, event.summon_id, event.position, "summon")


static func _observe_heal(cue: Dictionary, event: Dictionary, cell: Variant) -> void:
	var id: String = event.get("target_id", "")
	if id == cue.unit_id:
		cue.clip = "self_heal"
	# Prefer an ally who actually restored HP over an earlier full-health
	# allocation. A successful wasted cast still plays its animation.
	if not cue.has("target_cell") or (event.amount > 0 and not _has_recipient(cue, "heal")):
		_aim(cue, id, cell)
	if event.amount > 0:
		_recipient(cue, id, cell, "heal")


static func _aim(cue: Dictionary, id: String, cell: Variant) -> void:
	if cell is Vector2i:
		cue.target_id = id
		cue["target_cell"] = cell


static func _recipient(cue: Dictionary, id: String, cell: Variant, kind: String) -> void:
	if id.is_empty() or not cell is Vector2i:
		return
	var entry := {"id": id, "cell": cell, "kind": kind}
	if entry not in cue.recipients:
		cue.recipients.append(entry)


static func _has_recipient(cue: Dictionary, kind: String) -> bool:
	return cue.recipients.any(func(recipient: Dictionary) -> bool: return recipient.kind == kind)


static func _trace_position(event: Dictionary, positions: Dictionary) -> void:
	match event.type:
		"move":
			positions[event.unit_id] = event.position
		"push", "repel":
			positions[event.target_id] = event.position
		"pull":
			positions[event.target_id] = event.position
			if event.has("recoil_position"):
				positions[event.unit_id] = event.recoil_position
		"swap":
			positions[event.unit_id] = event.position
			positions[event.target_id] = event.target_position
		"summon":
			positions[event.summon_id] = event.position
