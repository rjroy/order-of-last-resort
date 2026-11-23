extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/standalone_loadout_scene_test.gd
# Each launch is a separate process: the real headless error screen exits the tree.
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
const SCRIPT := "res://tests/standalone_loadout_scene_test.gd"
const SENTINEL := "test-owned profile must not change\n"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--launcher-child" in OS.get_cmdline_user_args():
		await _child()
		return
	var directory := ProjectSettings.globalize_path("user://standalone_launcher_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		_check(false, "Create a new isolated child home")
		_finish()
		return
	var profile := directory + "/profile.json"
	var file := FileAccess.open(profile, FileAccess.WRITE)
	if file == null:
		_check(false, "Create test-owned profile sentinel")
		_remove_tree(directory)
		_finish()
		return
	file.store_string(SENTINEL)
	file.close()
	var fixture_paths := _write_custom_fixtures(directory)
	if fixture_paths.is_empty():
		_check(_remove_tree(directory), "Remove isolated test-owned home")
		_finish()
		return
	var home := OS.get_environment("HOME")
	var xdg := OS.get_environment("XDG_DATA_HOME")
	OS.set_environment("HOME", directory)
	OS.set_environment("XDG_DATA_HOME", directory + "/data")
	var cases := [
		{"name": "authored defaults", "args": ["--mission=wrong_side_of_the_door"], "mode": "defaults"},
		{"name": "authored party with partial build", "args": ["--mission=wrong_side_of_the_door",
			"--loadout=knight:utility=knight_rescue_line,order=order_knight_escort"], "mode": "authored"},
		{"name": "explicit ordered party and repeated loadouts", "args": ["--mission=bridge_patrol",
			"--party=wizard,knight,healer", "--loadout=knight:offense=healer_bonk,utility=knight_rescue_line,order=order_knight_escort",
			"--loadout=healer:offense=wizard_blast"], "mode": "party"},
		{"name": "party without mission", "args": ["--party=knight,healer,wizard"],
			"error": ["mission", "--party"]},
		{"name": "loadout without mission", "args": ["--loadout=knight:utility=knight_rescue_line"],
			"error": ["mission", "loadout"]},
		{"name": "wrong party size", "args": ["--mission=bridge_patrol", "--party=knight,healer"], "error": ["size", "count", "exact", "slots", "received", "provided"]},
		{"name": "empty party member", "args": ["--mission=bridge_patrol", "--party=knight,,wizard"], "error": ["empty", "blank", "malformed", "invalid", "comma"]},
		{"name": "duplicate party member", "args": ["--mission=bridge_patrol", "--party=knight,knight,wizard"], "error": ["duplicate", "repeated", "unique", "distinct", "knight"]},
		{"name": "nonhero party member", "args": ["--mission=bridge_patrol", "--party=knight,healer,harpooner"], "error": ["harpooner", "hero", "roster"]},
		{"name": "unknown party member", "args": ["--mission=bridge_patrol", "--party=knight,healer,missing"], "error": ["missing", "unknown", "invalid", "roster"]},
		{"name": "unselected loadout", "args": ["--mission=bridge_patrol", "--party=knight,healer,wizard",
			"--loadout=bard:offense=healing_sonnet"], "error": ["bard", "selected", "deployed"]},
		{"name": "malformed loadout", "args": ["--mission=wrong_side_of_the_door", "--loadout=knight:utility"], "error": ["loadout", "utility", "slot"]},
		{"name": "empty loadout", "args": ["--mission=wrong_side_of_the_door", "--loadout=knight:"], "error": ["loadout", "knight", "slot"]},
		{"name": "duplicate hero loadout", "args": ["--mission=wrong_side_of_the_door",
			"--loadout=knight:utility=knight_rescue_line", "--loadout=knight:order=order_knight_escort"],
			"error": ["duplicate", "repeated", "knight", "loadout"]},
		{"name": "duplicate loadout slot", "args": ["--mission=wrong_side_of_the_door",
			"--loadout=knight:utility=knight_aura,utility=knight_rescue_line"],
			"error": ["duplicate", "repeated", "utility", "slot"]},
		{"name": "unknown slot", "args": ["--mission=wrong_side_of_the_door", "--loadout=knight:weapon=healer_bonk"],
			"error": ["slot"], "required_error": ["weapon", "slot"]},
		{"name": "wrong slot ability", "args": ["--mission=wrong_side_of_the_door", "--loadout=knight:utility=healer_bonk"],
			"error": ["slot"], "required_error": ["healer_bonk", "utility"]},
		{"name": "unknown order", "args": ["--mission=wrong_side_of_the_door", "--loadout=knight:order=missing"],
			"error": ["unknown", "unrecognized", "not found", "no such"], "required_error": ["missing", "order"]},
		{"name": "incompatible order", "args": ["--mission=wrong_side_of_the_door",
			"--loadout=knight:offense=healer_bonk,utility=knight_rescue_line,order=order_advance"],
			"error": ["incompatible", "requires", "missing", "not compatible", "needs"],
			"required_error": ["order_advance", "order"]},
		{"name": "custom mission needs party", "args": ["--content=" + fixture_paths.route,
			"--mission=bridge_patrol"], "error": ["--party"], "required_error": ["--party", "3"]},
		{"name": "custom mission with party", "args": ["--content=" + fixture_paths.route,
			"--mission=bridge_patrol", "--party=wizard,knight,healer"], "mode": "custom"},
		{"name": "custom hero without base default order", "args": ["--content=" + fixture_paths.no_default_order,
			"--mission=wrong_side_of_the_door",
			"--loadout=knight:utility=knight_rescue_line,order=order_knight_escort"], "mode": "authored"},
		{"name": "custom hero with no available orders", "args": ["--content=" + fixture_paths.no_orders,
			"--mission=wrong_side_of_the_door", "--loadout=knight:order=order_advance"],
			"error": ["no standing orders", "no orders", "none available", "no available",
				"no compatible orders", "no valid orders"],
			"required_error": ["order_advance"]},
	]
	for id in ["progression", "kits", "hero_kit"]:
		cases.append({"name": "malformed custom " + id, "args": [
			"--content=" + fixture_paths[id], "--mission=wrong_side_of_the_door",
			"--loadout=knight:utility=knight_rescue_line"], "error": ["guild", "progression", "kit", "loadout"]})
	for test in cases:
		var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--quit-after", "600", "--script", SCRIPT, "--", "--launcher-child", "--test-profile=" + profile,
			"--test-mode=" + test.get("mode", "invalid")])
		args.append_array(PackedStringArray(test.args))
		var output: Array = []
		var code := OS.execute(OS.get_executable_path(), args, output, true)
		var text := "\n".join(output)
		if test.has("error"):
			var marker := "Could not start the game:"
			var message := text.substr(text.find(marker) + marker.length()).to_lower() if marker in text else ""
			var relevant := false
			for token in test.error:
				if token in message:
					relevant = true
			_check(code != 0 and relevant,
				test.name + ": rejects launch with a useful error; output: " + text)
			for token in test.get("required_error", []):
				_check(token in message, test.name + ": error includes " + token + "; output: " + text)
			_check("SCRIPT ERROR" not in text, test.name + ": no GDScript exception; output: " + text)
		else:
			_check(code == 0 and "PASS: child" in text, test.name + ": " + text)
			_check("SCRIPT ERROR" not in text, test.name + ": no GDScript exception; output: " + text)
		_check(FileAccess.get_file_as_string(profile) == SENTINEL, test.name + ": profile is untouched")
		_check(not _contains_default_profile(directory), test.name + ": no default guild profile is created")
	var count := cases.size()
	if OS.get_name() == "Linux":
		_test_unconfigured_launch(directory)
		count += 1
	else:
		print("SKIP: unconfigured legacy isolation requires Linux XDG paths")
	OS.set_environment("HOME", home)
	OS.set_environment("XDG_DATA_HOME", xdg)
	_check(_remove_tree(directory), "Remove isolated test-owned home")
	if failures.is_empty():
		print("PASS: standalone launcher (%d cases)" % count)
	_finish()


func _child() -> void:
	var mode := ""
	var profile := ""
	var isolated_root := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-mode="):
			mode = arg.trim_prefix("--test-mode=")
		if arg.begins_with("--test-profile="):
			profile = arg.trim_prefix("--test-profile=")
		if arg.begins_with("--test-root="):
			isolated_root = arg.trim_prefix("--test-root=")
	if mode == "unconfigured":
		var user_dir := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
		if OS.get_name() != "Linux" or isolated_root.is_empty() \
				or not user_dir.begins_with(isolated_root.simplify_path().trim_suffix("/") + "/"):
			_check(false, "Refusing unconfigured launch outside isolated Linux user directory: " + user_dir)
			_finish()
			return
	var scene: Node = load("res://main.tscn").instantiate()
	if mode != "unconfigured":
		scene.configure_profile_path(profile)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	if mode == "invalid":
		_check(false, "Invalid launch unexpectedly reached screen: " + scene.current_screen())
		scene.queue_free()
		await process_frame
		_finish()
		return
	if scene.current_screen() != "battle":
		_check(false, "Expected battle, got " + scene.current_screen())
		_finish()
		return
	var state: Dictionary = scene.battle_snapshot()
	var defs: Dictionary = Catalog.read_default()
	var rules := Rules.new()
	var party: Array = ["wizard", "knight", "healer"] if mode in ["party", "custom"] else ["knight", "healer", "wizard"]
	var mission := "bridge_patrol" if mode in ["party", "custom"] else "wrong_side_of_the_door"
	var slots: Array = defs.encounters[defs.missions[mission].encounter].party_slots
	_check(state.get("party", []) == party, "Party order is preserved")
	for index in party.size():
		var found := false
		for unit in state.get("units", []):
			if unit.get("id") == party[index]:
				found = true
				_check(unit.get("position") == Vector2i(slots[index][0], slots[index][1]),
					party[index] + " deploys at its ordered party slot")
		_check(found, party[index] + " is deployed")
	if mode in ["defaults", "custom", "unconfigured"]:
		var expected := Rules.open_mission(defs, mission, party)
		_check(state.get("orders") == expected.get("orders"), "No-loadout orders remain authored defaults")
		for hero in party:
			_check(rules.entity_profile(state, hero).abilities == rules.entity_profile(expected, hero).abilities,
				hero + " retains authored abilities without loadout flags")
	else:
		var knight: Dictionary = rules.entity_profile(state, "knight")
		_check("knight_rescue_line" in knight.get("abilities", [])
			and "knight_aura" not in knight.get("abilities", []), "Knight utility override is equipped")
		_check(state.get("orders", {}).get("knight") == "order_knight_escort",
			"Knight learned standing order is active")
		if mode == "party":
			_check("healer_bonk" in knight.abilities and "knight_push" not in knight.abilities,
				"Knight offense override is equipped")
			var healer: Dictionary = rules.entity_profile(state, "healer")
			_check("wizard_blast" in healer.get("abilities", []) and "healer_bonk" not in healer.get("abilities", [])
				and "healer_heal" in healer.get("abilities", []), "Second partial loadout preserves utility")
		else:
			_check("knight_push" in knight.abilities, "Partial override preserves default offense")
	var opening: Dictionary = scene.battle_snapshot()
	scene.call("_commit")
	_check(scene.battle_snapshot() != opening, "A real round mutates the battle")
	scene.call("_restart_fixed")
	_check(scene.battle_snapshot() == opening, "Restart restores the identical configured opening")
	scene.call("_forfeit")
	_check(scene.battle_snapshot().get("outcome", "ongoing") != "ongoing", "Standalone battle can finish")
	if mode != "unconfigured":
		_check(FileAccess.get_file_as_string(profile) == SENTINEL, "Finish does not touch profile")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: child")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_unconfigured_launch(directory: String) -> void:
	var legacy_dir := directory.path_join("data/godot/app_userdata/The Company of Unlikely Heroes/company_of_unlikely_heroes")
	if DirAccess.make_dir_recursive_absolute(legacy_dir) != OK:
		_check(false, "Create isolated legacy profile directory")
		return
	var legacy := legacy_dir.path_join("guild_profile_v1.json")
	var contents := JSON.stringify({"version": 1, "name": "Test legacy guild", "board_seed": "101"})
	var file := FileAccess.open(legacy, FileAccess.WRITE)
	if file == null:
		_check(false, "Create isolated legacy profile")
		return
	file.store_string(contents)
	file.close()
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--quit-after", "600", "--script", SCRIPT, "--", "--launcher-child",
		"--test-mode=unconfigured", "--test-root=" + directory, "--mission=wrong_side_of_the_door"])
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(output)
	_check(code == 0 and "PASS: child" in text and "SCRIPT ERROR" not in text,
		"Unconfigured public CLI launch succeeds inside isolated user directory: " + text)
	_check(FileAccess.get_file_as_string(legacy) == contents, "Legacy source remains unchanged")
	var canonical := directory.path_join("data/godot/app_userdata/Barnaby's Order of Last Resort")
	_check(not FileAccess.file_exists(canonical.path_join("guild_profile_v1.json"))
		and not FileAccess.file_exists(canonical.path_join("custom_guild_profile_v1.json")),
		"Unconfigured standalone launch does not migrate a canonical guild profile")


func _write_custom_fixtures(directory: String) -> Dictionary:
	var stock: Dictionary = Catalog.read_default()
	var route := stock.duplicate(true)
	for table in ["adventures", "commission_settings", "mission_kinds", "mission_reports"]:
		route.erase(table)
	var malformed_progression := stock.duplicate(true)
	malformed_progression.guild_progression = []
	var malformed_kits := stock.duplicate(true)
	malformed_kits.guild_progression.kits = []
	var malformed_hero_kit := stock.duplicate(true)
	malformed_hero_kit.guild_progression.kits.knight = []
	var no_default_order := stock.duplicate(true)
	no_default_order.classes.knight.erase("default_order")
	# Rename Hold everywhere so other heroes remain valid without providing the
	# hard-coded fallback ID; the Knight has neither native nor learned orders.
	var no_orders: Dictionary = JSON.parse_string(JSON.stringify(stock).replace('"order_hold"', '"order_fixture_hold"'))
	no_orders.classes.knight.erase("default_order")
	no_orders.classes.knight.habits = {}
	no_orders.guild_progression.petitions.erase("knight_escort_order")
	var fixtures := {"route": route, "progression": malformed_progression,
		"kits": malformed_kits, "hero_kit": malformed_hero_kit, "no_default_order": no_default_order,
		"no_orders": no_orders}
	var paths := {}
	for id in fixtures:
		var data: Dictionary = fixtures[id]
		var errors := Catalog.validate(data)
		if not errors.is_empty():
			_check(false, id + " fixture must pass base catalog validation: " + "\n".join(errors))
			return {}
		if id != "route":
			var guild_errors := Catalog.validate_guild_progression(data)
			if id in ["no_default_order", "no_orders"] and not guild_errors.is_empty():
				_check(false, id + " fixture must pass guild progression validation: " + "\n".join(guild_errors))
				return {}
			if id not in ["no_default_order", "no_orders"] and guild_errors.is_empty():
				_check(false, id + " fixture must fail guild progression validation")
				return {}
		var path := directory.path_join(id + ".json")
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_check(false, "Write test-owned fixture " + id)
			return {}
		file.store_string(JSON.stringify(data))
		file.close()
		paths[id] = path
	return paths


func _remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	var ok := true
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if dir.current_is_dir():
			ok = _remove_tree(child) and ok
		else:
			ok = (DirAccess.remove_absolute(child) == OK) and ok
		name = dir.get_next()
	dir.list_dir_end()
	return (DirAccess.remove_absolute(path) == OK) and ok


func _contains_default_profile(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name in ["guild_profile_v1.json", "custom_guild_profile_v1.json"]:
			dir.list_dir_end()
			return true
		if dir.current_is_dir() and _contains_default_profile(path.path_join(name)):
			dir.list_dir_end()
			return true
		name = dir.get_next()
	dir.list_dir_end()
	return false


func _finish() -> void:
	for failure in failures:
		printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
