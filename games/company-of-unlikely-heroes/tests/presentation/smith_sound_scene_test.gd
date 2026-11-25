extends SceneTree
## Actual stock actions, forecast silence and committed sound requests.
## Set SMITH_SOUND_RENDER_DIR to an existing absolute directory to export the
## exact synthesized PCM streams as WAVs for offline audition.

const Rules = preload("res://rules/rules.gd")
const Recipes = preload("res://presentation/audio/sound_recipes.gd")
const Effects = preload("res://presentation/audio/sound_effects.gd")
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
	if not _check(service != null, "shared sound service exists"):
		_finish()
		return
	service.volume = 1.0
	service.master_volume = 1.0
	service.sound_requested.connect(_record)
	_recipes()
	var state := _fixture()
	_commit(state, "actor", "blacksmith_try_this", "ally", "smith_fit")
	_commit(_fixture(), "actor", "blacksmith_hammer_time", "foe", "smith_hammer")
	var fit: Dictionary = rules.preview(state, "actor", "blacksmith_try_this", "ally")
	if _check(fit.get("valid", false), "release fixture has a legal fitting"):
		var fitted: Dictionary = rules.apply_plan(state, fit)
		_commit(fitted, "ally", "smith_quick_release", "3,5", "smith_release")
	_finish()


func _recipes() -> void:
	var keys := ["smith_fit", "smith_hammer", "smith_release"]
	var previous: Array[PackedByteArray] = []
	for key in keys:
		var stream: AudioStreamWAV = Recipes.get_stream(key)
		if not _check(stream != null, key + ": recipe exists"):
			continue
		_check(stream.get_length() > 0.05 and stream.get_length() < 0.5 and stream.data.count(0) < stream.data.size(),
			key + ": bounded non-silent PCM")
		for data in previous:
			_check(data != stream.data, key + ": PCM differs from other Smith cues")
		previous.append(stream.data)
		Recipes._cache.erase(key)
		_check(Recipes.get_stream(key).data == stream.data, key + ": cold render is deterministic")
		var dir := OS.get_environment("SMITH_SOUND_RENDER_DIR")
		if not dir.is_empty():
			_check(stream.save_to_wav(dir.path_join(key + ".wav")) == OK, key + ": audition render saved")
	var effects := Effects.new()
	_check(effects._family("blacksmith_hammer_time", "push", "") != "smith_hammer",
		"custom redefinition does not acquire stock hammer audio")
	_check(effects._family("blacksmith_try_this", "attack", "") != "smith_fit",
		"custom redefinition does not acquire stock fitting audio")
	effects.free()


func _fixture() -> Dictionary:
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.round = 1
	state.outcome = "ongoing"
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	state.units = [_unit("actor", "blacksmith", Vector2i(3, 3)),
		_unit("ally", "knight", Vector2i(3, 4)),
		_unit("foe", "harpooner", Vector2i(4, 3))]
	state.units[0].upgrades = {"smith_quick_release": 1}
	state.party = ["actor", "ally"]
	state.orders = {}
	state.overrides = {}
	return state


func _commit(state: Dictionary, actor: String, ability: String, target: String, key: String) -> void:
	var direct: Dictionary = rules.preview(state, actor, ability, target)
	if not _check(direct.get("valid", false), ability + ": direct action is legal"):
		return
	scene.call("_show_battle", state)
	scene.set("_planned_state", rules.choose_manual(state, actor, ability, target))
	heard.clear()
	scene.call("_refresh")
	var plan: Dictionary = scene.get("_plan")
	if not _check(plan.get("valid", false) and plan.events.any(func(event):
			return event.get("resolved_action", {}).get("unit_id") == actor \
				and event.get("resolved_action", {}).get("ability_id") == ability),
			ability + ": forecast contains the actual action"):
		return
	_check(heard.is_empty(), ability + ": forecast is silent")
	var board: Control = scene.get("_board")
	board.set_process(false)
	var button := scene.find_child("Commit", true, false) as BaseButton
	if not _check(button != null and not button.disabled, ability + ": commit available"):
		return
	button.pressed.emit()
	board.set_process(false)
	var elapsed := 0
	while board.action_playback_pending() and elapsed < 3000:
		board.call("_process", 0.01)
		board.set_process(false)
		elapsed += 1
	_check(not board.action_playback_pending(), ability + ": playback drains")
	var impacts := heard.filter(func(sound): return sound.kind == "impact" \
		and sound.unit_id == actor and sound.ability_id == ability)
	if _check(impacts.size() == 1, ability + ": exactly one committed impact"):
		_check(impacts[0].cue_id == key and impacts[0].stream == Recipes.get_stream(key),
			ability + ": intended procedural stream plays")


func _record(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	var players := service.find_children("*", "AudioStreamPlayer", true, false)
	heard.append({"kind": kind, "unit_id": unit_id, "ability_id": ability_id,
		"cue_id": cue_id, "gain": gain,
		"stream": players.back().stream if not players.is_empty() else null})


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
		print("PASS: Smith committed action sounds")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
