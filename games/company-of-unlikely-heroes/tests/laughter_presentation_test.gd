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
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", "Fixture launches battle")
	if scene.current_screen() != "battle":
		_finish()
		return
	var state: Dictionary = rules.open_mission(defs, "goblin_mob", ["necromancer", "healer", "bard"])
	var hero := _unit(state, "healer")
	_check(not hero.is_empty() and hero.get("hp", 0) > 0, "Fixture has a living Healer")
	if hero.is_empty():
		_finish()
		return
	hero.statuses = {"laughter": {"source_id": "enemy_bard"}}
	await _show_editor(state)
	_check(not rules.can_act(state, "healer"), "Pending laughter still prevents the hero's action")
	_check(_actions_unavailable(), "Pending laughter disables the Healer's direct actions")
	var status := _visible_text()
	_check("laugh" in status and ("skip" in status or "cannot act" in status or "can't act" in status),
		"Player can see that laughter makes the Healer lose an action")
	_check(not status.contains("knock")
		and not status.contains("getting up") and not status.contains("is down"),
		"Pending laughter is not described as knockdown or getting up")

	var summary: Dictionary = adventure._summarize_mission(["healer"], state)
	_check(not summary.get("heroes_by_id", {}).get("healer", {}).get("knocked_down", true),
		"Debrief does not report pending laughter as recovered knockdown")

	hero.statuses = {"knockdown": {"source_id": "enemy_bard"}}
	await _show_editor(state)
	status = _visible_text()
	_check(not rules.can_act(state, "healer") and _actions_unavailable(),
		"Actual knockdown still prevents a direct action")
	_check(status.contains("getting up") or status.contains("knock"),
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
	scene.call("_refresh")
	await process_frame
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	_check(await driver.select_actor("healer"), "Healer can be selected: " + driver.error)
	var board := _node("BridgeBoard")
	board.cell_hovered.emit(_unit(state, "healer").position)
	await process_frame


func _actions_unavailable() -> bool:
	var menu := _node("Actions") as MenuButton
	if menu == null or not menu.is_visible_in_tree():
		return false
	if menu.disabled:
		return true
	var popup := menu.get_popup()
	if popup.item_count == 0:
		return false
	for index in popup.item_count:
		if not popup.is_item_disabled(index):
			return false
	return true


func _visible_text() -> String:
	var text := PackedStringArray()
	for control in scene.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and (control is Label or control is BaseButton):
			text.append(str(control.text).to_lower())
	return "\n".join(text)


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
