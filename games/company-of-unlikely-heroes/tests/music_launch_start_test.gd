extends SceneTree
## From the repository root, after the normal Godot import:
## sandbox=$(mktemp -d /tmp/opencode/olr-music-launch.XXXXXX)
## OLR_TEST_SANDBOX="$sandbox" XDG_DATA_HOME="$sandbox" godot --headless --path games/company-of-unlikely-heroes --script res://tests/music_launch_start_test.gd
##
## Run each launch in its own verbose child process. The music service logs
## "Playing background music" immediately after AudioStreamPlayer.play(), so
## the first such log records actual playback, including starts within _ready.
## Looking at the player after the first frame would miss transient starts.

const START_LOG := "Playing background music "
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sandbox := OS.get_environment("OLR_TEST_SANDBOX")
	if sandbox.is_empty() or not sandbox.is_absolute_path() \
			or OS.get_environment("XDG_DATA_HOME") != sandbox \
			or not OS.get_user_data_dir().begins_with(sandbox.trim_suffix("/") + "/") \
			or FileAccess.file_exists("user://battle_display.cfg"):
		push_error("Set OLR_TEST_SANDBOX and XDG_DATA_HOME to the same fresh absolute directory.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if "--probe=standalone" in args:
		await _probe(true)
		return
	if "--probe=guild" in args:
		await _probe(false)
		return
	_check_launch("standalone", "res://assets/music/road")
	_check_launch("guild", "res://assets/music/main")
	for failure in failures:
		push_error("FAIL: music_launch_start_test: " + failure)
	if failures.is_empty():
		print("PASS: music_launch_start_test")
	quit(0 if failures.is_empty() else 1)


func _check_launch(mode: String, expected: String) -> void:
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--verbose", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/music_launch_start_test.gd", "--", "--probe=" + mode,
	]), output, true)
	if exit_code != 0:
		failures.append("%s probe exited %d: %s" % [mode, exit_code, "\n".join(output)])
		return
	var starts: Array[String] = []
	for line in str(output[0]).split("\n"):
		var offset := line.find(START_LOG)
		if offset >= 0:
			starts.append(line.substr(offset + START_LOG.length()).strip_edges().trim_suffix("."))
	if starts.is_empty():
		failures.append(mode + " probe did not observe any actual music playback start")
	elif starts[0].get_base_dir() != expected:
		failures.append("%s first played %s, expected %s; starts: %s" % [mode, starts[0], expected, starts])


func _probe(standalone: bool) -> void:
	var game: Node = load("res://main.tscn").instantiate()
	game.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]) if standalone else PackedStringArray())
	# A normal fresh guild launch must not read or migrate a real player profile.
	game.configure_profile_path("user://music_launch_probe_%d.json" % OS.get_process_id())
	root.add_child(game)
	await process_frame
	var expected_screen := "battle" if standalone else "guild_creation"
	var player := game.find_child("MusicPlayer", true, false) as AudioStreamPlayer
	var valid: bool = game.current_screen() == expected_screen and player != null and player.playing \
		and player.stream is AudioStream and player.stream.get_length() > 1.0
	game.queue_free()
	await process_frame
	quit(0 if valid else 1)
