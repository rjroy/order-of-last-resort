extends VBoxContainer

const Layout := preload("res://crossing_layout.gd")
const CrossingView := preload("res://crossing_view.gd")
const TEXT := Color("#f4ead3")
const MUTED := Color("#cfc6aa")
const BRASS := Color("#dfb67a")
const DEMO_EVENTS := [
	[0.55, &"guard"], [3.57, &"heal"], [5.0, &"crate"],
	[5.95, &"select_span"], [6.65, &"span"], [7.65, &"threat"],
	[8.18, &"selection"], [8.72, &"shadows"], [9.14, &"shadows"],
	[9.58, &"span"], [9.58, &"threat"], [9.58, &"selection"], [9.58, &"play_size"],
	[10.12, &"heal"],
]
const STILLS := [[0.4, "crossing-intact"], [1.7, "crossing-guard"],
		[4.35, "crossing-heal"], [7.40, "crossing-open-water"], [10.80, "crossing-play-size"]]

@onready var _board: CrossingView = $Board
@onready var _header: HBoxContainer = $Header
@onready var _footer: VBoxContainer = $Footer

var _buttons: Dictionary[StringName, Button] = {}
var _status: Label
var _scale: Label
var _guard: Button
var _heal: Button
var _crate: Button
var _demo_time := 0.0
var _demo_cursor := 0
var _still_cursor := 0
var _capture_dir := ""
var _registration_file := ""


func _ready() -> void:
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 1)
	_header.add_child(heading)
	var title := _label("Ferryman’s Crossing", 35, TEXT)
	var display_face := SystemFont.new()
	display_face.font_names = ["Noto Serif Display", "Georgia", "serif"]
	display_face.font_weight = 600
	title.add_theme_font_override("font", display_face)
	heading.add_child(title)
	heading.add_child(_label("Replay the poses or pick a tile on either bank.", 16, MUTED))
	var heading_status := VBoxContainer.new()
	heading_status.alignment = BoxContainer.ALIGNMENT_CENTER
	_header.add_child(heading_status)
	var caption := _label("CROSSING ART STUDY", 14, BRASS)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading_status.add_child(caption)
	_scale = _label("", 14, MUTED)
	_scale.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading_status.add_child(_scale)
	_build_footer()
	_board.inspection_changed.connect(_refresh)
	_board.resized.connect(_refresh)
	_refresh()
	var run_demo := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--showcase":
			run_demo = true
		elif arg.begins_with("--capture-dir="):
			_capture_dir = arg.trim_prefix("--capture-dir=")
	if OS.get_cmdline_user_args().has("--registration-check"):
		var raw := OS.get_cmdline_user_args().has("--raw-plate")
		_registration_file = "registration-before" if raw else "registration-after"
		caption.text = "SOURCE PLATE" if raw else "REGISTERED PLATE"
	set_process(run_demo and _board.art_errors.is_empty())
	if run_demo and not _board.art_errors.is_empty():
		push_error("Cannot capture crossing: " + "; ".join(_board.art_errors))
		get_tree().quit(1)


func _build_footer() -> void:
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	_footer.add_child(tools)
	_guard = _add_button(tools, "Replay guard", KEY_G, func() -> void: _board.play_action(_board.KNIGHT))
	_heal = _add_button(tools, "Replay heal", KEY_H, func() -> void: _board.play_action(_board.HEALER))
	_crate = _add_button(tools, "Move crate", KEY_M, func() -> void: _board.move_crate())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	_add_toggle(tools, &"span", "Bridge intact", KEY_B, true, _board.set_span_intact)
	_add_toggle(tools, &"threat", "Threat", KEY_T, true)
	_add_toggle(tools, &"selection", "Selection", KEY_S, true)
	_add_toggle(tools, &"shadows", "Shadows", KEY_V, true)
	_add_toggle(tools, &"play_size", "Play-size check", KEY_P, false)
	var notes := HBoxContainer.new()
	notes.add_theme_constant_override("separation", 14)
	_footer.add_child(notes)
	_status = _label("", 15, TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_child(_status)
	notes.add_child(_label("Illustrative staging · no combat or turns", 14, MUTED))


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _add_button(parent: HBoxContainer, title: String, key: Key, run: Callable) -> Button:
	var button := _make_button(parent, title, key, false)
	button.pressed.connect(run)
	return button


func _add_toggle(parent: HBoxContainer, layer: StringName, title: String, key: Key, value: bool,
		run: Callable = Callable()) -> void:
	var button := _make_button(parent, title, key, true)
	button.set_pressed_no_signal(value)
	if run.is_valid():
		button.toggled.connect(run)
	else:
		button.toggled.connect(func(enabled: bool) -> void: _board.set_display(layer, enabled))
	_buttons[layer] = button


func _make_button(parent: HBoxContainer, title: String, key: Key, toggle: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.toggle_mode = toggle
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_pressed_color", Color("#182821"))
	button.add_theme_color_override("font_hover_pressed_color", Color("#182821"))
	button.add_theme_color_override("font_disabled_color", Color("#a59d8b"))
	var base := Color("#283831") if toggle else Color("#404636")
	button.add_theme_stylebox_override("normal", _button_box(base, Color("#676854")))
	button.add_theme_stylebox_override("hover", _button_box(base.lightened(0.11), BRASS))
	button.add_theme_stylebox_override("pressed", _button_box(Color("#b9d5bb"), Color("#e1eacb")))
	button.add_theme_stylebox_override("hover_pressed", _button_box(Color("#c9e0c5"), TEXT))
	button.add_theme_stylebox_override("disabled", _button_box(Color("#2b3128"), Color("#525341")))
	var focus := _button_box(Color.TRANSPARENT, BRASS, 2)
	button.add_theme_stylebox_override("focus", focus)
	var key_event := InputEventKey.new()
	key_event.keycode = key
	var shortcut := Shortcut.new()
	shortcut.events = [key_event]
	button.shortcut = shortcut
	button.tooltip_text = "%s (%s)" % [title, OS.get_keycode_string(key)]
	parent.add_child(button)
	return button


func _button_box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(4)
	box.content_margin_left = 15.0
	box.content_margin_right = 15.0
	return box


func _refresh() -> void:
	var zoom := _board.board_transform().x.length()
	var cell_width := roundi(Layout.COLUMN.x * zoom)
	var cell_depth := roundi(Layout.ROW.y * zoom)
	_scale.text = "%s  ·  %d × %d px per tile" % [
			"Play-size" if _board.play_size else "Full board", cell_width, cell_depth]
	_buttons[&"span"].text = "Bridge intact" if _board.span_intact else "Bridge absent"
	_guard.disabled = not _board.has_sprite(_board.KNIGHT)
	_heal.disabled = not _board.has_sprite(_board.HEALER)
	_crate.disabled = not _board.has_sprite(_board.CRATE)
	if not _board.art_errors.is_empty():
		_status.text = "; ".join(_board.art_errors)
		return
	var cell := _board.selected
	var picked := "No tile selected"
	if cell != Layout.INVALID:
		var occupant: String = {
			Layout.KNIGHT: "Knight",
			Layout.HEALER: "Healer",
			_board.crate_cell: "Crate",
			Layout.SPAN: "Bridge",
		}.get(cell, "Shore")
		picked = "%s  %s%s" % [
			Layout.address(cell), occupant, " (mark hidden)" if not _board.selection_visible else ""]
	var crate := "Crate at " + Layout.address(_board.crate_cell)
	var threat := "Threat at " + Layout.address(Layout.THREAT) if _board.threat_visible else "Threat hidden"
	_status.text = "%s   ·   %s   ·   %s" % [picked, crate, threat]


func _process(delta: float) -> void:
	_demo_time += delta
	if not _registration_file.is_empty():
		if _demo_time >= 0.4 and _still_cursor == 0:
			_queue_still(_registration_file)
		if _demo_time >= 0.65:
			get_tree().quit()
		return
	while _demo_cursor < DEMO_EVENTS.size() and _demo_time >= DEMO_EVENTS[_demo_cursor][0]:
		var action: StringName = DEMO_EVENTS[_demo_cursor][1]
		match action:
			&"guard": _board.play_action(_board.KNIGHT)
			&"heal": _board.play_action(_board.HEALER)
			&"crate": _board.move_crate()
			&"select_span": _board.select_cell(Layout.SPAN)
			_: _buttons[action].button_pressed = not _buttons[action].button_pressed
		_demo_cursor += 1
	if not _capture_dir.is_empty() and _still_cursor < STILLS.size() and _demo_time >= STILLS[_still_cursor][0]:
		_queue_still(STILLS[_still_cursor][1])
	if _demo_time >= 12.0:
		get_tree().quit()


func _queue_still(name: String) -> void:
	if not _capture_dir.is_empty():
		RenderingServer.frame_post_draw.connect(func() -> void: _write_still(name), CONNECT_ONE_SHOT)
	_still_cursor += 1


func _write_still(name: String) -> void:
	var file := _capture_dir.path_join(name + ".png")
	var image := get_viewport().get_texture().get_image()
	# Wayland fractional scale can yield a larger readback than the review frame.
	var width := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var height := int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	if image.get_size() != Vector2i(width, height):
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)
	var result := image.save_png(file)
	if result != OK:
		push_error("Could not write crossing preview to " + file)
		get_tree().quit(1)
