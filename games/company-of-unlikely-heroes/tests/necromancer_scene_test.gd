extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/necromancer_scene_test.gd
# This exercises the documented fixed mission through the actual battle controls.
var failures: Array[String] = []
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default()
	_check(defs.get("encounters", {}).get("necromancer_practice", {}).get("seed") == 2,
		"Practice fixture retains its documented deterministic seed")
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=necromancer_wave"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if scene.current_screen() != "battle":
		_check(false, "Practice mission launches into battle")
		_finish()
		return

	var initial: Dictionary = scene.battle_snapshot()
	_check(_unit(initial, "healer").get("position") == Vector2i(1, 1), "Healer starts at B2")
	_check(_unit(initial, "necromancer").get("position") == Vector2i(2, 2), "Necromancer starts at C3")
	_check(_unit(initial, "practice_raider").get("position") == Vector2i(3, 1), "Raider starts at D2")
	_check(_unit(initial, "fallen_raider").get("position") == Vector2i(4, 3)
		and _unit(initial, "fallen_raider").get("hp") == 0, "Corpse starts at E4")

	if not await _command("necromancer", "raise_dead", "fallen_raider"):
		_finish()
		return
	var first: Dictionary = scene.get("_plan").duplicate(true)
	_check(_has_summon(first, "necromancer_zombie", Vector2i(4, 3), 3),
		"Round 1 previews a 3 HP zombie at E4")
	if not await _commit_matches(first):
		_finish()
		return

	if not await _command("necromancer", "summon_skeleton", "2,1"):
		_finish()
		return
	var second: Dictionary = scene.get("_plan").duplicate(true)
	_check(_has_summon(second, "necromancer_skeleton", Vector2i(2, 1), 1),
		"Round 2 previews a 1 HP skeleton at C2")
	if not await _commit_matches(second):
		_finish()
		return
	var board := _node("BridgeBoard")
	_check(board != null and board.is_visible_in_tree(), "Battle board is visible")
	if board != null:
		var drawn: Array = board.get("_units")
		_check(_drawn(drawn, "necromancer_zombie", "zombie"), "Board displays the zombie art key")
		_check(_drawn(drawn, "necromancer_skeleton", "skeleton"), "Board displays the skeleton art key")

	var stay: Dictionary = scene.get("_plan").duplicate(true)
	_check(_wave_hits(stay, "healer") and _wave_hits(stay, "necromancer")
		and _wave_hits(stay, "practice_raider"), "Standing forecast shows Wave hitting all three neighbors")
	var forecast := _node("PreviewText")
	_check(forecast != null and forecast.is_visible_in_tree() and "Wave" in str(forecast.text),
		"Visible standing forecast names Wave")
	var before: Dictionary = scene.battle_snapshot()
	if not await _command("healer", "move", "0,1"):
		_finish()
		return
	var escape: Dictionary = scene.get("_plan").duplicate(true)
	_check(scene.battle_snapshot() == before, "Preview does not mutate the battle")
	_check(not _wave_hits(escape, "healer") and _wave_hits(escape, "necromancer")
		and _wave_hits(escape, "practice_raider"), "Moving to A2 avoids Wave while the other hits remain")
	_check(_move_precedes_wave(escape), "Forecast orders the Healer's move before Wave")
	if await _commit_matches(escape):
		var healer := _unit(scene.battle_snapshot(), "healer")
		_check(healer.get("position") == Vector2i(0, 1) and healer.get("hp") == 7,
			"Healer ends at A2 with full HP")
	_finish()


func _command(actor: String, ability: String, target: String) -> bool:
	if not await _select("ActorSelect", actor):
		return false
	if not await _select("AbilitySelect", ability):
		return false
	if not await _select("TargetSelect", target):
		return false
	return await _press("Preview")


func _select(name: String, id: String) -> bool:
	var picker := _node(name) as OptionButton
	if picker != null and not picker.disabled and picker.is_visible_in_tree():
		for i in picker.item_count:
			if str(picker.get_item_metadata(i)) == id and not picker.is_item_disabled(i):
				picker.select(i)
				picker.item_selected.emit(i)
				await process_frame
				return true
	_check(false, "%s offers selectable %s" % [name, id])
	return false


func _press(name: String) -> bool:
	var button := _node(name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is visible and enabled")
		return false
	button.pressed.emit()
	await process_frame
	return true


func _commit_matches(plan: Dictionary) -> bool:
	_check(plan.get("valid", false), "Forecast is valid")
	if not await _press("Commit"):
		return false
	_check(scene.battle_snapshot() == plan.get("result"), "Commit matches the complete forecast")
	var ongoing: bool = scene.current_screen() == "battle"
	_check(ongoing, "Practice battle remains active")
	return ongoing


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _has_summon(plan: Dictionary, id: String, position: Vector2i, hp: int) -> bool:
	for event in plan.get("events", []):
		if event.get("type") == "summon" and event.get("summon_id") == id:
			return event.get("position") == position and event.get("hp") == hp
	return false


func _drawn(units: Array, id: String, art_key: String) -> bool:
	for unit in units:
		if unit.get("id") == id and unit.get("art_key") == art_key and unit.get("hp", 0) > 0:
			return true
	return false


func _wave_hits(plan: Dictionary, target: String) -> bool:
	for event in plan.get("events", []):
		if event.get("type") == "damage" and event.get("ability_id") == "wave" \
				and event.get("source_id") == "necromancer_skeleton" and event.get("target_id") == target:
			return true
	return false


func _move_precedes_wave(plan: Dictionary) -> bool:
	var moved := false
	for event in plan.get("events", []):
		if event.get("type") == "move" and event.get("unit_id") == "healer" \
				and event.get("position") == Vector2i(0, 1):
			moved = true
		if event.get("type") == "wave" and event.get("unit_id") == "necromancer_skeleton":
			return moved
	return false


func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: Necromancer practice scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
