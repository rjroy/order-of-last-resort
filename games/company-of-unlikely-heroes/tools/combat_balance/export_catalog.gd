extends SceneTree

const Catalog = preload("res://content/catalog.gd")


func _initialize() -> void:
	var output := ""
	var catalog_path: String = Catalog.DEFAULT_PATH
	var seen := {}
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		if key not in ["--out", "--catalog"] or not arg.begins_with(key + "="):
			_fail("Unknown argument: %s" % arg)
			return
		if seen.has(key):
			_fail("Duplicate argument: %s" % key)
			return
		seen[key] = true
		var value := arg.substr(key.length() + 1)
		if value.is_empty():
			_fail("Empty value for %s" % key)
			return
		if key == "--out":
			output = value
		else:
			catalog_path = value
	if output.is_empty():
		_fail("Missing required --out=<new file> argument.")
		return
	if FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output):
		_fail("Output already exists: %s" % output)
		return

	var loaded := Catalog.read_source(catalog_path)
	if loaded.has("error"):
		_fail("Catalog load failed: %s" % loaded.error)
		return
	var definitions: Dictionary = loaded.definitions
	var profiles := {}
	for id in definitions.characters:
		profiles[id] = Catalog.profile(definitions, id)
	var text := JSON.stringify({"definitions": definitions, "profiles": profiles}, "", false)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		_fail("Could not serialize catalog JSON: %s" % parser.get_error_message())
		return

	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		_fail("Could not open output \"%s\": %s" % [output, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		_fail("Could not write output \"%s\": %s" % [output, error_string(error)])
		return
	print("Exported catalog to %s" % output)
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
