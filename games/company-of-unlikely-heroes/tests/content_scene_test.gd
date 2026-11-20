extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/content_scene_test.gd
# The child process exercises the same command-line content bootstrap as the game.
const MISSION := "ferryman"
var failures: Array[String] = []
var scene: Node
var controls: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--content-scene-child" not in OS.get_cmdline_user_args():
		_run_child()
		return
	scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	for name in ["ModeDirect", "ModeStanding", "Restart", "Preview", "Commit",
			"ActorSelect", "AbilitySelect", "TargetSelect", "PreviewText", "ObjectiveText", "RoundText", "BridgeBoard"]:
		var control := scene.find_child(name, true, false)
		if control == null:
			failures.append("Missing scene control: " + name)
		else:
			controls[name] = control
	if failures.is_empty():
		if "--permanent-regression" in OS.get_cmdline_user_args():
			await _exercise_permanent_regression()
		else:
			await _exercise_scene()
	_finish()


func _run_child() -> void:
	var file := FileAccess.open("res://content/ferryman.json", FileAccess.READ)
	if file == null:
		failures.append("Default authored catalog is missing")
		_finish()
		return
	var definitions: Variant = JSON.parse_string(file.get_as_text())
	if not definitions is Dictionary:
		failures.append("Default authored catalog is invalid JSON")
		_finish()
		return
	var data: Dictionary = definitions
	data["missions"][MISSION]["title"] = "A courier crossing"
	data["missions"][MISSION]["objective"]["subject"] = "passenger"
	data["missions"][MISSION]["objective"]["text"] = "Escort {subject_label} to {destination}; {hp}/{max_hp} at {position}"
	data["boards"]["bridge"]["locations"]["safe_bank"] = [6, 4]
	data["characters"]["courier"] = {"class": "civilian", "label": "Courier Sel"}
	data["characters"]["blast_knight"] = {
		"class": "knight", "label": "Spark Knight", "abilities": ["move", "wizard_blast"],
		"habits": {"order_cautious": "hold", "order_blast": "blast"}, "default_order": "order_cautious"
	}
	data["encounters"]["crossing"]["placements"] = [
		{"id": "knight", "character": "knight", "at": [4, 3]},
		{"id": "second_knight", "character": "blast_knight", "at": [6, 3]},
		{"id": "passenger", "character": "courier", "at": [0, 3]},
		{"id": "crate", "object": "crate", "at": [4, 2]},
		{"id": "second_crate", "object": "crate", "at": [5, 3]}
	]
	var fixture := "user://content_scene_fixture_%d.json" % OS.get_process_id()
	var output_file := FileAccess.open(fixture, FileAccess.WRITE)
	if output_file == null:
		failures.append("Cannot write temporary authored fixture")
		_finish()
		return
	output_file.store_string(JSON.stringify(data))
	output_file.close()
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/content_scene_test.gd", "--",
		"--content=" + ProjectSettings.globalize_path(fixture), "--mission=" + MISSION,
		"--content-scene-child"
	], output, true)
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture)) != OK:
		failures.append("Could not remove temporary authored fixture: " + fixture)
	for line in output:
		print(line)
	if exit_code != 0:
		failures.append("Authored scene child failed (exit %d)" % exit_code)
	output.clear()
	exit_code = OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/content_scene_test.gd", "--",
		"--mission=extra_knight", "--content-scene-child", "--permanent-regression"
	], output, true)
	for line in output:
		print(line)
	if exit_code != 0:
		failures.append("Permanent regression scene child failed (exit %d)" % exit_code)
	_finish()


func _exercise_permanent_regression() -> void:
	var initial: Dictionary = scene.get("_state").duplicate(true)
	_check(_entity(initial, "blast_knight").get("position") == Vector2i(0, 0), "Blast knight starts at A1")
	_check(_entity(initial, "near_crate").get("position") == Vector2i(1, 0), "Near crate starts at B1")
	_check(_entity(initial, "far_crate").get("position") == Vector2i(2, 2), "Far crate starts at C3")
	_check(initial.objective.destination == Vector2i(2, 0), "Regression exit is at C1")
	_check(controls["BridgeBoard"].get("_overlay").get("exit") == Vector2i(2, 0),
		"Board displays the regression exit")
	_check_shore(controls["BridgeBoard"].get("_overlay").get("safe", {}), 0)
	_check("C1" in str(controls["ObjectiveText"].text), "Objective displays the regression exit")
	var first_plan: Dictionary = scene.get("_plan")
	_check(_event_targets(first_plan, "near_crate"), "First forecast hits the B1 crate")
	_check(not _event_targets(first_plan, "far_crate"), "First forecast does not hit the C3 crate")
	_check(_entity(first_plan.get("result", {}), "near_crate").get("hp", 0) <
		_entity(initial, "near_crate").get("hp", 0), "First forecast damages the near crate")
	_check(_entity(first_plan.get("result", {}), "far_crate") == _entity(initial, "far_crate"),
		"First forecast leaves the far crate unchanged")
	_check(_same_state(scene.get("_state"), initial), "First forecast does not commit")
	await _press("ModeDirect")
	_check(scene.get("_state").get("manual_remaining") == 4, "Direct mode has four command slots")
	for hero in ["blast_knight", "knight", "healer", "wizard"]:
		_check(_has_id(controls["ActorSelect"], hero), "Direct mode offers " + hero)
	if await _select_id(controls["ActorSelect"], "blast_knight"):
		_check(_has_id(controls["AbilitySelect"], "wizard_blast"), "Blast knight has blast")
		_check(not _has_id(controls["AbilitySelect"], "knight_push"), "Blast knight does not have push")
	if await _select_id(controls["ActorSelect"], "knight"):
		_check(_has_id(controls["AbilitySelect"], "knight_push"), "Original knight retains push")
		_check(not _has_id(controls["AbilitySelect"], "wizard_blast"), "Original knight does not have blast")


func _exercise_scene() -> void:
	var initial: Dictionary = scene.get("_state").duplicate(true)
	_check(initial.objective.destination == Vector2i(6, 4), "CLI content must relocate the named exit")
	_check(_entity(initial, "passenger").get("position") == Vector2i(0, 3),
		"CLI content must instantiate the renamed subject")
	var objective: String = controls["ObjectiveText"].text
	_check("Courier Sel" in objective and "G5" in objective,
		"Objective must display authored subject label and relocated destination")
	var overlay: Dictionary = controls["BridgeBoard"].get("_overlay")
	_check(overlay.get("exit") == Vector2i(6, 4), "Board must mark the authored exit")
	_check_shore(overlay.get("safe", {}), 4)

	await _press("ModeDirect")
	var before: Dictionary = scene.get("_state").duplicate(true)
	if await _select_id(controls["ActorSelect"], "knight") and await _select_id(controls["AbilitySelect"], "knight_push"):
		var retained_forecast: Dictionary = {}
		for crate_id in ["crate", "second_crate"]:
			if not await _select_id(controls["TargetSelect"], crate_id):
				continue
			await _press("Preview")
			var plan: Dictionary = scene.get("_plan")
			_check(_entity(plan.get("result", {}), crate_id) != _entity(before, crate_id),
				"Forecast must act on selected " + crate_id)
			var pos: Vector2i = _entity(before, crate_id).get("position")
			var coordinate := "%s%d" % [char(65 + pos.x), pos.y + 1]
			_check(coordinate in str(controls["PreviewText"].text),
				"Forecast must distinguish selected crate by its location")
			_check(_same_state(scene.get("_state"), before), "Preview must not commit either crate selection")
			if crate_id == "second_crate":
				retained_forecast = plan.get("result", {}).duplicate(true)
		await _press("Commit")
		_check(not retained_forecast.is_empty() and _same_state(scene.get("_state"), retained_forecast),
			"Commit must match the retained second-crate forecast")
		await _press("Restart")
		_check(_same_state(scene.get("_state"), before), "Restart must restore authored direct encounter")

	if await _select_id(controls["ActorSelect"], "second_knight"):
		_check(_has_id(controls["AbilitySelect"], "wizard_blast"), "Second knight must expose its authored blast")
		_check(not _has_id(controls["AbilitySelect"], "knight_push"), "Second knight must not inherit the other knight's push")
		if await _select_id(controls["AbilitySelect"], "wizard_blast"):
			await _press("Preview")
			_check(_event_targets(scene.get("_plan"), "second_crate"), "Second knight direct blast must forecast its nearby crate")
			_check(_same_state(scene.get("_state"), before), "Second knight preview must not mutate committed state")

	await _press("ModeStanding")
	var standing_before: Dictionary = scene.get("_state").duplicate(true)
	var first_order := _order_picker("knight")
	var second_order := _order_picker("second_knight")
	_check(first_order != null and second_order != null and first_order != second_order,
		"Each knight must have an independent visible order control")
	if first_order != null and second_order != null:
		_check(_has_id(second_order, "order_blast") and not _has_id(first_order, "order_blast"),
			"Only the authored knight gets its blast habit")
		if await _select_id(second_order, "order_blast"):
			var ordered: Dictionary = scene.get("_state")
			_check(ordered.get("orders", {}).get("second_knight") == "order_blast",
				"Second knight order control must update its own order")
			_check(ordered.get("orders", {}).get("knight") == standing_before.get("orders", {}).get("knight"),
				"Changing second knight order must not change the first knight")
			_check(_event_targets(scene.get("_plan"), "second_crate"),
				"Standing forecast must show the authored habit affecting its nearby crate")
			var standing_forecast: Dictionary = scene.get("_plan").get("result", {}).duplicate(true)
			var predicted_crate := _entity(standing_forecast, "second_crate")
			_check(predicted_crate.get("hp", 0) < _entity(ordered, "second_crate").get("hp", 0),
				"Standing blast must predict damage to the second crate")
			await _press("Commit")
			_check(_same_state(scene.get("_state"), standing_forecast)
				and _entity(scene.get("_state"), "second_crate") == predicted_crate,
				"Standing commit must apply the predicted crate damage")
			await _press("Restart")
			_check(_same_state(scene.get("_state"), standing_before), "Restart must restore authored standing orders and placements")


func _check_shore(safe: Dictionary, first_x: int) -> void:
	_check(safe.size() == 15, "Shore tint covers exactly one 3 by 5 bank")
	for x in range(7):
		for y in range(5):
			_check(safe.has(Vector2i(x, y)) == (x >= first_x and x < first_x + 3),
				"Shore tint matches authored bank at %s" % Vector2i(x, y))


func _same_state(left: Dictionary, right: Dictionary) -> bool:
	if not left.has("catalog") or not right.has("catalog"):
		return false
	var left_content: Dictionary = left["catalog"].defs
	var right_content: Dictionary = right["catalog"].defs
	var left_state := left.duplicate()
	var right_state := right.duplicate()
	left_state.erase("catalog")
	right_state.erase("catalog")
	return left_content == right_content and left_state == right_state


func _event_targets(plan: Dictionary, id: String) -> bool:
	for event in plan.get("events", []):
		if event.get("target_id", "") == id:
			return true
	return false


func _entity(state: Dictionary, id: String) -> Dictionary:
	for entity in state.get("units", []) + state.get("obstacles", []):
		if entity.get("id", "") == id:
			return entity
	return {}


func _order_picker(actor_id: String) -> OptionButton:
	for picker in scene.find_children("*", "OptionButton", true, false):
		if picker.get_meta("actor_id", "") == actor_id:
			return picker
	return null


func _has_id(picker: OptionButton, id: String) -> bool:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == id:
			return true
	return false


func _select_id(picker: OptionButton, id: String) -> bool:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == id:
			if picker.disabled or picker.is_item_disabled(index) or not picker.is_visible_in_tree():
				failures.append("Choice %s is not selectable" % id)
				return false
			picker.select(index)
			picker.item_selected.emit(index)
			await process_frame
			return true
	failures.append("Missing selectable choice: " + id)
	return false


func _press(name: String) -> void:
	var button: BaseButton = controls[name]
	if button.disabled or not button.is_visible_in_tree():
		failures.append(name + " must be visible and enabled")
		return
	button.pressed.emit()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: authored encounter scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
