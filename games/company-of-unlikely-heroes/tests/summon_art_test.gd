extends SceneTree
## Run with a graphical display from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/summon_art_test.gd
## Optionally append -- --capture=/absolute/path.png for the rendered comparison.
## The reference PNGs are derived from Ronald's accepted Blender models; their
## provenance and accepted master hashes are in assets/summons/README.md.

const Board = preload("res://bridge_art.gd")
const CELL := Vector2i.ZERO
const CELLS := {CELL: "bridge"}
const MODELS := {
	"skeleton": {"file": "res://assets/summons/skeleton.png", "pivot": Vector2(68, 233)},
	"zombie": {"file": "res://assets/summons/zombie.png", "pivot": Vector2(52, 204)},
}

var board := Board.new()
var viewport := SubViewport.new()
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Summon art test needs a graphical renderer; omit --headless.")
		board.free()
		viewport.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE + Board.GUTTER * 2.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var preview := SubViewportContainer.new()
	preview.add_child(viewport)
	root.add_child(preview)

	var fallback := await _render("unknown_art")
	board.set_render_state(CELLS, [])
	await process_frame
	await RenderingServer.frame_post_draw
	var empty := viewport.get_texture().get_image()
	var frames: Array[Image] = []
	for key in MODELS:
		var model: Dictionary = MODELS[key]
		var source := Image.load_from_file(model.file)
		_check(source != null and not source.is_empty(), "%s model texture must load" % key)
		if source == null or source.is_empty():
			continue
		var right := await _render(key, 1)
		var left := await _render(key, -1)
		frames.append(right)
		frames.append(left)
		_check(_difference(right, fallback, _tile()) > 0.08,
			"%s must not use the unknown-art fallback pawn" % key)
		_check(_difference(right, left, _tile()) > 0.04,
			"%s must respond to facing" % key)
		# Match opaque interior samples to the approved texture, not fixed screen
		# colors. Search a little around the expected placement to allow filtering,
		# small sizing changes, and restrained outline treatments.
		var right_score := _model_score(right, source, model.pivot, false)
		var left_score := _model_score(left, source, model.pivot, true)
		print("%s reference match (lower is better): right %.3f, left %.3f" % [key, right_score, left_score])
		_check(right_score < 0.15, "%s right-facing drawing should use its approved model" % key)
		_check(left_score < 0.15, "%s left-facing drawing should mirror its approved model" % key)
		_check(_transparent_background_fraction(right, empty, source, model.pivot) > 0.65,
			"%s transparent texture background must not cover the board" % key)

		var marked := await _render(key, 1, {"selected": CELL})
		# Selection brackets live at the tile corners, away from the figure.
		var corner := Rect2i(_tile().position, Vector2i(20, 20))
		_check(_difference(right, marked, corner) > 0.06,
			"%s must leave selection brackets visible" % key)
		var unlabelled := await _render(key, 1, {}, "", 2)
		_check(_difference(right, unlabelled, Rect2i(_tile().position + Vector2i(5, 67), Vector2i(86, 13))) > 0.05,
			"%s must retain a visible name marker" % key)
		var no_health := await _render(key, 1, {}, "SUMMON", 0)
		_check(_difference(right, no_health, Rect2i(_tile().position + Vector2i(30, 60), Vector2i(40, 10))) > 0.08,
			"%s must retain a visible health marker" % key)
	if frames.size() == 4:
		_check(_difference(frames[0], frames[2], _tile()) > 0.08,
			"Skeleton and zombie must have distinct appearances")
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				_save_comparison(frames, argument.trim_prefix("--capture="))
	if failures == 0:
		print("Summon art test passed: approved appearances, facing, selection, name and health.")
	quit(1 if failures else 0)


func _render(key: String, facing := 1, overlay: Dictionary = {}, label := "SUMMON", hp := 2) -> Image:
	board.set_render_state(CELLS, [{"id": "summon", "art_key": key, "cell": CELL,
		"facing": facing, "label": label, "hp": hp, "max_hp": hp}], overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _tile() -> Rect2i:
	return Rect2i(Vector2i(board.cell_center(CELL) - Board.TILE * 0.5), Vector2i(Board.TILE))


func _difference(first: Image, second: Image, region: Rect2i) -> float:
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var diff := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(diff.r), maxf(absf(diff.g), absf(diff.b))) > 4.0 / 255.0:
				changed += 1
	return float(changed) / region.get_area()


func _model_score(rendered: Image, source: Image, pivot: Vector2, flipped: bool) -> float:
	var best := 1.0
	var foot := Vector2(_tile().position) + Vector2(49, 62)
	for scale in [0.27, 0.285, 0.30, 0.315, 0.33]:
		var reference: Image = source.duplicate()
		reference.resize(maxi(1, roundi(source.get_width() * scale)),
			maxi(1, roundi(source.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
		if flipped:
			reference.flip_x()
		var left: float = foot.x - (reference.get_width() - pivot.x * scale if flipped else pivot.x * scale)
		var top: float = foot.y - pivot.y * scale
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var total := 0.0
				var count := 0
				for y in range(1, reference.get_height(), 3):
					for x in range(1, reference.get_width(), 3):
						var sample := reference.get_pixel(x, y)
						var at := Vector2i(roundi(left) + dx + x, roundi(top) + dy + y)
						if sample.a < 0.95 or not _tile().has_point(at) or at.y >= foot.y:
							continue
						var actual := rendered.get_pixelv(at)
						total += (absf(sample.r - actual.r) + absf(sample.g - actual.g) + absf(sample.b - actual.b)) / 3.0
						count += 1
				if count >= 30:
					best = minf(best, total / count)
	return best


func _transparent_background_fraction(rendered: Image, empty: Image, source: Image, pivot: Vector2) -> float:
	var foot := Vector2(_tile().position) + Vector2(49, 62)
	var start := foot - pivot * 0.30
	var unchanged := 0
	var count := 0
	for y in range(0, source.get_height(), 10):
		for x in range(0, source.get_width(), 10):
			var at := Vector2i(start + Vector2(x, y) * 0.30)
			# Avoid antialiased edges, the unit's shadow, and marker area.
			if source.get_pixel(x, y).a > 0.01 or not _tile().has_point(at) or at.y >= foot.y - 5:
				continue
			var diff := rendered.get_pixelv(at) - empty.get_pixelv(at)
			if maxf(absf(diff.r), maxf(absf(diff.g), absf(diff.b))) < 4.0 / 255.0:
				unchanged += 1
			count += 1
	return float(unchanged) / count if count > 0 else 0.0


func _save_comparison(frames: Array[Image], path: String) -> void:
	var frame := frames[0]
	var sheet := Image.create(frame.get_width() * frames.size(), frame.get_height(), false, frame.get_format())
	for index in range(frames.size()):
		sheet.blit_rect(frames[index], Rect2i(Vector2i.ZERO, frame.get_size()),
			Vector2i(index * frame.get_width(), 0))
	_check(sheet.save_png(path) == OK, "Could not write capture to %s" % path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
