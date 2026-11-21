extends RefCounted
## One detachable oak deck with low stone sills. All points use D3's grid basis.

const Layout := preload("res://crossing_layout.gd")
const INK := Color("#584633")
const PLANKS := ["#9d7d52", "#ad895b", "#99734b", "#b18e59", "#9f7a4f",
		"#a88761", "#947350", "#ad8557", "#a47c53", "#a9845f", "#9a7950"]

var _canvas: CanvasItem


func paint(canvas: CanvasItem) -> void:
	_canvas = canvas
	# Reflected dark under the boards belongs with the deck, not the base plate.
	for i in 5:
		var edge := 0.44 - i * 0.013
		_fill([[-0.60, -0.18], [0.61, -0.11], [0.63, edge-0.025], [-0.64, edge]],
				Color(0.14, 0.16, 0.14, 0.067))
	for side in [-1.0, 1.0]:
		_stone_sill(side)
	_fill([[-0.58, -0.31], [0.57, -0.30], [0.59, 0.28], [0.56, 0.36],
			[-0.58, 0.38], [-0.60, 0.29]], INK)
	_fill([[-0.58, 0.24], [0.58, 0.23], [0.58, 0.34], [-0.58, 0.36]],
			Color("#74523b"))
	_line([-0.53, 0.34], [0.56, 0.32], Color("#79604a"), 1.8)
	var starts := [-0.575, -0.474, -0.380, -0.275, -0.168, -0.057, 0.048, 0.16,
			0.259, 0.363, 0.463, 0.573]
	for i in PLANKS.size():
		var a: float = starts[i]
		var b: float = starts[i + 1] - 0.006
		var far_edge := -0.288 + 0.016 * sin(i * 2.13)
		var near_edge := 0.273 + 0.023 * cos(i * 2.64)
		var bend := 0.015 * sin(i * 1.79)
		_fill([[a, far_edge], [b, far_edge + 0.010], [b + bend, near_edge - 0.012],
				[a + bend, near_edge]], Color(PLANKS[i]))
		_line([a + 0.009, far_edge + 0.021], [a + bend + 0.013, near_edge - 0.019],
				Color(0.90, 0.75, 0.52, 0.35), 1.25)
		_plank_grain(i, a, b, bend)
		for y in [-0.212, 0.203]:
			var nail_offset := ((i * 7) % 5 - 2) * 0.002
			_canvas.draw_circle(_p([(a + b) / 2.0 + nail_offset, y + nail_offset]),
					1.75, Color("#5d4932"), true, -1, true)
	_canvas = null


func _plank_grain(index: int, a: float, b: float, bend: float) -> void:
	var grain := RandomNumberGenerator.new()
	grain.seed = 47 + 11 * index
	for i in 21:
		var x := grain.randf_range(a + 0.012, b - 0.012)
		var v := grain.randf_range(-0.253, 0.216)
		var h := minf(v + grain.randf_range(0.029, 0.19), 0.24)
		var start := x + bend * smoothstep(-0.27, 0.26, v)
		var end := x + bend * smoothstep(-0.27, 0.26, h)
		var color := Color(0.34, 0.24, 0.14, grain.randf_range(0.15, 0.34))
		if i % 3 == 0:
			color = Color(1.0, 0.83, 0.54, grain.randf_range(0.12, 0.29))
		_line([start, v], [end, h], color, grain.randf_range(0.85, 1.9))


func _stone_sill(side: float) -> void:
	var center := side * 0.56
	_fill([[center-0.15, -0.31], [center+0.12, -0.37], [center+0.16, -0.12],
			[center+0.14, 0.34], [center-0.12, 0.40], [center-0.17, 0.13]], INK)
	_fill([[center-0.15, -0.28], [center+0.097, -0.35], [center+0.136, -0.12],
			[center+0.123, 0.32], [center-0.105, 0.36], [center-0.148, 0.13]],
			Color("#897157"))
	_fill([[center-0.136, -0.23], [center+0.094, -0.326], [center+0.111, -0.17],
			[center+0.049, -0.086], [center-0.115, -0.11]], Color("#ab9270"))
	_fill([[center-0.113, 0.01], [center+0.107, -0.041], [center+0.10, 0.14],
			[center-0.121, 0.17]], Color("#968362"))
	_fill([[center-0.104, 0.177], [center+0.099, 0.153], [center+0.095, 0.278],
			[center-0.075, 0.303]], Color("#9c9076"))
	_line([center-0.115, -0.084], [center+0.065, -0.073], Color("#706b54"), 2.8)
	_line([center-0.100, 0.215], [center+0.021, 0.19], Color("#777c58"), 2.8)
	_line([center-0.109, 0.03], [center-0.063, 0.056], Color("#ad9873"), 2.7)
	_line([center+0.038, 0.316], [center+0.119, 0.285], Color("#665e46"), 2.5)


func _p(point: Array) -> Vector2:
	return Layout.project(Vector2(Layout.SPAN) + Vector2(point[0], point[1]))


func _fill(points: Array, color: Color) -> void:
	var polygon := PackedVector2Array()
	for point: Array in points:
		polygon.append(_p(point))
	_canvas.draw_colored_polygon(polygon, color)


func _line(a: Array, b: Array, color: Color, width: float) -> void:
	_canvas.draw_line(_p(a), _p(b), color, width, true)
