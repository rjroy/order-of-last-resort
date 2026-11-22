extends Control
## Extends the registered ground without moving the grid.

const BoardPainting := preload("res://presentation/board_painting.gd")
const BridgeArt := preload("res://bridge_art.gd")
const SEAM_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 board_rect = vec4(144.0, 81.0, 992.0, 633.0);
uniform bool quiet_edges = false;
varying vec2 position_on_page;
void vertex() {
	position_on_page = VERTEX;
}
void fragment() {
	vec3 paint = texture(TEXTURE, clamp(UV, vec2(0.001), vec2(0.999))).rgb;
	vec2 excess = max(max(board_rect.xy - position_on_page,
		position_on_page - board_rect.xy - board_rect.zw), vec2(0.0));
	float margin = smoothstep(0.0, 145.0, length(excess));
	vec3 distant_ink = paint * vec3(0.53, 0.47, 0.39) + vec3(0.04, 0.021, 0.013);
	vec3 color = mix(paint, distant_ink, margin * 0.85);
	if (quiet_edges) {
		// Do not stretch the raw texture's edge pixels into a visible band of streaks.
		vec2 edge = min(UV, vec2(1.0) - UV);
		float border = 1.0 - smoothstep(0.008, 0.088, min(edge.x, edge.y));
		float outside_board = smoothstep(0.0, 7.0, length(excess));
		vec3 paper = vec3(0.19, 0.132, 0.086) - vec3(0.038, 0.029, 0.021) * margin;
		color = mix(color, paper, border * outside_board);
	}
	COLOR = vec4(color, 1.0);
}
"""

var _plate: BoardPainting.Plate
var _board_rect := Rect2()
var _seam: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var painting := Shader.new()
	painting.code = SEAM_SHADER
	_seam = ShaderMaterial.new()
	_seam.shader = painting
	material = _seam if _plate != null else null


func set_painting(board_id: String) -> void:
	_plate = BoardPainting.open(board_id) if not board_id.is_empty() else null
	material = _seam if _plate != null else null
	queue_redraw()


func set_quiet_edges(enabled: bool) -> void:
	if _seam != null:
		_seam.set_shader_parameter("quiet_edges", enabled)


func place(board_rect: Rect2) -> void:
	_board_rect = board_rect
	if _seam != null:
		_seam.set_shader_parameter("board_rect",
			Vector4(board_rect.position.x, board_rect.position.y, board_rect.size.x, board_rect.size.y))
	queue_redraw()


func _draw() -> void:
	if _plate == null:
		# The live board still draws its procedural terrain and coordinate labels.
		var upper := Color("#39291c")
		var lower := Color("#281c13")
		var corners := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
		draw_polygon(corners, PackedColorArray([upper, upper, lower, lower]))
		return
	if _board_rect.size.x <= 0.0:
		return
	var logical_map := Vector2(_plate.dimensions) * BridgeArt.TILE + BridgeArt.GUTTER * 2.0
	var quad := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
	var uv := PackedVector2Array()
	for point in quad:
		var logical_point := (point - _board_rect.position) / _board_rect.size * logical_map
		var cell := (logical_point - BridgeArt.GUTTER) / BridgeArt.TILE - Vector2(0.5, 0.5)
		uv.append((_plate.origin + _plate.column * cell.x + _plate.row * cell.y) / _plate.pixels)
	draw_polygon(quad, PackedColorArray([Color.WHITE]), uv, _plate.texture)
