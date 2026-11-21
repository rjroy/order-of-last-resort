extends RefCounted
## Loads unimported PNGs so the art study can run before opening the editor.

const FRAME_SIZE := Vector2i(256, 256)
const FEET := Vector2(128, 216)

var texture: ImageTexture
var frames: Array[Rect2] = []
var end_times: Array[float] = []
var total_seconds := 0.0


func load_files(png_path: String, metadata: Dictionary) -> String:
	var image := Image.new()
	if not FileAccess.file_exists(png_path) or image.load(png_path) != OK:
		return "Cannot load " + png_path
	var anchor: Variant = metadata.get("anchor")
	var raw_frames: Variant = metadata.get("frames")
	if not anchor is Array or anchor.size() != 2 \
			or Vector2(float(anchor[0]), float(anchor[1])) != FEET \
			or not raw_frames is Array or raw_frames.is_empty():
		return "Invalid frame or anchor metadata for " + png_path
	if image.get_size() != Vector2i(FRAME_SIZE.x * raw_frames.size(), FRAME_SIZE.y):
		return "Unexpected strip size for " + png_path
	for index in raw_frames.size():
		var frame: Variant = raw_frames[index]
		var expected := Rect2i(Vector2i(index * FRAME_SIZE.x, 0), FRAME_SIZE)
		var rect: Variant = frame.get("rect") if frame is Dictionary else null
		if not rect is Array or rect.size() != 4 or Rect2i(
				int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])) != expected:
			return "Unexpected frame rectangle for " + png_path
		var duration: float = float(frame.get("duration_ms", 0)) / 1000.0
		if duration <= 0.0:
			return "Missing frame duration for " + png_path
		frames.append(Rect2(expected))
		total_seconds += duration
		end_times.append(total_seconds)
	texture = ImageTexture.create_from_image(image)
	return ""


func frame_at(seconds: float) -> int:
	for index in end_times.size():
		if seconds < end_times[index]:
			return index
	return end_times.size() - 1
