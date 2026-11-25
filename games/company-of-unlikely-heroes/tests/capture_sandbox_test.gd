extends SceneTree
## Run with SMITH_CAPTURE_SANDBOX and XDG/TMP set as documented in
## capture_sandbox.gd. A stale-profile fixture is created only in scratch;
## the real Godot user profile is never written.

const Guard = preload("res://tests/support/capture_sandbox.gd")


func _initialize() -> void:
	var sandbox := OS.get_environment("SMITH_CAPTURE_SANDBOX")
	var output := sandbox.path_join("captures")
	var data := OS.get_environment("XDG_DATA_HOME")
	var config := OS.get_environment("XDG_CONFIG_HOME")
	var cache := OS.get_environment("XDG_CACHE_HOME")
	var state := OS.get_environment("XDG_STATE_HOME")
	var tmp := OS.get_environment("TMPDIR")
	var actual := OS.get_user_data_dir()
	var failures: Array[String] = []
	if not Guard.validate("SMITH_CAPTURE_SANDBOX", output).is_empty():
		failures.append("real isolated Godot user data must pass")
	if Guard.validate_values("", data, config, cache, state, tmp, actual, output).is_empty():
		failures.append("missing explicit sandbox must fail")
	var real_default := OS.get_environment("HOME").path_join(".local/share/godot/app_userdata/Barnaby's Order of Last Resort")
	if Guard.validate_values(sandbox, data, config, cache, state, tmp, real_default, output).is_empty():
		failures.append("default desktop user data must fail")
	if Guard.validate_values(sandbox, OS.get_environment("HOME").path_join(".local/share"),
			config, cache, state, tmp, actual, output).is_empty():
		failures.append("default desktop XDG data must fail")
	if Guard.validate_values(sandbox, data, config, cache, state, tmp, actual,
			OS.get_environment("HOME")).is_empty():
		failures.append("output outside sandbox must fail")
	var stale := data.path_join("synthetic-stale-profile")
	if DirAccess.dir_exists_absolute(stale) or DirAccess.make_dir_absolute(stale) != OK:
		failures.append("fresh synthetic stale-profile test directory required")
	else:
		var prior := FileAccess.open(stale.path_join("battle_display.cfg"), FileAccess.WRITE)
		if prior == null:
			failures.append("synthetic stale preferences fixture could not be created")
		else:
			prior.store_string("[battle]\nmusic_volume=0.5\n")
			prior.close()
			if Guard.validate_values(sandbox, data, config, cache, state, tmp, stale, output).is_empty():
				failures.append("existing isolated preferences must fail")
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: isolated capture accepted; default desktop profiles rejected without writes")
	quit(0 if failures.is_empty() else 1)
