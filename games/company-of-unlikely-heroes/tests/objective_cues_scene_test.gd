extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/objective_cues_scene_test.gd
# Fixed missions use the same public launch path as standalone play.
var rules = preload("res://rules.gd").new()
var failures: Array[String] = []
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _launch("wrong_side_of_the_door")
	if scene != null and scene.has_method("current_screen") and scene.current_screen() == "battle":
		_check_marker("plate", "plate")
	await _launch("bridge_is_out")
	if scene != null and scene.has_method("current_screen") and scene.current_screen() == "battle":
		_check_bridge_marker()
		await _check_bridge_forecast()
	if failures.is_empty():
		print("PASS: objective cues scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _launch(mission: String) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	if not scene.has_method("configure_launch"):
		_check(false, mission + " main scene exposes launch configuration")
		scene.free()
		scene = null
		return
	scene.configure_launch(PackedStringArray(["--mission=" + mission]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", mission + " launches into battle")


func _check_marker(field: String, expected_kind: String) -> void:
	var state: Dictionary = scene.battle_snapshot()
	var cell: Vector2i = state.objective[field]
	_check_cell_marker(state, cell, expected_kind)


func _check_bridge_marker() -> void:
	var state: Dictionary = scene.battle_snapshot()
	var collapses: Array = state.objective.get("collapses", [])
	if collapses.is_empty() or collapses[0].get("cells", []).is_empty():
		_check(false, "Bridge mission has a scheduled collapse cell")
		return
	var cell: Vector2i = collapses[0].cells[0]
	var markers: Dictionary = rules.objective_markers(state)
	if not markers.has(cell):
		_check(false, "Scheduled bridge cell has an objective marker")
		return
	_check_cell_marker(state, cell, str(markers[cell].get("kind", "")))


func _check_cell_marker(state: Dictionary, cell: Vector2i, expected_kind: String) -> void:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	var markers_node := scene.find_child("ObjectiveMarkers", true, false) as Control
	var legend := scene.find_child("MapLegend", true, false) as Control
	var inspection := scene.find_child("TileInspection", true, false) as Label
	if board == null or markers_node == null or legend == null or inspection == null:
		_check(false, "Board exposes visible markers, legend and tile inspection")
		return
	var markers: Dictionary = rules.objective_markers(state)
	var marker: Dictionary = markers.get(cell, {})
	_check(not expected_kind.is_empty() and marker.get("kind") == expected_kind,
		"Named objective cell has the expected marker kind")
	_check(markers_node.is_visible_in_tree() and markers_node.get_meta("markers", {}) == markers,
		"Visible board marker layer displays the current objective markers")
	_check(legend.is_visible_in_tree() and expected_kind in legend.get_meta("objective_kinds", PackedStringArray()),
		"Visible legend identifies the objective marker")
	board.cell_hovered.emit(cell)
	var description := str(inspection.tooltip_text)
	_check(inspection.is_visible_in_tree() and not str(marker.get("label", "")).is_empty()
		and str(marker.get("label", "")).to_lower() in description.to_lower(),
		"Pre-action tile inspection describes the named objective marker")


func _check_bridge_forecast() -> void:
	var forecast := scene.find_child("ObjectiveForecast", true, false) as Label
	var progress := scene.find_child("ObjectiveProgress", true, false) as Label
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if forecast == null or progress == null or commit == null:
		_check(false, "Battle exposes objective progress, forecast and commit")
		return
	var found_change := false
	# Advance only until a forecast predicts changed objective progress or an outcome.
	for attempt in range(6):
		var before: Dictionary = scene.battle_snapshot()
		var plan: Dictionary = rules.preview_round(before)
		if not plan.get("valid", false):
			_check(false, "Bridge forecast is valid")
			return
		var result: Dictionary = plan.get("result", {})
		var current_text := str(rules.objective_progress(before).get("text", ""))
		var predicted_text := str(rules.objective_progress(result).get("text", ""))
		var outcome := str(result.get("outcome", ""))
		if (not predicted_text.is_empty() and predicted_text != current_text) or outcome in ["victory", "defeat"]:
			found_change = true
			_check(progress.is_visible_in_tree() and current_text in progress.text,
				"Current objective progress remains visible before commitment")
			_check(forecast.is_visible_in_tree() and (
				(not predicted_text.is_empty() and predicted_text in forecast.text)
				or (outcome in ["victory", "defeat"] and forecast.get_meta("outcome", "") == outcome)),
				"Visible forecast describes the changed progress or terminal outcome")
			_check(scene.battle_snapshot() == before, "Forecast does not commit the round")
			break
		if commit.disabled or not commit.is_visible_in_tree():
			break
		commit.pressed.emit()
		await process_frame
		if scene.current_screen() != "battle":
			break
	_check(found_change, "Bridge opening produces an observable changed objective forecast")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
