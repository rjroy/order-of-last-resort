extends "res://tests/smith_committed_board_test.gd"
## Headless checks the real scene's renderer bindings and geometry. On native
## Wayland, optionally set SMITH_CHOREOGRAPHY_OUTPUT to a fresh absolute
## directory for chronological visible game-window viewport captures.
## Installed production cast sheets are required; no fixture sprites are used.
## Pass -- --case=prone-companions to isolate the prone undead paths.

var _output := ""
var _render_pixels := false
var _wrote_samples := 0


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args != PackedStringArray(["--case=prone-companions"]):
		_check(false, "Use --case=prone-companions or omit the case to verify the full choreography")
		await _finish("Smith choreography")
		return
	_output = OS.get_environment("SMITH_CHOREOGRAPHY_OUTPUT")
	_render_pixels = DisplayServer.get_name() != "headless"
	if not _output.is_empty() and (not _render_pixels or not _output.is_absolute_path() \
			or not DirAccess.dir_exists_absolute(_output) or not DirAccess.get_files_at(_output).is_empty()):
		_check(false, "Capture needs a graphical renderer and a fresh absolute output directory")
		await _finish("Smith choreography")
		return
	root.size = Vector2i(1280, 820)
	await _open_scene()
	var crypter := SummonCases.cases()
	var recall := _case(crypter, "summon_skeleton")
	var play_dead := _case(crypter, "raise_dead")
	await _prone_companion(recall, "skeleton")
	await _prone_companion(play_dead, "zombie")
	if args.is_empty():
		await _recall_choreography(recall)
		await _play_dead_choreography(play_dead)
		var tactical := TacticalCases.cases()
		await _lend_choreography(_case(tactical, "knight_shield_throw"))
		await _shieldless_knight(_case(tactical, "knight_push"), "fitted_pull_unshielded")
		await _shieldless_knight(_case(tactical, "knight_rescue_line"), "safety_distance_unshielded")
		var borrowed := BorrowedCases.cases()
		await _shieldless_knight(_case(borrowed, "borrowed_knight_healer_bonk"), "keep_your_head_down_unshielded")
		await _jump_choreography(_case(tactical, "rogue_confusing_dodge"), 7)
		await _jump_choreography(_case(borrowed, "borrowed_wizard_rogue_confusing_dodge"), 8)
	print("Graphics=", _render_pixels, " saved_chronological_samples=", _wrote_samples)
	await _finish("Smith companion, shield release and jump choreography")


func _recall_choreography(example: Dictionary) -> void:
	var plan := await _commit(example)
	var event := _event(plan, "recall")
	if event.is_empty():
		return
	var owner = _entry(example.actor, "recall")
	var child = _entry(event.target_id, "recall_tuck")
	if owner == null or child == null:
		return
	var cut: float = owner.clip.time_at_source_frame(17)
	_check(is_equal_approx(owner.impact_ms, cut) and child.cue.companion_for == owner.order,
		"Recall owner F17 controls its own Skeleton companion")
	_seek(owner, cut - 1.0)
	var before := _drawn_row(event.target_id)
	_check(before.get("cell") == event.from_position and _drawn_action(event.target_id) != child,
		"Recall holds the single Skeleton on its source until the cut")
	await _sample("recall", "before-cut")
	_seek(owner, cut + 1.0)
	_check(_drawn_row(event.target_id).get("cell") == event.position and _drawn_action(event.target_id) == child \
			and _source_frame(child) == 1 and _drawn_row(event.target_id).hp == before.hp,
		"The same Skeleton draws its own F1 tuck at the destination immediately after the cut")
	var arrived := await _sample("recall", "destination-tuck-f1", event.target_id, "recall_tuck", 1)
	_seek(child, child.clip.time_at_source_frame(9) + 1.0)
	_check(_drawn_action(event.target_id) == child and _source_frame(child) == 9, "Skeleton draws its own later tuck")
	var settling := await _sample("recall", "destination-tuck-f9", event.target_id, "recall_tuck", 9)
	_pixel_change(arrived, settling, _screen_point(_board._unit_foot(event.position)),
		"Skeleton tuck visibly changes on the destination; no duplicate source Skeleton")
	_seek(child, child.clip.total_ms + 1.0)
	_check(_drawn_action(event.target_id) != child and _drawn_row(event.target_id).get("cell") == event.position,
		"Skeleton finishes its tuck on the destination, with no return to the source")
	await _sample("recall", "destination-settled")


func _play_dead_choreography(example: Dictionary) -> void:
	var plan := await _commit(example)
	var event := _event(plan, "play_dead")
	if event.is_empty():
		return
	var owner = _entry(example.actor, "hush")
	var child = _entry(event.summon_id, "play_dead")
	if owner == null or child == null:
		return
	_check(child.cue.companion_for == owner.order and child.cue.cast_key == "zombie" \
		and child.cue.get("requires_existing_figure") and not child.cue.has("performance"),
		"Play Dead's separate Zombie pose belongs to the actual minion, not a second cast")
	_seek(child, -1.0)
	_check(_drawn_action(event.summon_id) != child and _drawn_row(event.target_id).is_empty(),
		"Zombie is still standing before its own performance starts")
	var upright := await _sample("play-dead", "standing", event.summon_id, "ready")
	_seek(child, child.clip.time_at_source_frame(15) + 1.0)
	_check(_drawn_action(event.summon_id) == child and _source_frame(child) == 15 \
		and _drawn_row(event.summon_id).get("cell") == event.position and _drawn_row(event.target_id).is_empty(),
		"Actual Zombie draws its own lowering F15 alone on the handoff cell")
	var lowering := await _sample("play-dead", "zombie-lowering-f15", event.summon_id, "play_dead", 15)
	_pixel_change(upright, lowering, _screen_point(_board._unit_foot(event.position)),
		"Zombie's own silhouette visibly lowers on the real board")
	_seek(child, child.clip.total_ms - 1.0)
	_check(_source_frame(child) == 26 and _drawn_action(event.summon_id) == child \
		and _drawn_row(event.target_id).is_empty(), "Zombie holds the full terminal F26 drawing before handoff")
	var terminal := await _sample("play-dead", "zombie-terminal-f26", event.summon_id, "play_dead", 26)
	_seek(owner, owner.handoff_ms + 1.0)
	_check(_drawn_row(event.summon_id).is_empty() and _drawn_action(event.summon_id) == null \
		and _drawn_row(event.target_id).get("cell") == event.position and _marks("hit").is_empty(),
		"Only the original corpse is drawn after the same-cell handoff, without a transient Zombie or hit")
	var corpse := await _sample("play-dead", "original-corpse-after-f26")
	if _render_pixels:
		_check(_draws_only_play_dead_corpse(event.target_id, event.summon_id),
			"Actual paint contains the original corpse, no Zombie or combat-death caption after F26")
	_pixel_change(terminal, corpse, _screen_point(_board._unit_foot(event.position)),
		"The original corpse visibly replaces the terminal Zombie pose")


func _prone_companion(example: Dictionary, role: String) -> void:
	example = example.duplicate(true)
	if example.is_empty():
		return
	var minions: Array = example.state.units.filter(func(unit): return unit.character_id == role and unit.hp > 0)
	if not _check(minions.size() == 1, "One living minion for the prone " + role + " fixture"):
		return
	var id: String = minions[0].id
	minions[0].statuses["knockdown"] = {"source_id": "enemy"}
	if role == "zombie":
		var ordinary_corpse := _lookup(example.state.units, "corpse").duplicate(true)
		ordinary_corpse.merge({"id": "ordinary_corpse_control", "position": Vector2i(4, 3)}, true)
		ordinary_corpse.erase("corpse_consumed")
		example.state.units.append(ordinary_corpse)
	var plan := await _commit(example)
	var recall := role == "skeleton"
	var event := _event(plan, "recall" if recall else "play_dead")
	if event.is_empty():
		return
	var owner = _entry(example.actor, "recall" if recall else "hush")
	var child = _entry(id, "recall_tuck" if recall else "play_dead")
	if owner == null or child == null:
		return
	var later_child = null
	var later_cell = null
	if recall:
		var next := Rules.new().choose_manual(plan.result, example.actor, example.ability, "1,2")
		var later := _queue_round(next)
		var next_recall := _event(later, "recall")
		var later_owner = _entry(example.actor, "recall", owner.order)
		if not next_recall.is_empty() and later_owner != null:
			later_cell = next_recall.position
			later_child = _board.get("_playback").companion_for(later_owner.order)
	_seek(child, -1.0)
	var source: Vector2i = event.from_position if recall else event.position
	var before_row := _drawn_row(id)
	_check(before_row.get("prone") and before_row.get("cell") == source and _drawn_action(id) == null,
		"Already-prone %s does not use a future Ready or standing companion pose before the effect" % role)
	var before := await _sample("prone-" + role, "before-effect", id, "ready")
	if _render_pixels:
		_check(_board.actual_draw_snapshot().actors.get(id, {}).get("turned_down", false),
			"The actual pre-effect minion uses the stock prone convention")
	_seek(child, child.clip.time_at_source_frame(5) + 1.0)
	_check(_drawn_row(id).get("prone") and _drawn_action(id) == null \
		and _drawn_row(id).get("cell") == event.position,
		"Already-prone %s is relocated/retired in place without an invented stand" % role)
	var held := await _sample("prone-" + role, "held-prone", id, "ready")
	if _render_pixels:
		_check(_board.actual_draw_snapshot().actors.get(id, {}).get("turned_down", false),
			"The visible minion uses the normal prone convention, not an upright companion pose")
	_seek(child, child.clip.total_ms + 1.0)
	if recall:
		_pixel_change(before, held, _screen_point(_board._unit_foot(event.position)),
			"Real viewport draws the prone Skeleton at the new cell")
		var ending := _lookup(plan.result.units, id)
		_check(not Rules.new().knocked_down(plan.result, ending.id) and not _drawn_row(id).get("prone", true),
			"The same Skeleton returns to Ready only after its actual later recovery, not as a Recall effect")
		var recovered := await _sample("prone-skeleton", "recovered-after-first-recall", id, "ready")
		if _render_pixels:
			_check(not _board.actual_draw_snapshot().actors.get(id, {}).get("turned_down", true),
				"The actual draw returns to upright Ready after the earlier prone lifecycle")
		_pixel_change(held, recovered, _screen_point(_board._unit_foot(event.position)),
			"The actual drawing changes from prone to Ready after the paired interval")
		if _check(later_child != null, "An upright second Recall was queued for the same Skeleton"):
			_seek(later_child, 1.0)
			_check(_drawn_row(id).get("cell") == later_cell and not _drawn_row(id).get("prone", true) \
					and _drawn_action(id) == later_child,
				"First Recall's prone projection does not bleed into the later action on the same instance")
			await _sample("prone-skeleton", "second-recall-upright-f1", id, "recall_tuck", 1)
	else:
		_check(_drawn_row(id).is_empty() and _drawn_row(event.target_id).get("cell") == event.position,
			"Already-prone Zombie still hands off once to the same-cell original corpse")
		var corpse := await _sample("prone-zombie", "original-corpse")
		if _render_pixels:
			_check(_draws_only_play_dead_corpse(event.target_id, id),
				"Actual paint contains only the original corpse, no duplicated Zombie or combat-death caption")
			_check(_board.actual_draw_snapshot().marks.any(func(mark):
				return mark.kind == "fallen" and mark.target_id == "ordinary_corpse_control"),
				"The unrelated ordinary corpse still draws its FALLEN caption")
		_pixel_change(held, corpse, _screen_point(_board._unit_foot(event.position)),
			"The original corpse visibly replaces the already-prone Zombie")
		_tick(3.0)
		_scene.call("_refresh_board")
		_board.set_process(false)
		await _sample("prone-zombie", "settled-original-corpse")
		if _render_pixels:
			_check(_draws_only_play_dead_corpse(event.target_id, id),
				"The settled and refreshed original corpse still has no FALLEN caption")


func _lend_choreography(example: Dictionary) -> void:
	if example.is_empty():
		return
	var rules := Rules.new()
	for unit: Dictionary in example.state.units:
		if rules.entity_profile(example.state, unit.id).team == "enemies" and unit.hp > 0:
			unit.position = Vector2i(6, 3)
	_lookup(example.state.units, example.target).position = Vector2i(5, 1)
	var plan := await _commit(example)
	var drop := _event(plan, "shield_drop")
	if drop.is_empty():
		return
	var entry = _entry(example.actor, "lend_a_shield")
	if entry == null:
		return
	var tile: Vector2i = drop.position
	var release: float = entry.clip.time_at_source_frame(18)
	if not _check(entry.is_shield_throw() and entry.gift != null and entry.gift == _board.get("_cast").clip_for(
			"knight", entry.clip.release_clip) and is_equal_approx(entry.clip.release_ms, release) \
			and release < entry.impact_ms, "Lend uses its approved separate F18 prop and later impact"):
		return
	_seek(entry, release - 1.0)
	_check(_source_frame(entry) == 17 and _drawn_action(example.actor) == entry \
		and _board._gift_pose(entry).is_empty() and tile not in _board._presentation_shields() \
		and not _covered(example.target), "F17 still holds shield with no prop, landing marker, or Cover")
	await _sample("lend", "held-f17", example.actor, "lend_a_shield", 17)
	_seek(entry, release + 1.0)
	var split := _board._gift_pose(entry)
	var source: Vector2 = _board._unit_foot(entry.cue.source_cell) \
		+ entry.clip.release_offset * Vector2(entry.facing, 1.0) * entry.clip.scale
	_check(_source_frame(entry) == 18 and not split.is_empty() and split.position.distance_to(source) < 1.0,
		"Detached shield starts at the actual F18 hand mount")
	var split_image := await _sample("lend", "release-f18", example.actor, "lend_a_shield", 18)
	_seek(entry, (release + entry.impact_ms) * 0.5)
	var flying := _board._gift_pose(entry)
	_check(not flying.is_empty() and flying.position.distance_to(source) > 10.0 \
		and tile not in _board._presentation_shields() and not _covered(example.target),
		"Shield flies as one low prop without a premature loose marker or Cover")
	var flight_image := await _sample("lend", "detached-flight")
	if _render_pixels:
		var drawn := _board.actual_draw_snapshot()
		_check(drawn.props.any(func(prop): return prop.actor_id == example.actor \
				and prop.clip == entry.clip.release_clip and prop.atlas == entry.gift.path \
				and prop.position == flying.position) and tile not in drawn.shields,
			"The actual paint contains the detached prop but no ground shield while airborne")
	_pixel_change(split_image, flight_image, _screen_point(flying.get("position", source)),
		"Detached shield changes visible pixels along its real flight path")
	_seek(entry, entry.impact_ms + 1.0)
	_check(_board._gift_pose(entry).is_empty() and _board._presentation_shields().count(tile) == 1 \
		and _drawn_row(example.actor).shield_away and _covered(example.target) \
		and _drawn_action(example.actor) == entry,
		"Arrival draws one shield and Cover; Knight keeps the Lend recovery pose")
	var landing := await _sample("lend", "landed-with-cover", example.actor, "lend_a_shield")
	if _render_pixels:
		var drawn := _board.actual_draw_snapshot()
		_check(tile in drawn.shields and not drawn.props.any(func(prop): return prop.actor_id == example.actor) \
			and drawn.marks.any(func(mark): return mark.kind == "cover" and mark.target_id == example.target),
			"The actual paint has one shield marker and the recipient's Cover after arrival")
	_pixel_change(flight_image, landing, _screen_point(_board._tile_origin(tile) + BridgeArt.SHIELD_MARK_CENTER),
		"The resolved tile visibly changes when shield and Cover arrive")


func _shieldless_knight(example: Dictionary, expected: String) -> void:
	if example.is_empty():
		return
	_lookup(example.state.units, "knight").shield_position = Vector2i(1, 1)
	var plan := await _commit(example)
	if plan.is_empty():
		return
	var entry = _entry("knight", expected)
	if entry == null:
		return
	_seek(entry, entry.impact_ms + 1.0)
	var pose = _drawn_action("knight")
	_check(pose == entry and _drawn_row("knight").get("shield_away") \
		and _board._knight_action_while_shield_away(pose) == expected,
		"Draw selection keeps %s, rather than substituting static Shield Away" % expected)
	await _sample(expected, "impact", "knight", expected, _source_frame(entry))


func _jump_choreography(example: Dictionary, takeoff_frame: int) -> void:
	var plan := await _commit(example)
	if plan.is_empty():
		return
	var entry = _entry(example.actor, "clear_jump")
	if entry == null:
		return
	var motion: Dictionary = entry.cue.motions[0]
	var origin := _board._unit_foot(motion.from)
	var landing := _board._unit_foot(motion.to)
	var takeoff: float = entry.clip.time_at_source_frame(takeoff_frame)
	var land: float = entry.clip.time_at_source_frame(17)
	var locator: String = entry.cue.performance.aim.id
	_seek(entry, takeoff - 1.0)
	var locator_foot := _visible_foot(locator)
	_check(_drawn_action(example.actor) == entry and _visible_foot(example.actor) == origin \
			and entry.impact_ms == land, "Only the actor is planted before its wearer-specific takeoff")
	var ready := await _sample(example.actor + "-jump", "planted")
	_seek(entry, takeoff + 1.0)
	_check(_source_frame(entry) == takeoff_frame and _visible_foot(example.actor).distance_to(origin) < 1.0 \
			and _visible_foot(locator) == locator_foot, "Travel begins at the authored takeoff, not during the plant")
	await _sample(example.actor + "-jump", "takeoff-f%d" % takeoff_frame, example.actor, "clear_jump", takeoff_frame)
	_seek(entry, entry.clip.time_at_source_frame(12) + 1.0)
	var mid := _visible_foot(example.actor)
	_check(_source_frame(entry) == 12 and mid.distance_to(origin) > 4.0 and mid.distance_to(landing) > 4.0 \
		and _visible_foot(locator) == locator_foot, "F12 shows only the active wearer translated between cells")
	var airborne := await _sample(example.actor + "-jump", "airborne-f12", example.actor, "clear_jump", 12)
	_pixel_change(ready, airborne, _screen_point(mid), "Jump visibly traverses the game board")
	_seek(entry, land + 1.0)
	_check(_source_frame(entry) == 17 and _visible_foot(example.actor) == landing \
		and _visible_foot(locator) == locator_foot, "F17 plants the wearer beside the unchanged locator")
	var planted := await _sample(example.actor + "-jump", "landing-f17", example.actor, "clear_jump", 17)
	_pixel_change(airborne, planted, _screen_point(landing), "Landing visibly plants at the resolved destination")


func _entry(id: String, clip: String, after_order := -1):
	for entry in _board.get("_playback").get("_entries"):
		if entry.cue.unit_id == id and entry.cue.clip == clip and entry.order > after_order:
			return entry
	_check(false, "No actual queued %s clip for %s" % [clip, id])
	return null


func _seek(entry, sample_ms: float) -> void:
	if _check(sample_ms >= entry.elapsed_ms, "Choreography samples advance monotonically"):
		_tick((sample_ms - entry.elapsed_ms) / 1000.0)


func _source_frame(entry) -> int:
	return entry.clip.source_frames[entry.clip.frame_index(entry.elapsed_ms + entry.sample_offset_ms)]


func _frame_state() -> Dictionary:
	return _board._figure_frame(_board.get("_playback").active())


func _drawn_row(id: String) -> Dictionary:
	return _lookup(_frame_state().occupants, id)


func _drawn_action(id: String):
	return _frame_state().actions.get(id)


func _visible_foot(id: String) -> Vector2:
	var row := _drawn_row(id)
	return _board._visual_foot(row) if not row.is_empty() else Vector2.INF


func _covered(id: String) -> bool:
	return _drawn_row(id).get("tactical_statuses", {}).has("lend_a_shield")


func _draws_only_play_dead_corpse(corpse_id: String, zombie_id: String) -> bool:
	var draw := _board.actual_draw_snapshot()
	return draw.actors.has(corpse_id) and not draw.actors.has(zombie_id) \
		and not draw.marks.any(func(mark): return mark.kind == "fallen" and mark.target_id == corpse_id)


func _screen_point(logical: Vector2) -> Vector2:
	return _board.get_global_transform_with_canvas() \
		* (_board.get("_map_origin") + logical * _board.get("_map_scale"))


func _sample(example: String, stage: String, actor_id := "", clip := "", source_frame := -1) -> Image:
	if not _render_pixels:
		return null
	_board.set_actual_draw_capture_enabled(true)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var drawn := _board.actual_draw_snapshot()
	if not actor_id.is_empty():
		var pose: Dictionary = drawn.get("actors", {}).get(actor_id, {})
		_check(not pose.is_empty() and not str(pose.get("atlas", "")).is_empty() and pose.get("clip") == clip \
			and (source_frame < 0 or pose.get("source_frame") == source_frame),
			"%s: actual paint used the expected wearer, atlas, and source frame" % stage)
		print("DRAW ", example, " ", stage, " frame_serial=", drawn.get("frame_serial"), " actor=", pose)
	if _check(image != null and not image.is_empty() and _board.is_visible_in_tree(),
			"Capture sees the actual game board in the visible window: " + stage) and not _output.is_empty():
		var path := _output.path_join("%02d-%s-%s.png" % [_wrote_samples, example, stage])
		_check(image.save_png(path) == OK, "Capture writes " + path)
		_wrote_samples += 1
	return image


func _pixel_change(older: Image, newer: Image, point: Vector2, message: String) -> void:
	if not _render_pixels:
		return
	if not _check(older != null and newer != null, "Both viewport images exist: " + message):
		return
	var box := Rect2i(Vector2i(point) - Vector2i(27, 66), Vector2i(54, 82)) \
		.intersection(Rect2i(Vector2i.ZERO, older.get_size()))
	var changed := 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if older.get_pixel(x, y) != newer.get_pixel(x, y):
				changed += 1
	_check(changed >= 24, "%s (%d changed local pixels)" % [message, changed])
