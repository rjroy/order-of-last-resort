extends Control

signal inspection_changed

const Layout := preload("res://crossing_layout.gd")
const SpriteSheet := preload("res://sprite_sheet.gd")
const SpanPaint := preload("res://span_paint.gd")
const RegisteredPlate := preload("res://registered_plate.gdshader")

const KNIGHT := &"knight_guard"
const HEALER := &"healer_ally_heal"
const CRATE := &"crate"
const ART_DIR := "res://assets/"
# The nominal 96 px frame is reached at a 0.60 full-view plate scale.
const SPRITE_TO_PLATE := 0.375 / 0.60
const PLAY_SIZE_SCALE := 65.0 / 184.0
const CRATE_SLIDE_SECONDS := 0.38
const TILE_INK := Color(0.09, 0.13, 0.11, 0.36)
const TILE_LINE_WIDTH := 3.0
const SELECTION_INK := Color("#142f29")
const SELECTION_LIGHT := Color("#c8ffe8")
const DANGER_INK := Color("#52302c")
const DANGER_LIGHT := Color("#ffd2ad")

var art_errors: PackedStringArray
var span_intact := true
var threat_visible := true
var selection_visible := true
var shadows_visible := true
var play_size := false
var selected := Layout.KNIGHT
var hovered := Layout.INVALID
var crate_cell := Layout.CRATE_START

var _plate: ImageTexture
var _plate_surface: Sprite2D
var _span := SpanPaint.new()
var _registration_check := false
var _sheets: Dictionary[StringName, SpriteSheet] = {}
var _action_seconds: Dictionary[StringName, float] = {KNIGHT: -1.0, HEALER: -1.0}
var _crate_from := Layout.CRATE_START
var _crate_time := CRATE_SLIDE_SECONDS


func _ready() -> void:
	_load_art()
	_registration_check = OS.get_cmdline_user_args().has("--registration-check")
	_build_plate_surface()
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_position_plate_surface)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	set_process(false)


func _build_plate_surface() -> void:
	if not _plate:
		return
	_plate_surface = Sprite2D.new()
	_plate_surface.z_index = -1
	_plate_surface.centered = false
	_plate_surface.texture = _plate
	if not OS.get_cmdline_user_args().has("--raw-plate"):
		var registration := ShaderMaterial.new()
		registration.shader = RegisteredPlate
		registration.set_shader_parameter("plate_size", Layout.PLATE_SIZE)
		registration.set_shader_parameter("bridge_contact", Layout.project(Vector2(Layout.SPAN)))
		registration.set_shader_parameter("column_axis", Layout.COLUMN)
		registration.set_shader_parameter("row_axis", Layout.ROW)
		_plate_surface.material = registration
	add_child(_plate_surface)
	_position_plate_surface()


func _position_plate_surface() -> void:
	if _plate_surface:
		var transform := board_transform()
		_plate_surface.position = transform.origin
		_plate_surface.scale = transform.get_scale() * Layout.PLATE_SIZE / _plate.get_size()


func _load_art() -> void:
	var plate_path := ART_DIR + "crossing-plate.png"
	var image := Image.new()
	if FileAccess.file_exists(plate_path) and image.load(plate_path) == OK:
		if absf(float(image.get_width()) / image.get_height() - Layout.PLATE_SIZE.aspect()) < 0.002:
			_plate = ImageTexture.create_from_image(image)
		else:
			art_errors.append("Crossing plate does not match the guide's 3:2 aspect.")
	else:
		art_errors.append("Missing crossing-plate.png")
	var path := ART_DIR + "sprites.json"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
			if FileAccess.file_exists(path) else null
	if not data is Dictionary or not data.get("sprites") is Dictionary:
		art_errors.append("Cannot load sprites.json")
		return
	for actor: StringName in [KNIGHT, HEALER, CRATE]:
		var info: Variant = data.sprites.get(String(actor))
		if not info is Dictionary:
			art_errors.append("No sprite metadata for " + String(actor))
			continue
		var sprite := SpriteSheet.new()
		var error := sprite.load_files(ART_DIR + String(actor) + ".png", info)
		if error.is_empty():
			_sheets[actor] = sprite
		else:
			art_errors.append(error)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = Layout.cell_at(board_transform().affine_inverse() * event.position)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if can_select(hovered) else CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := Layout.cell_at(board_transform().affine_inverse() * event.position)
		if select_cell(cell):
			grab_focus()
			accept_event()
	elif event is InputEventKey and event.pressed:
		var offsets := {KEY_LEFT: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT,
				KEY_UP: Vector2i.UP, KEY_DOWN: Vector2i.DOWN}
		if offsets.has(event.keycode):
			var origin := selected if selected != Layout.INVALID else Layout.KNIGHT
			var target: Vector2i = origin + offsets[event.keycode]
			select_cell(target)
			accept_event()


func _on_mouse_exited() -> void:
	hovered = Layout.INVALID
	queue_redraw()


func board_transform() -> Transform2D:
	var fit := minf(size.x / Layout.PLATE_SIZE.x, size.y / Layout.PLATE_SIZE.y)
	var zoom := minf(fit, PLAY_SIZE_SCALE) if play_size else fit
	return Transform2D(0.0, Vector2.ONE * zoom, 0.0, (size - Layout.PLATE_SIZE * zoom) / 2.0)


func can_select(cell: Vector2i) -> bool:
	return Layout.can_select(cell, span_intact)


func select_cell(cell: Vector2i) -> bool:
	if not can_select(cell):
		return false
	selected = cell
	_changed()
	return true


func set_span_intact(value: bool) -> void:
	span_intact = value
	if not can_select(selected):
		selected = Layout.INVALID
	_changed()


func set_display(layer: StringName, value: bool) -> void:
	match layer:
		&"threat": threat_visible = value
		&"selection": selection_visible = value
		&"shadows": shadows_visible = value
		&"play_size":
			play_size = value
			_position_plate_surface()
	_changed()


func play_action(actor: StringName) -> void:
	if not _sheets.has(actor) or not _action_seconds.has(actor):
		return
	_action_seconds[actor] = 0.0
	select_cell(Layout.KNIGHT if actor == KNIGHT else Layout.HEALER)
	set_process(true)


func move_crate() -> bool:
	if _crate_time < CRATE_SLIDE_SECONDS:
		return false
	var next := Layout.CRATE_END if crate_cell == Layout.CRATE_START else Layout.CRATE_START
	var step := next - crate_cell
	if not can_select(next) or absi(step.x) + absi(step.y) != 1:
		return false
	_crate_from = crate_cell
	crate_cell = next
	_crate_time = 0.0
	if selected == _crate_from:
		selected = crate_cell
	_changed()
	set_process(true)
	return true


func crate_foot() -> Vector2:
	var fraction := clampf(_crate_time / CRATE_SLIDE_SECONDS, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, fraction)
	return Layout.project(Vector2(_crate_from).lerp(Vector2(crate_cell), eased))


func has_sprite(actor: StringName) -> bool:
	return _sheets.has(actor)


func frame_index(actor: StringName) -> int:
	return _sheets[actor].frame_at(_action_seconds.get(actor, 0.0)) if has_sprite(actor) else -1


func _changed() -> void:
	queue_redraw()
	inspection_changed.emit()


func _process(delta: float) -> void:
	var active := false
	for actor: StringName in _action_seconds:
		if _action_seconds[actor] >= 0.0:
			_action_seconds[actor] += delta
			if _action_seconds[actor] >= _sheets[actor].total_seconds:
				_action_seconds[actor] = -1.0
			else:
				active = true
	_crate_time = minf(_crate_time + delta, CRATE_SLIDE_SECONDS)
	queue_redraw()
	set_process(active or _crate_time < CRATE_SLIDE_SECONDS)


func _draw() -> void:
	var pose := board_transform()
	var art_rect := Rect2(Vector2.ZERO, Layout.PLATE_SIZE)
	draw_set_transform_matrix(pose)
	if not _plate_surface:
		draw_rect(art_rect, Color("#30413a"))
	if span_intact and not _registration_check:
		_span.paint(self)
	if _registration_check:
		_draw_registration_marks()
	else:
		_draw_tile_outlines()
		_draw_tactical_marks()
		_draw_entities()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var frame := Rect2(pose.origin, Layout.PLATE_SIZE * pose.x.length()).grow(1.0)
	draw_rect(frame, Color("#68634b") if not has_focus() else SELECTION_LIGHT, false, 1.0)


func _draw_tile_outlines() -> void:
	# Tile centers are integral; continuous boundary lines draw shared edges only once.
	var first := Vector2(-0.5, -0.5)
	var last := Vector2(Layout.GRID_SIZE) + first
	for column in range(Layout.GRID_SIZE.x + 1):
		var x := first.x + column
		draw_line(Layout.project(Vector2(x, first.y)), Layout.project(Vector2(x, last.y)),
				TILE_INK, TILE_LINE_WIDTH, true)
	for row in range(Layout.GRID_SIZE.y + 1):
		var y := first.y + row
		draw_line(Layout.project(Vector2(first.x, y)), Layout.project(Vector2(last.x, y)),
				TILE_INK, TILE_LINE_WIDTH, true)


func _draw_registration_marks() -> void:
	var left := float(Layout.SPAN.x) - 0.5
	var right := float(Layout.SPAN.x) + 0.5
	for x in [left, right]:
		draw_line(Layout.project(Vector2(x, -0.5)), Layout.project(Vector2(x, 4.5)),
				Color("#f4d397"), 2.0, true)
	for y in Layout.GRID_SIZE.y:
		for x in Layout.GRID_SIZE.x:
			var cell := Vector2i(x, y)
			var point := Layout.project(Vector2(cell))
			var wet := cell.x == Layout.SPAN.x
			var ink := DANGER_LIGHT if wet else SELECTION_LIGHT
			draw_circle(point, 8.0, SELECTION_INK, true, -1.0, true)
			draw_circle(point, 4.0, ink, true, -1.0, true)
			draw_string(get_theme_default_font(), point + Vector2(13, 6), Layout.address(cell),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)


func _draw_tactical_marks() -> void:
	if threat_visible:
		var area := _cell_outline(Layout.THREAT, 0.40)
		draw_colored_polygon(area, Color(0.59, 0.24, 0.14, 0.31))
		_outline(area, DANGER_INK, DANGER_LIGHT, 2.4)
		var c := Vector2(Layout.THREAT)
		for x in [-0.37, -0.25, -0.13, -0.01, 0.11, 0.23]:
			var a := Layout.project(c + Vector2(x, 0.388))
			var b := Layout.project(c + Vector2(x + 0.105, 0.248))
			draw_line(a, b, DANGER_INK, 4.0, true)
			draw_line(a, b, DANGER_LIGHT, 2.0, true)
	if can_select(hovered) and (hovered != selected or not selection_visible):
		_outline(_cell_outline(hovered, 0.44), SELECTION_INK, Color("#b9dfcc"), 1.7)
	if selection_visible and can_select(selected):
		var corners := _cell_outline(selected, 0.44)
		draw_colored_polygon(corners, Color(0.13, 0.58, 0.44, 0.13))
		for i in corners.size():
			var corner := corners[i]
			var before := corner.lerp(corners[posmod(i - 1, 4)], 0.24)
			var after := corner.lerp(corners[(i + 1) % 4], 0.24)
			var segment := PackedVector2Array([before, corner, after])
			draw_polyline(segment, SELECTION_INK, 8.0, true)
			draw_polyline(segment, SELECTION_LIGHT, 3.8, true)


func _cell_outline(cell: Vector2i, inset: float) -> PackedVector2Array:
	var c := Vector2(cell)
	return PackedVector2Array([Layout.project(c + Vector2(-inset, -inset)),
			Layout.project(c + Vector2(inset, -inset)), Layout.project(c + Vector2(inset, inset)),
			Layout.project(c + Vector2(-inset, inset))])


func _outline(polygon: PackedVector2Array, dark: Color, light: Color, width: float) -> void:
	var edges := polygon.duplicate()
	edges.append(edges[0])
	draw_polyline(edges, dark, width + 3.0, true)
	draw_polyline(edges, light, width, true)


func _draw_entities() -> void:
	var feet := {
		KNIGHT: Layout.project(Vector2(Layout.KNIGHT)),
		HEALER: Layout.project(Vector2(Layout.HEALER)),
		CRATE: crate_foot(),
	}
	var actors := feet.keys()
	actors.sort_custom(func(a: StringName, b: StringName) -> bool: return feet[a].y < feet[b].y)
	# Do not paint a later actor's shadow over an earlier actor's body.
	if shadows_visible:
		for actor: StringName in actors:
			if has_sprite(actor):
				_draw_shadow(feet[actor], Vector2(29, 11) if actor == CRATE else Vector2(26, 8))
	for actor: StringName in actors:
		if not has_sprite(actor):
			continue
		var sheet := _sheets[actor]
		var anchor := feet[actor] as Vector2
		var top_left := anchor - SpriteSheet.FEET * SPRITE_TO_PLATE
		var destination := Rect2(top_left, Vector2(SpriteSheet.FRAME_SIZE) * SPRITE_TO_PLATE)
		draw_texture_rect_region(sheet.texture, destination, sheet.frames[frame_index(actor)])


func _draw_shadow(anchor: Vector2, radius: Vector2) -> void:
	# Soft projection and tighter contact core drift independently from the sprite outline.
	for layer in 9:
		var t := float(layer) / 8.0
		var center := anchor + Vector2(7.0, 3.5).lerp(Vector2(2.4, 1.0), t)
		var extent := radius * lerpf(1.34, 0.46, t)
		var ellipse := PackedVector2Array()
		for point in 28:
			ellipse.append(center + Vector2.from_angle(TAU * point / 28.0) * extent)
		draw_colored_polygon(ellipse, Color(0.10, 0.11, 0.11, lerpf(0.033, 0.126, t)))
