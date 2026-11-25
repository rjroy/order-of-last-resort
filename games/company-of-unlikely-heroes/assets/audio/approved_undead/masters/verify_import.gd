extends SceneTree

const ASSETS := "res://assets/audio/approved_undead/"
const CUES := [
	"grave_bell", "raise_dead", "ring_of_sparks", "say_hello_to_that_one",
	"skeleton_dont_go", "skeleton_wave", "summon_skeleton", "wasnt_me",
	"zombie_offer_flower", "zombie_say_hello",
]
const SETTINGS := {
	"force/8_bit": false,
	"force/mono": false,
	"force/max_rate": false,
	"edit/trim": false,
	"edit/normalize": false,
	"edit/loop_mode": 0,
	"edit/loop_begin": 0,
	"edit/loop_end": -1,
	"compress/mode": 0,
}


func _initialize() -> void:
	for cue: String in CUES:
		var path := ASSETS + cue + ".wav"
		var failure := _verify(path, 3 if cue == "wasnt_me" else 2)
		if not failure.is_empty():
			push_error(path + ": " + failure)
			quit(1)
			return
	var imported := DirAccess.get_files_at("res://.godot/imported")
	for child in DirAccess.get_files_at(ASSETS + "masters/originals"):
		if not child.ends_with(".wav"):
			continue
		if FileAccess.file_exists(ASSETS + "masters/originals/" + child + ".import"):
			push_error("Master has an import sidecar: " + child)
			quit(1)
			return
		for artifact in imported:
			if artifact.begins_with(child + "-"):
				push_error("Master was imported: " + child)
				quit(1)
				return
	print("10 AudioStreamWAV imports match source PCM; no masters imported.")
	quit()


func _verify(path: String, width: int) -> String:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK or config.get_value("deps", "source_file", "") != path:
		return "missing or mismatched import sidecar"
	for setting in SETTINGS:
		if config.get_value("params", setting, null) != SETTINGS[setting]:
			return "incorrect import setting: " + setting
	var stream := ResourceLoader.load(path, "AudioStreamWAV") as AudioStreamWAV
	if stream == null:
		return "AudioStreamWAV did not load"
	if stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.mix_rate != 44100 \
			or not stream.stereo or stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return "incorrect imported audio format"
	var source := FileAccess.get_file_as_bytes(path)
	if source.size() < 12 or source.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or source.slice(8, 12).get_string_from_ascii() != "WAVE":
		return "invalid source WAV"
	var cursor := 12
	while cursor + 8 <= source.size():
		var name := source.slice(cursor, cursor + 4).get_string_from_ascii()
		var size := source.decode_u32(cursor + 4)
		var start := cursor + 8
		var end := start + size
		if end > source.size():
			return "truncated WAV chunk"
		if name == "data":
			var expected := source.slice(start, end)
			if width == 3:
				# Godot stores the high 16 bits of each PCM24 sample.
				var pcm16 := PackedByteArray()
				pcm16.resize(size / 3 * 2)
				for i in range(0, size, 3):
					var j := i / 3 * 2
					pcm16[j] = expected[i + 1]
					pcm16[j + 1] = expected[i + 2]
				expected = pcm16
			if stream.data != expected:
				return "imported PCM differs from source"
			return ""
		cursor = end + size % 2
	return "missing WAV data chunk"
