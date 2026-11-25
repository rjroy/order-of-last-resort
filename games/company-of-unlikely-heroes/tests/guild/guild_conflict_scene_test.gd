extends "res://tests/expedition/forfeit_outing_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/guild_conflict_scene_test.gd
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
	var store = load("res://guild/guild_profile.gd")
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
	var rewards = load("res://expedition/rewards.gd")
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
	var adventure = load("res://expedition/adventure.gd")
	var receipt: Dictionary = adventure.receipt(scene.get("_run"))
	_check(receipt.get("points", 0) > 0, "The abandoned outing actually earned points")
	await _check_result_displays()
	var original: Dictionary = store.load_profile(profile_path)
	if original.has("error") or original.is_empty():
		_check(false, "Read current guild before failure fixture")
		_cleanup_conflict(absolute_dir)
		return
	await _check_transient_write_failure(absolute_dir, original)
	await _check_long_return_diagnostic()
	# Another instance advances the exact same guild while this result waits.
	var latest: Dictionary = store.renew(profile_path, original, BOARD_SEED + 1)
	if latest.has("error"):
		_check(false, "Another instance advances the board: " + str(latest))
		_cleanup_conflict(absolute_dir)
		return
	var latest_bytes := FileAccess.get_file_as_bytes(profile_path)
	await _press("ReturnToGuild")
	_check(scene.current_screen() == "result", "Superseded outing cannot silently settle")
	var ordinary_return := _node("ReturnToGuild") as BaseButton
	_check(ordinary_return == null or ordinary_return.disabled, "Conflict has no actionable normal return")
	_check(store.load_profile(profile_path) == latest and FileAccess.get_file_as_bytes(profile_path) == latest_bytes,
		"Conflict does not overwrite or credit the newer ledger")
	var text := _visible_text().to_lower()
	_check(("changed" in text or "current board" in text or "superseded" in text)
		and ("discard" in text or "abandon" in text or "lost" in text),
		"Result visibly explains the conflict and that the outing payout will not be credited")
	var reload := _node("ReloadGuild") as BaseButton
	if reload == null or not _reachable(reload) or reload.disabled or not reload.has_focus():
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
	var store = load("res://guild/guild_profile.gd")
	_check(scene.current_screen() == "result" and store.load_profile(profile_path) == original,
		"Transient write failure retains the result and original ledger")
	var retry := _node("ReturnToGuild") as BaseButton
	_check(retry != null and _reachable(retry) and not retry.disabled and retry.has_focus() and retry.text == "Retry return",
		"Transient write failure retains an enabled retry")
	_check(FileAccess.set_unix_permissions(directory, permissions) == OK, "Restore directory permissions")


func _check_return_displays(profile: Dictionary) -> void:
	var adventure = load("res://expedition/adventure.gd")
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


func _check_long_return_diagnostic() -> void:
	var original: String = scene.get("_return_error")
	var diagnostic := "Could not write /" + "test-owned/subdirectory/".repeat(145) + "profile.json."
	scene.set("_return_error", diagnostic)
	scene.call("_show_result")
	for frame in 3:
		await process_frame
	var title := _node("ReturnNotSaved") as Label
	var copy := _node("ReturnDiagnostic") as Label
	var scroller := _node("ResultDetailsScroll") as ScrollContainer
	var retry := _node("ReturnToGuild") as Button
	_check(_reachable(title) and title.text == "Return not saved" and _reachable(retry) and retry.has_focus(),
		"Long write diagnostic keeps its heading and the focused retry on screen")
	_check(copy != null and copy.text.begins_with(diagnostic) and scroller != null
		and scroller.get_global_rect().has_point(copy.get_global_rect().position + Vector2.ONE),
		"Long diagnostic begins on screen and preserves the full error")
	if scroller != null:
		var bar := scroller.get_v_scroll_bar()
		_check(bar.focus_mode == Control.FOCUS_ALL, "Overflowing return diagnostic is keyboard reachable")
		bar.grab_focus()
		var down := InputEventAction.new()
		down.action = "ui_down"
		down.pressed = true
		viewport.push_input(down, true)
		await process_frame
		_check(scroller.scroll_vertical > 0, "Keyboard scroll moves the return diagnostic")
	scene.set("_return_error", original)
	scene.call("_show_result")
	await process_frame


func _check_result_displays() -> void:
	var adventure = load("res://expedition/adventure.gd")
	var original: Dictionary = scene.get("_run")
	var samples := {
		"victory": [4, "won", "4 points", "5 points", "9 points"],
		"defeat": [4, "lost", "4 points", "0 points", "4 points"],
		"forfeit": [4, "forfeited", "4 points", "0 points", "4 points"],
		"not_reached": [0, "not reached", "0 points", "0 points", "0 points"],
	}
	for outcome: String in ["victory", "defeat", "forfeit", "not_reached"]:
		var fixture := original.duplicate(true)
		var expected: Array = samples[outcome]
		fixture.mission_index = expected[0]
		fixture.mission.mission_id = "shield_wall" if outcome == "not_reached" else fixture.destination_id
		fixture.mission.outcome = "victory" if outcome == "victory" else "defeat"
		fixture.mission["_voluntary_defeat"] = outcome == "forfeit"
		fixture.outcome = fixture.mission.outcome
		fixture.last_result.outcome = fixture.outcome
		fixture.last_result.mission_id = fixture.mission.mission_id
		var receipt: Dictionary = adventure.receipt(fixture)
		_check(receipt.get("destination_outcome") == outcome, "Result fixture represents " + outcome)
		scene.set("_run", fixture)
		scene.call("_show_result")
		for frame in 3:
			await process_frame
		_check_receipt_row("Road", "Road (%d wins)" % expected[0], expected[2])
		_check_receipt_row("Destination", "Destination (%s)" % expected[1], expected[3])
		_check_receipt_row("Total", "Total", expected[4])
		var title := _node("ResultMissionTitle") as Label
		var defs: Dictionary = scene.get("_definitions")
		_check(title != null and title.text == defs.missions[fixture.mission.mission_id].title,
			"Result identifies the terminal mission, not merely the commission destination")
		var art = load("res://presentation/book/guild_book_art.gd")
		var image: Texture2D = art.destination(fixture.mission.mission_id)
		if image == null:
			image = art.report(fixture.mission.mission_id)
		var frame := _node("ResultMissionArt")
		var prints := frame.find_children("*", "TextureRect", true, false) if frame != null else []
		_check(prints.size() == 1 and prints[0].texture == image, "Terminal mission uses its own packaged art")
	scene.set("_run", original)
	scene.call("_show_result")
	await process_frame


func _check_receipt_row(id: String, caption: String, amount: String) -> void:
	var entry := _node("Receipt" + id)
	var label := entry.find_child("ReceiptLabel", true, false) as Label if entry != null else null
	var value := entry.find_child("ReceiptValue", true, false) as Label if entry != null else null
	_check(label != null and value != null and label.text == caption and value.text == amount
		and _reachable(label) and _reachable(value), "Receipt prints %s: %s" % [caption, amount])


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
