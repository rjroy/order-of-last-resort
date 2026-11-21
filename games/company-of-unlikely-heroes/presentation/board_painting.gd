extends RefCounted
## Resolves an authored ground texture without needing a Godot editor import.

const MANIFEST := "res://assets/boards/manifest.json"

static var _manifest_checked := false
static var _boards: Dictionary = {}

class Plate:
	var texture: Texture2D
	var dimensions: Vector2i
	var pixels: Vector2
	var origin: Vector2
	var column: Vector2
	var row: Vector2

	func draw(canvas: CanvasItem, extent: Vector2, gutter: Vector2, tile: Vector2) -> void:
		var points := PackedVector2Array([Vector2.ZERO, Vector2(extent.x, 0), extent, Vector2(0, extent.y)])
		var uv := PackedVector2Array()
		for point in points:
			var cell := (point - gutter) / tile - Vector2(0.5, 0.5)
			uv.append((origin + cell.x * column + cell.y * row) / pixels)
		canvas.draw_polygon(points, PackedColorArray([Color.WHITE]), uv, texture)


static func open(board_id: String) -> Plate:
	if not _manifest_checked:
		_manifest_checked = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) \
			if FileAccess.file_exists(MANIFEST) else null
		if data is Dictionary and data.get("version") == 1 and data.get("boards") is Dictionary:
			_boards = data.boards
		else:
			push_warning("Board paintings unavailable: " + MANIFEST)

	var entry: Variant = _boards.get(board_id)
	if not entry is Dictionary:
		return null
	var file: Variant = entry.get("file")
	var fit: Variant = entry.get("registration")
	if not file is String or file != file.get_file() or file.get_extension() != "png" \
			or not fit is Dictionary or not _pair(entry.get("pixels")) \
			or not _pair(entry.get("board_dimensions")) or not _pair(fit.get("a1_center_px")) \
			or not _pair(fit.get("column_px")) or not _pair(fit.get("row_px")):
		push_warning("Invalid board painting entry: " + board_id)
		return null

	var plate := Plate.new()
	plate.pixels = _vector(entry.pixels)
	plate.dimensions = Vector2i(_vector(entry.board_dimensions))
	plate.origin = _vector(fit.a1_center_px)
	plate.column = _vector(fit.column_px)
	plate.row = _vector(fit.row_px)
	if minf(plate.pixels.x, plate.pixels.y) <= 0.0 \
			or mini(plate.dimensions.x, plate.dimensions.y) <= 0 \
			or is_zero_approx(plate.column.cross(plate.row)):
		push_warning("Invalid board painting registration: " + board_id)
		return null

	var path := MANIFEST.get_base_dir().path_join(file)
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			plate.texture = ImageTexture.create_from_image(image)
	elif ResourceLoader.exists(path, "Texture2D"):
		plate.texture = load(path) as Texture2D
	if plate.texture == null or plate.texture.get_size() != plate.pixels:
		push_warning("Could not load registered board painting: " + path)
		return null
	print_verbose("Loaded registered board painting: " + path)
	return plate


static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 \
		and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int)


static func _vector(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))
