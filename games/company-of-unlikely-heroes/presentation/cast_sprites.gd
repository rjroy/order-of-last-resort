extends RefCounted
## Reads packaged atlases. Frames and release offsets share the same source-pixel space.

const MANIFEST := "res://assets/cast/manifest.json"
const DEFAULT_DISPLAY_SCALE := 0.333333

static var _textures: Dictionary[String, Texture2D] = {}

class Clip:
	var path: String
	var anchor: Vector2
	var scale: float
	var loop: bool
	var total_ms := 0.0
	var frames: Array[Rect2] = []
	var frame_ends: Array[float] = []
	var source_frames: Array[int] = []
	var release_ms := -1.0
	var release_offset := Vector2.ZERO
	var release_clip := ""
	var tip: Variant = null

	func frame_index(at_ms: float) -> int:
		var sample := fposmod(at_ms, total_ms) if loop else maxf(0.0, at_ms)
		return mini(frame_ends.bsearch(sample, false), frames.size() - 1)

	func time_at_source_frame(source_frame: int) -> float:
		var index := source_frames.bsearch(source_frame)
		return 0.0 if index == 0 else frame_ends[index - 1]

var _actors: Dictionary = {}


func load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary or not data.get("actors") is Dictionary:
		push_warning("Invalid cast sprite manifest: " + MANIFEST)
		return
	var display_scale := _scale(data, DEFAULT_DISPLAY_SCALE)
	for role in data.actors:
		var actor: Variant = data.actors[role]
		if not actor is Dictionary or not actor.get("clips") is Dictionary:
			continue
		var clips := {}
		for key in actor.clips:
			var parsed := _parse_clip(actor.clips[key], _scale(actor, display_scale))
			if parsed != null:
				clips[key] = parsed
			else:
				push_warning("Invalid cast sprite clip: %s.%s" % [role, key])
		_actors[role] = clips


func clip_for(role: String, key: String) -> Clip:
	return _actors.get(role, {}).get(key)


func paint(canvas: CanvasItem, clip: Clip, frame_index: int) -> bool:
	if clip == null:
		return false
	var texture := load_texture(clip.path)
	if texture == null:
		return false
	var source := clip.frames[frame_index]
	if not Rect2(Vector2.ZERO, texture.get_size()).encloses(source):
		return false
	var destination := Rect2(-clip.anchor * clip.scale, source.size * clip.scale)
	canvas.draw_texture_rect_region(texture, destination, source)
	return true


static func load_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var texture: Texture2D
	if FileAccess.file_exists(path):
		# A source checkout does not require a prior Godot editor import.
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			texture = ImageTexture.create_from_image(image)
	elif ResourceLoader.exists(path, "Texture2D"):
		texture = load(path) as Texture2D
	_textures[path] = texture
	if texture == null:
		push_warning("Could not load board texture: " + path)
	return texture


static func _parse_clip(data: Variant, default_scale: float) -> Clip:
	if not data is Dictionary or not data.get("path") is String \
			or not _numbers(data.get("anchor"), 2) or not data.get("frames") is Array \
			or data.frames.is_empty():
		return null
	var clip := Clip.new()
	clip.path = data.path if data.path.begins_with("res://") else MANIFEST.get_base_dir().path_join(data.path)
	clip.anchor = Vector2(float(data.anchor[0]), float(data.anchor[1]))
	if _numbers(data.get("tip"), 2):
		clip.tip = Vector2(float(data.tip[0]), float(data.tip[1]))
	clip.scale = _scale(data, default_scale)
	clip.loop = bool(data.get("loop", false))
	for frame in data.frames:
		if not frame is Dictionary or not _numbers(frame.get("rect"), 4) \
				or not _number(frame.get("duration_ms")) or frame.duration_ms <= 0.0:
			return null
		var rect := Rect2(float(frame.rect[0]), float(frame.rect[1]), float(frame.rect[2]), float(frame.rect[3]))
		if rect.position.x < 0 or rect.position.y < 0 or rect.size.x <= 0 or rect.size.y <= 0:
			return null
		clip.frames.append(rect)
		clip.source_frames.append(int(frame.get("source_frame", 0)))
		clip.total_ms += float(frame.duration_ms)
		clip.frame_ends.append(clip.total_ms)
	var release: Variant = data.get("release")
	if release is Dictionary and _number(release.get("time_ms")) \
			and release.time_ms >= 0.0 and release.time_ms < clip.total_ms \
			and _numbers(release.get("offset"), 2) and release.get("clip") is String:
		clip.release_ms = float(release.time_ms)
		clip.release_offset = Vector2(float(release.offset[0]), float(release.offset[1]))
		clip.release_clip = release.clip
	return clip


static func _scale(config: Dictionary, fallback: float) -> float:
	var value: Variant = config.get("display_scale")
	return float(value) if _number(value) and value > 0.0 else fallback


static func _numbers(values: Variant, count: int) -> bool:
	if not values is Array or values.size() != count:
		return false
	for value in values:
		if not _number(value):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
