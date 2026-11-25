extends SceneTree
## Graphical, real packaged Archer release; output directory supplied with --output.
const Board = preload("res://presentation/battle/bridge_art.gd")
var failures: Array[String] = []
var viewport := SubViewport.new()
var board := Board.new()
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless" or output.is_empty():
		push_error("Graphical display and --output are required")
		quit(1)
		return
	call_deferred("_run")

func _run() -> void:
	var local := ProjectSettings.globalize_path("res://../../.lore/local").simplify_path()
	output = output.simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/"):
		push_error("Output must be under .lore/local")
		quit(1)
		return
	var check := local
	for part in output.trim_prefix(local + "/").split("/"):
		check = check.path_join(part)
		var parent := DirAccess.open(check.get_base_dir())
		if parent != null and parent.is_link(check.get_file()):
			push_error("Output may not use symlinks")
			quit(1)
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create output")
		quit(1)
		return
	var dir := DirAccess.open(output)
	if dir == null or not dir.get_files().is_empty() or not dir.get_directories().is_empty():
		push_error("Output must be new or empty")
		quit(1)
		return
	viewport.size = Vector2i(720, 280)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	root.add_child(viewport)
	await process_frame
	var art = board.get("_cast")
	var launch = art.clip_for("archer", "draw_and_release")
	var projectile = art.clip_for("archer", "arrow_projectile")
	if launch == null or projectile == null or not projectile.tip is Vector2 or launch.release_ms < 0:
		push_error("Packaged archer release/tip missing")
		quit(1)
		return
	var source := Vector2i(2, 0)
	var cells := {}
	for x in 5:
		cells[Vector2i(x, 0)] = "stone"
	for direction in [-1, 1]:
		board.clear_action_playback()
		board.set_render_state(cells, [{"id": "archer", "cell": source, "art_key": "enemy",
			"cast_key": "archer", "hp": 3}])
		board.set_process(false)
		var target := source + Vector2i(direction * 2, 0)
		board.play_committed_actions([{"unit_id": "archer", "cast_key": "archer",
			"clip": "draw_and_release", "ordinary_presentation": true, "ordinary_role": "action",
			"source_cell": source, "actor_cell": source, "target_cell": target, "target_id": "target",
			"recipients": []}])
		board.set_process(false)
		var entry = board.get("_playback").active()[0]
		board._process(launch.release_ms / 1000.0)
		board.set_process(false)
		board.call("_sync_playback_geometry")
		var sign := Vector2(direction, 1)
		var expected_origin: Vector2 = board.call("_unit_foot", source) + launch.release_offset * sign * launch.scale
		var landing: Vector2 = board.call("_unit_foot", target) + Vector2(0, -29)
		var tip: Vector2 = ((projectile.tip - projectile.anchor) * sign * projectile.scale).rotated(entry.gift_angle)
		if not entry.gift_point_first or not entry.gift_from is Vector2 \
				or not expected_origin.is_equal_approx(entry.gift_from) \
				or not landing.is_equal_approx(entry.gift_to + tip):
			failures.append("Release origin or arrow tip incorrect for facing %d" % direction)
		await process_frame
		await RenderingServer.frame_post_draw
		if viewport.get_texture().get_image().save_png(output.path_join("release-%d.png" % direction)) != OK:
			failures.append("Cannot save release")
		board._process(0.12)
		board.set_process(false)
		await process_frame
		await RenderingServer.frame_post_draw
		if viewport.get_texture().get_image().save_png(output.path_join("flight-%d.png" % direction)) != OK:
			failures.append("Cannot save flight")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: packaged Archer release origin and tip in both facings")
	quit(0 if failures.is_empty() else 1)
