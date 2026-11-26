extends SceneTree
## Direct checkout: godot --headless --path games/company-of-unlikely-heroes
##   --script res://tests/presentation/smith_playback_scene_test.gd -- --case=borrowed_knight_healer_bonk
## Omit --case to exercise all available fixtures. --list prints stable IDs.
## For later human review, omit --headless and add --interactive --case=ID.
## The real battle opens with the action staged; the reviewer commits it.
## Headless dispatch is not evidence that animation or audio was perceived.

const Driver = preload("res://tests/support/storybook_driver.gd")
const CASE_MODULES := [
	"res://tests/fixtures/smith_playback_borrowed_cases.gd",
	"res://tests/fixtures/smith_playback_tactical_cases.gd",
	"res://tests/fixtures/smith_playback_alchemy_cases.gd",
	"res://tests/fixtures/smith_playback_performance_summon_cases.gd",
]
var scene: Node
var driver
var sounds: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var selected := ""
	var interactive := false
	var listing := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			selected = arg.trim_prefix("--case=")
		elif arg == "--interactive":
			interactive = true
		elif arg == "--list":
			listing = true
	var examples: Array[Dictionary] = []
	var missing: Array[String] = []
	for path in CASE_MODULES:
		if ResourceLoader.exists(path):
			examples.append_array(load(path).cases())
		else:
			missing.append(path)
			print("NOT AVAILABLE: ", path)
	var ids: Array = examples.map(func(example: Dictionary): return example.get("id", ""))
	_check(ids.size() == ids.duplicate().reduce(func(acc, id):
		if id not in acc:
			acc.append(id)
		return acc, []).size(), "case IDs are unique")
	if listing:
		for id in ids:
			print(id)
		await _finish()
		return
	if selected.is_empty() and not missing.is_empty():
		_check(false, "complete run requires all fixture modules")
	if selected.is_empty() and missing.is_empty():
		var borrowed: Array = examples.filter(func(example: Dictionary):
			return str(example.get("id", "")).begins_with("borrowed_"))
		var native: Array = examples.filter(func(example: Dictionary):
			return not str(example.get("id", "")).begins_with("borrowed_"))
		var native_abilities: Array = native.map(func(example: Dictionary): return example.get("ability", ""))
		var unique_abilities: Array = []
		for ability in native_abilities:
			if ability not in unique_abilities:
				unique_abilities.append(ability)
		_check(borrowed.size() == 7 and native.size() == 25 and unique_abilities.size() == 25,
			"complete run requires seven borrowed and 25 distinct native source abilities")
	if not selected.is_empty():
		examples = examples.filter(func(example: Dictionary): return example.get("id") == selected)
		_check(examples.size() == 1, "unknown case: " + selected)
	if interactive and (selected.is_empty() or DisplayServer.get_name() == "headless"):
		_check(false, "--interactive requires one --case and a graphical display")
		await _finish()
		return
	if not failures.is_empty():
		await _finish()
		return
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	driver = Driver.new(self, scene)
	var service := scene.find_child("SoundEffects", true, false)
	if service == null or not service.has_signal("sound_requested"):
		_check(false, "battle sound service is unavailable")
		await _finish()
		return
	service.sound_requested.connect(_record_sound)
	for example in examples:
		await _exercise(example, interactive)
	if interactive:
		print("Review complete. Close the game window when finished.")
		while true:
			await process_frame
	await _finish()


func _exercise(example: Dictionary, interactive: bool) -> void:
	var id: String = example.get("id", "")
	var state: Dictionary = example.get("state", {})
	if state.is_empty():
		_check(false, id + ": fixture failed: " + str(example.get("error", "empty state")))
		return
	scene.set("_opening_state", state.duplicate(true))
	scene.set("_actor_id", "")
	scene.call("_show_battle", state.duplicate(true))
	await process_frame
	await process_frame
	sounds.clear()
	var board: Control = scene.get("_board")
	if not interactive:
		board.set_process(false)
	var actor: String = example.actor
	var ability: String = example.ability
	var target: String = example.get("target", "")
	if not await driver.select_actor(actor) or not await driver.action(ability):
		_check(false, id + ": " + driver.error)
		return
	if not target.is_empty():
		if example.has("target_position"):
			# The union of the selected hero's legal targets must include the
			# fixture's intended destination.
			var marks: Array = (board.get("_overlay") as Dictionary).get("targets", [])
			_check(example.target_position in marks, id + ": intended target position is marked")
		if not await driver.target(target):
			_check(false, id + ": " + driver.error)
			return
	var planned: Dictionary = scene.get("_planned_state")
	var override: Dictionary = planned.get("overrides", {}).get(actor, {})
	_check(override.get("ability_id") == ability and str(override.get("target_id", "")) == target,
		id + ": ordinary controls stage the intended source action")
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	var effective: String = example.effective
	var matches: Array = plan.get("events", []).filter(func(event: Dictionary):
		var action: Dictionary = event.get("resolved_action", {})
		return action.get("unit_id") == actor and action.get("ability_id") == effective \
			and action.get("source_ability_id") == ability)
	_check(plan.get("valid", false) and matches.size() == 1,
		id + ": forecast contains actual effective action and source")
	_check(plan.get("events", []).any(func(event: Dictionary):
		return event.get("type") == "fitted_conversion" and event.get("unit_id") == actor \
			and event.get("ability_id") == effective and event.get("source_ability_id") == ability),
		id + ": fitting was actually consumed by conversion")
	_check(scene.battle_snapshot() == state and sounds.is_empty(),
		id + ": action preview is silent and leaves committed battle unchanged")
	var button := scene.find_child("Commit", true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, id + ": Commit unavailable")
		return
	if interactive:
		print("READY ", id, ": action staged. Review forecast and use Commit in the game.")
		await button.pressed
		await process_frame
		var playback = board.get("_playback")
		var beats: Array = []
		while board.action_playback_pending():
			if playback.has_method("presentation_beats"):
				beats.append_array(playback.presentation_beats().duplicate(true))
			await process_frame
		print("OBSERVED ", id, " beats=", JSON.stringify(beats), " sound_requests=", JSON.stringify(sounds))
	else:
		button.pressed.emit()
		board.set_process(false)
		_check(scene.battle_snapshot() == plan.get("result"), id + ": committed state equals forecast")
		var playback = board.get("_playback")
		var beats: Array = []
		var ticks := 0
		while board.action_playback_pending() and ticks < 3000:
			board.call("_process", 0.01)
			board.set_process(false)
			if playback.has_method("presentation_beats"):
				beats.append_array(playback.presentation_beats().duplicate(true))
			ticks += 1
		_check(not board.action_playback_pending(), id + ": committed playback drains")
		_check(playback.has_method("presentation_beats"), id + ": playback beat readout available")
		_check(beats.any(func(beat: Dictionary):
			return beat.get("kind") == "impact" and beat.get("actor_id") == actor \
				and beat.get("form_id") == effective and beat.get("source_ability_id") == ability \
				and beat.get("branch") == "converted"),
			id + ": committed playback crosses the actual converted impact")
		print("OBSERVED ", id, " beats=", JSON.stringify(beats), " sound_requests=", JSON.stringify(sounds))
		print("NOTE ", id, ": dispatch is not observed visual or audible output")


func _record_sound(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	sounds.append({"kind": kind, "unit_id": unit_id, "ability_id": ability_id,
		"cue_id": cue_id, "gain": gain})


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	if is_instance_valid(scene):
		for player in scene.find_children("*", "AudioStreamPlayer", true, false):
			player.stop()
		scene.queue_free()
		await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: available Smith playback scene cases")
	quit(0 if failures.is_empty() else 1)
