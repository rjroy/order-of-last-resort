extends Control
## An ink-and-wash battle map. The caller owns all cells, occupants, and rules.

signal cell_selected(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal hover_cleared

const TILE := Vector2(96, 80)
const GUTTER := Vector2(31, 34)
const INK := Color("#282725")
const PARCHMENT := Color("#f5e5bd")
const RIVER := Color("#28474b")
const FOAM := Color("#b4c6ad")
const STONE := Color("#afa087")
const BRIDGE := Color("#beaa89")
const SAFE := Color("#a0a67a")
const SHORE_WASH := Color("#7eac5b", 0.36)
const AMBER := Color("#ffdc86")
const MINT := Color("#d7edbc")
const CORAL := Color("#ffc1a2")
const TILE_FACE := [
	Vector2(2, 2), Vector2(42, 1), Vector2(68, 2), Vector2(91, 1), Vector2(95, 6),
	Vector2(94, 37), Vector2(95, 62), Vector2(91, 78), Vector2(64, 79), Vector2(40, 77),
	Vector2(5, 79), Vector2(1, 75), Vector2(2, 51), Vector2(1, 16),
]

var _cells: Dictionary = {}
var _units: Array = []
var _overlay: Dictionary = {}
var _bounds := Rect2i()
var _hover: Variant = null
var _map_origin := Vector2.ZERO
var _map_scale := 1.0
var _map_size := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)
	mouse_exited.connect(_clear_hover)
	_layout()


## cells: Vector2i -> "stone", "bridge", "broken", "safe", "exit", "obstacle", or "water".
## An absent cell is scenery only. The canvas emits input for supplied cells; it never authorizes moves.
## units: {id, art_key, cell, hp, max_hp, prone}; optional facing (-1 left, 1 right), guarded, objective, variant.
## overlay: selected/chosen_target (Vector2i), targets/impact/threat (arrays of Vector2i),
## paths (each an array of Vector2i), exit (Vector2i), safe (a set of Vector2i),
## and obstacles (id, art_key, position, hp, max_hp).
func set_render_state(cells: Dictionary, units: Array, overlay: Dictionary = {}) -> void:
	_cells = cells.duplicate()
	_units = units.duplicate(true)
	_overlay = overlay.duplicate(true)
	_bounds = Rect2i()
	var first := true
	for value in _cells:
		var cell: Vector2i = value
		var rect := Rect2i(cell, Vector2i.ONE)
		_bounds = rect if first else _bounds.merge(rect)
		first = false
	if _hover != null and not _cells.has(_hover):
		_clear_hover()
	_layout()


func _layout() -> void:
	_map_size = Vector2(_bounds.size) * TILE + GUTTER * 2.0
	_map_scale = minf(size.x / _map_size.x, size.y / _map_size.y)
	_map_origin = (size - _map_size * _map_scale) * 0.5
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell: Variant = cell_at(event.position)
		if cell == null:
			_clear_hover()
		elif cell != _hover:
			_hover = cell
			cell_hovered.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell: Variant = cell_at(event.position)
		if cell != null:
			cell_selected.emit(cell)
			accept_event()


func _clear_hover() -> void:
	if _hover == null:
		return
	_hover = null
	hover_cleared.emit()
	queue_redraw()


## Returns null in the gutter or in a hole in the caller's cell map.
func cell_at(point: Vector2) -> Variant:
	if _map_scale <= 0.0:
		return null
	var local := ((point - _map_origin) / _map_scale - GUTTER) / TILE
	var cell := Vector2i(floori(local.x), floori(local.y)) + _bounds.position
	return cell if _cells.has(cell) else null


func cell_center(cell: Vector2i) -> Vector2:
	return _map_origin + (_tile_origin(cell) + TILE * 0.5) * _map_scale


static func coordinate(cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0:
		return "%d,%d" % [cell.x, cell.y]
	return "%s%d" % [_column_name(cell.x), cell.y + 1]


@warning_ignore("integer_division")
static func _column_name(column: int) -> String:
	if column < 0:
		return str(column)
	var label := ""
	var value := column + 1
	while value > 0:
		value -= 1
		label = String.chr(65 + value % 26) + label
		value /= 26
	return label


func _tile_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell - _bounds.position) * TILE + GUTTER


func _at(point: Vector2, angle := 0.0, local_scale := Vector2.ONE) -> void:
	draw_set_transform(_map_origin + point * _map_scale, angle, local_scale * _map_scale)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#203639"))
	if _map_scale <= 0.0:
		return
	_at(Vector2.ZERO)
	_draw_water()
	var cells := _cells.keys()
	cells.sort_custom(_reading_order)
	for value in cells:
		var cell: Vector2i = value
		_at(_tile_origin(cell))
		_draw_escapement(cell)
	var shore: Dictionary = _overlay.get("safe", {})
	for value in cells:
		var cell: Vector2i = value
		_at(_tile_origin(cell))
		_draw_tile(cell)
		if shore.has(cell):
			_piece(TILE_FACE, SHORE_WASH)
		if _overlay.get("exit") == cell:
			_draw_exit()
	_at(Vector2.ZERO)
	for path in _overlay.get("paths", []):
		_draw_path(path)
	for value in cells:
		var cell: Vector2i = value
		_at(_tile_origin(cell))
		_draw_overlays(cell)
	for obstacle in _overlay.get("obstacles", []):
		if obstacle.hp > 0 and _cells.has(obstacle.position):
			_at(_tile_origin(obstacle.position))
			_draw_object(obstacle)
	var occupants := _units.duplicate()
	occupants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _reading_order(a.cell, b.cell))
	for unit in occupants:
		if _cells.has(unit.cell):
			_draw_unit(unit)
	if not _cells.is_empty():
		_at(Vector2.ZERO)
		_draw_coordinates()


static func _reading_order(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x if a.y == b.y else a.y < b.y


func _draw_water() -> void:
	draw_rect(Rect2(Vector2.ZERO, _map_size), RIVER)
	_rng.seed = 4602
	for y in range(6, int(_map_size.y) - 8, 14):
		for x in range(6, int(_map_size.x) - 8, 35):
			var p := Vector2(x + _rng.randf_range(-5, 5), y + _rng.randf_range(-4, 4))
			var length := minf(_rng.randf_range(11, 67), _map_size.x - p.x - 3)
			var pigment := Color("#688c81") if _rng.randf() > 0.38 else Color("#132f37")
			pigment.a = _rng.randf_range(0.08, 0.27)
			_wash(p, Vector2(length, _rng.randf_range(2, 7)), pigment)
			if _rng.randf() > 0.50:
				var q := p + Vector2(1, 3)
				var pale := Color(FOAM, _rng.randf_range(0.10, 0.24))
				_line([q, q + Vector2(length * 0.28, 0), q + Vector2(length * 0.64, 2),
					q + Vector2(length * 0.87, 1)], pale, _rng.randf_range(0.5, 1.4))
	for y in range(4, int(_map_size.y) - 5, 6):
		for x in range(4, int(_map_size.x) - 5, 9):
			var p := Vector2(x + _rng.randf_range(-3, 3), y + _rng.randf_range(-2, 2))
			draw_line(p, p + Vector2(_rng.randf_range(0.4, 2.8), 0), Color(FOAM, 0.085), 0.65)
	draw_rect(Rect2(Vector2(2, 2), _map_size - Vector2(4, 4)), Color("#7d906f"), false, 1.0)
	draw_rect(Rect2(Vector2(6, 6), _map_size - Vector2(12, 12)), Color("#182f32"), false, 1.0)
	for corner in [Vector2(9, 9), Vector2(_map_size.x - 9, 9),
			Vector2(9, _map_size.y - 9), _map_size - Vector2(9, 9)]:
		var p: Vector2 = corner
		_line([p + Vector2(-3, 0), p + Vector2(0, -3), p + Vector2(3, 0),
			p + Vector2(0, 3), p + Vector2(-3, 0)], Color("#98a47c"), 0.9)


func _draw_escapement(cell: Vector2i) -> void:
	var terrain := str(_cells[cell])
	if not _solid(terrain):
		return
	if not _solid(str(_cells.get(cell + Vector2i.DOWN, ""))):
		var edge := 74.0
		_piece([Vector2(0, edge), Vector2(94, edge), Vector2(96, 85), Vector2(88, 93),
			Vector2(68, 94), Vector2(59, 90), Vector2(37, 95), Vector2(24, 92),
			Vector2(12, 96), Vector2(1, 88)], Color("#534b3d"), Color("#263738"), 1.7)
		_line([Vector2(3, 85), Vector2(16, 88), Vector2(33, 85), Vector2(52, 88),
			Vector2(70, 84), Vector2(94, 85)], Color("#8a7559"), 1.3)
		for x in [11, 25, 40, 58, 70, 89]:
			_line([Vector2(x, 79), Vector2(x - 2, 84), Vector2(x + 1, 91)], Color("#323734"), 1.0)
		_line([Vector2(7, 99), Vector2(24, 96), Vector2(46, 99), Vector2(63, 95)], Color(FOAM, 0.33), 1.0)
		_line([Vector2(47, 103), Vector2(68, 99), Vector2(86, 99)], Color(FOAM, 0.21), 1.1)
	if not _solid(str(_cells.get(cell + Vector2i.RIGHT, ""))):
		_piece([Vector2(91, 0), Vector2(99, 5), Vector2(102, 21), Vector2(97, 40),
			Vector2(101, 62), Vector2(99, 76), Vector2(97, 88), Vector2(89, 81)],
			Color("#6a5d46"), Color("#263738"), 1.4)


func _draw_tile(cell: Vector2i) -> void:
	_rng.seed = hash(cell) + 991
	var terrain := str(_cells[cell])
	if terrain == "water":
		_draw_water_cell()
		return
	if terrain == "broken":
		_draw_broken()
		return
	var base := STONE
	if terrain == "bridge":
		base = BRIDGE
	elif terrain == "safe" or terrain == "exit":
		base = SAFE
	base = base.lerp(INK if _rng.randf() < 0.50 else PARCHMENT, _rng.randf_range(0.02, 0.13))
	_piece(TILE_FACE, base, Color("#514b3e"), 1.3)
	_line([Vector2(4, 7), Vector2(26, 4), Vector2(56, 5), Vector2(88, 4)], Color(PARCHMENT, 0.50), 1.4)
	_line([Vector2(5, 75), Vector2(34, 73), Vector2(62, 76), Vector2(88, 74)], Color(INK, 0.30), 1.3)
	for i in range(12):
		var p := Vector2(_rng.randf_range(5, 72), _rng.randf_range(7, 69))
		var tint := Color(PARCHMENT, _rng.randf_range(0.06, 0.20)) if i % 3 > 0 else Color(INK, 0.11)
		_wash(p, Vector2(_rng.randf_range(7, 18), _rng.randf_range(3, 10)), tint)
	for i in range(28):
		var p := Vector2(_rng.randf_range(6, 90), _rng.randf_range(5, 74))
		draw_line(p, p + Vector2(_rng.randf_range(0.4, 3.5), -0.5), Color(INK, 0.18), 0.8, true)
	match terrain:
		"safe", "exit":
			_draw_safe()
		"obstacle":
			_draw_obstacle()
		_:
			_draw_masonry(terrain == "bridge")


func _draw_water_cell() -> void:
	# A mapped water cell has a faint survey mark; unmapped river has no tile.
	_line([Vector2(4, 15), Vector2(4, 4), Vector2(17, 4)], Color(FOAM, 0.39), 1.0)
	_line([Vector2(79, 76), Vector2(92, 76), Vector2(92, 65)], Color(FOAM, 0.39), 1.0)


func _draw_masonry(bridge: bool) -> void:
	var seam := Color(INK, 0.37)
	var c := _rng.randf_range(25, 47)
	_line([Vector2(1, c + 1), Vector2(22, c - 1), Vector2(49, c + 2), Vector2(72, c),
		Vector2(94, c + 1)], seam, 1.05)
	var split := _rng.randf_range(31, 63)
	_line([Vector2(split, 4), Vector2(split - 2, c - 13), Vector2(split + 2, c + 1)], seam, 1.0)
	_line([Vector2(72, c), Vector2(69, 66), Vector2(73, 75)], Color(INK, 0.22), 0.9)
	if not bridge:
		return
	_piece([Vector2(2, 5), Vector2(20, 2), Vector2(44, 4), Vector2(73, 2), Vector2(93, 4),
		Vector2(93, 11), Vector2(74, 12), Vector2(42, 11), Vector2(22, 13), Vector2(3, 12)],
		Color("#d4bd95"), Color("#766650"), 0.9)
	for x in [21, 44, 73]:
		_line([Vector2(x, 4), Vector2(x - 1, 11)], Color("#766650"), 1.0)
	_line([Vector2(94, 55), Vector2(82, 57), Vector2(76, 64), Vector2(65, 66),
		Vector2(60, 77)], Color("#645644"), 1.25)
	_line([Vector2(77, 62), Vector2(71, 54), Vector2(67, 53)], Color("#645644"), 0.9)


func _draw_broken() -> void:
	_draw_water_cell()
	var chip := _rng.randf_range(-10, 13)
	_piece([Vector2(2, 3), Vector2(37 + chip, 3), Vector2(34 + chip, 10), Vector2(44 + chip, 15),
		Vector2(27, 19), Vector2(24, 31), Vector2(15, 32), Vector2(17, 46),
		Vector2(3, 49)], Color("#a08f74"), Color("#3c4238"), 1.4)
	_piece([Vector2(92, 27), Vector2(94, 75), Vector2(53 + chip * 0.5, 77), Vector2(59 + chip * 0.5, 68),
		Vector2(55, 63), Vector2(70, 58), Vector2(72, 51), Vector2(84, 48), Vector2(80, 41)],
		Color("#8f8069"), Color("#3c4238"), 1.4)
	_line([Vector2(4, 42), Vector2(13, 41), Vector2(12, 29), Vector2(23, 27),
		Vector2(27, 17), Vector2(38 + chip, 14)], Color(FOAM, 0.52), 1.8)
	_line([Vector2(58 + chip * 0.5, 76), Vector2(63 + chip * 0.5, 69), Vector2(61, 63), Vector2(73, 58),
		Vector2(75, 51), Vector2(88, 48)], Color("#dbc6a1"), 1.45)
	_line([Vector2(55, 55), Vector2(63, 51), Vector2(72, 45), Vector2(86, 43)], Color(FOAM, 0.30), 1.0)
	_piece([Vector2(32, 41 + chip), Vector2(38, 36 + chip), Vector2(49, 37 + chip),
		Vector2(46, 47 + chip), Vector2(36, 48 + chip)],
		Color("#698078"), Color("#344a45"), 1.0)
	if chip < 6.0:
		_piece([Vector2(62, 26), Vector2(69, 22), Vector2(74, 25), Vector2(71, 31), Vector2(65, 34)],
			Color("#6f8276"), Color("#344a45"), 1.0)


func _draw_safe() -> void:
	for i in range(12):
		var p := Vector2(_rng.randf_range(5, 65), _rng.randf_range(5, 62))
		_wash(p, Vector2(_rng.randf_range(8, 26), _rng.randf_range(5, 13)), Color("#65794f", 0.25))
	for i in range(10):
		var p := Vector2(_rng.randf_range(10, 86), _rng.randf_range(9, 65))
		_line([p + Vector2(-4, -3), p, p + Vector2(0, -6), p, p + Vector2(4, -4)],
			Color("#596747", 0.85), 0.85)
	_line([Vector2(7, 65), Vector2(26, 58), Vector2(48, 61), Vector2(67, 67), Vector2(89, 61)],
		Color("#d0c69a", 0.54), 2.4)


func _draw_exit() -> void:
	# Shuttered guide lantern and arrow are kept to the left of the unit silhouette.
	draw_circle(Vector2(17, 24), 13.0, Color(AMBER, 0.20), true, -1.0, true)
	_line([Vector2(13, 55), Vector2(12, 20), Vector2(16, 17), Vector2(24, 18)], INK, 3.1)
	_line([Vector2(13, 49), Vector2(13, 27)], Color("#a08a56"), 1.0)
	_piece([Vector2(18, 21), Vector2(25, 21), Vector2(24, 31), Vector2(19, 32)],
		Color("#f8cb66"), INK, 1.1)
	_line([Vector2(21, 22), Vector2(21, 30)], Color("#fff3b8"), 1.1)
	_piece([Vector2(5, 39), Vector2(22, 38), Vector2(27, 43), Vector2(22, 47), Vector2(5, 46)],
		Color("#554f3a"), INK, 1.0)
	_line([Vector2(9, 43), Vector2(21, 43), Vector2(18, 40), Vector2(21, 43), Vector2(18, 45)],
		PARCHMENT, 1.1)
	_caption("EXIT", Vector2(86, 70), MINT, 10)


func _draw_obstacle() -> void:
	_wash(Vector2(14, 62), Vector2(69, 11), Color(INK, 0.38))
	_piece([Vector2(18, 30), Vector2(61, 28), Vector2(65, 60), Vector2(21, 63)],
		Color("#946746"), INK, 1.8)
	_piece([Vector2(61, 28), Vector2(79, 17), Vector2(80, 47), Vector2(65, 60)],
		Color("#6a4c34"), INK, 1.6)
	_piece([Vector2(18, 30), Vector2(37, 18), Vector2(79, 17), Vector2(61, 28)],
		Color("#c09862"), INK, 1.5)
	for y in [37, 46, 54]:
		_line([Vector2(20, y), Vector2(42, y - 2), Vector2(63, y - 3)], Color("#4c3b2e"), 1.15)
		_line([Vector2(63, y - 3), Vector2(79, y - 13)], Color("#4c3b2e"), 1.05)
	_piece([Vector2(21, 55), Vector2(53, 29), Vector2(61, 28), Vector2(64, 34),
		Vector2(29, 61), Vector2(22, 62)], Color("#b58a58"), INK, 1.3)
	_line([Vector2(32, 24), Vector2(54, 24), Vector2(70, 22)], Color("#684a32"), 1.0)
	_line([Vector2(40, 44), Vector2(43, 43), Vector2(47, 42)], Color("#e2b57f"), 1.05)
	_line([Vector2(71, 49), Vector2(76, 43), Vector2(69, 44), Vector2(75, 37)], Color("#3c3129"), 1.15)


func _draw_object(object: Dictionary) -> void:
	match str(object.art_key):
		"obstacle", "crate":
			_draw_obstacle()
	_draw_health(object, false)


static func _solid(terrain: String) -> bool:
	return terrain != "" and terrain != "water" and terrain != "broken"


func _draw_path(path: Array) -> void:
	for index in range(1, path.size()):
		if not _cells.has(path[index - 1]) or not _cells.has(path[index]):
			continue
		var a := _tile_origin(path[index - 1]) + TILE * 0.5
		var b := _tile_origin(path[index]) + TILE * 0.5
		draw_dashed_line(a, b, INK, 5.0, 7.0, true, true)
		draw_dashed_line(a, b, AMBER, 2.0, 7.0, true, true)
		var n := (b - a).normalized()
		var arrow := b - n * 18.0
		_piece([arrow + n * 5.0, arrow - n * 5.0 + n.orthogonal() * 5.0,
			arrow - n * 5.0 - n.orthogonal() * 5.0], AMBER, INK, 1.1)


func _draw_overlays(cell: Vector2i) -> void:
	var threatened: Array = _overlay.get("threat", [])
	var targets: Array = _overlay.get("targets", [])
	var impacts: Array = _overlay.get("impact", [])
	if cell in threatened:
		_brackets(CORAL, 9, 2.0)
		_line([Vector2(72, 17), Vector2(81, 9), Vector2(88, 17), Vector2(81, 25), Vector2(72, 17)], CORAL, 1.8)
	if cell in targets:
		_brackets(MINT, 6, 2.0)
		_piece([Vector2(45, 15), Vector2(50, 10), Vector2(55, 15), Vector2(50, 20)], MINT, INK, 1.15)
	if _overlay.get("chosen_target", null) == cell:
		_brackets(MINT, 2, 2.8)
	if cell in impacts:
		_brackets(CORAL, 5, 2.3)
		_line([Vector2(74, 14), Vector2(83, 23)], INK, 4.2)
		_line([Vector2(83, 14), Vector2(74, 23)], INK, 4.2)
		_line([Vector2(74, 14), Vector2(83, 23)], CORAL, 2.0)
		_line([Vector2(83, 14), Vector2(74, 23)], CORAL, 2.0)
	if _overlay.get("selected", null) == cell:
		_brackets(AMBER, 2, 3.0)
	elif _hover == cell:
		_brackets(PARCHMENT, 3, 1.65)


func _brackets(color: Color, pad: float, weight: float) -> void:
	for corner in [Vector2(0, 0), Vector2(TILE.x, 0), TILE, Vector2(0, TILE.y)]:
		var direction := Vector2(1 if corner.x == 0 else -1, 1 if corner.y == 0 else -1)
		var p: Vector2 = corner + direction * pad
		var points := [p + Vector2(0, direction.y * 16), p, p + Vector2(direction.x * 19, 0)]
		_line(points, INK, weight + 2.5)
		_line(points, color, weight)


func _draw_coordinates() -> void:
	for column in range(_bounds.position.x, _bounds.end.x):
		var x := _tile_origin(Vector2i(column, _bounds.position.y)).x + TILE.x * 0.5
		_axis_mark(_column_name(column), Vector2(x, 25))
	for row in range(_bounds.position.y, _bounds.end.y):
		var y := _tile_origin(Vector2i(_bounds.position.x, row)).y + TILE.y * 0.5 + 4.0
		_axis_mark(str(row + 1) if row >= 0 else str(row), Vector2(17, y))


func _axis_mark(label: String, p: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, p - Vector2(width * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PARCHMENT)


func _caption(label: String, right_baseline: Vector2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := right_baseline - Vector2(width, 0)
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, INK)
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_unit(unit: Dictionary) -> void:
	var role := str(unit.art_key)
	var prone := bool(unit.get("prone", false))
	var origin := _tile_origin(unit.cell)
	var foot := origin + Vector2(49, 62)
	var facing := -1.0 if float(unit.get("facing", -1 if role == "enemy" else 1)) < 0.0 else 1.0
	_at(foot)
	_wash(Vector2(-29, -1), Vector2(59, 9), Color("#24312a", 0.27))
	_wash(Vector2(-22, 0), Vector2(48, 5), Color("#222824", 0.40))
	if bool(unit.get("guarded", false)):
		draw_arc(Vector2(0, -1), 24, PI * 0.07, PI * 0.93, 20, AMBER, 2.0, true)
	if prone:
		_at(foot + Vector2(-28 * facing, -13), 1.43 * facing, Vector2(facing * 0.80, 0.80))
	else:
		_at(foot, 0.0, Vector2(facing * 0.90, 0.90))
	match role:
		"knight":
			_knight()
		"healer":
			_healer()
		"wizard":
			_wizard()
		"ferryman":
			_ferryman()
		_:
			_enemy(str(unit.get("variant", "")))
	_at(origin)
	_draw_health(unit, prone)


func _draw_health(unit: Dictionary, prone: bool) -> void:
	var maximum := maxi(0, int(unit.get("max_hp", 0)))
	var hp := clampi(int(unit.get("hp", maximum)), 0, maximum)
	if maximum > 0:
		var width := 27.0
		var top := Vector2(49 - width * 0.5, 69)
		draw_rect(Rect2(top - Vector2(2, 2), Vector2(width + 4, 7)), INK)
		draw_rect(Rect2(top, Vector2(width, 3)), Color("#725344"))
		var fill := CORAL if hp < maximum and hp * 2 <= maximum else (AMBER if unit.get("objective", false) else MINT)
		draw_rect(Rect2(top, Vector2(width * float(hp) / maximum, 3)), fill)
		if maximum < 9:
			for index in range(1, maximum):
				var x := top.x + width * float(index) / maximum
				draw_line(Vector2(x, top.y), Vector2(x, top.y + 3), INK, 1.0)
	if prone:
		_caption("FALLEN" if hp == 0 else "DOWN", Vector2(85, 19), CORAL, 11)


func _knight() -> void:
	var steel := Color("#969b8e")
	var light := Color("#d1c39e")
	var blue := Color("#4f6b70")
	var brass := Color("#c3a265")
	_piece([Vector2(-14, -47), Vector2(-24, -39), Vector2(-28, -14), Vector2(-33, -7),
		Vector2(-20, -7), Vector2(-13, -12), Vector2(-6, -28)], blue, INK, 1.8)
	_line([Vector2(-22, -34), Vector2(-24, -19), Vector2(-28, -11)], Color("#788684"), 1.3)
	_piece([Vector2(-16, -27), Vector2(-3, -25), Vector2(-4, -14), Vector2(-11, -5),
		Vector2(-6, -3), Vector2(-7, 1), Vector2(-23, 1), Vector2(-23, -4), Vector2(-18, -12)],
		steel, INK, 1.8)
	_piece([Vector2(-1, -25), Vector2(11, -27), Vector2(12, -15), Vector2(8, -9), Vector2(9, -4),
		Vector2(17, -2), Vector2(16, 2), Vector2(2, 2), Vector2(-1, -1)], Color("#74776f"), INK, 1.8)
	_line([Vector2(-21, -4), Vector2(-14, -5), Vector2(-12, -10), Vector2(-17, -11)], light, 1.4)
	_piece([Vector2(-13, -43), Vector2(4, -48), Vector2(13, -41), Vector2(12, -24),
		Vector2(1, -17), Vector2(-14, -24), Vector2(-18, -34)], steel, INK, 1.8)
	_line([Vector2(-10, -30), Vector2(-4, -26), Vector2(4, -25)], Color("#58594f"), 1.4)
	_piece([Vector2(-24, -39), Vector2(-22, -48), Vector2(-16, -51), Vector2(-8, -48),
		Vector2(-3, -40), Vector2(-7, -32), Vector2(-20, -34)], light, INK, 1.7)
	_line([Vector2(-22, -40), Vector2(-17, -44), Vector2(-11, -42), Vector2(-8, -37)], Color("#77796c"), 1.4)
	_piece([Vector2(-9, -51), Vector2(-12, -58), Vector2(-9, -64), Vector2(-3, -65), Vector2(4, -62),
		Vector2(6, -56), Vector2(9, -53), Vector2(6, -49), Vector2(2, -45), Vector2(-4, -47)],
		Color("#cb9c70"), INK, 1.45)
	_piece([Vector2(-12, -54), Vector2(-15, -62), Vector2(-11, -68), Vector2(-4, -70), Vector2(5, -67),
		Vector2(8, -60), Vector2(3, -58), Vector2(-3, -60), Vector2(-8, -55)], steel, INK, 1.6)
	_line([Vector2(-12, -63), Vector2(-5, -66), Vector2(3, -64)], light, 1.3)
	_line([Vector2(-1, -56), Vector2(3, -57), Vector2(5, -55)], INK, 1.15)
	draw_circle(Vector2(3, -54), 0.9, INK, true, -1.0, true)
	_line([Vector2(0, -49), Vector2(3, -51), Vector2(5, -50)], INK, 1.0)
	_piece([Vector2(2, -48), Vector2(15, -50), Vector2(30, -43), Vector2(27, -27),
		Vector2(24, -17), Vector2(14, -9), Vector2(4, -16), Vector2(-2, -26), Vector2(-4, -40)],
		brass, INK, 2.1)
	_piece([Vector2(3, -43), Vector2(14, -46), Vector2(26, -41), Vector2(23, -25), Vector2(19, -17),
		Vector2(14, -13), Vector2(6, -19), Vector2(1, -29), Vector2(0, -39)], blue, Color("#6b644a"), 1.0)
	_line([Vector2(4, -40), Vector2(12, -43), Vector2(21, -40)], Color("#e0c593"), 1.2)
	_line([Vector2(14, -19), Vector2(13, -35), Vector2(14, -39)], brass, 1.5)
	_piece([Vector2(13, -31), Vector2(7, -35), Vector2(9, -28), Vector2(14, -25), Vector2(21, -32),
		Vector2(22, -36), Vector2(17, -34)], brass)
	_line([Vector2(29, -40), Vector2(25, -36), Vector2(25, -32)], Color("#e6c99b"), 1.1)
	for point in [Vector2(2, -45), Vector2(26, -42), Vector2(12, -13), Vector2(2, -22)]:
		draw_circle(point, 1.0, light, true, -1.0, true)


func _healer() -> void:
	var flax := Color("#dfc69a")
	var rose := Color("#a75a48")
	var moss := Color("#66715a")
	var leather := Color("#99704d")
	_piece([Vector2(-15, -25), Vector2(2, -26), Vector2(13, -17), Vector2(8, -7), Vector2(16, -4),
		Vector2(16, 1), Vector2(1, 1), Vector2(-3, -4), Vector2(-2, -14), Vector2(-8, -12),
		Vector2(-11, -3), Vector2(-17, 1), Vector2(-28, 0), Vector2(-27, -4), Vector2(-20, -8)],
		Color("#575446"), INK, 1.7)
	_piece([Vector2(-13, -47), Vector2(-25, -39), Vector2(-24, -28), Vector2(-20, -16), Vector2(-21, -9),
		Vector2(-14, -11), Vector2(-7, -8), Vector2(-3, -12), Vector2(11, -10), Vector2(17, -14),
		Vector2(15, -32), Vector2(13, -43), Vector2(4, -48)], flax, INK, 1.8)
	_piece([Vector2(-17, -38), Vector2(-21, -27), Vector2(-17, -20), Vector2(-18, -11), Vector2(-12, -14),
		Vector2(-10, -36)], Color("#b29971"))
	_piece([Vector2(2, -42), Vector2(11, -39), Vector2(13, -20), Vector2(8, -11), Vector2(-2, -13),
		Vector2(-5, -20), Vector2(-3, -30)], moss, INK, 1.1)
	_line([Vector2(-18, -42), Vector2(-10, -38), Vector2(0, -30), Vector2(7, -17)], Color("#745032"), 3.2)
	_line([Vector2(-17, -42), Vector2(-10, -38), Vector2(1, -30), Vector2(6, -20)], Color("#d7ad6d"), 0.85)
	_piece([Vector2(-15, -52), Vector2(-22, -57), Vector2(-22, -63), Vector2(-16, -66),
		Vector2(-11, -64), Vector2(-7, -59), Vector2(-9, -51)], Color("#3e312a"), INK, 1.4)
	_piece([Vector2(-15, -56), Vector2(-12, -63), Vector2(-4, -66), Vector2(4, -63), Vector2(8, -57),
		Vector2(10, -54), Vector2(6, -51), Vector2(3, -46), Vector2(-4, -47), Vector2(-12, -50)],
		Color("#d1a075"), INK, 1.65)
	_piece([Vector2(-15, -52), Vector2(-18, -60), Vector2(-14, -67), Vector2(-6, -69),
		Vector2(3, -67), Vector2(8, -61), Vector2(2, -61), Vector2(-3, -63), Vector2(-8, -57),
		Vector2(-11, -50)], Color("#43362c"), INK, 1.1)
	_line([Vector2(-14, -62), Vector2(-10, -66), Vector2(-4, -67)], Color("#a27451"), 1.0)
	_line([Vector2(1, -57), Vector2(5, -56)], INK, 1.25)
	_line([Vector2(0, -51), Vector2(4, -51)], Color("#663d2b"), 0.95)
	_piece([Vector2(7, -43), Vector2(12, -43), Vector2(17, -37), Vector2(27, -40), Vector2(30, -36),
		Vector2(19, -28), Vector2(12, -29), Vector2(6, -35)], flax, INK, 1.5)
	_piece([Vector2(25, -39), Vector2(30, -44), Vector2(35, -42), Vector2(35, -37), Vector2(29, -33)],
		Color("#e9d7ae"), INK, 1.15)
	_line([Vector2(30, -42), Vector2(33, -37)], Color("#8c7558"), 0.85)
	_piece([Vector2(-22, -27), Vector2(-5, -30), Vector2(3, -25), Vector2(2, -14),
		Vector2(-2, -8), Vector2(-18, -8), Vector2(-25, -14)], leather, INK, 1.8)
	_piece([Vector2(-24, -28), Vector2(-6, -30), Vector2(3, -25), Vector2(-1, -18), Vector2(-23, -18)],
		Color("#ead2a4"), INK, 1.15)
	_line([Vector2(-12, -27), Vector2(-12, -20)], rose, 2.4)
	_line([Vector2(-16, -24), Vector2(-8, -24)], rose, 2.4)
	_line([Vector2(-21, -14), Vector2(-17, -11), Vector2(-7, -11)], Color("#d2a775"), 1.0)


func _wizard() -> void:
	var plum := Color("#74586c")
	var plum_light := Color("#9a7582")
	var auburn := Color("#af643f")
	var gold := Color("#d4a759")
	_piece([Vector2(-16, -30), Vector2(5, -33), Vector2(11, -20), Vector2(10, -7), Vector2(18, -5),
		Vector2(17, 0), Vector2(4, 2), Vector2(0, -4), Vector2(0, -16), Vector2(-8, -17),
		Vector2(-13, -4), Vector2(-16, 1), Vector2(-28, 0), Vector2(-29, -4), Vector2(-21, -8)],
		Color("#554433"), INK, 1.5)
	_piece([Vector2(-11, -44), Vector2(-19, -43), Vector2(-24, -31), Vector2(-20, -20), Vector2(-28, -8),
		Vector2(-17, -9), Vector2(-13, -13), Vector2(-5, -10), Vector2(0, -12), Vector2(9, -11),
		Vector2(17, -14), Vector2(13, -21), Vector2(10, -36), Vector2(3, -45)], plum, INK, 1.9)
	_line([Vector2(-13, -39), Vector2(-13, -30), Vector2(-12, -25), Vector2(-16, -16)], plum_light, 1.6)
	_line([Vector2(2, -36), Vector2(2, -27), Vector2(7, -17)], Color("#4a3c48"), 1.15)
	_piece([Vector2(-14, -53), Vector2(-20, -47), Vector2(-17, -43), Vector2(-22, -41), Vector2(-16, -38),
		Vector2(-7, -41), Vector2(-5, -38), Vector2(3, -44), Vector2(8, -48), Vector2(7, -54)],
		auburn, INK, 1.5)
	_piece([Vector2(-6, -56), Vector2(1, -59), Vector2(8, -55), Vector2(9, -51), Vector2(12, -49),
		Vector2(8, -46), Vector2(6, -42), Vector2(1, -43), Vector2(-6, -47)], Color("#e6b586"), INK, 1.3)
	_line([Vector2(2, -48), Vector2(5, -46), Vector2(8, -47)], Color("#5f3b34"), 1.1)
	draw_arc(Vector2(6, -52), 3.0, 0, TAU, 12, INK, 1.1, true)
	draw_arc(Vector2(-1, -52), 2.4, 0, TAU, 12, INK, 1.0, true)
	draw_circle(Vector2(7, -52), 0.75, INK, true, -1.0, true)
	_piece([Vector2(-24, -52), Vector2(-28, -55), Vector2(-23, -59), Vector2(-17, -61),
		Vector2(-16, -67), Vector2(-21, -73), Vector2(-28, -70), Vector2(-26, -77),
		Vector2(-19, -80), Vector2(-11, -77), Vector2(0, -64), Vector2(12, -67),
		Vector2(21, -64), Vector2(20, -60), Vector2(12, -57), Vector2(-6, -53), Vector2(-15, -50)],
		plum, INK, 1.8)
	_line([Vector2(-26, -54), Vector2(-15, -55), Vector2(-1, -58), Vector2(18, -62)], plum_light, 1.5)
	_line([Vector2(-17, -62), Vector2(-11, -61), Vector2(-1, -65)], gold, 2.6)
	_line([Vector2(-26, -74), Vector2(-20, -77), Vector2(-13, -75)], Color("#bd917f"), 1.2)
	_piece([Vector2(4, -40), Vector2(10, -43), Vector2(14, -39), Vector2(20, -42), Vector2(21, -49),
		Vector2(26, -50), Vector2(29, -44), Vector2(29, -38), Vector2(20, -31), Vector2(12, -32)],
		plum_light, INK, 1.45)
	_piece([Vector2(22, -48), Vector2(19, -53), Vector2(20, -56), Vector2(24, -54), Vector2(27, -59),
		Vector2(29, -58), Vector2(28, -54), Vector2(32, -57), Vector2(34, -55), Vector2(28, -48)],
		Color("#e6b586"), INK, 1.0)
	_piece([Vector2(-14, -36), Vector2(4, -39), Vector2(11, -29), Vector2(9, -20), Vector2(-9, -20),
		Vector2(-16, -26)], Color("#935e47"), INK, 1.5)
	_line([Vector2(-12, -36), Vector2(-7, -30), Vector2(-8, -22), Vector2(8, -23)], Color("#ddc29a"), 1.35)
	_line([Vector2(-9, -32), Vector2(-1, -34), Vector2(6, -31)], gold, 1.1)
	# A tight, crooked spark rather than a large effect that could look like a preview.
	_line([Vector2(32, -60), Vector2(38, -62), Vector2(37, -68), Vector2(34, -69),
		Vector2(31, -66), Vector2(34, -65)], Color("#f2cb78"), 1.5)


func _ferryman() -> void:
	var ochre := Color("#c89956")
	var dull_gold := Color("#8b673f")
	var linen := Color("#d7c4a2")
	_line([Vector2(-28, -8), Vector2(-33, -38), Vector2(-37, -60)], INK, 4.0)
	_line([Vector2(-28, -8), Vector2(-33, -38), Vector2(-37, -60)], Color("#a17b51"), 1.85)
	_piece([Vector2(-37, -57), Vector2(-40, -61), Vector2(-43, -71), Vector2(-41, -75),
		Vector2(-36, -73), Vector2(-34, -65), Vector2(-35, -58)], Color("#b79a68"), INK, 1.2)
	_piece([Vector2(-11, -23), Vector2(7, -24), Vector2(13, -15), Vector2(10, -6), Vector2(18, -3),
		Vector2(18, 1), Vector2(3, 2), Vector2(-1, -2), Vector2(-2, -12), Vector2(-8, -9),
		Vector2(-12, 1), Vector2(-26, 0), Vector2(-28, -4), Vector2(-20, -8)], Color("#5e5948"), INK, 1.6)
	_piece([Vector2(-12, -49), Vector2(1, -48), Vector2(12, -42), Vector2(17, -32),
		Vector2(13, -19), Vector2(8, -16), Vector2(-6, -13), Vector2(-19, -19), Vector2(-22, -31),
		Vector2(-31, -32), Vector2(-33, -41), Vector2(-26, -45), Vector2(-20, -40)], ochre, INK, 1.8)
	_piece([Vector2(-6, -46), Vector2(3, -43), Vector2(7, -35), Vector2(3, -16), Vector2(-6, -14),
		Vector2(-8, -28), Vector2(-8, -35)], dull_gold, Color("#685039"), 1.05)
	_line([Vector2(-18, -34), Vector2(-16, -29), Vector2(-18, -26), Vector2(-14, -19)], Color("#efd198"), 1.2)
	_line([Vector2(-16, -22), Vector2(-4, -24), Vector2(8, -25), Vector2(14, -23)], Color("#584634"), 2.1)
	_piece([Vector2(-6, -56), Vector2(-2, -61), Vector2(8, -60), Vector2(13, -55), Vector2(12, -51),
		Vector2(16, -48), Vector2(12, -46), Vector2(10, -41), Vector2(1, -42), Vector2(-4, -48)],
		Color("#c69c73"), INK, 1.4)
	_piece([Vector2(-5, -49), Vector2(0, -50), Vector2(3, -45), Vector2(9, -47), Vector2(13, -46),
		Vector2(11, -40), Vector2(5, -36), Vector2(-1, -40)], linen, INK, 1.15)
	_line([Vector2(7, -53), Vector2(11, -52)], INK, 1.1)
	_line([Vector2(3, -43), Vector2(5, -40), Vector2(7, -43)], Color("#8f7d65"), 0.95)
	_piece([Vector2(-11, -55), Vector2(-8, -58), Vector2(-5, -65), Vector2(1, -69), Vector2(10, -65),
		Vector2(13, -58), Vector2(20, -55), Vector2(18, -52), Vector2(8, -54), Vector2(0, -52),
		Vector2(-8, -51)], dull_gold, INK, 1.6)
	_line([Vector2(-8, -56), Vector2(-2, -56), Vector2(7, -58), Vector2(14, -55)], Color("#e0b777"), 1.35)
	_line([Vector2(11, -29), Vector2(17, -25), Vector2(21, -26), Vector2(23, -23), Vector2(18, -20),
		Vector2(8, -23)], INK, 1.35)
	_line([Vector2(-29, -41), Vector2(-33, -44), Vector2(-35, -41), Vector2(-34, -36)],
		linen, 2.3)


func _enemy(variant: String) -> void:
	var rust := Color("#a55447")
	var hide := Color("#826a50")
	var cowl := Color("#495750")
	var iron := Color("#a4a69a")
	var long_reach := variant == "spear" or variant == "rear"
	if long_reach:
		_line([Vector2(-28, -3), Vector2(35, -59)], INK, 4.1)
		_line([Vector2(-28, -3), Vector2(35, -59)], Color("#bea16c"), 1.8)
		_piece([Vector2(31, -57), Vector2(36, -70), Vector2(47, -74), Vector2(42, -63)],
			iron, INK, 1.4)
	else:
		_piece([Vector2(19, -29), Vector2(23, -47), Vector2(32, -53), Vector2(40, -50), Vector2(40, -42),
			Vector2(32, -39), Vector2(24, -26)], iron, INK, 1.65)
		_line([Vector2(28, -45), Vector2(33, -50), Vector2(38, -48)], Color("#ded1aa"), 1.1)
	_piece([Vector2(-17, -27), Vector2(6, -27), Vector2(15, -15), Vector2(14, -8), Vector2(22, -3),
		Vector2(21, 0), Vector2(7, 1), Vector2(4, -3), Vector2(3, -12), Vector2(-7, -15), Vector2(-13, -7),
		Vector2(-12, -2), Vector2(-19, 2), Vector2(-29, 1), Vector2(-29, -3), Vector2(-22, -8)],
		hide, INK, 1.8)
	_piece([Vector2(-16, -48), Vector2(-24, -42), Vector2(-25, -32), Vector2(-18, -27), Vector2(-14, -19),
		Vector2(-1, -17), Vector2(10, -23), Vector2(12, -29), Vector2(23, -28), Vector2(27, -34),
		Vector2(23, -39), Vector2(13, -37), Vector2(8, -48), Vector2(-4, -52)], cowl, INK, 1.9)
	_piece([Vector2(-24, -40), Vector2(-21, -37), Vector2(-26, -32), Vector2(-32, -24), Vector2(-26, -25),
		Vector2(-27, -18), Vector2(-15, -26), Vector2(-12, -33), Vector2(7, -37), Vector2(9, -43),
		Vector2(-2, -45), Vector2(-15, -45)], rust, INK, 1.3)
	_line([Vector2(-27, -29), Vector2(-20, -33), Vector2(-13, -35)], Color("#d48365"), 1.1)
	_piece([Vector2(-12, -49), Vector2(-16, -57), Vector2(-13, -62), Vector2(-5, -66), Vector2(5, -65),
		Vector2(12, -59), Vector2(15, -52), Vector2(11, -49), Vector2(11, -43), Vector2(6, -39),
		Vector2(-4, -42)], cowl, INK, 1.85)
	_line([Vector2(-13, -57), Vector2(-9, -61), Vector2(-2, -63), Vector2(7, -61)], Color("#809283"), 1.4)
	_piece([Vector2(1, -55), Vector2(10, -56), Vector2(12, -51), Vector2(10, -48),
		Vector2(9, -44), Vector2(3, -45), Vector2(-1, -48)], Color("#8e966d"), INK, 1.1)
	_line([Vector2(4, -52), Vector2(9, -53)], Color("#f1d79b"), 1.3)
	_line([Vector2(6, -48), Vector2(10, -48)], INK, 1.0)
	_piece([Vector2(-20, -29), Vector2(-24, -24), Vector2(-20, -18), Vector2(-14, -19),
		Vector2(-11, -26), Vector2(-15, -30)], hide, INK, 1.2)
	_line([Vector2(21, -36), Vector2(23, -31), Vector2(25, -32)], Color("#c6ae82"), 1.55)


# Freehand paths are authored in tile-local coordinates. Each wash is a broad,
# transparent polygon; the boundary and interior marks carry different weights.
func _wash(p: Vector2, extent: Vector2, color: Color) -> void:
	var x := extent.x
	var y := extent.y
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, y * 0.35), p + Vector2(x * 0.19, 0),
		p + Vector2(x * 0.53, y * 0.15), p + Vector2(x * 0.90, y * 0.03), p + Vector2(x, y * 0.46),
		p + Vector2(x * 0.79, y * 0.76), p + Vector2(x * 0.43, y), p + Vector2(x * 0.13, y * 0.80)]), color)


func _piece(points: Array, fill: Color, outline := Color.TRANSPARENT, weight := 1.0) -> void:
	draw_colored_polygon(PackedVector2Array(points), fill)
	if outline.a > 0.0:
		var closed := PackedVector2Array(points)
		closed.append(closed[0])
		draw_polyline(closed, outline, weight, true)


func _line(points: Array, color: Color, weight: float) -> void:
	draw_polyline(PackedVector2Array(points), color, weight, true)
