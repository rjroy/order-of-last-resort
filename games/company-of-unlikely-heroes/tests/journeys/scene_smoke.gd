extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/journeys/scene_smoke.gd
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	if packed == null:
		printerr("FAIL: missing playable main scene")
		quit(1)
		return
	var scene := packed.instantiate()
	scene.configure_launch(PackedStringArray(["--mission=shield_wall"]))
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_check(scene.current_screen() == "battle", "Stock mission enters battle")
	_check(scene.battle_snapshot().get("mission_id") == "shield_wall", "Requested stock mission is loaded")
	var page: Control = scene.get("_storybook_page")
	var board := scene.find_child("BridgeBoard", true, false) as Control
	_check(page != null and page.is_visible_in_tree() and board != null and board.is_visible_in_tree(),
		"Player page mounts the live board")
	_check(scene.find_child("Commit", true, false) is BaseButton, "Player page offers Commit")
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: stock scene smoke")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
