extends SceneTree
## Run with a graphical display from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/cast_idle_identity_test.gd

const Board = preload("res://presentation/battle/bridge_art.gd")
const CELL := Vector2i.ZERO
const IDS := ["healer_a", "healer_b"]
const SAMPLES := 12

var board := Board.new()
var viewport := SubViewport.new()
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Cast idle identity test needs a graphical renderer; omit --headless.")
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
	var container := SubViewportContainer.new()
	container.add_child(viewport)
	root.add_child(container)
	_set_unit(IDS[0])
	var ready = board.get("_cast").clip_for("healer", "ready")
	if ready == null or not ready.loop or ready.frames.size() < 2:
		_check(false, "Fixture needs the animated Healer ready clip")
		quit(1)
		return

	# Compare the two identities' relative poses over the same interval, then
	# after many original loop lengths. A constant phase offset, even a nonzero
	# one, repeats the same equality pattern and cannot satisfy this check.
	var early := []
	var late := []
	for id in IDS:
		early.append(await _sample_idle(id, 0.0, ready.total_ms))
		late.append(await _sample_idle(id, 30.0 * ready.total_ms, ready.total_ms))
	var different_relative_phase := false
	for index in SAMPLES:
		var early_equal := _difference(early[0][index], early[1][index]) < 10
		var late_equal := _difference(late[0][index], late[1][index]) < 10
		if early_equal != late_equal:
			different_relative_phase = true
	_check(different_relative_phase, "Identical models with different IDs drift in relative idle speed, not just phase")

	var replay := await _sample_idle(IDS[0], 0.0, ready.total_ms)
	for index in SAMPLES:
		_check(_difference(early[0][index], replay[index]) == 0,
			"Same identity and elapsed time reproduce the same idle pose")

	await _check_action_timing()
	for id in IDS:
		await _check_idle_redraw(id, ready)
	if failures == 0:
		print("Cast idle identity test passed.")
	quit(1 if failures else 0)


func _set_unit(id: String) -> void:
	board.clear_action_playback()
	board.set_render_state({CELL: "bridge"}, [
		{"id": id, "art_key": "healer", "cast_key": "healer", "cell": CELL, "facing": 1}
	], {})
	board.set_process(false)


func _sample_idle(id: String, start_ms: float, period_ms: float) -> Array:
	_set_unit(id)
	var images := []
	for index in SAMPLES:
		board.set("_ready_ms", start_ms + (index + 0.37) * period_ms / SAMPLES)
		board.get("_figures").queue_redraw()
		images.append(await _image())
	return images


func _check_action_timing() -> void:
	var clip = board.get("_cast").clip_for("healer", "bonk")
	if clip == null or clip.frame_ends.size() < 2:
		_check(false, "Fixture needs a multi-frame Bonk clip")
		return
	var visible_boundary := false
	for index in clip.frame_ends.size() - 1:
		var boundary: float = clip.frame_ends[index]
		var before := await _sample_action("reference", boundary - 0.25, true)
		var after := await _sample_action("reference", boundary + 0.25, true)
		if before == null or after == null:
			return
		if _difference(before, after) <= 10:
			continue
		visible_boundary = true
		for id in IDS:
			var actual_before := await _sample_action(id, boundary - 0.25)
			var actual_after := await _sample_action(id, boundary + 0.25)
			if actual_before == null or actual_after == null:
				return
			_check(_difference(before, actual_before) == 0 and _difference(after, actual_after) == 0,
				"%s Bonk uses unscaled time on both sides of boundary %.2f" % [id, boundary])
	_check(visible_boundary, "Bonk fixture has a visibly changing frame boundary")


func _sample_action(id: String, elapsed_ms: float, unscaled := false) -> Image:
	_set_unit(id)
	if unscaled:
		board.get("_ready_rates")[id] = 1.0
	board.set("_ready_ms", 1729.0)
	board.play_committed_actions([
		{"unit_id": id, "cast_key": "healer", "clip": "bonk", "source_cell": CELL}
	])
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.is_empty():
		_check(false, "Committed bonk enters playback")
		return null
	board._process(elapsed_ms / 1000.0)
	board.set_process(false)
	return await _image()


func _check_idle_redraw(id: String, ready) -> void:
	_set_unit(id)
	var rate: float = board.get("_ready_rates")[id]
	_check(not is_equal_approx(rate, 1.0), id + " fixture needs a rate distinct from one")
	if is_equal_approx(rate, 1.0):
		return
	var visible_boundary := false
	for index in ready.frame_ends.size() - 1:
		var raw_boundary: float = ready.frame_ends[index]
		var boundary: float = raw_boundary / rate
		var previous: float = 0.0 if index == 0 else ready.frame_ends[index - 1] / rate
		var next: float = ready.frame_ends[index + 1] / rate
		# Both samples lie between the neighbouring scaled boundaries and on
		# the same side of the unscaled boundary.
		var margin := minf(absf(boundary - raw_boundary) / 4.0,
			minf(boundary - previous, next - boundary) / 4.0)
		var before_time := boundary - margin
		var after_time := boundary + margin
		var before := await _forced_idle(id, before_time)
		var expected := await _forced_idle(id, after_time)
		if _difference(before, expected) <= 10:
			continue
		visible_boundary = true
		_set_unit(id)
		board.set("_ready_ms", before_time)
		board.get("_figures").queue_redraw()
		await _image()
		board._process((after_time - before_time) / 1000.0)
		board.set_process(false)
		var actual := await _image()
		_check(_difference(actual, expected) == 0,
			"%s redraws at its scaled idle boundary without crossing the raw boundary" % id)
		break
	_check(visible_boundary, id + " ready fixture has a visibly changing frame boundary")


func _forced_idle(id: String, at_ms: float) -> Image:
	_set_unit(id)
	board.set("_ready_ms", at_ms)
	board.get("_figures").queue_redraw()
	return await _image()


func _image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _difference(first: Image, second: Image) -> int:
	var changed := 0
	for y in first.get_height():
		for x in first.get_width():
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
