extends SceneTree
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/harpooner_projectile_tip_test.gd
##
## Uses the committed stock ability's real cue and the board's projected
## geometry. The atlas registration is the root of the shaft, not its tip.

const Board = preload("res://presentation/battle/bridge_art.gd")
const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const SHAFT_TIP := Vector2(160.0, 11.5)
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_finish("A graphical renderer is required.")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var board := Board.new()
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	root.add_child(viewport)
	await process_frame
	for facing in [1, -1]:
		await _case(board, facing)
	viewport.queue_free()
	_finish("")


func _case(board: Node, facing: int) -> void:
	var rules := Rules.new()
	var state: Dictionary = Rules.open_mission(Catalog.read_default(), "company_rescue",
		["knight", "healer", "wizard"])
	var source := Vector2i(2, 2) if facing == 1 else Vector2i(4, 2)
	var target := Vector2i(4, 2) if facing == 1 else Vector2i(2, 2)
	for unit: Dictionary in state.units:
		if unit.id == "harpooner":
			unit.position = source
		elif unit.id == "knight":
			unit.position = target
		else:
			unit.position = Vector2i(0, 0)
	for obstacle: Dictionary in state.obstacles:
		obstacle.position = Vector2i(6, 4)
	var plan: Dictionary = rules.preview(state, "harpooner", "enemy_harpoon", "knight")
	if not plan.get("valid", false):
		_check(false, "Facing %d: stock ranged attack resolves" % facing)
		return
	var cues: Array = Cues.build(state, plan.result, plan.events)
	var cue := {}
	for candidate: Dictionary in cues:
		if candidate.get("unit_id") == "harpooner" and candidate.get("clip") == "ranged_cast":
			cue = candidate
	if cue.is_empty():
		_check(false, "Facing %d: real ranged cue exists" % facing)
		return
	var cells := {}
	for x in range(7):
		for y in range(5):
			cells[Vector2i(x, y)] = "stone"
	board.call("clear_action_playback")
	board.call("set_render_state", cells, [
		{"id": "harpooner", "cell": source, "art_key": "enemy", "cast_key": "harpooner", "hp": 6},
		{"id": "knight", "cell": target, "art_key": "knight", "cast_key": "knight", "hp": 8}])
	board.call("play_committed_actions", [cue])
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.is_empty() or active[0].gift == null:
		_check(false, "Facing %d: detached projectile exists" % facing)
		return
	var entry = active[0]
	board.call("_process", entry.clip.release_ms / 1000.0 + 0.001)
	board.set_process(false)
	var hand: Vector2 = board.call("_unit_foot", source) \
		+ entry.clip.release_offset * Vector2(float(facing), 1.0) * entry.clip.scale
	_check(entry.gift_from is Vector2 and entry.gift_from.distance_to(hand) < 0.01,
		"Facing %d: detached shaft root begins at the registered hand" % facing)
	if not entry.gift_from is Vector2 or not entry.gift_to is Vector2:
		_check(false, "Facing %d: projectile endpoints are available" % facing)
		return
	var landing: Vector2 = board.call("_unit_foot", target) + Vector2(0, -29)
	_check(entry.gift.tip is Vector2 and entry.gift.tip.distance_to(SHAFT_TIP) < 0.01,
		"Facing %d: projectile metadata records the actual shaft tip" % facing)
	var tip_offset: Vector2 = (SHAFT_TIP - entry.gift.anchor) * entry.gift.scale
	tip_offset = (tip_offset * Vector2(float(facing), 1.0)).rotated(entry.gift_angle)
	var tip_at_impact: Vector2 = entry.gift_to + tip_offset
	_check(tip_at_impact.distance_to(landing) < 3.0,
		"Facing %d: shaft TIP, not its root, reaches the target at impact (error %.2f px)" \
			% [facing, tip_at_impact.distance_to(landing)])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(error: String) -> void:
	if not error.is_empty():
		failures.append(error)
	if failures.is_empty():
		print("PASS: Harpooner projectile hand and tip geometry")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
