extends SceneTree

## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/storybook_mixologist_reaction_scene_test.gd
## Add `-- --case=aim` or `-- --case=cosmetic` to run one regression.
const Catalog := preload("res://content/catalog.gd")
const Rules := preload("res://rules.gd")
const Driver := preload("res://tests/support/storybook_driver.gd")
const SIZE := Vector2i(1280, 720)
const ACTOR := "alchemist"
const POTION := "alchemist_potion"
const RECIPIENT := "knight"
const OTHER := "healer"
const COSMETIC := "fine_bubbles"
const MIN_MARK_PIXELS := 24

var rules := Rules.new()
var scene: Node
var viewport: SubViewport
var board: Control
var driver: Driver
var failures: Array[String] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Mixologist reaction tests require a graphical renderer.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var test_case := str(args[0]).trim_prefix("--case=") if not args.is_empty() else "all"
	if not _check(test_case in ["all", "aim", "cosmetic"], "Use --case=aim or --case=cosmetic"):
		_finish()
		return
	# A fixed SubViewport exercises this layout independently of the window manager.
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=goblin_mob"]))
	viewport.add_child(scene)
	driver = Driver.new(self, scene)
	await process_frame
	await process_frame
	if _check(viewport.get_visible_rect().size == Vector2(SIZE), "Layout is actually 1280x720"):
		if test_case in ["all", "aim"]:
			await _test_aim()
		if test_case in ["all", "cosmetic"]:
			await _test_cosmetic()
	_finish()


func _test_aim() -> void:
	var opening := await _open_fixture("handle_with_care", "aim_fixture")
	if opening.is_empty():
		return
	var dose: Dictionary = rules.dose_forecast(opening, ACTOR, POTION)
	_check(str(dose.description).length() > 90, "Fixture uses an extended reaction with an expiry clause")
	if not await _aim(opening):
		return
	# Also fill the board inspection line, as when a player points at a legal recipient.
	var recipient := _cell_center(_unit(opening, RECIPIENT).position)
	_move_pointer(recipient)
	await process_frame
	await process_frame
	# The title and effect may live in different UI elements. Require the complete
	# effect, including expiry, to be readable without having to pick a target.
	var effect := str(dose.description).trim_prefix(str(dose.label)).strip_edges().substr(1).strip_edges()
	_check(not effect.is_empty() and await _readable_aim_effect(effect),
		"Before a recipient is picked, the complete reaction effect and expiry are readable "
		+ "at 1280x720 (inline or through a working tooltip)")
	_check(scene.battle_snapshot() == opening
		and (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty(),
		"Reading the locked reaction neither picks a recipient nor commits the round")


func _test_cosmetic() -> void:
	var opening := await _open_fixture(COSMETIC, "cosmetic_fixture")
	if opening.is_empty():
		return
	_isolate_reaction_ink()
	var recipient := _tile_area(_unit(opening, RECIPIENT).position)
	var caster := _tile_area(_unit(opening, ACTOR).position)
	var other := _tile_area(_unit(opening, OTHER).position)
	var clean := await _frame()
	if not await _stage_cosmetic(opening):
		return
	var forecast := await _frame()
	if not await _commit_cosmetic():
		return
	board.set_process(false)
	var before_impact := await _frame()
	if not _advance_to_reaction():
		return
	var committed := await _frame()
	_tick_board(0.5)
	var readable := await _frame()
	_tick_board(2.25)
	var settled := await _frame()
	_check(_changed_pixels(forecast, clean, recipient) >= MIN_MARK_PIXELS,
		"Staged cosmetic displays a forecast mark on the chosen recipient")
	_check(_changed_pixels(before_impact, settled, recipient) < MIN_MARK_PIXELS,
		"Committed seal does not display during the action windup")
	_check(_changed_pixels(committed, settled, recipient) >= MIN_MARK_PIXELS,
		"Committed cosmetic visibly marks the actual recipient")
	_check(_changed_pixels(committed, forecast, recipient) >= MIN_MARK_PIXELS,
		"Committed mark is visually distinct from forecast on the recipient's tile")
	_check(_changed_pixels(readable, settled, recipient) >= MIN_MARK_PIXELS,
		"Actual recipient cue is still readable after half a second")
	_check(_changed_pixels(committed, settled, caster) < MIN_MARK_PIXELS
		and _changed_pixels(committed, settled, other) < MIN_MARK_PIXELS,
		"The committed recipient mark does not appear on the caster or unchosen ally")
	_check(_changed_pixels(settled, clean, recipient) < MIN_MARK_PIXELS,
		"Committed cosmetic clears from the board without another round or input")

	# Transition while a second cue is live, not just after the first one expired.
	opening = await _open_fixture(COSMETIC, "cosmetic_fixture")
	if opening.is_empty():
		return
	_isolate_reaction_ink()
	if not await _stage_cosmetic(opening) or not await _commit_cosmetic():
		return
	board.set_process(false)
	if not _advance_to_reaction():
		return
	var replayed := await _frame()
	_check(_changed_pixels(replayed, clean, recipient) >= MIN_MARK_PIXELS,
		"Second commit starts a visible cosmetic before the battle transition")
	var next := await _open_fixture("handle_with_care", "next_battle_fixture")
	if next.is_empty():
		return
	_isolate_reaction_ink()
	var next_frame := await _frame()
	var next_recipient := _tile_area(_unit(next, RECIPIENT).position)
	_check(next_recipient == recipient, "The next battle uses the same recipient tile and layout")
	_check(_changed_pixels(next_frame, clean, next_recipient) < MIN_MARK_PIXELS,
		"Next battle starts without the prior battle's active cosmetic")


func _advance_to_reaction() -> bool:
	for _frame_index in 1000:
		if not board.committed_reaction_marks().is_empty():
			return true
		if not board.action_playback_pending():
			break
		_tick_board(0.01)
	return _check(false, "Committed dose never reached its reaction marker")


func _tick_board(delta: float) -> void:
	board.call("_process", delta)
	board.set_process(false)


func _isolate_reaction_ink() -> void:
	# The board keeps processing its ready and action animations. Hide only their
	# shared drawing layer: unrelated sprite frames otherwise dominate tile diffs.
	# Forecast and committed seals remain on the live storybook ink layer.
	(board.get("_figures") as CanvasItem).hide()


func _aim(opening: Dictionary) -> bool:
	if not await driver.select_actor(ACTOR) or not await driver.action(POTION):
		return _check(false, driver.error)
	var ids: Array = (scene.get("_targets") as Array).map(func(choice: Dictionary) -> String:
		return choice.id)
	return _check(RECIPIENT in ids and OTHER in ids
		and (scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty()
		and scene.battle_snapshot() == opening,
		"Aimed potion offers at least two recipients while no command is staged")


func _stage_cosmetic(opening: Dictionary) -> bool:
	if not await _aim(opening):
		return false
	if not await driver.target(RECIPIENT):
		return _check(false, driver.error)
	# Close targeting mode without clearing the stage, so the rings for legal
	# targets cannot masquerade as a difference between forecast and actual.
	if not await driver.action(POTION):
		return _check(false, driver.error)
	var planned: Dictionary = scene.get("_planned_state")
	var plan: Dictionary = scene.get("_plan")
	var target_cell: Vector2i = _unit(opening, RECIPIENT).position
	var reactions := (plan.get("events", []) as Array).filter(func(event: Dictionary) -> bool:
		return event.get("type") == "alchemy_reaction")
	_move_pointer(Vector2(6, 6))
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if commit != null:
		commit.grab_focus()
	return _check(scene.battle_snapshot() == opening and plan.get("valid", false)
		and planned.get("overrides", {}).get(ACTOR, {}).get("target_id") == RECIPIENT
		and not target_cell in (board.get("_overlay") as Dictionary).get("targets", [])
		and reactions.size() == 1 and reactions[0].get("reaction_id") == COSMETIC
		and reactions[0].get("category") == "cosmetic" and reactions[0].get("target_id") == RECIPIENT
		and reactions[0].get("position") == target_cell,
		"Potion forecasts one cosmetic on the intended unmoved recipient, without aiming rings")


func _commit_cosmetic() -> bool:
	var commit := scene.find_child("Commit", true, false) as BaseButton
	if not _check(commit != null and commit.is_visible_in_tree() and not commit.disabled,
			"Commit is available for the staged cosmetic"):
		return false
	var forecast: Dictionary = (scene.get("_plan") as Dictionary).get("result")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = commit.get_global_rect().get_center()
		event.global_position = event.position
		viewport.push_input(event, true)
		await process_frame
	return _check(scene.battle_snapshot() == forecast and forecast.get("outcome") == "ongoing",
		"Commit resolves the forecast and leaves a live board for the next round")


func _open_fixture(reaction_id: String, mission_id: String) -> Dictionary:
	var defs := Catalog.read_default().duplicate(true)
	defs.characters.practice_raider = defs.characters.grunt.duplicate(true)
	defs.characters.practice_raider.behavior = "hold"
	for id in [ACTOR, RECIPIENT, OTHER]:
		var habits: Dictionary = Catalog.profile(defs, id).habits.duplicate()
		habits["order_hold"] = "hold"
		defs.characters[id]["habits"] = habits
		defs.characters[id]["default_order"] = "order_hold"
	defs.encounters.reaction_fixture = {"board": "road", "seed": 2, "placements": [
		{"id": ACTOR, "character": ACTOR, "at": [2, 2]},
		{"id": RECIPIENT, "character": RECIPIENT, "at": [3, 2]},
		{"id": OTHER, "character": OTHER, "at": [1, 2]},
		{"id": "practice_raider", "character": "practice_raider", "at": [6, 3]},
	]}
	defs.missions[mission_id] = defs.missions.shield_wall.duplicate(true)
	defs.missions[mission_id].encounter = "reaction_fixture"
	defs.missions[mission_id].erase("default_party")
	var opening := Rules.open_mission(defs, mission_id)
	if not _check(not opening.is_empty(), "Test-owned reaction battle opens"):
		return {}
	# Control the dose without coupling the test to a particular RNG sequence.
	var matched := false
	for seed_value in range(1, 1000):
		opening.dose_seed = seed_value
		if rules.dose_forecast(opening, ACTOR, POTION).get("reaction_id") == reaction_id:
			matched = true
			break
	if not _check(matched, "Fixture has a locked " + reaction_id + " dose"):
		return {}
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	_move_pointer(Vector2(6, 6))
	await process_frame
	await process_frame
	board = scene.find_child("BridgeBoard", true, false) as Control
	return opening if _check(board != null and scene.battle_snapshot() == opening,
		"Storybook mounts the fixture's live battle board") else {}


func _readable_aim_effect(effect: String) -> bool:
	for label in scene.find_children("*", "Label", true, false):
		if effect in label.text and _label_fits(label):
			return true
	for node in scene.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.mouse_filter == Control.MOUSE_FILTER_IGNORE \
				or effect not in control.tooltip_text or not _within_viewport(control):
			continue
		_move_pointer(control.get_global_rect().get_center())
		await process_frame
		var hovered := viewport.gui_get_hovered_control()
		if hovered == null or (hovered != control and not control.is_ancestor_of(hovered)):
			continue
		await create_timer(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")) + 0.2).timeout
		for candidate in viewport.find_children("*", "Label", true, false):
			if effect in candidate.text and _label_fits(candidate):
				return true
	return false


func _label_fits(label: Label) -> bool:
	if not label.is_visible_in_tree() or not _within_viewport(label) \
			or label.get_visible_line_count() != label.get_line_count():
		return false
	var font: Font = label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	if label.label_settings != null:
		font = label.label_settings.font if label.label_settings.font != null else font
		font_size = label.label_settings.font_size
	var content_size := label.size - label.get_theme_stylebox("normal").get_minimum_size()
	if label.get_line_count() == 1 or label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		for line in label.text.split("\n"):
			if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > content_size.x + 1.0:
				return false
	return label.get_line_height() * label.get_line_count() <= content_size.y + 1.0


func _within_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	if not rect.has_area() or not control.get_viewport().get_visible_rect().encloses(rect):
		return false
	var parent := control.get_parent() as Control
	while parent != null:
		if parent.clip_contents and not parent.get_global_rect().encloses(rect):
			return false
		parent = parent.get_parent() as Control
	return true


func _cell_center(cell: Vector2i) -> Vector2:
	return board.get_global_transform_with_canvas() * board.cell_center(cell)


func _tile_area(cell: Vector2i) -> Rect2i:
	var step := _cell_center(Vector2i.ONE) - _cell_center(Vector2i.ZERO)
	return Rect2i(Rect2(_cell_center(cell) - step * 0.49, step * 0.98))


func _frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _changed_pixels(a: Image, b: Image, area: Rect2i) -> int:
	var changed := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 12.0 / 255.0:
				changed += 1
	return changed


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.units:
		if unit.id == id:
			return unit
	return {}


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func _finish() -> void:
	if failures.is_empty():
		print("PASS: storybook Mixologist reaction scene")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
