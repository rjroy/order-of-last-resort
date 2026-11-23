extends SceneTree
## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/cast_state_art_test.gd

const Board = preload("res://bridge_art.gd")
const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Statuses = preload("res://rules/statuses.gd")
const CELL := Vector2i.ZERO
const CELLS := {CELL: "bridge"}

var board := Board.new()
var viewport := SubViewport.new()
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Cast state art test requires a graphical renderer.")
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

	await _ko_overrides_live_action()
	await _knockdown_overrides_live_heal()
	await _recovered_shield_overrides_live_throw()
	await _shield_away_rescue_line()
	await _fallen_rescue_equipment()
	await _wizard_pull_finishes_seated()
	_test_acid_release_geometry()
	await _mixologist_knockdown_playback()
	if failures == 0:
		print("Cast state art test passed: KO, shield recovery and Pull seating.")
	quit(1 if failures else 0)


func _ko_overrides_live_action() -> void:
	var alive := _unit("wizard", {"hp": 3, "max_hp": 3})
	await _state(alive)
	_cue("wizard", "blast")
	_advance(0.2)
	_check(not board.action_playback_snapshot().is_empty(), "Blast cue must still be live")
	var knocked_out := _unit("wizard", {"hp": 0, "max_hp": 3})
	var with_cue := await _state(knocked_out)
	board.clear_action_playback()
	board.set_process(false)
	var without_cue := await _capture()
	_check(_difference(with_cue, without_cue) == 0,
		"KO must override a live action, including its standing pose")
	var standing := await _state(alive)
	_check(_difference(without_cue, standing) > 100, "KO must visibly differ from standing")


func _knockdown_overrides_live_heal() -> void:
	board.clear_action_playback()
	await _state(_unit("healer", {"hp": 3, "max_hp": 3}))
	_cue("healer", "ally_heal")
	_advance(0.2)
	var down := _unit("healer", {"prone": true, "hp": 2, "max_hp": 3})
	var with_cue := await _state(down)
	_check(not board.action_playback_snapshot().is_empty(), "Heal cue must still be live")
	board.clear_action_playback()
	board.set_process(false)
	var without_cue := await _capture()
	_check(_difference(with_cue, without_cue) == 0,
		"An unrelated knockdown must override a living Healer's live cast")
	var standing := await _state(_unit("healer", {"hp": 2, "max_hp": 3}))
	_check(_difference(without_cue, standing) > 100, "Knocked-down Healer must remain visibly prone")


func _recovered_shield_overrides_live_throw() -> void:
	board.clear_action_playback()
	var away := _unit("knight", {"shield_away": true})
	await _state(away)
	_cue("knight", "shield_away")
	_advance(0.1)
	var recovered := _unit("knight", {"shield_away": false})
	var with_cue := await _state(recovered)
	_check(not board.action_playback_snapshot().is_empty(), "Shield-away cue must still be live")
	board.clear_action_playback()
	board.set_process(false)
	var without_cue := await _capture()
	_check(_difference(with_cue, without_cue) == 0,
		"Recovered shield must override the still-live shield-away cue")
	var shield_away := await _state(away)
	_check(_difference(without_cue, shield_away) > 100,
		"Recovered and away shield states must be visually distinct")


func _shield_away_rescue_line() -> void:
	board.clear_action_playback()
	var away := _unit("knight", {"shield_away": true})
	var hold := await _state(away)
	var cast = board.get("_cast")
	var gesture = cast.clip_for("knight", "rescue_line_unshielded")
	var rescue = cast.clip_for("knight", "rescue_line")
	if gesture == null or rescue == null:
		_check(false, "Rescue Line has shielded and unshielded gesture clips")
		return
	var sample_ms: float = gesture.time_at_source_frame(14) + 1.0
	_cue("knight", "rescue_line")
	_advance(sample_ms / 1000.0)
	var actual := await _capture()
	_check(_difference(hold, actual) > 30, "Shield-away Rescue Line visibly plays its gesture")

	# The same authored unshielded clip played directly is the reference, so
	# displaying a shielded gesture or the stationary hold cannot satisfy this.
	board.clear_action_playback()
	await _state(_unit("knight", {"shield_away": false}))
	_cue("knight", "rescue_line_unshielded")
	_advance(sample_ms / 1000.0)
	var expected := await _capture()
	_check(_difference(actual, expected) == 0,
		"Shield-away Rescue Line renders the unshielded gesture")

	board.clear_action_playback()
	await _state(away)
	_cue("knight", "rescue_line")
	var active: Array = board.get("_playback").active()
	if active.is_empty():
		_check(false, "Shield-away Rescue Line enters playback")
		return
	_advance((active[0].duration_ms + 1.0) / 1000.0)
	_check(board.action_playback_snapshot().is_empty(), "Shield-away Rescue Line completes")
	var returned := await _capture()
	_check(_difference(hold, returned) == 0,
		"Shield-away Rescue Line returns to the equipment hold")


func _fallen_rescue_equipment() -> void:
	var defs := Catalog.read_default()
	defs.classes.knight.abilities.append("knight_rescue_line")
	defs = load("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(defs)
	var rules := Rules.new()
	var cast = board.get("_cast")
	var away_clip = cast.clip_for("knight", "rescue_line_unshielded")
	var held_clip = cast.clip_for("knight", "rescue_line")
	if away_clip == null or held_clip == null:
		_check(false, "Fallen rescue fixture needs both Rescue Line clips")
		return
	for facing in [-1, 1]:
		for away in [true, false]:
			var source := Vector2i(3, 3)
			var state: Dictionary = rules.new_game(defs, "test_escort")
			state.width = 12
			state.height = 12
			state.default_tile = "stone"
			state.terrain = []
			state.obstacles = []
			var knight := {"id": "knight", "character_id": "knight", "position": source,
				"hp": 1, "max_hp": 8, "statuses": {}}
			if away:
				knight["shield_position"] = Vector2i(8, 8)
			state.units = [knight, {"id": "patient", "character_id": "healer",
				"position": source + Vector2i(2 * facing, 0), "hp": 7, "max_hp": 7, "statuses": {}}]
			state.orders = {}
			state.overrides = {}
			state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
			var plan: Dictionary = rules.preview(state, "knight", "knight_rescue_line", "patient")
			if not plan.get("valid", false):
				_check(false, "Fallen rescue fixture has a valid action")
				continue
			# Model a later fatal event in the committed round. The board removes
			# the dead non-objective hero, but the earlier cue is still playing.
			var after: Dictionary = rules.apply_plan(state, plan)
			_entity(after, "knight").hp = 0
			var cues: Array = Cues.build(state, after, plan.events)
			var rescue := cues.filter(func(cue): return cue.get("unit_id") == "knight" \
				and cue.get("clip") == "rescue_line")
			if rescue.size() != 1:
				_check(false, "Fallen rescue produces its actual action cue")
				continue
			if facing == 1:
				var equipment_event := {"type": "shield_retrieve" if away else "shield_drop",
					"unit_id": "knight", "position": Vector2i(8, 8),
					"resolved_action": {"unit_id": "knight", "ability_id": "move",
						"source_cell": source, "actor_cell": source, "event_count": 1}}
				var changed_cues: Array = Cues.build(state, after, [equipment_event] + plan.events)
				var changed := changed_cues.filter(func(cue): return cue.get("unit_id") == "knight" \
					and cue.get("clip") == "rescue_line")
				_check(changed.size() == 1 and changed[0].get("shield_away") == not away,
					"Rescue snapshots equipment changes before the action")
			var cell := {source: "bridge"}
			board.clear_action_playback()
			board.set_render_state(cell, [])
			board.play_committed_actions(rescue)
			board.set_process(false)
			var sample: float = held_clip.time_at_source_frame(14) + 1.0
			_advance(sample / 1000.0)
			var transient := await _capture()

			board.clear_action_playback()
			board.set_render_state(cell, [{"id": "knight", "art_key": "knight",
				"cast_key": "knight", "cell": source, "facing": facing}])
			var reference: Dictionary = rescue[0].duplicate(true)
			reference.clip = "rescue_line_unshielded" if away else "rescue_line"
			board.play_committed_actions([reference])
			board.set_process(false)
			_advance(sample / 1000.0)
			var expected := await _capture()
			_check(_difference(transient, expected) == 0,
				"Fallen rescue preserves shield %s facing %d" % ["away" if away else "held", facing])


func _wizard_pull_finishes_seated() -> void:
	board.clear_action_playback()
	var down := _unit("wizard", {"prone": true, "hp": 2, "max_hp": 3})
	await _state(down)
	_cue("wizard", "pull")
	var first := await _capture()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cast/manifest.json"))
	var frames: Array = manifest.actors.wizard.clips.pull.frames
	var duration_ms := 0.0
	for frame in frames:
		duration_ms += float(frame.duration_ms)
	_advance((duration_ms - float(frames.back().duration_ms) * 0.5) / 1000.0)
	var last := await _capture()
	_check(_difference(first, last) > 100, "Pull must animate rather than jump straight to seated")
	_advance(1.0)
	_check(board.action_playback_snapshot().is_empty(), "Pull cue must finish")
	var seated := await _capture()
	_check(_difference(last, seated) == 0, "Finished Pull must hold its final seated frame")
	var standing := await _state(_unit("wizard", {"hp": 2, "max_hp": 3}))
	_check(_difference(seated, standing) > 100, "Recovery must clear the seated pose")
	var down_again := await _state(down)
	_check(_difference(seated, down_again) > 100,
		"A later ordinary knockdown must not reuse the earlier Pull pose")


func _test_acid_release_geometry() -> void:
	var rules := Rules.new()
	var opening := Rules.open_mission(Catalog.read_default(), "harpoon_squad",
		["alchemist", "healer", "bard"])
	for id in ["healer", "bard"]:
		opening = rules.set_order(opening, id, "order_hold")
	var selected: Dictionary = rules.choose_manual(opening, "alchemist", "alchemist_acid", "bruiser")
	var plan: Dictionary = rules.preview_round(selected)
	if not plan.get("valid", false):
		_check(false, "Stock Harpoon Squad acid round is valid")
		return
	var after: Dictionary = rules.commit_round(selected, plan)
	var actor := _entity(after, "alchemist")
	var cues: Array = Cues.build(selected, after, plan.events)
	var acids := cues.filter(func(cue): return cue.get("unit_id") == "alchemist" and cue.get("clip") == "acid")
	_check(actor.get("position") == Vector2i(2, 2) and plan.events.any(func(event):
		return event.get("type") == "pull" and event.get("target_id") == "alchemist"),
		"Hookhand displaces the Mixologist in the stock committed round")
	if acids.size() != 1:
		_check(false, "Stock committed round produces one Mixologist acid cue")
		return
	var cue: Dictionary = acids[0]
	_check(cue.get("source_cell") == Vector2i(1, 2)
		and cue.get("target_id") == "bruiser" and cue.get("target_cell") == Vector2i(2, 3),
		"Acid cue preserves the cast-time source and Bruiser's action-time cell")
	var cells := {}
	for x in after.width:
		for y in after.height:
			cells[Vector2i(x, y)] = "stone"
	var units := []
	for unit in after.units:
		if unit.hp > 0:
			units.append({"id": unit.id, "cell": unit.position, "hp": unit.hp,
				"art_key": rules.entity_profile(after, unit.id).art_key,
				"cast_key": Cues.cast_key_for(after, unit)})
	_release_case(cells, units, cue, 1.0, "Displaced stock cast")
	# Control cases use the same real clip and drawing projection in both directions.
	for facing in [1, -1]:
		var source := Vector2i(3, 2)
		var target := Vector2i(3 + facing, 2)
		var control := cue.duplicate(true)
		control.source_cell = source
		control.actor_cell = source
		control.target_cell = target
		var control_units := [{"id": "alchemist", "cell": source, "hp": 7,
			"art_key": "healer", "cast_key": "alchemist"}]
		_release_case(cells, control_units, control, float(facing), "Stationary facing %d" % facing)


func _release_case(cells: Dictionary, units: Array, cue: Dictionary, facing: float, label: String) -> void:
	board.clear_action_playback()
	board.set_render_state(cells, units)
	board.play_committed_actions([cue])
	board.set_process(false)
	var playback = board.get("_playback")
	var active: Array = playback.active()
	if active.size() != 1 or active[0].gift == null:
		_check(false, label + ": acid flask playback exists")
		return
	var entry = active[0]
	playback.advance(entry.clip.release_ms)
	board.call("_sync_playback_geometry")
	var actor: Dictionary = board.get("_units_by_id").get("alchemist", {})
	var foot: Vector2 = board.call("_tile_origin", actor.cell) + Board.FOOT
	var hand: Vector2 = foot + entry.clip.release_offset * Vector2(entry.facing, 1.0) * entry.clip.scale
	var landing: Vector2 = board.call("_tile_origin", cue.target_cell) + Board.FOOT + Vector2(0, -29)
	_check(entry.facing == facing, label + ": facing follows the action-time target")
	_check(entry.gift_from is Vector2 and entry.gift_from.is_equal_approx(hand),
		label + ": flask starts at the hand projected from the rendered actor's cell")
	_check(entry.gift_to is Vector2 and entry.gift_to.is_equal_approx(landing),
		label + ": flask lands at the action-time target projection")


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _mixologist_knockdown_playback() -> void:
	var rules := Rules.new()
	var opening := Rules.open_mission(Catalog.read_default(), "harpoon_squad",
		["alchemist", "healer", "bard"])
	var jelly := _jelly_potion(rules, opening)
	if jelly.is_empty():
		_check(false, "Self-potion can actually resolve Jelly Knees")
		return
	var potion_before: Dictionary = jelly.state
	var potion_plan: Dictionary = jelly.plan
	var down: Dictionary = rules.apply_plan(potion_before, potion_plan)
	_check(Statuses.knocked_down(down, _entity(down, "alchemist")),
		"Committed self-potion actually knocks the Mixologist down")
	var potion_cues: Array = Cues.build(potion_before, down, potion_plan.events)
	await _knockdown_cast_image(down, potion_cues, "potion", 17,
		"Self-potion with Jelly Knees")

	# A later real reaction knocks her down after the successful acid action.
	var acid_plan: Dictionary = rules.preview(opening, "alchemist", "alchemist_acid", "bruiser")
	if not acid_plan.get("valid", false):
		_check(false, "Acid fixture is a successful real action")
		return
	var after_acid: Dictionary = rules.apply_plan(opening, acid_plan)
	var later_jelly := _jelly_potion(rules, after_acid)
	if later_jelly.is_empty():
		_check(false, "Later self-potion can resolve Jelly Knees")
		return
	var final_state: Dictionary = rules.apply_plan(later_jelly.state, later_jelly.plan)
	_check(Statuses.knocked_down(final_state, _entity(final_state, "alchemist")),
		"Later action really leaves the acid thrower knocked down")
	var acid_cues: Array = Cues.build(opening, final_state, acid_plan.events)
	await _knockdown_cast_image(final_state, acid_cues, "acid", 18,
		"Acid before a later knockdown")


func _jelly_potion(rules, input: Dictionary) -> Dictionary:
	for seed_value in range(1, 1000):
		var candidate := input.duplicate(true)
		_entity(candidate, "alchemist")["dose_rng_state"] = seed_value
		var plan: Dictionary = rules.preview(candidate, "alchemist", "alchemist_potion", "alchemist")
		if plan.get("valid", false) and plan.events.any(func(event):
			return (event.get("type") == "alchemy_reaction" and event.get("reaction_id") == "jelly_knees"
				and event.get("target_id") == "alchemist")):
			return {"state": candidate, "plan": plan}
	return {}


func _knockdown_cast_image(state: Dictionary, cues: Array, clip: String, source_frame: int, label: String) -> void:
	var matching := cues.filter(func(cue): return cue.get("unit_id") == "alchemist" and cue.get("clip") == clip)
	if matching.size() != 1:
		_check(false, label + ": successful rules event produces its action cue")
		return
	var actor := _entity(state, "alchemist")
	var cell: Vector2i = actor.position
	var cells := {cell: "bridge"}
	var down_unit := {"id": "alchemist", "art_key": "healer", "cast_key": "alchemist",
		"cell": cell, "facing": 1, "hp": actor.hp, "max_hp": actor.max_hp, "prone": true}
	board.clear_action_playback()
	board.set_render_state(cells, [down_unit])
	board.set_process(false)
	var idle_down := await _capture()
	board.play_committed_actions(matching)
	board.set_process(false)
	var entries: Array = board.get("_playback").active()
	if entries.size() != 1:
		_check(false, label + ": action enters playback")
		return
	var entry = entries[0]
	if clip == "acid":
		_check(entry.gift != null, label + ": actual flask is attached to the action")
	var sample_ms: float = entry.clip.time_at_source_frame(source_frame) + 10.0
	_advance(sample_ms / 1000.0)
	var down_action := await _capture()
	var standing_unit := down_unit.duplicate(true)
	standing_unit.prone = false
	board.set_render_state(cells, [standing_unit])
	board.set_process(false)
	var standing_action := await _capture()
	# Compare the figure above the health marker; both renders include identical
	# feedback and projectile, so a floating flask cannot stand in for the actor.
	var foot: Vector2 = board.get("_map_origin") + (board.call("_tile_origin", cell) + Board.FOOT) * board.get("_map_scale")
	var top_area := Rect2i(0, 0, viewport.size.x, clampi(int(foot.y - 25), 1, viewport.size.y))
	var actual_figure := down_action.get_region(top_area)
	var expected_figure := standing_action.get_region(top_area)
	var idle_figure := idle_down.get_region(top_area)
	_check(_difference(actual_figure, expected_figure) < 10,
		label + ": live gesture renders despite the final prone state")
	_check(_difference(expected_figure, idle_figure) > 30,
		label + ": sampled gesture is visibly different from idle prone")
	board.set_render_state(cells, [down_unit])
	_advance((entry.duration_ms - entry.elapsed_ms) / 1000.0 + 0.1)
	var returned := await _capture()
	_check(_difference(returned, idle_down) == 0, label + ": completed action returns to prone")
	var fallen := down_unit.duplicate(true)
	fallen.hp = 0
	board.set_render_state(cells, [fallen])
	board.set_process(false)
	var idle_ko := await _capture()
	_check(_difference(idle_ko, idle_down) > 10, label + ": idle fallen remains distinct from living prone")


func _unit(role: String, extra: Dictionary = {}) -> Dictionary:
	var unit := {"id": role, "art_key": role, "cast_key": role, "cell": CELL, "facing": 1}
	unit.merge(extra, true)
	return unit


func _state(unit: Dictionary) -> Image:
	board.set_render_state(CELLS, [unit])
	# Freeze animation so comparisons exercise state, not frame timing.
	board.set_process(false)
	return await _capture()


func _cue(role: String, clip: String) -> void:
	board.play_committed_actions([{"unit_id": role, "cast_key": role, "clip": clip,
		"source_cell": CELL}])
	board.set_process(false)


func _advance(seconds: float) -> void:
	board._process(seconds)
	board.set_process(false)


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _difference(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
