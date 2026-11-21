extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/cast_action_scene_test.gd
var failures: Array[String] = []
var scene: Node
var fixture_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _launch()
	if scene.current_screen() != "battle":
		_check(false, "Practice mission launches into battle")
		_finish()
		return
	var board := _node("BridgeBoard")
	if board == null or not board.has_method("action_playback_snapshot"):
		_check(false, "Battle board exposes committed action playback")
		_finish()
		return
	await _summons_and_restart()
	await _heal_case("healer", "self_heal")
	await _heal_case("necromancer", "ally_heal")
	await _bard_repeat()
	_finish()


func _launch(content := "") -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	var args := PackedStringArray(["--mission=necromancer_wave"])
	if not content.is_empty():
		args.append("--content=" + ProjectSettings.globalize_path(content))
	scene.configure_launch(args)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame


func _summons_and_restart() -> void:
	var board := _node("BridgeBoard")
	_check(_playback(board).is_empty(), "Opening forecast does not play actions")
	var before: Dictionary = scene.battle_snapshot()
	if not await _command("necromancer", "raise_dead", "fallen_raider"):
		return
	_check(scene.battle_snapshot() == before, "Summon preview preserves battle state")
	_check(_playback(board).is_empty(), "Summon preview does not play a committed clip")
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	if not await _press("Commit"):
		return
	_check(scene.battle_snapshot() == plan.get("result"), "Summon commit preserves forecast outcome")
	_check(_has_cue(board, "necromancer", "necromancer", "raise_dead", "fallen_raider"),
		"Committed Raise Dead plays for the Necromancer and identifies the corpse")
	var playback := _playback(board)
	scene.call("_refresh")
	_check(_playback(board) == playback, "Normal refresh does not restart or discard queued playback")
	if not await _command("necromancer", "summon_skeleton", "2,1"):
		return
	plan = scene.get("_plan").duplicate(true)
	if not await _press("Commit"):
		return
	_check(scene.battle_snapshot() == plan.get("result"), "Skeleton commit preserves forecast outcome")
	_check(_has_cue(board, "necromancer", "necromancer", "summon_skeleton"),
		"Committed skeleton summon plays the Necromancer's matching clip")
	if await _press("Restart"):
		_check(_playback(board).is_empty(), "Restart clears active and queued actions")
		_check(scene.battle_snapshot() == before, "Restart restores the opening battle")


func _heal_case(wounded: String, clip: String) -> void:
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default().duplicate(true)
	for placement in defs.encounters.necromancer_practice.placements:
		if placement.id == wounded:
			placement.hp = 4
	fixture_path = "user://cast_action_scene_%d.json" % OS.get_process_id()
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write isolated heal fixture")
		return
	file.store_string(JSON.stringify(defs))
	file.close()
	await _launch(fixture_path)
	if scene.current_screen() != "battle":
		_check(false, "Heal fixture launches")
		return
	var board := _node("BridgeBoard")
	var before: Dictionary = scene.battle_snapshot()
	if not await _command("healer", "healer_heal"):
		return
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	var actual_target := ""
	var healed := 0
	for event in plan.get("events", []):
		if event.get("type") == "heal" and event.get("unit_id") == "healer":
			actual_target = event.get("target_id", "")
			healed = int(event.get("amount", 0))
			break
	_check(actual_target == wounded and healed > 0,
		"Fixture forecasts positive healing for the intended " + wounded)
	_check(scene.battle_snapshot() == before and _playback(board).is_empty(),
		"Heal preview changes neither battle state nor action playback")
	if not await _press("Commit"):
		return
	_check(scene.battle_snapshot() == plan.get("result"), "Heal commit preserves forecast outcome")
	_check(_has_cue(board, "healer", "healer", clip) and _has_recipient(board, "healer", clip, wounded, "heal"),
		"Committed heal plays %s for healer with recipient %s" % [clip, wounded])


func _bard_repeat() -> void:
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default().duplicate(true)
	for placement in defs.encounters.necromancer_practice.placements:
		if placement.id == "healer":
			placement.id = "bard"
			placement.character = "bard"
	defs.characters.practice_raider.max_hp = 30
	defs.characters.practice_raider.behavior = "hold"
	fixture_path = "user://cast_action_scene_%d.json" % OS.get_process_id()
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write isolated Bard fixture")
		return
	file.store_string(JSON.stringify(defs))
	file.close()
	await _launch(fixture_path)
	if scene.current_screen() != "battle":
		_check(false, "Bard fixture launches")
		return
	var picker: OptionButton
	for candidate in scene.find_children("*", "OptionButton", true, false):
		if candidate.get_meta("actor_id", "") == "bard":
			picker = candidate
			break
	if picker == null:
		_check(false, "Bard has a standing order picker")
		return
	var selected := false
	for i in picker.item_count:
		if picker.get_item_metadata(i) == "order_healing_sonnet":
			picker.select(i)
			picker.item_selected.emit(i)
			selected = true
			break
	if not selected:
		_check(false, "Bard offers Healing Sonnet as a standing order")
		return
	await process_frame
	var board := _node("BridgeBoard")
	_check(_playback(board).is_empty(), "Standing forecast does not play Bard's song")
	for round_number in range(2):
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		if not await _press("Commit"):
			return
		_check(scene.battle_snapshot() == plan.get("result"),
			"Bard standing order round %d preserves forecast outcome" % (round_number + 1))
		_check(_has_cue(board, "bard", "bard", "healing_sonnet"),
			"Bard standing order plays Healing Sonnet in round %d" % (round_number + 1))
	_check(_cue_count(board, "bard", "healing_sonnet") >= 2,
		"Repeated Bard standing order queues a second song rather than deduplicating it")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cast/manifest.json"))
	var duration := 0.0
	for frame in manifest.actors.bard.clips.healing_sonnet.frames:
		duration += float(frame.duration_ms) / 1000.0
	await create_timer(duration * 2.0 + 1.0).timeout
	_check(_playback(board).is_empty(), "Finished songs return to rest instead of replaying indefinitely")
	if await _press("Restart"):
		_check(_playback(board).is_empty(), "Restart does not resurrect finished Bard songs")


func _command(actor: String, ability: String, target := "") -> bool:
	if not await _select("ActorSelect", actor) or not await _select("AbilitySelect", ability):
		return false
	if not target.is_empty() and not await _select("TargetSelect", target):
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


func _playback(board: Node) -> Array:
	return board.call("action_playback_snapshot")


func _has_cue(board: Node, unit_id: String, cast_key: String, clip: String, target_id := "") -> bool:
	for cue in _playback(board):
		if cue.get("unit_id") == unit_id and cue.get("cast_key") == cast_key \
				and cue.get("clip") == clip and (target_id.is_empty() or cue.get("target_id") == target_id):
			return true
	return false


func _has_recipient(board: Node, unit_id: String, clip: String, recipient: String, kind: String) -> bool:
	for cue in _playback(board):
		if cue.get("unit_id") == unit_id and cue.get("clip") == clip:
			for target in cue.get("recipients", []):
				if target.get("id") == recipient and target.get("kind") == kind:
					return true
	return false


func _cue_count(board: Node, unit_id: String, clip: String) -> int:
	var count := 0
	for cue in _playback(board):
		if cue.get("unit_id") == unit_id and cue.get("clip") == clip:
			count += 1
	return count


func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if not fixture_path.is_empty() and FileAccess.file_exists(fixture_path):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) == OK,
			"Temporary fixture is removed")
	if failures.is_empty():
		print("PASS: committed cast action scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
