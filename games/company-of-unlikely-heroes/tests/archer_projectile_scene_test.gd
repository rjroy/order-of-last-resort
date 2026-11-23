extends "res://tests/stock_cast_mission_test.gd"
## Use the stock Hold the Line reserve route and packaged Archer artwork.

const Playback = preload("res://presentation/cast_playback.gd")
var checked_flight := false


func _sample_case_detail(board: Node, round_number: int, value: Variant) -> void:
	var entry := value as Playback.Entry
	if checked_flight or entry == null or entry.cue.get("cast_key") != "archer" \
			or entry.cue.get("clip") != "draw_and_release":
		return
	checked_flight = true
	var native_release := entry.gift != null and entry.clip.release_clip == "arrow_projectile" \
		and entry.clip.release_ms >= 0.0 and entry.gift.tip is Vector2
	_check(native_release, "Stock shot supplies the native detached arrow at its authored release")
	if not native_release:
		return
	var sample := entry.clip.release_ms + Playback.GIFT_FLIGHT_MS * 0.5
	board.call("_process", maxf(0.0, sample - entry.elapsed_ms) / 1000.0)
	board.set_process(false)
	var projected := entry.gift_from is Vector2 and entry.gift_to is Vector2 \
		and entry.cue.get("actor_cell") is Vector2i and entry.cue.get("target_cell") is Vector2i
	_check(projected and is_equal_approx(entry.flight_progress(), 0.5),
		"Detached arrow is projected on the live board at midflight")
	if not projected:
		return
	var facing := Vector2(entry.facing, 1.0)
	var foot: Vector2 = board.call("_unit_foot", entry.cue.actor_cell)
	var hand := foot + entry.clip.release_offset * facing * entry.clip.scale
	var aim: Vector2 = board.call("_unit_foot", entry.cue.target_cell) + Vector2(0, -29)
	var tip: Vector2 = ((entry.gift.tip - entry.gift.anchor) * facing * entry.gift.scale).rotated(entry.gift_angle)
	_check(hand.is_equal_approx(entry.gift_from), "Detached arrow starts at the Archer's authored hand")
	_check(entry.gift_point_first and tip.normalized().dot((aim - hand).normalized()) > 0.999,
		"Arrow points from the hand toward its committed target")
	_check(aim.is_equal_approx(entry.gift_to + tip), "Arrow lands its tip, not its anchor, on the resolved target")
	await _capture("round-%02d-arrow-midflight.png" % round_number)
	await _check_visible_arrow(board, entry)


func _check_visible_arrow(board: Node, entry: Playback.Entry) -> void:
	var with_arrow := viewport.get_texture().get_image()
	var origin: Vector2 = entry.gift_from
	# Redraw the same frozen board without just this projectile. This checks
	# pixels from the detached atlas rather than motion in the Archer pose.
	entry.gift_from = null
	board.get("_figures").queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_arrow := viewport.get_texture().get_image()
	entry.gift_from = origin
	board.get("_figures").queue_redraw()
	var changed := 0
	for y in with_arrow.get_height():
		for x in with_arrow.get_width():
			if with_arrow.get_pixel(x, y) != without_arrow.get_pixel(x, y):
				changed += 1
	_check(changed > 25, "Detached arrow visibly paints on the stock board")
	print("Archer detached arrow: %d changed pixels at midflight" % changed)


func _finish(error: String) -> void:
	if error.is_empty():
		_check(checked_flight, "Stock route committed and sampled the Archer's detached projectile")
	super._finish(error)
