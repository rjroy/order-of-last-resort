extends SceneTree
## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/fitted_cast_bindings_test.gd

const Bindings = preload("res://presentation/cast/fitted_cast_bindings.gd")
const CastSprites = preload("res://presentation/cast/cast_sprites.gd")

const ACTOR := "wearer_instance"
const OTHER := "picked_recipient"
const OFFER := {"clip": "potion", "impact_frame": 17, "impact_ms": 759.84}
const TOSS := {"clip": "acid", "impact_frame": 18}
const PASTE := {"clip": "etching_paste", "impact_frame": 13}
const HOSTILE := {"clip": "hostile_dose", "impact_frame": 13}

var _art := CastSprites.new()
var _failures: Array[String] = []
var _proof := {}
var _checks := 0


func _initialize() -> void:
	_art.load_manifest()
	_mount_declared_cast()
	_stock_wearers()
	_approved_takes()
	_mending_primary()
	_undead_companions()
	_dose_delivery()
	_replayed_fitted_bottles()
	_exclusions()
	_missing_media()
	for failure in _failures:
		push_error(failure)
	if _failures.is_empty():
		var keys := _proof.keys()
		keys.sort()
		for key in keys:
			print(_proof[key])
		print("PASS: fitted wearer cast bindings (%d lookups, %d distinct mounted bindings)" % [_checks, keys.size()])
	quit(0 if _failures.is_empty() else 1)


func _expect(performance: Dictionary, expected: Dictionary, message: String, resolver := Callable()) -> void:
	_checks += 1
	var actual := Bindings.lookup(performance, resolver if resolver.is_valid() else _art.clip_for)
	if actual != expected:
		_failures.append("%s: got %s, expected %s" % [message, actual, expected])
	elif not actual.is_empty() and not resolver.is_valid():
		_record_mounted_binding(performance.cast_key, actual)


func _mount_declared_cast() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(CastSprites.MANIFEST))
	if not manifest is Dictionary or not manifest.get("actors") is Dictionary or manifest.actors.is_empty():
		_failures.append("runtime cast manifest must declare mounted actors")
		return
	var paths := {}
	var mounted_clips := 0
	var mounted_frames := 0
	var missing := 0
	var declared := 0
	for role: String in manifest.actors:
		for key: String in manifest.actors[role].clips:
			declared += 1
			var clip := _art.clip_for(role, key)
			if clip == null:
				missing += 1
				_failures.append("declared clip did not mount: %s/%s" % [role, key])
				continue
			var texture := CastSprites.load_texture(clip.path)
			if texture == null:
				missing += 1
				_failures.append("declared clip texture did not load: %s/%s at %s" % [role, key, clip.path])
				continue
			paths[clip.path] = true
			mounted_clips += 1
			var bounds := Rect2(Vector2.ZERO, texture.get_size())
			for index in clip.frames.size():
				if not clip.frames[index].has_area() or not bounds.encloses(clip.frames[index]):
					_failures.append("declared frame outside texture: %s/%s F%d at %s" \
						% [role, key, clip.source_frames[index], clip.path])
				else:
					mounted_frames += 1
	print("Whole cast: %d declared actors, %d atlas paths, %d/%d clips mounted, %d frames in bounds, %d missing clips" \
		% [manifest.actors.size(), paths.size(), mounted_clips, declared, mounted_frames, missing])


func _record_mounted_binding(wearer: String, binding: Dictionary) -> void:
	var clip := _art.clip_for(wearer, binding.clip)
	var label := "%s/%s F%d" % [wearer, binding.clip, binding.impact_frame]
	var line := "%s @ %s [%.2f ms]" \
		% [label, clip.path, binding.get("impact_ms", clip.time_at_source_frame(binding.impact_frame))]
	for marker in ["takeoff_frame", "claim_frame"]:
		if binding.has(marker):
			line += "; %s=F%d" % [marker, binding[marker]]
	if not clip.release_clip.is_empty():
		var prop := _art.clip_for(wearer, clip.release_clip)
		line += "; release %.2f ms -> %s/%s F%d @ %s" \
			% [clip.release_ms, wearer, clip.release_clip, binding.impact_frame, prop.path]
	if binding.has("companion"):
		var spec: Dictionary = binding.companion
		var role := "skeleton" if spec.effect_kind == "recall" else "zombie"
		var companion := _art.clip_for(role, spec.clip)
		label += " + " + spec.clip
		line += "; performer F%d -> %s/%s F1–F%d @ %s" \
			% [spec.start_frame, role, spec.clip, companion.source_frames.back(), companion.path]
	_proof[label] = line


func _use(wearer: String, form: String, source: String, handler: String) -> Dictionary:
	return {"cast_key": wearer, "form_id": form, "source_ability_id": source, "source_handler": handler,
		"branch": "converted", "actor_id": ACTOR, "source_cell": Vector2i(2, 2)}


func _stock_wearers() -> void:
	# Expectations are independent of the binding table and use the shipped atlas.
	var rows := [
		["healer", "doctors_orders", "healer_heal", "heal", "blast", 12],
		["wizard", "ring_of_salve", "wizard_ring_sparks", "sweep", "ring_sparks", 12],
		["bard", "healing_sonnet_in_tune", "healing_sonnet", "perform", "healing_sonnet", 25],
		["bard", "inspiring_melody_in_tune", "inspiring_melody", "perform", "inspiring_melody", 13],
		["bard", "company_chorus", "bard_take_the_stage", "perform", "healing_sonnet", 25],
		["necromancer", "dinner_bell", "necro_grave_bell", "repel", "grave_bell", 12],
		["necromancer", "inspiring_melody_in_tune", "inspiring_melody", "perform", "melody", 13],
	]
	for row in rows:
		var performance := _use(row[0], row[1], row[2], row[3])
		var expected := {"clip": row[4], "impact_frame": row[5]}
		_expect(performance, expected, "%s uses its own %s" % [row[0], row[4]])
		var first := Bindings.lookup(performance, _art.clip_for)
		first["clip"] = "bad caller mutation"
		_expect(performance, expected, "each lookup returns a fresh result")


func _approved_takes() -> void:
	var approved := [
		["knight", "fitted_pull", "knight_push", "push", "fitted_pull", 14],
		["knight", "clear_the_floor", "knight_aura", "apply_status", "clear_the_floor", 14],
		["knight", "safety_distance", "knight_rescue_line", "hook", "safety_distance", 13],
		["knight", "lend_a_shield", "knight_shield_throw", "attack", "lend_a_shield", 18],
		["knight", "keep_your_head_down", "healer_bonk", "bonk", "keep_your_head_down", 13],
		["healer", "keep_your_head_down", "healer_bonk", "bonk", "keep_your_head_down", 13],
		["bard", "fitted_pull", "knight_push", "push", "fitted_pull", 14],
		["wizard", "send_off", "wizard_pull", "pull", "send_off", 13],
		["wizard", "clear_jump", "rogue_confusing_dodge", "swap_furthest", "clear_jump", 17, {"takeoff_frame": 8}],
		["rogue", "clear_jump", "rogue_confusing_dodge", "swap_furthest", "clear_jump", 17, {"takeoff_frame": 7}],
		["rogue", "it_was_me", "rogue_wasnt_me", "misdirect", "it_was_me", 10, {"claim_frame": 19}],
		["rogue", "cut_the_wire", "rogue_tripwire", "stop_target", "cut_the_wire", 13],
		["necromancer", "recall_skeleton", "summon_skeleton", "summon", "recall", 17],
		["necromancer", "play_dead", "raise_dead", "summon", "hush", 11],
		["necromancer", "stay_close_to_that_one", "necromancer_say_hello_to_that_one", "nominate", "stay_close", 15],
		["alchemist", "send_off", "wizard_pull", "pull", "send_off", 13],
	]
	for row in approved:
		var performance := _use(row[0], row[1], row[2], row[3])
		var expected := {"clip": row[4], "impact_frame": row[5]}
		if row.size() > 6:
			expected.merge(row[6])
		var label := "%s/%s" % [row[0], row[1]]
		if row[0] == "knight":
			_expect(performance, {}, "%s must know action-time shield state" % label)
			performance["shield_away"] = false
		_expect(performance, expected, "%s binds its approved media" % label)
		if row[0] == "knight":
			performance["shield_away"] = true
			if row[1] in ["clear_the_floor", "lend_a_shield"]:
				_expect(performance, {}, "%s requires a shield in hand" % label)
			else:
				expected.clip += "_unshielded"
				_expect(performance, expected, "%s cannot draw a phantom shield" % label)


func _mending_primary() -> void:
	for wearer in ["wizard", "healer"]:
		var performance := _use(wearer, "mending_blast", "wizard_blast", "blast")
		_expect(performance, {}, "%s cannot guess whether the patient is self" % wearer)
		performance["aim"] = {"id": OTHER, "cell": Vector2i(2, 3)}
		_expect(performance, {"clip": "blast", "impact_frame": 17 if wearer == "wizard" else 12},
			"%s uses its own outward cast and key" % wearer)
		performance["aim"] = {"id": ACTOR, "cell": Vector2i(2, 2)}
		performance["effects"] = [{"kind": "heal", "target_id": OTHER, "amount": 2}]
		_expect(performance, {"clip": "self_heal" if wearer == "healer" else "mending_blast_self", "impact_frame": 17},
			"%s follows the primary self patient, not the secondary effect" % wearer)
		performance["aim"] = {"id": ACTOR}
		_expect(performance, {}, "%s rejects an incomplete committed primary aim" % wearer)


func _undead_companions() -> void:
	var recall := _use("necromancer", "recall_skeleton", "summon_skeleton", "summon")
	recall["effects"] = [{"kind": "recall", "cast_key": "skeleton", "target_id": OTHER}]
	var recall_actor := {"clip": "recall", "impact_frame": 17}
	_expect(recall, recall_actor.merged({
		"companion": {"effect_kind": "recall", "clip": "recall_tuck", "start_frame": 17},
	}), "Recall tucks the same Skeleton after the cut")
	_expect(recall, recall_actor, "Recall still plays when the actual tuck is unavailable",
		func(wearer, key): return null if wearer == "skeleton" else _art.clip_for(wearer, key))
	var hush := _use("necromancer", "play_dead", "raise_dead", "summon")
	hush["effects"] = [{"kind": "play_dead", "retired_cast_key": "zombie", "retired_id": OTHER}]
	var hush_actor := {"clip": "hush", "impact_frame": 11}
	_expect(hush, hush_actor.merged({"companion": {"effect_kind": "play_dead", "clip": "play_dead",
		"start_frame": 6, "handoff_frame": 26}}), "Play Dead waits for the Zombie's terminal pose")
	_expect(hush, hush_actor, "missing Zombie sheet cannot advertise a corpse handoff marker",
		func(wearer, key): return null if wearer == "zombie" else _art.clip_for(wearer, key))
	hush.effects[0]["retired_cast_key"] = "goblin"
	_expect(hush, hush_actor, "corpse's cast never substitutes for the Zombie")


func _dose(performance: Dictionary, recipe: String, polarity: String, recipient: String) -> Dictionary:
	var result := performance.duplicate(true)
	result["dose"] = {"recipe_id": recipe, "polarity": polarity, "recipient_id": recipient,
		"delivery_form_id": result.form_id, "cell": Vector2i(2, 2) if recipient == ACTOR else Vector2i(3, 2)}
	return result


func _dose_delivery() -> void:
	var buffer := _use("alchemist", "buffer_solution", "alchemist_acid", "acid")
	var seal := _use("alchemist", "sealing_paste", "alchemist_etching_paste", "acid")
	var repeat := _use("alchemist", "counterbatch", "alchemist_repeat_batch", "repeat_batch")
	var bitter := _use("alchemist", "bitter_medicine", "alchemist_potion", "healing_potion")
	var rogue_bitter := _use("rogue", "bitter_medicine", "alchemist_potion", "healing_potion")
	var solvent := _use("alchemist", "plain_solvent", "alchemist_plain_tonic", "plain_tonic")
	var cases := [
		[buffer, "alchemist_acid", "heal", OTHER, TOSS, "outward Buffer stays ranged"],
		[buffer, "alchemist_acid", "heal", ACTOR, OFFER, "self Buffer does not fly back"],
		[buffer, "alchemist_acid", "damage", OTHER, {}, "Buffer never accepts damaging polarity"],
		[buffer, "alchemist_potion", "heal", OTHER, {}, "Buffer cannot receive another recipe"],
		[seal, "alchemist_etching_paste", "heal", OTHER, PASTE, "close Sealing Paste"],
		[seal, "alchemist_etching_paste", "heal", ACTOR, PASTE, "self Sealing Paste"],
		[seal, "alchemist_etching_paste", "damage", OTHER, {}, "Sealing Paste cannot deal damage"],
		[seal, "alchemist_acid", "heal", OTHER, {}, "Sealing Paste is not thrown Acid"],
		[repeat, "alchemist_acid", "heal", OTHER, TOSS, "Counterbatch can heal at Acid range"],
		[repeat, "alchemist_acid", "damage", OTHER, TOSS, "Counterbatch can damage at Acid range"],
		[repeat, "alchemist_acid", "heal", ACTOR, OFFER, "Counterbatch self Acid uses offer"],
		[repeat, "alchemist_acid", "damage", ACTOR, {}, "Counterbatch cannot damage self"],
		[repeat, "alchemist_potion", "heal", OTHER, OFFER, "Counterbatch healing potion offer"],
		[repeat, "alchemist_potion", "heal", ACTOR, OFFER, "Counterbatch self potion offer"],
		[repeat, "alchemist_potion", "damage", OTHER, HOSTILE, "Counterbatch damaging potion uses the hostile tip"],
		[repeat, "alchemist_etching_paste", "heal", ACTOR, PASTE, "Counterbatch can heal self with paste"],
		[repeat, "alchemist_etching_paste", "damage", OTHER, PASTE, "Counterbatch can damage with paste"],
		[repeat, "alchemist_plain_tonic", "damage", OTHER, {}, "Plain Tonic cannot be bottled"],
		[repeat, "alchemist_acid", "unknown", OTHER, {}, "missing dose polarity cannot guess"],
		[bitter, "alchemist_potion", "damage", OTHER, HOSTILE, "Mixologist uses her own hostile tip"],
		[bitter, "alchemist_potion", "heal", OTHER, {}, "Bitter never plays a helpful pour"],
		[rogue_bitter, "alchemist_potion", "damage", OTHER, {"clip": "bitter_medicine", "impact_frame": 13},
			"Dodger uses his borrowed Potion's own fitted tip"],
		[rogue_bitter, "alchemist_potion", "heal", OTHER, {}, "Dodger never gives a helpful bitter dose"],
		[solvent, "alchemist_plain_tonic", "damage", OTHER, HOSTILE, "Plain Solvent shares the hostile tip"],
		[solvent, "alchemist_potion", "damage", OTHER, {}, "Plain Solvent does not pass as a potion"],
	]
	for row in cases:
		_expect(_dose(row[0], row[1], row[2], row[3]), row[4], row[5])
	var primary := _dose(buffer, "alchemist_acid", "heal", OTHER)
	primary["effects"] = [{"kind": "heal", "target_id": ACTOR, "amount": 1}]
	_expect(primary, TOSS, "splash on self must not choose the self delivery")
	primary.dose["delivery_form_id"] = "alchemist_acid"
	_expect(primary, {}, "ordinary recipe data cannot authorize a converted delivery")
	_expect(buffer, {}, "no dose metadata cannot guess")


func _replay(wearer: String, branch: String, delivery: String, recipe: String, polarity: String,
		recipient: String) -> Dictionary:
	var repeat := _use(wearer, "alchemist_repeat_batch", "alchemist_repeat_batch", "repeat_batch")
	repeat["branch"] = branch
	var result := _dose(repeat, recipe, polarity, recipient)
	result.dose["delivery_form_id"] = delivery
	return result


func _expect_replay(performance: Dictionary, handles: bool, expected: Dictionary, message: String) -> void:
	if Bindings.replays_fitted_dose(performance) != handles:
		_failures.append("%s: incorrect stored-fitted replay classification" % message)
	var before := performance.duplicate(true)
	_expect(performance, expected, message)
	if performance != before:
		_failures.append("%s: binding lookup rewrote the committed facts" % message)


func _replayed_fitted_bottles() -> void:
	var cases := [
		["buffer_solution", "alchemist_acid", "heal", OTHER, true, TOSS, "Buffer remains a ranged heal"],
		["buffer_solution", "alchemist_acid", "heal", ACTOR, true, OFFER, "Buffer to self uses the compact offer"],
		["sealing_paste", "alchemist_etching_paste", "heal", OTHER, true, PASTE, "Sealing stays a close application"],
		["sealing_paste", "alchemist_etching_paste", "heal", ACTOR, true, PASTE, "Sealing to self does not fly"],
		["bitter_medicine", "alchemist_potion", "damage", OTHER, true, HOSTILE, "Bitter owns the replay and uses the hostile tip"],
		["alchemist_acid", "alchemist_acid", "damage", OTHER, false, {}, "stock Acid is untouched"],
		["alchemist_potion", "alchemist_potion", "heal", OTHER, false, {}, "stock Potion is untouched"],
		["alchemist_etching_paste", "alchemist_etching_paste", "damage", OTHER, false, {}, "stock Paste is untouched"],
		["buffer_solution", "alchemist_acid", "damage", OTHER, false, {}, "contradictory Buffer polarity is not a fitted bottle"],
		["buffer_solution", "alchemist_potion", "heal", OTHER, false, {}, "contradictory Buffer recipe is not a fitted bottle"],
		["bitter_medicine", "alchemist_potion", "heal", OTHER, false, {}, "Bitter cannot have helpful polarity"],
		["bitter_medicine", "alchemist_potion", "damage", ACTOR, false, {}, "hostile replay cannot target self"],
		["counterbatch", "alchemist_acid", "heal", OTHER, false, {}, "Counterbatch cannot be stored"],
		["plain_solvent", "alchemist_plain_tonic", "damage", OTHER, false, {}, "Plain Solvent cannot be stored"],
		["unknown", "alchemist_potion", "damage", OTHER, false, {}, "a different form name alone proves nothing"],
	]
	for branch in ["ordinary", "fallback"]:
		for row in cases:
			_expect_replay(_replay("alchemist", branch, row[0], row[1], row[2], row[3]),
				row[4], row[5], "%s: %s" % [branch, row[6]])
	var buffer := _replay("alchemist", "ordinary", "buffer_solution", "alchemist_acid", "heal", ACTOR)
	buffer["aim"] = {"id": OTHER, "cell": Vector2i(3, 2)}
	_expect_replay(buffer, true, OFFER, "replay uses current dose recipient, not unrelated aim")
	_expect_replay(buffer.merged({"cast_key": "rogue"}, true), false, {}, "wrong wearer cannot replay")
	_expect_replay(buffer.merged({"source_handler": "heal"}, true), false, {}, "wrong source handler cannot replay")
	_expect_replay(buffer.merged({"source_ability_id": "alchemist_acid"}, true), false, {}, "wrong source cannot replay")
	_expect_replay(buffer.merged({"branch": "echo"}, true), false, {}, "echo is not an ordinary replay")
	_expect_replay(buffer.merged({"dose": {}}, true), false, {}, "missing delivery cannot claim replay")
	_expect(buffer, {}, "missing fitted replay art remains clipless, not a legacy fallback",
		func(_wearer, _id): return null)
	var bitter := _replay("alchemist", "fallback", "bitter_medicine", "alchemist_potion", "damage", OTHER)
	_expect(bitter, {}, "missing hostile tip cannot fall back to a helpful Potion",
		func(wearer, key): return null if key == "hostile_dose" else _art.clip_for(wearer, key))


func _exclusions() -> void:
	var known := _use("necromancer", "inspiring_melody_in_tune", "inspiring_melody", "perform")
	for branch in ["ordinary", "fallback", "echo"]:
		var ordinary := known.merged({"branch": branch, "form_id": "inspiring_melody"}, true)
		_expect(ordinary, {}, "ordinary %s is owned by the caller" % branch)
		_expect(known.merged({"branch": branch}, true), {}, "even a valid form cannot claim %s" % branch)
	_expect(known.merged({"cast_key": "wizard"}, true), {}, "no Bard or Crypter pose on Wizard")
	_expect(known.merged({"cast_key": "rival_wizard"}, true), {}, "a rival is not the guild wearer")
	_expect(known.merged({"source_handler": "heal"}, true), {}, "catalog source redefinition is not a song")
	_expect(known.merged({"source_ability_id": "bard_take_the_stage"}, true), {}, "source ability must match")
	_expect(_use("blacksmith", "clear_the_floor", "knight_aura", "apply_status"), {},
		"Smith's native kit is not a fitted wearer")
	_expect(_use("bard", "clear_jump", "rogue_confusing_dodge", "swap_furthest"), {},
		"borrowed Dodge cannot substitute another learner's jump")


func _missing_media() -> void:
	var ring := _use("wizard", "ring_of_salve", "wizard_ring_sparks", "sweep")
	_expect(ring, {}, "no wearer clip means no binding", func(_wearer, _id): return null)
	var partial := CastSprites.Clip.new()
	partial.path = "res://assets/cast/wizard.png"
	partial.frames = [Rect2(0, 0, 1, 1)]
	partial.source_frames = [1]
	_expect(ring, {}, "no authored key drawing means no binding", func(_wearer, _id): return partial)
	partial.source_frames = [12]
	partial.path = "res://assets/cast/__missing_wizard_texture__.png"
	_expect(ring, {}, "atlas metadata with missing texture is not available",
		func(_wearer, _id): return partial)
	partial.path = "res://assets/cast/wizard.png"
	partial.frames = [Rect2(100000, 0, 1, 1)]
	_expect(ring, {}, "an out-of-bounds frame cannot act as loaded media",
		func(_wearer, _id): return partial)
	var buffer := _dose(_use("alchemist", "buffer_solution", "alchemist_acid", "acid"),
		"alchemist_acid", "heal", OTHER)
	_expect(buffer, {}, "no detached flask means no ranged take",
		func(wearer, id): return null if id == "acid_flask" else _art.clip_for(wearer, id))
	var lend := _use("knight", "lend_a_shield", "knight_shield_throw", "attack")
	lend["shield_away"] = false
	_expect(lend, {}, "the hostile shield prop is not a substitute for the fitted release",
		func(wearer, id): return null if id == "lend_a_shield_prop" else _art.clip_for(wearer, id))
	var jump := _use("wizard", "clear_jump", "rogue_confusing_dodge", "swap_furthest")
	partial.frames = [Rect2(0, 0, 1, 1)]
	partial.source_frames = [17]
	_expect(jump, {}, "an authored landing alone is not enough; takeoff drawing is required",
		func(_wearer, _id): return partial)
