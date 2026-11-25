extends SceneTree

# Launched by test_guild_location.py with an isolated HOME and XDG directories.
# Exercise the same main scene and user arguments as a normal game launch.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Fail before instantiating the game if Godot ignored the isolated XDG home.
	if OS.get_user_data_dir().simplify_path() != OS.get_environment("TEST_EXPECTED_USER_DIR").simplify_path():
		printerr("Refusing to launch with unexpected user data directory: " + OS.get_user_data_dir())
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-migrate="):
			var migration_path := arg.trim_prefix("--probe-migrate=")
			var result: Dictionary = load("res://guild/guild_profile.gd").migrate_location(migration_path)
			print("GUILD_LOCATION_PROBE=" + JSON.stringify({"migration": result}))
			quit()
			return
	var scene = load("res://main.tscn").instantiate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-profile="):
			scene.configure_profile_path(arg.trim_prefix("--probe-profile="))
	root.add_child(scene)
	await process_frame
	await process_frame
	var initial_screen: String = scene.current_screen()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-create=") and initial_screen == "guild_creation":
			var input := scene.find_child("GuildName", true, false) as LineEdit
			var button := scene.find_child("CreateGuild", true, false) as Button
			if input != null and button != null:
				input.text = arg.trim_prefix("--probe-create=")
				input.text_changed.emit(input.text)
				if not button.disabled:
					button.pressed.emit()
					await process_frame
	var profile: Dictionary = scene.get("_guild_profile")
	var path: String = scene.get("_profile_path")
	if "--probe-renew" in OS.get_cmdline_user_args() and not profile.is_empty() and not profile.has("error"):
		profile = load("res://guild/guild_profile.gd").renew(path, profile, 987654)
	print("GUILD_LOCATION_PROBE=" + JSON.stringify({
		"user_dir": ProjectSettings.globalize_path("user://"),
		"path": ProjectSettings.globalize_path(path),
		"initial_screen": initial_screen,
		"screen": scene.current_screen(),
		"profile": profile,
	}))
	quit()
