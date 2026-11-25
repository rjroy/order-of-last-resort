extends "res://tests/journeys/commission_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/practice_scene_test.gd
# The practice lesson uses normal battle controls, not calls to lesson handlers.
# Contract: change Wizard to Blast, command a legal Wizard Move, inspect Forecast,
# commit, inspect the restored Blast forecast, and commit the next round.

func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _launch_normal()
	var input := _node("GuildName") as LineEdit
	if input == null:
		_check(false, "Fresh profile opens guild creation")
		_cleanup()
		return
	input.text = GUILD_NAME
	input.text_changed.emit(input.text)
	await _press("CreateGuild")
	if scene.current_screen() != "battle":
		_check(false, "Founding a stock guild automatically starts practice")
		_cleanup()
		return
	var store = load("res://guild/guild_profile.gd")
	var profile: Dictionary = store.load_profile(profile_path).duplicate(true)
	var opening: Dictionary = scene.battle_snapshot().duplicate(true)
	_check(opening.get("party") == ["knight", "healer", "wizard"],
		"Practice deploys the fixed founders")
	_check(opening.get("orders", {}).get("wizard") == "order_cautious",
		"Practice starts with the Wizard's starter order")
	await _premature_commit(opening, "Before changing an order")
	# Quitting in practice must not enroll the already-created profile again.
	await _launch_normal()
	_check(scene.current_screen() == "commissions", "Relaunch during practice opens the board")
	_check(store.load_profile(profile_path) == profile, "Relaunch leaves guild progress unchanged")
	if scene.current_screen() != "commissions":
		_cleanup()
		return
	# An established guild may prefer a different starting order. Practice
	# must ignore that preference without overwriting it.
	var defs: Dictionary = scene.get("_definitions")
	var preference: Dictionary = store.default_loadout(defs, profile, "wizard")
	preference["order_id"] = "order_blast"
	var saved: Dictionary = store.save_loadouts(profile_path, profile, defs, {"wizard": preference})
	_check(not saved.has("error") and saved.get("preferred_loadouts", {}).get("wizard") == preference,
		"Test establishes a distinct valid preferred Wizard loadout")
	if saved.has("error"):
		_cleanup()
		return
	profile = saved.duplicate(true)
	await _launch_normal()
	_check(scene.current_screen() == "commissions", "Existing guild is not auto-enrolled")
	await _press("ReplayPractice")
	if scene.current_screen() != "battle":
		_check(false, "Board can replay practice")
		_cleanup()
		return
	_check(scene.battle_snapshot() == opening, "Replay uses the same fixed founders and starter kit")
	await _press("SkipPractice")
	_check(scene.current_screen() == "commissions", "Skip returns directly to the board")
	_check(store.load_profile(profile_path) == profile,
		"Skip pays nothing and preserves wounds, unlocks, loadouts and board seed")
	if scene.current_screen() != "commissions":
		_cleanup()
		return
	await _press("ReplayPractice")
	if scene.current_screen() == "battle":
		await _walkthrough()
	else:
		_check(false, "Practice can be replayed after Skip")
	_check(scene.current_screen() == "commissions", "Completing practice returns to the board")
	_check(store.load_profile(profile_path) == profile,
		"Completing practice does not change any persisted guild progress")
	if scene.current_screen() == "commissions":
		await _press("Commission_0")
		_check(scene.current_screen() == "guild", "A real commission remains selectable after practice")
		var replay := _node("ReplayPractice") as BaseButton
		_check(replay == null or not replay.is_visible_in_tree() or replay.disabled,
			"Replay cannot replace a live commission from recruitment")
	_cleanup()


func _premature_commit(before: Dictionary, context: String) -> void:
	var commit := _node("Commit") as BaseButton
	if commit != null and commit.is_visible_in_tree() and not commit.disabled:
		commit.pressed.emit()
		await process_frame
	_check(scene.current_screen() == "battle" and scene.battle_snapshot() == before,
		context + ": committing cannot advance the lesson")
	var skip := _node("SkipPractice") as BaseButton
	_check(skip != null and skip.is_visible_in_tree() and not skip.disabled,
		context + ": Skip remains available")


func _walkthrough() -> void:
	var start: Dictionary = scene.battle_snapshot().duplicate(true)
	var player = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await player.order("wizard", "order_blast"):
		_check(false, "Wizard can change standing order through the actual control: " + player.error)
		return
	var ordered: Dictionary = scene.battle_snapshot().duplicate(true)
	_check(ordered.get("orders", {}).get("wizard") == "order_blast",
		"Changing the order updates the battle")
	await _premature_commit(ordered, "Before issuing the direct command")
	var rules = player.rules
	var targets: Array = rules.targets(rules.state_before_action(ordered, "wizard"), "wizard", "move")
	if targets.is_empty():
		_check(false, "Practice gives Wizard a legal opening Move")
		return
	var target: Dictionary = targets[0]
	if not await player.command("wizard", "move", str(target.id)):
		_check(false, "Wizard can stage a legal Move through battle controls: " + player.error)
		return
	var planned: Dictionary = scene.get("_planned_state").duplicate(true)
	var forecast: Dictionary = scene.get("_plan").duplicate(true)
	_check(scene.battle_snapshot() == ordered and forecast.get("valid", false),
		"Direct Move creates a forecast without committing")
	_check(planned.get("orders", {}).get("wizard") == "order_blast"
		and planned.get("overrides", {}).get("wizard", {}).get("ability_id") == "move",
		"Move temporarily overrides rather than replacing Blast")
	_check(_event(forecast, "heal", "healer", true), "Forecast shows Healer restoring actual HP")
	_check(_event(forecast, "aura", "knight") and _event(forecast, "reflect"),
		"Forecast shows Knight's protection affecting a real attack")
	await _premature_commit(ordered, "Before opening the forecast")
	await _press("ForecastDetails")
	var lesson_text := _visible_text().to_lower()
	_check("healer" in lesson_text and "knight" in lesson_text,
		"Lesson or forecast identifies both other founders' contributions")
	await _press("Commit")
	var second: Dictionary = scene.battle_snapshot().duplicate(true)
	_check(second.get("round", 0) > start.get("round", 0),
		"Commit advances the real round")
	_check(second.get("orders", {}).get("wizard") == "order_blast"
		and second.get("overrides", {}).is_empty(),
		"One-round command clears and Blast remains the standing order")
	var next: Dictionary = scene.get("_plan").duplicate(true)
	_check(_event(next, "damage", "wizard"),
		"Following round forecasts Wizard's restored Blast hitting a real target")
	await _press("ForecastDetails")
	var return_text := _visible_text().to_lower()
	_check("blast" in return_text and "round" in return_text,
		"Lesson explains the direct command lasts one round and Blast returns")
	await _press("Commit")
	var continue_button := _node("ContinuePractice") as BaseButton
	if continue_button != null and continue_button.is_visible_in_tree() and not continue_button.disabled:
		await _press("ContinuePractice")


func _event(plan: Dictionary, kind: String, actor := "", positive := false) -> bool:
	for event: Dictionary in plan.get("events", []):
		if event.get("type") == kind \
				and (actor.is_empty() or event.get("unit_id") == actor or event.get("source_id") == actor) \
				and (not positive or event.get("amount", 0) > 0):
			return true
	return false
