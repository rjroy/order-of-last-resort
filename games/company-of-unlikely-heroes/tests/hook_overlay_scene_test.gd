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
	if not await _select("ActorSelect", "healer") \
			or not await _select("AbilitySelect", "move") \
			or not await _select("TargetSelect", "2,1"):
		_finish()
		return
	await _press("Preview")
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
		_check([Vector2i(2, 1), Vector2i(3, 1)] in paths, "Overlay draws Hookhand's real C2 to D2 pull")
		_check([Vector2i(2, 2), Vector2i(3, 1)] not in paths, "Overlay does not draw a diagonal C3 to D2 shortcut")
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


func _select(name: String, id: String) -> bool:
	var picker := scene.find_child(name, true, false) as OptionButton
	if picker != null:
		for i in picker.item_count:
			if str(picker.get_item_metadata(i)) == id and not picker.is_item_disabled(i):
				picker.select(i)
				picker.item_selected.emit(i)
				await process_frame
				return true
	_check(false, name + " offers " + id)
	return false


func _press(name: String) -> void:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled:
		_check(false, name + " is enabled")
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
