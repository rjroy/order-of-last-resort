extends "res://tests/presentation/storybook_gate_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/forfeit_gate_scene_test.gd
const ForfeitControls = preload("res://tests/support/forfeit_controls.gd")
const BoardRules = preload("res://rules/board.gd")


func _run() -> void:
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if scene.current_screen() != "battle" or board == null:
		_check(false, "Standalone Gate opens its interactive battle")
		_finish()
		return
	var opening: Dictionary = scene.battle_snapshot().duplicate(true)
	# Build the reported dead end from the test-owned opening: only Wizard
	# remains west of the closed gate, with nobody on the plate.
	var stranded := opening.duplicate(true)
	for unit in stranded.units:
		if unit.id in ["knight", "healer"]:
			unit.hp = 0
	_check(_unit(stranded, "wizard").get("hp", 0) > 0
		and _unit(stranded, "wizard").get("position", Vector2i(99, 99)).x < 3
		and not BoardRules.pressure_gate_open(stranded),
		"Fixture has one living hero west of the closed, unheld gate")
	scene.set("_state", stranded)
	scene.call("_begin_attempt")
	# The editor normally auto-selects a survivor; also cover an empty selection.
	scene.set("_actor_id", "")
	scene.call("_sync_command")
	scene.call("_refresh")
	await process_frame
	var escape := ForfeitControls.button(root, ["forfeit"])
	for name in ["ForecastDetails", "StandingOrders"]:
		var control := scene.find_child(name, true, false) as BaseButton
		_check(control != null and control.is_visible_in_tree() and not control.disabled,
			name + " is available before confirmation")
	_check(escape != null and scene.get("_actor_id") == ""
		and (scene.get("_targets") as Array).is_empty(),
		"Forfeit is discoverable without a selected hero or targets")
	if escape == null:
		_finish()
		return
	await ForfeitControls.click(self, escape)
	_check(scene.battle_snapshot() == stranded and scene.current_screen() == "battle",
		"Opening confirmation does not commit or forfeit")
	var cancel := ForfeitControls.button(root, ["cancel"])
	_check(cancel != null, "Forfeit requires an explicit confirmation with Cancel")
	if cancel == null:
		_finish()
		return
	_check(cancel.has_focus(), "Confirmation defaults keyboard focus to Cancel")
	await _background_leaf_accessibility(cancel)
	await ForfeitControls.click(self, cancel)
	_check(scene.battle_snapshot() == stranded, "Cancel preserves the stranded mission")
	await ForfeitControls.click(self, escape)
	await _key(KEY_ESCAPE)
	_check(scene.battle_snapshot() == stranded
		and ForfeitControls.button(root, ["cancel"]) == null and escape.has_focus(),
		"Escape cancels confirmation, restores Forfeit focus, and does not change the battle")
	await ForfeitControls.click(self, escape)
	cancel = ForfeitControls.button(root, ["cancel"])
	if cancel == null:
		_check(false, "Confirmation reopens after Escape")
		_finish()
		return
	_check(cancel.has_focus(), "Reopened confirmation defaults focus to Cancel")
	await _key(KEY_ENTER)
	_check(scene.battle_snapshot() == stranded
		and ForfeitControls.button(root, ["cancel"]) == null,
		"Default Enter cancels instead of forfeiting")

	# Start over and queue an aimed command using the actual storybook controls.
	if not await _click_button("Restart"):
		_finish()
		return
	await _click_cell(board, _unit(opening, "wizard").position)
	if not await _choose_action("wizard_pull"):
		_finish()
		return
	await _click_cell(board, _unit(opening, "healer").position)
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var queued: Dictionary = scene.get("_planned_state").duplicate(true)
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	var actor: String = scene.get("_actor_id")
	var ability: String = scene.get("_ability_id")
	var target: String = scene.get("_target_id")
	var aiming: bool = scene.get("_storybook_aiming")
	var targets: Array = (scene.get("_targets") as Array).duplicate(true)
	var highlights := _highlighted_cells(board).duplicate(true)
	_check(queued.get("overrides", {}).get("wizard", {}).get("ability_id") == "wizard_pull"
		and aiming and not targets.is_empty(), "Fixture queues Pull while retaining aim")
	escape = ForfeitControls.button(root, ["forfeit"])
	if escape == null:
		_check(false, "Forfeit remains available with a queued aimed command")
		_finish()
		return
	await ForfeitControls.click(self, escape)
	cancel = ForfeitControls.button(root, ["cancel"])
	if cancel == null:
		_check(false, "Queued command offers a cancelable confirmation")
		_finish()
		return
	# The paper and scrim do not dismiss the dialog, run a command, or steal keyboard focus.
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit != null:
		await ForfeitControls.click(self, commit)
	await ForfeitControls.click(self, escape)
	await _click_cell(board, _unit(opening, "knight").position)
	await _key(KEY_DOWN)
	_check(cancel.is_visible_in_tree() and cancel.has_focus() and scene.battle_snapshot() == before
		and scene.get("_planned_state") == queued and scene.get("_actor_id") == actor,
		"Backdrop clicks, board clicks, and keyboard input cannot dismiss or change the battle")
	await ForfeitControls.click(self, cancel)
	_check(scene.battle_snapshot() == before and scene.get("_planned_state") == queued
		and scene.get("_plan") == plan and scene.get("_actor_id") == actor
		and scene.get("_ability_id") == ability and scene.get("_target_id") == target
		and scene.get("_storybook_aiming") == aiming and scene.get("_targets") == targets
		and _highlighted_cells(board) == highlights,
		"Cancel restores exact battle, queue, forecast, editor and aim")
	await _open_order_popup_accessibility()

	# Confirm the actual lone-survivor case, not a normal opening.
	scene.set("_state", stranded.duplicate(true))
	scene.call("_begin_attempt")
	await process_frame
	escape = ForfeitControls.button(root, ["forfeit"])
	if escape == null:
		_check(false, "Stranded survivor can still forfeit")
		_finish()
		return
	await ForfeitControls.click(self, escape)
	var confirm := ForfeitControls.button(root, ["forfeit mission"], escape)
	_check(confirm != null, "Confirmation offers an affirmative choice")
	if confirm != null:
		for _step in 8:
			if confirm.has_focus():
				break
			await _key(KEY_TAB)
		_check(confirm.has_focus(), "Keyboard navigation reaches the affirmative choice")
		if not confirm.has_focus():
			_finish()
			return
		await _key(KEY_ENTER)
		_check(scene.battle_snapshot().get("outcome") == "defeat",
			"Confirmed stranded Gate resolves as ordinary defeat")
		_check(ForfeitControls.button(root, ["cancel"]) == null
			and ForfeitControls.button(root, ["forfeit mission"]) == null,
			"Keyboard confirmation closes the active confirmation")
		var restart := scene.find_child("Restart", true, false) as BaseButton
		_check(restart != null and restart.is_visible_in_tree() and not restart.disabled
			and restart.has_focus(), "Defeat moves keyboard focus to the visible Restart action")
		if restart != null and restart.has_focus():
			await _key(KEY_ENTER)
			_check(scene.battle_snapshot() == opening,
				"Keyboard Restart after forfeit restores the original Gate")
	_finish()


func _open_order_popup_accessibility() -> void:
	if not await _click_button("StandingOrders"):
		return
	var page: Node = scene.get("_storybook_page")
	var picker := scene.find_child("KnightOrder", true, false) as OptionButton
	var leaf := scene.find_child("ExtraDetails", true, false) as Control
	var escape := ForfeitControls.button(root, ["forfeit"])
	if picker == null or leaf == null or escape == null or not picker.is_visible_in_tree():
		_check(false, "Open orders leaf offers Knight's order picker and Forfeit")
		return
	var guard := ""
	var advance := ""
	for choice in rules.options(scene.battle_snapshot(), "knight"):
		if choice.kind == "order" and choice.id == "order_guard":
			guard = choice.label
		elif choice.kind == "order" and choice.id == "order_advance":
			advance = choice.label
	var advance_index := -1
	for index in picker.item_count:
		if picker.get_item_text(index) == advance and not picker.is_item_disabled(index):
			advance_index = index
	if guard.is_empty() or advance.is_empty() or advance_index < 0 \
			or picker.selected < 0 or picker.get_item_text(picker.selected) != guard:
		_check(false, "Knight starts on Guard and offers Advance")
		return
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var queued: Dictionary = scene.get("_planned_state").duplicate(true)
	var intents: Array = []
	var record := func(hero: String, order: String) -> void: intents.append([hero, order])
	page.connect("order_selected", record)
	picker.show_popup()
	await process_frame
	var popup := picker.get_popup()
	if not popup.visible:
		_check(false, "Knight order dropdown opens before Forfeit")
		page.disconnect("order_selected", record)
		return
	# Accessibility invokes the button directly, without a pointer click that
	# would first dismiss the existing popup.
	escape.pressed.emit()
	await process_frame
	var cancel := ForfeitControls.button(root, ["cancel"])
	_check(cancel != null and not popup.visible,
		"Accessible Forfeit closes the previously open order popup")
	# Godot OptionButton listens to PopupMenu.index_pressed and updates its
	# selection before emitting item_selected, even for a retained callback.
	popup.index_pressed.emit(advance_index)
	await process_frame
	_check(intents.is_empty() and scene.battle_snapshot() == before
		and scene.get("_planned_state") == queued,
		"Retained popup selection emits no order intent and preserves battle and queue")
	if popup.visible:
		popup.hide()
	if cancel != null:
		cancel.pressed.emit()
		await process_frame
		_check(leaf.is_visible_in_tree() and page.get("_expanded") == "orders"
			and picker.selected >= 0 and picker.get_item_text(picker.selected) == guard
			and scene.battle_snapshot() == before and scene.get("_planned_state") == queued,
			"Cancel preserves orders leaf, queued command and authoritative Guard selection")
		picker = scene.find_child("KnightOrder", true, false) as OptionButton
		if picker != null and picker.is_visible_in_tree() and not picker.disabled:
			picker.grab_focus()
			await _key(KEY_SPACE)
			var reopened := picker.get_popup()
			_check(reopened.visible, "Knight order picker deliberately reopens after Cancel")
			if reopened.visible:
				var fresh_index := -1
				for index in picker.item_count:
					if picker.get_item_text(index) == advance and not picker.is_item_disabled(index):
						fresh_index = index
				for _attempt in picker.item_count:
					if reopened.get_focused_item() == fresh_index:
						break
					await _key(KEY_DOWN)
				if fresh_index >= 0 and reopened.get_focused_item() == fresh_index:
					await _key(KEY_ENTER)
					var expected_battle: Dictionary = rules.set_order(before, "knight", "order_advance")
					var expected_queue: Dictionary = rules.set_order(queued, "knight", "order_advance")
					_check(not reopened.visible and intents == [["knight", "order_advance"]]
						and scene.battle_snapshot() == expected_battle
						and scene.get("_planned_state") == expected_queue,
						"Fresh Advance choice applies after Cancel without changing queued Pull")
				else:
					_check(false, "Reopened Knight picker offers Advance to keyboard navigation")
					await _key(KEY_ESCAPE)
		else:
			_check(false, "Knight order picker remains available after Cancel")
	page.disconnect("order_selected", record)


func _background_leaf_accessibility(cancel: BaseButton) -> void:
	var page: Node = scene.get("_storybook_page")
	var leaf := scene.find_child("ExtraDetails", true, false) as Control
	if leaf == null:
		_check(false, "Battle exposes its details leaf")
		return
	for name in ["ForecastDetails", "StandingOrders"]:
		var control := scene.find_child(name, true, false) as BaseButton
		if control == null:
			_check(false, name + " exists during confirmation")
			continue
		# Accessibility activation reaches the button's pressed callback directly,
		# rather than passing through the pointer scrim. Hidden or disabled
		# controls cannot be activated by the player and need no synthetic press.
		cancel.grab_focus()
		var section: String = page.get("_expanded")
		var visible_before := leaf.is_visible_in_tree()
		var focus_before := root.gui_get_focus_owner()
		if control.is_visible_in_tree() and not control.disabled:
			control.pressed.emit()
			await process_frame
		_check(page.get("_expanded") == section and leaf.is_visible_in_tree() == visible_before
			and root.gui_get_focus_owner() == focus_before and cancel.is_visible_in_tree(),
			name + " accessibility activation cannot change details or steal confirmation focus")
