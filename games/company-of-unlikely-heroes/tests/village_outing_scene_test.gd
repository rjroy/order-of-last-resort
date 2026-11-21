extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/village_outing_scene_test.gd
# In a graphical session, -- --capture-dir=/absolute/directory saves opening and preview boards.
# The policy uses only the scene's normal command editor and its round forecast.
const MISSIONS := ["goblin_mob", "harpoon_squad", "unwelcome_guest"]
const PARTY := ["healer", "knight", "bard"]
const MAX_ROUNDS := 30
const VIEWPORT_SIZE := Vector2i(1280, 820)
var failures: Array[String] = []
var scene: Node
var direct_openings: Dictionary = {}
var played_rounds := 0
var viewport := SubViewport.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	# Keep the complete native-resolution fixture inside small desktop windows.
	# Captures come directly from the unscaled SubViewport texture.
	container.scale = Vector2(0.5, 0.5)
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	for id in MISSIONS:
		await _launch(PackedStringArray(["--mission=" + id]))
		_check(scene.current_screen() == "battle", id + " launches directly into battle")
		if scene.current_screen() == "battle":
			var opening: Dictionary = scene.battle_snapshot()
			_check(opening.get("mission_id") == id, id + " launches the requested mission")
			_check(opening.get("party", []).size() == 3, id + " has an authored three-hero party")
			direct_openings[id] = opening
			await _capture(id + "_direct")
	await _launch(PackedStringArray(["--fixed-outings"]))
	_check(scene.current_screen() == "guild", "Fixed outings launch opens the guild")
	var selector := _node("AdventureSelect") as OptionButton
	if selector == null:
		_check(false, "Guild exposes AdventureSelect")
		_finish()
		return
	_check(_has_id(selector, "first_outing"), "Original outing remains selectable")
	await _select_id(selector, "first_outing")
	selector = _node("AdventureSelect") as OptionButton
	if not await _select_id(selector, "village_troubles"):
		_finish()
		return
	for id in ["knight", "healer", "bard"]:
		await _press("Recruit_" + id)
	await _press("PartyEarlier_healer")
	_check(scene.selected_recruits() == PARTY, "Guild can select and order three heroes")
	await _press("StartAdventure")
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 12345
	var outing: Dictionary = scene.get("_run")
	outing.reward_rng_state = reward_rng.state
	var preserved_orders: Dictionary = {}
	for mission_index in MISSIONS.size():
		var id: String = MISSIONS[mission_index]
		if scene.current_screen() != "battle":
			_check(false, "Expected battle for " + id + ", got " + scene.current_screen())
			break
		var opening: Dictionary = scene.battle_snapshot()
		_check(opening.get("mission_id") == id, "Outing deploys " + id + " in order")
		_check(opening.get("party") == PARTY, id + " retains the chosen deployment order")
		if mission_index == 0:
			for actor in PARTY:
				preserved_orders[actor] = opening.get("orders", {}).get(actor)
		else:
			for actor in PARTY:
				_check(opening.get("orders", {}).get(actor) == preserved_orders.get(actor),
					id + " preserves " + actor + "'s standing order")
		_check_battle_controls(id)
		if direct_openings.has(id):
			_check(_geometry(opening) == _geometry(direct_openings[id]),
				id + " uses the same board and encounter geometry as direct launch")
		await _capture(id + "_outing")
		await _play_battle(id)
		print("%s: %d committed round(s), screen=%s" % [id, played_rounds, scene.current_screen()])
		var expected := "result" if mission_index == MISSIONS.size() - 1 else "debrief"
		if scene.current_screen() != expected:
			_check(false, id + " must reach " + expected + " after victory; got " + scene.current_screen())
			break
		if expected == "debrief":
			_check(_node("CarryReport") != null, id + " displays carry report")
			await process_frame
			_check(scene.current_screen() == "debrief", "Debrief waits for continuation")
			var reward := _node("Reward_knight") as BaseButton
			_check(reward != null and reward.is_visible_in_tree(), "Debrief offers Knight a reward")
			if reward != null:
				await _press("Reward_knight")
			await _press("ContinueAdventure")
		else:
			var outcome := _node("RunOutcome")
			_check(outcome != null and outcome.get_meta("outcome", "") == "victory",
				"Completing all three missions reports victory")
			await _press("ReturnToGuild")
			_check(scene.current_screen() == "guild" and scene.selected_recruits().is_empty(),
				"Return to guild resets the company")
			var guild_run: Dictionary = scene.get("_run")
			_check(guild_run.get("upgrades_by_id", {}).is_empty() and guild_run.get("reward_offers", []).is_empty(),
				"Return after victory clears outing rewards")
			var returned := _node("AdventureSelect") as OptionButton
			_check(returned != null and _has_id(returned, "first_outing"),
				"Original outing remains selectable after return")
			if returned != null:
				await _select_id(returned, "first_outing")
	await _test_custom_adventure_bootstrap()
	_finish()


func _test_custom_adventure_bootstrap() -> void:
	var catalog = load("res://content/catalog.gd")
	var data: Dictionary = catalog.read_default().duplicate(true)
	# This legacy custom catalog has no commission board; its roster adventure
	# is deliberately removed below.
	for table in ["mission_reports", "mission_kinds", "commission_settings"]:
		data.erase(table)
	data.adventures.erase("first_outing")
	var errors: PackedStringArray = catalog.validate(data)
	_check(errors.is_empty() and data.adventures.has("village_troubles"),
		"Custom village-only catalog validates: " + str(errors))
	if not errors.is_empty():
		return
	var path := "user://village_only_scene_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write custom catalog fixture")
		return
	file.store_string(JSON.stringify(data))
	file.close()
	var args := PackedStringArray(["--content=" + ProjectSettings.globalize_path(path)])
	await _launch(args)
	_check(scene.current_screen() == "guild", "Custom catalog without first_outing opens the guild")
	if scene.current_screen() == "guild":
		var selector := _node("AdventureSelect") as OptionButton
		_check(selector != null and _has_id(selector, "village_troubles"),
			"Custom guild offers its authored village adventure")
		if selector != null and await _select_id(selector, "village_troubles"):
			for id in PARTY:
				await _press("Recruit_" + id)
			await _press("StartAdventure")
			_check(scene.current_screen() == "battle"
				and scene.battle_snapshot().get("mission_id") == "goblin_mob"
				and scene.battle_snapshot().get("party") == PARTY,
				"Custom guild deploys its selected company into the village adventure")
	data.adventures.clear()
	errors = catalog.validate(data)
	_check(errors.is_empty(), "Zero-adventure standalone catalog validates: " + str(errors))
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Can write zero-adventure catalog fixture")
	else:
		file.store_string(JSON.stringify(data))
		file.close()
		await _launch(args)
		_check(scene.current_screen() == "battle" and scene.battle_snapshot().get("mission_id") == "ferryman",
			"Zero-adventure custom catalog preserves standalone ferryman fallback")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
		"Custom catalog fixture is removed")


func _launch(args: PackedStringArray) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(args)
	viewport.add_child(scene)
	await process_frame
	await process_frame


func _play_battle(id: String) -> void:
	played_rounds = 0
	for round_index in MAX_ROUNDS:
		if scene.current_screen() != "battle":
			return
		var before: Dictionary = scene.battle_snapshot()
		# Preview each legal direct command, and compare it with standing orders.
		# This is bounded and deterministic for the authored encounter seed.
		var best_score := _score(scene.get("_plan").get("result", {}), PARTY)
		var best := {}
		var actor_ids := _choice_ids(_node("ActorSelect") as OptionButton)
		for actor in actor_ids:
			if not await _try_select("ActorSelect", actor):
				continue
			var abilities := _choice_ids(_node("AbilitySelect") as OptionButton)
			for ability in abilities:
				if not await _try_select("AbilitySelect", ability):
					continue
				var targets := _choice_ids(_node("TargetSelect") as OptionButton)
				if targets.is_empty():
					targets = [""]
				for target in targets:
					if not target.is_empty() and not await _try_select("TargetSelect", target):
						continue
					var preview := _node("Preview") as BaseButton
					if preview == null or preview.disabled:
						continue
					await _press("Preview")
					var plan: Dictionary = scene.get("_plan")
					if plan.get("valid", false):
						var score := _score(plan.get("result", {}), PARTY)
						if score > best_score:
							best_score = score
							best = {"actor": actor, "ability": ability, "target": target}
		# Discard the exploratory draft and apply only the chosen player command.
		var clear := _node("ClearCommand") as BaseButton
		if clear != null and not clear.disabled:
			await _press("ClearCommand")
			clear = _node("ClearCommand") as BaseButton
			if clear != null and not clear.disabled:
				await _press("ClearCommand")
		if not best.is_empty():
			await _try_select("ActorSelect", best.actor)
			await _try_select("AbilitySelect", best.ability)
			if not best.target.is_empty():
				await _try_select("TargetSelect", best.target)
			await _press("Preview")
		if round_index == 0:
			await _capture(id + "_preview")
		if round_index == 0 and _reachable(_node("Commit") as Control):
			await _click_commit()
		else:
			await _press("Commit")
		played_rounds += 1
		if scene.current_screen() == "battle":
			_check(scene.battle_snapshot().get("round", 0) > before.get("round", 0),
				id + " commit advances the round")
			if scene.battle_snapshot().get("round", 0) <= before.get("round", 0):
				return
	_check(false, id + " did not finish within %d rounds" % MAX_ROUNDS)


func _check_battle_controls(id: String) -> void:
	_check(_reachable(_node("Commit") as Control), id + " Commit is fully reachable at 1280x820")
	for actor in PARTY:
		var picker: Control
		for candidate in scene.find_children("*", "OptionButton", true, false):
			if candidate.get_meta("actor_id", "") == actor:
				picker = candidate
				break
		_check(_reachable(picker), id + " standing order for " + actor + " is fully reachable at 1280x820")


func _reachable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	var rect := control.get_global_rect()
	if rect.size.x <= 0 or rect.size.y <= 0 or not Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE)).encloses(rect):
		return false
	var parent := control.get_parent()
	while parent != null and parent != viewport:
		if parent is Control and parent.clip_contents and not parent.get_global_rect().encloses(rect):
			return false
		parent = parent.get_parent()
	return true


func _click_commit() -> void:
	var control := _node("Commit") as Control
	var point := control.get_global_rect().get_center() * 0.5
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame


func _score(state: Dictionary, party: Array) -> float:
	if state.is_empty():
		return -INF
	if state.get("outcome") == "victory":
		return 100000.0
	if state.get("outcome") == "defeat":
		return -100000.0
	var heroes: Array = []
	var enemies: Array = []
	for unit in state.get("units", []):
		if unit.id in party:
			heroes.append(unit)
		elif unit.get("hp", 0) > 0:
			enemies.append(unit)
	var score := 0.0
	for hero in heroes:
		score += float(hero.hp) * 3.0
		if hero.hp <= 0:
			score -= 50.0
		elif not enemies.is_empty():
			var nearest := 100
			for enemy in enemies:
				var delta: Vector2i = hero.position - enemy.position
				nearest = mini(nearest, absi(delta.x) + absi(delta.y))
			score -= float(nearest) * 0.5
	for enemy in enemies:
		score -= 20.0 + float(enemy.hp) * 6.0
	return score


func _geometry(state: Dictionary) -> Dictionary:
	var result := {"board": state.get("board_id"), "width": state.get("width"),
		"height": state.get("height"), "terrain": state.get("terrain"), "obstacles": state.get("obstacles")}
	var others: Array = []
	for unit in state.get("units", []):
		if unit.id not in state.get("party", []):
			others.append({"id": unit.id, "position": unit.position})
	result["others"] = others
	return result


func _choice_ids(picker: OptionButton) -> Array:
	var result: Array = []
	if picker != null and not picker.disabled and picker.is_visible_in_tree():
		for i in picker.item_count:
			var id := str(picker.get_item_metadata(i))
			if not id.is_empty() and not picker.is_item_disabled(i):
				result.append(id)
	return result


func _has_id(picker: OptionButton, id: String) -> bool:
	for i in picker.item_count:
		if str(picker.get_item_metadata(i)) == id and not picker.is_item_disabled(i):
			return true
	return false


func _select_id(picker: OptionButton, id: String) -> bool:
	if picker != null and not picker.disabled and picker.is_visible_in_tree():
		for i in picker.item_count:
			if str(picker.get_item_metadata(i)) == id and not picker.is_item_disabled(i):
				picker.select(i)
				picker.item_selected.emit(i)
				await process_frame
				return true
	_check(false, "Missing selectable choice " + id)
	return false


func _try_select(name: String, id: String) -> bool:
	var picker := _node(name) as OptionButton
	if picker == null or picker.disabled or not picker.is_visible_in_tree():
		return false
	for i in picker.item_count:
		if str(picker.get_item_metadata(i)) == id and not picker.is_item_disabled(i):
			picker.select(i)
			picker.item_selected.emit(i)
			await process_frame
			return true
	return false


func _node(name: String) -> Node:
	return scene.find_child(name, true, false)


func _press(name: String) -> void:
	var button := _node(name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is visible and enabled")
		return
	button.pressed.emit()
	await process_frame


func _capture(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var directory := arg.trim_prefix("--capture-dir=")
			if not directory.is_absolute_path() or DisplayServer.get_name() == "headless":
				_check(false, "Capture requires an absolute directory and graphical display")
				return
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			_check(image != null and not image.is_empty() and image.save_png(directory.path_join(name + ".png")) == OK,
				"Capture saves " + name)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: village outing scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
