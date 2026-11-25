extends SceneTree
## Run with a graphical renderer:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/move_preview_scene_test.gd

const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const CastCues = preload("res://presentation/cast/cast_cues.gd")
var failures: Array[String] = []
var scene: Node


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("A graphical renderer is required.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 820)
	var defs: Dictionary = Catalog.read_default()
	var roster: Array = defs.commission_settings.recruitment_roster
	_check(roster.size() >= 3, "Commission roster has at least three playable heroes")
	# Rotate the whole roster through three deployment slots. Consecutive staging
	# exercises replacement of an earlier hero's command without committing.
	for start in range(0, roster.size(), 3):
		var party: Array[String] = []
		for offset in 3:
			party.append(str(roster[(start + offset) % roster.size()]))
		await _exercise_party(party)
	if failures.is_empty():
		print("PASS: move preview for playable roster")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _exercise_party(party: Array[String]) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=shield_wall", "--party=" + ",".join(party)]))
	root.add_child(scene)
	await process_frame
	await process_frame
	if scene.current_screen() != "battle":
		_check(false, "Party launches: " + str(party))
		return
	var initial: Dictionary = scene.battle_snapshot().duplicate(true)
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var rules := Rules.new()
	var ink := scene.find_child("StorybookInk", true, false) as Control
	var board := scene.find_child("BridgeBoard", true, false) as Control
	if ink == null:
		_check(false, "Storybook ink exists")
		return
	var has_command := false
	for hero in party:
		if has_command:
			_check(await driver.clear(), "Previous hero's command clears without committing: " + driver.error)
			has_command = false
		var targets: Array = rules.targets(initial, hero, "move")
		if targets.is_empty():
			_check(false, hero + " has a legal opening move")
			continue
		if not await driver.command(hero, "move", str(targets[0].id)):
			_check(false, hero + " stages a move: " + driver.error)
			continue
		has_command = true
		var cues: Dictionary = ink.get("_cues")
		var move: Dictionary = cues.get("move", {})
		var actor := {}
		for unit: Dictionary in initial.units:
			if unit.id == hero:
				actor = unit
		var key: String = CastCues.cast_key_for(initial, actor, rules.entity_profile(initial, hero))
		_check(not key.is_empty(), hero + " has an approved cast key")
		_check(move.get("cast_key") == key, hero + " preview uses the selected hero's cast, not its fallback art")
		_check(move.get("from") == actor.get("position") and move.get("to") == targets[0].position,
			hero + " preview follows the staged move")
		_check(scene.battle_snapshot() == initial, hero + " preview leaves the battle uncommitted")
		await _check_stamp(hero, key, board, ink)


func _check_stamp(hero: String, key: String, board: Control, ink: Control) -> void:
	var cast = ink.get("_cast")
	var ready = cast.clip_for(key, "ready")
	_check(ready != null, hero + " has a stationary ready pose")
	var stamp := ink.get("_stamp") as CanvasItem
	_check(stamp != null and stamp.material is ShaderMaterial, hero + " preview has a tint material")
	if stamp == null:
		return
	# Isolate the stamp from other figures while advancing the real board clock
	# deterministically. Redraw it at each time to avoid cached draw commands.
	board.set_process(false)
	var figures := board.get("_figures") as CanvasItem
	figures.visible = false
	board.set("_ready_ms", 0.0)
	stamp.queue_redraw()
	stamp.visible = false
	var without := await _image()
	stamp.visible = true
	var with_stamp := await _image()
	_check(_difference(without, with_stamp) > 30, hero + " paints a visible tinted destination pose")
	var elapsed_ms := 1000.0
	if ready != null and ready.loop and ready.frames.size() > 1:
		elapsed_ms = ready.frame_ends[0] + 1.0
		_check(ready.frame_index(0.0) != ready.frame_index(elapsed_ms),
			hero + " ready animation reaches a different frame")
	board.call("_process", elapsed_ms / 1000.0)
	_check(is_equal_approx(float(board.get("_ready_ms")), elapsed_ms),
		hero + " board ready clock advances")
	stamp.queue_redraw()
	var later := await _image()
	_check(_difference(with_stamp, later) == 0,
		hero + " destination pose remains stationary across board ready times")
	var tint := stamp.material
	stamp.material = null
	var untinted := await _image()
	stamp.material = tint
	_check(_difference(later, untinted) > 30, hero + " destination pose is visibly tinted")
	figures.visible = true


func _image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
