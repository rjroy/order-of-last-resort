extends SceneTree
## godot --path games/company-of-unlikely-heroes --script res://tests/ordinary_cast_renderer_test.gd
## Test-owned in-memory atlas. No unapproved runtime artwork is required.

const Board = preload("res://bridge_art.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")
const CELL := Vector2i.ZERO
var failures: Array[String] = []
var board := Board.new()
var viewport := SubViewport.new()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		board.free()
		viewport.free()
		printerr("A graphical renderer is required.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE + Board.GUTTER * 2.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var container := SubViewportContainer.new()
	container.add_child(viewport)
	root.add_child(container)
	await process_frame
	_install_test_atlas()
	var alive := {"id": "instance", "cell": CELL, "art_key": "unknown",
		"cast_key": "fixture_actor", "cast_lifecycle": {"hit": "flinch", "defeat": "fall"}, "hp": 1}
	var dead := alive.merged({"hp": 0, "prone": true}, true)
	await _set_state(alive)
	var ready := await _image()
	board.play_committed_actions([_cue("poke"), _cue("fall", "defeat")])
	board.set_process(false)
	await _set_state(dead)
	var dead_action := await _image()
	await _set_state(alive)
	var alive_action := await _image()
	_check(_difference(_figure(dead_action), _figure(alive_action)) == 0,
		"Future corpse does not suppress a generic actor's active attack")
	_check(_difference(_figure(ready), _figure(alive_action)) > 20,
		"Committed action actually differs from generic ready")
	await _set_state(dead)
	board._process(0.38)
	board.set_process(false)
	var falling := await _image()
	_check(_difference(_figure(falling), _figure(dead_action)) > 20,
		"Queued generic defeat follows the preceding action")
	var active: Array = board.get("_playback").active()
	var defeat = null
	for entry in active:
		if entry.cue.get("unit_id") == "instance" and entry.cue.get("clip") == "fall":
			defeat = entry
	if defeat == null:
		_check(false, "Short defeat is active before testing its feedback tail")
	else:
		var sample_ms: float = (defeat.clip.total_ms + defeat.duration_ms) * 0.5
		board._process((sample_ms - defeat.elapsed_ms) / 1000.0)
		board.set_process(false)
		_check(defeat.elapsed_ms > defeat.clip.total_ms and defeat.elapsed_ms < defeat.duration_ms,
			"Sample is strictly inside defeat's feedback tail, after the animation ends")
		_check(board.action_playback_snapshot().any(func(cue): return cue.get("unit_id") == "instance" \
			and cue.get("clip") == "fall"), "Defeat remains queued during the feedback tail")
		var tail := await _image()
		_check(_blue_pixels(_figure(tail)) > 20,
			"Short defeat holds its final blue frame during the feedback tail instead of flashing ready")
	board._process(2.0)
	board.set_process(false)
	var settled := await _image()
	_check(board.action_playback_snapshot().is_empty(), "Generic actor queue finishes")
	_check(_blue_pixels(_figure(falling)) > 20 and _blue_pixels(_figure(settled)) > 20,
		"Generic actor plays and settles on the declared blue defeat frame")
	board.clear_action_playback()
	await _set_state(alive)
	board.play_committed_actions([_cue("flinch", "hit")])
	board.set_process(false)
	var prone := alive.merged({"prone": true}, true)
	await _set_state(prone)
	var prone_hit := await _image()
	await _set_state(alive)
	var upright_hit := await _image()
	_check(_difference(_figure(prone_hit), _figure(upright_hit)) == 0,
		"Surviving actor's committed ordinary hit renders before its final prone pose")
	board.clear_action_playback()
	await _set_state(prone)
	var prone_rest := await _image()
	_check(_difference(_figure(prone_hit), _figure(prone_rest)) > 20,
		"Committed hit differs from final prone rest")
	board.play_committed_actions([_cue("flinch", "action")])
	board.set_process(false)
	var colliding_hit_action := await _image()
	_check(_difference(_figure(prone_rest), _figure(colliding_hit_action)) == 0,
		"An action sharing the hit clip is not treated as a hit reaction")
	board.clear_action_playback()
	await _set_state(dead)
	var dead_rest := await _image()
	board.play_committed_actions([_cue("fall", "action")])
	board.set_process(false)
	var colliding_defeat_action := await _image()
	_check(_difference(dead_rest, colliding_defeat_action) == 0,
		"An action sharing the defeat clip does not stage or hide the final corpse")
	board.clear_action_playback()
	await _set_pending_state(prone)
	var parent := _cue("poke", "action")
	parent.unit_id = "attacker"
	parent.source_cell = Vector2i(1, 0)
	parent.actor_cell = Vector2i(1, 0)
	var pending := _cue("flinch", "hit")
	pending["after_cue"] = 0
	board.play_committed_actions([parent, pending])
	board.set_process(false)
	var queued: Array = board.get("_playback").get("_entries")
	_check(queued.size() == 2 and queued[1].elapsed_ms < 0.0,
		"Victim's ordinary hit is truly scheduled after its attacker's impact")
	var waiting_prone := await _image()
	await _set_pending_state(alive)
	var waiting_ready := await _image()
	_check(_difference(_figure(waiting_prone), _figure(waiting_ready)) == 0,
		"A newly prone living actor stays ready while its committed hit is pending")
	board.clear_action_playback()
	await _set_pending_state(prone)
	pending["was_prone"] = true
	board.play_committed_actions([parent, pending])
	board.set_process(false)
	var waiting_already_prone := await _image()
	var pending_entries: Array = board.get("_playback").get("_entries")
	pending_entries.pop_back()
	board.get("_figures").queue_redraw()
	var already_prone := await _image()
	_check(_difference(_figure(already_prone), _figure(waiting_already_prone)) == 0,
		"An actor already prone before the hit does not stand up while waiting")
	if failures.is_empty():
		print("PASS: ordinary actor renderer with in-memory atlas")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _install_test_atlas() -> void:
	var path := "res://tests/ordinary-test-memory.png"
	var image := Image.create(96, 32, false, Image.FORMAT_RGBA8)
	for i in 3:
		image.fill_rect(Rect2i(i * 32, 0, 32, 32), [Color.RED, Color.GREEN, Color.BLUE][i])
	Sprites._textures[path] = ImageTexture.create_from_image(image)
	var clips := {}
	for i in 3:
		var clip = Sprites.Clip.new()
		clip.path = path
		clip.anchor = Vector2(16, 30)
		clip.scale = 1.0
		clip.loop = false
		clip.frames.append(Rect2(i * 32, 0, 32, 32))
		clip.frame_ends.append(200.0)
		clip.source_frames.append(1)
		clip.total_ms = 200.0
		clips[["ready", "poke", "fall"][i]] = clip
	board.get("_cast").get("_actors")["fixture_actor"] = clips
	clips["flinch"] = clips["poke"]


func _set_state(unit: Dictionary) -> void:
	board.set_render_state({CELL: "stone"}, [unit])
	board.set_process(false)
	await process_frame


func _set_pending_state(unit: Dictionary) -> void:
	var attacker := {"id": "attacker", "cell": Vector2i(1, 0), "art_key": "unknown",
		"cast_key": "fixture_actor", "cast_lifecycle": {"hit": "flinch", "defeat": "fall"}, "hp": 1}
	board.set_render_state({CELL: "stone", Vector2i(1, 0): "stone"}, [unit, attacker])
	board.set_process(false)
	await process_frame


func _cue(clip: String, role := "action") -> Dictionary:
	return {"unit_id": "instance", "cast_key": "fixture_actor", "clip": clip,
		"ordinary_presentation": true, "ordinary_role": role,
		"source_cell": CELL, "actor_cell": CELL, "target_id": "", "recipients": []}


func _image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _figure(image: Image) -> Image:
	var foot: Vector2 = board.get("_map_origin") \
		+ (board.call("_tile_origin", CELL) + Board.FOOT) * board.get("_map_scale")
	return image.get_region(Rect2i(0, 0, image.get_width(), clampi(int(foot.y - 25), 1, image.get_height())))


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func _blue_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.b > 0.8 and color.r < 0.2 and color.g < 0.2:
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
