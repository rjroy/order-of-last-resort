extends SceneTree

const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const Runner = preload("res://tools/road_balance/road_playtester.gd")
const STANDALONE = ["no_room_to_swing", "last_crate_on_the_road", "longbows_blind_spot",
	"friars_last_favor", "wrong_twin", "hired_hammer", "borrowed_armor",
	"empty_helmets", "very_long_spear", "big_windup"]


func _initialize() -> void:
	var suite := "pilot"
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):
			suite = arg.trim_prefix("--suite=")
		elif arg.begins_with("--report="):
			path = arg.trim_prefix("--report=")
		else:
			_fail("Unknown option: " + arg)
			return
	if suite not in ["pilot", "catalog"] or path.is_empty():
		_fail("Supply --suite=pilot|catalog and --report=<JSON path>")
		return
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		_fail("Report destination already exists: " + path)
		return
	var defs: Dictionary = Catalog.read_default()
	if defs.is_empty():
		_fail("Unable to load stock catalog")
		return
	var cases: Array = []
	if suite == "pilot":
		for mission in ["big_windup", "big_windup_t3", "big_windup_t4", "big_windup_t5"]:
			if not _cases(cases, defs, mission, "catalog"):
				return
		for mission in ["bridge_patrol", "explosive_situation"]:
			if not _cases(cases, defs, mission, "reference"):
				return
	else:
		var selected := {}
		for id in defs.mission_reports:
			if not defs.mission_reports[id].has("destination_descriptors"):
				selected[id] = true
		for id in STANDALONE:
			selected[id] = true
		# Only variants of the in-scope roots, not destinations or unrelated missions.
		var roots := selected.duplicate()
		for id in defs.missions:
			var base_id: String = defs.missions[id].get("base_mission_id", "")
			if roots.has(base_id):
				selected[id] = true
		var ids: Array = selected.keys()
		ids.sort()
		for id in ids:
			if not _cases(cases, defs, id, "catalog"):
				return
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		_fail("Report destination appeared during simulation: " + path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write report: " + path)
		return
	file.store_string(JSON.stringify({"suite": suite, "round_limit": 12, "cases": cases}, "\t"))
	if file.get_error() != OK:
		_fail("Failed writing report: " + path)
		return
	file.close()
	print("Wrote %d cases to %s" % [cases.size(), path])
	quit(0)


func _cases(cases: Array, defs: Dictionary, mission: String, variant: String) -> bool:
	var rules := Rules.new()
	var runner := Runner.new()
	for roster in [["knight", "healer", "wizard"], ["knight", "alchemist", "bard"]]:
		for wounded in [false, true]:
			var state: Dictionary = Rules.open_mission(defs, mission, roster)
			if state.is_empty():
				_fail("Cannot open %s with %s" % [mission, str(roster)])
				return false
			if wounded:
				for unit in state.units:
					if unit.id in roster:
						unit.hp = maxi(1, unit.hp - 2)
			var opening: Array = []
			for unit in state.units:
				opening.append({"id": unit.id, "character_id": unit.character_id,
					"position": unit.position, "hp": unit.hp, "max_hp": unit.max_hp})
			for policy in ["wizard_first", "forecast_first"]:
				# Without a Wizard, wizard_first falls back to forecast_first.
				if policy == "wizard_first" and "wizard" not in roster:
					continue
				var result: Dictionary = runner.run_case(rules, state, policy, 12)
				if result.has("error"):
					_fail("%s: %s" % [mission, result.error])
					return false
				cases.append({"mission": mission, "variant": variant, "roster": roster,
					"wounded": wounded, "opening": opening, "orders": state.orders,
				"settings": _settings(state), "tier": defs.missions[mission].get("tier"),
					"policy": policy, "result": result})
	return true


func _settings(state: Dictionary) -> Dictionary:
	var defs: Dictionary = state.catalog.defs
	var heal: Dictionary = defs.abilities.get("healer_heal", {})
	var aura: Dictionary = defs.abilities.get("knight_aura", {})
	var aura_id: String = aura.get("params", {}).get("status", "")
	var aura_params: Dictionary = defs.statuses.get(aura_id, {}).get("params", {})
	var aura_cap := int(aura_params.get("max_reflect_damage_per_round", -1))
	var settings := {
		"heal_amount": heal.get("params", {}).get("amount"),
		"heal_range": heal.get("targeting", {}).get("range"),
		"aura_cap": aura_cap if aura_cap >= 0 else "uncapped",
	}
	var windups := {}
	for unit in state.units:
		var profile: Dictionary = Catalog.profile(defs, unit.character_id)
		for trait_spec in profile.get("traits", []):
			if trait_spec.get("kind") == "big_windup":
				windups[unit.id] = trait_spec.damage
	if not windups.is_empty():
		settings["windup_hit_damage"] = windups
	return settings


func _fail(message: String) -> void:
	printerr("ERROR: " + message)
	quit(1)
