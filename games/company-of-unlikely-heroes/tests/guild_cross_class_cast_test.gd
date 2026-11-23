extends "res://tests/guild_full_catalog_test.gd"
## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_cross_class_cast_test.gd

const CastCues = preload("res://presentation/cast_cues.gd")
const RulesBoard = preload("res://rules/board.gd")
# Learner, purchased petition, manual target, learner-owned performance.
const CASES := [
	["knight", "knight_learn_bonk", "enemy", "bonk"],
	["healer", "teach_healer_blast", "", "blast"],
	["wizard", "wizard_learn_dodge", "", "dodge"],
	["bard", "bard_learn_push", "enemy", "push"],
	["rogue", "rogue_learn_potion", "patient", "potion"],
	["necromancer", "necro_learn_melody", "", "melody"],
	["alchemist", "alchemist_learn_pull", "enemy", "pull"],
]


func _initialize() -> void:
	call_deferred("_run_cross_class")


func _run_cross_class() -> void:
	defs = Catalog.read_default()
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	var profile := _profile()
	for id in ["recruit_bard", "recruit_rogue", "recruit_necromancer", "recruit_alchemist",
			"knight_learn_bonk", "teach_healer_blast", "healer_blast_order",
			"wizard_learn_dodge", "bard_learn_push", "rogue_learn_potion",
			"necro_learn_melody", "alchemist_learn_pull"]:
		profile = Progression.purchased_profile(defs, profile, id)
		if profile.has("error"):
			_check(false, "Fixture purchases " + id + ": " + str(profile))
			_finish_cross_class()
			return
	for example in CASES:
		await _exercise_cross_class(profile, example, false)
	await _exercise_cross_class(profile, CASES[1], true)
	_bard_collision(profile)
	_pull_resisted(profile)
	_finish_cross_class()


func _exercise_cross_class(profile: Dictionary, example: Array, standing: bool) -> void:
	var hero: String = example[0]
	var petition: String = example[1]
	var ability: String = defs.guild_progression.petitions[petition].grant.ability_id
	var clip: String = example[3]
	var label := petition + (" standing order" if standing else " manual")
	var loadout := _action_loadout(profile, hero, petition)
	if standing:
		loadout.order_id = defs.guild_progression.petitions.healer_blast_order.grant.order_id
	var state := _battle(profile, hero, loadout)
	if state.is_empty():
		_check(false, label + " deploys with the purchased ability equipped")
		return
	# All resolved targets are left of the learner, including the dodge's ally.
	_unit_at(state, "enemy").position = Vector2i(2, 3)
	_unit_at(state, "patient").position = Vector2i(1, 3) if hero == "wizard" else Vector2i(3, 5)
	if hero == "wizard":
		_unit_at(state, "civilian").position = Vector2i(3, 4)
		var origin: Vector2i = _unit_at(state, hero).position
		var patient_distance: int = RulesBoard.distance(origin, _unit_at(state, "patient").position)
		for unit in state.units:
			if unit.id != hero and unit.id != "patient":
				_check(unit.position != origin and unit.position != _unit_at(state, "patient").position \
					and RulesBoard.distance(origin, unit.position) < patient_distance,
					label + " fixture keeps the patient uniquely farthest")
	if hero == "rogue":
		_unit_at(state, "patient").position = Vector2i(2, 3)
		_unit_at(state, "enemy").position = Vector2i(4, 3)
	if hero == "alchemist":
		_unit_at(state, "enemy").position = Vector2i(1, 3)
	if standing:
		state = rules.set_order(state, hero, loadout.order_id)
	var scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.call("_show_battle", state.duplicate(true))
	await process_frame
	var board: Node = scene.find_child("BridgeBoard", true, false)
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var staged: bool = await driver.order(hero, loadout.order_id) if standing \
		else await driver.command(hero, ability, example[2])
	if not staged:
		_check(false, label + " stages in battle: " + driver.error)
		scene.queue_free()
		await process_frame
		return
	_check(scene.battle_snapshot() == state and board.action_playback_snapshot().is_empty(),
		label + " preview is silent and uncommitted")
	var forecast: Dictionary = scene.get("_plan").duplicate(true)
	var button := scene.find_child("Commit", true, false) as BaseButton
	if button == null or button.disabled:
		_check(false, label + " can commit")
	else:
		button.pressed.emit()
		await process_frame
		_check(scene.battle_snapshot() == forecast.get("result"), label + " commits its forecast")
		_check(board.action_playback_snapshot().any(func(cue): return cue.get("unit_id") == hero \
			and cue.get("cast_key") == hero and cue.get("clip") == clip),
			label + " queues the learner's " + clip + " scene performance")
	scene.queue_free()
	await process_frame

	var plan: Dictionary = rules.preview_round(state) if standing else rules.preview(state, hero, ability, example[2])
	if not plan.get("valid", false):
		_check(false, label + " resolves")
		return
	var after: Dictionary = rules.commit_round(state, plan) if standing else rules.apply_plan(state, plan)
	if hero == "alchemist":
		_check(_unit_at(after, hero).hp < _unit_at(state, hero).hp \
			and rules.knocked_down(after, hero), label + " retains real Pull recoil and knockdown")
	var cues: Array = CastCues.build(state, after, plan.events)
	var matches := cues.filter(func(cue): return cue.get("unit_id") == hero and cue.get("cast_key") == hero)
	if matches.size() != 1:
		_check(false, label + " resolves one performance on the learner: " + str(cues))
		return
	var cue: Dictionary = matches[0]
	_check(cue.get("clip") == clip, label + " resolves the learner's " + clip + " gesture")
	var target := "patient" if hero in ["wizard", "rogue"] else "enemy"
	var target_cell: Vector2i = _unit_at(state, target).position
	_check(cue.get("target_id") == target and cue.get("target_cell") == target_cell,
		label + " aims at the actual action-time recipient")
	_check(cue.get("recipients", []).any(func(item): return item.get("id") == target),
		label + " attaches feedback to the actual recipient")
	_check(not cues.any(func(item): return item.get("unit_id") == hero and item.get("cast_key") != hero),
		label + " never paints the donor as performer")
	var isolated := preload("res://bridge_art.gd").new()
	root.add_child(isolated)
	isolated.set_render_state({Vector2i(3, 3): "stone"}, [
		{"id": hero, "art_key": hero, "cast_key": hero, "cell": Vector2i(3, 3), "facing": 1}])
	isolated.play_committed_actions([cue])
	isolated.set_process(false)
	var active: Array = isolated.get("_playback").active()
	if active.size() != 1:
		_check(false, label + " plays the learner's packaged clip")
	else:
		var entry = active[0]
		_check(entry.facing == -1.0, label + " faces the resolved recipient")
		_check(entry.gift == null, label + " does not borrow a donor projectile")
		isolated._process((entry.duration_ms + 1.0) / 1000.0)
		_check(isolated.action_playback_snapshot().is_empty(), label + " completes its gesture")
		if hero != "alchemist":
			var ready = isolated.get("_cast").clip_for(hero, "ready")
			_check(ready != null and ready in isolated.get("_ready_clips") and isolated.is_processing(),
				label + " resumes the learner's live ready animation")
	isolated.queue_free()


func _bard_collision(profile: Dictionary) -> void:
	var state := _battle(profile, "bard", _action_loadout(profile, "bard", "bard_learn_push"))
	_unit_at(state, "enemy").position = Vector2i(2, 3)
	state.obstacles = [{"id": "wall", "object_id": "crate", "statuses": {},
		"position": Vector2i(1, 3), "hp": 10, "max_hp": 10}]
	var plan: Dictionary = rules.preview(state, "bard", "knight_push", "enemy")
	if not plan.get("valid", false):
		_check(false, "Bard collision fixture resolves")
		return
	var after: Dictionary = rules.apply_plan(state, plan)
	_check(_unit_at(after, "enemy").hp < _unit_at(state, "enemy").hp \
		and _unit_at(after, "enemy").position == Vector2i(2, 3),
		"Blocked Bard Push actually deals collision damage without moving its target")
	var cues: Array = CastCues.build(state, after, plan.events)
	var pushes := cues.filter(func(cue): return cue.get("unit_id") == "bard" and cue.get("clip") == "push")
	if pushes.size() != 1:
		_check(false, "Bard collision produces one push performance")
		return
	var cue: Dictionary = pushes[0]
	_check(cue.get("target_id") == "enemy" and cue.get("target_cell") == Vector2i(2, 3),
		"Bard collision aims at the actual damaged target")
	_check(cue.get("recipients", []).any(func(item): return item.get("id") == "enemy" \
		and item.get("cell") == Vector2i(2, 3) and item.get("kind") == "hit"),
		"Bard collision attaches hit feedback to the damaged target")
	var board := preload("res://bridge_art.gd").new()
	root.add_child(board)
	board.set_render_state({Vector2i(3, 3): "stone"}, [
		{"id": "bard", "art_key": "bard", "cast_key": "bard", "cell": Vector2i(3, 3), "facing": 1}])
	board.play_committed_actions([cue])
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	_check(active.size() == 1 and active[0].facing == -1.0,
		"Bard collision faces left toward the actual target")
	board.queue_free()


func _pull_resisted(profile: Dictionary) -> void:
	for reaction in ["target_cork", "actor_cork", "stiff_upper_lip", "normal"]:
		var state := _battle(profile, "alchemist", _action_loadout(profile, "alchemist", "alchemist_learn_pull"))
		_unit_at(state, "enemy").position = Vector2i(1, 3)
		if reaction.ends_with("cork"):
			var recipient := "enemy" if reaction == "target_cork" else "alchemist"
			_unit_at(state, recipient)["alchemy_statuses"] = {"cork_soles": {"source_id": recipient}}
		elif reaction == "stiff_upper_lip":
			_unit_at(state, "alchemist")["alchemy_statuses"] = {"stiff_upper_lip": {"source_id": "alchemist"}}
		var plan: Dictionary = rules.preview(state, "alchemist", "wizard_pull", "enemy")
		if not plan.get("valid", false):
			_check(false, reaction + " Pull fixture resolves")
			continue
		var after: Dictionary = rules.apply_plan(state, plan)
		var down: bool = rules.knocked_down(after, "alchemist")
		_check(down == (reaction == "normal"), reaction + " has the expected actual knockdown state")
		if reaction.ends_with("cork"):
			var resisting := "enemy" if reaction == "target_cork" else "alchemist"
			_check(_unit_at(after, "alchemist").position == _unit_at(state, "alchemist").position \
				and _unit_at(after, "enemy").position == _unit_at(state, "enemy").position \
				and _unit_at(after, "alchemist").hp == _unit_at(state, "alchemist").hp \
				and _unit_at(after, "enemy").hp == _unit_at(state, "enemy").hp \
				and not _unit_at(after, resisting).get("alchemy_statuses", {}).has("cork_soles"),
				reaction + " consumes only the resisting status without movement or damage")
			_check(plan.events.any(func(event): return event.get("reaction_id") == "cork_soles" \
				and event.get("unit_id") == resisting and event.get("resisted_target_id") == "enemy"),
				reaction + " retains resistance owner and intended target in the diagnostic event")
		elif reaction == "stiff_upper_lip":
			_check(_unit_at(after, "alchemist").position != _unit_at(state, "alchemist").position \
				and _unit_at(after, "enemy").position != _unit_at(state, "enemy").position \
				and _unit_at(after, "alchemist").hp < _unit_at(state, "alchemist").hp \
				and not _unit_at(after, "alchemist").get("alchemy_statuses", {}).has("stiff_upper_lip"),
				"Stiff Upper Lip consumes resistance but preserves Pull displacement and recoil damage")
		var cues: Array = CastCues.build(state, after, plan.events)
		var pulls := cues.filter(func(cue): return cue.get("unit_id") == "alchemist" \
			and cue.get("cast_key") == "alchemist")
		if pulls.size() != 1:
			_check(false, reaction + " produces one Mixologist performance")
			continue
		var cue: Dictionary = pulls[0]
		_check(cue.get("clip") == ("pull" if down else "pull_upright"),
			reaction + " selects fall only for actual recoil knockdown")
		if reaction == "actor_cork":
			_check(cue.get("target_id") == "enemy" and cue.get("target_cell") == Vector2i(1, 3),
				"Caster Cork Soles keeps the actual intended Pull target rather than aiming at the caster")
		var board := preload("res://bridge_art.gd").new()
		root.add_child(board)
		board.set_render_state({Vector2i(3, 3): "stone"}, [
			{"id": "alchemist", "art_key": "healer", "cast_key": "alchemist",
				"cell": Vector2i(3, 3), "prone": down}])
		board.play_committed_actions([cue])
		board.set_process(false)
		var active: Array = board.get("_playback").active()
		if active.size() != 1:
			_check(false, reaction + " plays its packaged performance")
		elif not down:
			var entry = active[0]
			if reaction == "actor_cork":
				_check(entry.facing == -1.0, "Caster Cork Soles faces the intended left-hand target")
			_check(entry.clip.source_frames == [1, 5, 9, 13, 16, 13, 5, 1],
				reaction + " plays the approved upright pull and recovery frames")
			var source = board.get("_cast").clip_for("alchemist", "pull")
			for index in entry.clip.frames.size():
				var source_index: int = source.source_frames.find(entry.clip.source_frames[index])
				_check(source_index >= 0 and entry.clip.frames[index] == source.frames[source_index],
					reaction + " reuses the approved upright atlas drawing")
			_check(is_equal_approx(entry.clip.total_ms, 1010.0) \
				and entry.clip.frame_ends == [167.0, 333.0, 500.0, 625.0, 715.0, 800.0, 910.0, 1010.0] \
				and is_equal_approx(entry.impact_ms, 500.0) and entry.gift == null,
				reaction + " preserves impact timing without a projectile or fall")
		board.queue_free()


func _finish_cross_class() -> void:
	if failures.is_empty():
		print("PASS: purchased cross-class performances")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
