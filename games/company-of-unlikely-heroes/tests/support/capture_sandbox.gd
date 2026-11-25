extends RefCounted
## Test-only guard for live capture programs that write user preferences.
## A new sandbox must be inside this checkout's ignored .lore/local directory.
## From the repository root, create one before launching Godot:
##   s=$(mktemp -d "$PWD/.lore/local/capture.XXXXXX")
##   mkdir -p "$s"/{data,config,cache,state,tmp,captures}
##   export SMITH_CAPTURE_SANDBOX="$s" XDG_DATA_HOME="$s/data"
##   export XDG_CONFIG_HOME="$s/config" XDG_CACHE_HOME="$s/cache"
##   export XDG_STATE_HOME="$s/state" TMPDIR="$s/tmp"
## Pass "$s/captures" as the capture script's output directory.


static func validate(sandbox_env: String, output: String) -> String:
	return validate_values(OS.get_environment(sandbox_env), OS.get_environment("XDG_DATA_HOME"),
		OS.get_environment("XDG_CONFIG_HOME"), OS.get_environment("XDG_CACHE_HOME"),
		OS.get_environment("XDG_STATE_HOME"), OS.get_environment("TMPDIR"),
		OS.get_user_data_dir(), output)


static func validate_values(sandbox: String, data: String, config: String, cache: String,
		state: String, tmp: String, user_data: String, output: String) -> String:
	var local := ProjectSettings.globalize_path("res://").path_join("../../.lore/local").simplify_path()
	sandbox = sandbox.simplify_path()
	if not sandbox.is_absolute_path() or not sandbox.begins_with(local + "/") \
			or not DirAccess.dir_exists_absolute(sandbox) or _has_link(sandbox):
		return "Capture sandbox must be a real directory under this checkout's .lore/local"
	for pair in [[data, "data"], [config, "config"], [cache, "cache"],
			[state, "state"], [tmp, "tmp"]]:
		var value: String = pair[0]
		if not value.is_absolute_path() or value.simplify_path() != sandbox.path_join(pair[1]) \
				or not DirAccess.dir_exists_absolute(value) or _has_link(value):
			return "Capture XDG/TMP directories must be real sandbox/data, config, cache, state and tmp"
	user_data = user_data.simplify_path()
	if not user_data.is_absolute_path() or not user_data.begins_with(data.simplify_path() + "/") \
			or _has_link(user_data):
		return "Actual Godot user data directory must be inside the sandbox data directory"
	if FileAccess.file_exists(user_data.path_join("battle_display.cfg")):
		return "Capture user preferences already exist; use a fresh sandbox"
	var user_dir := DirAccess.open(user_data)
	if user_dir == null or not user_dir.get_files().is_empty():
		return "Godot user data must be a fresh sandbox profile"
	for folder in user_dir.get_directories():
		if folder not in ["logs", "objectdb_snapshots", "shader_cache"] or _has_link(user_data.path_join(folder)):
			return "Godot user data must be a fresh sandbox profile"
	output = output.simplify_path()
	if not output.is_absolute_path() or not output.begins_with(sandbox + "/") \
			or not DirAccess.dir_exists_absolute(output) or _has_link(output):
		return "Capture output must be a real directory inside the sandbox"
	return ""


static func _has_link(path: String) -> bool:
	var root := DirAccess.open("/")
	var current := ""
	for part in path.split("/", false):
		current += "/" + part
		if root.is_link(current):
			return true
	return false
