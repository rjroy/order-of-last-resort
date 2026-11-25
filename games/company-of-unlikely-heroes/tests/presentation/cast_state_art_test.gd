extends SceneTree
## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/cast_state_art_test.gd

const Board = preload("res://presentation/battle/bridge_art.gd")
const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
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
	await _shield_away_gesture("rescue_line")
	await _shield_away_gesture("bonk")
	await _fallen_rescue_equipment()
	await _wizard_pull_finishes_seated()
	await _mixologist_pull_recoil()
	await _resisted_pull_before_later_hit()
	_test_acid_release_geometry()
	await _mixologist_knockdown_playback()
	await _rogue_jelly_potion_playback()
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


func _shield_away_gesture(clip_name: String) -> void:
	board.clear_action_playback()
	var away := _unit("knight", {"shield_away": true})
	var hold := await _state(away)
	var cast = board.get("_cast")
	var gesture = cast.clip_for("knight", clip_name + "_unshielded")
	var rescue = cast.clip_for("knight", clip_name)
	if gesture == null or rescue == null:
		_check(false, clip_name + " has shielded and unshielded gesture clips")
		return
	var sample_ms: float = gesture.total_ms * 0.5
	_cue("knight", clip_name)
	_advance(sample_ms / 1000.0)
	var actual := await _capture()
	_check(_difference(hold, actual) > 30, "Shield-away " + clip_name + " visibly plays its gesture")

	# The same authored unshielded clip played directly is the reference, so
	# displaying a shielded gesture or the stationary hold cannot satisfy this.
	board.clear_action_playback()
	await _state(_unit("knight", {"shield_away": false}))
	_cue("knight", clip_name + "_unshielded")
	_advance(sample_ms / 1000.0)
	var expected := await _capture()
	_check(_difference(actual, expected) == 0,
		"Shield-away " + clip_name + " renders the unshielded gesture")

	board.clear_action_playback()
	await _state(away)
	_cue("knight", clip_name)
	var active: Array = board.get("_playback").active()
	if active.is_empty():
		_check(false, "Shield-away " + clip_name + " enters playback")
		return
	_advance((active[0].duration_ms + 1.0) / 1000.0)
	_check(board.action_playback_snapshot().is_empty(), "Shield-away " + clip_name + " completes")
	var returned := await _capture()
	_check(_difference(hold, returned) == 0,
		"Shield-away " + clip_name + " returns to the equipment hold")


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
	var rules := Rules.new()
	var before := Rules.open_mission(Catalog.read_default(), "harpoon_squad", ["wizard", "healer", "bard"])
	before.obstacles = []
	_entity(before, "wizard").position = Vector2i(3, 3)
	_entity(before, "bruiser").position = Vector2i(6, 3)
	_entity(before, "healer").position = Vector2i(0, 0)
	_entity(before, "bard").position = Vector2i(0, 1)
	var plan: Dictionary = rules.preview(before, "wizard", "wizard_pull", "bruiser")
	if not plan.get("valid", false):
		_check(false, "Wizard Pull fixture resolves")
		return
	var after: Dictionary = rules.apply_plan(before, plan)
	var pulls: Array = Cues.build(before, after, plan.events).filter(func(cue): return \
		cue.get("unit_id") == "wizard" and cue.get("clip") == "pull")
	if pulls.size() != 1 or not pulls[0].get("pull_recoil_down", false):
		_check(false, "Wizard Pull cue records its own actual recoil knockdown")
		return
	var down := _unit("wizard", {"prone": true, "hp": 2, "max_hp": 3})
	await _state(down)
	board.play_committed_actions(pulls)
	board.set_process(false)
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


func _mixologist_pull_recoil() -> void:
	board.clear_action_playback()
	var defs := Catalog.read_default()
	defs.classes.alchemist.abilities.append("wizard_pull")
	var rules := Rules.new()
	var before := Rules.open_mission(defs, "harpoon_squad", ["alchemist", "healer", "bard"])
	before.obstacles = []
	_entity(before, "alchemist").position = Vector2i(3, 3)
	_entity(before, "bruiser").position = Vector2i(6, 3)
	_entity(before, "healer").position = Vector2i(0, 0)
	_entity(before, "bard").position = Vector2i(0, 1)
	var plan: Dictionary = rules.preview(before, "alchemist", "wizard_pull", "bruiser")
	if not plan.get("valid", false):
		_check(false, "Mixologist Pull fixture resolves a valid action")
		return
	var after: Dictionary = rules.apply_plan(before, plan)
	var actor := _entity(after, "alchemist")
	_check(actor.hp < _entity(before, "alchemist").hp and Statuses.knocked_down(after, actor)
		and actor.position != _entity(before, "alchemist").position,
		"Committed Pull applies recoil damage, displacement and knockdown")
	var cues: Array = Cues.build(before, after, plan.events)
	var pulls := cues.filter(func(cue): return cue.get("unit_id") == "alchemist" and cue.get("clip") == "pull")
	if pulls.size() != 1:
		_check(false, "Committed Mixologist Pull produces its actual cue")
		return
	_check(pulls[0].get("pull_recoil_down", false),
		"Actual Pull cue records its own recoil knockdown")
	var down := _unit("alchemist", {"art_key": "healer", "prone": Statuses.knocked_down(after, actor),
		"hp": actor.hp, "max_hp": actor.max_hp, "guild_knockdown_art": true})
	var idle_down := await _state(down)
	# Capture the standing reference on a separate playback. Setting the real
	# board to standing while recoil is active represents recovery and correctly
	# invalidates the seated tail, so it must not interrupt the actual timeline.
	var standing := down.duplicate(true)
	standing.prone = false
	await _state(standing)
	board.play_committed_actions(pulls)
	board.set_process(false)
	var reference_entries: Array = board.get("_playback").active()
	if reference_entries.size() != 1:
		_check(false, "Mixologist Pull reference enters playback")
		return
	_advance(reference_entries[0].clip.total_ms * 0.3 / 1000.0)
	var upright_action := await _capture()
	board.clear_action_playback()
	await _state(down)
	board.play_committed_actions(pulls)
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.size() != 1:
		_check(false, "Mixologist Pull enters playback with her own equipment")
		return
	var entry = active[0]
	var cast = board.get("_cast")
	var pull = cast.clip_for("alchemist", "pull")
	var wizard_pull = cast.clip_for("wizard", "pull")
	_check(pull != null and wizard_pull != null and entry.clip.path == pull.path \
		and entry.clip.path != wizard_pull.path,
		"Mixologist Pull uses her own equipped atlas, not the Wizard's")
	_check(entry.gift == null, "Mixologist Pull does not launch a flask")
	_advance(entry.clip.total_ms * 0.3 / 1000.0)
	var recoil_action := await _capture()
	# The DOWN caption differs between these states even while the cast pose is
	# identical. Mask that caption, not the figure or the rest of the board.
	var scale: float = board.get("_map_scale")
	var tile: Vector2 = board.get("_map_origin") + board.call("_tile_origin", CELL) * scale
	var caption := Rect2i(Vector2i(tile + Vector2(42, 0) * scale),
		Vector2i(52 * scale + 2, 25 * scale + 2))
	var recoil_figure := recoil_action.duplicate()
	var upright_figure := upright_action.duplicate()
	recoil_figure.fill_rect(caption, Color.BLACK)
	upright_figure.fill_rect(caption, Color.BLACK)
	_check(_difference(recoil_figure, upright_figure) == 0,
		"Mixologist shows her own Pull gesture before recoil knockdown")
	_check(_difference(recoil_action, idle_down) > 30,
		"Mixologist Pull gesture differs from her ordinary knocked-down pose")
	_advance((entry.clip.total_ms - entry.elapsed_ms - 1.0) / 1000.0)
	var final_drawing := await _capture()
	_check(_difference(final_drawing, idle_down) > 30,
		"Mixologist's final Pull drawing is visibly distinct from ordinary prone")
	_advance((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
	var seated := await _capture()
	_check(board.action_playback_snapshot().is_empty(), "Mixologist Pull completes")
	_check(_difference(seated, final_drawing) == 0,
		"Mixologist holds her own final Pull drawing while still prone from recoil")
	await _state(standing)
	var down_again := await _state(down)
	_check(_difference(down_again, idle_down) == 0 and _difference(down_again, seated) > 30,
		"A later unrelated knockdown after recovery uses ordinary prone, not stale Pull seating")
	# Recovery can happen while a previous action still blocks Pull in the
	# queue, before the Pull has ever populated the board's facing cache.
	board.clear_action_playback()
	await _state(down)
	board.play_committed_actions([{"unit_id": "alchemist", "cast_key": "alchemist",
		"clip": "potion", "source_cell": CELL}, pulls[0]])
	board.set_process(false)
	var waiting: Array = board.get("_playback").active()
	_check(board.action_playback_snapshot().size() == 2 and waiting.size() == 1 \
		and not board.get("_pull_facing").has("alchemist"),
		"Pull waits behind an unrelated action before recovery")
	if waiting.size() != 1:
		return
	var blocking_ms: float = waiting[0].duration_ms
	await _state(standing)
	_check(board.action_playback_snapshot().size() == 2, "Recovery retains both queued actions")
	await _state(down)
	_advance((blocking_ms + 1.0) / 1000.0)
	var now_active: Array = board.get("_playback").active()
	_check(now_active.size() == 1 and now_active[0].cue.clip == "pull",
		"Previously queued Pull still plays after the unrelated action")
	if now_active.size() != 1:
		return
	_advance((now_active[0].duration_ms + 1.0) / 1000.0)
	var queued_return := await _capture()
	_check(_difference(queued_return, idle_down) == 0,
		"Recovery while Pull is queued prevents stale seating on a later knockdown")
	await _same_batch_recoil_reset(after, pulls[0], down, idle_down, seated)


func _resisted_pull_before_later_hit() -> void:
	board.clear_action_playback()
	var defs := Catalog.read_default()
	defs.classes.alchemist.abilities.append("wizard_pull")
	defs.characters["hostile_caster"] = defs.characters.wizard.duplicate(true)
	defs.characters.hostile_caster["team"] = "enemies"
	var rules := Rules.new()
	var before := Rules.open_mission(defs, "harpoon_squad", ["alchemist", "healer", "bard"])
	before.obstacles = []
	_entity(before, "alchemist").position = Vector2i(3, 3)
	_entity(before, "bruiser").position = Vector2i(6, 3)
	_entity(before, "bruiser")["alchemy_statuses"] = {"cork_soles": {"source_id": "bruiser"}}
	_entity(before, "healer").position = Vector2i(0, 0)
	_entity(before, "bard").position = Vector2i(0, 1)
	before.units.append({"id": "hostile_caster", "character_id": "hostile_caster",
		"position": Vector2i(3, 4), "hp": 5, "max_hp": 5, "statuses": {}})
	var hit_first: Dictionary = rules.preview(before, "hostile_caster", "wizard_blast")
	if hit_first.get("valid", false):
		var struck: Dictionary = rules.apply_plan(before, hit_first)
		_check(rules.knocked_down(struck, "alchemist") \
			and not rules.preview(struck, "alchemist", "wizard_pull", "bruiser").get("valid", false),
			"A hit before the turn prevents a knocked-down Mixologist from performing Pull")
	else:
		_check(false, "Independent hostile Blast before Pull resolves")
	var pull: Dictionary = rules.preview(before, "alchemist", "wizard_pull", "bruiser")
	if not pull.get("valid", false):
		_check(false, "Resisted Pull before later hit resolves")
		return
	var middle: Dictionary = rules.apply_plan(before, pull)
	_check(not rules.knocked_down(middle, "alchemist"), "Cork Soles prevents Pull recoil knockdown")
	var hit: Dictionary = rules.preview(middle, "hostile_caster", "wizard_blast")
	if not hit.get("valid", false):
		_check(false, "Later independent hostile Blast resolves")
		return
	var after: Dictionary = rules.apply_plan(middle, hit)
	_check(rules.knocked_down(after, "alchemist") and hit.events.any(func(event):
		return event.get("type") == "damage" and event.get("target_id") == "alchemist"),
		"A later independent hit actually knocks the Mixologist down")
	var cues: Array = Cues.build(before, after, pull.events + hit.events)
	var gestures := cues.filter(func(cue): return cue.get("unit_id") == "alchemist" \
		and cue.get("clip") == "pull_upright")
	if gestures.size() != 1:
		_check(false, "Earlier resisted Pull produces its upright cue")
		return
	_check(not gestures[0].get("pull_recoil_down", false),
		"The later hit does not grant the earlier Pull seated-tail provenance")
	var actor := _entity(after, "alchemist")
	var down := _unit("alchemist", {"art_key": "healer", "prone": true, "hp": actor.hp, "max_hp": actor.max_hp})
	var idle_down := await _state(down)
	board.play_committed_actions(gestures)
	board.set_process(false)
	var entries: Array = board.get("_playback").active()
	if entries.size() != 1:
		_check(false, "Resisted Pull enters playback before the later knockdown")
		return
	var entry = entries[0]
	_advance(0.51)
	var gesture := await _capture()
	_check(_difference(gesture, idle_down) > 30,
		"Earlier upright Pull visibly plays despite the final unrelated knockdown")
	_advance((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
	var returned := await _capture()
	_check(_difference(returned, idle_down) == 0 and not board.get("_pull_facing").has("alchemist"),
		"Resisted Pull finishes in ordinary prone without a seated tail")


func _same_batch_recoil_reset(state: Dictionary, pull: Dictionary, down: Dictionary,
		idle_down: Image, seated: Image) -> void:
	# The final board is prone both before and after the second commit, even
	# though recovery occurred in between. The real recovery event must carry
	# that transition to the presentation queue.
	var recovery_plan: Dictionary = Rules.new().preview_round(state)
	var recoveries: Array = recovery_plan.get("events", []).filter(func(event): return \
		event.get("type") == "recover" and event.get("unit_id") == "alchemist")
	if recoveries.size() != 1:
		_check(false, "Real recoil state produces one committed recovery event")
		return
	var recovery: Dictionary = recoveries[0]
	var later_down := {"type": "damage", "source_id": "bruiser", "target_id": "alchemist",
		"amount": 0, "status_id": "knockdown"}
	var reset_cues: Array = Cues.build(state, state, [recovery, later_down])
	for with_new_pull in [false, true]:
		board.clear_action_playback()
		await _state(down)
		board.play_committed_actions([{"unit_id": "alchemist", "cast_key": "alchemist",
			"clip": "potion", "source_cell": CELL}, pull])
		board.set_process(false)
		var active: Array = board.get("_playback").active()
		if active.size() != 1:
			_check(false, "Prior action blocks old Pull for same-batch recovery test")
			continue
		var blocking_ms: float = active[0].duration_ms
		var batch := reset_cues.duplicate(true)
		if with_new_pull:
			batch.append(pull.duplicate(true))
		board.play_committed_actions(batch)
		board.set_process(false)
		var snapshot: Array = board.action_playback_snapshot()
		var queued := snapshot.filter(func(cue): return cue.get("unit_id") == "alchemist" \
			and cue.get("clip") == "pull")
		_check(queued.size() == (2 if with_new_pull else 1) \
			and not queued[0].get("pull_recoil_down", false),
			"Committed recovery invalidates old queued Pull despite unchanged final prone state")
		if with_new_pull:
			_check(queued.size() == 2 and queued[1].get("pull_recoil_down", false),
				"Recovery does not invalidate a new same-batch recoil after it")
		else:
			_advance((blocking_ms + 1.0) / 1000.0)
			active = board.get("_playback").active()
			if active.size() != 1 or active[0].cue.get("clip") != "pull":
				_check(false, "Old Pull still plays after committed recovery")
				continue
			_advance((active[0].duration_ms + 1.0) / 1000.0)
			active = board.get("_playback").active()
			if active.size() != 1 or active[0].cue.get("clip") != "seated_recover":
				_check(false, "Actual recovery follows the old Pull")
				continue
			_advance((active[0].duration_ms + 1.0) / 1000.0)
			active = board.get("_playback").active()
			if active.size() != 1 or active[0].cue.get("clip") != "down":
				_check(false, "Later unrelated knockdown follows actual recovery")
				continue
			_advance((active[0].duration_ms + 1.0) / 1000.0)
			var returned := await _capture()
			_check(board.action_playback_snapshot().is_empty() and _difference(returned, idle_down) == 0 \
				and _difference(returned, seated) > 30,
				"Committed recovery and later knockdown end at ordinary down, not the stale Pull seat")


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


func _rogue_jelly_potion_playback() -> void:
	board.clear_action_playback()
	var defs := Catalog.read_default()
	defs.characters.rogue.abilities.append("alchemist_potion")
	var rules := Rules.new()
	var before := Rules.open_mission(defs, "harpoon_squad", ["rogue", "healer", "bard"])
	var actor := _entity(before, "rogue")
	actor.hp -= 2
	actor["dose_rng_state"] = 25
	var plan: Dictionary = rules.preview(before, "rogue", "alchemist_potion", "rogue")
	if not plan.get("valid", false):
		_check(false, "Rogue self-potion fixture resolves")
		return
	var after: Dictionary = rules.apply_plan(before, plan)
	_check(plan.events.any(func(event): return event.get("type") == "alchemy_reaction" \
		and event.get("reaction_id") == "jelly_knees" and event.get("applied", false)) \
		and Statuses.knocked_down(after, _entity(after, "rogue")),
		"Rogue self-potion really resolves Jelly Knees and knockdown")
	var cues: Array = Cues.build(before, after, plan.events)
	var potions := cues.filter(func(cue): return cue.get("unit_id") == "rogue" \
		and cue.get("cast_key") == "rogue" and cue.get("clip") == "potion")
	if potions.size() != 1:
		_check(false, "Rogue self-potion produces her own committed cue")
		return
	var result := _entity(after, "rogue")
	var down := _unit("rogue", {"art_key": "wizard", "prone": true, "hp": result.hp, "max_hp": result.max_hp})
	var idle_down := await _state(down)
	board.play_committed_actions(potions)
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.size() != 1:
		_check(false, "Rogue self-potion enters playback")
		return
	var entry = active[0]
	_check(entry.gift == null, "Rogue self-potion does not launch a donor flask")
	_advance(entry.clip.time_at_source_frame(15) / 1000.0 + 0.01)
	var live_down := await _capture()
	var upright := down.duplicate(true)
	upright.prone = false
	var live_upright := await _state(upright)
	_check(_difference(live_down, live_upright) == 0,
		"Rogue self-potion gesture plays before its own Jelly Knees knockdown")
	_check(_difference(live_down, idle_down) > 30,
		"Rogue self-potion gesture is visibly distinct from ordinary prone")
	await _state(down)
	_advance((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
	var returned := await _capture()
	_check(board.action_playback_snapshot().is_empty() and _difference(returned, idle_down) == 0,
		"Rogue self-potion completes and returns to ordinary prone")
	var recovered := await _state(upright)
	_check(_difference(recovered, idle_down) > 30, "Recovering Rogue returns to her standing pose")


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
