extends RefCounted

var tree: SceneTree
var scene: Node
var rules = preload("res://rules/rules.gd").new()
var error := ""


func _init(owner: SceneTree, game: Node) -> void:
	tree = owner
	scene = game


func select_actor(id: String) -> bool:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	for unit: Dictionary in scene.battle_snapshot().get("units", []):
		if unit.get("id") == id and unit.get("hp", 0) > 0 and board != null:
			await _click(board.get_global_transform_with_canvas() * board.cell_center(unit.position))
			if scene.get("_actor_id") == id:
				return true
	error = "Cannot select living actor " + id
	return false


func action(id: String) -> bool:
	var actor := str(scene.get("_actor_id"))
	var label: String = rules.ability_definition(scene.battle_snapshot(), id, actor).get("label", "")
	var menu := scene.find_child("Actions", true, false) as MenuButton
	if menu != null and menu.is_visible_in_tree() and not menu.disabled and not label.is_empty():
		var popup := menu.get_popup()
		for index in popup.item_count:
			if popup.get_item_text(index).begins_with(label) and not popup.is_item_disabled(index):
				popup.id_pressed.emit(popup.get_item_id(index))
				await tree.process_frame
				return true
	error = "Actions menu does not offer %s for %s" % [id, actor]
	return false


func target(id: String) -> bool:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	for choice: Dictionary in scene.get("_targets"):
		if str(choice.get("id")) == id and board != null:
			await _click(board.get_global_transform_with_canvas() * board.cell_center(choice.position))
			var menu := scene.find_child("Targets", true, false) as MenuButton
			if menu != null and menu.is_visible_in_tree():
				var popup := menu.get_popup()
				var rows: Array = scene.get("_storybook_page").get("_target_rows")
				for index in rows.size():
					if str(rows[index].id) == id and not popup.is_item_disabled(index):
						popup.id_pressed.emit(popup.get_item_id(index))
						await tree.process_frame
						break
			var planned: Dictionary = scene.get("_planned_state")
			if str(planned.get("overrides", {}).get(scene.get("_actor_id"), {}).get("target_id", "")) == id:
				return true
	error = "Cannot select target " + id
	return false


func order(hero: String, id: String) -> bool:
	var toggle := scene.find_child("StandingOrders", true, false) as BaseButton
	if toggle == null or not toggle.is_visible_in_tree() or toggle.disabled:
		error = "Standing orders unavailable"
		return false
	if not toggle.button_pressed:
		toggle.pressed.emit()
		await tree.process_frame
	var picker := scene.find_child(hero.to_pascal_case() + "Order", true, false) as OptionButton
	var label := ""
	for choice: Dictionary in rules.options(scene.battle_snapshot(), hero):
		if choice.kind == "order" and choice.id == id:
			label = choice.label
	if picker != null and picker.is_visible_in_tree() and not picker.disabled:
		for index in picker.item_count:
			if picker.get_item_text(index) == label and not picker.is_item_disabled(index):
				picker.select(index)
				picker.item_selected.emit(index)
				await tree.process_frame
				toggle.pressed.emit()
				await tree.process_frame
				return true
	error = "Order %s unavailable for %s" % [id, hero]
	return false


func command(actor: String, ability: String, target_id := "") -> bool:
	if not await select_actor(actor) or not await action(ability):
		return false
	if not target_id.is_empty() and not await target(target_id):
		return false
	var planned: Dictionary = scene.get("_planned_state")
	var override: Dictionary = planned.get("overrides", {}).get(actor, {})
	if override.get("ability_id") == ability and (target_id.is_empty() or override.get("target_id") == target_id):
		return true
	error = "Command did not stage: %s %s %s" % [actor, ability, target_id]
	return false


func clear() -> bool:
	var button := scene.find_child("ClearCommand", true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		error = "Clear command unavailable"
		return false
	button.pressed.emit()
	await tree.process_frame
	return true


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		scene.get_viewport().push_input(event, true)
		await tree.process_frame
