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
const BOW = preload("res://assets/audio/bow_harpoon.wav")
const SHIELD = preload("res://assets/audio/shield_strike.wav")
const ROPE = preload("res://assets/audio/rope_pull.wav")
const GLASS = preload("res://assets/audio/potion_smash.wav")
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
	service.sound_requested.connect(_record)
	var cases := [
		{"label": "adjacent harpoon", "actor": "harpooner", "ability": "enemy_harpoon",
			"target": "knight", "at": Vector2i(4, 3), "id": "target", "clip": "close_thrust"},
		{"label": "ranged harpoon", "actor": "harpooner", "ability": "enemy_harpoon",
			"target": "knight", "at": Vector2i(5, 3), "id": "target", "clip": "ranged_cast"},
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
	var paste: Dictionary = results["Etching Paste"]
	var acid: Dictionary = results["thrown Acid"]
	if not paste.is_empty() and not acid.is_empty():
		_check(acid.stream == GLASS, "Thrown Acid uses the approved smashed vial")
		_check(paste.stream != GLASS and paste.stream != acid.stream,
			"Intact Etching Paste is not the sound of smashing a thrown vial")
	service.free()
	if failures.is_empty():
		print("PASS: stock action sounds follow their actual presentation")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _resolve_and_play(example: Dictionary) -> Dictionary:
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
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
	var result: Dictionary = rules.apply_plan(state, plan)
	var cues: Array = Cues.build(state, result, plan.events, true)
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
