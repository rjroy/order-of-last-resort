extends SceneTree
## Stock ready bindings only. No manifest or atlas files are loaded.
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/road_cast_ready_test.gd

const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")

const ROLES := [
	"road_swing_giant", "road_crate_archer", "road_longbow_archer", "road_friar",
	"road_fresh_twin", "road_wounded_twin", "road_windup_bruiser",
	"road_hired_mercenary", "road_bell_soldier", "road_armor_lender",
	"road_long_spearman",
]

var failures: Array[String] = []


func _initialize() -> void:
	var defs: Dictionary = Catalog.read_default()
	var seen := {}
	for mission_id in defs.missions:
		var mission: Dictionary = defs.missions[mission_id]
		var encounter: Dictionary = defs.encounters.get(mission.get("encounter", ""), {})
		var placements: Array = encounter.get("placements", [])
		var relevant := placements.any(func(placement): return placement.get("character") in ROLES)
		if not relevant:
			continue
		var state: Dictionary = Rules.open_mission(defs, mission_id, ["knight", "healer", "wizard"])
		_check(not state.is_empty(), "%s opens for ready binding" % mission_id)
		if state.is_empty():
			continue
		for placement: Dictionary in placements:
			var role: String = placement.get("character", "")
			if role not in ROLES:
				continue
			var matches: Array = state.get("units", []).filter(
				func(unit): return unit.get("id") == placement.get("id") and unit.get("character_id") == role)
			_check(matches.size() == 1, "%s contains stock placement %s / %s" % [mission_id, placement.id, role])
			if matches.size() == 1:
				seen[role] = true
				_check(Cues.cast_key_for(state, matches[0]) == role,
					"%s / %s resolves ready cast key %s" % [mission_id, placement.id, role])

	# The bell soldier is not an opening placement. Use the stock mission's
	# configured raised character with the same identity field as a runtime unit.
	var bell: Dictionary = Rules.open_mission(defs, "empty_helmets", ["knight", "healer", "wizard"])
	_check(not bell.is_empty(), "empty_helmets opens for bell ready binding")
	if not bell.is_empty():
		var role: String = bell.get("objective", {}).get("corpse_bell", {}).get("character", "")
		_check(role == "road_bell_soldier", "stock bell config selects the risen soldier")
		if role == "road_bell_soldier":
			seen[role] = true
			var risen := {"id": "raised_soldier", "character_id": role}
			_check(Cues.cast_key_for(bell, risen) == role, "stock risen soldier resolves ready cast key " + role)

	for role in ROLES:
		_check(seen.has(role), "Stock mission or bell references " + role)
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: road cast stock ready bindings")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
