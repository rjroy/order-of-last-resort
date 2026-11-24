extends Node
## Persistent music playback, separate from effects and gameplay randomness.

const Playlist = preload("res://presentation/music_playlist.gd")
const MUSIC_ROOT := "res://assets/music"
const SETS := ["main", "road", "destination"]
const GAIN_DB := -14.0

var _rng := RandomNumberGenerator.new()
var _playlists := {}
var _current_set := ""
var _player: AudioStreamPlayer


func _ready() -> void:
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.volume_db = GAIN_DB
	add_child(_player)
	_player.finished.connect(_play_next)
	for set_name in SETS:
		var directory := MUSIC_ROOT.path_join(set_name)
		var tracks: Array = []
		# ResourceLoader sees imported resources in exported packs, unlike
		# DirAccess enumeration of the original loose source files.
		for filename in ResourceLoader.list_directory(directory):
			if filename.get_extension().to_lower() == "mp3":
				var path := directory.path_join(filename)
				if ResourceLoader.exists(path, "AudioStream"):
					tracks.append(path)
		tracks.sort()
		if tracks.is_empty():
			push_warning("No background music found in %s." % directory)
		_playlists[set_name] = Playlist.new(tracks, _rng)


func set_context(set_name: String) -> void:
	if set_name == _current_set:
		return
	if not _playlists.has(set_name):
		push_warning("Unknown background music set: %s." % set_name)
		return
	print_verbose("Changing background music from %s to %s." % [_current_set, set_name])
	_current_set = set_name
	_player.stop()
	_play_next()


func _play_next() -> void:
	var path: Variant = _playlists[_current_set].next_track() if _playlists.has(_current_set) else null
	if path == null:
		_player.stream = null
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Could not load background music %s." % path)
		return
	_player.stream = stream
	_player.play()
	print_verbose("Playing background music %s." % path)
