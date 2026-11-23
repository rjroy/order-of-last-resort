extends RefCounted
## Each actor file is independently stageable; absent future actors are fine.
const DIRECTORY := "res://tests/support"


static func load_cases() -> Dictionary:
	var result := {}
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		push_error("Cannot open stock cast case directory")
		return {}
	var files := dir.get_files()
	files.sort()
	for file in files:
		if not file.begins_with("stock_cast_case_") or not file.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY.path_join(file)))
		if not data is Dictionary or not data.get("case") is Dictionary \
				or str(data.get("mission", "")).is_empty() or str(data.get("actor", "")).is_empty():
			push_error("Invalid stock cast case " + file)
			return {}
		var mission := str(data.mission)
		var actor := str(data.actor)
		if not result.has(mission):
			result[mission] = {}
		if result[mission].has(actor):
			push_error("Duplicate stock cast case " + mission + " / " + actor)
			return {}
		result[mission][actor] = data.case
	return result
