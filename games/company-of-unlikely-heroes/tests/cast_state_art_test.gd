extends SceneTree
## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/cast_state_art_test.gd

const Board = preload("res://bridge_art.gd")
const CELL := Vector2i.ZERO
const CELLS := {CELL: "bridge"}

var board := Board.new()
var viewport := SubViewport.new()
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Cast state art test requires a graphical renderer.")
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

	await _ko_overrides_live_action()
	await _knockdown_overrides_live_heal()
	await _recovered_shield_overrides_live_throw()
	await _wizard_pull_finishes_seated()
	if failures == 0:
		print("Cast state art test passed: KO, shield recovery and Pull seating.")
	quit(1 if failures else 0)


func _ko_overrides_live_action() -> void:
	var alive := _unit("wizard", {"hp": 3, "max_hp": 3})
	await _state(alive)
	_cue("wizard", "blast")
	_advance(0.2)
	_check(not board.action_playback_snapshot().is_empty(), "Blast cue must still be live")
	var knocked_out := _unit("wizard", {"hp": 0, "max_hp": 3})
	var with_cue := await _state(knocked_out)
	board.clear_action_playback()
	board.set_process(false)
	var without_cue := await _capture()
	_check(_difference(with_cue, without_cue) == 0,
		"KO must override a live action, including its standing pose")
	var standing := await _state(alive)
	_check(_difference(without_cue, standing) > 100, "KO must visibly differ from standing")


func _knockdown_overrides_live_heal() -> void:
	board.clear_action_playback()
	await _state(_unit("healer", {"hp": 3, "max_hp": 3}))
	_cue("healer", "ally_heal")
	_advance(0.2)
	var down := _unit("healer", {"prone": true, "hp": 2, "max_hp": 3})
	var with_cue := await _state(down)
	_check(not board.action_playback_snapshot().is_empty(), "Heal cue must still be live")
	board.clear_action_playback()
	board.set_process(false)
	var without_cue := await _capture()
	_check(_difference(with_cue, without_cue) == 0,
		"An unrelated knockdown must override a living Healer's live cast")
	var standing := await _state(_unit("healer", {"hp": 2, "max_hp": 3}))
	_check(_difference(without_cue, standing) > 100, "Knocked-down Healer must remain visibly prone")


func _recovered_shield_overrides_live_throw() -> void:
	board.clear_action_playback()
	var away := _unit("knight", {"shield_away": true})
	await _state(away)
	_cue("knight", "shield_away")
	_advance(0.1)
	var recovered := _unit("knight", {"shield_away": false})
	var with_cue := await _state(recovered)
	_check(not board.action_playback_snapshot().is_empty(), "Shield-away cue must still be live")
	board.clear_action_playback()
	board.set_process(false)
	var without_cue := await _capture()
	_check(_difference(with_cue, without_cue) == 0,
		"Recovered shield must override the still-live shield-away cue")
	var shield_away := await _state(away)
	_check(_difference(without_cue, shield_away) > 100,
		"Recovered and away shield states must be visually distinct")


func _wizard_pull_finishes_seated() -> void:
	board.clear_action_playback()
	var down := _unit("wizard", {"prone": true, "hp": 2, "max_hp": 3})
	await _state(down)
	_cue("wizard", "pull")
	var first := await _capture()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cast/manifest.json"))
	var frames: Array = manifest.actors.wizard.clips.pull.frames
	var duration_ms := 0.0
	for frame in frames:
		duration_ms += float(frame.duration_ms)
	_advance((duration_ms - float(frames.back().duration_ms) * 0.5) / 1000.0)
	var last := await _capture()
	_check(_difference(first, last) > 100, "Pull must animate rather than jump straight to seated")
	_advance(1.0)
	_check(board.action_playback_snapshot().is_empty(), "Pull cue must finish")
	var seated := await _capture()
	_check(_difference(last, seated) == 0, "Finished Pull must hold its final seated frame")
	var standing := await _state(_unit("wizard", {"hp": 2, "max_hp": 3}))
	_check(_difference(seated, standing) > 100, "Recovery must clear the seated pose")
	var down_again := await _state(down)
	_check(_difference(seated, down_again) > 100,
		"A later ordinary knockdown must not reuse the earlier Pull pose")


func _unit(role: String, extra: Dictionary = {}) -> Dictionary:
	var unit := {"id": role, "art_key": role, "cast_key": role, "cell": CELL, "facing": 1}
	unit.merge(extra, true)
	return unit


func _state(unit: Dictionary) -> Image:
	board.set_render_state(CELLS, [unit])
	# Freeze animation so comparisons exercise state, not frame timing.
	board.set_process(false)
	return await _capture()


func _cue(role: String, clip: String) -> void:
	board.play_committed_actions([{"unit_id": role, "cast_key": role, "clip": clip,
		"source_cell": CELL}])
	board.set_process(false)


func _advance(seconds: float) -> void:
	board._process(seconds)
	board.set_process(false)


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _difference(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
