extends RefCounted

## Shared driver for visible Direct Order abilities and real board input.
## Buttons and hero choices are identified by their stable IDs, not labels.

var tree: SceneTree
var scene: Node
var rules = preload("res://rules/rules.gd").new()
var error := ""
var _pending_ability := ""


func _init(owner: SceneTree, game: Node) -> void:
	tree = owner
	scene = game


## Use the hero selector while aiming so a board click cannot become a target.
## Otherwise select directly on the board.
func select_actor(id: String) -> bool:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if board == null:
		error = "Battle board unavailable"
		return false
	for unit: Dictionary in scene.battle_snapshot().get("units", []):
		if unit.get("id") == id and unit.get("hp", 0) > 0:
			if str(scene.get("_actor_id")) == id:
				return true
			var picker := scene.find_child("DirectOrderHero", true, false) as OptionButton
			if picker != null and picker.is_visible_in_tree() and not picker.disabled:
				for index in picker.item_count:
					if str(picker.get_item_metadata(index)) == id and not picker.is_item_disabled(index):
						picker.select(index)
						picker.item_selected.emit(index)
						await tree.process_frame
						_pending_ability = ""
						if str(scene.get("_actor_id")) == id:
							return true
						error = "Hero selector did not select " + id
						return false
			if not await _cancel_aim():
				return false
			await _click(board.get_global_transform_with_canvas() * board.cell_center(unit.position))
			_pending_ability = ""
			if str(scene.get("_actor_id")) == id:
				return true
			break
	error = "Cannot select living actor " + id
	return false


## Operate the visible equipped ability, including its effective fitted form.
func action(id: String) -> bool:
	var form: Dictionary = _current_action(id)
	if form.is_empty():
		return false
	if not form.enabled:
		error = "%s is not currently usable" % id
		return false
	if not await _press_ability_button(id):
		return false
	_pending_ability = id if _is_selectable_kind(str(form.kind)) else ""
	if _pending_ability.is_empty():
		var actor := str(scene.get("_actor_id"))
		var override: Dictionary = scene.get("_planned_state").get("overrides", {}).get(actor, {})
		if str(override.get("ability_id", "")) != id:
			error = "Automatic ability did not stage: " + id
			return false
	return true


## Click a legal target and resolve a same-ability occupant choice if needed.
func target(id: String, ability := "") -> bool:
	var board := scene.find_child("BridgeBoard", true, false) as Control
	var wanted: String = ability if not ability.is_empty() else _pending_ability
	if wanted.is_empty():
		wanted = "move"
	if board == null:
		error = "Battle board unavailable"
		return false
	var actor := str(scene.get("_actor_id"))
	var form := _current_action(wanted)
	if form.is_empty() or not form.enabled or not _is_selectable_kind(str(form.kind)):
		error = "Targeted ability is unavailable: " + wanted
		return false
	var legal := false
	var position: Variant = null
	for choice: Dictionary in rules.targets(_action_context(actor), actor, wanted):
		if str(choice.get("id", "")) == id:
			legal = true
			position = choice.get("position")
			break
	if not legal:
		error = "Target %s is not legal for %s" % [id, wanted]
		return false
	if not position is Vector2i:
		error = "Target %s has no valid board position" % id
		return false
	if wanted != "move" and str(scene.get("_aimed_ability_id")) != wanted:
		if not await action(wanted):
			return false
	if wanted == "move" and not str(scene.get("_aimed_ability_id")).is_empty() \
			and str(scene.get("_aimed_ability_id")) != "move":
		if not await _cancel_aim():
			return false
	if wanted == "move" and str(scene.get("_aimed_ability_id")) != "move" \
			and _living_commandable_at(id):
		if not await action("move"):
			return false
	await _click(board.get_global_transform_with_canvas() * board.cell_center(position))
	var choice_button := _visible_button_with_metadata(&"target_id", id)
	if choice_button != null:
		choice_button.pressed.emit()
		await tree.process_frame
	_pending_ability = ""
	var planned: Dictionary = scene.get("_planned_state")
	var override: Dictionary = planned.get("overrides", {}).get(actor, {})
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


## Move normally uses the two-click board path. An occupied hero cell needs
## explicit Move because an ordinary click selects that hero instead.
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
		if not await action(ability):
			return false
	else:
		if target_id.is_empty():
			error = "Targeted ability %s needs a board target" % ability
			return false
		if ability == "move":
			if not await _cancel_aim():
				return false
			if _living_commandable_at(target_id) and not await action(ability):
				return false
		elif not await action(ability):
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
	var context := _action_context(actor)
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


func _action_context(actor: String) -> Dictionary:
	var snapshot: Dictionary = scene.get("_state")
	var planned: Dictionary = scene.get("_planned_state")
	return rules.state_before_action(
		planned if planned.get("overrides", {}).has(actor) else snapshot, actor)


func clear() -> bool:
	var button := scene.find_child("ClearCommand", true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		error = "Clear command unavailable"
		return false
	button.pressed.emit()
	await tree.process_frame
	_pending_ability = ""
	return true


func _press_ability_button(ability: String) -> bool:
	var button := _visible_button_with_metadata(&"ability_id", ability)
	if button == null:
		error = "Visible ability button unavailable: " + ability
		return false
	button.pressed.emit()
	await tree.process_frame
	return true


func _visible_button_with_metadata(key: StringName, id: String) -> Button:
	return _visible_button_search(scene, key, id)


func _visible_button_search(node: Node, key: StringName, id: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).disabled:
		if str(node.get_meta(key, "")) == id:
			return node as Button
	for child in node.get_children():
		var found := _visible_button_search(child, key, id)
		if found != null:
			return found
	return null


func _cancel_aim() -> bool:
	if str(scene.get("_aimed_ability_id")).is_empty():
		return true
	var cancel := scene.find_child("CancelTargeting", true, false) as BaseButton
	if cancel == null or not cancel.is_visible_in_tree() or cancel.disabled:
		error = "Cannot cancel active targeting"
		return false
	cancel.pressed.emit()
	await tree.process_frame
	_pending_ability = ""
	return true


func _living_commandable_at(id: String) -> bool:
	var position: Variant = _position_of(id)
	if position == null:
		return false
	var snapshot: Dictionary = scene.battle_snapshot()
	for unit: Dictionary in snapshot.get("units", []):
		if unit.get("hp", 0) > 0 and unit.get("position") == position \
				and rules.has_capability(snapshot, str(unit.get("id", "")), "commandable"):
			return true
	return false


func _position_of(id: String) -> Variant:
	for unit: Dictionary in scene.battle_snapshot().get("units", []):
		if str(unit.get("id")) == id:
			return unit.get("position")
	var parts := id.split(",")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	return null


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
