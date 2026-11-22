extends RefCounted

# Search by player-facing text rather than imposing a particular modal layout.
static func button(root: Node, words: Array, except: BaseButton = null) -> BaseButton:
	for node in root.find_children("*", "BaseButton", true, false):
		var candidate := node as BaseButton
		if candidate == except or candidate.disabled or not candidate.is_visible_in_tree():
			continue
		var text := (candidate as Button).text if candidate is Button else ""
		var label := (text + " " + candidate.accessibility_name).strip_edges().to_lower()
		for word in words:
			if label.contains(word):
				return candidate
	return null


static func click(tree: SceneTree, control: Control) -> void:
	var viewport := control.get_viewport()
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	await tree.process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		viewport.push_input(event, true)
		await tree.process_frame
