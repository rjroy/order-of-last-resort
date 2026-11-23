extends SceneTree
## Shared scene fixture and bounded forecast-driven battle player.

const MAX_ROUNDS := 30
const VIEWPORT_SIZE := Vector2i(1280, 820)
var failures: Array[String] = []
var scene: Node
var viewport := SubViewport.new()
var driver


func _initialize() -> void:
	call_deferred("_run")

func _launch(args: PackedStringArray) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(args)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)

func _play_battle(id: String) -> void:
	if driver == null or driver.scene != scene:
		driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	for round_index in MAX_ROUNDS:
		if scene.current_screen() != "battle":
			return
		var before: Dictionary = scene.battle_snapshot()
		var battle_party: Array = before.get("party", [])
		# Preview each legal direct command, and compare it with standing orders.
		# This is bounded and deterministic for the authored encounter seed.
		var best_score := _score(scene.get("_plan").get("result", {}), battle_party)
		var best := {}
		var rules = driver.rules
		for actor in battle_party:
			var context: Dictionary = rules.state_before_action(scene.get("_state"), actor)
			if not rules.can_act(context, actor):
				continue
			for choice: Dictionary in rules.options(scene.get("_state"), actor):
				if choice.kind != "action":
					continue
				var ability: String = choice.id
				var targets: Array = rules.targets(context, actor, ability)
				if targets.is_empty():
					targets = [{"id": ""}]
				for target: Dictionary in targets:
					if not await driver.command(actor, ability, str(target.id)):
						continue
					var plan: Dictionary = scene.get("_plan")
					if plan.get("valid", false):
						var score := _score(plan.get("result", {}), battle_party)
						if score > best_score:
							best_score = score
							best = {"actor": actor, "ability": ability, "target": str(target.id)}
					await driver.clear()
		# Discard the exploratory draft and apply only the chosen player command.
		if not best.is_empty():
			_check(await driver.command(best.actor, best.ability, best.target), driver.error)
		if round_index == 0:
			await _capture(id + "_preview")
		if round_index == 0 and _reachable(_node("Commit") as Control):
			await _click_commit()
		else:
			await _press("Commit")
		if scene.current_screen() == "battle":
			if scene.battle_snapshot().get("outcome") != "ongoing":
				return
			_check(scene.battle_snapshot().get("round", 0) > before.get("round", 0),
				id + " commit advances the round")
			if scene.battle_snapshot().get("round", 0) <= before.get("round", 0):
				return
	_check(false, id + " did not finish within %d rounds" % MAX_ROUNDS)

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
	var suite: String = get_script().resource_path.get_file().trim_suffix(".gd")
	if failures.is_empty():
		print("PASS: " + suite)
	else:
		for failure in failures:
			push_error("FAIL: " + suite + ": " + failure)
	quit(0 if failures.is_empty() else 1)
