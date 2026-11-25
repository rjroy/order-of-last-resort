extends SceneTree
## Run graphically from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/storybook_ink_reparent_test.gd
## The parent process checks engine errors as well as the child process exit code.

const Board := preload("res://presentation/battle/bridge_art.gd")
const Page := preload("res://presentation/battle/storybook_battle_page.gd")
const GATE := Vector2i(1, 0)
const CELLS := {Vector2i(0, 0): "stone", GATE: "stone", Vector2i(2, 0): "stone"}

var failures: Array[String] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Storybook ink reparent test requires a graphical renderer.")
		quit(1)
		return
	if "--child" not in OS.get_cmdline_user_args():
		call_deferred("_run_child")
	else:
		call_deferred("_scenario")


func _run_child() -> void:
	var output := []
	var code := OS.execute(OS.get_executable_path(), [
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/presentation/storybook_ink_reparent_test.gd", "--", "--child"
	], output, true)
	var text := "\n".join(output)
	print(text)
	_check(code == 0, "Reparent scenario exits successfully")
	_check(not text.contains("SCRIPT ERROR:") and not text.contains("ERROR:"),
		"Reparent and resize produce no engine or script errors")
	_finish()


func _scenario() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var old_host := Control.new()
	viewport.add_child(old_host)
	var page := Page.new()
	old_host.add_child(page)
	var board := Board.new()
	page.mount_board(board, "frontier_gate_board")
	board.set_render_state(CELLS, [], {"pressure_gate": {"cell": GATE, "open": false}})
	var ink: Control = page.get("_ink")
	var props: Dictionary = page.get("_props")
	ink.render({"gate_actual": {"cell": GATE, "open": false}, "selected_cell": GATE})
	await process_frame
	_check(props.get("gate_closed", {}).get("texture") is Texture2D
		and props.get("gate_open", {}).get("texture") is Texture2D,
		"Accepted open and closed gate art is loaded")
	_check_state(board, ink, props, false)

	# Match the terminal replay: move the entire live board, then delete its old page.
	var destination := ColorRect.new()
	destination.color = Color("#36261b")
	destination.size = Vector2(viewport.size)
	destination.z_index = 10
	viewport.add_child(destination)
	board.reparent(destination)
	old_host.queue_free()
	await process_frame
	await process_frame
	board.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	board.size = Vector2(900, 540)
	await process_frame
	await RenderingServer.frame_post_draw
	_check_state(board, ink, props, false)
	var closed := viewport.get_texture().get_image()
	var layer: CanvasItem = ink.get("_prop_layer")
	if is_instance_valid(layer):
		layer.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		var without_prop := viewport.get_texture().get_image()
		_check(_difference(closed, without_prop) > 100, "Closed gate prop visibly renders after reparent")
		layer.visible = true
	ink.render({"gate_actual": {"cell": GATE, "open": true}, "selected_cell": GATE})
	board.set_render_state(CELLS, [], {"pressure_gate": {"cell": GATE, "open": true}})
	await process_frame
	await RenderingServer.frame_post_draw
	_check_state(board, ink, props, true)
	var opened := viewport.get_texture().get_image()
	_check(_difference(closed, opened) > 100, "Open and closed gate states render differently")
	var units := [{"id": "knight", "art_key": "knight", "cast_key": "knight", "cell": GATE, "facing": 1}]
	board.set_render_state(CELLS, units, {"pressure_gate": {"cell": GATE, "open": true}})
	await process_frame
	await RenderingServer.frame_post_draw
	var occupied := viewport.get_texture().get_image()
	_check(_difference(opened, occupied) > 100, "An actor remains visible on the gate cell")
	viewport.queue_free()
	await process_frame
	_finish()


func _check_state(board: Control, ink: Control, props: Dictionary, open: bool) -> void:
	var layer: Variant = ink.get("_prop_layer")
	var figures: CanvasItem = board.get("_figures")
	var selected: Dictionary = ink.call("_actual_gate_prop")
	var expected: Dictionary = props.get("gate_open" if open else "gate_closed", {})
	_check(bool(board.get("_pressure_gate_prop_installed")), "Replacement gate remains installed")
	_check(selected.get("texture") is Texture2D and selected.get("texture") == expected.get("texture"),
		"Actual gate selects the accepted art for its current state")
	_check(is_instance_valid(layer) and layer.is_inside_tree() and board.is_ancestor_of(layer),
		"Real prop layer remains mounted on the live board")
	if is_instance_valid(layer) and board.is_ancestor_of(layer):
		var prop_z := _effective_z(layer)
		var figure_z := _effective_z(figures)
		var top: Node = layer
		while top.get_parent() != board:
			top = top.get_parent()
		_check(prop_z < figure_z or (prop_z == figure_z and top.get_index() < figures.get_index()),
			"Props render below actors")
		_check(_effective_z(ink) > figure_z, "Foreground pencil marks render above actors")


func _effective_z(item: CanvasItem) -> int:
	var value := item.z_index
	var current := item
	while current.z_as_relative and current.get_parent() is CanvasItem:
		current = current.get_parent()
		value += current.z_index
	return value


func _difference(first: Image, second: Image) -> int:
	var changed := 0
	for y in first.get_height():
		for x in first.get_width():
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 8.0 / 255.0:
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: storybook ink survives board reparent, deletion, resize, and gate state changes")
	quit(0 if failures.is_empty() else 1)
