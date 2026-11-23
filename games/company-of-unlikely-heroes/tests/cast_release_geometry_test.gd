extends SceneTree
## In-memory atlas geometry; no approved packet or display server required.

const Board = preload("res://bridge_art.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")
const Playback = preload("res://presentation/cast_playback.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var board := Board.new()
	var art := Sprites.new()
	var launch := Sprites.Clip.new()
	launch.total_ms = 1000.0
	launch.release_ms = 667.0
	launch.release_offset = Vector2(17, -111)
	launch.release_clip = "fixture_detached"
	launch.scale = 0.6
	var detached := Sprites.Clip.new()
	detached.anchor = Vector2(82, 4)
	detached.tip = Vector2(8, 42)
	detached.scale = 0.7
	art.set("_actors", {"unrelated_fixture": {"fixture_gesture": launch, "fixture_detached": detached}})
	var playback: Playback = board.get("_playback")
	for side: int in [-1, 1]:
		var source := Vector2i(3, 2)
		var target := Vector2i(3 + side * 2, 3)
		var cue := {"unit_id": "fixture", "cast_key": "unrelated_fixture", "clip": "fixture_gesture",
			"ordinary_presentation": true, "source_cell": source, "actor_cell": source,
			"target_cell": target, "target_id": "recipient"}
		playback.enqueue([cue], art)
		var entry: Playback.Entry = playback.active()[0]
		_check(entry.gift == detached and is_equal_approx(entry.impact_ms, 967.0),
			"Valid detached art schedules impact after the manifest release plus flight")
		playback.advance(launch.release_ms - 1.0)
		board.call("_sync_playback_geometry")
		_check(entry.gift_from == null, "Detached artwork is not placed before the authored release")
		playback.advance(1.0)
		board.call("_sync_playback_geometry")
		var flip := Vector2(side, 1.0)
		var origin: Vector2 = board.call("_unit_foot", source) + launch.release_offset * flip * launch.scale
		var landing: Vector2 = board.call("_unit_foot", target) + Vector2(0, -29)
		var tip: Vector2 = (detached.tip - detached.anchor) * flip * detached.scale
		tip = tip.rotated(entry.gift_angle)
		_check(entry.gift_point_first and origin.is_equal_approx(entry.gift_from),
			"Tip-authored art of either facing starts at the authored hand anchor")
		_check(landing.is_equal_approx(entry.gift_to + tip) \
			and tip.normalized().is_equal_approx((landing - origin).normalized()),
			"Tip aligns with flight and lands on target in either facing")
		playback.clear()
		var saved_tip: Variant = detached.tip
		detached.tip = null
		playback.enqueue([cue], art)
		playback.advance(launch.release_ms)
		board.call("_sync_playback_geometry")
		entry = playback.active()[0]
		_check(not entry.gift_point_first and landing.is_equal_approx(entry.gift_to),
			"Untipped detached art retains anchor-based landing and tumble")
		playback.clear()
		detached.tip = saved_tip
		cue.erase("target_cell")
		playback.enqueue([cue], art)
		entry = playback.active()[0]
		_check(entry.gift == null and is_equal_approx(entry.impact_ms, 480.0),
			"Without a resolved aim cell, retain the gesture but not a ghost release")
		playback.clear()
	board.get("_figures").free()
	board.free()
	for message in failures:
		push_error(message)
	if failures.is_empty():
		print("PASS: detached cast release geometry and fallbacks")
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
