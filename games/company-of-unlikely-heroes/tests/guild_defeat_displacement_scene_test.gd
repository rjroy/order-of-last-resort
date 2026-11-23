extends SceneTree
## godot --path games/company-of-unlikely-heroes --script res://tests/guild_defeat_displacement_scene_test.gd

const Rules = preload("res://rules.gd")
const CAST_CELL := Vector2i(7, 3)
const DEATH_CELL := Vector2i(4, 3)

var rules := Rules.new()
var scene: Node
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Guild defeat displacement requires a graphical renderer.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 820)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	await _case("bard", "order_healing_sonnet", "healing_sonnet")
	await _case("alchemist", "order_throw_samples", "acid")
	if failures == 0:
		print("PASS: displaced guild heroes act at their cast cell and fall at their death cell")
	quit(1 if failures else 0)


func _case(hero: String, order: String, clip: String) -> void:
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.round = 1
	state.outcome = "ongoing"
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	state.units = [_unit("victim", hero, CAST_CELL, 1),
		_unit("wizard", "wizard", DEATH_CELL, 20),
		_unit("harpooner", "harpooner", Vector2i(5, 2), 20)]
	state.party = ["victim", "wizard"]
	state.orders = {}
	state.overrides = {}
	state = rules.set_order(state, "victim", order)
	scene.call("_show_battle", state)
	scene.set("_planned_state", rules.choose_manual(state, "wizard", "wizard_pull", "victim"))
	scene.call("_refresh")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if not _check(commit != null and not commit.disabled, hero + ": round can commit"):
		return
	commit.pressed.emit()
	var board: Control = scene.get("_board")
	board.set_process(false)
	var committed: Dictionary = scene.battle_snapshot()
	var victim: Dictionary = committed.units[0]
	_check(committed.outcome == "ongoing" and victim.hp == 0 and victim.position == DEATH_CELL,
		hero + ": the committed round leaves the hero dead at the Pull destination")
	var events: Array = scene.get("_last_events")
	var pull := events.find_custom(func(event): return event.type == "pull" and event.target_id == "victim" \
		and event.unit_id == "wizard" and event.position == DEATH_CELL)
	var lethal := events.find_custom(func(event): return event.type == "damage" and event.target_id == "victim" \
		and event.source_id == "harpooner" and event.amount > 0)
	_check(pull >= 0 and lethal > pull, hero + ": allied Pull actually precedes the Harpooner's lethal hit")
	var playback = board.get("_playback")
	var entries: Array = playback.get("_entries").filter(func(entry): return entry.cue.unit_id == "victim")
	if not _check(entries.size() == 2 and entries[0].cue.clip == clip \
			and entries[0].cue.actor_cell == CAST_CELL and entries[1].cue.get("hero_defeat", false) \
			and entries[1].cue.actor_cell == DEATH_CELL,
			hero + ": the real commit records one own gesture at (7,3) and one defeat at (4,3)"):
		return
	var action = entries[0]
	var defeat = entries[1]
	_advance(board, action.clip.time_at_source_frame(10) + 1.0 - action.elapsed_ms)
	await _check_figure_locations(board, CAST_CELL, DEATH_CELL, hero + " own gesture")

	if hero == "alchemist":
		_advance(board, action.clip.release_ms + 1.0 - action.elapsed_ms)
		var expected: Vector2 = board.call("_unit_foot", CAST_CELL) \
			+ action.clip.release_offset * Vector2(action.facing, 1.0) * action.clip.scale
		_check(action.gift_from is Vector2 and action.gift_from.is_equal_approx(expected),
			"alchemist: first released Acid starts at the hand on (7,3), not the corpse tile")
		await _check_figure_locations(board, CAST_CELL, DEATH_CELL, "alchemist Acid release")

	_advance(board, 1.0 - defeat.elapsed_ms)
	await _check_figure_locations(board, DEATH_CELL, CAST_CELL, hero + " defeat entry")
	_advance(board, board.action_playback_remaining_ms() + 1.0)
	_check(board.action_playback_snapshot().is_empty(), hero + ": visual timeline finishes")
	await _check_figure_locations(board, DEATH_CELL, CAST_CELL, hero + " defeat hold")


func _advance(board: Control, ms: float) -> void:
	board._process(ms / 1000.0)
	board.set_process(false)


func _check_figure_locations(board: Control, occupied: Vector2i, empty: Vector2i, label: String) -> void:
	var figures := board.get("_figures") as CanvasItem
	var drawn := await _capture()
	figures.hide()
	var bare := await _capture()
	figures.show()
	_check(_figure_pixels(board, drawn, bare, occupied) > 20, "%s is visible at %s" % [label, occupied])
	_check(_figure_pixels(board, drawn, bare, empty) == 0, "%s has no second figure at %s" % [label, empty])


func _figure_pixels(board: Control, drawn: Image, bare: Image, cell: Vector2i) -> int:
	var origin: Vector2 = board.get("_map_origin")
	var scale: float = board.get("_map_scale")
	var foot: Vector2 = board.call("_unit_foot", cell)
	var to_pixels := root.get_stretch_transform() * board.get_global_transform_with_canvas()
	# Only the lower center of the figure; nearby Harpoon and Pull marks are outside it.
	var patch := Rect2i(to_pixels * Rect2(origin + (foot + Vector2(-18, -24)) * scale,
		Vector2(36, 30) * scale))
	var changed := 0
	for y in range(patch.position.y, patch.end.y):
		for x in range(patch.position.x, patch.end.x):
			if drawn.get_pixel(x, y) != bare.get_pixel(x, y):
				changed += 1
	return changed


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _unit(id: String, character: String, cell: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "character_id": character, "position": cell,
		"hp": hp, "max_hp": 20, "statuses": {}, "dose_rng_state": 1}


func _check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	return ok
