extends Control
## Noninteractive marks drawn in the same space as the live tactical board.

const BridgeArt := preload("res://bridge_art.gd")
const CastSprites := preload("res://presentation/cast_sprites.gd")
const GRAPHITE := Color("#44392e")
const PAPER := Color("#f5dfaa")
const DARK := Color("#2b1e17")
const GOLD := Color("#f5c779")
const STAMP_SHADER := """
shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float light = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	vec3 charcoal = mix(vec3(0.17, 0.13, 0.11), vec3(0.73, 0.62, 0.46), light);
	float grain = 0.14 * step(0.82, fract((FRAGCOORD.x + FRAGCOORD.y) / 3.8));
	COLOR = vec4(charcoal, base.a * (0.82 - light * 0.40 - grain));
}
"""

var _board: BridgeArt
var _cues: Dictionary = {}
var _stamp := Node2D.new()
var _prop_layer := Node2D.new()
var _props: Dictionary = {}
var _draw_coordinates := false
var _cast := CastSprites.new()


func mount(board: Control) -> void:
	_board = board as BridgeArt
	assert(_board != null, "Storybook ink requires the live BridgeArt board.")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 3
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.resized.connect(_redraw)
	_cast.load_manifest()
	var shader := Shader.new()
	shader.code = STAMP_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_stamp.material = material
	_stamp.z_index = -1
	_stamp.draw.connect(_draw_stamp)
	add_child(_stamp)
	# Keep props owned by the ink node while rendering them below the figures.
	# Moving the whole board to a replay viewport must not tear this layer down.
	_board.move_child(self, 0)
	# Cancel the ink's lift relative to the board, not relative to the root.
	_prop_layer.z_index = -z_index
	_prop_layer.draw.connect(_draw_props)
	add_child(_prop_layer)


func render(cues: Dictionary) -> void:
	_cues = cues.duplicate(true)
	_sync_gate_art()
	_redraw()


func set_scene_props(props: Dictionary) -> void:
	_props = props.duplicate(true)
	_sync_gate_art()
	_redraw()


func set_scenery_coordinates(enabled: bool) -> void:
	_draw_coordinates = enabled
	queue_redraw()


func _notification(what: int) -> void:
	# Unparenting the ink itself is different from reparenting its whole board.
	if what != NOTIFICATION_UNPARENTED or not is_instance_valid(_board):
		return
	if _board.resized.is_connected(_redraw):
		_board.resized.disconnect(_redraw)
	if not _board.is_queued_for_deletion():
		_board.set_pressure_gate_prop_installed(false)
	_board = null


func _sync_gate_art() -> void:
	if is_instance_valid(_board) and _board.has_method("set_pressure_gate_prop_installed"):
		_board.call("set_pressure_gate_prop_installed", not _actual_gate_prop().is_empty())


func _redraw() -> void:
	queue_redraw()
	_stamp.queue_redraw()
	_prop_layer.queue_redraw()


func _step() -> Vector2:
	return _board.cell_center(Vector2i.ONE) - _board.cell_center(Vector2i.ZERO)


func _draw() -> void:
	if not is_instance_valid(_board):
		return
	var step := _step()
	if minf(step.x, step.y) < 1.0:
		return
	if _draw_coordinates:
		_coordinates(step)
	var context_cell: Variant = _cues.get("context_cell")
	var context_text: String = _cues.get("context_text", "")
	for mark: Dictionary in _cues.get("landmarks", []):
		if mark.get("cell") is Vector2i:
			var label: String = mark.get("label", "")
			if not context_text.is_empty() and context_cell == mark.cell:
				if mark.get("kind") == "plate":
					context_text = "Move to plate"
				label = ""
			var kind: String = mark.get("kind", "")
			_landmark(_board.cell_center(mark.cell), step, kind, label, _prop(kind).is_empty())
	var actual: Dictionary = _cues.get("gate_actual", {})
	if actual.get("cell") is Vector2i:
		_actual_gate(_board.cell_center(actual.cell), step, actual.get("open", false), _actual_gate_prop().is_empty())
	var selected: Variant = _cues.get("selected_cell")
	if selected is Vector2i:
		_selection(_board.cell_center(selected), step)
	var focus: Variant = _cues.get("focus_cell")
	if focus is Vector2i:
		_keyboard_focus(_board.cell_center(focus), step)
	var move: Dictionary = _cues.get("move", {})
	if move.get("from") is Vector2i and move.get("to") is Vector2i:
		_move(_board.cell_center(move.from), _board.cell_center(move.to), step)
	var gate: Dictionary = _cues.get("gate", {})
	if gate.get("cell") is Vector2i:
		_gate(_board.cell_center(gate.cell), step, gate.get("opens", false))
	if context_cell is Vector2i and not context_text.is_empty():
		var target := _board.cell_center(context_cell)
		_tag(context_text, target + Vector2(0.0, -step.y * 0.67), true)


func _coordinates(step: Vector2) -> void:
	var font := get_theme_default_font()
	for x in 7:
		var point := _board.cell_center(Vector2i(x, 0)) - Vector2(5.0, step.y * 0.60)
		_coordinate(font, String.chr(65 + x), point)
	for y in 5:
		var point := _board.cell_center(Vector2i(0, y)) - Vector2(step.x * 0.65, -4.0)
		_coordinate(font, str(y + 1), point)


func _coordinate(font: Font, text: String, point: Vector2) -> void:
	draw_string_outline(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(DARK, 0.9))
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PAPER)


func _prop(kind: String) -> Dictionary:
	var prop: Dictionary = _props.get(kind, {})
	if not prop.get("texture") is Texture2D or not prop.get("anchor") is Vector2 or not prop.get("size") is Vector2:
		return {}
	var dimensions: Vector2 = prop.size
	return prop if minf(dimensions.x, dimensions.y) > 0.0 else {}


func _actual_gate_prop() -> Dictionary:
	var gate: Dictionary = _cues.get("gate_actual", {})
	if not gate.get("cell") is Vector2i:
		return {}
	return _prop("gate_open" if gate.get("open", false) else "gate_closed")


func _draw_props() -> void:
	var step := _step()
	if minf(step.x, step.y) < 1.0:
		return
	for mark: Dictionary in _cues.get("landmarks", []):
		var kind: String = mark.get("kind", "")
		var prop := _prop(kind)
		if prop.is_empty() or not mark.get("cell") is Vector2i:
			continue
		var foot := _board.cell_center(mark.cell)
		if kind == "plate":
			foot.y += step.y * 0.25
		_paint_prop(prop, foot, step)
	var gate := _actual_gate_prop()
	if not gate.is_empty():
		_paint_prop(gate, _board.cell_center(_cues.gate_actual.cell), step)


func _paint_prop(prop: Dictionary, point: Vector2, step: Vector2) -> void:
	var dimensions: Vector2 = prop.size * (step.y / 108.0)
	_prop_layer.draw_texture_rect(prop.texture, Rect2(point - prop.anchor * dimensions, dimensions), false)


func _landmark(center: Vector2, step: Vector2, kind: String, label: String, fallback: bool) -> void:
	var foot := center + Vector2(0.0, step.y * 0.25)
	if kind == "plate" and fallback:
		var rim := PackedVector2Array()
		for index in range(24):
			var angle := TAU * index / 24.0
			rim.append(foot + Vector2(cos(angle) * step.x * 0.22, sin(angle) * step.y * 0.11))
		draw_colored_polygon(rim, Color("#6e563a"))
		rim.append(rim[0])
		draw_polyline(rim, DARK, 4.0, true)
		draw_polyline(rim, Color("#c8a56d"), 1.9, true)
		var enamel := Color("#dcb777")
		var shape := PackedVector2Array([Vector2(-0.06, 0), Vector2(0, -0.044),
			Vector2(0.06, 0), Vector2(0, 0.044), Vector2(-0.06, 0)])
		for index in shape.size():
			shape[index] = foot + step * shape[index]
		draw_polyline(shape, enamel, 1.7, true)
	elif kind == "exit" and fallback:
		var size_unit := minf(step.x, step.y)
		var pole := center + Vector2(-0.06, 0.12) * step
		var tip := pole - Vector2(0, size_unit * 0.40)
		var flag := PackedVector2Array([tip, tip + Vector2(size_unit * 0.22, 0.035 * size_unit),
			tip + Vector2(size_unit * 0.17, 0.093 * size_unit), tip + Vector2(size_unit * 0.22, 0.15 * size_unit),
			tip + Vector2(0, 0.13 * size_unit)])
		draw_colored_polygon(flag, GOLD)
		flag.append(flag[0])
		draw_polyline(flag, DARK, 2.2, true)
		draw_line(tip, pole, DARK, 2.5, true)
	elif kind != "plate" and kind != "exit":
		return
	# The plate tag goes into the tile's upper corner, away from occupants' feet.
	var marker := center + step * (Vector2(-0.31, -0.40) if kind == "plate" else Vector2(0.06, 0.25))
	_marker("Plate" if kind == "plate" and label == "Pressure plate" else label, marker)


func _actual_gate(center: Vector2, step: Vector2, open: bool, fallback: bool) -> void:
	if not fallback:
		_marker("Gate open" if open else "Gate shut", center - Vector2(step.x * 0.35, step.y * 0.38))
		return
	# Leave the renderer's handle/panel in place; add two solid posts and an
	# unmistakable passage line. Do not use the graphite palette for actual state.
	var half := Vector2(step.x * 0.17, step.y * 0.28)
	for edge: float in [-1.0, 1.0]:
		var y := center.y + edge * half.y
		var corners := PackedVector2Array([Vector2(center.x - half.x, y - 3),
			Vector2(center.x - half.x + 19, y - 5), Vector2(center.x + half.x, y - 2),
			Vector2(center.x + half.x - 2, y + 4), Vector2(center.x - half.x + 2, y + 4)])
		draw_colored_polygon(corners, Color("#55402c"))
		corners.append(corners[0])
		draw_polyline(corners, Color("#251b13"), 2.3, true)
		draw_line(corners[0], corners[2], Color("#c6a278"), 1.15, true)
	if not open:
		var center_bar := Rect2(center - Vector2(half.x * 0.61, half.y * 0.81),
			Vector2(half.x * 1.22, half.y * 1.62))
		draw_rect(center_bar, Color("#473222"))
		for cross: float in [0.24, 0.5, 0.75]:
			var y := center_bar.position.y + center_bar.size.y * cross
			draw_line(Vector2(center_bar.position.x + 2, y), Vector2(center_bar.end.x - 2, y - 3),
				Color("#b38e65"), 1.8, true)
	_marker("Gate open" if open else "Gate shut", center - Vector2(step.x * 0.23, step.y * 0.32))


func _marker(text: String, point: Vector2) -> void:
	if text.is_empty():
		return
	var font := get_theme_default_font()
	var font_size := 14
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var rect := Rect2(point - Vector2(width * 0.5 + 6, 9), Vector2(width + 12, 20))
	draw_rect(rect, Color("#33251a"))
	draw_rect(rect, Color("#bd9b62"), false, 1.0)
	draw_string(font, point + Vector2(-width * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PAPER)


func _selection(center: Vector2, step: Vector2) -> void:
	var foot := center + Vector2(0, step.y * 0.24)
	var marks := PackedVector2Array()
	for point in range(25):
		var angle := TAU * point / 24.0
		marks.append(foot + Vector2(cos(angle) * step.x * 0.30, sin(angle) * step.y * 0.15))
	draw_polyline(marks, DARK, 4.0, true)
	draw_polyline(marks, GOLD, 2.0, true)


func _keyboard_focus(center: Vector2, step: Vector2) -> void:
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := center + corner * (step * 0.5 - Vector2(7, 7))
		var line := PackedVector2Array([p - Vector2(15 * corner.x, 0), p, p - Vector2(0, 15 * corner.y)])
		draw_polyline(line, DARK, 6.0, true)
		draw_polyline(line, PAPER, 2.75, true)


func _move(source: Vector2, destination: Vector2, step: Vector2) -> void:
	var direction := source.direction_to(destination)
	if direction.is_zero_approx():
		return
	var offset := Vector2(0.0, step.y * 0.15)
	var trim := minf(step.x, step.y) * 0.25
	var start := source + direction * trim + offset
	var tip := destination - direction * trim + offset
	draw_dashed_line(start, tip, Color(PAPER, 0.74), 4.5, 5.0, true, true)
	draw_dashed_line(start, tip, Color(GRAPHITE, 0.96), 2.2, 5.0, true, true)
	var wing := direction.orthogonal() * 5.0
	var head := PackedVector2Array([tip - direction * 9.0 + wing, tip, tip - direction * 9.0 - wing])
	draw_polyline(head, Color(PAPER, 0.8), 4.0, true)
	draw_polyline(head, GRAPHITE, 1.8, true)
	draw_arc(destination + Vector2(0, step.y * 0.26), step.y * 0.14, 0.35, PI - 0.35,
		16, Color(GRAPHITE, 0.68), 1.7, true)


func _draw_stamp() -> void:
	if not is_instance_valid(_board):
		return
	var move: Dictionary = _cues.get("move", {})
	if not move.get("to") is Vector2i:
		return
	var clip := _cast.clip_for(move.get("cast_key", ""), "ready")
	if clip == null:
		return
	var step := _step()
	if minf(step.x, step.y) < 1.0:
		return
	var pivot := _board.cell_center(move.to) + Vector2(1.0 / 96.0, 22.0 / 80.0) * step
	var scale := step.y / 80.0
	_stamp.draw_set_transform(pivot, 0.0, Vector2(scale, scale))
	_cast.paint(_stamp, clip, 0)


func _gate(center: Vector2, step: Vector2, opens: bool) -> void:
	var hinge := center + Vector2(-0.02, -0.29) * step
	var bottom := center + Vector2(-0.02, 0.31) * step
	var leaf := step * (Vector2(0.38, -0.13) if opens else Vector2(0.12, 0.04))
	var far_top := hinge + leaf
	var far_bottom := bottom + leaf
	var outline := PackedVector2Array([hinge, far_top, far_bottom, bottom, hinge])
	draw_polyline(outline, Color(PAPER, 0.42), 5.2, true)
	draw_polyline(outline, Color(GRAPHITE, 0.78), 2.0, true)
	for segment in [0.20, 0.44, 0.68, 0.88]:
		draw_line(hinge.lerp(far_top, segment), bottom.lerp(far_bottom, segment),
			Color(GRAPHITE, 0.63), 1.65, true)
	if opens:
		var sweep := PackedVector2Array()
		for index in range(13):
			var angle := lerpf(PI * 0.45, -0.05, index / 12.0)
			sweep.append(bottom + Vector2(cos(angle) * step.x * 0.43, sin(angle) * step.y * 0.17))
		for index in range(0, sweep.size() - 1, 2):
			draw_line(sweep[index], sweep[index + 1], PAPER, 2.1, true)
	var label := "Opens while plate is held" if opens else "Closes when plate is empty"
	_tag(label, center + Vector2(0.70, -0.56) * step, false)


func _tag(text: String, point: Vector2, parchment: bool) -> void:
	var font := get_theme_default_font()
	var font_size := 16
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var outer := minf(width + 24.0, size.x - 12.0)
	if outer <= 24.0:
		return
	var x := clampf(point.x, outer * 0.5 + 6.0, size.x - outer * 0.5 - 6.0)
	var y := maxf(point.y, 25.0)
	var rect := Rect2(Vector2(x - outer * 0.5, y - 23.0), Vector2(outer, 28.0))
	if parchment:
		var left := rect.position.x
		var right := rect.end.x
		var top := rect.position.y
		var edge := PackedVector2Array([Vector2(left + 4, top + 1), Vector2(right - 8, top),
			Vector2(right, top + 6), Vector2(right - 3, y + 3), Vector2(x + 7, y + 4),
			Vector2(x, y + 11), Vector2(x - 6, y + 4), Vector2(left + 3, y + 5), Vector2(left, top + 9)])
		draw_colored_polygon(edge, PAPER)
		edge.append(edge[0])
		draw_polyline(edge, DARK, 1.45, true)
	var start := Vector2(rect.position.x + 12, y - 3)
	if not parchment:
		draw_string_outline(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, outer - 16, font_size, 4, DARK)
	draw_string(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, outer - 16, font_size,
		DARK if parchment else PAPER)
