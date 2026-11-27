extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/fitted_sound_palette_test.gd
## Optionally set OLR_FITTED_AUDIO_RENDER_DIR to an absolute, ignored review
## directory. The test writes the exact custom runtime streams, not auditions.

const Palette = preload("res://presentation/audio/fitted_sound_palette.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_cast_and_form()
	_test_phases()
	_test_doses()
	_test_pcm()
	if _failures.is_empty():
		print("Fitted palette: native and borrowed routes, resolved variants, and PCM passed.")
		quit()
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_cast_and_form() -> void:
	var push := _move("push", "patient")
	var pull := _move("pull", "patient")
	var cover := {"kind": "status", "status_id": "keep_your_head_down", "target_id": "patient"}
	var heal := {"kind": "heal", "target_id": "patient", "amount": 2}
	var damage := {"kind": "damage", "target_id": "patient", "amount": 2}
	var melody := {"kind": "status", "status_id": "inspired", "target_id": "listener"}
	var rows := [
		["knight", "knight_push", "fitted_pull", [pull], "fitted_knight_pull"],
		["bard", "knight_push", "fitted_pull", [pull], "fitted_bard_pull"], # borrowed
		["knight", "knight_aura", "clear_the_floor", [push, _move("push", "crate")], "fitted_floor_sweep"],
		["knight", "knight_rescue_line", "safety_distance", [push], "fitted_stop_palm"],
		["knight", "knight_shield_throw", "lend_a_shield", [{"kind": "shield_drop"}], "fitted_shield_seat"],
		["healer", "healer_bonk", "keep_your_head_down", [cover], "dressing"],
		["knight", "healer_bonk", "keep_your_head_down", [cover], "fitted_knight_cover"], # borrowed
		["healer", "healer_heal", "doctors_orders", [damage], "fitted_doctor_snap"],
		["wizard", "wizard_blast", "mending_blast", [heal], "fitted_mend_outward"],
		["healer", "wizard_blast", "mending_blast", [heal], "heal"], # borrowed
		["wizard", "wizard_pull", "send_off", [push], "shunt"],
		["alchemist", "wizard_pull", "send_off", [push], "shunt"], # borrowed
		["wizard", "wizard_ring_sparks", "ring_of_salve", [heal], "fitted_salve_ring"],
		["rogue", "rogue_wasnt_me", "it_was_me", [damage], "bonk"],
		["rogue", "rogue_tripwire", "cut_the_wire", [{"kind": "status", "status_id": "steady_hands"},
			{"kind": "status", "removed": true, "status_ids": ["boot_toffee"]}], "fitted_wire_cut"],
		["necromancer", "summon_skeleton", "recall_skeleton", [_move("recall", "same_skeleton")], "fitted_recall"],
		["necromancer", "raise_dead", "play_dead", [{"kind": "play_dead", "retired_id": "zombie"}], "fitted_hush"],
		["necromancer", "necro_grave_bell", "dinner_bell", [pull], "fitted_dinner_bell"],
		["necromancer", "necromancer_say_hello_to_that_one", "stay_close_to_that_one",
			[{"kind": "rally", "target_id": "company"}], "fitted_rally"],
		["bard", "healing_sonnet", "healing_sonnet_in_tune", [heal], "fitted_sonnet"],
		["bard", "inspiring_melody", "inspiring_melody_in_tune", [melody], "melody"],
		["necromancer", "inspiring_melody", "inspiring_melody_in_tune", [melody], "fitted_crypter_melody"], # borrowed
		["bard", "bard_take_the_stage", "company_chorus", [heal, heal], "fitted_chorus"],
	]
	for row: Array in rows:
		var use := _use(row[0], row[1], row[2], row[3])
		_expect_keys(use, [row[4]])
		var routed := Palette.route(use)
		if routed.size() == 1:
			_expect(routed[0].unit_id == "wearer" and routed[0].ability_id == row[1],
				"Use the actual wearer and equipped ability on %s." % row[2])
	var use := _use("wizard", "wizard_blast", "mending_blast", [
		{"kind": "heal", "target_id": "wearer", "amount": 2}, heal])
	use.aim.id = use.actor_id
	_expect_keys(use, ["fitted_mend_inward"])
	use.effects = [{"kind": "heal", "target_id": "wearer", "amount": 0}]
	_expect_keys(use, ["fitted_empty_press"])
	_expect_keys(_use("wizard", "wizard_pull", "send_off", []), ["fitted_empty_press"])
	_expect_keys(_use("healer", "healer_heal", "doctors_orders",
		[{"kind": "damage", "amount": 0}]), ["fitted_doctor_snap"])
	# Custom catalogs may still bind the retained Unpick form.
	_expect_keys(_use("healer", "healer_field_dressing", "unpick_the_stitch",
		[{"kind": "damage", "amount": 0}]), ["fitted_empty_press"])
	_expect_keys(_use("healer", "healer_bonk", "keep_your_head_down", [damage]), [])
	_expect_keys(_use("rogue", "rogue_tripwire", "cut_the_wire", [{"kind": "status", "status_id": "knockdown"}]), [])
	_expect_keys(_use("necromancer", "summon_skeleton", "recall_skeleton", [{"kind": "summon"}]), [])
	var inspired := _use("necromancer", "inspiring_melody", "inspiring_melody_in_tune", [melody])
	_expect(Palette.route(inspired).any(func(event): return event.target_id == "listener"),
		"Melody names the actual Inspired listener, not a stale aim.")
	# No source replacement for an ordinary fallback, stock action or ordinary echo.
	for source: String in ["wizard_blast", "summon_skeleton", "raise_dead", "inspiring_melody", "healing_sonnet"]:
		var ordinary := _use("wearer", source, source, [])
		ordinary.branch = "ordinary"
		_expect(not Palette.handles(ordinary) and Palette.route(ordinary).is_empty(),
			"Ordinary fallback/echo of %s stays on stock path." % source)


func _test_phases() -> void:
	var movement := _move("move", "wearer")
	for wearer: String in ["rogue", "wizard"]: # native and borrowed
		var use := _use(wearer, "rogue_confusing_dodge", "clear_jump", [])
		use["kind"] = "takeoff"
		use["performance_effects"] = [movement]
		_expect_keys(use, ["fitted_jump_cape" if wearer == "rogue" else "fitted_jump_caster"])
		use.kind = "impact"
		_expect_keys(use, [])
		use.kind = "motion_land"
		_expect_keys(use, []) # full facts cannot fabricate a crossed landing
		use.effects = [_move("move", "far_opponent")]
		_expect_keys(use, []) # neither swap nor locator is a landing subject
		use.effects = [movement]
		_expect_keys(use, ["step"])
	var use := _use("rogue", "rogue_wasnt_me", "it_was_me", [])
	use["kind"] = "claim"
	_expect_keys(use, ["fitted_claim"])
	use = _use("necromancer", "raise_dead", "play_dead", [])
	use["kind"] = "impact"
	use["performance_effects"] = [{"kind": "play_dead", "retired_id": "existing_zombie", "target_id": "corpse"}]
	_expect_keys(use, ["fitted_hush"])
	_expect(Palette.route(use).any(func(event): return event.target_id == "existing_zombie"),
		"Play Dead addresses the living role, not the replacement corpse.")
	use.kind = "handoff"
	use.effects = use.performance_effects
	_expect_keys(use, [])


func _test_doses() -> void:
	var jelly := _reaction("jelly_knees", "harmful", "patient", true)
	var splash := _reaction("boot_toffee", "harmful", "neighbor", true)
	var suppressed := _reaction("cork_soles", "beneficial", "patient", false)
	var good := _reaction("cork_soles", "beneficial", "patient", true)
	var bubbles := _reaction("fine_bubbles", "cosmetic", "patient", false)
	# Full HP is still real delivery and can produce a real reaction.
	var use := _dose("alchemist", "alchemist_acid", "buffer_solution", "alchemist_acid", "heal",
		[splash, suppressed, jelly, jelly])
	_expect_keys(use, ["dose", "fitted_reaction_knees"])
	var requests := Palette.route(use)
	if requests.size() == 2:
		_expect(requests[0].unit_id == "wearer" and requests[0].target_id == "patient"
			and requests[1].unit_id == "patient" and requests[1].kind == "reaction"
			and requests[1].reaction_id == "jelly_knees", "Dose and exact reaction have separate owners.")
	use.dose.recipient_id = "wearer"
	use.effects = [_reaction("fine_bubbles", "cosmetic", "wearer", false)]
	_expect_keys(use, ["dose", "fitted_reaction_bubbles"])
	for wearer: String in ["rogue", "alchemist"]: # same retained vial contact, different wearer
		_expect_keys(_dose(wearer, "alchemist_potion", "bitter_medicine", "alchemist_potion", "damage", [good]),
			["fitted_bitter", "fitted_reaction_good"])
	_expect_keys(_dose("alchemist", "alchemist_etching_paste", "sealing_paste", "alchemist_etching_paste",
		"heal", [bubbles]), ["paste", "fitted_reaction_bubbles"])
	_expect_keys(_dose("alchemist", "alchemist_plain_tonic", "plain_solvent", "alchemist_plain_tonic",
		"damage", [jelly]), ["fitted_bitter"])
	for row: Array in [["alchemist_acid", "heal", "dose"], ["alchemist_acid", "damage", "potion"],
		["alchemist_potion", "heal", "dose"], ["alchemist_potion", "damage", "fitted_bitter"],
		["alchemist_etching_paste", "heal", "paste"], ["alchemist_etching_paste", "damage", "paste"]]:
		_expect_keys(_dose("alchemist", "alchemist_repeat_batch", "counterbatch", row[0], row[1], [jelly]),
			[row[2], "fitted_reaction_knees"])
	use = _dose("alchemist", "alchemist_repeat_batch", "alchemist_repeat_batch", "alchemist_acid", "heal", [jelly])
	use.branch = "ordinary"
	use.dose.delivery_form_id = "buffer_solution"
	_expect_keys(use, ["dose", "fitted_reaction_knees"])
	use.branch = "fallback" # no legal Counterbatch target but same stored dose
	_expect_keys(use, ["dose", "fitted_reaction_knees"])
	use.dose.delivery_form_id = "alchemist_acid"
	use.dose.polarity = "damage"
	_expect(not Palette.handles(use), "An ordinary repeat of stock Acid remains on the stock path.")
	use = _dose("alchemist", "alchemist_acid", "alchemist_acid", "alchemist_acid", "damage", [jelly])
	use.branch = "ordinary"
	_expect(not Palette.handles(use), "Ordinary nonrepeat doses remain on the stock path.")


func _test_pcm() -> void:
	var render_dir := OS.get_environment("OLR_FITTED_AUDIO_RENDER_DIR")
	if not render_dir.is_empty():
		_expect(render_dir.is_absolute_path(), "Render directory must be absolute.")
		_expect(DirAccess.make_dir_recursive_absolute(render_dir) == OK, "Cannot create exact-render directory.")
	var digests := {}
	for key: String in Palette.LAYERS.keys() + Palette.PHRASES.keys():
		var stream: AudioStreamWAV = Palette.get_stream(key)
		_expect(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo
			and stream.mix_rate == 22050, "%s must produce mono 22.05 kHz PCM16." % key)
		if stream == null:
			continue
		var count := stream.data.size() >> 1
		_expect(count >= 1764 and count <= 11467, "%s has an unsuitable board cue duration." % key)
		var peak := 0
		for index in count:
			peak = maxi(peak, absi(stream.data.decode_s16(2 * index)))
		_expect(peak > 650 and peak < 19000, "%s is inaudibly weak or has too much level (%d)." % [key, peak])
		_expect(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(2 * (count - 1)) == 0,
			"%s must not start or end with a discontinuity." % key)
		var hash := _digest(stream.data)
		_expect(not digests.has(hash), "%s duplicated a waveform: %s." % [key, digests.get(hash, "")])
		digests[hash] = key
		if not render_dir.is_empty() and render_dir.is_absolute_path():
			_expect(stream.save_to_wav(render_dir.path_join(key + ".wav")) == OK, "Cannot render %s." % key)
		var before := stream.data
		Palette._streams.erase(key)
		_expect(before == Palette.get_stream(key).data, "%s changed on a fresh synthesis." % key)
	_expect(Palette.get_stream("heal") == null, "Stock cues must stay the service's responsibility.")
	var sonnet := Palette.get_stream("fitted_sonnet").data
	var chorus := Palette.get_stream("fitted_chorus").data
	_expect(_band(sonnet, .152, .24, 554.37) > 3.0 * _band(sonnet, .152, .24, 523.25),
		"The restored A motif needs a major, not minor, third.")
	_expect(_band(chorus, .411, .497, 880.0) > 3.0 * _band(chorus, .411, .497, 659.25),
		"The Chorus must extend the Sonnet with a distinct high A.")


func _band(data: PackedByteArray, begin: float, end: float, hz: float) -> float:
	var component := Vector2.ZERO
	for i in range(int(begin * 22050), int(end * 22050)):
		var angle := TAU * hz * i / 22050
		component += Vector2(cos(angle), sin(angle)) * data.decode_s16(i * 2)
	return component.length()


func _digest(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _use(wearer: String, source: String, form: String, effects: Array) -> Dictionary:
	return {"actor_id": "wearer", "cast_key": wearer, "source_ability_id": source, "form_id": form,
		"branch": "converted", "effects": effects, "aim": {"id": "patient"}}


func _move(kind: String, target: String) -> Dictionary:
	return {"kind": kind, "target_id": target, "from": Vector2i(1, 2), "to": Vector2i(2, 2)}


func _dose(wearer: String, source: String, form: String, recipe: String, polarity: String,
		effects: Array) -> Dictionary:
	var use := _use(wearer, source, form, effects)
	use["dose"] = {"recipe_id": recipe, "delivery_form_id": form, "polarity": polarity,
		"recipient_id": "patient"}
	return use


func _reaction(id: String, category: String, target: String, applied: bool) -> Dictionary:
	return {"kind": "alchemy_reaction", "source_id": "wearer", "target_id": target,
		"reaction_id": id, "category": category, "applied": applied}


func _expect_keys(use: Dictionary, keys: Array) -> void:
	var actual := Palette.route(use).map(func(request): return request.cue_id)
	_expect(actual == keys, "%s/%s at %s: expected %s, got %s."
		% [use.cast_key, use.form_id, use.get("kind", "impact"), keys, actual])


func _expect(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
