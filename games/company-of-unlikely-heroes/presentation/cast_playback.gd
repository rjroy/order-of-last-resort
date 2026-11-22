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
	var facing: float

	func progress() -> float:
		return (elapsed_ms - impact_ms) / FEEDBACK_MS

	func flight_progress() -> float:
		return (elapsed_ms - clip.release_ms) / GIFT_FLIGHT_MS

var _entries: Array[Entry] = []


func enqueue(cues: Array, art: CastSprites) -> void:
	var tails := {}
	for entry in _entries:
		tails[entry.cue.unit_id] = entry.duration_ms - entry.elapsed_ms
	for value in cues:
		if not value is Dictionary or str(value.get("unit_id", "")).is_empty():
			continue
		var role := str(value.get("cast_key", ""))
		var key := str(value.get("clip", ""))
		var clip := art.clip_for(role, key)
		if clip == null or key in ["ready", "gift", "acid_flask"]:
			continue
		var cue: Dictionary = value.duplicate(true)
		cue["target_id"] = str(cue.get("target_id", ""))
		var entry := Entry.new()
		entry.cue = cue
		entry.clip = clip
		entry.facing = 0.0
		entry.impact_ms = clip.time_at_source_frame(ACTION_BEATS[key]) \
			if ACTION_BEATS.has(key) else clip.total_ms * 0.48
		if clip.release_ms >= 0.0:
			entry.gift = art.clip_for(role, clip.release_clip)
			if entry.gift != null:
				entry.impact_ms = clip.release_ms + GIFT_FLIGHT_MS
		entry.duration_ms = maxf(clip.total_ms, entry.impact_ms + FEEDBACK_MS)
		entry.elapsed_ms = -float(tails.get(cue.unit_id, 0.0))
		tails[cue.unit_id] = entry.duration_ms - entry.elapsed_ms
		_entries.append(entry)


func clear() -> void:
	_entries.clear()


func pending() -> bool:
	return not _entries.is_empty()


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
