extends SceneTree
## Run graphically: godot --path games/company-of-unlikely-heroes --script res://tests/battle/fallen_hero_transient_test.gd

const Board = preload("res://presentation/battle/bridge_art.gd")
const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const Statuses = preload("res://rules/statuses.gd")
const CELL := Vector2i(1, 1)

var failures := 0
var board := Board.new()
var viewport := SubViewport.new()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Fallen hero transient test requires a graphical renderer.")
		board.free()
		viewport.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE + Board.GUTTER * 2.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var container := SubViewportContainer.new()
	container.add_child(viewport)
	root.add_child(container)

	var defs := Catalog.read_default()
	defs.classes.knight.abilities.append("knight_rescue_line")
	defs = load("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(defs)
	var rules := Rules.new()
	var before: Dictionary = rules.new_game(defs, "test_escort")
	before.width = 12
	before.height = 12
	before.default_tile = "stone"
	before.terrain = []
	before.obstacles = []
	before.units = [
		{"id": "knight", "character_id": "knight", "position": CELL, "hp": 7, "max_hp": 7, "statuses": {}},
		{"id": "wizard", "character_id": "wizard", "position": Vector2i(2, 1), "hp": 7, "max_hp": 7, "statuses": {}},
		{"id": "patient", "character_id": "healer", "position": Vector2i(1, 3), "hp": 7, "max_hp": 7, "statuses": {}},
	]
	before.orders = {}
	before.overrides = {}
	var first: Dictionary = rules.preview(before, "wizard", "wizard_blast")
	if not first.get("valid", false):
		_check(false, "First real Blast is legal")
		_finish(container)
		return
	var wounded: Dictionary = rules.apply_plan(before, first)
	_check(_unit(wounded, "knight").hp == 3 and Statuses.knocked_down(wounded, _unit(wounded, "knight")),
		"First Blast takes the Knight from 7 to 3 and knocks them down")
	var second: Dictionary = rules.preview(wounded, "wizard", "wizard_blast")
	if not second.get("valid", false):
		_check(false, "Second real Blast is legal")
		_finish(container)
		return
	var fallen: Dictionary = rules.apply_plan(wounded, second)
	_check(_unit(fallen, "knight").hp == 0, "Second Blast takes the Knight from 3 to zero")
	var cues: Array = Cues.build(before, fallen, first.events + second.events)
	_check(not cues.any(func(cue): return cue.get("unit_id") == "knight" \
		and not cue.has("hero_knockdown") and not cue.get("hero_defeat", false)),
		"The fallen Knight has no committed action in this batch")
	var defeats := cues.filter(func(cue): return cue.get("unit_id") == "knight" \
		and cue.get("hero_defeat", false) and cue.get("clip") == "defeat")
	_check(defeats.size() == 1 and defeats[0].get("was_prone", false),
		"A real lethal hit on an already down Knight queues one prone defeat")
	var downs := cues.filter(func(cue): return cue.get("unit_id") == "knight" \
		and cue.get("hero_knockdown") == "down")
	_check(downs.size() == 1, "Real committed Blast batch includes the Knight's living down reaction")
	if downs.size() == 1:
		var empty := await _image([], [])
		var phantom := await _image([], [downs[0]])
		_check(_difference(empty, phantom) == 0,
			"Absent fallen Knight does not appear as a living down reaction")
		var living := {"id": "knight", "cast_key": "knight", "art_key": "knight",
			"cell": CELL, "hp": 3, "max_hp": 7, "prone": true}
		var live_down := await _image([living], [downs[0]])
		_check(_difference(empty, live_down) > 30, "The same reaction remains visible on a living Knight")

	var rescue: Dictionary = rules.preview(before, "knight", "knight_rescue_line", "patient")
	if not rescue.get("valid", false):
		_check(false, "Knight's real Rescue Line action is legal")
	else:
		var acted: Dictionary = rules.apply_plan(before, rescue)
		var hit: Dictionary = rules.preview(acted, "wizard", "wizard_blast")
		var after_hit: Dictionary = rules.apply_plan(acted, hit)
		var lethal: Dictionary = rules.preview(after_hit, "wizard", "wizard_blast")
		var final: Dictionary = rules.apply_plan(after_hit, lethal)
		var performed: Array = Cues.build(before, final, rescue.events + hit.events + lethal.events)
		var actions := performed.filter(func(cue): return cue.get("unit_id") == "knight" \
			and cue.get("clip") == "rescue_line")
		_check(_unit(final, "knight").hp == 0 and actions.size() == 1,
			"Real Rescue Line precedes the two fatal Blasts")
		var death := performed.filter(func(cue): return cue.get("unit_id") == "knight" \
			and cue.get("hero_defeat", false))
		_check(actions.size() == 1 and death.size() == 1 and performed.find(actions[0]) < performed.find(death[0]),
			"Fallen Knight's actual action remains ahead of exactly one defeat")
		if actions.size() == 1:
			var empty := await _image([], [])
			var acting := await _image([], [actions[0]])
			_check(_difference(empty, acting) > 30,
				"Absent fallen Knight still renders their actual committed action")
	_finish(container)


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _image(units: Array, cues: Array) -> Image:
	board.clear_action_playback()
	board.set_render_state({CELL: "bridge"}, units)
	board.play_committed_actions(cues)
	board.set_process(false)
	board._process(0.1)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func _finish(container: Control) -> void:
	container.queue_free()
	if failures == 0:
		print("PASS: fallen hero transient playback")
	quit(1 if failures else 0)
