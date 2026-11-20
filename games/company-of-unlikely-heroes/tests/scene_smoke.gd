extends SceneTree

# Run: godot --path games/company-of-unlikely-heroes --script res://tests/scene_smoke.gd
# Add -- --capture=/absolute/path.png to capture the actual game viewport.
var failures: Array[String] = []
var scene: Node
var controls: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_path.is_empty() or not ResourceLoader.exists(main_path):
		failures.append("Missing behavior: project has no playable main scene")
		_finish()
		return
	var packed = load(main_path)
	if not packed is PackedScene:
		failures.append("Missing behavior: project main scene is not a playable PackedScene")
		_finish()
		return
	scene = packed.instantiate()
	if scene == null:
		failures.append("Missing behavior: project main scene could not be instantiated")
		_finish()
		return
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	for name in ["ModeHybrid", "ModeDirect", "ModeStanding", "Restart", "Preview", "Commit"]:
		_require_control(name, BaseButton)
	for name in ["ActorSelect", "AbilitySelect", "TargetSelect"]:
		_require_control(name, OptionButton)
	for name in ["StatusText", "RoundText", "PreviewText"]:
		var node := scene.find_child(name, true, false)
		if node == null or not (node is Label or node is RichTextLabel or node is TextEdit):
			failures.append("Missing behavior: visible text control " + name)
		else:
			controls[name] = node
			_check(node.is_visible_in_tree(), name + " must be visible")
	if not failures.is_empty():
		_finish()
		return

	var initial_status := _text("StatusText")
	var initial_round := _text("RoundText")
	_check(not initial_status.strip_edges().is_empty(), "Hybrid entry must display status")
	_check(not initial_round.strip_edges().is_empty(), "Hybrid entry must display the round")

	await _press("ModeDirect")
	var direct_status := _text("StatusText")
	_check(not direct_status.strip_edges().is_empty() and direct_status != initial_status,
		"Direct mode must visibly differ from hybrid")
	await _press("ModeStanding")
	var standing_status := _text("StatusText")
	_check(not standing_status.strip_edges().is_empty() and standing_status != direct_status
		and standing_status != initial_status, "Standing mode must visibly differ from other modes")
	await _press("ModeHybrid")
	_check(_text("StatusText") == initial_status and _text("RoundText") == initial_round,
		"Hybrid mode must restart at its initial state")

	var actors: OptionButton = controls["ActorSelect"]
	var abilities: OptionButton = controls["AbilitySelect"]
	var found_editable := false
	for actor_index in range(actors.item_count):
		await _select(actors, actor_index)
		if abilities.item_count >= 2:
			found_editable = true
			break
	_check(found_editable, "A selectable actor must offer at least two abilities")
	if found_editable:
		await _select(abilities, 0)
		await _press("Preview")
		var first_preview := _text("PreviewText")
		_check(not first_preview.strip_edges().is_empty(), "Preview must display the planned action")
		_check(_text("RoundText") == initial_round, "Preview must not advance the round")
		await _select(abilities, 1)
		await _press("Preview")
		var edited_preview := _text("PreviewText")
		_check(not edited_preview.strip_edges().is_empty() and edited_preview != first_preview,
			"Editing the ability must change the visible preview")
		_check(_text("RoundText") == initial_round, "Editing a preview must not advance the round")
		await _press("Commit")
		_check(_text("RoundText") != initial_round, "Committing the preview must advance the round")
		await _press("Restart")
		_check(_text("RoundText") == initial_round and _text("StatusText") == initial_status,
			"Restart must restore the initial hybrid state")

	await _test_direct_follow_up_move()
	await _press("ModeHybrid")

	var capture_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
	if not capture_path.is_empty():
		if not capture_path.is_absolute_path():
			failures.append("Capture path must be absolute")
		else:
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			if image == null or image.is_empty():
				failures.append("Could not capture the game viewport")
			else:
				var error := image.save_png(capture_path)
				_check(error == OK, "Could not save viewport capture: %s" % error)
	_finish()


func _test_direct_follow_up_move() -> void:
	await _press("ModeDirect")
	var initial: Dictionary = scene.get("_state").duplicate(true)
	var initial_round := _text("RoundText")
	if not await _select_id("ActorSelect", "knight"):
		return
	if not await _select_id("AbilitySelect", "knight_push"):
		return
	if not await _select_id("TargetSelect", "civilian"):
		return
	await _press("Preview")
	_check("Knight pushes ferryman to B4." in _text("PreviewText"),
		"Direct forecast must show the knight pushing the ferryman from B3 to B4")
	if not await _select_id("ActorSelect", "healer"):
		return
	if not await _select_id("AbilitySelect", "move"):
		return
	if not await _select_id("TargetSelect", "1,2"):
		return
	await _press("Preview")
	_check("Healer moves to B3." in _text("PreviewText"),
		"Direct forecast must show the healer successfully moving into the vacated B3")
	_check(scene.get("_state") == initial and _text("RoundText") == initial_round,
		"Previewing the chained move must not alter the committed initial state")


func _select_id(name: String, id: String) -> bool:
	var button: OptionButton = controls[name]
	for index in range(button.item_count):
		if str(button.get_item_metadata(index)) == id:
			if button.disabled or not button.is_visible_in_tree() or button.is_item_disabled(index):
				failures.append("%s choice %s must be visible and selectable" % [name, id])
				return false
			await _select(button, index)
			return true
	failures.append("%s must offer selectable choice %s" % [name, id])
	return false


func _require_control(name: String, type: Variant) -> void:
	var node := scene.find_child(name, true, false)
	if node == null or not is_instance_of(node, type):
		failures.append("Missing behavior: control " + name)
		return
	controls[name] = node
	_check(node.is_visible_in_tree(), name + " must be visible")


func _text(name: String) -> String:
	return str(controls[name].text)


func _press(name: String) -> void:
	var button: BaseButton = controls[name]
	if button.disabled or not button.is_visible_in_tree():
		failures.append(name + " must be visible and enabled when used")
		return
	button.pressed.emit()
	await process_frame


func _select(button: OptionButton, index: int) -> void:
	if button.disabled or not button.is_visible_in_tree() or button.is_item_disabled(index):
		failures.append("%s option %d must be selectable" % [button.name, index])
		return
	button.select(index)
	button.item_selected.emit(index)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: company scene smoke")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
