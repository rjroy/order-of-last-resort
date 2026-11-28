extends RefCounted
## Cosmetic timeline. Different actors can act in parallel, but never overlap their own clips.

const CastSprites := preload("res://presentation/cast/cast_sprites.gd")
const FittedCastBindings := preload("res://presentation/cast/fitted_cast_bindings.gd")
const GIFT_FLIGHT_MS := 300.0
const FEEDBACK_MS := 280.0
const BEAT_GAP_MS := 120.0
const SILENT_BEAT_MS := 300.0
const DISPLACEMENT_MS := 180.0
# Cover can expire on an ally's otherwise silent Hold. Make the committed
# grant visible for a short beat, without inventing a Hold animation or sound.
const MIN_STATUS_VISIBILITY_MS := 240.0
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
const ACTOR_BEATS := {
	"blacksmith": {"try_this": 13, "hammer_time": 17, "pursue": 28,
		"bonk": 15, "acid": 18, "hit": 5, "down": 16, "recover": 22, "defeat": 16},
	"knight": {"bonk": 13, "bonk_unshielded": 13},
	"healer": {"blast": 12},
	"wizard": {"dodge": 11},
	"bard": {"push": 12},
	"rogue": {"potion": 15},
	"necromancer": {"melody": 13},
	"alchemist": {"pull": 13, "pull_upright": 13},
}
const SMITH_FIRST_PLANT_FRAME := 13
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
	var order: int
	var presentation_impact_emitted := false
	var handoff_ms := -1.0
	var handoff_emitted := false
	var extra_markers := {}
	var companion: Entry
	var companion_start_ms := 0.0

	func progress() -> float:
		return (elapsed_ms - impact_ms) / FEEDBACK_MS

	func flight_progress() -> float:
		return (elapsed_ms - clip.release_ms) / GIFT_FLIGHT_MS

	func is_shield_throw() -> bool:
		return cue.cast_key == "knight" and not cue.get("ordinary_presentation", false) \
			and (cue.clip == "shield_throw" or (cue.get("performance", {}).get("form_id") == "lend_a_shield" \
			and gift != null and clip.release_clip == "lend_a_shield_prop"))

var _entries: Array[Entry] = []
var _motions: Array[Dictionary] = []
var _settled := {}
var _last_presentation_beats: Array[Dictionary] = []
var _next_order := 0


func enqueue(cues: Array, art: CastSprites) -> void:
	var tails := {}
	var impacts := {}
	var cue_orders := {}
	var previous_beat := 0.0
	var has_beat := false
	var movement_barrier := 0.0
	var landings := {}
	var visible_status_until := {}
	var reached_round_end := false
	for entry in _entries:
		if not entry.cue.get("presentation_boundary", false) and not entry.cue.get("projection_only", false):
			tails[entry.cue.unit_id] = maxf(float(tails.get(entry.cue.unit_id, 0.0)),
				entry.duration_ms - entry.elapsed_ms)
		if entry.cue.has("companion_for"):
			continue # A companion occupies its actor, but performs no second rules action.
		var pending_beat := entry.impact_ms - entry.elapsed_ms
		if pending_beat > 0.0:
			previous_beat = maxf(previous_beat, pending_beat)
			has_beat = true
		_remember_status_grants(entry.cue, pending_beat, visible_status_until)
		if not entry.handoff_emitted and entry.handoff_ms >= 0.0:
			var pending_handoff := entry.handoff_ms - entry.elapsed_ms
			previous_beat = maxf(previous_beat, pending_handoff)
			has_beat = has_beat or pending_handoff > 0.0
			for effect: Dictionary in entry.cue.performance.effects:
				if effect.get("phase") == "handoff":
					landings[effect.retired_id] = pending_handoff
					landings[effect.target_id] = pending_handoff
	for motion in _motions:
		var pending_motion: float = motion.duration_ms - motion.elapsed_ms
		if pending_motion > 0.0:
			previous_beat = maxf(previous_beat, pending_motion)
			movement_barrier = maxf(movement_barrier, pending_motion)
			tails[motion.unit_id] = maxf(float(tails.get(motion.unit_id, 0.0)), pending_motion)
			landings[motion.unit_id] = maxf(float(landings.get(motion.unit_id, 0.0)), pending_motion)
			has_beat = true
	for index in cues.size():
		var value = cues[index]
		if not value is Dictionary or str(value.get("unit_id", "")).is_empty():
			continue
		if value.get("control") == "clear_pull_recoil":
			clear_pull_recoil(value.unit_id)
			continue
		if value.get("presentation_boundary", false):
			# Rule boundaries don't invent a cast or sound.
			var boundary_at := previous_beat
			var effect: Dictionary = value.performance.effects[0]
			if effect.get("timing") == "round_end" and not reached_round_end:
				# One boundary for the round-end group, not a pause per HP write.
				reached_round_end = true
				boundary_at += BEAT_GAP_MS if has_beat else 0.0
				previous_beat = boundary_at
				has_beat = true
			if effect.kind == "status_expired":
				var key := _status_key(effect)
				boundary_at = maxf(boundary_at, float(visible_status_until.get(key, 0.0)))
				visible_status_until.erase(key)
				if boundary_at > previous_beat:
					previous_beat = boundary_at
					has_beat = true
			var boundary := Entry.new()
			boundary.cue = value.merged({"cast_key": "", "clip": "", "target_id": "", "silent_action": true})
			boundary.clip = CastSprites.Clip.new()
			boundary.elapsed_ms = -boundary_at
			boundary.impact_ms = 0.0
			boundary.duration_ms = 1.0
			boundary.order = _timeline_order()
			_entries.append(boundary)
			impacts[index] = boundary_at
			continue
		if value.has("after_impacts"):
			# A motion-only continuation is scheduled after all of its causes
			# have been placed, without waiting for their recovery clips.
			var motion_start := 0.0
			for dependency in value.after_impacts:
				motion_start = maxf(motion_start, float(impacts.get(dependency, 0.0)))
			var cue_order := int(cue_orders.get(value.get("parent_cue", -1), -1))
			var landing := _enqueue_motion(value.motion, motion_start, DISPLACEMENT_MS, value, cue_order)
			landings[value.unit_id] = landing
			movement_barrier = maxf(movement_barrier, landing)
			previous_beat = maxf(previous_beat, landing)
			tails[value.unit_id] = maxf(float(tails.get(value.unit_id, 0.0)), landing)
			impacts[index] = landing
			has_beat = true
			continue
		var parent_index := int(value.get("after_cue", -1))
		var parent: Variant = impacts.get(parent_index)
		var entry := _entry_for(value, art)
		if entry == null:
			if parent != null:
				impacts[index] = parent # Missing art adds no time but still passes on its cause.
			continue
		var cue := entry.cue
		var clip := entry.clip
		entry.order = _timeline_order()
		cue_orders[index] = entry.order
		var start := 0.0 if cue.get("projection_only", false) else float(tails.get(cue.unit_id, 0.0))
		if cue.has("performance") or cue.get("wait_for_actor_landing", false):
			start = maxf(start, float(landings.get(cue.unit_id, 0.0)))
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
		if entry.companion != null:
			var recipient: String = entry.companion.cue.unit_id
			var prior_end := maxf(float(tails.get(recipient, 0.0)), float(landings.get(recipient, 0.0)))
			start = maxf(start, prior_end - entry.companion_start_ms)
		if primary:
			previous_beat = start + entry.impact_ms
			has_beat = true
		entry.elapsed_ms = -start
		_remember_status_grants(cue, start + entry.impact_ms, visible_status_until)
		if parent != null and has_beat:
			previous_beat = maxf(previous_beat, start + entry.impact_ms)
		if entry.handoff_ms >= 0.0:
			previous_beat = maxf(previous_beat, start + entry.handoff_ms)
			for effect: Dictionary in cue.performance.effects:
				if effect.get("phase") == "handoff":
					landings[effect.retired_id] = start + entry.handoff_ms
					landings[effect.target_id] = start + entry.handoff_ms
		for motion: Dictionary in cue.get("motions", []):
			var before: bool = motion.get("before_impact", false)
			var mode: String = motion.get("mode", "")
			var motion_start := start if before else start + entry.impact_ms
			var motion_duration := maxf(1.0, entry.impact_ms / float(counts.get(motion.unit_id, 1))) \
				if before else DISPLACEMENT_MS
			if mode == "cut":
				motion_duration = 0.0
			elif mode == "jump":
				var takeoff := clampf(_marker_time(clip, cue.get("takeoff_frame"), 0.0), 0.0, entry.impact_ms)
				motion_start = start + takeoff
				motion_duration = entry.impact_ms - takeoff
			motion_start = maxf(motion_start, float(landings.get(motion.unit_id, motion_start)))
			var plant_ms := -1.0
			if cue.cast_key == "blacksmith" and cue.clip == "pursue" and before and counts[motion.unit_id] == 1:
				plant_ms = _marker_time(clip, SMITH_FIRST_PLANT_FRAME, -1.0)
			var landing := _enqueue_motion(motion, motion_start, motion_duration, cue, entry.order, plant_ms)
			landings[motion.unit_id] = landing
			movement_barrier = maxf(movement_barrier, landing)
			if has_beat and not before:
				previous_beat = maxf(previous_beat, landing)
		if not cue.get("projection_only", false):
			tails[cue.unit_id] = entry.duration_ms - entry.elapsed_ms
		_entries.append(entry)
		if entry.companion != null:
			var companion := entry.companion
			companion.order = _timeline_order()
			companion.cue["companion_for"] = entry.order
			companion.elapsed_ms = -start - entry.companion_start_ms
			tails[companion.cue.unit_id] = companion.duration_ms - companion.elapsed_ms
			_entries.append(companion)
		impacts[index] = start + entry.impact_ms


## Loading, marker selection and neutral fallback are independent of where
## this entry lands in the queue. Legacy authored timings remain the default.
static func _entry_for(value: Dictionary, art: CastSprites, allow_binding := true) -> Entry:
	if allow_binding:
		value = _bind_performance(value, art)
	var role := str(value.get("cast_key", ""))
	var key := str(value.get("clip", ""))
	var rendered_key := key
	if role == "knight" and value.get("hero_defeat", false) and value.get("shield_away", false):
		rendered_key = "defeat_unshielded"
	var clip := art.clip_for(role, rendered_key)
	if role == "blacksmith" and key in ACTOR_BEATS.blacksmith and not _has_smith_clip(art, clip, key):
		clip = null
		key = ""
	var ordinary: bool = value.get("ordinary_presentation", false)
	if ordinary and value.get("ordinary_role") != "action" and _missing_atlas(clip):
		clip = null
	if ordinary and clip == null and value.get("fallback_clip") is String:
		key = value.fallback_clip
		clip = art.clip_for(role, key)
		if _missing_atlas(clip):
			clip = null
		value = value.duplicate()
		if value.has("fallback_impact_frame"):
			value["impact_frame"] = value.fallback_impact_frame
		if value.get("ordinary_role") == "tactical_retreat":
			value.erase("facing")
	var projection_only: bool = clip == null and (value.get("presentation_kind") == "projection" \
		or value.get("projection_fallback", false))
	var no_art: bool = clip == null and (projection_only or value.get("silent_action", false) or value.has("audio_ability"))
	if no_art:
		clip = CastSprites.Clip.new()
		clip.total_ms = 0.0 if projection_only else SILENT_BEAT_MS
	if clip == null or key == "ready" or (not ordinary and key in ["gift", "acid_flask", "harpoon_projectile"]):
		return null
	var cue: Dictionary = value.duplicate(true)
	if no_art:
		cue["silent_action"] = true
	if projection_only:
		cue["projection_only"] = true
		cue["presentation_kind"] = "projection"
		cue["recipients"] = []
	cue["cast_key"] = role
	cue["clip"] = key
	cue.erase("fallback_clip")
	cue.erase("fallback_impact_frame")
	cue["target_id"] = str(cue.get("target_id", ""))
	var entry := Entry.new()
	entry.cue = cue
	entry.clip = clip
	var declared_facing: Variant = cue.get("facing")
	entry.facing = float(declared_facing) if (declared_facing is int or declared_facing is float) \
		and absf(float(declared_facing)) == 1.0 else 0.0
	var beat: int = ACTOR_BEATS.get(role, {}).get(key, ACTION_BEATS.get(key, -1))
	if cue.get("hero_knockdown") in GUILD_REACTION_BEATS:
		beat = GUILD_REACTION_BEATS[cue.hero_knockdown]
	if cue.get("hero_defeat", false):
		beat = 16
		if cue.get("was_prone", false) or cue.get("start_grounded", false):
			entry.sample_offset_ms = clip.time_at_source_frame(16)
	entry.impact_ms = clip.time_at_source_frame(beat) \
		if not ordinary and beat >= 0 else clip.total_ms * 0.48
	entry.impact_ms = maxf(0.0, entry.impact_ms - entry.sample_offset_ms)
	entry.impact_ms = _marker_time(clip, cue.get("impact_frame"), entry.impact_ms)
	if cue.get("reveal_at_start", false):
		# Unlike an attack, the first drawn pose is itself the visible event.
		entry.impact_ms = 0.0
	var declared_impact: Variant = cue.get("impact_ms")
	if (declared_impact is int or declared_impact is float) and is_finite(float(declared_impact)) \
			and declared_impact >= 0.0 and declared_impact < clip.total_ms:
		entry.impact_ms = float(declared_impact)
	if key != "etching_paste" and not (role == "rogue" and key == "potion") \
			and clip.release_ms >= 0.0 and (cue.get("target_cell") is Vector2i or cue.get("shield_drop_cell") is Vector2i):
		entry.gift = art.clip_for(role, clip.release_clip)
		if entry.gift != null:
			entry.impact_ms = clip.release_ms + GIFT_FLIGHT_MS
	entry.duration_ms = 1.0 if projection_only \
		else maxf(clip.total_ms - entry.sample_offset_ms, entry.impact_ms + FEEDBACK_MS)
	if cue.has("performance"):
		_apply_performance_markers(entry)
	if cue.has("companion") and not _load_companion(entry, art):
		# The pair is one performance. Never claim a partial asset is the
		# full animation, or fall back to an incompatible ordinary gesture.
		var fallback := cue.merged({"clip": "", "silent_action": true}, true)
		for field in ["companion", "impact_frame", "impact_ms", "handoff_frame", "handoff_delay_ms"]:
			fallback.erase(field)
		return _entry_for(fallback, art, false)
	return entry


static func _missing_atlas(clip: CastSprites.Clip) -> bool:
	return clip != null and not clip.path.is_empty() and not FileAccess.file_exists(clip.path) \
		and not ResourceLoader.exists(clip.path, "Texture2D")


static func _apply_performance_markers(entry: Entry) -> void:
	var cue := entry.cue
	var clip := entry.clip
	var takeoff := _marker_time(clip, cue.get("takeoff_frame"), -1.0)
	if cue.performance.form_id == "clear_jump" and takeoff >= 0.0 and takeoff < entry.impact_ms:
		entry.extra_markers["takeoff"] = takeoff
	var claim := _marker_time(clip, cue.get("claim_frame"), -1.0)
	if cue.performance.form_id == "it_was_me" and claim >= entry.impact_ms:
		entry.extra_markers["claim"] = claim
	if cue.performance.effects.any(func(effect): return effect.get("phase") == "handoff"):
		# Place on an authored frame or after a companion gesture. A clipless
		# action defaults to impact and conveys no art or sound approval.
		var fallback := entry.impact_ms + maxf(0.0, float(cue.get("handoff_delay_ms", 0.0)))
		entry.handoff_ms = maxf(entry.impact_ms, _marker_time(clip, cue.get("handoff_frame"), fallback))
		entry.duration_ms = maxf(entry.duration_ms, entry.handoff_ms + FEEDBACK_MS)


static func _load_companion(entry: Entry, art: CastSprites) -> bool:
	var use: Dictionary = entry.cue.get("performance", {})
	var binding: Variant = entry.cue.get("companion")
	if not binding is Dictionary or use.get("branch") != "converted" or entry.cue.get("silent_action", false):
		return false
	var kind: String = binding.get("effect_kind", "")
	if kind not in ["recall", "play_dead"]:
		return false
	var effects: Array = use.effects.filter(func(effect): return effect.kind == kind)
	if effects.size() != 1:
		return false
	var effect: Dictionary = effects[0]
	var recall := kind == "recall"
	var id: String = effect.get("target_id" if recall else "retired_id", "")
	var role: String = effect.get("cast_key" if recall else "retired_cast_key", "")
	var cell: Variant = effect.get("to" if recall else "cell")
	var key: String = binding.get("clip", "")
	var clip := art.clip_for(role, key)
	var start := _marker_time(entry.clip, binding.get("start_frame"), -1.0)
	if id.is_empty() or id == entry.cue.unit_id or not cell is Vector2i or start < 0.0 \
			or role != ("skeleton" if recall else "zombie") \
			or key != ("recall_tuck" if recall else "play_dead") or not _has_drawing(clip, 1) or clip.loop:
		return false
	var duration := clip.total_ms
	if recall:
		if not is_equal_approx(start, entry.impact_ms):
			return false
	else:
		var terminal: int = binding.get("handoff_frame", -1)
		var last_sample := clip.source_frames.find(terminal)
		if last_sample < 0 or last_sample >= clip.frame_ends.size():
			return false
		# Swap only after the terminal drawing has been on screen for its
		# entire authored hold, not when that sample first becomes active.
		duration = clip.frame_ends[last_sample]
		entry.handoff_ms = start + duration
		entry.duration_ms = maxf(entry.duration_ms, entry.handoff_ms + FEEDBACK_MS)
	var companion := Entry.new()
	companion.cue = {"unit_id": id, "cast_key": role, "clip": key, "target_id": entry.cue.unit_id,
		"target_cell": use.source_cell, "source_cell": cell, "actor_cell": cell, "recipients": [],
		"requires_existing_figure": true}
	companion.clip = clip
	companion.duration_ms = duration
	entry.companion = companion
	entry.companion_start_ms = start
	return true


static func _bind_performance(cue: Dictionary, art: CastSprites) -> Dictionary:
	var use: Dictionary = cue.get("performance", {})
	if FittedCastBindings.replays_fitted_dose(use):
		# A fitted delivery can deliberately be clipless. Never fall back to
		# the ordinary recipe clip, release metadata or recipient marks.
		cue = cue.merged({"clip": "", "silent_action": true, "recipients": []}, true)
		for field in ["fallback_clip", "impact_frame", "impact_ms"]:
			cue.erase(field)
	elif not str(cue.get("clip", "")).is_empty():
		return cue
	var binding := FittedCastBindings.lookup(use, art.clip_for)
	if binding.is_empty():
		return cue
	if use.get("form_id") in ["recall_skeleton", "play_dead"] and not binding.has("companion"):
		return cue
	var bound := cue.merged(binding, true)
	bound.erase("silent_action")
	return bound


static func _has_smith_clip(art: CastSprites, clip: CastSprites.Clip, key: String) -> bool:
	var frame: int = ACTOR_BEATS.blacksmith[key]
	if not _has_drawing(clip, frame) or clip.loop:
		return false
	if key == "acid":
		return clip.release_clip == "acid_flask" \
			and is_equal_approx(clip.release_ms, clip.time_at_source_frame(frame)) \
			and _has_drawing(art.clip_for("blacksmith", clip.release_clip), frame)
	return key != "pursue" or SMITH_FIRST_PLANT_FRAME in clip.source_frames


static func _has_drawing(clip: CastSprites.Clip, frame: int) -> bool:
	return clip != null and not clip.frames.is_empty() and frame in clip.source_frames \
		and (FileAccess.file_exists(clip.path) or ResourceLoader.exists(clip.path, "Texture2D"))


static func _status_key(effect: Dictionary) -> Array:
	return [effect.target_id, effect.status_id]


static func _remember_status_grants(cue: Dictionary, impact: float, windows: Dictionary) -> void:
	for effect: Dictionary in cue.get("performance", {}).get("effects", []):
		if effect.kind != "status" or effect.get("status_id") not in ["keep_your_head_down", "lend_a_shield", "steady_hands"]:
			continue
		var key := _status_key(effect)
		if effect.get("consumed", false):
			windows.erase(key)
		elif impact + MIN_STATUS_VISIBILITY_MS > 0.0:
			windows[key] = impact + MIN_STATUS_VISIBILITY_MS


static func _marker_time(clip: CastSprites.Clip, frame: Variant, fallback: float) -> float:
	return clip.time_at_source_frame(frame) if frame is int and frame in clip.source_frames else fallback


func _timeline_order() -> int:
	var order := _next_order
	_next_order += 1
	return order


func _enqueue_motion(motion: Dictionary, start: float, duration: float, cue: Dictionary, cue_order: int,
		plant_ms := -1.0) -> float:
	var mode: String = motion.get("mode", "")
	var step: bool = mode == "release_step" or (motion.get("before_impact", false) and mode != "jump")
	var use: Dictionary = cue.get("performance", {})
	var matching: Array = []
	if not use.is_empty() and motion.has("event_index"):
		matching = use.effects.filter(func(effect):
			return effect.get("motion_event_index", effect.event_index) == motion.event_index \
				and effect.get("phase") == "landing" \
				and effect.target_id == motion.unit_id)
	_motions.append({"unit_id": motion.unit_id, "from": motion.from, "to": motion.to,
		"elapsed_ms": -start, "duration_ms": duration, "step": step, "order": _timeline_order(),
		"cue_order": cue_order,
		"ability_id": "move" if mode == "release_step" else cue.get("audio_ability", "move"),
		"mode": mode, "performance": use if not matching.is_empty() else {}, "effects": matching,
		"plant_ms": plant_ms})
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
	_last_presentation_beats.clear()
	_next_order = 0


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
		if entry.cue.get("unit_id") != unit_id:
			continue
		# A Pull supplies its own fall rather than a separate down reaction.
		# Until it starts, the final knockdown must not hide earlier gestures.
		if entry.cue.get("pull_recoil_down", false) and entry.elapsed_ms < 0.0:
			return "ready"
		if not entry.cue.has("hero_knockdown"):
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
			if motion.duration_ms == 0.0:
				return 0.0 # Cut: hold the origin until advance() swaps cells.
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


func has_pending_reveal(unit_id: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.unit_id == unit_id \
		and entry.cue.get("reveal_at_start", false) and not entry.presentation_impact_emitted)


func has_waiting_upright_hit(unit_id: String) -> bool:
	return _entries.any(func(entry: Entry): return entry.cue.get("unit_id") == unit_id \
		and entry.cue.get("ordinary_presentation", false) and entry.cue.get("ordinary_role") == "hit" \
		and not entry.cue.get("was_prone", false) and entry.elapsed_ms < 0.0)


func advance(delta_ms: float) -> Array:
	var beats := []
	_last_presentation_beats.clear()
	var remaining_motions: Array[Dictionary] = []
	for motion in _motions:
		var previous: float = motion.elapsed_ms
		motion.elapsed_ms += delta_ms
		if motion.plant_ms >= 0.0 and previous < motion.plant_ms and motion.elapsed_ms >= motion.plant_ms:
			beats.append(_step_beat(motion, motion.plant_ms - previous))
		if motion.elapsed_ms >= motion.duration_ms:
			_settled[motion.unit_id] = motion.to
			var offset := maxf(0.0, motion.duration_ms - previous)
			if not motion.performance.is_empty():
				_record_presentation("motion_land", motion.performance, motion.effects, offset, motion.cue_order, motion.order)
				_last_presentation_beats.back()["motion_mode"] = motion.mode
				_last_presentation_beats.back()["motion_order"] = motion.order
			if motion.get("step", false):
				beats.append(_step_beat(motion, offset))
		else:
			remaining_motions.append(motion)
	_motions = remaining_motions
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		var previous := entry.elapsed_ms
		entry.elapsed_ms += delta_ms
		_advance_presentation(entry, previous)
		if not entry.sound_emitted and entry.cue.has("audio_ability") \
				and entry.cue.get("audio_handler") != "move" and entry.elapsed_ms >= entry.impact_ms:
			entry.sound_emitted = true
			beats.append({"kind": "impact", "unit_id": entry.cue.unit_id,
				"ability_id": entry.cue.audio_ability, "handler": _audio_handler(entry.cue),
				"recipe": entry.cue.get("audio_recipe", ""),
				"offset": maxf(0.0, entry.impact_ms - previous), "order": entry.order, "cue_order": entry.order})
		if entry.elapsed_ms >= entry.duration_ms:
			_entries.remove_at(index)
	if _entries.is_empty() and _motions.is_empty():
		_settled.clear()
	beats.sort_custom(_beat_before)
	for beat: Dictionary in beats:
		beat.erase("order")
	_last_presentation_beats.sort_custom(_beat_before)
	for beat in _last_presentation_beats:
		beat.erase("order")
	return beats


static func _step_beat(motion: Dictionary, offset: float) -> Dictionary:
	return {"kind": "step", "unit_id": motion.unit_id, "ability_id": motion.ability_id,
		"handler": "move", "recipe": "", "offset": offset, "order": motion.order,
		"cue_order": motion.cue_order, "motion_order": motion.order}


## Facts that crossed the same clock as the audio return from advance().
## This does not dispatch media and is replaced by the next advance or clear.
func presentation_beats() -> Array[Dictionary]:
	return _last_presentation_beats.duplicate(true)


## Find the still-queued companion of this exact performance, even if its
## performer has finished. A reused recipient ID is not a playback identity.
func companion_for(cue_order: int) -> Entry:
	if cue_order < 0:
		return null
	for entry in _entries:
		if entry.cue.get("companion_for", -1) == cue_order:
			return entry
	return null


func _advance_presentation(entry: Entry, previous: float) -> void:
	var use: Dictionary = entry.cue.get("performance", {})
	if use.is_empty():
		return
	for kind: String in entry.extra_markers.keys():
		var marker: float = entry.extra_markers[kind]
		if entry.elapsed_ms >= marker:
			_record_presentation(kind, use, [], maxf(0.0, marker - previous), entry.order, entry.order)
			entry.extra_markers.erase(kind)
	if not entry.presentation_impact_emitted and entry.elapsed_ms >= entry.impact_ms:
		entry.presentation_impact_emitted = true
		var effects: Array = use.effects.filter(func(effect): return not effect.has("phase"))
		var default_kind := "status" if entry.cue.get("presentation_boundary", false) else "impact"
		var kind: String = entry.cue.get("presentation_kind", default_kind)
		_record_presentation(kind, use, effects, maxf(0.0, entry.impact_ms - previous), entry.order, entry.order)
	if entry.handoff_ms >= 0.0 and not entry.handoff_emitted and entry.elapsed_ms >= entry.handoff_ms:
		entry.handoff_emitted = true
		var effects: Array = use.effects.filter(func(effect): return effect.get("phase") == "handoff")
		_record_presentation("handoff", use, effects, maxf(0.0, entry.handoff_ms - previous), entry.order, entry.order)


func _record_presentation(kind: String, use: Dictionary, effects: Array, offset: float,
		cue_order: int, order: int) -> void:
	var beat := use.duplicate()
	beat.merge({"kind": kind, "effects": effects, "performance_effects": use.effects,
		"offset": offset, "cue_order": cue_order, "order": order}, true)
	_last_presentation_beats.append(beat)


static func _beat_before(a: Dictionary, b: Dictionary) -> bool:
	if a.offset != b.offset:
		return a.offset < b.offset
	if a.order != b.order:
		return a.order < b.order
	return a.kind == "impact" and b.kind != "impact"


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
