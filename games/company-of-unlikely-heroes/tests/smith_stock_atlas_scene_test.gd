extends SceneTree
## Graphical stock-battle regression. Set SMITH_STOCK_CAPTURE to a new absolute
## PNG path in an isolated sandbox. No fixture state is injected.

const Driver = preload("res://tests/support/storybook_driver.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := OS.get_environment("SMITH_STOCK_CAPTURE")
	var ready_output := output.get_basename() + "-ready.png"
	if DisplayServer.get_name() == "headless" or not output.is_absolute_path() \
			or FileAccess.file_exists(output) or FileAccess.file_exists(ready_output) \
			or not DirAccess.dir_exists_absolute(output.get_base_dir()):
		push_error("Requires a graphical display and a new absolute SMITH_STOCK_CAPTURE PNG path")
		quit(1)
		return
	root.size = Vector2i(1280, 820)
	var scene: Node = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray([
		"--mission=bridge_patrol", "--party=blacksmith,healer,knight"
	]))
	root.add_child(scene)
	await process_frame
	await process_frame
	var board: Control = scene.find_child("BridgeBoard", true, false)
	_check(scene.current_screen() == "battle" and board != null and board.is_visible_in_tree(),
		"stock mission opens its visible battle board")
	if board == null:
		_finish()
		return
	var unit: Dictionary = board.get("_units_by_id").get("blacksmith", {})
	_check(unit.get("cast_key") == "blacksmith", "stock board binds Smith cast identity")
	var cast = board.get("_cast")
	var ready = cast.clip_for("blacksmith", "ready")
	_check(ready != null, "Smith has a ready clip")
	if ready != null:
		_check(ready.path == "res://assets/cast/blacksmith.png", "ready uses the accepted Smith atlas")
		_check(Sprites.load_texture(ready.path) != null, "ready atlas is loadable")
		for rect: Rect2 in ready.frames:
			var texture = Sprites.load_texture(ready.path)
			_check(texture != null and Rect2(Vector2.ZERO, texture.get_size()).encloses(rect),
				"ready frame lies within the atlas")
	await RenderingServer.frame_post_draw
	var ready_image := root.get_texture().get_image()
	_check(ready_image != null and ready_image.save_png(ready_output) == OK,
		"actual game viewport ready comparator captured")
	var driver := Driver.new(self, scene)
	_check(await driver.command("blacksmith", "blacksmith_try_this", "healer"),
		"stock Try This can be staged through battle controls: " + driver.error)
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit == null or commit.disabled or not commit.is_visible_in_tree():
		_check(false, "stock Commit control is available")
	else:
		await driver._click(commit.get_global_rect().get_center())
		await process_frame
		_check(scene.battle_snapshot() != before, "stock command commits the round")
		var deadline := Time.get_ticks_msec() + 6000
		var found := false
		while Time.get_ticks_msec() < deadline:
			for entry in board.get("_playback").active():
				if entry.cue.get("unit_id") != "blacksmith" or entry.cue.get("clip") != "try_this":
					continue
				var clip = entry.clip
				if clip == null or clip.path != "res://assets/cast/blacksmith.png":
					continue
				var index: int = clip.frame_index(entry.elapsed_ms + entry.sample_offset_ms)
				var source_frame: int = clip.source_frames[index]
				if source_frame < 13 or source_frame > 18:
					continue
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				_check(image != null and image.save_png(output) == OK,
					"actual game viewport action captured")
				if image != null and ready_image != null:
					var foot: Vector2 = board.get_global_transform_with_canvas() * board.call("_unit_foot", unit.cell)
					_check(_changed_near(ready_image, image, foot) > 40,
						"Smith's visible board region changes from ready at the sampled action frame")
				print("Captured Smith try_this source frame ", source_frame, " elapsed_ms=", entry.elapsed_ms)
				found = true
				break
			if found:
				break
			await process_frame
		_check(found, "real playback reached Smith Try This frame F13–F18 on its own clock")
	scene.queue_free()
	await process_frame
	_finish()


func _changed_near(before: Image, after: Image, foot: Vector2) -> int:
	var changed := 0
	var bounds := Rect2i(int(foot.x) - 70, int(foot.y) - 150, 140, 165) \
		.intersection(Rect2i(0, 0, mini(before.get_width(), after.get_width()),
			mini(before.get_height(), after.get_height())))
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if before.get_pixel(x, y) != after.get_pixel(x, y):
				changed += 1
	return changed


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("FAIL: " + message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: stock Smith battle atlas and command")
	quit(0 if failures.is_empty() else 1)
