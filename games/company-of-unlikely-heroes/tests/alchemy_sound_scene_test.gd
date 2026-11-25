extends SceneTree
## Run with a fresh isolated XDG_DATA_HOME:
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/alchemy_sound_scene_test.gd
## Actual resolved doses, committed through the battle scene and observed at the player.

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const GLASS = preload("res://assets/audio/potion_smash.wav")
var rules := Rules.new()
var scene: Node
var service: Node
var heard: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	service = scene.find_child("SoundEffects", true, false)
	if not _check(service != null and service.has_signal("sound_requested"), "Shared sound service is present"):
		_finish()
		return
	service.connect("sound_requested", _record_sound)

	for case in [
		["alchemist", "alchemist_potion", "ally", false],
		["alchemist", "alchemist_plain_tonic", "ally", false],
		["rogue", "alchemist_potion", "ally", false],
		["alchemist", "alchemist_acid", "foe", true],
	]:
		var state := _fixture(case[0])
		_commit_dose(state, case[1], case[2], case[3], str(case[0]) + " " + str(case[1]))

	for recipe in [
		["alchemist_potion", "ally", "other_ally", false],
		["alchemist_acid", "foe", "other_foe", true],
	]:
		var state := _fixture("alchemist")
		var origin: Dictionary = rules.preview(state, "actor", recipe[0], recipe[1])
		if not _check(origin.get("valid", false), "Origin recipe resolves before Repeat Batch"):
			continue
		var bottled: Dictionary = rules.apply_plan(state, origin)
		_check(bottled.units[0].get("bottled_reaction", {}).get("recipe") == recipe[0],
			"Repeat Batch fixture bottles the actual original recipe")
		_commit_dose(bottled, "alchemist_repeat_batch", recipe[2], recipe[3],
			"Repeat Batch of " + str(recipe[0]))
	_finish()


func _fixture(character: String) -> Dictionary:
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.round = 1
	state.outcome = "ongoing"
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	state.units = [_unit("actor", character, Vector2i(3, 3)),
		_unit("ally", "knight", Vector2i(3, 4)),
		_unit("other_ally", "healer", Vector2i(3, 2)),
		_unit("foe", "harpooner", Vector2i(4, 3)),
		_unit("other_foe", "harpooner", Vector2i(2, 3))]
	state.units[0]["upgrades"] = {"alchemist_spare_vial": 1, "alchemist_keep_the_culture": 1}
	state.units[0]["dose_rng_state"] = 1
	state.units[1].hp = 5
	state.units[2].hp = 5
	state.party = ["actor", "ally", "other_ally"]
	state.orders = {}
	state.overrides = {}
	if character == "rogue":
		# A locally owned catalog grants the same donor ability as the learned kit.
		var definitions := {}
		definitions.merge(state.catalog.defs, true)
		var characters := {}
		characters.merge(state.catalog.defs.characters, true)
		var rogue := {}
		rogue.merge(state.catalog.defs.characters.rogue, true)
		var abilities: Array = []
		abilities.assign(rogue.abilities)
		abilities.append("alchemist_potion")
		rogue["abilities"] = abilities
		characters["rogue"] = rogue
		definitions["characters"] = characters
		state["catalog"] = Catalog.FrozenCatalog.new(definitions)
	return state


func _commit_dose(state: Dictionary, ability: String, target: String, breaks_glass: bool, label: String) -> void:
	var direct: Dictionary = rules.preview(state, "actor", ability, target)
	if not _check(direct.get("valid", false), label + ": actual dose is legal"):
		return
	scene.call("_show_battle", state)
	scene.set("_planned_state", rules.choose_manual(state, "actor", ability, target))
	heard.clear()
	scene.call("_refresh")
	var plan: Dictionary = scene.get("_plan")
	if not _check(plan.get("valid", false) and plan.events.any(func(event):
			return event.get("resolved_action", {}).get("unit_id") == "actor" \
				and event.get("resolved_action", {}).get("ability_id") == ability),
			label + ": actual round forecasts the selected dose"):
		return
	_check(heard.is_empty(), label + ": forecasting does not dispatch audio")
	var board: Control = scene.get("_board")
	board.set_process(false)
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if not _check(commit != null and not commit.disabled, label + ": dose can commit"):
		return
	commit.pressed.emit()
	board.set_process(false)
	var elapsed := 0.0
	while board.action_playback_pending() and elapsed < 30000.0:
		board.call("_process", 0.01)
		board.set_process(false)
		elapsed += 10.0
	_check(not board.action_playback_pending(), label + ": playback drains")
	var doses := heard.filter(func(sound): return sound.kind == "impact" \
		and sound.unit_id == "actor" and sound.ability_id == ability)
	if _check(doses.size() == 1, label + ": one actual dose sound is dispatched"):
		_check(doses[0].stream != null and (doses[0].stream == GLASS) == breaks_glass,
			label + (": thrown vial uses the breaking-glass recording" if breaks_glass \
				else ": intact handoff must never use the breaking-glass recording"))


func _record_sound(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	var players := service.find_children("*", "AudioStreamPlayer", true, false)
	var stream: AudioStream = players.back().stream if not players.is_empty() else null
	heard.append({"kind": kind, "unit_id": unit_id, "ability_id": ability_id,
		"cue_id": cue_id, "gain": gain, "stream": stream})


func _unit(id: String, character: String, at: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": at,
		"hp": 20, "max_hp": 20, "statuses": {}}


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func _finish() -> void:
	if is_instance_valid(scene):
		scene.free()
	if failures.is_empty():
		print("PASS: dose audio follows the real handoff or throw")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
