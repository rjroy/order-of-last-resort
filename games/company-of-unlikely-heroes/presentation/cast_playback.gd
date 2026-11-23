extends RefCounted
## Cosmetic timeline. Different actors can act in parallel, but never overlap their own clips.

const CastSprites := preload("res://presentation/cast_sprites.gd")
const GIFT_FLIGHT_MS := 300.0
const FEEDBACK_MS := 280.0
const ACTION_BEATS := {
	"guard": 39, "ally_heal": 17, "self_heal": 17, "bonk": 15,
	"blast": 17, "pull": 13, "retreat": 13, "swap": 15, "misdirect": 14,
	"inspiring_melody": 25, "healing_sonnet": 25, "summon_skeleton": 20, "raise_dead": 34,
	"wave": 18, "dont_go": 27, "say_hello": 25,
	"close_thrust": 8,
	"rescue_line": 14, "rescue_line_unshielded": 14, "ring_sparks": 12,
	"tripwire": 13, "grave_bell": 12, "etching_paste": 13,
}

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

	func progress() -> float:
		return (elapsed_ms - impact_ms) / FEEDBACK_MS

	func flight_progress() -> float:
		return (elapsed_ms - clip.release_ms) / GIFT_FLIGHT_MS

var _entries: Array[Entry] = []


func enqueue(cues: Array, art: CastSprites) -> void:
	var tails := {}
	var added := {}
	for entry in _entries:
		tails[entry.cue.unit_id] = entry.duration_ms - entry.elapsed_ms
	for index in cues.size():
		var value = cues[index]
		if not value is Dictionary or str(value.get("unit_id", "")).is_empty():
			continue
		var role := str(value.get("cast_key", ""))
		var key := str(value.get("clip", ""))
		var clip := art.clip_for(role, key)
		var ordinary: bool = value.get("ordinary_presentation", false)
		if ordinary and clip == null and value.get("fallback_clip") is String:
			key = value.fallback_clip
			clip = art.clip_for(role, key)
		if clip == null or key == "ready" \
				or (not ordinary and key in ["gift", "acid_flask", "harpoon_projectile"]):
			continue
		var cue: Dictionary = value.duplicate(true)
		cue["clip"] = key
		cue.erase("fallback_clip")
		cue["target_id"] = str(cue.get("target_id", ""))
		var entry := Entry.new()
		entry.cue = cue
		entry.clip = clip
		entry.facing = 0.0
		entry.impact_ms = clip.time_at_source_frame(ACTION_BEATS[key]) \
			if not ordinary and ACTION_BEATS.has(key) else clip.total_ms * 0.48
		if ordinary and cue.get("impact_frame") is int and cue.impact_frame in clip.source_frames:
			entry.impact_ms = clip.time_at_source_frame(cue.impact_frame)
		if key != "etching_paste" and clip.release_ms >= 0.0 and cue.get("target_cell") is Vector2i:
			entry.gift = art.clip_for(role, clip.release_clip)
			if entry.gift != null:
				entry.impact_ms = clip.release_ms + GIFT_FLIGHT_MS
		entry.duration_ms = maxf(clip.total_ms, entry.impact_ms + FEEDBACK_MS)
		var start := float(tails.get(cue.unit_id, 0.0))
		var parent: Variant = added.get(int(cue.get("after_cue", -1)))
		if parent != null:
			start = maxf(start, -parent.elapsed_ms + parent.impact_ms)
		entry.elapsed_ms = -start
		tails[cue.unit_id] = entry.duration_ms - entry.elapsed_ms
		_entries.append(entry)
		added[index] = entry


func clear() -> void:
	_entries.clear()


func pending() -> bool:
	return not _entries.is_empty()


func remaining_ms() -> float:
	var remaining := 0.0
	for entry in _entries:
		remaining = maxf(remaining, entry.duration_ms - entry.elapsed_ms)
	return remaining


func actor_cell(unit_id: String, fallback: Vector2i) -> Vector2i:
	# A waiting move still occupies its source. A playing move lands at its
	# destination, while actions/damage reactions use their action-time cells.
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


func has_pending_clip(unit_id: String, key: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.get("unit_id") == unit_id \
		and entry.cue.get("clip") == key)


func has_pending_ordinary_role(unit_id: String, role: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.get("unit_id") == unit_id \
		and entry.cue.get("ordinary_presentation", false) and entry.cue.get("ordinary_role") == role)


func has_waiting_upright_hit(unit_id: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.get("unit_id") == unit_id \
		and entry.cue.get("ordinary_presentation", false) and entry.cue.get("ordinary_role") == "hit" \
		and not entry.cue.get("was_prone", false) and entry.elapsed_ms < 0.0)


func advance(delta_ms: float) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		entry.elapsed_ms += delta_ms
		if entry.elapsed_ms >= entry.duration_ms:
			_entries.remove_at(index)


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
