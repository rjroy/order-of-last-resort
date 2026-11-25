extends SceneTree
## Run headless with isolated TMPDIR and XDG directories.
## Exercises the shared service and its real players, without audition renders.

const Effects = preload("res://presentation/sound_effects.gd")
const Recipes = preload("res://presentation/sound_recipes.gd")
const Palette = preload("res://presentation/fitted_sound_palette.gd")
const GLASS = preload("res://assets/audio/potion_smash.wav")
const Rules = preload("res://rules.gd")
const AlchemyCases = preload("res://tests/smith_playback_alchemy_cases.gd")

var service: Node
var heard: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	service = Effects.new()
	root.add_child(service)
	service.volume = 0.8
	service.master_volume = 1.0
	service.sound_requested.connect(_record)
	_check(not service.dispatch_performance({"kind": "impact", "branch": "fallback"}),
		"ordinary fallback remains owned by ordinary dispatch")
	service.dispatch_beat("impact", "smith", "blacksmith_hammer_time", "attack", "")
	if _check(heard.size() == 1, "native Smith attack dispatches once"):
		_check(heard[0].cue_id == "smith_hammer" and heard[0].stream == Recipes.get_stream("smith_hammer"),
			"native Smith attack keeps its actual stock stream")
		_check(heard[0].playing and is_equal_approx(heard[0].gain, db_to_linear(-14.0)),
			"native request reports the gain of the playing player")
	_check(not service.dispatch_performance({"kind": "impact", "branch": "echo"}),
		"ordinary echo remains owned by ordinary dispatch")
	service.planning("smith")
	if _check(heard.size() == 2, "planning produces only its pencil sound"):
		_check(heard[1].cue_id == "pencil" and heard[1].gain < heard[0].gain,
			"planning remains quieter than an impact")
	_fitted_cases()
	service.volume = 0.0
	var count := heard.size()
	var players_before := service.get_child_count()
	service.dispatch_beat("impact", "smith", "blacksmith_hammer_time", "attack", "")
	_check(service.dispatch_performance(_beat("doctors_orders")),
		"muted fitted beat still suppresses ordinary audio")
	_check(heard.size() == count and service.get_child_count() == players_before,
		"muted native dispatch creates no player or signal")
	for player in service.get_children():
		player.stop()
		player.queue_free()
	await process_frame
	service.free()
	await _scene_cases()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: fitted audio dispatch")
	quit(0 if failures.is_empty() else 1)


func _scene_cases() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	service = scene.find_child("SoundEffects", true, false)
	service.volume = 0.8
	service.master_volume = 1.0
	service.sound_requested.connect(_record)
	var rules := Rules.new()
	var samples := AlchemyCases.cases()
	for sample: Dictionary in [samples[0], samples[1], samples[4]]:
		var state: Dictionary = sample.state
		scene.call("_show_battle", state)
		scene.set("_planned_state", rules.choose_manual(state, sample.actor, sample.ability, sample.target))
		heard.clear()
		scene.call("_refresh")
		var plan: Dictionary = scene.get("_plan")
		_check(plan.get("valid", false) and heard.is_empty(),
			sample.id + ": real forecast is valid and silent")
		var board: Control = scene.get("_board")
		board.set_process(false)
		var button := scene.find_child("Commit", true, false) as BaseButton
		button.pressed.emit()
		board.set_process(false)
		var ticks := 0
		while board.action_playback_pending() and ticks < 3000:
			board.call("_process", 0.01)
			board.set_process(false)
			ticks += 1
		_check(not board.action_playback_pending(), sample.id + ": playback drains")
		var impacts := heard.filter(func(sound): return sound.kind == "impact" \
			and sound.unit_id == sample.actor and sound.ability_id == sample.ability)
		var reactions := heard.filter(func(sound): return sound.kind == "reaction" \
			and sound.ability_id == sample.ability)
		if _check(impacts.size() == 1, sample.id + ": one wearer impact, no duplicate stock impact"):
			var cue := "fitted_bitter" if sample.ability == "alchemist_potion" else "dose"
			var stream: AudioStream = Recipes.get_stream(cue) if cue == "dose" else Palette.get_stream(cue)
			_check(impacts[0].cue_id == cue and impacts[0].stream == stream and impacts[0].playing,
				sample.id + ": actual player uses the selected converted stream")
		_check(reactions.size() == 1 and reactions[0].unit_id == sample.target,
			sample.id + ": exactly one actual recipient reaction")
	for player in scene.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	scene.queue_free()
	await process_frame


func _beat(form: String) -> Dictionary:
	return {"kind": "impact", "branch": "converted", "actor_id": "wearer",
		"source_ability_id": "healer_heal", "form_id": form, "cast_key": "healer",
		"effects": [], "performance_effects": []}


func _fitted_cases() -> void:
	heard.clear()
	var beat := _beat("doctors_orders")
	_check(service.dispatch_performance(beat), "converted impact is handled")
	if _check(heard.size() == 1, "converted impact dispatches exactly once"):
		_check(heard[0].cue_id == "fitted_doctor_snap" \
			and heard[0].stream == Palette.get_stream("fitted_doctor_snap") \
			and heard[0].playing and heard[0].unit_id == "wearer",
			"converted gesture plays the selected fitted stream")
	heard.clear()
	beat = _beat("mending_blast")
	beat.performance_effects = [{"kind": "heal", "target_id": "patient"}]
	_check(service.dispatch_performance(beat), "converted stock cue is handled")
	if _check(heard.size() == 1, "converted stock cue plays once"):
		_check(heard[0].cue_id == "heal" and heard[0].stream == Effects._legacy_tone("heal"),
			"palette null stream falls back to stock lookup")
	heard.clear()
	beat = _beat("cut_the_wire")
	_check(service.dispatch_performance(beat) and heard.is_empty(),
		"deliberately silent converted impact is still handled")
	beat = _beat("counterbatch")
	beat.source_ability_id = "alchemist_repeat_batch"
	beat.dose = {"recipe_id": "alchemist_acid", "recipient_id": "patient",
		"delivery_form_id": "buffer_solution", "polarity": "heal"}
	var reaction := {"kind": "alchemy_reaction", "target_id": "patient", "source_id": "wearer",
		"category": "harmful", "reaction_id": "jelly_knees", "applied": true}
	beat.performance_effects = [reaction, reaction.duplicate()]
	_check(service.dispatch_performance(beat), "converted repeat is handled")
	if _check(heard.size() == 2, "dose and exactly one primary reaction play"):
		_check(heard[0].cue_id == "dose" and heard[0].stream == Recipes.get_stream("dose"),
			"healing acid uses intact dose stream")
		_check(heard[1].kind == "reaction" and heard[1].unit_id == "patient" \
			and heard[1].cue_id == "fitted_reaction_knees" \
			and heard[1].stream == Palette.get_stream("fitted_reaction_knees") \
			and is_equal_approx(heard[1].gain, db_to_linear(-14.0) * .57),
			"one recipient reaction uses selected stream and gain")
	heard.clear()
	beat.branch = "ordinary"
	beat.form_id = "alchemist_repeat_batch"
	beat.dose.polarity = "damage"
	beat.performance_effects[0].applied = false
	beat.performance_effects[1].applied = false
	_check(service.dispatch_performance(beat), "ordinary Repeat preserves resolved fitted delivery")
	if _check(heard.size() == 1, "suppressed reaction is silent"):
		_check(heard[0].cue_id == "potion" and heard[0].stream == GLASS,
			"damaging acid uses stock breaking glass")
	heard.clear()
	beat.dose.delivery_form_id = "alchemist_acid"
	_check(not service.dispatch_performance(beat) and heard.is_empty(),
		"ordinary unconverted Repeat remains with stock dispatch")
	service.dispatch_beat("impact", "wearer", "alchemist_repeat_batch", "repeat_batch", "alchemist_acid")
	_check(heard.size() == 1 and heard[0].stream == GLASS,
		"ordinary Repeat uses stock dispatch exactly once")


func _record(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	var players := service.find_children("*", "AudioStreamPlayer", true, false)
	var player: AudioStreamPlayer = players.back() if not players.is_empty() else null
	heard.append({"kind": kind, "unit_id": unit_id, "ability_id": ability_id,
		"cue_id": cue_id, "gain": gain, "stream": player.stream if player else null,
		"playing": player.playing if player else false})


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition
