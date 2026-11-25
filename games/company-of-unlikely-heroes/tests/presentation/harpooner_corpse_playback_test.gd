extends SceneTree
## Graphical regression:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/harpooner_corpse_playback_test.gd
##
## A controlled board state produces a real reflected Harpooner attack through
## the rules. A living Necromancer makes the defeated enemy a corpse marker.
## The final board must not hide the preceding action under that corpse.

const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const SIZE := Vector2i(1280, 820)

var failures: Array[String] = []
var viewport: SubViewport
var scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_finish("A graphical renderer is required.")
		return
	var rules := Rules.new()
	var state: Dictionary = Rules.open_mission(Catalog.read_default(), "company_rescue",
		["knight", "necromancer", "healer"])
	_unit(state, "knight").position = Vector2i(3, 2)
	_unit(state, "necromancer").position = Vector2i(1, 1)
	_unit(state, "healer").position = Vector2i(0, 1)
	_unit(state, "harpooner").position = Vector2i(5, 2)
	_unit(state, "harpooner").hp = 1
	for obstacle: Dictionary in state.obstacles:
		obstacle.position = Vector2i(6, 4)
	var guarded: Dictionary = rules.preview(state, "knight", "knight_aura")
	if not guarded.get("valid", false):
		_finish("Controlled guard action did not resolve.")
		return
	var before: Dictionary = guarded.result
	var attack: Dictionary = rules.preview(before, "harpooner", "enemy_harpoon", "knight")
	if not attack.get("valid", false):
		_finish("Controlled stock harpoon attack did not resolve.")
		return
	_check(attack.events.any(func(event): return event.get("type") == "reflect"),
		"Knight's guard actually reflects the stock attack")
	_check(_unit(attack.result, "harpooner").hp == 0, "Reflection actually defeats Harpooner")
	var cues: Array = Cues.build(before, attack.result, attack.events)
	_check(cues.any(func(cue): return cue.get("unit_id") == "harpooner" \
		and cue.get("clip") == "ranged_cast"), "Real event creates the ranged cast")
	_check(cues.any(func(cue): return cue.get("unit_id") == "harpooner" \
		and cue.get("clip") == "defeat"), "Real reflected damage creates defeat")

	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--storybook", "--mission=goblin_mob"]))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	scene.set("_opening_state", before.duplicate(true))
	scene.call("_show_battle", attack.result)
	await process_frame
	var board := scene.find_child("BridgeBoard", true, false)
	if board == null:
		_finish("Main battle board did not open.")
		return
	var corpse: Dictionary = board.get("_units_by_id").get("harpooner", {})
	_check(corpse.get("label") == "Corpse" and corpse.get("hp") == 0,
		"Main battle renderer retains Harpooner as a corpse row")
	board.call("play_committed_actions", cues)
	board.set_process(false)
	var playback = board.get("_playback")
	var entries: Array = playback.get("_entries")
	var cast = null
	var defeat = null
	for entry in entries:
		if entry.cue.get("unit_id") == "harpooner":
			if entry.cue.get("clip") == "ranged_cast":
				cast = entry
			elif entry.cue.get("clip") == "defeat":
				defeat = entry
	if cast == null or defeat == null:
		_finish("Both real cues must enter board playback.")
		return
	_check(defeat.elapsed_ms < 0.0, "Defeat is queued after the attack, not already active")
	var sample_ms: float = cast.clip.time_at_source_frame(8)
	board.call("_process", maxf(0.0, sample_ms - cast.elapsed_ms) / 1000.0 + 0.001)
	board.set_process(false)
	var actual := await _figure(board, corpse.cell)
	# Compare exactly the same queued action with only the renderer's final
	# corpse state changed to living. Mask health and labels below the figure.
	var units: Array = board.get("_units").duplicate(true)
	var living := units.duplicate(true)
	for unit: Dictionary in living:
		if unit.get("id") == "harpooner":
			unit.hp = 1
			unit.prone = false
	board.call("set_render_state", board.get("_cells"), living, board.get("_overlay"))
	board.set_process(false)
	var expected := await _figure(board, corpse.cell)
	_check(_difference(actual, expected) < 10,
		"Queued ranged gesture renders over the final corpse, not a fallen pose")
	board.call("set_render_state", board.get("_cells"), units, board.get("_overlay"))
	board.set_process(false)
	# If the attack's impact feedback extends beyond its last animation frame,
	# inspect that gap too. The future corpse must not flash up before defeat.
	var to_defeat: float = -defeat.elapsed_ms
	if to_defeat > 10.0 and cast.elapsed_ms + to_defeat - 2.0 >= cast.clip.total_ms:
		board.call("_process", (to_defeat - 2.0) / 1000.0)
		board.set_process(false)
		var gap_actual := await _figure(board, corpse.cell)
		board.call("set_render_state", board.get("_cells"), living, board.get("_overlay"))
		board.set_process(false)
		var gap_living := await _figure(board, corpse.cell)
		_check(_difference(gap_actual, gap_living) < 10,
			"No premature corpse pose appears between attack and defeat")
		board.call("set_render_state", board.get("_cells"), units, board.get("_overlay"))
		board.set_process(false)
	board.call("_process", maxf(0.0, -defeat.elapsed_ms) / 1000.0 + 0.001)
	board.set_process(false)
	_check(defeat.elapsed_ms >= 0.0, "Defeat begins after the attack")
	board.call("_process", 30.0)
	board.set_process(false)
	_check((board.call("action_playback_snapshot") as Array).is_empty(), "The sequence finishes")
	var settled: Dictionary = board.get("_units_by_id").get("harpooner", {})
	_check(settled.get("label") == "Corpse" and settled.get("hp") == 0,
		"Completed playback settles on the actual corpse row")
	_finish("")


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.units:
		if unit.id == id:
			return unit
	return {}


func _figure(board: Node, cell: Vector2i) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var foot: Vector2 = board.get("_map_origin") \
		+ (board.call("_tile_origin", cell) + board.FOOT) * board.get("_map_scale")
	var global_foot: Vector2 = board.get_global_transform_with_canvas() * foot
	var rect := Rect2i(int(global_foot.x - 80), int(global_foot.y - 150), 160, 120)
	return image.get_region(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())))


func _difference(first: Image, second: Image) -> int:
	var changed := 0
	for y in first.get_height():
		for x in first.get_width():
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(error: String) -> void:
	if not error.is_empty():
		failures.append(error)
	if failures.is_empty():
		print("PASS: Harpooner committed action precedes corpse defeat")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
