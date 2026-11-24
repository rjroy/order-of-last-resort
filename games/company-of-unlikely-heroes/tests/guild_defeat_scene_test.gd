extends SceneTree
## Graphical integration regression:
## godot --path games/company-of-unlikely-heroes --script res://tests/guild_defeat_scene_test.gd
## Uses committed production mission rounds, not a fabricated death event.

const Rules = preload("res://rules.gd")
const BoardRules = preload("res://rules/board.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Bridge = preload("res://bridge_art.gd")
const HEROES := ["knight", "healer", "wizard", "bard", "rogue", "necromancer", "alchemist"]
const CELL := Vector2i(3, 3)
const SCENE_SIZE := Vector2i(1280, 820)

class ProbeBoard extends Bridge:
	var force_fallen_foreground := false

	func _draw_figures() -> void:
		if not force_fallen_foreground:
			super._draw_figures()
			return
		# Negative control: deliberately paint the very same two rows in the
		# wrong order, without markers or effects. Production draws via super.
		_ink_canvas = _figures
		for unit in _units:
			_draw_unit_shadow(unit)
		for unit in _units:
			_draw_unit(unit, null)
		_ink_canvas = self

var rules := Rules.new()
var scene: Node
var scene_view := SubViewport.new()
var probe := ProbeBoard.new()
var probe_view := SubViewport.new()
var failures: Array[String] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Guild defeat scene test requires a graphical renderer.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	scene_view.size = SCENE_SIZE
	scene_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(scene_view)
	probe_view.size = Vector2i(Bridge.TILE + Bridge.GUTTER * 2.0)
	probe_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	probe.size = Vector2(probe_view.size)
	probe_view.add_child(probe)
	var probe_container := SubViewportContainer.new()
	probe_container.position = Vector2(-500, -500)
	probe_container.add_child(probe_view)
	root.add_child(probe_container)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	scene_view.add_child(scene)
	await process_frame
	await process_frame
	if scene.current_screen() != "battle":
		_check(false, "Stock mission launches")
	else:
		for hero in HEROES:
			await _case(hero, false)
		await _case("knight", true)
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: committed guild defeat presentations")
	quit(0 if failures.is_empty() else 1)


func _case(hero: String, shield_away: bool) -> void:
	var label := hero + (" shield away" if shield_away else "")
	var state: Dictionary = scene.battle_snapshot().duplicate(true)
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.objective = {"handler": "survive", "turns": 99, "reserves": []}
	state.outcome = "ongoing"
	state.units = [
		_unit("fallen", hero, CELL, 1),
		_unit("caster", "wizard", Vector2i(2, 3), 20),
		_unit("observer", "necromancer", Vector2i(3, 4), 20),
		_unit("medic", "healer", Vector2i(1, 4), 20),
		_unit("enemy", "harpooner", Vector2i(10, 10), 20),
	]
	state.party = ["fallen", "caster", "observer", "medic"]
	state.orders = {}
	state.overrides = {}
	if shield_away:
		_entity(state, "fallen")["shield_position"] = Vector2i(8, 8)
	for id in state.party:
		state = rules.set_order(state, id, "order_hold")
	scene.call("_show_battle", state)
	scene.set("_planned_state", rules.choose_manual(state, "caster", "wizard_blast"))
	scene.call("_refresh")
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	if not plan.get("valid", false) or _entity(plan.get("result", {}), "fallen").get("hp", 1) != 0:
		_check(false, label + ": real round forecasts lethal Blast")
		return
	var expected: Array = Cues.build(state, plan.result, plan.events).filter(func(cue): return \
		cue.get("unit_id") == "fallen" and cue.get("cast_key") == hero and cue.get("clip") == "defeat")
	_check(expected.size() == 1, label + ": lethal committed hit creates exactly one own defeat cue")
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit == null or commit.disabled:
		_check(false, label + ": lethal round can commit")
		return
	commit.pressed.emit()
	var after: Dictionary = scene.battle_snapshot()
	_check(after.get("outcome") == "ongoing" and _entity(after, "fallen").get("hp") == 0 \
		and _entity(after, "caster").get("hp", 0) > 0,
		label + ": death commits while another party member survives")
	_check(BoardRules.is_vacant(after, CELL) and not rules.corpse_markers(after).has(CELL) \
		and not rules.targets(after, "observer", "raise_dead").any(
			func(target): return target.get("id") == "fallen"),
		label + ": visual defeat neither occupies nor creates a raisable corpse")
	var pull_targets: Array = rules.targets(after, "caster", "wizard_pull")
	_check(pull_targets.any(func(target): return target.get("id") == "observer") \
		and not pull_targets.any(func(target): return target.get("id") == "fallen"),
		label + ": Pull can target a living ally but not the fallen hero")
	var board = scene.get("_board")
	board.set_process(false)
	var snapshot: Array = board.action_playback_snapshot()
	_check(snapshot.any(func(cue): return cue.get("unit_id") == "fallen" \
		and cue.get("cast_key") == hero and cue.get("clip") == "defeat"),
		label + ": scene queues the committed defeat")
	var art = board.get("_cast")
	var defeat_name := "defeat_unshielded" if shield_away else "defeat"
	_check(art.clip_for(hero, defeat_name) != null, label + ": equipment-appropriate defeat clip is packaged")
	var terminal_frame: Image
	for tick in 200:
		var own: Array = board.get("_playback").active().filter(func(entry): return \
			entry.cue.get("unit_id") == "fallen" and entry.cue.get("clip") == "defeat")
		if own.size() == 1:
			board._process(maxf(0.0, own[0].clip.total_ms - own[0].elapsed_ms - 1.0) / 1000.0)
			board.set_process(false)
			var at_end: Array = board.get("_playback").active().filter(func(entry): return \
				entry.cue.get("unit_id") == "fallen" and entry.cue.get("clip") == "defeat" \
				and entry.clip.frame_index(entry.elapsed_ms) == entry.clip.frames.size() - 1)
			if at_end.size() == 1:
				terminal_frame = await _capture()
			break
		if board.action_playback_snapshot().is_empty():
			break
		board._process(0.025)
		board.set_process(false)
	_check(terminal_frame != null, label + ": sampled the active defeat clip's final frame")
	if hero == "rogue":
		# Exercise the original failure between the two scene captures.
		root.size = Vector2i(960, 640) if root.size != Vector2i(960, 640) else SCENE_SIZE
	board._process((board.action_playback_remaining_ms() + 1.0) / 1000.0)
	board.set_process(false)
	var held := await _capture()
	if terminal_frame != null:
		_check(terminal_frame.get_size() == SCENE_SIZE and held.get_size() == SCENE_SIZE \
			and terminal_frame.get_data() == held.get_data(), label + ": final defeat frame holds after playback")
	var rows: Array = board.get("_units")
	var fallen_rows := rows.filter(func(row): return row.get("id") == "fallen")
	_check(fallen_rows.size() == 1 and fallen_rows[0].get("hp", 1) == 0,
		label + ": one visual-only fallen figure persists after playback")
	if fallen_rows.size() == 1:
		var living_down: Dictionary = fallen_rows[0].duplicate(true)
		living_down.hp = 1
		living_down.prone = true
		# A live row must not retain the scene's visual-only defeat flag.
		# Hide identifiers on both sides so only the actor drawings differ.
		living_down.erase("visual_defeat")
		living_down["transient"] = true
		var defeat_row: Dictionary = fallen_rows[0].duplicate(true)
		defeat_row["transient"] = true
		probe.clear_action_playback()
		probe.set_render_state({CELL: "stone"}, [defeat_row])
		probe.set_process(false)
		var full_scale_defeat := await _probe_capture()
		probe.set_render_state({CELL: "stone"}, [living_down])
		probe.set_process(false)
		var down_image := await _probe_capture()
		_check(_difference(full_scale_defeat, down_image) > 30,
			label + ": defeat hold differs from living knockdown at native tile scale")
		probe.set_render_state({CELL: "stone"}, [defeat_row])
		probe.play_committed_actions(expected)
		probe.set_process(false)
		var active: Array = probe.get("_playback").active()
		if active.size() == 1:
			probe._process((active[0].clip.total_ms - 1.0) / 1000.0)
			probe.set_process(false)
			var last := await _probe_capture()
			_check(_difference(last, full_scale_defeat) == 0,
				label + ": native-scale scene-projected hold matches the final committed defeat frame")
		else:
			_check(false, label + ": native-scale defeat cue plays")
	var move: Dictionary = rules.preview(after, "caster", "move", "3,3")
	_check(move.get("valid", false) and _entity(move.get("result", {}), "caster").get("position") == CELL,
		label + ": living hero can move onto the fallen hero's tile")
	scene.set("_planned_state", rules.choose_manual(after, "caster", "move", "3,3"))
	scene.call("_refresh")
	commit = scene.find_child("Commit", true, false) as BaseButton
	if commit != null and not commit.disabled:
		commit.pressed.emit()
		board.set_process(false)
		var moved: Dictionary = scene.battle_snapshot()
		_check(_entity(moved, "caster").get("position") == CELL,
			label + ": living movement onto the tile commits")
		if not fallen_rows.is_empty():
			await _check_underlap(board, label)
	else:
		_check(false, label + ": living movement round is available")


func _check_underlap(board: Control, label: String) -> void:
	# Compare the production projection against the same board with only the
	# later living occupant. Visible occupant pixels must not be painted over.
	var rows: Array = board.get("_units").duplicate(true)
	var living_rows := rows.filter(func(row): return row.get("id") == "caster")
	var fallen_rows := rows.filter(func(row): return row.get("id") == "fallen")
	if living_rows.size() != 1 or fallen_rows.size() != 1:
		_check(false, label + ": both figures remain after the actual move")
		return
	var living: Dictionary = living_rows[0]
	var fallen: Dictionary = fallen_rows[0]
	_check(living.get("cell") == CELL and fallen.get("cell") == CELL \
		and fallen.get("visual_defeat", false) and int(living.get("hp", 0)) > 0,
		label + ": scene projects both actual occupants at the same tile")
	living["transient"] = true
	fallen["transient"] = true
	probe.clear_action_playback()
	probe.set_render_state({CELL: "stone"}, [living])
	probe.set_process(false)
	var living_image := await _probe_capture()
	probe.set_render_state({CELL: "stone"}, [])
	probe.set_process(false)
	var bare := await _probe_capture()
	probe.set_render_state({CELL: "stone"}, [fallen])
	probe.set_process(false)
	var fallen_image := await _probe_capture()
	probe.set_render_state({CELL: "stone"}, [living, fallen])
	probe.set_process(false)
	var combined := await _probe_capture()
	probe.force_fallen_foreground = true
	probe.get("_figures").queue_redraw()
	var inverted := await _probe_capture()
	probe.force_fallen_foreground = false
	_check(_difference(bare, living_image) > 100 and _difference(bare, fallen_image) > 100 \
		and _difference(living_image, combined) > 30,
		label + ": both actual drawings are visible, including uncovered fallen pixels")
	var overlap := 0
	var living_on_top := 0
	var inverted_living_on_top := 0
	for y in living_image.get_height():
		for x in living_image.get_width():
			var base := bare.get_pixel(x, y)
			var live := living_image.get_pixel(x, y)
			var dead := fallen_image.get_pixel(x, y)
			var both := combined.get_pixel(x, y)
			if _color_distance(live, base) > 0.15 and _color_distance(dead, base) > 0.15 \
					and _color_distance(live, dead) > 0.15:
				overlap += 1
				if _color_distance(both, live) < _color_distance(both, dead):
					living_on_top += 1
				if _color_distance(inverted.get_pixel(x, y), live) < _color_distance(inverted.get_pixel(x, y), dead):
					inverted_living_on_top += 1
	# Watercolor sprites have translucent edges, so compare the majority of
	# genuinely shared pixels rather than requiring identical composite pixels.
	_check(overlap > 20 and living_on_top > overlap / 2,
		label + ": fallen figure underlaps the living occupant (%d/%d pixels)" % [living_on_top, overlap])
	_check(overlap > 20 and inverted_living_on_top < overlap / 2,
		label + ": deliberately reversed paint order fails the same overlap control (%d/%d pixels)" \
			% [inverted_living_on_top, overlap])


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return scene_view.get_texture().get_image()


func _probe_capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return probe_view.get_texture().get_image()


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func _color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _unit(id: String, character: String, cell: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "character_id": character, "position": cell,
		"hp": hp, "max_hp": 20, "statuses": {}}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
