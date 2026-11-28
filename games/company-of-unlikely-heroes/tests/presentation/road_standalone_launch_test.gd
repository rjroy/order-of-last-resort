extends SceneTree

# Run once per mission, with no --party:
# godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/road_standalone_launch_test.gd -- --mission=<id>
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("--mission="):
		_fail("Supply exactly one --mission=<id>, without party or loadout overrides")
		return
	var id: String = args[0].trim_prefix("--mission=")
	var defs: Dictionary = Catalog.read_default()
	if not defs.get("missions", {}).has(id):
		_fail("Mission is not enrolled in the default catalog: " + id)
		return
	var party: Array = defs.missions[id].get("default_party", [])
	if party.is_empty():
		_fail("Mission has no authored default party: " + id)
		return
	var expected: Dictionary = Rules.open_mission(defs, id, party)
	if expected.is_empty():
		_fail("Cannot open authored mission: " + id)
		return
	# No configure_launch: main reads the real user arguments after --.
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if scene.current_screen() != "battle":
		_fail("Expected battle for " + id + ", got " + scene.current_screen())
		return
	var opening: Dictionary = scene.battle_snapshot()
	if opening.get("mission_id") != id or opening.get("party") != party:
		_fail("Wrong mission or authored party for " + id)
		return
	for key in ["units", "obstacles", "orders", "objective", "terrain", "width", "height"]:
		if opening.get(key) != expected.get(key):
			_fail(id + ": opening differs from authored mission in " + key)
			return
	scene.call("_commit")
	var advanced: Dictionary = scene.battle_snapshot()
	if advanced.get("round") == opening.get("round") or advanced == opening:
		_fail(id + ": committing did not advance the opening round")
		return
	scene.call("_restart_fixed")
	if scene.battle_snapshot() != opening:
		_fail(id + ": restart did not restore the clean opening")
		return
	var music := scene.find_child("MusicPlayer", true, false) as AudioStreamPlayer
	if music != null:
		music.stop()
		music.stream = null
	scene.queue_free()
	await process_frame
	await process_frame
	print("PASS: %s standalone authored opening, round and restart" % id)
	quit(0)


func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	quit(1)
