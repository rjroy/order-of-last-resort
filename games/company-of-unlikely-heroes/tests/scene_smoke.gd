extends SceneTree

# Run: godot --path games/company-of-unlikely-heroes --script res://tests/scene_smoke.gd
# Add -- --capture=/absolute/path.png to capture the actual game viewport.
var failures: Array[String] = []
var scene: Node
var controls: Dictionary = {}


func _test_shore_presentation() -> void:
	var board := scene.find_child("BridgeBoard", true, false)
	var safe: Dictionary = board.get("_overlay").get("safe", {})
	_check(safe.size() == 15, "Default shore covers exactly the far bank")
	for x in range(7):
		for y in range(5):
			_check(safe.has(Vector2i(x, y)) == (x >= 4), "Default shore extent at %s" % Vector2i(x, y))
	var rules = scene.get("_rules")
	var original: Dictionary = scene.get("_state")
	var defs: Dictionary = rules.definitions(original).duplicate(true)
	defs.tiles.stone.art_key = "custom_floor"
	scene.set("_state", rules.new_game(defs, "ferryman"))
	var cells: Dictionary = scene.call("_terrain")
	_check(cells[Vector2i(6, 2)] == "custom_floor" and scene.get("_safe_cells").size() == 15,
		"Authored shore tint works with custom tile art without replacing it")
	defs.boards.bridge.erase("shore_cells")
	scene.set("_state", rules.new_game(defs, "ferryman"))
	scene.call("_terrain")
	_check(scene.get("_safe_cells").is_empty(), "Board without shore configuration has no automatic tint")
	defs.tiles.stone.art_key = "stone"
	scene.set("_state", rules.new_game(defs, "ferryman"))
	scene.call("_terrain")
	_check(scene.get("_safe_cells").is_empty(), "Stone art alone does not imply a shore")
	scene.set("_state", original)
	scene.call("_terrain")


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

	_check(scene.has_method("current_screen") and scene.call("current_screen") == "guild",
		"Default entry must show the guild screen")
	_check(scene.find_child("ModeDirect", true, false) == null
		and scene.find_child("ModeStanding", true, false) == null,
		"Guild entry must not offer retired mode selectors")
	scene.queue_free()
	await process_frame
	scene = packed.instantiate()
	scene.call("configure_launch", PackedStringArray(["--mission=ferryman"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_check(scene.call("current_screen") == "battle", "Fixed mission launches into battle")
	for name in ["Restart", "Preview", "Commit", "ClearCommand"]:
		_require_control(name, BaseButton)
	for name in ["ActorSelect", "AbilitySelect", "TargetSelect"]:
		_require_control(name, OptionButton)
	for name in ["MissionTitle", "RoundText", "PreviewText", "LastResult"]:
		var node := scene.find_child(name, true, false)
		if node == null or not (node is Label or node is RichTextLabel or node is TextEdit):
			failures.append("Missing behavior: visible text control " + name)
		else:
			controls[name] = node
			_check(node.is_visible_in_tree(), name + " must be visible")
	if not failures.is_empty():
		_finish()
		return

	var initial_status := _text("MissionTitle")
	var initial_round := _text("RoundText")
	_check(not initial_status.strip_edges().is_empty(), "Hybrid entry must display status")
	_check(not initial_round.strip_edges().is_empty(), "Hybrid entry must display the round")
	_test_shore_presentation()

	_check(scene.find_child("ModeDirect", true, false) == null
		and scene.find_child("ModeStanding", true, false) == null,
		"Battle must not offer retired mode selectors")

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
		_check(_text("RoundText") == initial_round and _text("MissionTitle") == initial_status,
			"Restart must restore the initial hybrid state")

	await _test_fixed_rescue_move()
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
	await _test_adventure_rescue_move(packed)
	await _test_forecast_knockdown(packed)
	_finish()


func _test_fixed_rescue_move() -> void:
	var start := Vector2i(0, 2)
	var down := Vector2i(0, 3)
	var up := Vector2i(0, 1)
	var opening: Dictionary = scene.battle_snapshot()
	_check(_hero("healer").position == start, "Fixed rescue starts Healer at A3")
	if not await _select_id("ActorSelect", "healer") or not await _select_id("AbilitySelect", "move"):
		return
	_check(_target_ids() == ["0,1", "0,3"], "Fixed A3 can move to A2 or A4, not into Ferryman at B3")
	await _click_cell(down)
	await _assert_edit_blocks_commit(opening)
	await _press("Preview")
	_check("Healer moves to A4." in _text("PreviewText"), "Preview includes the first selected move")
	await _click_cell(up)
	await _click_cell(start)
	_check(str(controls.TargetSelect.get_selected_metadata()) == "0,1",
		"Clicking the selected hero's tile does not discard their edit")
	await _assert_edit_blocks_commit(opening)
	_check("Healer moves to A4." in _text("PreviewText"), "Editing does not change the queued forecast")
	await _press("ClearCommand")
	_check("Healer moves to A4." in _text("PreviewText") and not controls.Commit.disabled,
		"Discard edit restores the previous forecast")
	await _click_cell(up)
	await _press("Preview")
	_check("Healer moves to A2." in _text("PreviewText"), "Replacement forecast uses the new target")
	_check(scene.battle_snapshot() == opening, "Previewing either move leaves the actual board alone")
	await _press("Commit")
	_check(_hero("healer").position == up and "Healer moves to A2." in _text("LastResult"),
		"Fixed rescue commits the previewed A2 move")
	await _press("Restart")


func _test_adventure_rescue_move(packed: PackedScene) -> void:
	await _start_patrol(packed, ["knight", "healer", "wizard"])
	# The same three-turn patrol route exercised at the rules boundary in adventure_test.
	if not await _select_id("WizardOrder", "order_blast"):
		return
	await _press("Commit")
	await _press("Commit")
	if not await _queue_action("wizard", "wizard_pull", "raider_two"):
		return
	await _press("Commit")
	if not await _continue_to_rescue():
		return
	var opening: Dictionary = scene.battle_snapshot()
	_check(_hero("healer").position == Vector2i(0, 2), "Adventure slot 2 starts Healer at A3")
	if not await _select_id("ActorSelect", "healer") or not await _select_id("AbilitySelect", "move"):
		return
	_check(_target_ids() == ["0,3"], "Adventure A3 offers only A4: Wizard at A2, Ferryman at B3")
	await _click_cell(Vector2i(0, 3))
	await _assert_edit_blocks_commit(opening)
	await _press("Preview")
	_check("Healer moves to A4." in _text("PreviewText"), "Adventure preview forecasts the board click")
	await _press("Commit")
	_check(_hero("healer").position == Vector2i(0, 3) and "Healer moves to A4." in _text("LastResult"),
		"Adventure rescue commits the previewed A4 move")


func _test_forecast_knockdown(packed: PackedScene) -> void:
	await _start_patrol(packed, ["wizard", "alchemist", "healer"])
	if not await _select_id("HealerOrder", "order_aggressive") \
			or not await _queue_action("wizard", "wizard_pull", "raider_one"):
		return
	await _press("Commit")
	if not await _select_id("AlchemistOrder", "order_blast") or not await _select_id("HealerOrder", "order_support"):
		return
	await _press("Commit")
	if not await _select_id("AlchemistOrder", "order_guard") or not await _select_id("WizardOrder", "order_blast"):
		return
	for turn in range(3):
		await _press("Commit")
	if not await _continue_to_rescue():
		return
	var healer := _hero("healer")
	_check(healer.position == Vector2i(0, 1) and healer.hp > 3 and healer.statuses.is_empty(),
		"Shipped rescue starts with an upright Healer at A2 that can survive a splash")
	if not await _select_id("WizardOrder", "order_cautious") or not await _select_id("AlchemistOrder", "order_blast"):
		return
	if not await _select_id("ActorSelect", "healer") or not await _select_id("AbilitySelect", "move"):
		return
	_check(controls.TargetSelect.disabled and controls.TargetSelect.get_item_text(0) == "Knocked down"
		and controls.Preview.disabled, "An earlier splash explains the disabled Move target and Preview")
	_check("before acting" in _text("ActionHelp") and "Change an earlier order" in _text("ActionHelp"),
		"Knockdown help says when it happens and how to avoid it")
	_check("Healer gets up and loses this action." in _text("PreviewText"),
		"Forecast explains why the currently upright Healer will miss their turn")
	await _press("ClearCommand")
	await _press("Commit")
	_check(_hero("healer").hp == healer.hp - 3, "The rescue splash leaves a wounded, upright Healer")
	if not await _select_id("AlchemistOrder", "order_guard") \
			or not await _queue_action("alchemist", "move", "0,3") \
			or not await _select_id("ActorSelect", "healer") \
			or not await _select_id("AbilitySelect", "move"):
		return
	_check(_target_ids() == ["0,0"], "Replacing Alchemist's queued Move keeps A3 occupied by the Guard order")
	await _click_cell(Vector2i(0, 0))
	await _press("Preview")
	_check("Alchemist moves to A4." not in _text("PreviewText") and "Healer moves to A1." in _text("PreviewText"),
		"Preview replaces rather than adds a second command")
	await _press("Commit")
	_check(_hero("healer").position == Vector2i(0, 0),
		"Missing HP alone does not restrict movement: wounded Healer moves to A1")

	if not await _queue_action("alchemist", "move", "0,1"):
		return
	await _press("Commit")
	if not await _queue_action("wizard", "move", "1,0"):
		return
	await _press("Commit")
	if not await _select_id("ActorSelect", "healer") or not await _select_id("AbilitySelect", "move"):
		return
	_check(controls.TargetSelect.disabled and controls.TargetSelect.get_item_text(0) == "No open adjacent tile"
		and controls.Preview.disabled, "A1 has no orthogonal step with Wizard at B1 and Alchemist at A2")
	_check("when this hero acts" in _text("ActionHelp") and "Choose another action or hero" in _text("ActionHelp"),
		"Enclosed movement explains the restriction and offers a next action")


func _start_patrol(packed: PackedScene, party: Array) -> void:
	scene.queue_free()
	await process_frame
	controls.clear()
	scene = packed.instantiate()
	scene.configure_launch(PackedStringArray())
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	for id in party:
		_require_control("Recruit_" + id, BaseButton)
		await _press("Recruit_" + id)
	_require_control("StartAdventure", BaseButton)
	await _press("StartAdventure")
	_bind_battle_controls()


func _continue_to_rescue() -> bool:
	if scene.current_screen() != "debrief":
		_check(false, "Shipped patrol route reaches the debrief")
		return false
	_require_control("ContinueAdventure", BaseButton)
	await _press("ContinueAdventure")
	_bind_battle_controls()
	var rescue: bool = scene.battle_snapshot().get("mission_id") == "company_rescue"
	_check(rescue, "Continue deploys the actual adventure rescue")
	return rescue


func _bind_battle_controls() -> void:
	for name in ["Preview", "Commit", "ClearCommand"]:
		_require_control(name, BaseButton)
	for name in ["ActorSelect", "AbilitySelect", "TargetSelect", "KnightOrder",
			"WizardOrder", "HealerOrder", "AlchemistOrder"]:
		if not name.ends_with("Order") or scene.find_child(name, true, false) != null:
			_require_control(name, OptionButton)
	_require_control("ActionHelp", Label)
	for name in ["LastResult", "PreviewText"]:
		_require_control(name, RichTextLabel)


func _queue_action(actor: String, ability: String, target: String) -> bool:
	if await _select_id("ActorSelect", actor) and await _select_id("AbilitySelect", ability) \
			and await _select_id("TargetSelect", target):
		await _press("Preview")
		return true
	return false


func _target_ids() -> Array[String]:
	var ids: Array[String] = []
	var picker: OptionButton = controls.TargetSelect
	if not picker.disabled:
		for index in range(picker.item_count):
			var id := str(picker.get_item_metadata(index))
			if not picker.is_item_disabled(index) and not id.is_empty():
				ids.append(id)
	ids.sort()
	return ids


func _hero(id: String) -> Dictionary:
	for unit in scene.battle_snapshot().get("units", []):
		if unit.id == id:
			return unit
	return {}


func _click_cell(cell: Vector2i) -> void:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	_check(board != null and board.is_visible_in_tree(), "Battle board is available for clicking")
	if board == null:
		return
	var point: Vector2 = board.get_global_transform_with_canvas() * board.cell_center(cell)
	await _click_at(point)


func _click_at(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = point
		event.pressed = down
		root.push_input(event, true)
	await process_frame


func _assert_edit_blocks_commit(before: Dictionary) -> void:
	var commit: Button = controls.Commit
	_check(commit.disabled and "Edit not queued" in _text("PreviewText"),
		"An edited move requires Preview or discard before Commit")
	await _click_at(commit.get_global_rect().get_center())
	_check(scene.battle_snapshot() == before, "Clicking Commit with an unqueued move leaves the round alone")


func _select_id(name: String, id: String) -> bool:
	var button: OptionButton = controls.get(name)
	if button == null or not is_instance_valid(button):
		failures.append("Missing picker " + name)
		return false
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
	var button: BaseButton = controls.get(name)
	if button == null or not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
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
