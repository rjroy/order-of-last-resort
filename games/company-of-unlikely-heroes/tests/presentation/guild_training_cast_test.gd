extends "res://tests/guild/guild_full_catalog_test.gd"
## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/guild_training_cast_test.gd

const CastCues = preload("res://presentation/cast/cast_cues.gd")
const CASES := [
	["knight", "knight_rescue_line", "patient", "rescue_line"],
	["wizard", "wizard_ring_sparks", "", "ring_sparks"],
	["rogue", "rogue_tripwire", "", "tripwire"],
	["necromancer", "necro_grave_bell", "", "grave_bell"],
	["alchemist", "alchemist_etching_paste", "enemy", "etching_paste"],
]
var board: Control


func _initialize() -> void:
	call_deferred("_run_cast_test")


func _run_cast_test() -> void:
	defs = Catalog.read_default()
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	var profile := _profile()
	for id in ["recruit_rogue", "recruit_necromancer", "recruit_alchemist",
			"knight_rescue_line", "wizard_ring_sparks", "rogue_tripwire",
			"necro_grave_bell", "alchemist_etching_paste",
			"rogue_tripwire_order", "necro_bell_order"]:
		profile = Progression.purchased_profile(defs, profile, id)
		if profile.has("error"):
			_check(false, "Fixture purchases " + id + ": " + str(profile))
			_finish_cast_test()
			return
	for example in CASES:
		await _exercise(profile, example, "")
	await _exercise(profile, CASES[2], "rogue_tripwire_order")
	await _exercise(profile, CASES[3], "necro_bell_order")
	_repeat_recipe(profile, "alchemist_etching_paste", "etching_paste", false)
	_repeat_recipe(profile, "alchemist_acid", "acid", true)
	_finish_cast_test()


func _exercise(profile: Dictionary, example: Array, order_petition: String) -> void:
	var hero: String = example[0]
	var ability: String = example[1]
	var expected_clip: String = example[3]
	var label := ability + (" standing order" if not order_petition.is_empty() else " manual")
	var loadout := _action_loadout(profile, hero, ability)
	if not order_petition.is_empty():
		loadout.order_id = defs.guild_progression.petitions[order_petition].grant.order_id
	var state := _battle(profile, hero, loadout)
	if state.is_empty():
		_check(false, label + " deploys with the purchased kit")
		return
	# Both targeted and automatic actions must face left toward their actual
	# effect, not the default right-facing actor. Sweep has targets on both sides.
	_unit_at(state, "enemy").position = Vector2i(2, 3)
	if hero == "knight":
		_unit_at(state, "enemy").position = Vector2i(4, 3)
		_unit_at(state, "patient").position = Vector2i(1, 3)
	if hero == "wizard":
		state.units.append(_unit("enemy_right", "harpooner", Vector2i(4, 3), 20))
	if not order_petition.is_empty():
		state = rules.set_order(state, hero, loadout.order_id)
	var scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.call("_show_battle", state.duplicate(true))
	await process_frame
	board = scene.find_child("BridgeBoard", true, false)
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var staged: bool
	if order_petition.is_empty():
		staged = await driver.command(hero, ability, example[2])
	else:
		staged = await driver.order(hero, loadout.order_id)
	if not staged:
		_check(false, label + " stages in battle: " + driver.error)
		scene.queue_free()
		await process_frame
		return
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, hero, ability, example[2]) \
		if order_petition.is_empty() else rules.preview_round(state)
	_check(scene.battle_snapshot() == before and board.action_playback_snapshot().is_empty(),
		label + " preview is silent and uncommitted")
	var forecast: Dictionary = scene.get("_plan").duplicate(true)
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit == null or commit.disabled:
		_check(false, label + " can commit its forecast")
	else:
		commit.pressed.emit()
		await process_frame
		_check(scene.battle_snapshot() == forecast.get("result"), label + " commits its forecast")
		_check(board.action_playback_snapshot().any(func(cue): return cue.get("unit_id") == hero \
			and cue.get("cast_key") == hero and cue.get("clip") == expected_clip),
			label + " queues the performer's " + expected_clip + " scene action")
	scene.queue_free()
	await process_frame
	# Continue with an isolated board so unrelated actors' queued performances
	# cannot obscure the performer, facing, projectile, or return-to-ready checks.
	board = preload("res://presentation/battle/bridge_art.gd").new()
	root.add_child(board)
	board.set_render_state({Vector2i(3, 3): "stone"}, [
		{"id": hero, "art_key": hero, "cast_key": hero, "cell": Vector2i(3, 3), "facing": 1}])
	if not plan.get("valid", false):
		_check(false, label + " fixture resolves")
		return
	var after: Dictionary = rules.apply_plan(state, plan) if order_petition.is_empty() \
		else rules.commit_round(state, plan)
	var cues: Array = CastCues.build(state, after, plan.events)
	var matches := cues.filter(func(cue): return cue.get("unit_id") == hero and cue.get("cast_key") == hero)
	if matches.size() != 1:
		_check(false, label + " produces one committed cue for the actual performer: " + str(cues))
		return
	var cue: Dictionary = matches[0]
	_check(cue.get("clip") == expected_clip, label + " resolves the " + expected_clip + " clip")
	var expected_target := "patient" if hero == "knight" else "enemy"
	if hero == "wizard":
		for id in ["enemy", "enemy_right"]:
			_check(cue.get("recipients", []).any(func(recipient): return recipient.get("id") == id),
				label + " includes sweep recipient " + id)
	else:
		_check(cue.get("target_id") == expected_target or cue.get("recipients", []).any(
			func(recipient): return recipient.get("id") == expected_target),
			label + " identifies its affected target")
		_check(cue.get("target_cell") == _unit_at(state, expected_target).position,
			label + " retains the effect's action-time target cell")
	board.play_committed_actions([cue])
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.size() != 1:
		_check(false, label + " plays a packaged action clip rather than remaining idle")
		return
	var entry = active[0]
	if hero != "wizard":
		_check(entry.facing == -1.0, label + " faces its left-hand effect target")
	if hero == "alchemist":
		_check(entry.gift == null, label + " does not launch an acid flask")
	board._process((entry.duration_ms + 1.0) / 1000.0)
	_check(board.action_playback_snapshot().is_empty(), label + " completes and returns to ready")
	var ready = board.get("_cast").clip_for(hero, "ready")
	_check(ready != null and ready in board.get("_ready_clips") and board.is_processing(),
		label + " resumes its live ready animation")


func _repeat_recipe(profile: Dictionary, recipe: String, clip: String, throws: bool) -> void:
	var loadout: Dictionary = _action_loadout(profile, "alchemist", recipe) \
		if recipe == "alchemist_etching_paste" else Progression.default_loadout(defs, profile, "alchemist")
	var state := _battle(profile, "alchemist", loadout)
	if state.is_empty():
		_check(false, recipe + " culture fixture deploys")
		return
	_unit_at(state, "alchemist").upgrades = {"alchemist_keep_the_culture": 1}
	state.units.append(_unit("enemy_b", "harpooner", Vector2i(3, 4), 20))
	var initial: Dictionary = rules.preview(state, "alchemist", recipe, "enemy")
	if not initial.get("valid", false):
		_check(false, recipe + " can be bottled")
		return
	state = rules.apply_plan(state, initial)
	_check(_unit_at(state, "alchemist").get("bottled_reaction", {}).get("recipe") == recipe,
		recipe + " stores its exact recipe")
	var plan: Dictionary = rules.preview(state, "alchemist", "alchemist_repeat_batch", "enemy_b")
	if not plan.get("valid", false):
		_check(false, recipe + " Repeat Batch resolves against another target")
		return
	var cues: Array = CastCues.build(state, rules.apply_plan(state, plan), plan.events)
	var matches := cues.filter(func(cue): return cue.get("unit_id") == "alchemist" \
		and cue.get("cast_key") == "alchemist" and cue.get("clip") == clip)
	if matches.size() != 1:
		_check(false, recipe + " Repeat Batch uses the " + clip + " performance")
		return
	var cue: Dictionary = matches[0]
	_check(cue.get("target_id") == "enemy_b" and cue.get("target_cell") == Vector2i(3, 4),
		recipe + " Repeat Batch targets the actual second recipient")
	var isolated := preload("res://presentation/battle/bridge_art.gd").new()
	root.add_child(isolated)
	isolated.set_render_state({Vector2i(3, 3): "stone", Vector2i(3, 4): "stone"}, [
		{"id": "alchemist", "art_key": "healer", "cast_key": "alchemist", "cell": Vector2i(3, 3)}])
	isolated.play_committed_actions([cue])
	isolated.set_process(false)
	var active: Array = isolated.get("_playback").active()
	if active.size() != 1:
		_check(false, recipe + " Repeat Batch plays its packaged clip")
	else:
		var entry = active[0]
		_check((entry.gift != null) == throws, recipe + (" throws a flask" if throws else " has no flying flask"))
		if not throws:
			_check(is_equal_approx(entry.impact_ms, entry.clip.time_at_source_frame(13)),
				"Repeated Paste applies feedback at the contact frame")
	isolated.queue_free()


func _finish_cast_test() -> void:
	if failures.is_empty():
		print("PASS: purchased guild training cast performances")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
