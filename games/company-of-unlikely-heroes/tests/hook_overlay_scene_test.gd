extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/hook_overlay_scene_test.gd
var scene: Node
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=harpoon_squad"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", "Squad mission opens in battle")
	var opening: Dictionary = scene.get("_plan")
	_check(_has_event(opening.get("events", []), "pull", "hookhand", "healer", Vector2i(2, 2)),
		"Standing round forecasts Hookhand pulling Healer from B3 to C3")
	await _press("Commit")
	var state: Dictionary = scene.battle_snapshot()
	_check(_position(state, "healer") == Vector2i(2, 2), "First commit places Healer at C3")
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await driver.command("healer", "move", "2,1"):
		_check(false, "Book offers Healer's move: " + driver.error)
		_finish()
		return
	var plan: Dictionary = scene.get("_plan")
	_check(plan.get("valid", false), "Second round direct Move forecasts")
	_check(_has_event(plan.get("events", []), "move", "healer", "", Vector2i(2, 1)),
		"Forecast records Healer moving from C3 to C2")
	_check(_has_event(plan.get("events", []), "pull", "hookhand", "healer", Vector2i(3, 1)),
		"Forecast records Hookhand pulling Healer from C2 to D2")
	var board: Node = scene.find_child("BridgeBoard", true, false)
	_check(board != null, "Battle exposes the rendered board")
	if board != null:
		var overlay: Dictionary = board.get("_overlay")
		var paths: Array = overlay.get("paths", [])
		_check([Vector2i(2, 2), Vector2i(2, 1)] in paths, "Overlay draws Healer's real C3 to C2 move")
		_check(board.is_visible_in_tree() and [Vector2i(2, 1), Vector2i(3, 1)] in paths,
			"Visible board overlay draws Hookhand's later C2 to D2 pull")
		_check([Vector2i(2, 2), Vector2i(3, 1)] not in paths, "Overlay does not draw a diagonal C3 to D2 shortcut")
		var ink := scene.find_child("StorybookInk", true, false) as Control
		_check(ink != null and ink.is_visible_in_tree(), "Manual move pencil ink is visible")
		if ink != null:
			var cues: Dictionary = ink.get("_cues")
			var move: Dictionary = cues.get("move", {})
			_check(move.get("from") == Vector2i(2, 2) and move.get("to") == Vector2i(2, 1),
				"Manual pencil path shows C3 to C2, not the final pulled position: " + str(move))
			_check(cues.get("context_cell") == Vector2i(2, 1) and cues.get("context_text") == "Move to C2",
				"Manual move tag says Move to C2 at C2: %s / %s" % [
					str(cues.get("context_cell")), str(cues.get("context_text"))])
	_finish()


func _has_event(events: Array, kind: String, actor: String, target: String, position: Vector2i) -> bool:
	for event in events:
		if event.get("type") == kind and event.get("unit_id") == actor \
				and (target.is_empty() or event.get("target_id") == target) \
				and event.get("position") == position:
			return true
	return false


func _position(state: Dictionary, id: String) -> Variant:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit.get("position")
	return null


func _press(name: String) -> void:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is visible and enabled")
		return
	button.pressed.emit()
	await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: hook overlay scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
