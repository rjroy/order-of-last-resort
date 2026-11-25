extends RefCounted
## Cosmetic timeline. Different actors can act in parallel, but never overlap their own clips.

const CastSprites := preload("res://presentation/cast_sprites.gd")
const GIFT_FLIGHT_MS := 300.0
const FEEDBACK_MS := 280.0
const BEAT_GAP_MS := 120.0
const SILENT_BEAT_MS := 300.0
const DISPLACEMENT_MS := 180.0
const ACTION_BEATS := {
	"guard": 39, "ally_heal": 17, "self_heal": 17, "bonk": 15,
	"blast": 17, "pull": 13, "retreat": 13, "swap": 15, "misdirect": 14,
	"inspiring_melody": 25, "healing_sonnet": 25, "summon_skeleton": 20, "raise_dead": 34,
	"wave": 18, "dont_go": 27, "say_hello": 25,
	"close_thrust": 8,
	"rescue_line": 14, "rescue_line_unshielded": 14, "ring_sparks": 12,
	"tripwire": 13, "grave_bell": 12, "etching_paste": 13,
	"nominate": 13,
}
const LEARNER_BEATS := {
	"knight": {"bonk": 13, "bonk_unshielded": 13},
	"healer": {"blast": 12},
	"wizard": {"dodge": 11},
	"bard": {"push": 12},
	"rogue": {"potion": 15},
	"necromancer": {"melody": 13},
	"alchemist": {"pull": 13, "pull_upright": 13},
}
const GUILD_REACTION_BEATS := {"down": 16, "recover": 22, "seated_recover": 22}

class Entry:
	var cue: Dictionary
	var clip: CastSprites.Clip
	var elapsed_ms := 0.0
	var duration_ms: float
	var impact_ms: float
	var gift: CastSprites.Clip
	var gift_from: Variant = null
	var gift_to: Variant = null
	var gift_angle := 0.0
	var gift_point_first := false
	var facing: float
	var waits_for_throw := false
	var sample_offset_ms := 0.0
	var sound_emitted := false

	func progress() -> float:
		return (elapsed_ms - impact_ms) / FEEDBACK_MS

	func flight_progress() -> float:
		return (elapsed_ms - clip.release_ms) / GIFT_FLIGHT_MS

	func is_shield_throw() -> bool:
		return cue.cast_key == "knight" and cue.clip == "shield_throw" \
			and not cue.get("ordinary_presentation", false)

var _entries: Array[Entry] = []
var _motions: Array[Dictionary] = []
var _settled := {}


func enqueue(cues: Array, art: CastSprites) -> void:
	var tails := {}
	var impacts := {}
	var previous_beat := 0.0
	var has_beat := false
	var movement_barrier := 0.0
	for entry in _entries:
		tails[entry.cue.unit_id] = entry.duration_ms - entry.elapsed_ms
		var pending_beat := entry.impact_ms - entry.elapsed_ms
		if pending_beat > 0.0:
			previous_beat = maxf(previous_beat, pending_beat)
			has_beat = true
	for motion in _motions:
		var pending_motion: float = motion.duration_ms - motion.elapsed_ms
		if pending_motion > 0.0:
			previous_beat = maxf(previous_beat, pending_motion)
			movement_barrier = maxf(movement_barrier, pending_motion)
			tails[motion.unit_id] = maxf(float(tails.get(motion.unit_id, 0.0)), pending_motion)
			has_beat = true
	for index in cues.size():
		var value = cues[index]
		if not value is Dictionary or str(value.get("unit_id", "")).is_empty():
			continue
		if value.get("control") == "clear_pull_recoil":
			clear_pull_recoil(value.unit_id)
			continue
		if value.has("after_impacts"):
			# A motion-only continuation is scheduled after all of its causes
			# have been placed, without waiting for their recovery clips.
			var motion_start := 0.0
			for dependency in value.after_impacts:
				motion_start = maxf(motion_start, float(impacts.get(dependency, 0.0)))
			var landing := _enqueue_motion(value.motion, motion_start, DISPLACEMENT_MS, value)
			movement_barrier = maxf(movement_barrier, landing)
			previous_beat = maxf(previous_beat, landing)
			tails[value.unit_id] = maxf(float(tails.get(value.unit_id, 0.0)), landing)
			impacts[index] = landing
			has_beat = true
			continue
		var role := str(value.get("cast_key", ""))
		var key := str(value.get("clip", ""))
		var rendered_key := key
		if role == "knight" and value.get("hero_defeat", false) and value.get("shield_away", false):
			rendered_key = "defeat_unshielded"
		var clip := art.clip_for(role, rendered_key)
		var ordinary: bool = value.get("ordinary_presentation", false)
		if ordinary and clip == null and value.get("fallback_clip") is String:
			key = value.fallback_clip
			clip = art.clip_for(role, key)
		var no_art: bool = clip == null and (value.get("silent_action", false) or value.has("audio_ability"))
		if no_art:
			clip = CastSprites.Clip.new()
			clip.total_ms = SILENT_BEAT_MS
		var parent_index := int(value.get("after_cue", -1))
		var parent: Variant = impacts.get(parent_index)
		if clip == null or key == "ready" \
				or (not ordinary and key in ["gift", "acid_flask", "harpoon_projectile"]):
			if parent != null:
				impacts[index] = parent # Missing art adds no time but still passes on its cause.
			continue
		var cue: Dictionary = value.duplicate(true)
		if no_art:
			cue["silent_action"] = true
		cue["clip"] = key
		cue.erase("fallback_clip")
		cue["target_id"] = str(cue.get("target_id", ""))
		var entry := Entry.new()
		entry.cue = cue
		entry.clip = clip
		var declared_facing: Variant = cue.get("facing")
		entry.facing = float(declared_facing) if (declared_facing is int or declared_facing is float) \
			and absf(float(declared_facing)) == 1.0 else 0.0
		var beat: int = LEARNER_BEATS.get(role, {}).get(key, ACTION_BEATS.get(key, -1))
		if cue.get("hero_knockdown") in GUILD_REACTION_BEATS:
			beat = GUILD_REACTION_BEATS[cue.hero_knockdown]
		if cue.get("hero_defeat", false):
			beat = 16
			if cue.get("was_prone", false) or cue.get("start_grounded", false):
				entry.sample_offset_ms = clip.time_at_source_frame(16)
		entry.impact_ms = clip.time_at_source_frame(beat) \
			if not ordinary and beat >= 0 else clip.total_ms * 0.48
		entry.impact_ms = maxf(0.0, entry.impact_ms - entry.sample_offset_ms)
		if ordinary and cue.get("impact_frame") is int and cue.impact_frame in clip.source_frames:
			entry.impact_ms = clip.time_at_source_frame(cue.impact_frame)
		if key != "etching_paste" and not (role == "rogue" and key == "potion") \
				and clip.release_ms >= 0.0 and (cue.get("target_cell") is Vector2i \
				or cue.get("shield_drop_cell") is Vector2i):
			entry.gift = art.clip_for(role, clip.release_clip)
			if entry.gift != null:
				entry.impact_ms = clip.release_ms + GIFT_FLIGHT_MS
		entry.duration_ms = maxf(clip.total_ms - entry.sample_offset_ms, entry.impact_ms + FEEDBACK_MS)
		var start := float(tails.get(cue.unit_id, 0.0))
		if parent != null:
			start = maxf(start, float(parent))
		var primary: bool = cue.get("action_beat", not cue.has("after_cue"))
		var counts := {}
		for motion: Dictionary in cue.get("motions", []):
			if motion.get("before_impact", false):
				counts[motion.unit_id] = int(counts.get(motion.unit_id, 0)) + 1
		if primary:
			if has_beat:
				start = maxf(start, previous_beat + BEAT_GAP_MS - entry.impact_ms)
				for id in counts:
					var first_landing := maxf(1.0, entry.impact_ms / float(counts[id]))
					start = maxf(start, previous_beat + BEAT_GAP_MS - first_landing)
		if not counts.is_empty():
			# Travel itself is a visible rules event, not merely the action's
			# later impact. Earlier displacement must land before it begins.
			start = maxf(start, movement_barrier)
		var throw_wait := _swap_throw_wait(cue)
		entry.waits_for_throw = throw_wait > 0.0
		start = maxf(start, throw_wait)
		if primary:
			previous_beat = start + entry.impact_ms
			has_beat = true
		entry.elapsed_ms = -start
		if parent != null and has_beat:
			previous_beat = maxf(previous_beat, start + entry.impact_ms)
		var motion_tails := {}
		for motion: Dictionary in cue.get("motions", []):
			var before: bool = motion.get("before_impact", false)
			var motion_start := start if before else start + entry.impact_ms
			var motion_duration := maxf(1.0, entry.impact_ms / float(counts.get(motion.unit_id, 1))) \
				if before else DISPLACEMENT_MS
			motion_start = maxf(motion_start, float(motion_tails.get(motion.unit_id, motion_start)))
			var landing := _enqueue_motion(motion, motion_start, motion_duration, cue)
			motion_tails[motion.unit_id] = landing
			movement_barrier = maxf(movement_barrier, landing)
			if has_beat and not before:
				previous_beat = maxf(previous_beat, landing)
		tails[cue.unit_id] = entry.duration_ms - entry.elapsed_ms
		_entries.append(entry)
		impacts[index] = start + entry.impact_ms


func _enqueue_motion(motion: Dictionary, start: float, duration: float, cue: Dictionary) -> float:
	_motions.append({"unit_id": motion.unit_id, "from": motion.from, "to": motion.to,
		"elapsed_ms": -start, "duration_ms": duration, "step": motion.get("before_impact", false),
		"ability_id": cue.get("audio_ability", "move")})
	return start + duration


func _swap_throw_wait(cue: Dictionary) -> float:
	var partner: String = cue.get("swap_partner_id", "")
	if partner.is_empty():
		return 0.0
	# A resolved swap would place its actor on the thrower's visible cast cell.
	# The queue includes earlier cues from this batch and from previous commits.
	var wait := 0.0
	for entry in _entries:
		if entry.cue.unit_id == partner and entry.is_shield_throw() \
				and entry.cue.get("shield_drop_cell") is Vector2i \
				and entry.cue.get("actor_cell") == cue.actor_cell:
			wait = maxf(wait, entry.duration_ms - entry.elapsed_ms)
	return wait


func clear() -> void:
	_entries.clear()
	_motions.clear()
	_settled.clear()


func clear_pull_recoil(unit_id: String) -> void:
	for entry in _entries:
		if entry.cue.get("unit_id") == unit_id and entry.cue.get("cast_key") in ["wizard", "alchemist"] \
				and entry.cue.get("clip") == "pull" and not entry.cue.get("ordinary_presentation", false):
			entry.cue.erase("pull_recoil_down")


func pull_recoil_facing(unit_id: String) -> float:
	# A pre-metadata save may still have its own Pull waiting in the queue.
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		if entry.cue.get("unit_id") != unit_id or entry.cue.get("cast_key") not in ["wizard", "alchemist"] \
				or entry.cue.get("clip") != "pull" or not entry.cue.get("pull_recoil_down", false):
			continue
		if entry.facing != 0.0:
			return entry.facing
		var source: Variant = entry.cue.get("source_cell")
		var target: Variant = entry.cue.get("target_cell")
		if source is Vector2i and target is Vector2i and source.x != target.x:
			return -1.0 if target.x < source.x else 1.0
	return 0.0


func shield_in_transit(cell: Vector2i) -> bool:
	for entry in _entries:
		if entry.is_shield_throw() \
				and entry.cue.get("shield_drop_cell") == cell \
				and entry.gift != null and entry.elapsed_ms < entry.impact_ms:
			return true
	return false


func pending() -> bool:
	return not _entries.is_empty() or not _motions.is_empty()


func remaining_ms() -> float:
	var remaining := 0.0
	for entry in _entries:
		remaining = maxf(remaining, entry.duration_ms - entry.elapsed_ms)
	for motion in _motions:
		remaining = maxf(remaining, motion.duration_ms - motion.elapsed_ms)
	return remaining


func waiting_swap_cell(unit_id: String) -> Variant:
	for entry in _entries:
		if not entry.waits_for_throw or entry.elapsed_ms >= 0.0:
			continue
		if entry.cue.unit_id == unit_id:
			return entry.cue.get("source_cell")
		if entry.cue.swap_partner_id == unit_id:
			return entry.cue.get("actor_cell")
	return null


func hero_pending_pose(unit_id: String) -> String:
	# The final rules snapshot can be ahead of this unit's queued reactions.
	for entry in _entries:
		if entry.cue.get("unit_id") != unit_id or not entry.cue.has("hero_knockdown"):
			continue
		var kind: String = entry.cue.hero_knockdown
		if entry.elapsed_ms < 0.0:
			if kind == "down":
				return "ready"
			return "seated" if kind == "seated_recover" else "down"
		if entry.elapsed_ms >= entry.clip.total_ms:
			return "down" if kind == "down" else "ready"
		return ""
	return ""


func actor_cell(unit_id: String, fallback: Vector2i) -> Vector2i:
	for motion in _motions:
		if motion.unit_id == unit_id:
			return motion.from
	if _settled.has(unit_id):
		return _settled[unit_id]
	for entry in _entries:
		if entry.cue.get("unit_id") != unit_id:
			continue
		var cell: Variant = entry.cue.get("actor_cell")
		if (entry.cue.get("clip") == "travel" or entry.cue.get("ordinary_presentation", false)) \
				and entry.elapsed_ms < 0.0:
			cell = entry.cue.get("source_cell", cell)
		if cell is Vector2i:
			return cell
	return fallback


func movement_fraction(unit_id: String) -> float:
	for motion in _motions:
		if motion.unit_id == unit_id:
			return clampf(motion.elapsed_ms / motion.duration_ms, 0.0, 1.0)
	return 0.0


func movement_destination(unit_id: String) -> Variant:
	for motion in _motions:
		if motion.unit_id == unit_id:
			return motion.to
	return null


func movement_source(unit_id: String) -> Variant:
	for motion in _motions:
		if motion.unit_id == unit_id:
			return motion.from
	return null


func has_settled_position(unit_id: String) -> bool:
	return _settled.has(unit_id)


func has_pending_clip(unit_id: String, key: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.get("unit_id") == unit_id \
		and entry.cue.get("clip") == key)


func pending_hero_defeat(unit_id: String) -> Dictionary:
	for entry in _entries:
		if entry.cue.get("unit_id") == unit_id and entry.cue.get("hero_defeat", false):
			return entry.cue
	return {}


func has_pending_ordinary_role(unit_id: String, role: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.get("unit_id") == unit_id \
		and entry.cue.get("ordinary_presentation", false) and entry.cue.get("ordinary_role") == role)


func has_waiting_upright_hit(unit_id: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.get("unit_id") == unit_id \
		and entry.cue.get("ordinary_presentation", false) and entry.cue.get("ordinary_role") == "hit" \
		and not entry.cue.get("was_prone", false) and entry.elapsed_ms < 0.0)


func advance(delta_ms: float) -> Array:
	var beats := []
	var remaining_motions: Array[Dictionary] = []
	for motion in _motions:
		var previous: float = motion.elapsed_ms
		motion.elapsed_ms += delta_ms
		if motion.elapsed_ms >= motion.duration_ms:
			_settled[motion.unit_id] = motion.to
			if motion.get("step", false):
				beats.append({"kind": "step", "unit_id": motion.unit_id,
					"ability_id": motion.ability_id, "handler": "move", "recipe": "",
					"offset": maxf(0.0, motion.duration_ms - previous)})
		else:
			remaining_motions.append(motion)
	_motions = remaining_motions
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		var previous := entry.elapsed_ms
		entry.elapsed_ms += delta_ms
		if not entry.sound_emitted and entry.cue.has("audio_ability") \
				and entry.cue.get("audio_handler") != "move" and entry.elapsed_ms >= entry.impact_ms:
			entry.sound_emitted = true
			beats.append({"kind": "impact", "unit_id": entry.cue.unit_id,
				"ability_id": entry.cue.audio_ability, "handler": _audio_handler(entry.cue),
				"recipe": entry.cue.get("audio_recipe", ""),
				"offset": maxf(0.0, entry.impact_ms - previous)})
		if entry.elapsed_ms >= entry.duration_ms:
			_entries.remove_at(index)
	if _entries.is_empty() and _motions.is_empty():
		_settled.clear()
	beats.sort_custom(func(a: Dictionary, b: Dictionary): return a.offset < b.offset)
	return beats


func _audio_handler(cue: Dictionary) -> String:
	var handler: String = cue.get("audio_handler", "")
	var source: Variant = cue.get("source_cell")
	var target: Variant = cue.get("target_cell")
	if handler == "attack" and cue.get("audio_ability") == "enemy_harpoon" \
			and source is Vector2i and target is Vector2i \
			and absi(source.x - target.x) + absi(source.y - target.y) <= 1:
		return "close_thrust"
	return handler


func active() -> Array[Entry]:
	var result: Array[Entry] = []
	for entry in _entries:
		if entry.elapsed_ms >= 0.0:
			result.append(entry)
	return result


func snapshot() -> Array:
	var result: Array = []
	for entry in _entries:
		result.append(entry.cue.duplicate(true))
	return result
