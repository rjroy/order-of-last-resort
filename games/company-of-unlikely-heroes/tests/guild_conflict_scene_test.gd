extends "res://tests/forfeit_outing_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_conflict_scene_test.gd
# Stock guild, disposable profile, real road victory and confirmed forfeit.
func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var dir := "user://guild_conflict_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute_dir := ProjectSettings.globalize_path(dir)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		_check(false, "Create isolated profile directory")
		_finish()
		return
	profile_path = dir.path_join("profile.json")
	var store = load("res://guild_profile.gd")
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Create stock guild: " + str(created))
		_cleanup_conflict(absolute_dir)
		return
	await _launch_normal()
	await _check_return_displays(created)
	await _launch_normal()
	await _press("Commission_0")
	for id in FOUNDER_PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	# Fix only the reward draw so this fixture exercises a long debrief layout.
	var rewards = load("res://rewards.gd")
	var run: Dictionary = scene.get("_run")
	run.reward_rng_state = rewards.starting_rng_state(13)
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "Stock commission enters its first battle")
		_cleanup_conflict(absolute_dir)
		return
	if not await _earn_upgrade_and_deploy():
		_check(false, "Stock commission wins a road and reaches the next battle")
		_cleanup_conflict(absolute_dir)
		return
	var escape := ForfeitControls.button(viewport, ["forfeit"])
	if escape == null:
		_check(false, "Next battle offers forfeit")
		_cleanup_conflict(absolute_dir)
		return
	await ForfeitControls.click(self, escape)
	var confirm := ForfeitControls.button(viewport, ["forfeit mission"], escape)
	if confirm == null or ForfeitControls.button(viewport, ["cancel"]) == null:
		_check(false, "Forfeit requires confirmation and permits cancel")
		_cleanup_conflict(absolute_dir)
		return
	await ForfeitControls.click(self, confirm)
	if scene.current_screen() != "result":
		_check(false, "Confirmed forfeit reaches the result")
		_cleanup_conflict(absolute_dir)
		return
	var adventure = load("res://adventure.gd")
	var receipt: Dictionary = adventure.receipt(scene.get("_run"))
	_check(receipt.get("points", 0) > 0, "The abandoned outing actually earned points")
	await _check_result_displays()
	var original: Dictionary = store.load_profile(profile_path)
	if original.has("error") or original.is_empty():
		_check(false, "Read current guild before failure fixture")
		_cleanup_conflict(absolute_dir)
		return
	await _check_transient_write_failure(absolute_dir, original)
	# Another instance advances the exact same guild while this result waits.
	var latest: Dictionary = store.renew(profile_path, original, BOARD_SEED + 1)
	if latest.has("error"):
		_check(false, "Another instance advances the board: " + str(latest))
		_cleanup_conflict(absolute_dir)
		return
	var latest_bytes := FileAccess.get_file_as_bytes(profile_path)
	await _press("ReturnToGuild")
	_check(scene.current_screen() == "result", "Superseded outing cannot silently settle")
	_check(store.load_profile(profile_path) == latest and FileAccess.get_file_as_bytes(profile_path) == latest_bytes,
		"Conflict does not overwrite or credit the newer ledger")
	var text := _visible_text().to_lower()
	_check(("changed" in text or "current board" in text or "superseded" in text)
		and ("discard" in text or "abandon" in text or "lost" in text),
		"Result visibly explains the conflict and that the outing payout will not be credited")
	var reload := _node("ReloadGuild") as BaseButton
	if reload == null or not reload.is_visible_in_tree() or reload.disabled:
		_check(false, "Conflict offers an explicit action to abandon and reload the current ledger")
		_cleanup_conflict(absolute_dir)
		return
	await _press("ReloadGuild")
	_check(scene.current_screen() == "commissions", "Abandon opens the current guild board")
	_check(store.load_profile(profile_path) == latest and FileAccess.get_file_as_bytes(profile_path) == latest_bytes,
		"Abandon preserves the current balance, seed, generation and ledger bytes")
	await _launch_normal()
	_check(store.load_profile(profile_path) == latest and FileAccess.get_file_as_bytes(profile_path) == latest_bytes,
		"Relaunch cannot recredit the abandoned outing")
	_cleanup_conflict(absolute_dir)


func _check_transient_write_failure(directory: String, original: Dictionary) -> void:
	if OS.get_name() != "Linux":
		print("SKIP: transient write fixture requires Linux permissions")
		return
	var permissions := FileAccess.get_unix_permissions(directory)
	var error := FileAccess.set_unix_permissions(directory, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_EXECUTE_OWNER)
	if error != OK:
		_check(false, "Can restrict test-owned profile directory")
		return
	var probe_path := profile_path + ".probe"
	var probe := FileAccess.open(probe_path, FileAccess.WRITE)
	if probe != null:
		probe.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))
		_check(FileAccess.set_unix_permissions(directory, permissions) == OK, "Restore directory permissions")
		print("SKIP: directory permissions do not block writes for this user")
		return
	await _press("ReturnToGuild")
	var store = load("res://guild_profile.gd")
	_check(scene.current_screen() == "result" and store.load_profile(profile_path) == original,
		"Transient write failure retains the result and original ledger")
	var retry := _node("ReturnToGuild") as BaseButton
	_check(retry != null and retry.is_visible_in_tree() and not retry.disabled,
		"Transient write failure retains an enabled retry")
	_check(FileAccess.set_unix_permissions(directory, permissions) == OK, "Restore directory permissions")


func _check_return_displays(profile: Dictionary) -> void:
	var adventure = load("res://adventure.gd")
	for outcome: String in ["victory", "defeat", "forfeit", "not_reached"]:
		var fixture := profile.duplicate(true)
		fixture.last_receipt = adventure.accounting(profile.board_seed, profile.board_generation, 1, outcome)
		scene.set("_guild_profile", fixture)
		scene.call("_show_commissions")
		await process_frame
		var text := _visible_text().to_lower()
		var expected: String = outcome.replace("_", " ")
		_check(_mentions_destination(text, outcome), "Returned ledger displays destination outcome " + expected)
		_check("total" in text and str(fixture.last_receipt.points) in text
			and ("guild points: %d" % profile.points) in text,
			"Returned ledger shows receipt total and current balance for " + expected)


func _check_result_displays() -> void:
	var adventure = load("res://adventure.gd")
	var original: Dictionary = scene.get("_run")
	var summaries: Array[String] = []
	for outcome: String in ["victory", "defeat", "forfeit", "not_reached"]:
		var fixture := original.duplicate(true)
		fixture.mission.mission_id = "shield_wall" if outcome == "not_reached" else fixture.destination_id
		fixture.mission.outcome = "defeat" if outcome in ["defeat", "forfeit"] else "victory"
		fixture.mission["_voluntary_defeat"] = outcome == "forfeit"
		fixture.outcome = fixture.mission.outcome
		fixture.last_result.outcome = fixture.outcome
		var receipt: Dictionary = adventure.receipt(fixture)
		_check(receipt.get("destination_outcome") == outcome, "Result fixture represents " + outcome)
		scene.set("_run", fixture)
		scene.call("_show_result")
		await process_frame
		var summary: String = scene.call("_receipt_summary", receipt)
		_check(not summary.is_empty() and summary in _visible_text(),
			"Result renders the actual receipt for " + outcome)
		_check(_mentions_destination(summary.to_lower(), outcome),
			"Result distinguishes destination " + outcome.replace("_", " "))
		_check("total" in summary.to_lower() and str(receipt.points) in summary,
			"Result retains the receipt total for " + outcome)
		_check(summary not in summaries, "Destination outcomes have distinct summaries")
		summaries.append(summary)
	scene.set("_run", original)
	scene.call("_show_result")
	await process_frame


func _mentions_destination(text: String, outcome: String) -> bool:
	match outcome:
		"victory":
			return "victory" in text or "won" in text or "win" in text
		"defeat":
			return "defeat" in text or "lost" in text or "failed" in text
		"forfeit":
			return "forfeit" in text
		"not_reached":
			return "not reached" in text or "did not reach" in text or "never reached" in text
	return false


func _cleanup_conflict(directory: String) -> void:
	if FileAccess.file_exists(profile_path):
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path)) == OK, "Remove test profile")
	_remove_test_backup()
	_check(DirAccess.remove_absolute(directory) == OK, "Remove test directory")
	_finish()
