extends RefCounted
## Committed sound gestures for Try This. This consumes presentation facts,
## never orders, forecast descriptions, or the current state of the board.
## Authored in-project from the fitted choreography handoffs (remaining-fitted,
## knight-fitted-candidate, wizard/fitted-candidate, rogue-try-this and
## crypter-try-this). No audition audio or third-party material is embedded.

const RATE := 22050

# Editable original dry foley. Layer columns: voice, onset s, length s, Hz
# start/end, amplitude, attack s, decay /s. For "air" the Hz pair is low-pass
# cutoff; "edge" removes the low end of the same seeded noise.
const LAYERS := {
	# The Knight hauls against mail; the Bard draws a lighter bow arm inward.
	"fitted_knight_pull": [["air", 0.00, 0.18, 620, 260, .24, .036, 7], ["mode", .018, .18, 360, 155, .15, .025, 12], ["edge", .058, .054, 1650, 860, .075, .005, 22]],
	"fitted_bard_pull": [["air", 0.00, .20, 1750, 510, .19, .036, 9], ["mode", .014, .17, 530, 230, .095, .039, 10]],
	"fitted_floor_sweep": [["air", 0.00, .17, 460, 1700, .27, .035, 7], ["mode", .02, .16, 310, 112, .17, .016, 12], ["edge", .039, .10, 1320, 800, .087, .008, 13]],
	"fitted_stop_palm": [["air", 0.00, .14, 620, 1380, .19, .016, 15], ["mode", .013, .11, 225, 142, .12, .007, 22]],
	"fitted_empty_press": [["air", 0.00, .105, 850, 540, .16, .014, 19]],
	"fitted_shield_seat": [["air", 0.00, .13, 440, 780, .14, .022, 10], ["mode", .036, .14, 368, 341, .16, .004, 19], ["mode", .041, .20, 1120, 1068, .073, .006, 18], ["edge", .039, .037, 2100, 1100, .082, .003, 46]],
	"fitted_knight_cover": [["air", 0.00, .10, 380, 730, .18, .01, 17], ["mode", .04, .091, 420, 345, .12, .005, 26], ["mode", .046, .11, 1190, 1110, .056, .002, 34]],
	"fitted_doctor_snap": [["edge", 0.00, .10, 4200, 540, .20, .007, 27], ["air", .006, .13, 1550, 480, .32, .004, 21], ["mode", .013, .11, 310, 145, .11, .008, 21]],
	"fitted_mend_outward": [["air", 0.00, .13, 650, 1700, .18, .019, 14], ["mode", .018, .22, 481, 659, .12, .023, 7], ["mode", .081, .20, 987, 989, .11, .014, 11], ["mode", .126, .16, 1319, 1319, .068, .012, 12]],
	"fitted_mend_inward": [["air", 0.00, .14, 650, 310, .20, .021, 14], ["mode", .015, .24, 659, 659, .13, .024, 7], ["mode", .057, .22, 784, 660, .085, .016, 10], ["mode", .099, .19, 990, 990, .10, .022, 9]],
	"fitted_salve_ring": [["air", 0.00, .22, 550, 1420, .15, .027, 6], ["mode", .012, .22, 587, 591, .11, .025, 8], ["mode", .05, .24, 740, 740, .10, .026, 7], ["mode", .104, .23, 880, 880, .092, .024, 9]],
	# Not the alibi voice. A light vest tap and keys after the claimant's bonk.
	"fitted_claim": [["air", 0.00, .09, 660, 420, .19, .006, 20], ["mode", .018, .093, 230, 153, .12, .004, 24], ["mode", .041, .099, 2130, 2190, .067, .003, 31], ["mode", .068, .111, 2820, 2660, .059, .003, 32]],
	"fitted_jump_cape": [["air", 0.00, .28, 420, 1610, .25, .035, 5], ["edge", .035, .18, 1100, 670, .11, .031, 7]],
	"fitted_jump_caster": [["air", 0.00, .25, 680, 1260, .20, .026, 7], ["mode", .028, .23, 238, 413, .102, .032, 7], ["mode", .099, .13, 673, 739, .064, .021, 12]],
	"fitted_wire_cut": [["edge", 0.00, .052, 3000, 1150, .20, .002, 36], ["mode", .006, .049, 1780, 1620, .16, .002, 40], ["mode", .028, .193, 770, 350, .21, .006, 14], ["mode", .03, .12, 1710, 895, .075, .004, 22]],
	# Recall has two dull bone seats, not the ascending fresh-summon ring.
	"fitted_recall": [["air", 0.00, .11, 1200, 370, .18, .017, 13], ["mode", .045, .082, 524, 452, .15, .003, 33], ["edge", .044, .036, 2380, 1170, .13, .002, 42], ["mode", .092, .12, 365, 312, .18, .004, 27], ["mode", .094, .079, 930, 700, .085, .002, 30]],
	"fitted_hush": [["air", 0.00, .22, 1780, 470, .22, .031, 8], ["edge", .029, .14, 1180, 560, .085, .027, 11]],
	"fitted_rally": [["air", 0.00, .17, 560, 930, .20, .02, 11], ["mode", .049, .13, 422, 391, .09, .012, 16]],
	# Held vial: tick then wet pat. No projectile hiss or glass shatter.
	"fitted_bitter": [["mode", 0.00, .083, 1940, 1870, .18, .002, 39], ["mode", .004, .081, 3120, 2960, .069, .002, 43], ["air", .022, .105, 460, 1190, .27, .004, 24], ["mode", .026, .11, 510, 230, .14, .006, 23]],
	# Delayed, low-weight recipient accents. The dose can help and its
	# reaction still be harmful. The core recipe never includes this tail.
	"fitted_reaction_good": [["mode", .084, .099, 622, 691, .14, .006, 21], ["mode", .135, .133, 934, 988, .13, .007, 17]],
	"fitted_reaction_bad": [["mode", .084, .15, 346, 202, .17, .012, 13], ["mode", .11, .12, 487, 280, .12, .014, 17]],
	"fitted_reaction_knees": [["air", .084, .113, 1180, 350, .19, .012, 12], ["mode", .091, .17, 420, 161, .20, .015, 14], ["mode", .143, .095, 230, 116, .12, .006, 19]],
	"fitted_reaction_cosmetic": [["mode", .09, .062, 870, 1100, .13, .008, 23], ["mode", .143, .072, 1220, 1390, .105, .005, 29]],
	"fitted_reaction_bubbles": [["mode", .084, .049, 815, 1120, .14, .004, 32], ["mode", .123, .061, 690, 979, .14, .005, 35], ["mode", .176, .095, 1140, 1580, .12, .003, 37]],
}

# One bell strike vs. a brief articulated phrase on the actual Crypter's
# instrument. Sonnet and Chorus retain the stock A motif, major third/fifth
# and stock high A ending, but use damped bow harmonics instead of bare sine.
const PHRASES := {
	"fitted_dinner_bell": {"bell": true, "notes": [587.33], "interval": .31},
	"fitted_crypter_melody": {"bell": true, "notes": [523.25, 659.25, 783.99], "interval": .13},
	"fitted_sonnet": {"bell": false, "notes": [440.0, 554.37, 659.25], "interval": .13},
	"fitted_chorus": {"bell": false, "notes": [440.0, 554.37, 659.25, 880.0], "interval": .13},
}
const DOSE_FORMS := ["buffer_solution", "bitter_medicine", "sealing_paste", "plain_solvent", "counterbatch"]
const REACTION_KEYS := {"beneficial": "fitted_reaction_good", "harmful": "fitted_reaction_bad",
	"cosmetic": "fitted_reaction_cosmetic"}

static var _streams := {}


## Can replace ordinary dispatch, including an ordinary Repeat that replays a
## fitted batch. Leave ordinary stock recipes, fallback actions and echoes alone.
static func handles(use: Dictionary) -> bool:
	var branch: String = use.get("branch", "")
	if branch == "converted":
		return true
	var dose: Dictionary = use.get("dose", {})
	var recipe: String = dose.get("recipe_id", "")
	return branch in ["ordinary", "fallback"] and use.get("form_id") == "alchemist_repeat_batch" \
		and not recipe.is_empty() \
		and dose.get("delivery_form_id", recipe) != recipe


## Each request names the emitting unit, cue, mix gain and resolved recipient.
## The playback scheduler owns timing. Only impact/takeoff use the full facts;
## the signature footfall must be supported by an actual crossed landing.
static func route(use: Dictionary) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	if not handles(use) or String(use.get("actor_id", "")).is_empty():
		return requests
	var kind: String = use.get("kind", "impact")
	var form: String = use.get("form_id", "")
	var wearer: String = use.get("cast_key", "")
	var crossed: Array = use.get("effects", [])
	var facts: Array = use.get("performance_effects", crossed)
	if kind == "motion_land" and form == "clear_jump":
		var jump := _first(crossed, "move")
		if jump.get("target_id") == use.actor_id and _changed_cell(jump):
			requests.append(_request(use, "step", use.actor_id, 0.45 / 0.7))
		return requests
	if kind == "takeoff" and form == "clear_jump":
		var jump := _first(facts, "move")
		if jump.get("target_id") == use.actor_id and _changed_cell(jump):
			var sound := "fitted_jump_caster" if wearer == "wizard" else "fitted_jump_cape"
			requests.append(_request(use, sound, use.actor_id, .86))
		return requests
	if kind == "claim" and form == "it_was_me":
		requests.append(_request(use, "fitted_claim", use.actor_id, .77))
		return requests
	if kind != "impact":
		return requests
	if form in DOSE_FORMS or form == "alchemist_repeat_batch":
		return _dose_requests(use, facts)
	var key: String = _gesture(use, facts)
	if not key.is_empty():
		var target: String = use.get("aim", {}).get("id", "")
		var subject := _subject(form, facts)
		if not subject.is_empty():
			target = subject
		requests.append(_request(use, key, target))
	return requests


static func _gesture(use: Dictionary, facts: Array) -> String:
	match use.form_id:
		"fitted_pull":
			if not _changed_cell(_first(facts, "pull")):
				return "fitted_empty_press"
			return "fitted_bard_pull" if use.get("cast_key") == "bard" else "fitted_knight_pull"
		"clear_the_floor":
			return "fitted_floor_sweep" if _changed_cell(_first(facts, "push")) else "fitted_empty_press"
		"safety_distance":
			return "fitted_stop_palm" if _changed_cell(_first(facts, "push")) else "fitted_empty_press"
		"send_off":
			return "shunt" if _changed_cell(_first(facts, "push")) else "fitted_empty_press"
		"lend_a_shield":
			return "fitted_shield_seat" if not _first(facts, "shield_drop").is_empty() else ""
		"keep_your_head_down":
			if _first(facts, "status", "keep_your_head_down").is_empty():
				return ""
			return "fitted_knight_cover" if use.get("cast_key") == "knight" else "dressing"
		"doctors_orders":
			# The palm snaps even if protection absorbs the damage; the sound
			# does not portray wounded flesh, a staff strike, or healing.
			return "fitted_doctor_snap"
		"it_was_me", "unpick_the_stitch":
			return "bonk" if not _first(facts, "damage").is_empty() else "fitted_empty_press"
		"mending_blast":
			var healed := _first(facts, "heal")
			if healed.is_empty():
				return "fitted_empty_press"
			if use.get("cast_key") == "healer":
				return "heal"
			var primary: String = use.get("aim", {}).get("id", healed.get("target_id", ""))
			return "fitted_mend_inward" if primary == use.actor_id else "fitted_mend_outward"
		"ring_of_salve":
			return "fitted_salve_ring" if not _first(facts, "heal").is_empty() else "fitted_empty_press"
		"cut_the_wire":
			for fact: Dictionary in facts:
				if fact.get("kind") == "status" and fact.get("removed", false) \
						and not fact.get("status_ids", []).is_empty():
					return "fitted_wire_cut"
			return ""
		"recall_skeleton":
			return "fitted_recall" if not _first(facts, "recall").is_empty() else ""
		"play_dead":
			return "fitted_hush" if not _first(facts, "play_dead").is_empty() else ""
		"dinner_bell":
			# One performed chime; no second movement accent if resisted.
			return "fitted_dinner_bell"
		"stay_close_to_that_one":
			return "fitted_rally" if not _first(facts, "rally").is_empty() else ""
		"inspiring_melody_in_tune":
			return "fitted_crypter_melody" if use.get("cast_key") == "necromancer" else "melody"
		"healing_sonnet_in_tune":
			return "fitted_sonnet"
		"company_chorus":
			return "fitted_chorus"
	return ""


static func _dose_requests(use: Dictionary, facts: Array) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var dose: Dictionary = use.get("dose", {})
	var target: String = dose.get("recipient_id", "")
	var polarity: String = dose.get("polarity", "")
	if target.is_empty() or polarity not in ["heal", "damage"]:
		return requests
	var key := ""
	match dose.get("recipe_id"):
		"alchemist_acid":
			key = "dose" if polarity == "heal" else "potion"
		"alchemist_etching_paste":
			key = "paste"
		"alchemist_potion", "alchemist_plain_tonic":
			key = "dose" if polarity == "heal" else "fitted_bitter"
	if key.is_empty():
		return requests
	requests.append(_request(use, key, target))
	# Plain Solvent has no reaction. Apply a single accent only for the
	# primary recipient's actual event; splash and suppressed reactions are silent.
	if dose.recipe_id == "alchemist_plain_tonic":
		return requests
	for effect: Dictionary in facts:
		if effect.get("kind") != "alchemy_reaction" or effect.get("target_id") != target \
				or effect.get("source_id") != use.actor_id:
			continue
		var id: String = effect.get("reaction_id", "")
		var category: String = effect.get("category", "")
		var reaction: String = REACTION_KEYS.get(category, "")
		# The resolver deliberately marks cosmetic events as not applied:
		# they never install a gameplay status.
		if reaction.is_empty() or id.is_empty() \
				or (category != "cosmetic" and not effect.get("applied", false)):
			continue
		if id == "jelly_knees" and category == "harmful":
			reaction = "fitted_reaction_knees"
		elif id == "fine_bubbles" and category == "cosmetic":
			reaction = "fitted_reaction_bubbles"
		var request := _request(use, reaction, target, .57)
		request.merge({"kind": "reaction", "unit_id": target, "reaction_id": id, "category": category}, true)
		requests.append(request)
		break
	return requests


static func _subject(form: String, facts: Array) -> String:
	match form:
		"fitted_pull", "dinner_bell":
			return _first(facts, "pull").get("target_id", "")
		"safety_distance", "send_off":
			return _first(facts, "push").get("target_id", "")
		"lend_a_shield":
			return _first(facts, "status", "lend_a_shield").get("target_id", "")
		"doctors_orders", "it_was_me", "unpick_the_stitch":
			return _first(facts, "damage").get("target_id", "")
		"mending_blast", "ring_of_salve":
			return _first(facts, "heal").get("target_id", "")
		"play_dead":
			return _first(facts, "play_dead").get("retired_id", "")
		"recall_skeleton":
			return _first(facts, "recall").get("target_id", "")
		"inspiring_melody_in_tune":
			return _first(facts, "status", "inspired").get("target_id", "")
		"stay_close_to_that_one":
			return _first(facts, "rally").get("target_id", "")
	return ""


static func _request(use: Dictionary, key: String, target: String, gain := 1.0) -> Dictionary:
	return {"kind": use.get("kind", "impact"), "unit_id": use.actor_id,
		"ability_id": use.get("source_ability_id", use.form_id), "cue_id": key,
		"gain": gain, "target_id": target}


static func _first(facts: Array, kind: String, status := "") -> Dictionary:
	for fact: Dictionary in facts:
		if fact.get("kind") == kind and (status.is_empty() or fact.get("status_id") == status):
			if kind in ["heal", "damage"] and int(fact.get("amount", 1)) <= 0:
				continue
			return fact
	return {}


static func _changed_cell(fact: Dictionary) -> bool:
	return fact.get("to") is Vector2i and fact.get("from") is Vector2i and fact.to != fact.from


## Null means this is a stock cue; the service retains its existing lookup.
static func get_stream(key: String) -> AudioStreamWAV:
	if _streams.has(key):
		return _streams[key]
	var layers: Array = LAYERS.get(key, [])
	if PHRASES.has(key):
		layers = _phrase(PHRASES[key])
	if layers.is_empty():
		return null
	var duration := 0.0
	for layer: Array in layers:
		duration = maxf(duration, float(layer[1]) + float(layer[2]))
	var mix := PackedFloat32Array()
	mix.resize(ceili(duration * RATE))
	for index in layers.size():
		_render_layer(mix, layers[index], 112087 + 7919 * index)
	var bytes := PackedByteArray()
	bytes.resize(mix.size() * 2)
	for i in mix.size():
		bytes.encode_s16(i * 2, roundi(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	_streams[key] = stream
	return stream


static func _phrase(phrase: Dictionary) -> Array:
	var layers: Array = []
	var interval: float = phrase.interval
	for i in phrase.notes.size():
		var hz: float = phrase.notes[i]
		var start: float = i * interval
		if phrase.bell:
			layers.append(["mode", start, interval, hz, hz, .19, .004, 14])
			layers.append(["mode", start, interval, hz * 2.38, hz * 2.38, .11, .002, 24])
			layers.append(["mode", start, interval * .8, hz * 3.73, hz * 3.73, .059, .002, 29])
		else:
			layers.append(["mode", start, interval, hz * .985, hz, .21, .016, 8])
			layers.append(["mode", start, interval, hz * 1.97, hz * 2, .065, .011, 15])
			layers.append(["mode", start, interval * .87, hz * 2.98, hz * 3, .038, .009, 19])
			layers.append(["edge", start, interval * .55, 1860, 1080, .045, .006, 29])
	return layers


static func _render_layer(mix: PackedFloat32Array, layer: Array, seed: int) -> void:
	var start := roundi(float(layer[1]) * RATE)
	var count := mini(roundi(float(layer[2]) * RATE), mix.size() - start)
	var phase := 0.0
	var filtered := 0.0
	for i in count:
		var t := float(i) / RATE
		var u := float(i) / maxi(count - 1, 1)
		var hz := lerpf(layer[3], layer[4], u)
		var envelope := minf(1.0, t / float(layer[6])) * exp(-t * float(layer[7])) \
			* minf(1.0, (1.0 - u) * 10.0)
		var value: float
		if layer[0] == "mode":
			phase += TAU * hz / RATE
			value = sin(phase)
		else:
			seed = (1664525 * seed + 1013904223) & 0xffffffff
			var noise := float(seed) / 2147483648.0 - 1.0
			filtered += (1.0 - exp(-TAU * hz / RATE)) * (noise - filtered)
			value = filtered if layer[0] == "air" else noise - filtered
		mix[start + i] += value * float(layer[5]) * envelope
