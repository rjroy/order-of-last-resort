extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/laughter_presentation_test.gd
# Test-owned pending statuses exercise the actual editor and debrief summary.
var failures: Array[String] = []
var scene: Node
var rules = preload("res://rules.gd").new()
var adventure = preload("res://adventure.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var defs: Dictionary = preload("res://content/catalog.gd").read_default().duplicate(true)
	defs.statuses.laughter = {"label": "Laughing; skips next turn", "handler": "skip_action",
		"expiry": "consume_action", "params": {"immunity_rounds": 1,
			"immune_label": "Immune to laughter", "skip_event": "laugh_skip"}}
	defs.statuses.knockdown = {"label": "Down", "handler": "skip_action",
		"expiry": "consume_action", "params": {}}
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=ferryman"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", "Fixture launches battle")
	if scene.current_screen() != "battle":
		_finish()
		return
	var state: Dictionary = rules.new_game(defs, "ferryman")
	var hero := _unit(state, "healer")
	_check(not hero.is_empty() and hero.get("hp", 0) > 0, "Fixture has a living Healer")
	if hero.is_empty():
		_finish()
		return
	hero.statuses = {"laughter": {"source_id": "enemy_bard"}}
	await _show_editor(state)
	_check(not rules.can_act(state, "healer"), "Pending laughter still prevents the hero's action")
	_check((_node("Preview") as BaseButton).disabled, "Pending laughter disables command preview")
	var target := _node("TargetSelect") as OptionButton
	var help := str(_node("ActionHelp").text).to_lower()
	_check(not target.get_item_text(0).to_lower().contains("knock")
		and not help.contains("knock") and not help.contains("getting up") and not help.contains("is down"),
		"Pending laughter is not described as knockdown or getting up")

	var summary: Dictionary = adventure._summarize_mission(["healer"], state)
	_check(not summary.get("heroes_by_id", {}).get("healer", {}).get("knocked_down", true),
		"Debrief does not report pending laughter as recovered knockdown")

	hero.statuses = {"knockdown": {"source_id": "enemy_bard"}}
	await _show_editor(state)
	target = _node("TargetSelect") as OptionButton
	help = str(_node("ActionHelp").text).to_lower()
	_check(not rules.can_act(state, "healer") and (_node("Preview") as BaseButton).disabled,
		"Actual knockdown still prevents a direct action")
	_check(target.get_item_text(0).to_lower().contains("knock")
		and (help.contains("getting up") or help.contains("knock")),
		"Actual knockdown is still described as knockdown or getting up")
	summary = adventure._summarize_mission(["healer"], state)
	_check(summary.get("heroes_by_id", {}).get("healer", {}).get("knocked_down", false),
		"Debrief still reports an actual knockdown")
	_finish()


func _show_editor(state: Dictionary) -> void:
	scene.set("_state", state.duplicate(true))
	scene.set("_planned_state", state.duplicate(true))
	scene.call("_sync_actors")
	scene.call("_sync_command")
	scene.call("_refresh", true)
	await process_frame
	await _select_id("ActorSelect", "healer")
	await _select_id("AbilitySelect", "move")


func _select_id(name: String, id: String) -> void:
	var picker := _node(name) as OptionButton
	if picker != null:
		for index in picker.item_count:
			if str(picker.get_item_metadata(index)) == id:
				picker.select(index)
				picker.item_selected.emit(index)
				await process_frame
				return
	_check(false, name + " offers " + id)


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: laughter presentation")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
