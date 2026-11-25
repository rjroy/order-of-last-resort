extends SceneTree

# Run graphically: godot --path games/company-of-unlikely-heroes --script res://tests/content/content_scene_test.gd
# The child exercises the real --content bootstrap, not a test-only launch path.
const MISSION := "company_rescue"
var failures: Array[String] = []
var scene: Node
var board: Control


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Content scene test requires a graphical display.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	if "--content-scene-child" not in OS.get_cmdline_user_args():
		_run_child()
		return
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", "External mission launches into battle")
	board = scene.find_child("BridgeBoard", true, false) as Control
	var page: Control = scene.get("_storybook_page")
	_check(board != null and board.is_visible_in_tree() and page != null and page.is_visible_in_tree(),
		"External content uses the normal player battle page and board")
	if board == null or page == null:
		_finish()
		return
	_check((page.get("_title") as Label).text == "A courier crossing",
		"Player page displays the external mission title")
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var objective: Label = page.get("_objective")
	_check(objective.is_visible_in_tree() and "Courier Sel" in objective.text
		and "G5" in objective.text and "A4" in objective.text,
		"Escort objective displays the authored subject, position and relocated exit")
	_check((board.get("_overlay") as Dictionary).get("exit") == Vector2i(6, 4),
		"Board marks the relocated escort destination")
	await _cell(Vector2i(2, 2))
	_check(_has_action("Push") and not _has_action("Blast nearest"),
		"Original knight offers Push but not the other knight's Blast")
	if await _action("Push"):
		for target in [
			{"cell": Vector2i(3, 2), "id": "crate", "name": "Supply crate"},
			{"cell": Vector2i(2, 3), "id": "second_crate", "name": "Relic chest"},
		]:
			await _cell(target.cell)
			var command: Dictionary = scene.get("_planned_state").get("overrides", {}).get("knight", {})
			_check(command.get("ability_id") == "knight_push" and command.get("target_id") == target.id,
				"Board selects authored target " + target.name)
			_check(target.name in (page.get("_summary") as Label).text,
				"Visible command identifies authored target " + target.name)
			_check(scene.battle_snapshot() == before, "Targeting does not commit the forecast")
	var clear := scene.find_child("ClearCommand", true, false) as BaseButton
	if clear != null and clear.is_visible_in_tree() and not clear.disabled:
		await _click(clear.get_global_rect().get_center())
	await _cell(Vector2i(5, 3))
	_check(_has_action("Blast nearest") and not _has_action("Push"),
		"Second knight offers authored Blast but not Push")
	if await _action("Blast nearest"):
		_check(scene.get("_planned_state").get("overrides", {}).get("second_knight", {}).get("ability_id") == "wizard_blast",
			"Selecting Blast stages the second knight's authored ability")
	if clear != null and not clear.disabled:
		await _click(clear.get_global_rect().get_center())
	var orders := scene.find_child("StandingOrders", true, false) as BaseButton
	if orders != null and orders.is_visible_in_tree() and not orders.disabled:
		await _click(orders.get_global_rect().get_center())
	else:
		_check(false, "Standing orders control is available")
	var first := scene.find_child("KnightOrder", true, false) as OptionButton
	var second := scene.find_child("SecondKnightOrder", true, false) as OptionButton
	_check(first != null and second != null and first.is_visible_in_tree() and second.is_visible_in_tree(),
		"Same-class heroes have independent visible order controls")
	if first != null and second != null:
		_check(not _has_option(first, "Blast nearest") and _has_option(second, "Blast nearest"),
			"Only the second knight offers its authored Blast order")
		if await _select_option(second, "Blast nearest"):
			_check(scene.battle_snapshot().orders.get("second_knight") == "order_blast"
				and scene.battle_snapshot().orders.get("knight") == before.orders.get("knight"),
				"Changing second knight's order leaves the first knight unchanged")
	_finish()


func _run_child() -> void:
	var data: Dictionary = load("res://content/catalog.gd").read_default()
	if data.is_empty():
		_check(false, "Default catalog is available to construct the test-owned fixture")
		_finish()
		return
	data.missions[MISSION].title = "A courier crossing"
	data.missions[MISSION].default_party = ["knight", "second_knight", "healer"]
	data.missions[MISSION].objective.subject = "passenger"
	data.missions[MISSION].objective.text = "Escort {subject_label} to {destination}. {hp}/{max_hp} HP at {position}"
	data.boards.bridge.locations.safe_bank = [6, 4]
	data.characters.courier = {"class": "civilian", "label": "Courier Sel"}
	data.characters.second_knight = {
		"class": "knight", "label": "Spark Knight", "abilities": ["move", "wizard_blast"],
		"habits": {"order_cautious": "hold", "order_blast": "blast"}, "default_order": "order_cautious"
	}
	data.objects.supply_crate = data.objects.crate.duplicate(true)
	data.objects.supply_crate.label = "Supply crate"
	data.objects.relic_chest = data.objects.crate.duplicate(true)
	data.objects.relic_chest.label = "Relic chest"
	data.encounters.company_crossing.party_slots = [[2, 2], [5, 3], [0, 1]]
	data.encounters.company_crossing.placements = [
		{"id": "passenger", "character": "courier", "at": [0, 3]},
		{"id": "crate", "object": "supply_crate", "at": [3, 2]},
		{"id": "second_crate", "object": "relic_chest", "at": [2, 3]}
	]
	var fixture := "user://content_scene_fixture_%d.json" % OS.get_process_id()
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write temporary fixture")
		_finish()
		return
	file.store_string(JSON.stringify(data))
	file.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), [
		"--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/content/content_scene_test.gd",
		"--", "--content=" + ProjectSettings.globalize_path(fixture), "--mission=" + MISSION,
		"--content-scene-child"
	], output, true)
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture)) == OK,
		"Temporary fixture was removed")
	for line in output:
		print(line)
	_check(code == 0, "External content child succeeded (exit %d)" % code)
	_finish()


func _cell(cell: Vector2i) -> void:
	await _click(board.get_global_transform_with_canvas() * board.cell_center(cell))


func _has_action(label: String) -> bool:
	var menu := scene.find_child("Actions", true, false) as MenuButton
	if menu == null or not menu.is_visible_in_tree() or menu.disabled:
		return false
	var popup := menu.get_popup()
	for index in popup.item_count:
		if popup.get_item_text(index).begins_with(label) and not popup.is_item_disabled(index):
			return true
	return false


func _action(label: String) -> bool:
	var menu := scene.find_child("Actions", true, false) as MenuButton
	if _has_action(label):
		var popup := menu.get_popup()
		for index in popup.item_count:
			if popup.get_item_text(index).begins_with(label) and not popup.is_item_disabled(index):
				popup.id_pressed.emit(popup.get_item_id(index))
				await process_frame
				return true
	_check(false, "Action is selectable: " + label)
	return false


func _has_option(picker: OptionButton, label: String) -> bool:
	for index in picker.item_count:
		if picker.get_item_text(index) == label and not picker.is_item_disabled(index):
			return true
	return false


func _select_option(picker: OptionButton, label: String) -> bool:
	if picker.is_visible_in_tree() and not picker.disabled:
		for index in picker.item_count:
			if picker.get_item_text(index) == label and not picker.is_item_disabled(index):
				picker.select(index)
				picker.item_selected.emit(index)
				await process_frame
				return true
	_check(false, "Order is selectable: " + label)
	return false


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: external content uses player battle controls")
	quit(0 if failures.is_empty() else 1)
