extends SceneTree
## Real-scene board capture. Run from the repository root with a graphical display:
## godot --path games/company-of-unlikely-heroes --script res://tools/capture_painted_boards.gd -- --output="$PWD/.lore/local/painted-boards"
## The output directory must be empty. No guild profile or existing save is read.

const BoardRules = preload("res://rules/board.gd")
const Rules = preload("res://rules.gd")
const SIZE := Vector2i(1280, 820)

var viewport: SubViewport
var scene: Node
var output := ""
var failure := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			if not output.is_empty():
				_finish("Specify --output only once.")
				return
			output = arg.trim_prefix("--output=").simplify_path()
	var local := ProjectSettings.globalize_path("res://../../.lore/local").simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/"):
		_finish("Supply an absolute --output directory under .lore/local/.")
		return
	if DisplayServer.get_name() == "headless":
		_finish("A graphical renderer is required.")
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_finish("Cannot create output directory: " + output)
		return
	var directory := DirAccess.open(output)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_finish("Output directory must be empty: " + output)
		return
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	if not await _launch("wrong_side_of_the_door"):
		_finish(failure)
		return
	if BoardRules.pressure_gate_open(scene.battle_snapshot()) or not await _capture("gate-closed.png"):
		_finish("Gate opening was not closed, or capture failed: " + failure)
		return
	for target in ["1,1", "2,1"]:
		if not await _command("knight", "move", target):
			_finish(failure)
			return
	if not BoardRules.pressure_gate_open(scene.battle_snapshot()) or not await _capture("gate-open.png"):
		_finish("The committed moves did not open the gate, or capture failed: " + failure)
		return

	if not await _launch("bridge_is_out") or not await _capture("bridge-opening.png"):
		_finish(failure)
		return
	for round_number in range(1, 7):
		if not await _commit():
			_finish(failure)
			return
		if round_number in [4, 6]:
			var state: Dictionary = scene.battle_snapshot()
			if state.is_empty() or not _collapsed_through(state, round_number):
				_finish("Expected committed bridge collapse through round %d." % round_number)
				return
			if not await _capture("bridge-after-round-%d.png" % round_number):
				_finish(failure)
				return
	if not await _launch("goblin_mob") or not await _capture("village-opening.png"):
		_finish(failure)
		return
	print("Captured real mission boards in " + output)
	_finish("")


func _launch(mission: String) -> bool:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--mission=" + mission]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if scene.current_screen() != "battle" or scene.battle_snapshot().get("mission_id") != mission:
		return _fail("Could not launch mission " + mission)
	return true


func _command(actor: String, ability: String, target: String) -> bool:
	if not await _select("ActorSelect", actor) or not await _select("AbilitySelect", ability) \
			or not await _select("TargetSelect", target) or not await _press("Preview"):
		return false
	return await _commit()


func _commit() -> bool:
	var before: Dictionary = scene.battle_snapshot()
	var plan: Dictionary = scene.get("_plan")
	if before.is_empty() or not plan.get("valid", false):
		return _fail("The scene has no valid round forecast.")
	var expected: Dictionary = plan.get("result", {}).duplicate(true)
	if not await _press("Commit"):
		return false
	if scene.battle_snapshot() != expected:
		return _fail("Committed round differs from its forecast or left battle.")
	return true


func _select(name: String, id: String) -> bool:
	var picker := scene.find_child(name, true, false) as OptionButton
	if picker != null and picker.is_visible_in_tree() and not picker.disabled:
		for i in picker.item_count:
			if str(picker.get_item_metadata(i)) == id and not picker.is_item_disabled(i):
				picker.select(i)
				picker.item_selected.emit(i)
				await process_frame
				return true
	return _fail("%s does not offer %s." % [name, id])


func _press(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		return _fail(name + " is not available.")
	button.pressed.emit()
	await process_frame
	return true


func _collapsed_through(state: Dictionary, round_number: int) -> bool:
	var rules = Rules.new()
	for span in state.objective.get("collapses", []):
		if int(span.round) <= round_number:
			for cell in span.cells:
				if rules.tile_definition(state, cell).get("passable", true):
					return false
	return true


func _capture(filename: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != SIZE:
		return _fail("Could not read the full viewport for " + filename)
	if image.save_png(output.path_join(filename)) != OK:
		return _fail("Could not write " + filename)
	print("Captured %s: mission=%s next_round=%s" % [
		filename, scene.battle_snapshot().get("mission_id"), scene.battle_snapshot().get("round")])
	return true


func _fail(message: String) -> bool:
	failure = message
	return false


func _finish(message: String) -> void:
	if not message.is_empty():
		push_error(message)
	quit(0 if message.is_empty() else 1)
