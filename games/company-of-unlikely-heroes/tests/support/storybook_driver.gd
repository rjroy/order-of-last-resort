extends RefCounted

## Shared driver for the target-first Direct Order controls: automatic
## abilities stage from named footer buttons, targeted abilities stage from
## real board clicks, and ambiguous cells pick from the floating choice
## buttons. No menu access and no bare action/target signal emissions.

var tree: SceneTree
var scene: Node
var rules = preload("res://rules/rules.gd").new()
var error := ""
var _pending_ability := ""


func _init(owner: SceneTree, game: Node) -> void:
	tree = owner
	scene = game


## Selection follows the target-first rules: an already-selected hero needs
## no click, and any other selection is cleared with Escape first so
## friendly-target priority, the own-cell clear and the self-target
## exception cannot capture the click. Escape never discards a staged
## command.
func select_actor(id: String) -> bool:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		error = "Battle board unavailable"
		return false
	for unit: Dictionary in scene.battle_snapshot().get("units", []):
		if unit.get("id") == id and unit.get("hp", 0) > 0:
			if str(scene.get("_actor_id")) == id:
				return true
			var guard := 0
			while not str(scene.get("_actor_id")).is_empty() and guard < 3:
				await _press_escape()
				guard += 1
			await _click(board.get_global_transform_with_canvas() * board.cell_center(unit.position))
			if str(scene.get("_actor_id")) == id:
				return true
			break
	error = "Cannot select living actor " + id
	return false


## Automatic and non-targeted abilities stage by pressing their named footer
## button. Targeted abilities stage target-first from the board; `action`
## only records which action a following `target` click must pick when
## several share the clicked cell. Offer, form kind and usability come from
## the same rules context the real controls render their rows from, so a
## fitted conversion (Raise Dead → Play Dead) is non-targeted and stages
## through the footer, while an unoffered or disabled action fails.
func action(id: String) -> bool:
	var form: Dictionary = _current_action(id)
	if form.is_empty():
		return false
	if not form.enabled:
		error = "%s is not currently usable" % id
		return false
	if not _is_selectable_kind(str(form.kind)):
		_pending_ability = ""
		return await _press_footer_button(id)
	_pending_ability = id
	return true


## Stages a targeted action by clicking its target cell on the board; when
## several actions or occupants share the cell, the named floating choice
## button picks the wanted one, preserving per-target identity.
func target(id: String, ability := "") -> bool:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	var wanted: String = ability if not ability.is_empty() else _pending_ability
	_pending_ability = ""
	if board == null:
		error = "Battle board unavailable"
		return false
	var position: Variant = _position_of(id)
	if position == null:
		error = "Cannot locate target " + id
		return false
	await _click(board.get_global_transform_with_canvas() * board.cell_center(position))
	if not (scene.get("_storybook_ambiguous") as Array).is_empty():
		if wanted.is_empty():
			error = "Several actions share %s; pass the wanted ability" % id
			return false
		if not await _press_choice_button(wanted, id):
			return false
	var planned: Dictionary = scene.get("_planned_state")
	var override: Dictionary = planned.get("overrides", {}).get(str(scene.get("_actor_id")), {})
	if str(override.get("target_id", "")) != id:
		error = "Cannot stage target " + id
		return false
	if not wanted.is_empty() and str(override.get("ability_id", "")) != wanted:
		error = "Target %s staged %s instead of %s" % [id, override.get("ability_id", ""), wanted]
		return false
	return true


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


## Stages one command through the public controls: safe selection, then the
## automatic footer button for offered non-targeted forms, or the target
## cell (plus the named floating choice when the cell is ambiguous) for
## offered targeted forms. Unoffered or disabled actions fail.
func command(actor: String, ability: String, target_id := "") -> bool:
	_pending_ability = ""
	if not await select_actor(actor):
		return false
	var form: Dictionary = _current_action(ability)
	if form.is_empty():
		return false
	if not form.enabled:
		error = "%s is not currently usable" % ability
		return false
	if not _is_selectable_kind(str(form.kind)):
		if not target_id.is_empty():
			error = "Automatic ability %s stages without a stored target" % ability
			return false
		if not await _press_footer_button(ability):
			return false
	else:
		if target_id.is_empty():
			error = "Targeted ability %s needs a board target" % ability
			return false
		if not await target(target_id, ability):
			return false
	var planned: Dictionary = scene.get("_planned_state")
	var override: Dictionary = planned.get("overrides", {}).get(actor, {})
	if override.get("ability_id") == ability and (target_id.is_empty() or override.get("target_id") == target_id):
		return true
	error = "Command did not stage: %s %s %s" % [actor, ability, target_id]
	return false


## The action's current form as the real controls render it: offered by the
## rules options on the actor's current editor context, classified by the
## form the actor will actually use (`command_ability`), and enabled exactly
## when the footer or the board would accept it. Mirrors main's action-row
## build, so gating (Quick Release before fitting) and fitted conversions
## (Play Dead) resolve exactly as the visible controls do.
func _current_action(ability: String) -> Dictionary:
	var actor := str(scene.get("_actor_id"))
	if actor.is_empty():
		error = "No hero is selected for " + ability
		return {}
	var snapshot: Dictionary = scene.get("_state")
	var planned: Dictionary = scene.get("_planned_state")
	var context: Dictionary = rules.state_before_action(
		planned if planned.get("overrides", {}).has(actor) else snapshot, actor)
	var offered := false
	for choice: Dictionary in rules.options(context, actor):
		if choice.kind == "action" and choice.id == ability:
			offered = true
			break
	if not offered:
		error = "%s is not offered to %s" % [ability, actor]
		return {}
	var definition: Dictionary = rules.command_ability(context, actor, ability)
	if definition.is_empty():
		error = "Unknown ability " + ability
		return {}
	var kind: String = str(definition.get("targeting", {}).get("kind", ""))
	var enabled: bool = scene.current_screen() == "battle" and rules.can_act(context, actor) \
		and not definition.get("command_blocked", false)
	if enabled and _is_selectable_kind(kind) and rules.targets(context, actor, ability).is_empty():
		enabled = false
	return {"kind": kind, "enabled": enabled, "label": str(definition.get("label", ""))}


func _is_selectable_kind(kind: String) -> bool:
	return kind == "cell" or kind == "entity"


func clear() -> bool:
	var button := scene.find_child("ClearCommand", true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		error = "Clear command unavailable"
		return false
	button.pressed.emit()
	await tree.process_frame
	return true


func _press_footer_button(ability: String) -> bool:
	var rows: Array = scene.get("_storybook_page").get("_automatic_action_rows")
	for row: Dictionary in rows:
		if str(row.get("id")) == ability:
			var button := _visible_button_with_text(str(row.get("label", "")))
			if button == null:
				error = "Footer button for %s is unavailable" % ability
				return false
			button.pressed.emit()
			await tree.process_frame
			return true
	error = "No footer button for %s" % ability
	return false


func _press_choice_button(ability: String, target_id: String) -> bool:
	var rows: Array = scene.get("_storybook_page").get("_target_rows")
	for row: Dictionary in rows:
		if str(row.get("id")) == "%s::%s" % [ability, target_id]:
			var button := _visible_button_with_text(str(row.get("label", "")))
			if button == null:
				error = "Floating choice for %s is unavailable" % str(row.get("label"))
				return false
			button.pressed.emit()
			await tree.process_frame
			return true
	error = "Floating choice does not offer %s::%s" % [ability, target_id]
	return false


func _visible_button_with_text(label: String) -> Button:
	return _visible_button_search(scene, label)


func _visible_button_search(node: Node, label: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).disabled:
		if str((node as Button).text) == label or str((node as Button).accessibility_name) == label:
			return node as Button
	for child in node.get_children():
		var found := _visible_button_search(child, label)
		if found != null:
			return found
	return null


func _position_of(id: String) -> Variant:
	for unit: Dictionary in scene.battle_snapshot().get("units", []):
		if str(unit.get("id")) == id:
			return unit.get("position")
	var parts := id.split(",")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return null


func _press_escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		event.echo = false
		scene.get_viewport().push_input(event, true)
		await tree.process_frame


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
