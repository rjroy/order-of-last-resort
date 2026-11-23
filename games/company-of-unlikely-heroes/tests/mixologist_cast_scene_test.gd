extends SceneTree

## Graphical: godot --path games/company-of-unlikely-heroes --script res://tests/mixologist_cast_scene_test.gd
## Optional: -- --capture-dir=/absolute/ignored/directory
## Launches the stock mission with an explicit party and commits real player commands.
const Driver = preload("res://tests/support/storybook_driver.gd")
var rules = preload("res://rules.gd").new()
var scene: Node
var failures: Array[String] = []
var capture_dir := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	call_deferred("_run")


func _run() -> void:
	if not capture_dir.is_empty() and DisplayServer.get_name() == "headless":
		_check(false, "Captures require a graphical display")
		_finish()
		return
	for action in ["potion", "acid"]:
		if await _launch_stock():
			await _exercise(action)
	_finish()


func _launch_stock() -> bool:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray([
		"--mission=goblin_mob", "--party=alchemist,healer,wizard"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var state: Dictionary = scene.battle_snapshot()
	return _check(scene.current_screen() == "battle" and state.get("mission_id") == "goblin_mob"
		and state.get("party") == ["alchemist", "healer", "wizard"],
		"Stock Goblin Mob launches with the specified Mixologist, Healer and Wizard")


func _exercise(action: String) -> void:
	var board := scene.find_child("BridgeBoard", true, false)
	if not _check(board != null, "Primary battle page contains the board"):
		return
	var art = board.get("_cast")
	var ready = art.clip_for("alchemist", "ready")
	var healer = art.clip_for("healer", "ready")
	var potion = art.clip_for("alchemist", "potion")
	var acid = art.clip_for("alchemist", "acid")
	var units: Array = board.get("_units")
	var mix := units.filter(func(unit): return unit.get("id") == "alchemist")
	_check(mix.size() == 1 and mix[0].get("cast_key") == "alchemist",
		"Deployed Mixologist resolves to her own cast key")
	_check(ready != null and healer != null and ready.path != healer.path,
		"Deployed Mixologist Ready uses her own texture, not Healer")
	_check(potion != null and acid != null and potion.frames != acid.frames
		and potion.total_ms > 0 and acid.total_ms > 0 and not potion.loop and not acid.loop,
		"Potion and acid have distinct timed non-looping frame sequences")
	await _capture(action + "_ready")
	var driver = Driver.new(self, scene)
	var ability := "alchemist_" + action
	# Enemies begin out of acid range; let the unmodified encounter advance normally.
	for round_number in range(4):
		var choices: Array = rules.targets(scene.battle_snapshot(), "alchemist", ability)
		if not choices.is_empty():
			break
		if not await _press("Commit"):
			return
	var choices: Array = rules.targets(scene.battle_snapshot(), "alchemist", ability)
	if not _check(not choices.is_empty(), "Stock battle offers a legal " + action + " target"):
		return
	var target := str(choices[0].id)
	var before: Dictionary = scene.battle_snapshot()
	if not await driver.command("alchemist", ability, target):
		_check(false, "Stage stock command: " + driver.error)
		return
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	_check(scene.battle_snapshot() == before, "Forecast does not commit the action")
	_check(not (board.call("action_playback_snapshot") as Array).any(
		func(cue): return cue.get("unit_id") == "alchemist" and cue.get("clip") == action),
		"Forecast does not play the selected action")
	_check((plan.get("events", []) as Array).any(func(event):
		return (event.get("resolved_action", {}).get("unit_id") == "alchemist"
			and event.get("resolved_action", {}).get("ability_id") == ability)),
		"Round contains the real resolved Mixologist action")
	if not await _press("Commit"):
		return
	_check(scene.battle_snapshot() == plan.get("result"), "Committed state matches forecast")
	var entries: Array = board.get("_playback").active()
	var matching := entries.filter(func(entry):
		return entry.cue.get("unit_id") == "alchemist" and entry.cue.get("clip") == action)
	_check(matching.size() == 1, "Committed " + action + " activates exactly one Mixologist clip")
	_check(entries.all(func(entry): return (entry.cue.get("cast_key") != "alchemist"
		or entry.cue.get("unit_id") == "alchemist")), "Other heroes never play Mixologist clips")
	if matching.is_empty():
		return
	var entry = matching[0]
	var expected = potion if action == "potion" else acid
	_check(entry.clip == expected and entry.duration_ms >= expected.total_ms,
		"Playback uses the correct complete timed sheet")
	await _capture_action(action, entry)
	await create_timer(entry.duration_ms / 1000.0 + 0.25).timeout
	_check(not (board.call("action_playback_snapshot") as Array).any(
		func(cue): return cue.get("unit_id") == "alchemist"),
		"Mixologist action finishes and returns to Ready")
	units = board.get("_units")
	mix = units.filter(func(unit): return unit.get("id") == "alchemist")
	_check(mix.size() == 1 and mix[0].get("cast_key") == "alchemist"
		and art.clip_for("alchemist", "ready") == ready,
		"Finished action retains her own Ready clip")
	await _capture(action + "_returned")


func _capture(name: String) -> void:
	if capture_dir.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))
	_check(error == OK, "Capture saved: " + name)


func _capture_action(action: String, entry) -> void:
	if capture_dir.is_empty():
		return
	# The sampled source frames are the offer and the acid release, respectively.
	var source_frame := 17 if action == "potion" else 18
	var capture_ms: float = entry.clip.time_at_source_frame(source_frame) + 25.0
	while entry.elapsed_ms < capture_ms:
		await process_frame
	await RenderingServer.frame_post_draw
	var frame_index: int = entry.clip.frame_index(entry.elapsed_ms)
	if not _check(entry.clip.source_frames[frame_index] == source_frame,
			"Capture reached %s source frame %d while the action was live" % [action, source_frame]):
		return
	var error := root.get_texture().get_image().save_png(capture_dir.path_join(action + "_action.png"))
	_check(error == OK, "Active gesture capture saved: " + action)


func _press(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if not _check(button != null and button.is_visible_in_tree() and not button.disabled,
			name + " is available"):
		return false
	button.pressed.emit()
	await process_frame
	return true


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures.append(message)
	return ok


func _finish() -> void:
	if failures.is_empty():
		print("PASS: stock mission Mixologist cast")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
