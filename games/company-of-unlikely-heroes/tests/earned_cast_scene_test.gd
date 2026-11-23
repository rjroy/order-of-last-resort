extends "res://tests/guild_full_catalog_test.gd"
## Run with a graphical display:
## godot --path games/company-of-unlikely-heroes --script res://tests/earned_cast_scene_test.gd

var scene: Node


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Earned cast scene test requires a graphical renderer.")
		quit(1)
		return
	call_deferred("_run_earned_cast")


func _run_earned_cast() -> void:
	defs = Catalog.read_default()
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	root.size = Vector2i(1280, 820)
	await _case("knight", "knight_shield_throw", "shield_throw")
	await _case("necromancer", "necromancer_say_hello_to_that_one", "nominate")
	await _redirected_shield()
	await _forced_pickup()
	await _rapid_swap(false)
	await _rapid_swap(true)
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: earned Shield Throw and nomination presentations")
	quit(0 if failures.is_empty() else 1)


func _rapid_swap(mirrored: bool) -> void:
	var state := _earned_mission("knight", "knight_shield_throw")
	if state.is_empty():
		return
	state.units = [_unit_at(state, "knight"), _unit_at(state, "enemy"),
		_unit("rogue", "rogue", Vector2i(5, 3), 20)]
	state.party = ["knight", "rogue"]
	state.objective = {"handler": "survive", "turns": 9, "reserves": []}
	if mirrored:
		for unit: Dictionary in state.units:
			unit.position.x = 9 - unit.position.x
	var knight_start: Vector2i = _unit_at(state, "knight").position
	var rogue_start: Vector2i = _unit_at(state, "rogue").position
	var facing := -1.0 if mirrored else 1.0
	var label := "Two-commit swap facing %s" % facing
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	root.add_child(scene)
	await process_frame
	scene.call("_show_battle", state)
	await process_frame
	var board: Control = scene.find_child("BridgeBoard", true, false)
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await driver.command("knight", "knight_shield_throw", "enemy"):
		_check(false, label + " stages Shield Throw: " + driver.error)
		return
	var commit := scene.find_child("Commit", true, false) as BaseButton
	commit.pressed.emit()
	board.set_process(false)
	var throws: Array = board.get("_playback").active().filter(
		func(entry): return entry.cue.get("unit_id") == "knight" and entry.cue.get("clip") == "shield_throw")
	if throws.size() != 1:
		_check(false, label + " queues one throw on the first real commit")
		return
	var throw = throws[0]
	var windup_ms: float = throw.clip.release_ms * 0.5
	_check(throw.facing == facing and throw.gift != null and windup_ms > 0.0,
		label + " has the expected launch facing and timed windup")

	# Keep the two real commits and live board, but stage the second command
	# without UI frame waits so the first throw is still in its windup.
	var middle: Dictionary = scene.battle_snapshot()
	scene.set("_planned_state", rules.choose_manual(middle, "rogue", "rogue_confusing_dodge"))
	scene.call("_refresh")
	var plan: Dictionary = scene.get("_plan")
	var retrieves: bool = plan.events.any(func(event):
		return event.type == "shield_retrieve" and event.unit_id == "knight")
	if commit.disabled or not retrieves or throw.elapsed_ms >= windup_ms:
		_check(false, label + " can commit Dodge and its shield pickup before release")
		return
	commit.pressed.emit()
	_advance_board(board, windup_ms - throw.elapsed_ms)
	var resolved: Dictionary = scene.battle_snapshot()
	_check(_unit_at(resolved, "knight").position == rogue_start \
		and _unit_at(resolved, "rogue").position == knight_start \
		and not (rules.shield_position(resolved, "knight") is Vector2i),
		label + " immediately commits the exchanged positions and equipment pickup")
	_check(not commit.disabled, label + " leaves the next round available during playback")
	await _check_swap_figures(board, knight_start, rogue_start, label + " windup")

	var flight_ms: float = throw.clip.release_ms \
		+ preload("res://presentation/cast_playback.gd").GIFT_FLIGHT_MS * 0.5
	_advance_board(board, flight_ms - throw.elapsed_ms)
	_check(throw.gift_from is Vector2 and throw.flight_progress() > 0.0 and throw.flight_progress() < 1.0,
		label + " reaches mid-flight after the second commit")
	await _check_swap_figures(board, knight_start, rogue_start, label + " flight")

	_advance_board(board, board.action_playback_remaining_ms() + 1.0)
	_check(board.action_playback_snapshot().is_empty(), label + " fully settles its playback queue")
	await _check_swap_figures(board, rogue_start, knight_start, label + " resolved swap")


func _advance_board(board: Control, ms: float) -> void:
	board._process(ms / 1000.0)
	board.set_process(false)


func _check_swap_figures(board: Control, knight_cell: Vector2i, rogue_cell: Vector2i, label: String) -> void:
	var figures := board.get("_figures") as CanvasItem
	await process_frame
	await RenderingServer.frame_post_draw
	var painted := root.get_texture().get_image()
	figures.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var bare := root.get_texture().get_image()
	figures.show()
	for pair in [["Knight", knight_cell], ["Rogue", rogue_cell]]:
		# Sample the lower body, below the mid-flight shield. The two
		# units are two tiles apart, with no other figure in these patches.
		var foot: Vector2 = board.get("_map_origin")
		var scale: float = board.get("_map_scale")
		foot += board.call("_unit_foot", pair[1]) * scale
		var to_view := root.get_stretch_transform() * board.get_global_transform_with_canvas()
		var region := Rect2i(Rect2(to_view * (foot + Vector2(-20, -23) * scale),
			(to_view.basis_xform(Vector2(40, 20) * scale)).abs()))
		_check(_difference(painted.get_region(region), bare.get_region(region)) > 10,
			"%s shows the %s at %s" % [label, pair[0], pair[1]])


func _earned_mission(hero: String, reward: String) -> Dictionary:
	var profile := _profile()
	if hero == "necromancer":
		profile = Progression.purchased_profile(defs, profile, "recruit_necromancer")
	var loadout: Dictionary = Progression.default_loadout(defs, profile, hero)
	var commission := Commissions.board(defs, profile.board_seed)
	if commission.is_empty() or loadout.is_empty():
		_check(false, reward + " has a commission and eligible kit")
		return {}
	var party := [hero, "knight" if hero != "knight" else "healer", "wizard"]
	var run := Adventure.start_guild_commission(defs, commission[0], party, profile, {hero: loadout}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, reward + " starts an adventure")
		return {}
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	if run.get("mission", {}).is_empty():
		_check(false, reward + " has an initial mission")
		return {}
	# Control the earned offer, then use the real reward selection and next-mission deployment.
	run.phase = "reward"
	run.reward_offers = [{"hero_id": hero, "upgrade_id": reward}]
	run = Adventure.choose_reward(run, hero, reward)
	if run.get("upgrades_by_id", {}).get(hero, {}).get(reward, 0) != 1:
		_check(false, reward + " is earned through reward selection")
		return {}
	if run.get("phase") == "route":
		if run.get("reports", []).is_empty():
			_check(false, reward + " has a subsequent route")
			return {}
		run = Adventure.choose_route(run, run.reports[0].mission_id)
	run = Adventure.begin_mission(run)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		_check(false, reward + " deploys on a subsequent mission")
		return {}
	var upgrades: Dictionary = _unit_at(state, hero).get("upgrades", {}).duplicate(true)
	_check(upgrades.get(reward, 0) == 1, reward + " reaches the subsequent mission")
	state = _battlefield(state, hero)
	_unit_at(state, hero).upgrades = upgrades
	_unit_at(state, "enemy").position = Vector2i(6, 3)
	if hero == "necromancer":
		_unit_at(state, "enemy").position = Vector2i(7, 3)
		state.units.append(_unit("nearer", "harpooner", Vector2i(4, 4), 20))
		var skeleton := _unit("minion", "skeleton", Vector2i(4, 5), 5)
		skeleton["summoner_id"] = hero
		state.units.append(skeleton)
	return state


func _case(hero: String, ability: String, clip: String) -> void:
	var state := _earned_mission(hero, ability)
	if state.is_empty():
		return
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.call("_show_battle", state.duplicate(true))
	await process_frame
	var board: Node = scene.find_child("BridgeBoard", true, false)
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await driver.command(hero, ability, "enemy"):
		_check(false, ability + " can stage its earned action: " + driver.error)
		return
	_check(scene.battle_snapshot() == state and board.action_playback_snapshot().is_empty(),
		ability + " preview is silent and leaves the battle uncommitted")
	var plan: Dictionary = scene.get("_plan").duplicate(true)
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit == null or commit.disabled:
		_check(false, ability + " can commit")
		return
	commit.pressed.emit()
	await process_frame
	_check(scene.battle_snapshot() == plan.get("result"), ability + " commits its forecast")
	var committed: Dictionary = scene.battle_snapshot()
	var drop: Variant = null
	var restored := false
	if hero == "knight":
		drop = rules.shield_position(committed, hero)
		var drops: Array = plan.get("events", []).filter(func(event): return event.get("type") == "shield_drop" \
			and event.get("unit_id") == hero)
		_check(drop is Vector2i and drops.size() == 1 and drops[0].get("position") == drop,
			"Committed Shield Throw records the actual shield-drop event tile")
		var step: Dictionary = rules.preview(committed, hero, "move", "4,3")
		if step.get("valid", false):
			var approaching: Dictionary = rules.apply_plan(committed, step)
			_check(rules.shield_position(approaching, hero) is Vector2i,
				"Shield remains away while outside retrieval range")
			var pickup: Dictionary = rules.preview(approaching, hero, "move", "5,3")
			if pickup.get("valid", false):
				var picked: Dictionary = rules.apply_plan(approaching, pickup)
				restored = not (rules.shield_position(picked, hero) is Vector2i)
		_check(restored, "Actual movement retrieves the dropped shield")
	else:
		_check(_unit_at(committed, hero).get("nominated_target_id") == "enemy",
			"Committed nomination retains the selected distant enemy")
		var before_minion: Vector2i = _unit_at(committed, "minion").position
		var pursuit: Dictionary = rules.preview_round(committed)
		_check(pursuit.get("valid", false) and \
			_unit_at(pursuit.result, "minion").position.distance_to(_unit_at(committed, "enemy").position) \
				< before_minion.distance_to(_unit_at(committed, "enemy").position),
			"Undead continue to pursue the nominated target rather than the nearer opponent")
	var matches: Array = board.action_playback_snapshot().filter(func(cue): return \
		cue.get("unit_id") == hero and cue.get("cast_key") == hero and cue.get("clip") == clip)
	if matches.size() != 1:
		_check(false, ability + " plays one " + hero + "." + clip + " cue on commit")
		return
	var cue: Dictionary = matches[0]
	_check(cue.get("target_id") == "enemy" and cue.get("target_cell") == _unit_at(state, "enemy").position,
		ability + " aims at the selected enemy, not a nearer actor")
	if hero == "knight" and drop is Vector2i and restored:
		await _shield_timeline(cue, drop)
	elif hero == "necromancer":
		var entries: Array = board.get("_playback").active()
		var pointing := entries.filter(func(entry): return entry.cue.get("unit_id") == hero \
			and entry.cue.get("clip") == clip)
		_check(pointing.size() == 1 and pointing[0].facing == 1.0 \
			and is_equal_approx(pointing[0].impact_ms, pointing[0].clip.time_at_source_frame(13)),
			"Nomination points toward its selected target at the authored contact frame")


func _redirected_shield() -> void:
	var state := _earned_mission("knight", "knight_shield_throw")
	if state.is_empty():
		return
	_unit_at(state, "enemy").statuses["body_double"] = {"partner_id": "redirect", "source_id": "enemy"}
	state.units.append(_unit("redirect", "harpooner", Vector2i(6, 4), 20))
	var plan: Dictionary = rules.preview(state, "knight", "knight_shield_throw", "enemy")
	if not plan.get("valid", false):
		_check(false, "Redirected Shield Throw resolves")
		return
	var after: Dictionary = rules.apply_plan(state, plan)
	var drop: Variant = rules.shield_position(after, "knight")
	_check(drop == Vector2i(6, 4) and drop != _unit_at(state, "enemy").position \
		and plan.events.any(func(event): return event.get("type") == "body_double"),
		"Real Body Double redirects the shield's actual drop away from the intended target")
	var cues: Array = preload("res://presentation/cast_cues.gd").build(state, after, plan.events)
	var throws := cues.filter(func(cue): return cue.get("unit_id") == "knight" and cue.get("clip") == "shield_throw")
	if throws.size() != 1:
		_check(false, "Redirected Shield Throw produces its actual cast cue")
		return
	await _shield_timeline(throws[0], drop)


func _forced_pickup() -> void:
	var state := _earned_mission("knight", "knight_shield_throw")
	if state.is_empty():
		return
	_unit_at(state, "patient").position = Vector2i(4, 4)
	_unit_at(state, "civilian").position = Vector2i(5, 4)
	state.units.append(_unit("rogue", "rogue", Vector2i(5, 3), 20))
	var thrown: Dictionary = rules.preview(state, "knight", "knight_shield_throw", "enemy")
	if not thrown.get("valid", false):
		_check(false, "Forced pickup fixture throws the shield")
		return
	var middle: Dictionary = rules.apply_plan(state, thrown)
	var drop: Variant = rules.shield_position(middle, "knight")
	var swap: Dictionary = rules.preview(middle, "rogue", "rogue_confusing_dodge")
	if not swap.get("valid", false):
		_check(false, "Forced pickup fixture resolves Confusing Dodge")
		return
	var after: Dictionary = rules.apply_plan(middle, swap)
	_check(drop is Vector2i and not (rules.shield_position(after, "knight") is Vector2i) \
		and swap.events.any(func(event): return event.get("type") == "shield_retrieve" \
			and event.get("unit_id") == "knight"),
		"Real allied swap moves the Knight into retrieval range in the same event sequence")
	var mapper := preload("res://presentation/cast_cues.gd")
	var cues: Array = mapper.build(state, after, thrown.events)
	var throws := cues.filter(func(value): return value.get("unit_id") == "knight" \
		and value.get("clip") == "shield_throw")
	if throws.size() != 1:
		_check(false, "Throw followed by forced pickup retains its original cue")
		return
	_check(not throws[0].get("shield_away", true),
		"Same-sequence throw cue records final recovered equipment")
	var swaps := mapper.build(middle, after, swap.events).filter(
		func(value): return value.get("unit_id") == "rogue" and value.get("clip") == "swap")
	if swaps.size() != 1:
		_check(false, "Forced pickup also produces the Rogue's actual swap cue")
		return
	if drop is Vector2i:
		await _full_swap_board(throws[0], swaps[0], _unit_at(state, "rogue").position,
			_unit_at(after, "knight").position, false)
		await _full_swap_board(throws[0], swaps[0], _unit_at(state, "rogue").position,
			_unit_at(after, "knight").position, true)
		await _displaced_throw_origin(throws[0], _unit_at(after, "knight").position, false)
		await _displaced_throw_origin(throws[0], _unit_at(after, "knight").position, true)
		await _shield_timeline(throws[0], drop)


func _full_swap_board(original: Dictionary, original_swap: Dictionary, rogue_start: Vector2i,
		knight_end: Vector2i, mirrored: bool) -> void:
	var throw := original.duplicate(true)
	var swap := original_swap.duplicate(true)
	if mirrored:
		for cue in [throw, swap]:
			for key in ["source_cell", "actor_cell", "target_cell", "shield_drop_cell"]:
				if cue.get(key) is Vector2i:
					cue[key] = Vector2i(9 - cue[key].x, cue[key].y)
			for recipient in cue.get("recipients", []):
				if recipient.get("cell") is Vector2i:
					recipient.cell = Vector2i(9 - recipient.cell.x, recipient.cell.y)
		rogue_start = Vector2i(9 - rogue_start.x, rogue_start.y)
		knight_end = Vector2i(9 - knight_end.x, knight_end.y)
	var knight_start: Vector2i = throw.actor_cell
	var rogue_end: Vector2i = swap.actor_cell
	_check(knight_start == rogue_end and knight_end == rogue_start and knight_start != knight_end,
		"Real pickup swap exchanges the two figures")
	var cells := {}
	for x in range(2, 8):
		cells[Vector2i(x, 3)] = "stone"
	var renderer := preload("res://bridge_art.gd").new()
	var view := SubViewport.new()
	view.size = Vector2i(480, 220)
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	renderer.size = Vector2(view.size)
	view.add_child(renderer)
	var container := SubViewportContainer.new()
	container.add_child(view)
	root.add_child(container)
	var knight := {"id": "knight", "art_key": "knight", "cast_key": "knight",
		"cell": knight_start, "shield_away": false}
	var rogue := {"id": "rogue", "art_key": "wizard", "cast_key": "rogue", "cell": rogue_start}
	renderer.set("_ready_ms", 0.0)
	renderer.set_render_state(cells, [knight, rogue])
	renderer.play_committed_actions([throw])
	renderer.set_process(false)
	var active: Array = renderer.get("_playback").active()
	if active.size() != 1:
		_check(false, "Full-board throw reference plays")
		container.queue_free()
		return
	var windup_ms: float = active[0].clip.release_ms * 0.5
	renderer._process(windup_ms / 1000.0)
	renderer.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var expected := view.get_texture().get_image()
	var flight_ms: float = active[0].clip.release_ms \
		+ preload("res://presentation/cast_playback.gd").GIFT_FLIGHT_MS * 0.5
	renderer._process((flight_ms - windup_ms) / 1000.0)
	renderer.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var expected_flight := view.get_texture().get_image()
	renderer.clear_action_playback()
	knight.cell = knight_end
	rogue.cell = rogue_end
	renderer.set("_ready_ms", 0.0)
	renderer.set_render_state(cells, [knight, rogue])
	# Exercise the same-batch scheduler with two genuine resolved action cues.
	renderer.play_committed_actions([throw, swap])
	renderer.set_process(false)
	renderer._process(windup_ms / 1000.0)
	renderer.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var actual := view.get_texture().get_image()
	_check(_difference(actual, expected) == 0,
		"Full-board throw keeps Knight and Rogue visibly at separate pre-swap cells, mirrored=%s" % mirrored)
	renderer._process((flight_ms - windup_ms) / 1000.0)
	renderer.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(_difference(view.get_texture().get_image(), expected_flight) == 0,
		"Full-board flight keeps both pre-swap figures and the detached shield, mirrored=%s" % mirrored)
	renderer._process((renderer.action_playback_remaining_ms() + 1.0) / 1000.0)
	renderer.set_process(false)
	renderer.set("_ready_ms", 0.0)
	renderer.set_render_state(cells, [knight, rogue])
	renderer.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var final_image := view.get_texture().get_image()
	renderer.clear_action_playback()
	renderer.set_render_state(cells, [knight, rogue])
	renderer.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(_difference(final_image, view.get_texture().get_image()) == 0,
		"Full-board playback finishes with both figures at the authoritative swapped cells, mirrored=%s" % mirrored)
	container.queue_free()


func _displaced_throw_origin(original: Dictionary, final_cell: Vector2i, mirrored: bool) -> void:
	var cue := original.duplicate(true)
	if mirrored:
		for key in ["source_cell", "actor_cell", "target_cell", "shield_drop_cell"]:
			if cue.get(key) is Vector2i:
				cue[key] = Vector2i(9 - cue[key].x, cue[key].y)
		final_cell = Vector2i(9 - final_cell.x, final_cell.y)
	var source: Vector2i = cue.source_cell
	var drop: Vector2i = cue.shield_drop_cell
	var facing := -1.0 if mirrored else 1.0
	_check(source != final_cell, "Forced-pickup fixture moves the final Knight away from the cast cell")
	var cells := {}
	for x in range(2, 8):
		cells[Vector2i(x, 3)] = "stone"
	var renderer := preload("res://bridge_art.gd").new()
	var view := SubViewport.new()
	view.size = Vector2i(480, 220)
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	renderer.size = Vector2(view.size)
	view.add_child(renderer)
	var container := SubViewportContainer.new()
	container.add_child(view)
	root.add_child(container)
	var at_source := {"id": "knight", "art_key": "knight", "cast_key": "knight",
		"cell": source, "facing": facing, "shield_away": false}
	var at_final := at_source.duplicate(true)
	at_final.cell = final_cell
	await _render_view(renderer, view, cells, at_source, {})
	renderer.play_committed_actions([cue])
	renderer.set_process(false)
	var entries: Array = renderer.get("_playback").active()
	if entries.size() != 1:
		_check(false, "Displaced throw reference enters playback")
		container.queue_free()
		return
	var entry = entries[0]
	var windup_ms: float = entry.clip.release_ms * 0.5
	renderer._process(windup_ms / 1000.0)
	renderer.set_process(false)
	var expected_windup := await _render_view(renderer, view, cells, at_source, {})
	renderer.clear_action_playback()
	await _render_view(renderer, view, cells, at_final, {})
	renderer.play_committed_actions([cue])
	renderer.set_process(false)
	entries = renderer.get("_playback").active()
	if entries.size() != 1:
		_check(false, "Displaced committed throw enters playback")
		container.queue_free()
		return
	entry = entries[0]
	renderer._process(windup_ms / 1000.0)
	renderer.set_process(false)
	var actual_windup := await _render_view(renderer, view, cells, at_final, {})
	_check(_difference(actual_windup, expected_windup) == 0,
		"Displaced throw draws exactly one Knight at the action-time cell facing %s" % facing)
	renderer._process((entry.clip.release_ms - entry.elapsed_ms + 1.0) / 1000.0)
	renderer.set_process(false)
	var hand: Vector2 = renderer.call("_unit_foot", source) \
		+ entry.clip.release_offset * Vector2(facing, 1.0) * entry.clip.scale
	var landing_tile := Rect2(renderer.call("_tile_origin", drop), Vector2(preload("res://bridge_art.gd").TILE))
	_check(entry.gift_from is Vector2 and entry.gift_from.is_equal_approx(hand) \
		and entry.gift_to is Vector2 and landing_tile.has_point(entry.gift_to),
		"Displaced throw launches from the action-time hand to the resolved drop facing %s" % facing)
	renderer._process((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
	renderer.set_process(false)
	renderer.set("_ready_ms", 0.0)
	var returned := await _render_view(renderer, view, cells, at_final, {})
	renderer.clear_action_playback()
	var expected_final := await _render_view(renderer, view, cells, at_final, {})
	_check(_difference(returned, expected_final) == 0 and renderer.action_playback_snapshot().is_empty(),
		"After displaced throw one held-shield Knight returns to the final cell facing %s" % facing)
	container.queue_free()


func _shield_timeline(cue: Dictionary, drop: Vector2i) -> void:
	# Use the actual committed cue with an otherwise empty board. Captures with
	# and without the ground overlay expose a duplicate marker during the flight.
	var source: Vector2i = cue.source_cell
	var cells := {source: "stone", drop: "stone"}
	var renderer := preload("res://bridge_art.gd").new()
	var view := SubViewport.new()
	view.size = Vector2i(480, 220)
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	renderer.size = Vector2(view.size)
	view.add_child(renderer)
	var container := SubViewportContainer.new()
	container.add_child(view)
	root.add_child(container)
	var knight := {"id": "knight", "art_key": "knight", "cast_key": "knight",
		"cell": source, "facing": 1, "shield_away": true}
	var hold := await _render_view(renderer, view, cells, knight, {})
	renderer.set_render_state(cells, [knight], {"shields": [drop]})
	renderer.play_committed_actions([cue])
	renderer.set_process(false)
	var entries: Array = renderer.get("_playback").active()
	if entries.size() != 1:
		_check(false, "Shield Throw has a packaged playable clip")
		container.queue_free()
		return
	var entry = entries[0]
	_check(entry.gift != null and entry.clip.release_ms > 0.0,
		"Shield Throw has a separately rendered shield and timed release")
	if entry.gift == null or entry.clip.release_ms <= 0.0:
		container.queue_free()
		return
	var release_index: int = entry.clip.frame_index(entry.clip.release_ms + 0.01)
	_check(entry.clip.source_frames[release_index] == 16 and release_index > 0 \
		and entry.clip.source_frames[release_index - 1] == 15,
		"Shield release uses the authored last-held and first-empty frames")
	var before_ground := await _ground_comparison(renderer, view, cells, knight, drop)
	_check(before_ground == 0, "No loose shield appears before release")
	renderer._process(maxf(0.0, entry.clip.release_ms - 1.0) / 1000.0)
	renderer.set_process(false)
	var before_release := await _render_view(renderer, view, cells, knight, {})
	_check(_difference(before_release, hold) > 30, "Shield Throw visibly plays the held-shield wind-up")
	renderer._process((entry.clip.release_ms - entry.elapsed_ms + 1.0) / 1000.0)
	renderer.set_process(false)
	_check(entry.gift_from is Vector2 and entry.gift_to is Vector2,
		"Released shield has a rendered flight from hand to drop")
	if entry.gift_to is Vector2:
		var tile := Rect2(renderer.call("_tile_origin", drop), Vector2(preload("res://bridge_art.gd").TILE))
		_check(tile.has_point(entry.gift_to), "Flying shield arrives within the actual shield-drop tile")
	var during_ground := await _ground_comparison(renderer, view, cells, knight, drop)
	_check(during_ground == 0, "No duplicate loose shield appears during flight")
	renderer._process(preload("res://presentation/cast_playback.gd").GIFT_FLIGHT_MS / 2000.0)
	renderer.set_process(false)
	var in_flight := await _render_view(renderer, view, cells, knight, {})
	var flight_origin: Variant = entry.gift_from
	entry.gift_from = null
	var no_flight := await _render_view(renderer, view, cells, knight, {})
	entry.gift_from = flight_origin
	_check(_difference(in_flight, no_flight) > 10, "Detached shield is visibly in flight")
	renderer._process(preload("res://presentation/cast_playback.gd").GIFT_FLIGHT_MS / 2000.0)
	renderer.set_process(false)
	var landed_ground := await _ground_comparison(renderer, view, cells, knight, drop)
	_check(landed_ground > 10, "Shield appears on its actual drop tile after landing")
	renderer._process((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
	renderer.set_process(false)
	_check(renderer.action_playback_snapshot().is_empty(), "Shield Throw finishes")
	var away := await _render_view(renderer, view, cells, knight, {})
	var held := knight.duplicate(true)
	held.shield_away = false
	var recovered := await _render_view(renderer, view, cells, held, {})
	_check(_difference(away, recovered) > 30, "Equipment hold stays shield-free until retrieval restores the shield")
	await _retrieved_during_throw(renderer, view, cells, knight, cue)
	container.queue_free()


func _retrieved_during_throw(renderer: Control, view: SubViewport, cells: Dictionary,
		away: Dictionary, cue: Dictionary) -> void:
	var held := away.duplicate(true)
	held.shield_away = false
	# Establish the rendered wind-up and mid-flight appearance from the
	# ordinary still-away throw, including the actor and detached shield.
	renderer.clear_action_playback()
	await _render_view(renderer, view, cells, away, {})
	renderer.play_committed_actions([cue])
	renderer.set_process(false)
	var reference_entries: Array = renderer.get("_playback").active()
	if reference_entries.size() != 1:
		_check(false, "Retrieved throw reference starts")
		return
	var reference = reference_entries[0]
	var windup_ms: float = reference.clip.release_ms * 0.5
	var flight_ms: float = reference.clip.release_ms \
		+ preload("res://presentation/cast_playback.gd").GIFT_FLIGHT_MS * 0.5
	renderer._process(windup_ms / 1000.0)
	renderer.set_process(false)
	var reference_windup := await _render_view(renderer, view, cells, away, {})
	renderer._process((flight_ms - windup_ms) / 1000.0)
	renderer.set_process(false)
	var reference_flight := await _render_view(renderer, view, cells, away, {})
	renderer.clear_action_playback()
	renderer.set("_ready_ms", 0.0)
	var expected_held := await _render_view(renderer, view, cells, held, {})

	for same_round in [true, false]:
		var label := "same-round pickup" if same_round else "rapid next-commit pickup"
		renderer.clear_action_playback()
		await _render_view(renderer, view, cells, held if same_round else away, {})
		var actual_cue := cue.duplicate(true)
		if same_round:
			actual_cue["shield_away"] = false
		renderer.play_committed_actions([actual_cue])
		renderer.set_process(false)
		var entries: Array = renderer.get("_playback").active()
		if entries.size() != 1:
			_check(false, label + " keeps the committed throw queued")
			continue
		var entry = entries[0]
		if not same_round:
			renderer._process(windup_ms / 2000.0)
			renderer.set_process(false)
			await _render_view(renderer, view, cells, held, {})
		renderer._process((windup_ms - entry.elapsed_ms) / 1000.0)
		renderer.set_process(false)
		var windup := await _render_view(renderer, view, cells, held, {})
		_check(_difference(windup, reference_windup) == 0,
			label + " preserves the committed held-shield wind-up")
		renderer._process((flight_ms - entry.elapsed_ms) / 1000.0)
		renderer.set_process(false)
		var flight := await _render_view(renderer, view, cells, held, {})
		_check(_difference(flight, reference_flight) == 0,
			label + " renders the empty-hand follow-through and one flying shield")
		renderer._process((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
		renderer.set_process(false)
		renderer.set("_ready_ms", 0.0)
		var returned := await _render_view(renderer, view, cells, held, {})
		_check(renderer.action_playback_snapshot().is_empty() and _difference(returned, expected_held) == 0,
			label + " restores the held shield without a stale ground marker")


func _ground_comparison(renderer: Control, view: SubViewport, cells: Dictionary, knight: Dictionary, drop: Vector2i) -> int:
	var marked := await _render_view(renderer, view, cells, knight, {"shields": [drop]})
	var plain := await _render_view(renderer, view, cells, knight, {})
	return _difference(marked, plain)


func _render_view(renderer: Control, view: SubViewport, cells: Dictionary, knight: Dictionary, overlay: Dictionary) -> Image:
	renderer.set_render_state(cells, [knight], overlay)
	renderer.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _difference(first: Image, second: Image) -> int:
	var changed := 0
	for y in first.get_height():
		for x in first.get_width():
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				changed += 1
	return changed
