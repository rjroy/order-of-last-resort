extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/music_playlist_test.gd
## Playlist inputs belong to this test, not to the shipped music catalog.

var failures: Array[String] = []


func _initialize() -> void:
	var script = load("res://presentation/audio/music_playlist.gd")
	if script == null:
		push_error("FAIL: missing music playlist")
		quit(1)
		return
	var tracks := ["one", "two", "three", "four"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 70823
	var bag = script.new(tracks, rng)
	var sequences: Array = []
	for cycle in 8:
		var drawn: Array = []
		for index in tracks.size():
			drawn.append(bag.next_track())
		var sorted := drawn.duplicate()
		sorted.sort()
		var expected := tracks.duplicate()
		expected.sort()
		_check(sorted == expected, "Each cycle exhausts all tracks exactly once")
		sequences.append(drawn)
	_check(sequences.any(func(value): return value != sequences[0]),
		"Seeded draws actually shuffle rather than always using a fixed ordering")
	var singleton = script.new(["only"], rng)
	for index in 4:
		_check(singleton.next_track() == "only", "A singleton can be drawn repeatedly")
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: music_playlist_test")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
