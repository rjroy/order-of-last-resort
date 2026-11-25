extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/stock_action_sound_test.gd
## Real stock rule actions -> committed presentation beats -> actual sound player.

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Fixtures = preload("res://tests/fixtures/rules_catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")
const Playback = preload("res://presentation/cast_playback.gd")
const Effects = preload("res://presentation/sound_effects.gd")
const Recipes = preload("res://presentation/sound_recipes.gd")
const BOW = preload("res://assets/audio/bow_harpoon.wav")
const SHIELD = preload("res://assets/audio/shield_strike.wav")
const ROPE = preload("res://assets/audio/rope_pull.wav")
const GLASS = preload("res://assets/audio/potion_smash.wav")
const BLAST = preload("res://assets/audio/magical_blast.wav")
const BONES = preload("res://assets/audio/bone_summon.wav")
var rules := Rules.new()
var service
var heard: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	service = Effects.new()
	root.add_child(service)
	await process_frame
	service.volume = 1.0
	service.master_volume = 1.0
	service.sound_requested.connect(_record)
	var cases := [
		{"label": "adjacent harpoon", "actor": "harpooner", "ability": "enemy_harpoon",
			"target": "knight", "at": Vector2i(4, 3), "id": "target", "clip": "close_thrust"},
		{"label": "ranged harpoon", "actor": "harpooner", "ability": "enemy_harpoon",
			"target": "knight", "at": Vector2i(5, 3), "id": "target", "clip": "ranged_cast"},
		{"label": "Hookhand pull", "actor": "hookhand", "ability": "hook_pull",
			"target": "knight", "at": Vector2i(5, 3), "id": "target"},
		{"label": "shepherd wave", "actor": "frontier_shepherd", "ability": "frontier_shepherd_wave",
			"target": "frontier_sheep", "at": Vector2i(4, 3), "id": "target"},
		{"label": "Grave Bell", "actor": "necromancer", "ability": "necro_grave_bell",
			"target": "harpooner", "at": Vector2i(4, 3), "id": "", "grant": true},
		{"label": "Etching Paste", "actor": "alchemist", "ability": "alchemist_etching_paste",
			"target": "harpooner", "at": Vector2i(4, 3), "id": "target", "grant": true},
		{"label": "thrown Acid", "actor": "alchemist", "ability": "alchemist_acid",
			"target": "harpooner", "at": Vector2i(4, 3), "id": "target"},
	]
	var results := {}
	for example: Dictionary in cases:
		results[example.label] = _resolve_and_play(example)
	var adjacent: Dictionary = results["adjacent harpoon"]
	var ranged: Dictionary = results["ranged harpoon"]
	if not adjacent.is_empty() and not ranged.is_empty():
		_check(ranged.stream == BOW, "Ranged harpoon plays the approved fired projectile")
		_check(adjacent.stream != BOW and adjacent.stream != ranged.stream,
			"In-hand close thrust is audibly distinct from a fired projectile")
	var wave: Dictionary = results["shepherd wave"]
	if not wave.is_empty():
		_check(wave.stream != SHIELD, "Harmless Shepherd wave is not a shield strike")
	var bell: Dictionary = results["Grave Bell"]
	if not bell.is_empty():
		_check(bell.stream != ROPE and bell.cue_id == "bell",
			"Grave Bell produces a bell cue, not a rope snap")
	var hook: Dictionary = results["Hookhand pull"]
	if not hook.is_empty():
		_check(hook.stream == ROPE, "Hookhand pull retains the approved rope recording")
	var paste: Dictionary = results["Etching Paste"]
	var acid: Dictionary = results["thrown Acid"]
	if not paste.is_empty() and not acid.is_empty():
		_check(acid.stream == GLASS, "Thrown Acid uses the approved smashed vial")
		_check(paste.stream != GLASS and paste.stream != acid.stream,
			"Intact Etching Paste is not the sound of smashing a thrown vial")
	_custom_handlers()
	_dispatch_catalog()
	service.free()
	if failures.is_empty():
		print("PASS: stock action sounds follow their actual presentation")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _custom_handlers() -> void:
	var shout := {"handler": "attack", "label": "Shout", "help": "Damage the nearest opponent.",
		"params": {"damage": 2}, "targeting": {"kind": "automatic", "teams": ["enemies"]}}
	var harmless := shout.duplicate(true)
	harmless.params.damage = 0
	for example in [
		{"label": "custom damaging greeting", "actor": "zombie", "ability": "say_hello",
			"target": "harpooner", "at": Vector2i(4, 3), "id": "", "definition": shout, "damage": 2},
		{"label": "custom harmless greeting", "actor": "zombie", "ability": "say_hello",
			"target": "harpooner", "at": Vector2i(4, 3), "id": "", "definition": harmless, "damage": 0},
	]:
		var result := _resolve_and_play(example)
		if not result.is_empty():
			var expected := SHIELD if example.damage > 0 else _dispatch("impact", "custom_gesture", "harmless_attack", "")
			_check(expected != null and _same_audio(result.stream, expected),
				example.label + ": actual handler determines sound, not the stock ID")

	# A zero-damage Harpoon is a gesture, not either the close shaft or bow,
	# even at the cells where stock playback selects those two action-time sounds.
	var defs: Dictionary = Catalog.read_default()
	var harmless_harpoon: Dictionary = defs.abilities.enemy_harpoon.duplicate(true)
	harmless_harpoon.params.damage = 0
	for at in [Vector2i(4, 3), Vector2i(5, 3)]:
		var example := {"label": "custom harmless harpoon at " + str(at), "actor": "harpooner",
			"ability": "enemy_harpoon", "target": "knight", "at": at, "id": "target",
			"definition": harmless_harpoon, "damage": 0}
		var result := _resolve_and_play(example)
		if not result.is_empty():
			var expected := _dispatch("impact", "custom_gesture", "harmless_attack", "")
			_check(expected != null and _same_audio(result.stream, expected),
				example.label + ": harmless handler takes precedence over action-time attack branches")


func _dispatch_catalog() -> void:
	var defs: Dictionary = Catalog.read_default()
	var sounds := {}
	for ability: String in defs.abilities:
		var handler: String = defs.abilities[ability].handler
		var kind := "step" if handler == "move" else "impact"
		var recipe := "alchemist_potion" if handler == "repeat_batch" else ""
		var stream := _dispatch(kind, ability, handler, recipe)
		if _check(stream != null, ability + ": catalog action dispatches a playable stream"):
			sounds[ability] = stream

	# These are different actions, not just different labels on identical samples.
	for pair in [
		["knight_shield_throw", "enemy_attack"],
		["rogue_tripwire", "shield_bash"],
		["knight_aura", "shield_bash"],
		["wizard_ring_sparks", "wizard_blast"],
		["alchemist_etching_paste", "alchemist_acid"],
		["healer_bonk", "shield_bash"],
		["healer_field_dressing", "healer_bonk"],
		["rogue_confusing_dodge", "rogue_wasnt_me"],
		["raise_dead", "summon_skeleton"],
		["wave", "dont_go"],
		["say_hello", "offer_flower"],
		["frontier_wagon_strike", "goblin_jab"],
		["ogre_strike", "goblin_jab"],
		["bomber_strike", "frontier_wagon_strike"],
	]:
		if sounds.has(pair[0]) and sounds.has(pair[1]):
			_check(not _same_audio(sounds[pair[0]], sounds[pair[1]]),
				"%s and %s must sound different" % pair)
	if sounds.has("bard_take_the_stage") and sounds.has("frontier_war_drum"):
		_check(not _same_audio(sounds.bard_take_the_stage, sounds.frontier_war_drum),
			"Take the Stage is a song, not a war drum")
	for preserved in [["wizard_blast", BLAST], ["summon_skeleton", BONES],
			["enemy_harpoon", BOW], ["alchemist_acid", GLASS]]:
		if sounds.has(preserved[0]):
			_check(sounds[preserved[0]] == preserved[1], preserved[0] + ": suitable approved recording is retained")
	if sounds.has("wizard_pull"):
		_check(not _same_audio(sounds.wizard_pull, ROPE), "Magical Pull sounds distinct from rope")

	for recipe in ["alchemist_potion", "alchemist_acid", "alchemist_etching_paste"]:
		var repeated := _dispatch("impact", "alchemist_repeat_batch", "repeat_batch", recipe)
		if _check(repeated != null and sounds.has(recipe), "Repeat Batch plays " + recipe):
			_check(_same_audio(repeated, sounds[recipe]), "Repeat Batch inherits " + recipe + " audio")

	# Shared cache reuse and a fresh synthesis are different properties. This
	# isolated test process can evict individual private entries without adding
	# a runtime cache-control API.
	var other = Effects.new()
	root.add_child(other)
	other.volume = 1.0
	other.master_volume = 1.0
	for ability in sounds:
		var first: AudioStream = sounds[ability]
		if not first is AudioStreamWAV or not first.resource_path.is_empty():
			continue
		var handler: String = defs.abilities[ability].handler
		var recipe := "alchemist_potion" if handler == "repeat_batch" else ""
		var kind := "step" if handler == "move" else "impact"
		var key: String = service._family(ability, handler, recipe)
		var cached := _dispatch(kind, ability, handler, recipe, other)
		_check(cached == first, ability + ": generated stream is shared across services")
		Recipes._cache.erase(key)
		Effects._tones.erase(key)
		var cold := _dispatch(kind, ability, handler, recipe, other)
		_check(cold != null and cold != first and _same_audio(first, cold),
			ability + ": independent cold synthesis reproduces the PCM")
		# Later abilities can share this recipe, but must compare against the
		# newly cached resource rather than the evicted earlier instance.
		for other_ability in sounds:
			if sounds[other_ability] == first:
				sounds[other_ability] = cold
		_check(first.get_length() > 0.02 and first.get_length() < 5.0 and first.data.count(0) < first.data.size(),
			ability + ": generated audio has audible samples and a usable duration")
	other.free()


func _dispatch(kind: String, ability: String, handler: String, recipe: String, target = null) -> AudioStream:
	var player_service = service if target == null else target
	var before: int = player_service.get_child_count()
	player_service.dispatch_beat(kind, "actor", ability, handler, recipe)
	if player_service.get_child_count() != before + 1:
		return null
	var player := player_service.get_child(before) as AudioStreamPlayer
	return player.stream if player != null else null


func _same_audio(left: AudioStream, right: AudioStream) -> bool:
	if left is AudioStreamWAV and right is AudioStreamWAV:
		return left.mix_rate == right.mix_rate and left.format == right.format \
			and left.stereo == right.stereo and left.data == right.data
	return left == right


func _resolve_and_play(example: Dictionary) -> Dictionary:
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
	if example.has("definition"):
		defs.abilities[example.ability] = example.definition
		if example.ability == "say_hello":
			defs.upgrades.erase("necromancer_warm_welcome")
	if example.get("grant", false):
		var characters := {}
		characters.merge(defs.characters, true)
		var owner := {}
		owner.merge(defs.characters[example.actor], true)
		var abilities: Array = []
		abilities.assign(Catalog.profile(defs, example.actor).abilities)
		abilities.append(example.ability)
		owner["abilities"] = abilities
		characters[example.actor] = owner
		var owned_defs := {}
		owned_defs.merge(defs, true)
		owned_defs["characters"] = characters
		defs = owned_defs
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [_unit("actor", example.actor, Vector2i(3, 3)),
		_unit("target", example.target, example.at)]
	state.orders = {}
	state.overrides = {}
	var plan: Dictionary = rules.preview(state, "actor", example.ability, example.id)
	if not _check(plan.get("valid", false), example.label + ": real rules action resolves"):
		return {}
	if example.has("damage"):
		_check(plan.events.any(func(event): return event.get("type") == "damage" \
			and event.get("target_id") == "target" and int(event.get("amount", -1)) == example.damage),
			example.label + ": custom action resolves the intended damage")
	var result: Dictionary = rules.apply_plan(state, plan)
	var cues: Array = Cues.build(state, result, plan.events, true)
	if example.ability == "say_hello" and example.has("definition"):
		_check(cues.any(func(cue): return cue.get("unit_id") == "actor" \
			and cue.get("silent_action", false) and cue.get("audio_ability") == "say_hello"),
			example.label + ": include_silent retains the custom committed action")
	if example.has("clip"):
		_check(cues.any(func(cue): return cue.get("unit_id") == "actor" \
			and cue.get("clip") == example.clip), example.label + ": correct action-time presentation is selected")
	if example.ability == "frontier_shepherd_wave":
		_check(plan.events.any(func(event): return event.get("type") == "damage" \
			and event.get("target_id") == "target" and int(event.get("amount", -1)) == 0),
			"Shepherd wave is genuinely harmless")
	var art := Sprites.new()
	art.load_manifest()
	var playback := Playback.new()
	playback.enqueue(cues, art)
	heard.clear()
	for beat: Dictionary in playback.advance(60000.0):
		service.dispatch_beat(beat.kind, beat.unit_id, beat.ability_id, beat.handler, beat.recipe)
	var matches := heard.filter(func(sound): return sound.kind == "impact" \
		and sound.unit_id == "actor" and sound.ability_id == example.ability)
	if not _check(matches.size() == 1 and matches[0].stream != null,
			example.label + ": one actual impact sound is played"):
		return {}
	return matches[0]


func _record(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	var players: Array = service.find_children("*", "AudioStreamPlayer", true, false)
	var stream: AudioStream = players.back().stream if not players.is_empty() else null
	heard.append({"kind": kind, "unit_id": unit_id, "ability_id": ability_id,
		"cue_id": cue_id, "gain": gain, "stream": stream})


func _unit(id: String, character: String, at: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": at,
		"hp": 20, "max_hp": 20, "statuses": {}, "dose_rng_state": 1}


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition
