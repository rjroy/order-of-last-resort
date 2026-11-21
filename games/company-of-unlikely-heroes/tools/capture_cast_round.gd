extends SceneTree
## Capture the real seeded practice battle, not an art fixture.
## From the repository root, with a graphical display:
##   godot --fixed-fps 15 --path games/company-of-unlikely-heroes \
##     --script res://tools/capture_cast_round.gd -- --output=/absolute/empty/directory
##   ffmpeg -framerate 15 -i /absolute/empty/directory/frame-%04d.png \
##     -c:v libx264 -pix_fmt yuv420p /absolute/empty/directory/cast-round.mp4
## Use a fresh directory under .lore/local/. Preview PNGs are also saved separately.

const FPS := 15
var scene: Node
var capture_viewport: SubViewport
var output := ""
var frame_number := 0
var failure := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			if not output.is_empty():
				_fail("Specify --output only once.")
				_finish()
				return
			output = arg.trim_prefix("--output=")
	if output.is_empty() or not output.is_absolute_path():
		_fail("Supply --output=/absolute/empty/directory.")
		_finish()
		return
	if DisplayServer.get_name() == "headless":
		_fail("Capture needs a graphical renderer, not --headless.")
		_finish()
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_fail("Cannot create output directory: " + output)
		_finish()
		return
	var directory := DirAccess.open(output)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_fail("Output directory must be empty: " + output)
		_finish()
		return
	# An offscreen viewport fixes the pixel size even on scaled desktop displays.
	capture_viewport = SubViewport.new()
	capture_viewport.size = Vector2i(1280, 820)
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=necromancer_wave"]))
	# This fixed mission does not use the guild profile, but isolate it defensively.
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	capture_viewport.add_child(scene)
	await process_frame
	await process_frame
	if scene.current_screen() != "battle":
		_fail("The fixed practice mission did not launch.")
		_finish()
		return
	var board := scene.find_child("BridgeBoard", true, false)
	if board == null or not board.has_method("action_playback_snapshot"):
		_fail("Committed cast playback is not available in this runtime.")
		_finish()
		return
	if not await _round(board, "raise_dead", "fallen_raider", "raise-dead-preview.png"):
		_finish()
		return
	if not await _round(board, "summon_skeleton", "2,1", "skeleton-preview.png"):
		_finish()
		return
	print("Captured %d frames at %d fps in %s" % [frame_number, FPS, output])
	_finish()


func _round(board: Node, ability: String, target: String, preview_name: String) -> bool:
	var before: Dictionary = scene.battle_snapshot()
	if not await _select("ActorSelect", "necromancer") \
			or not await _select("AbilitySelect", ability) \
			or not await _select("TargetSelect", target) \
			or not await _press("Preview"):
		return false
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	if scene.battle_snapshot() != before or not plan.get("valid", false):
		return _fail("Preview mutated the battle or was invalid: " + ability)
	if not board.action_playback_snapshot().is_empty():
		return _fail("Preview unexpectedly started committed action playback.")
	if not await _frames(24, preview_name):
		return false
	if not await _press("Commit"):
		return false
	if scene.battle_snapshot() != plan.get("result"):
		return _fail("Committed battle differs from the preview: " + ability)
	var found := false
	for cue in board.action_playback_snapshot():
		if cue.get("unit_id") == "necromancer" and cue.get("clip") == ability:
			found = true
	if not found:
		return _fail("Committed cast cue missing: " + ability)
	return await _frames(75)


func _select(node_name: String, id: String) -> bool:
	var picker := scene.find_child(node_name, true, false) as OptionButton
	if picker != null and picker.is_visible_in_tree() and not picker.disabled:
		for i in picker.item_count:
			if str(picker.get_item_metadata(i)) == id and not picker.is_item_disabled(i):
				picker.select(i)
				picker.item_selected.emit(i)
				await process_frame
				return true
	return _fail("%s does not offer %s." % [node_name, id])


func _press(node_name: String) -> bool:
	var button := scene.find_child(node_name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		return _fail(node_name + " is not available.")
	button.pressed.emit()
	await process_frame
	return true


func _frames(count: int, still_name := "") -> bool:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw
		var image := capture_viewport.get_texture().get_image()
		if image == null or image.is_empty():
			return _fail("Could not capture the rendered viewport.")
		if image.get_size() != Vector2i(1280, 820):
			return _fail("Viewport is %s, expected 1280x820." % image.get_size())
		if image.save_png(output.path_join("frame-%04d.png" % frame_number)) != OK:
			return _fail("Could not write frame %d." % frame_number)
		if i == 0 and not still_name.is_empty() and image.save_png(output.path_join(still_name)) != OK:
			return _fail("Could not write " + still_name)
		frame_number += 1
	return true


func _fail(message: String) -> bool:
	failure = message
	return false


func _finish() -> void:
	if not failure.is_empty():
		push_error(failure)
	quit(0 if failure.is_empty() else 1)
