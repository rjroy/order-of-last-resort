extends RefCounted
## Approved wearer art for committed conversions and repeats of fitted bottles.
## No entry on either path means keep the effects but play no performer clip.

const CastSprites = preload("res://presentation/cast/cast_sprites.gd")

# Wearer -> form -> [source ability, source handler, clip, impact frame, optional markers].
const TAKES := {
	"knight": {
		"fitted_pull": ["knight_push", "push", "fitted_pull", 14],
		"clear_the_floor": ["knight_aura", "apply_status", "clear_the_floor", 14],
		"safety_distance": ["knight_rescue_line", "hook", "safety_distance", 13],
		"keep_your_head_down": ["healer_bonk", "bonk", "keep_your_head_down", 13],
		"lend_a_shield": ["knight_shield_throw", "attack", "lend_a_shield", 18],
	},
	"healer": {
		"keep_your_head_down": ["healer_bonk", "bonk", "keep_your_head_down", 13],
		"doctors_orders": ["healer_heal", "heal", "blast", 12],
		"unpick_the_stitch": ["healer_field_dressing", "heal", "bonk", 15],
	},
	"wizard": {
		"ring_of_salve": ["wizard_ring_sparks", "sweep", "ring_sparks", 12],
		"send_off": ["wizard_pull", "pull", "send_off", 13],
		"clear_jump": ["rogue_confusing_dodge", "swap_furthest", "clear_jump", 17, {"takeoff_frame": 8}],
	},
	"bard": {
		"fitted_pull": ["knight_push", "push", "fitted_pull", 14],
		"healing_sonnet_in_tune": ["healing_sonnet", "perform", "healing_sonnet", 25],
		"inspiring_melody_in_tune": ["inspiring_melody", "perform", "inspiring_melody", 13],
		"company_chorus": ["bard_take_the_stage", "perform", "healing_sonnet", 25],
	},
	"necromancer": {
		"recall_skeleton": ["summon_skeleton", "summon", "recall", 17],
		"play_dead": ["raise_dead", "summon", "hush", 11],
		"dinner_bell": ["necro_grave_bell", "repel", "grave_bell", 12],
		"stay_close_to_that_one": ["necromancer_say_hello_to_that_one", "nominate", "stay_close", 15],
		"inspiring_melody_in_tune": ["inspiring_melody", "perform", "melody", 13],
	},
	"rogue": {
		"it_was_me": ["rogue_wasnt_me", "misdirect", "it_was_me", 10, {"claim_frame": 19}],
		"clear_jump": ["rogue_confusing_dodge", "swap_furthest", "clear_jump", 17, {"takeoff_frame": 7}],
		"cut_the_wire": ["rogue_tripwire", "stop_target", "cut_the_wire", 13],
	},
	"alchemist": {
		"send_off": ["wizard_pull", "pull", "send_off", 13],
	},
}
const DOSE_SOURCES := {
	"buffer_solution": ["alchemist_acid", "acid"],
	"bitter_medicine": ["alchemist_potion", "healing_potion"],
	"sealing_paste": ["alchemist_etching_paste", "acid"],
	"plain_solvent": ["alchemist_plain_tonic", "plain_tonic"],
	"counterbatch": ["alchemist_repeat_batch", "repeat_batch"],
}
# Only these fitted deliveries can fill a bottle. Plain Solvent has no
# reaction to store, and Counterbatch always empties the bottle.
const FITTED_BOTTLES := {
	"buffer_solution": ["alchemist_acid", "heal"],
	"bitter_medicine": ["alchemist_potion", "damage"],
	"sealing_paste": ["alchemist_etching_paste", "heal"],
}
const FLIGHT := {"acid": "acid_flask", "lend_a_shield": "lend_a_shield_prop"}
const WITHOUT_SHIELD := ["fitted_pull", "safety_distance", "keep_your_head_down"]


## A true result owns the performer clip even if lookup() returns {}. The
## scheduler must not keep the stock recipe clip for such a replay.
static func replays_fitted_dose(performance: Dictionary) -> bool:
	if performance.get("branch") not in ["ordinary", "fallback"] \
			or performance.get("cast_key") != "alchemist" \
			or performance.get("form_id") != "alchemist_repeat_batch" \
			or not _matches_source(performance, "alchemist_repeat_batch", "repeat_batch"):
		return false
	var actor: Variant = performance.get("actor_id")
	var dose: Variant = performance.get("dose")
	if not actor is String or actor.is_empty() or not dose is Dictionary:
		return false
	var delivery: Variant = dose.get("delivery_form_id")
	return delivery is String and FITTED_BOTTLES.has(delivery) and _valid_dose(dose, delivery, actor)


## Call after collecting the committed performance's primary aim and dose.
## clip_for is the loaded CastSprites.clip_for(wearer, id), or an equivalent
## resolver. Results are fresh dictionaries; {} never requests a fallback.
## Projectile takes use their authored release drawing; the scheduler adds flight to impact.
static func lookup(performance: Dictionary, clip_for: Callable) -> Dictionary:
	if not clip_for.is_valid():
		return {}
	var actor: Variant = performance.get("actor_id")
	if not actor is String or actor.is_empty():
		return {}
	var wearer: Variant = performance.get("cast_key")
	var form: Variant = performance.get("form_id")
	if not wearer is String or not form is String:
		return {}
	var binding: Dictionary
	if replays_fitted_dose(performance):
		binding = _dose_binding(performance.dose, actor, wearer)
	elif performance.get("branch") == "converted":
		binding = _binding(performance, wearer, form, actor)
	else:
		return {}
	if binding.is_empty() or not _has_media(wearer, binding, clip_for):
		return {}
	if wearer == "necromancer":
		_bind_companion(performance, binding, clip_for)
	return binding


static func _binding(performance: Dictionary, wearer: String, form: String, actor: String) -> Dictionary:
	if form == "mending_blast" and wearer in ["wizard", "healer"] \
			and _matches_source(performance, "wizard_blast", "blast"):
		var aim: Variant = performance.get("aim")
		if not aim is Dictionary or not aim.get("id") is String or aim.id.is_empty() \
				or not aim.get("cell") is Vector2i:
			return {}
		if aim.id == actor:
			return {"clip": "self_heal" if wearer == "healer" else "mending_blast_self", "impact_frame": 17}
		return {"clip": "blast", "impact_frame": 17 if wearer == "wizard" else 12}
	if (wearer == "alchemist" and DOSE_SOURCES.has(form)) or (wearer == "rogue" and form == "bitter_medicine"):
		var source: Array = DOSE_SOURCES[form]
		var dose: Variant = performance.get("dose")
		if _matches_source(performance, source[0], source[1]) and _valid_dose(dose, form, actor):
			return _dose_binding(dose, actor, wearer)
		return {}
	var row: Array = TAKES.get(wearer, {}).get(form, [])
	if row.is_empty() or not _matches_source(performance, row[0], row[1]):
		return {}
	var key: String = row[2]
	if wearer == "knight":
		var shield_away: Variant = performance.get("shield_away")
		if not shield_away is bool:
			return {}
		if shield_away:
			if form not in WITHOUT_SHIELD:
				return {}
			key += "_unshielded"
	var binding := {"clip": key, "impact_frame": row[3]}
	return binding.merged(row[4]) if row.size() > 4 else binding


static func _matches_source(performance: Dictionary, ability: String, handler: String) -> bool:
	return performance.get("source_ability_id") == ability and performance.get("source_handler") == handler


static func _valid_dose(dose: Variant, form: String, actor: String) -> bool:
	if not dose is Dictionary or not dose.get("recipient_id") is String \
			or dose.recipient_id.is_empty() or not dose.get("cell") is Vector2i \
			or dose.get("delivery_form_id") != form:
		return false
	var recipe: Variant = dose.get("recipe_id")
	var polarity: Variant = dose.get("polarity")
	if dose.recipient_id == actor and polarity == "damage":
		return false
	if form == "plain_solvent":
		return recipe == "alchemist_plain_tonic" and polarity == "damage"
	if recipe not in ["alchemist_acid", "alchemist_potion", "alchemist_etching_paste"] \
			or polarity not in ["heal", "damage"]:
		return false
	return form == "counterbatch" or FITTED_BOTTLES.get(form, []) == [recipe, polarity]


static func _dose_binding(dose: Dictionary, actor: String, wearer: String) -> Dictionary:
	var self_dose: bool = dose.recipient_id == actor
	match dose.recipe_id:
		"alchemist_acid":
			return _offer() if self_dose else {"clip": "acid", "impact_frame": 18}
		"alchemist_potion":
			if dose.polarity == "heal":
				return _offer()
			return {"clip": "bitter_medicine" if wearer == "rogue" else "hostile_dose", "impact_frame": 13}
		"alchemist_plain_tonic":
			return {"clip": "hostile_dose", "impact_frame": 13}
		"alchemist_etching_paste":
			return {"clip": "etching_paste", "impact_frame": 13}
	return {}


static func _offer() -> Dictionary:
	# The stock offer happens within its F17 drawing, at 48% of 1,583 ms.
	return {"clip": "potion", "impact_frame": 17, "impact_ms": 759.84}


static func _has_media(wearer: String, binding: Dictionary, clip_for: Callable) -> bool:
	var clip: Variant = clip_for.call(wearer, binding.clip)
	if not _has_drawing(clip, binding.impact_frame):
		return false
	for marker in ["takeoff_frame", "claim_frame"]:
		if binding.has(marker) and not _has_drawing(clip, binding[marker]):
			return false
	if FLIGHT.has(binding.clip):
		# Do not play a release without the matching detached prop.
		return clip.release_clip == FLIGHT[binding.clip] and clip.release_ms >= 0.0 \
			and is_equal_approx(clip.release_ms, clip.time_at_source_frame(binding.impact_frame)) \
			and _has_drawing(clip_for.call(wearer, clip.release_clip), binding.impact_frame)
	return true


static func _bind_companion(performance: Dictionary, binding: Dictionary, clip_for: Callable) -> void:
	var effects: Variant = performance.get("effects")
	if not effects is Array:
		return
	var main: Variant = clip_for.call("necromancer", binding.clip)
	for effect: Variant in effects:
		if not effect is Dictionary:
			continue
		if binding.clip == "recall" and effect.get("kind") == "recall" \
				and effect.get("cast_key") == "skeleton" and effect.get("target_id", "") != "":
			var tuck: Variant = clip_for.call("skeleton", "recall_tuck")
			if _has_drawing(tuck, 1) and _has_drawing(tuck, 17):
				binding["companion"] = {"effect_kind": "recall", "clip": "recall_tuck", "start_frame": 17}
			return
		if binding.clip == "hush" and effect.get("kind") == "play_dead" \
				and effect.get("retired_cast_key") == "zombie" and effect.get("retired_id", "") != "":
			var lowering: Variant = clip_for.call("zombie", "play_dead")
			if _has_drawing(main, 6) and _has_drawing(lowering, 1) and _has_drawing(lowering, 26):
				binding["companion"] = {"effect_kind": "play_dead", "clip": "play_dead",
					"start_frame": 6, "handoff_frame": 26}
			return


static func _has_drawing(clip: Variant, frame: int) -> bool:
	if not clip is CastSprites.Clip or clip.path.is_empty():
		return false
	var index: int = clip.source_frames.find(frame)
	if index < 0 or index >= clip.frames.size() \
			or not (FileAccess.file_exists(clip.path) or ResourceLoader.exists(clip.path, "Texture2D")):
		return false
	var texture := CastSprites.load_texture(clip.path)
	var drawing: Rect2 = clip.frames[index]
	return texture != null and drawing.has_area() and Rect2(Vector2.ZERO, texture.get_size()).encloses(drawing)
