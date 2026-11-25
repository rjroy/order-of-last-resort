extends "res://tests/support/scene_fixture.gd"

# Run graphically with --script res://tests/presentation/launch_diagnostic_scene_test.gd.
# Add -- --capture-dir=/absolute/existing/directory to save the long case.
const WRONG_PARTY := "Mission 'bridge_patrol' needs exactly 3 party heroes; received 2."
const PARTY_HINT := "Use --party=<hero,...> in deployment order."
const LAST_BOARD := "last_board_[img]literal[/img]"


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "Launch diagnostic scene requires a graphical display")
		_finish()
		return
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	await _launch_error_view(["--mission=bridge_patrol", "--party=knight,wizard"])
	var detail := _page_detail()
	_check(detail != null and detail.get_parsed_text() == WRONG_PARTY + "\n" + PARTY_HINT
		and _reachable(detail), "Wrong party size shows the real error and literal syntax on separate lines")
	var unavailable := ProjectSettings.globalize_path("user://missing_launch_test_%d_[[img]].json" % OS.get_process_id())
	await _launch_error_view(["--content=" + unavailable])
	detail = _page_detail()
	_check(detail != null and detail.get_parsed_text().begins_with("Could not open the content file")
		and unavailable in detail.get_parsed_text() and _reachable(detail), "Missing external path is displayed literally")
	await _long_content_error()
	_finish()


func _long_content_error() -> void:
	var path := ProjectSettings.globalize_path("user://launch_diagnostic_%d_%d.json" % [
		OS.get_process_id(), Time.get_ticks_usec()])
	var boards := {}
	boards["invalid_long_id_" + "single_token_".repeat(14)] = 0
	for index in 14:
		boards["invalid_test_board_%02d" % index] = 0
	boards[LAST_BOARD] = 0
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "Write the test-owned invalid catalog")
		return
	file.store_string(JSON.stringify({"boards": boards}))
	file.close()
	var catalog = load("res://content/catalog.gd")
	var expected: String = catalog.read_source(path).get("error", "")
	_check(expected.count("\n") > 20 and LAST_BOARD in expected, "The actual validator returns a long multi-line error")
	await _launch_error_view(["--content=" + path])
	var detail := _page_detail()
	_check(detail != null and detail.get_parsed_text() == expected and detail.accessibility_name == expected
		and not detail.bbcode_enabled,
		"All validator text, newlines and bracket-shaped literals remain intact")
	var scroll := _node("LaunchErrorTextScroll") as ScrollContainer
	if _reachable(scroll) and detail != null:
		var bar := scroll.get_v_scroll_bar()
		_check(bar.max_value > bar.page and detail.size.x <= scroll.size.x,
			"Long content wraps inside its bounded, vertically scrollable page")
		await _capture("long-content-launch-error")
		await _key(KEY_TAB)
		_check(bar.has_focus() and _reachable(bar), "Tab reaches the visible diagnostic scrollbar")
		await _key(KEY_DOWN)
		_check(scroll.scroll_vertical > 0, "The keyboard scrolls through the diagnostic")
		scroll.scroll_vertical = int(ceilf(bar.max_value - bar.page))
		await process_frame
		_check(detail.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1.0,
			"Scrolling to the bottom exposes the diagnostic's last line")
	else:
		_check(false, "Long diagnostic viewport is visible and in bounds")
	_check(DirAccess.remove_absolute(path) == OK, "Remove test-owned invalid catalog")


func _launch_error_view(args: Array[String]) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(args))
	viewport.add_child(scene)
	for frame in 5:
		await process_frame
	_check(scene.current_screen() == "error", "Invalid startup opens the launch error page")
	var page: Control = scene.get("_screen_root")
	_check(_reachable(page) and page.find_children("*", "BaseButton", true, false).is_empty(),
		"Launch error is within the viewport and offers no in-game fix")


func _page_detail() -> RichTextLabel:
	return _node("LaunchErrorText") as RichTextLabel


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
