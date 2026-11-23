extends RefCounted


static func click(test: SceneTree, button: BaseButton, click_at: Callable) -> bool:
	var scroll := test.call("_node", "RewardScroll") as ScrollContainer
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled \
			or scroll == null or not scroll.is_visible_in_tree() or not scroll.is_ancestor_of(button):
		test.call("_check", false, "Reward click requires an enabled button inside visible RewardScroll")
		return false
	scroll.ensure_control_visible(button)
	await test.process_frame
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled \
			or not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
		test.call("_check", false, "Reward button and scroll must remain available after layout")
		return false
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2.0)
	var viewport := button.get_viewport()
	if not viewport.get_visible_rect().has_point(point):
		test.call("_check", false, "Reward button center is outside the viewport after scrolling")
		return false
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor == scroll or (ancestor as Control).clip_contents):
			var clip := ancestor as Control
			var local_point: Vector2 = clip.get_global_transform_with_canvas().affine_inverse() * point
			if not Rect2(Vector2.ZERO, clip.size).has_point(local_point):
				test.call("_check", false, "Reward button center remains clipped by " + str(clip.name))
				return false
		ancestor = ancestor.get_parent()
	await click_at.call(point)
	return true
