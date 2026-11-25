extends SceneTree
## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/nameplate_occlusion_test.gd -- --capture=/absolute/path.png
## The capture is a reproducible board fixture, not a screenshot of a mission.

const Board = preload("res://presentation/battle/bridge_art.gd")
const CELLS := {
	Vector2i(0, 0): "stone", Vector2i(1, 0): "stone", Vector2i(2, 0): "stone",
	Vector2i(0, 1): "stone", Vector2i(1, 1): "stone", Vector2i(2, 1): "stone",
	Vector2i(0, 2): "stone", Vector2i(1, 2): "stone", Vector2i(2, 2): "stone",
}
const UPPER := {"id": "upper", "cell": Vector2i(1, 0), "art_key": "knight",
	"cast_key": "knight", "hp": 3, "label": "Anxious Knight"}
const LOWER := {"id": "lower", "cell": Vector2i(1, 1), "art_key": "wizard",
	"cast_key": "wizard", "hp": 3}

var board := Board.new()
var viewport := SubViewport.new()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Nameplate occlusion test requires a graphical renderer.")
		board.free()
		viewport.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE * Vector2(3, 3) + Board.GUTTER * 2.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var container := SubViewportContainer.new()
	container.add_child(viewport)
	root.add_child(container)
	await process_frame
	var unlabelled := UPPER.merged({"label": ""}, true)
	var upper_plain := await _render([unlabelled])
	var upper_label := await _render([UPPER])
	var both_plain := await _render([unlabelled, LOWER])
	var both_label := await _render([UPPER, LOWER])

	# Draw only the neighboring figure over known black and white backings,
	# placed above the board but behind its actual figure canvas. Their difference
	# measures per-pixel transmission, including the sprite's antialiased edges.
	var backing := ColorRect.new()
	backing.size = Vector2(viewport.size)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(backing)
	board.move_child(backing, board.get_node("CastAndUnitMarkers").get_index())
	backing.color = Color.BLACK
	var black := await _render([LOWER])
	backing.color = Color.WHITE
	var white := await _render([LOWER])
	backing.queue_free()
	await process_frame

	# With the text behind the figure, the change caused by adding the text
	# must be attenuated by that transmission. Opaque pixels transmit no change;
	# partially transparent edges retain the proportion that passes through.
	# Health is omitted so moving its bar cannot mimic the text.
	var opaque_overlap := 0
	var opaque_covered := 0
	var compositing_errors := 0
	var visible_label := 0
	for y in both_label.get_height():
		for x in both_label.get_width():
			var marker := upper_label.get_pixel(x, y) - upper_plain.get_pixel(x, y)
			if _magnitude(marker) <= 4.0 / 255.0:
				continue
			var transmission := white.get_pixel(x, y) - black.get_pixel(x, y)
			var actual := both_label.get_pixel(x, y) - both_plain.get_pixel(x, y)
			if minf(transmission.r, minf(transmission.g, transmission.b)) >= 253.0 / 255.0:
				if _magnitude(actual) > 4.0 / 255.0:
					visible_label += 1
				continue
			if maxf(transmission.r, maxf(transmission.g, transmission.b)) <= 2.0 / 255.0:
				opaque_overlap += 1
				if _magnitude(actual) > 2.0 / 255.0:
					opaque_covered += 1
			var expected := Color(marker.r * transmission.r, marker.g * transmission.g,
				marker.b * transmission.b)
			if _magnitude(actual - expected) > 2.01 / 255.0:
				compositing_errors += 1
	print("Opaque overlap: %d; covered: %d; compositing errors: %d; visible label pixels: %d" \
		% [opaque_overlap, opaque_covered, compositing_errors, visible_label])
	var capture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	if not capture.is_empty():
		# Include the normal HP bars in the visual evidence, without affecting
		# the isolated marker comparison above.
		var upper_gameplay := UPPER.merged({"max_hp": 3}, true)
		var lower_gameplay := LOWER.merged({"max_hp": 3, "label": "Caster"}, true)
		var evidence := await _render([upper_gameplay, lower_gameplay])
		if evidence.save_png(capture) != OK:
			printerr("Could not save capture: ", capture)
			quit(1)
			return
	if opaque_overlap < 10:
		printerr("FAIL: fixture lacks sufficient opaque figure and label overlap")
		quit(1)
	elif visible_label < 10:
		printerr("FAIL: label is not visible outside the neighboring figure")
		quit(1)
	elif opaque_covered > 0 or compositing_errors > 0:
		printerr("FAIL: label covers %d opaque pixels; %d pixels violate compositing" \
			% [opaque_covered, compositing_errors])
		quit(1)
	else:
		print("PASS: overlapping label does not obscure the neighboring figure")
		quit(0)


func _render(units: Array) -> Image:
	board.set_render_state(CELLS, units)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _magnitude(color: Color) -> float:
	return maxf(absf(color.r), maxf(absf(color.g), absf(color.b)))
