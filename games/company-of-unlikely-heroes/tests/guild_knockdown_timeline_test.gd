extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_knockdown_timeline_test.gd
## Test-owned clips isolate ordering and impact boundaries from packaged artwork.

const Sprites = preload("res://presentation/cast_sprites.gd")
const Playback = preload("res://presentation/cast_playback.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_test_action_order()
	_test_move_action_order()
	var art := Sprites.new()
	art.set("_actors", {
		"wizard": {"blast": _clip([1, 17], [500.0, 500.0])},
		"rogue": {"potion": _clip([1, 15], [600.0, 400.0]),
			"down": _clip([1, 16, 24], [625.0, 333.0, 167.0]),
			"recover": _clip([1, 22, 26], [875.0, 167.0, 125.0]),
			"defeat": _clip([1, 4, 8, 12, 16, 20, 24],
				[125.0, 167.0, 166.0, 167.0, 167.0, 166.0, 167.0])},
	})
	var timeline := Playback.new()
	timeline.enqueue([
		{"unit_id": "caster", "cast_key": "wizard", "clip": "blast"},
		{"unit_id": "target", "cast_key": "rogue", "clip": "down",
			"hero_knockdown": "down", "after_cue": 0},
		{"unit_id": "target", "cast_key": "rogue", "clip": "recover", "hero_knockdown": "recover"},
	], art)
	_check(timeline.active().size() == 1 and timeline.hero_pending_pose("target") == "ready",
		"Victim remains upright until the attacker's impact")
	timeline.advance(500.0)
	var active := timeline.active()
	_check(active.any(func(entry): return entry.cue.get("unit_id") == "target" and entry.cue.clip == "down") \
		and not active.any(func(entry): return entry.cue.get("clip") == "recover"),
		"Fall starts at impact and recovery waits for the whole fall")
	timeline.advance(1125.0)
	active = timeline.active()
	_check(active.size() == 1 and active[0].cue.clip == "recover" \
		and is_equal_approx(active[0].impact_ms, 875.0),
		"Recovery starts only after the fall and uses its planted-rise frame")

	timeline.clear()
	timeline.enqueue([
		{"unit_id": "target", "cast_key": "rogue", "clip": "potion"},
		{"unit_id": "target", "cast_key": "rogue", "clip": "down",
			"hero_knockdown": "down", "after_cue": 0},
	], art)
	timeline.advance(999.0)
	_check(timeline.active().size() == 1 and timeline.active()[0].cue.clip == "potion",
		"Self-potion completes before its own Jelly Knees fall")
	timeline.advance(1.0)
	_check(timeline.active().size() == 1 and timeline.active()[0].cue.clip == "down" \
		and is_equal_approx(timeline.active()[0].impact_ms, 625.0),
		"Self-potion fall starts after the dose and uses the contact frame")

	timeline.clear()
	timeline.enqueue([
		{"unit_id": "target", "cast_key": "rogue", "clip": "recover", "hero_knockdown": "recover"},
		{"unit_id": "target", "cast_key": "rogue", "clip": "down", "hero_knockdown": "down"},
	], art)
	timeline.advance(1166.0)
	_check(timeline.active().size() == 1 and timeline.active()[0].cue.clip == "recover",
		"Same-round later knockdown does not interrupt recovery")
	timeline.advance(1.0)
	_check(timeline.active().size() == 1 and timeline.active()[0].cue.clip == "down",
		"Same-round later knockdown follows recovery exactly once")
	timeline.clear()
	timeline.enqueue([
		{"unit_id": "caster", "cast_key": "wizard", "clip": "blast"},
		{"unit_id": "target", "cast_key": "rogue", "clip": "defeat",
			"hero_defeat": true, "was_prone": true, "after_cue": 0},
	], art)
	timeline.advance(500.0)
	active = timeline.active()
	var defeats := active.filter(func(entry): return entry.cue.get("hero_defeat", false))
	_check(defeats.size() == 1 and is_equal_approx(defeats[0].sample_offset_ms, 625.0) \
		and defeats[0].clip.source_frames[defeats[0].clip.frame_index(defeats[0].sample_offset_ms)] == 16,
		"A lethal hit on a down hero starts the collapse at floor contact, never upright")
	for message in failures:
		push_error("FAIL: " + message)
	if failures.is_empty():
		print("PASS: guild knockdown playback chronology")
	quit(0 if failures.is_empty() else 1)


func _test_action_order() -> void:
	var art := Sprites.new()
	art.set("_actors", {
		"wizard": {"blast": _clip([1, 17, 25], [500.0, 100.0, 900.0])},
		"healer": {"bonk": _clip([1, 15, 20], [100.0, 100.0, 800.0])},
	})
	var timeline := Playback.new()
	timeline.enqueue([
		{"unit_id": "first", "cast_key": "wizard", "clip": "blast"},
		{"unit_id": "second", "cast_key": "healer", "clip": "bonk"},
	], art)
	# Windups may overlap. Only the consequential moments must retain order.
	var first_impact := -1
	var second_impact := -1
	for time_ms in range(0, 4001, 10):
		for entry in timeline.active():
			if entry.elapsed_ms >= entry.impact_ms:
				if entry.cue.unit_id == "first" and first_impact < 0:
					first_impact = time_ms
				if entry.cue.unit_id == "second" and second_impact < 0:
					second_impact = time_ms
		timeline.advance(10.0)
	_check(first_impact >= 0 and second_impact > first_impact,
		"Different performers show both committed action impacts in resolution order")


func _test_move_action_order() -> void:
	var art := Sprites.new()
	art.set("_actors", {
		"scout": {"run": _clip([1, 8, 16], [400.0, 100.0, 700.0])},
		"wizard": {"blast": _clip([1, 17, 25], [100.0, 100.0, 800.0])},
	})
	var timeline := Playback.new()
	timeline.enqueue([
		{"unit_id": "mover", "cast_key": "scout", "clip": "run",
			"ordinary_presentation": true, "ordinary_role": "action", "ordinary_handler": "move",
			"source_cell": Vector2i(1, 1), "actor_cell": Vector2i(2, 1), "impact_frame": 8},
		{"unit_id": "caster", "cast_key": "wizard", "clip": "blast"},
	], art)
	var move_moment := -1
	var blast_moment := -1
	for time_ms in range(0, 4001, 10):
		for entry in timeline.active():
			if entry.elapsed_ms >= entry.impact_ms:
				if entry.cue.unit_id == "mover" and move_moment < 0:
					move_moment = time_ms
				if entry.cue.unit_id == "caster" and blast_moment < 0:
					blast_moment = time_ms
		timeline.advance(10.0)
	_check(move_moment >= 0 and blast_moment > move_moment,
		"A committed move's key moment precedes the later performer's action impact")


func _clip(frames: Array[int], durations: Array[float]) -> Sprites.Clip:
	var clip := Sprites.Clip.new()
	clip.loop = false
	for index in frames.size():
		clip.frames.append(Rect2(0, 0, 1, 1))
		clip.source_frames.append(frames[index])
		clip.total_ms += durations[index]
		clip.frame_ends.append(clip.total_ms)
	return clip


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
