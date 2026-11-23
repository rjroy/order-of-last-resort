extends "res://tests/commission_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_profile_recovery_scene_test.gd
# Exercise recovery through the result screen using a test-owned profile.
const RENEWED_SEED := 97531
var fixture_path := "user://commission_recovery_catalog_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]


func _run() -> void:
	if not _write_fixture():
		_cleanup()
		return
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	container.scale = Vector2(0.5, 0.5)
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	await _test_corrupt_profile()
	await _test_changed_profile()
	await _test_missing_profile()
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path)) == OK,
		"Removed test-owned catalog")
	_cleanup()


func _test_corrupt_profile() -> void:
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Create disposable corrupt profile")
		return
	file.store_string("{ invalid json")
	file.close()
	await _launch_normal()
	_check(scene.current_screen() == "profile_error", "Corrupt profile opens recovery")
	_check_no_practice("Corrupt profile recovery")
	_check(_reload_button() != null, "Corrupt profile recovery offers reload")
	_check(FileAccess.get_file_as_string(profile_path) == "{ invalid json",
		"Recovery preserves corrupt profile for repair")
	await _press("ReloadGuild")
	_check(scene.current_screen() == "profile_error", "Reload keeps reporting an unrepaired profile")
	_check_no_practice("Corrupt profile recovery after retry")


func _write_fixture() -> bool:
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default().duplicate(true)
	var mission: Dictionary = defs.missions.shield_wall.duplicate(true)
	mission.encounter = "recovery_test_encounter"
	defs.encounters.recovery_test_encounter = {
		"board": "frontier_field", "party_slots": [[1, 1], [1, 2], [1, 3]],
		"placements": [{"id": "grunt_1", "character": "grunt", "at": [2, 2]}]
	}
	defs.characters.grunt.max_hp = 1
	defs.mission_reports = {}
	defs.mission_kinds = {}
	for kind_index in 4:
		var kind := "recovery_kind_%d" % kind_index
		defs.mission_kinds[kind] = {"label": kind, "descriptors": ["Hint " + kind]}
		for index in 3:
			var id := "recovery_transit_%d_%d" % [kind_index, index]
			defs.missions[id] = mission.duplicate(true)
			defs.missions[id].title = id
			defs.mission_reports[id] = {"kind": kind, "descriptors": ["Report " + id]}
	for index in 8:
		var id := "recovery_destination_%d" % index
		defs.missions[id] = mission.duplicate(true)
		defs.missions[id].title = "Destination %d" % index
		defs.mission_reports[id] = {
			"kind": "recovery_kind_%d" % (index % 4),
			"descriptors": ["Report " + id], "destination_descriptors": ["Contract " + id]
		}
	var errors: PackedStringArray = catalog.validate(defs)
	if not errors.is_empty():
		_check(false, "Recovery catalog validates: " + str(errors))
		return false
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Recovery catalog can be written")
		return false
	file.store_string(JSON.stringify(defs))
	file.close()
	return true


func _start_outing() -> bool:
	var store = load("res://guild_profile.gd")
	if FileAccess.file_exists(profile_path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path)) != OK:
			_check(false, "Previous test-owned profile can be removed")
			return false
	if not _remove_test_backup():
		return false
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Test-owned profile can be created: " + str(created))
		return false
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(fixture_path)]))
	scene.configure_profile_path(profile_path)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if scene.current_screen() != "commissions":
		_check(false, "Outing starts from the commission board")
		return false
	await _press("Commission_0")
	for id in PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	for step in 5:
		if step < 4:
			if scene.current_screen() != "routes":
				_check(false, "Controlled outing opens route selection")
				return false
			await _press("Route_0")
		if scene.current_screen() != "battle":
			_check(false, "Controlled outing opens battle")
			return false
		await _play_battle(str(scene.battle_snapshot().get("mission_id", "")))
		if step < 4:
			if scene.current_screen() != "debrief":
				_check(false, "Controlled battle opens debrief")
				return false
			var selected := false
			for id in PARTY:
				var reward := _node("Reward_" + id) as BaseButton
				if reward != null and reward.is_visible_in_tree() and not reward.disabled:
					await _press(str(reward.name))
					selected = true
					break
			if not selected:
				_check(false, "Controlled debrief offers an eligible reward")
				return false
			await _press("ContinueAdventure")
	if scene.current_screen() != "result":
		_check(false, "Outing reaches a terminal result")
		return false
	return true


func _test_changed_profile() -> void:
	if not await _start_outing():
		return
	var store = load("res://guild_profile.gd")
	var original: Dictionary = store.load_profile(profile_path)
	var latest: Dictionary = store.renew(profile_path, original, RENEWED_SEED)
	if latest.has("error") or latest.get("board_seed") != RENEWED_SEED:
		_check(false, "Another instance can renew the test profile")
		return
	await _press("ReturnToGuild")
	_check(store.load_profile(profile_path) == latest, "Conflicting return does not overwrite the latest profile")
	if scene.current_screen() == "result":
		var reload := _reload_button()
		_check(reload != null, "Conflict offers a visible reload action")
		if reload == null:
			return
		await _press("ReloadGuild")
	_check(scene.current_screen() == "commissions", "Reload opens the latest commission board")
	_check_no_practice("Board after profile conflict recovery")
	_check(store.load_profile(profile_path) == latest, "Reload leaves the newest saved profile unchanged")
	if scene.current_screen() != "commissions":
		return
	var commissions = load("res://commissions.gd")
	var offers: Array = commissions.board(scene.get("_definitions"), RENEWED_SEED)
	_check(offers.size() == 3, "Latest profile generates three offers")
	for i in offers.size():
		var button := _node("Commission_%d" % i) as BaseButton
		_check(button != null and button.is_visible_in_tree()
			and button.accessibility_description.contains(str(offers[i].description)),
			"Visible commission %d matches the latest board" % i)
	_check(_visible_text().contains(GUILD_NAME), "Reloaded board shows the saved guild name")


func _test_missing_profile() -> void:
	if not await _start_outing():
		return
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	if error != OK:
		_check(false, "Another instance can remove the test profile")
		return
	if not _remove_test_backup():
		return
	await _press("ReturnToGuild")
	if scene.current_screen() == "result":
		var reload := _reload_button()
		_check(reload != null, "Missing profile offers a visible reload action, not only retry")
		if reload == null:
			return
		await _press("ReloadGuild")
	_check(scene.current_screen() == "guild_creation", "Missing profile leads to guild creation")
	_check_no_practice("Missing profile recovery")
	_check(not FileAccess.file_exists(profile_path), "Recovery does not silently recreate the missing profile")


func _reload_button() -> BaseButton:
	var node := _node("ReloadGuild") as BaseButton
	if node != null and node.is_visible_in_tree() and not node.disabled:
		return node
	return null
