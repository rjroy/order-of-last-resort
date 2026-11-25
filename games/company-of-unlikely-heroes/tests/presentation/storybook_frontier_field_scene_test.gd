extends SceneTree

# Run: godot --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_frontier_field_scene_test.gd
# A graphical display is required so rejected launches do not terminate the test tree.
const MISSIONS := [
	"shield_wall", "cowardly_captain", "explosive_situation", "unfortunate_healer",
	"duelists", "odd_couple", "mirror_company", "last_one_standing"
]
const Rules = preload("res://rules/rules.gd")
const CastSprites = preload("res://presentation/cast/cast_sprites.gd")
const FIELD_SURROUND := "res://assets/storybook-field/frontier-field-surround-rgba.png"
var rules = Rules.new()
var failures: Array[String] = []
var scene: Node
var board: Control
var field_surround: Texture2D
var viewport: SubViewport


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires a graphical display.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_check(FileAccess.file_exists(FIELD_SURROUND), "Approved field surround is packaged in the game")
	var packaged_surround := CastSprites.load_texture(FIELD_SURROUND)
	for id in MISSIONS:
		await _launch(PackedStringArray(["--mission=" + id]))
		_check(scene.current_screen() == "battle", id + ": storybook launch enters battle")
		if scene.current_screen() != "battle":
			continue
		var state: Dictionary = scene.battle_snapshot()
		_check(state.get("mission_id") == id, id + ": requested mission is loaded")
		board = scene.find_child("BridgeBoard", true, false) as Control
		var page: Control = scene.get("_storybook_page")
		var ink := scene.find_child("StorybookInk", true, false) as Control
		_check(page != null and page.is_visible_in_tree() and board != null and board.is_visible_in_tree()
			and ink != null, id + ": existing storybook page mounts the live board and ink")
		if page == null or board == null or ink == null:
			continue
		_check_objective(page, state, id)
		var cues: Dictionary = ink.get("_cues")
		_check(cues.get("gate_actual", {}).is_empty() and cues.get("gate", {}).is_empty(),
			id + ": no Gate state or forecast is drawn")
		for landmark in cues.get("landmarks", []):
			_check(landmark.get("kind", "") not in ["gate", "plate", "exit"],
				id + ": no Gate-specific landmark")
		_check(not bool(board.get("_pressure_gate_prop_installed")),
			id + ": no Gate prop installed on the field")
		var scenery: TextureRect = page.get("_scenery")
		var gate_scenery := CastSprites.load_texture(
			"res://assets/storybook-gate/gate-scenery-surround-wall-rgba.png")
		_check(scenery != null and scenery.texture != null and scenery.is_visible_in_tree(),
			id + ": normal launch displays the packaged field surround")
		if scenery != null and scenery.texture != null:
			_check(scenery.texture != gate_scenery, id + ": field does not display Gate scenery")
			_check(packaged_surround != null and scenery.texture == packaged_surround,
				id + ": displays the packaged field surround texture")
			if field_surround == null:
				field_surround = scenery.texture
			else:
				_check(scenery.texture == field_surround, id + ": uses the shared field surround")
		_check((page.get("_props") as Dictionary).is_empty(),
			id + ": no Gate scene props are loaded")
		if id == "shield_wall":
			if scenery != null and scenery.texture != null:
				await _check_rendered_surround(scenery)
				await _check_registered_field_with_orders(scenery, state)
			await _exercise_combat(state)

	await _launch(PackedStringArray(["--mission=not_a_mission"]))
	_check(scene.current_screen() == "error", "Unknown mission is rejected")
	await _launch(PackedStringArray(["--mission=goblin_mob"]))
	_check(scene.current_screen() == "battle" and scene.get("_storybook_page") != null,
		"Other stock boards also launch in the storybook")
	_finish()


func _check_rendered_surround(scenery: TextureRect) -> void:
	await RenderingServer.frame_post_draw
	var with_surround := viewport.get_texture().get_image()
	scenery.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var without_surround := viewport.get_texture().get_image()
	scenery.visible = true
	var changed := 0
	if with_surround.get_size() == without_surround.get_size():
		for y in range(0, with_surround.get_height(), 8):
			for x in range(0, with_surround.get_width(), 8):
				var delta := with_surround.get_pixel(x, y) - without_surround.get_pixel(x, y)
				if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
					changed += 1
	_check(changed > 50, "Packaged field surround contributes to the rendered page")
	await process_frame


func _check_registered_field_with_orders(scenery: TextureRect, state: Dictionary) -> void:
	if not await _button("StandingOrders"):
		return
	var leaf := scene.find_child("ExtraDetails", true, false) as Control
	_check(leaf != null and leaf.is_visible_in_tree() and not leaf.get_global_rect().intersects(board.get_global_rect()),
		"Standing orders keeps the painted Field and its gutters exposed")
	var with_art := await _frame()
	scenery.hide()
	var without_art := await _frame()
	scenery.show()
	var figures := board.get_node("CastAndUnitMarkers") as CanvasItem
	figures.hide()
	var without_figures := await _frame()
	figures.show()
	var tx := board.get_global_transform_with_canvas()
	var step: Vector2 = (tx * board.cell_center(Vector2i.ONE)) - (tx * board.cell_center(Vector2i.ZERO))
	var first: Vector2 = tx * board.cell_center(Vector2i.ZERO)
	var last: Vector2 = tx * board.cell_center(Vector2i(state.width - 1, state.height - 1))
	var field := Rect2i(Rect2(first - step * 0.45, last - first + step * 0.9))
	_check(_changed_samples(with_art, without_art, field) == 0,
		"Field surround leaves the refitted tactical aperture transparent, including occupied cells")
	for unit: Dictionary in state.units:
		var center: Vector2 = tx * board.cell_center(unit.position)
		var region := Rect2i(Rect2(center - step * 0.45, step * 0.9))
		_check(_changed_samples(with_art, without_figures, region) > 4,
			"Living %s is visibly rendered with Standing orders open" % unit.id)
	if leaf != null and leaf.is_visible_in_tree():
		await _check_visible_order_rows(leaf, state)
	await _button("StandingOrders")


func _check_visible_order_rows(leaf: Control, state: Dictionary) -> void:
	var page: Control = scene.get("_storybook_page")
	var scroll: ScrollContainer = page.get("_orders_scroll")
	var bar := scroll.get_v_scroll_bar()
	var instructions: Label = page.get("_order_instructions")
	var rows: Dictionary = page.get("_order_widgets")
	_check(rows.size() == 3 and not bar.is_visible_in_tree(),
		"All three stock Standing orders fit at 1280×820 without a scrollbar")
	_check(instructions.is_visible_in_tree()
		and leaf.get_global_rect().encloses(instructions.get_global_rect())
		and instructions.get_visible_line_count() == instructions.get_line_count(),
		"Standing orders instructions are shown in full")
	for unit: Dictionary in state.units:
		if not rows.has(unit.id):
			continue
		var widgets: Dictionary = rows[unit.id]
		var hp: Label = widgets.detail
		var order: OptionButton = widgets.picker
		_check(hp.text == "%d/%d HP" % [unit.hp, unit.max_hp],
			"Standing orders shows the actual HP for %s" % unit.id)
		_check(_fully_visible_in_orders(hp, scroll) and _fully_visible_in_orders(order, scroll),
			"Standing orders shows the full HP and order picker for %s, including the bottom edge" % unit.id)
	var last := scene.find_child("WizardOrder", true, false) as OptionButton
	if last == null:
		_check(false, "Standing orders has the Caster's picker")
		return
	await _click(last.get_global_rect().get_center())
	var popup := last.get_popup()
	_check(popup.visible and scene.battle_snapshot() == state,
		"The fully visible Caster picker opens by click without changing the order")
	popup.hide()

	# A short viewport exercises the same native overflow path used by longer custom order lists.
	var normal_size := viewport.size
	viewport.size = Vector2i(normal_size.x, 600)
	await _frame()
	_check(bar.is_visible_in_tree() and not _fully_visible_in_orders(last, scroll)
		and not leaf.get_global_rect().intersects(board.get_global_rect()),
		"A short viewport scrolls Standing orders rather than covering the board")
	var first := scene.find_child("KnightOrder", true, false) as OptionButton
	if first != null:
		first.grab_focus()
		await process_frame
	last.grab_focus()
	await _frame()
	_check(bar.value > 0.0 and _fully_visible_in_orders(last, scroll),
		"Focusing the bottom order scrolls it fully into view when space is constrained")
	viewport.size = normal_size
	await _frame()
	_check(not bar.is_visible_in_tree() and _fully_visible_in_orders(last, scroll),
		"Returning to play size restores the full list without scrolling")


func _fully_visible_in_orders(control: Control, scroll: ScrollContainer) -> bool:
	return control.is_visible_in_tree() and scroll.get_global_rect().encloses(control.get_global_rect())


func _frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _changed_samples(first: Image, second: Image, region: Rect2i) -> int:
	var changed := 0
	for y in range(region.position.y, region.end.y, 4):
		for x in range(region.position.x, region.end.x, 4):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
				changed += 1
	return changed


func _launch(args: PackedStringArray) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(args)
	viewport.add_child(scene)
	await process_frame
	await process_frame


func _exercise_combat(before: Dictionary) -> void:
	var knight := {}
	var healer := {}
	for unit in before.get("units", []):
		if unit.get("id") == "knight":
			knight = unit
		if unit.get("id") == "healer":
			healer = unit
	if knight.is_empty() or healer.is_empty():
		_check(false, "Shield Wall has Knight and Healer")
		return
	await _click_cell(healer.position)
	_check(scene.get("_actor_id") == "healer", "Board selects Healer")
	await _click_cell(knight.position)
	_check(scene.get("_actor_id") == "knight", "Board selects Knight")
	var targets: Array = rules.targets(before, "knight", "move")
	if targets.is_empty():
		_check(false, "Shield Wall Knight has a legal opening move")
		return
	var target: Dictionary = targets[0]
	await _click_cell(target.position)
	var planned: Dictionary = scene.get("_planned_state")
	var command: Dictionary = planned.get("overrides", {}).get("knight", {})
	_check(planned.get("overrides", {}).size() == 1 and command.get("ability_id") == "move"
		and command.get("target_id") == target.id, "Board input stages exactly one Knight move")
	_check(scene.battle_snapshot() == before, "Staging does not change the battle")
	var plan: Dictionary = scene.get("_plan")
	_check(plan.get("valid", false) and plan == rules.preview_round(planned),
		"Staged move has the real round forecast")
	if not await _button("ClearCommand"):
		return
	_check((scene.get("_planned_state") as Dictionary).get("overrides", {}).is_empty()
		and scene.battle_snapshot() == before, "Clear reverses the override without committing")
	await _click_cell(target.position)
	plan = scene.get("_plan").duplicate(true)
	_check(plan.get("valid", false) and scene.battle_snapshot() == before,
		"Restaged move remains a valid uncommitted forecast")
	if await _button("Commit"):
		_check(scene.battle_snapshot() == plan.get("result") and scene.battle_snapshot() != before,
			"Commit resolves the displayed forecast")
		if scene.battle_snapshot().get("outcome") == "ongoing":
			_check_objective(scene.get("_storybook_page"), scene.battle_snapshot(), "Shield Wall after commit")


func _check_objective(page: Control, state: Dictionary, label: String) -> void:
	var objective: Label = page.get("_objective")
	var mission: Dictionary = rules.mission_definition(state)
	var details: String = str(mission.objective.text).format({"deadline": rules.deadline(state)})
	var first_end := details.find(". ")
	var headline := details.substr(0, first_end + 1) if first_end >= 0 else details
	var progress: Dictionary = rules.objective_progress(state)
	var count := "%d / %d targets remaining" % [progress.alive, progress.total]
	_check(objective != null and objective.is_visible_in_tree()
		and objective.text.contains(headline) and objective.text.contains(count)
		and not objective.text.contains("Get a hero to the exit"),
		label + ": visible objective has the combat headline and current target count")
	_check(objective != null and objective.tooltip_text == details,
		label + ": objective tooltip retains full authored details")


func _click_cell(cell: Vector2i) -> void:
	await _click(board.get_global_transform_with_canvas() * board.cell_center(cell))


func _button(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, name + " is visible and enabled")
		return false
	await _click(button.get_global_rect().get_center())
	return true


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		viewport.push_input(event, true)
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: frontier field storybook launches and combat")
	quit(0 if failures.is_empty() else 1)
