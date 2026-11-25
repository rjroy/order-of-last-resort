extends "res://tests/support/scene_fixture.gd"
## Run with OLR_TEST_SANDBOX and XDG_DATA_HOME set to the same fresh absolute directory.
## Victories are controlled committed results, not a test of combat strategy.

const Adventure = preload("res://expedition/adventure.gd")
const PARTY := ["knight", "healer", "wizard"]
const MAIN := "res://assets/music/main/"
const ROAD := "res://assets/music/road/"
const DESTINATION := "res://assets/music/destination/"
const Playlist = preload("res://presentation/audio/music_playlist.gd")
var profile_path := "user://music_scene_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
var road_stream: AudioStream
var seek_marker := 0.0


func _run() -> void:
	var sandbox := OS.get_environment("OLR_TEST_SANDBOX")
	if sandbox.is_empty() or not sandbox.is_absolute_path() \
			or OS.get_environment("XDG_DATA_HOME") != sandbox \
			or not OS.get_user_data_dir().begins_with(sandbox.trim_suffix("/") + "/") \
			or FileAccess.file_exists("user://battle_display.cfg") \
			or FileAccess.file_exists(profile_path) or FileAccess.file_exists(profile_path + ".backup"):
		push_error("Set OLR_TEST_SANDBOX and XDG_DATA_HOME to the same fresh absolute directory.")
		quit(1)
		return
	root.add_child(viewport)
	viewport.size = VIEWPORT_SIZE
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(profile_path)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	_check(scene.current_screen() == "guild_creation", "Fresh guild creation opens")
	_music(MAIN, "Guild creation")
	var name_input := _node("GuildName") as LineEdit
	if name_input == null:
		await _cleanup()
		return
	name_input.text = "Music Test"
	name_input.text_changed.emit(name_input.text)
	await process_frame
	await _press("CreateGuild")
	_check(scene.current_screen() == "battle", "Founding starts practice")
	_music(ROAD, "Practice is a mission")
	await _press("SkipPractice")
	_check(scene.current_screen() == "commissions", "Skipping practice returns to guild")
	_music(MAIN, "Guild after practice")
	await _press("Commission_0")
	for id in PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	_check(scene.current_screen() == "routes", "First reports precede first battle")
	_music(MAIN, "First reports before the first mission")
	await _press("Route_0")
	_check(scene.current_screen() == "battle", "Selected road starts")
	var road := _music(ROAD, "First road")
	if road != null:
		# Inject a test-owned singleton bag into the real service, rather than
		# assuming the shipped road set will always contain just one track.
		var service := scene.find_child("BackgroundMusic", true, false)
		var playlists: Dictionary = service.get("_playlists")
		var original = playlists["road"]
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		playlists["road"] = Playlist.new([road.stream.resource_path], rng)
		var singleton_stream := road.stream
		road.stop()
		road.finished.emit()
		await process_frame
		_check(road.playing and road.stream == singleton_stream,
			"Natural completion replays the singleton road track")
		playlists["road"] = original
		road_stream = road.stream
		seek_marker = minf(10.0, road.stream.get_length() * 0.4)
		road.seek(seek_marker)
		await process_frame
		await _sfx_independence(road)
	var count := 0
	while scene.current_screen() == "battle" and count < 5:
		var run: Dictionary = scene.get("_run")
		var final := int(run.mission_index) == Adventure.mission_count(run) - 1
		if final:
			_music(DESTINATION, "Actual final battle")
			break
		await _settle_victory()
		if scene.current_screen() == "debrief":
			_same_road(road, "Victory reward debrief")
			var reward: BaseButton
			for id in PARTY:
				var candidate := _node("Reward_" + id) as BaseButton
				if candidate != null and candidate.is_visible_in_tree() and not candidate.disabled:
					reward = candidate
					break
			if reward != null:
				await _press(str(reward.name))
				_same_road(road, "Claimed reward debrief")
			var continuation := _node("ContinueAdventure") as BaseButton
			if continuation == null or continuation.disabled:
				_check(false, "Reward debrief can continue")
				break
			await _press("ContinueAdventure")
		if scene.current_screen() == "routes":
			_same_road(road, "Intervening route choices")
			await _press("Route_0")
		run = scene.get("_run")
		if scene.current_screen() == "battle" and int(run.mission_index) < Adventure.mission_count(run) - 1:
			_same_road(road, "Next road battle")
		count += 1
	var run: Dictionary = scene.get("_run")
	if scene.current_screen() == "battle" and int(run.mission_index) == Adventure.mission_count(run) - 1:
		await _settle_victory()
		_check(scene.current_screen() == "result", "Final victory opens result")
		await _press("ReturnToGuild")
		_check(scene.current_screen() == "commissions", "Return opens guild")
		_music(MAIN, "Returning to guild")
	else:
		_check(false, "The commission reaches the actual finale")
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	_check(scene.current_screen() == "battle", "Standalone launch starts battle")
	_music(ROAD, "Standalone mission is road, not a commission finale")
	await _cleanup()


func _settle_victory() -> void:
	var result: Dictionary = scene.battle_snapshot()
	# Use an already-completed test objective while retaining this mission's
	# catalog, party and identity. This isolates presentation from combat AI.
	result.objective = {"handler": "defeat_all", "team": "__music_test_no_team"}
	result.outcome = "victory"
	result["_terminal_commit"] = true
	var run: Dictionary = scene.get("_run")
	var settled: Dictionary = Adventure.settle_mission(run, result)
	_check(settled.get("phase") != "mission", "Controlled committed victory settles")
	scene.set("_run", settled)
	scene.call("_show_settled_mission")
	await process_frame


func _music(directory: String, label: String) -> AudioStreamPlayer:
	var matches: Array[AudioStreamPlayer] = []
	for candidate in scene.find_children("*", "AudioStreamPlayer", true, false):
		if candidate.stream is AudioStream and candidate.stream.resource_path.get_base_dir() + "/" == directory and candidate.playing:
			matches.append(candidate)
	_check(matches.size() == 1, label + ": one real playing music stream")
	if matches.size() != 1:
		return null
	var player := matches[0]
	_check(player.stream.get_length() > 1.0, label + ": imported stream has audio duration")
	return player


func _same_road(original: AudioStreamPlayer, label: String) -> void:
	var current := _music(ROAD, label)
	if original != null and current != null:
		_check(current == original, label + ": persistent player is not replaced")
		_check(current.stream == road_stream, label + ": same road track continues")
		_check(current.get_playback_position() >= seek_marker * 0.5, label + ": track did not restart")


func _sfx_independence(road: AudioStreamPlayer) -> void:
	var service := scene.find_child("SoundEffects", true, false)
	if service == null:
		_check(false, "Sound effects service exists")
		return
	service.set_volume(0.0)
	_check(road.playing, "Muting effects does not stop music")
	service.set_volume(0.8)
	service.planning("knight")
	var effects := service.find_children("*", "AudioStreamPlayer", true, false)
	_check(not effects.is_empty() and effects.back().playing, "Effects play independently over music")
	_check(road.playing, "Playing an effect does not stop music")


func _cleanup() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	for path in [profile_path, profile_path + ".backup"]:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
				"Remove test-owned profile " + path)
	_finish()
