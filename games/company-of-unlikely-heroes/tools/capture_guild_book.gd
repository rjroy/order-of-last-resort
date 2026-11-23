extends "res://tests/village_outing_scene_test.gd"
## Graphical capture. From the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tools/capture_guild_book.gd -- --output="$PWD/.lore/local/guild-book-review/<new-directory>"
## Opening spread only: add --guild-creation-only and use an output directory
## under .lore/local/release-polish/after/ instead.
## Commission board only: add --commission-board-only and use that same output root.
## Recruitment only: add --recruitment-only and use that same output root.
## The output directory must be new or empty. It contains the isolated profile.
## A seeded stock commission is played by the checked-in forecast-based test driver.
## That battle driver uses mouse input for board choices and emits menu signals for
## battle action/target menus. Nonbattle controls use mouse or keyboard input.
## The commission defeat is controlled: party HP is set to zero before commit.

const SIZE := Vector2i(1280, 820)
const BOARD_SEED := 6
const BOARD_REVIEW_SEED := 677 # Matches the approved board plate's destinations and copy.
const FOUNDERS := ["knight", "healer", "wizard"]
var output := ""
var failure := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[1] if args.size() == 2 else ""
	var focused := mode in ["--guild-creation-only", "--commission-board-only", "--recruitment-only"]
	if (args.size() != 1 and not focused) or not args[0].begins_with("--output="):
		_finish_capture("Supply --output=<absolute directory> and optionally one documented capture mode.")
		return
	output = args[0].trim_prefix("--output=").simplify_path()
	var location := "release-polish/after" if focused else "guild-book-review"
	var local := ProjectSettings.globalize_path("res://../../.lore/local/" + location).simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/"):
		_finish_capture("Output must be an absolute directory below .lore/local/" + location + "/.")
		return
	if DisplayServer.get_name() == "headless":
		_finish_capture("A graphical renderer is required.")
		return
	# Check every existing component, including the review directory itself.
	var root_path := ProjectSettings.globalize_path("res://../../").simplify_path()
	var path := root_path
	for component in output.trim_prefix(root_path + "/").split("/"):
		path = path.path_join(component)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_finish_capture("Output path must not contain symbolic links: " + path)
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_finish_capture("Cannot create output directory.")
		return
	var directory := DirAccess.open(output)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		_finish_capture("Output directory must be empty.")
		return

	viewport.size = SIZE
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	if mode == "--commission-board-only":
		_finish_capture(await _capture_commission_board())
		return
	if mode == "--recruitment-only":
		_finish_capture(await _capture_recruitment_states())
		return
	scene = load("res://main.tscn").instantiate()
	if not scene.has_method("configure_launch") or not scene.has_method("configure_profile_path"):
		_finish_capture("The main scene script could not be loaded.")
		return
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(output.path_join("profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if not _screen_is("guild_creation") or not await _save_capture("01-guild-creation"):
		_finish_capture(failure)
		return
	if mode == "--guild-creation-only":
		_finish_capture(await _capture_creation_states())
		return
	var name_edit := scene.find_child("GuildName", true, false) as LineEdit
	if name_edit == null:
		_finish_capture("GuildName is missing.")
		return
	await _click(name_edit.get_global_transform_with_canvas() * (name_edit.size * 0.5))
	for character in "The Review Company":
		await _key(character.unicode_at(0))
	if name_edit.text != "The Review Company":
		_finish_capture("Guild name keyboard input failed: " + name_edit.text)
		return
	if not await _press_button("CreateGuild") or not _screen_is("commissions") \
			or not await _save_capture("02-commissions"):
		_finish_capture(failure)
		return
	if not await _press_button("Commission_0") or not _screen_is("guild") \
			or not await _save_capture("03-commission-selected") \
			or not await _press_button("BackToCommissions") or not _screen_is("commissions") \
			or not await _press_button("Commission_0") or not _screen_is("guild") \
			or not await _save_capture("04-recruitment"):
		_finish_capture(failure)
		return
	for id in ["knight", "healer", "wizard"]:
		if not await _press_button("Recruit_" + id):
			_finish_capture(failure)
			return
	if not await _press_button("PartyEarlier_healer"):
		_finish_capture(failure)
		return
	var later := scene.find_child("PartyLater_healer", true, false) as BaseButton
	if later == null or later.disabled:
		_finish_capture("Keyboard reorder control unavailable.")
		return
	later.grab_focus()
	await _key(KEY_ENTER)
	if scene.selected_recruits() != ["knight", "healer", "wizard"]:
		_finish_capture("Keyboard reorder did not restore the original party order.")
		return
	if not await _save_capture("05-deployment-reordered") \
			or not await _press_button("StartAdventure") or not _screen_is("routes") \
			or not await _save_capture("06-field-reports") \
			or not await _press_button("Route_0") or not _screen_is("battle") \
			or not await _save_capture("07-battle-entry"):
		_finish_capture(failure)
		return
	# Exercise the normal resolver and return path with a deliberately lost battle.
	var controlled: Dictionary = scene.get("_state").duplicate(true)
	for unit: Dictionary in controlled.units:
		if unit.id in controlled.party:
			unit.hp = 0
	scene.set("_state", controlled)
	scene.set("_planned_state", controlled.duplicate(true))
	scene.call("_refresh")
	if not await _press_button("Commit") or not _screen_is("result") \
			or not _outcome_is("defeat") or not await _save_capture("08-controlled-defeat") \
			or not await _press_button("ReturnToGuild") or not _screen_is("commissions") \
			or not await _save_capture("09-return-after-defeat"):
		_finish_capture(failure)
		return
	# Fix the second board so the stock commission and battle driver are repeatable.
	var store = load("res://guild_profile.gd")
	var renewed: Dictionary = store.renew(output.path_join("profile.json"), scene.get("_guild_profile"), BOARD_SEED)
	if renewed.has("error"):
		_finish_capture("Could not seed the capture board: " + str(renewed.error))
		return
	scene.queue_free()
	await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(output.path_join("profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if not _screen_is("commissions") or not await _press_button("Commission_0") \
			or not _screen_is("guild") or not await _save_capture("10-commission-selected"):
		_finish_capture(failure)
		return
	for id in FOUNDERS:
		if not await _press_button("Recruit_" + id):
			_finish_capture(failure)
			return
	if not await _press_button("PartyEarlier_healer") \
			or scene.selected_recruits() != ["healer", "knight", "wizard"] \
			or not await _press_button("StartAdventure") or not _screen_is("routes"):
		_finish_capture("Could not start the stock commission: " + failure)
		return
	# Match the deterministic commission regression's reward stream.
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 12345
	var outing: Dictionary = scene.get("_run")
	outing.reward_rng_state = reward_rng.state
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var mission_count := int(outing.get("mission_count", 0))
	if mission_count < 2:
		_finish_capture("Commission has no road and destination.")
		return
	for index in mission_count:
		if index < mission_count - 1:
			if not _screen_is("routes") or not await _press_button("Route_0"):
				_finish_capture(failure)
				return
		if not _screen_is("battle"):
			_finish_capture("Expected commission battle: " + failure)
			return
		var mission_id := str(scene.battle_snapshot().get("mission_id", ""))
		await _play_battle(mission_id)
		if not failures.is_empty():
			_finish_capture("Stock battle driver failed: " + str(failures))
			return
		if index < mission_count - 1:
			if not _screen_is("debrief"):
				_finish_capture(failure)
				return
			if index == 0 and not await _save_capture("11-debrief-reward-choices"):
				_finish_capture(failure)
				return
			var chosen := false
			for id in FOUNDERS:
				var reward := scene.find_child("Reward_" + id, true, false) as BaseButton
				if reward != null and reward.is_visible_in_tree() and not reward.disabled:
					chosen = await _press_button(str(reward.name))
					break
			if not chosen or not await _save_capture("12-reward-selected-%d" % index) \
					or not await _press_button("ContinueAdventure"):
				_finish_capture("Could not choose or continue after reward: " + failure)
				return
		else:
			if not _screen_is("result") or not _outcome_is("victory") \
					or not await _save_capture("13-played-victory") \
					or not await _press_button("ReturnToGuild") or not _screen_is("commissions") \
					or not await _save_capture("14-return-after-victory"):
				_finish_capture(failure)
				return
	print("Completed stock-catalog capture in " + output)
	_finish_capture("")


func _capture_commission_board() -> String:
	var profile := output.path_join("profile.json")
	var store = load("res://guild_profile.gd")
	var created: Dictionary = store.create(profile, "The Review Company", BOARD_REVIEW_SEED)
	if created.has("error"):
		return "Could not seed the capture board: " + str(created.error)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(profile)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if not _screen_is("commissions") or not await _save_capture("02-commissions"):
		return failure
	await _key(KEY_ENTER)
	if not _screen_is("guild") or scene.get("_commission").get("destination_id") != "last_wagon":
		return "Keyboard did not accept the first commission."
	print("Captured and accepted the seed-%d board." % BOARD_REVIEW_SEED)
	return ""


func _capture_recruitment_states() -> String:
	var store = load("res://guild_profile.gd")
	var fixture = load("res://tests/guild_petitions_domain_test.gd").new()
	var path := output.path_join("profile.json")
	var profile: Dictionary = store.create(path, "The Review Company", fixture.SEED)
	if profile.has("error"):
		fixture.free()
		return str(profile.error)
	# Settle four controlled road wins so the real teaching petition can be bought.
	var defs: Dictionary = load("res://content/catalog.gd").read_default()
	var run: Dictionary = fixture._run_commission(defs, profile, 4, 0)
	fixture.free()
	if run.is_empty():
		return "Could not earn points for the loadout fixture."
	profile = store.settle_return(path, profile, run, BOARD_REVIEW_SEED)
	if profile.has("error"):
		return str(profile.error)
	profile = store.purchase(path, profile, defs, "teach_healer_blast")
	if profile.has("error"):
		return str(profile.error)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray())
	scene.configure_profile_path(path)
	viewport.add_child(scene)
	await process_frame
	await process_frame

	if not await _activate_with_key("Commission_0") or not _screen_is("guild") \
			or not await _save_capture("01-recruitment-empty"):
		return failure
	for id in FOUNDERS:
		if not await _activate_with_key("Recruit_" + id):
			return failure
	if scene.selected_recruits() != FOUNDERS or not await _save_capture("02-recruitment-filled"):
		return "Keyboard did not recruit the founders in order. " + failure
	if not await _activate_with_key("PartyEarlier_healer") \
			or scene.selected_recruits() != ["healer", "knight", "wizard"] \
			or not await _save_capture("03-recruitment-reordered"):
		return "Keyboard did not move the Healer earlier. " + failure
	if not await _activate_with_key("PartyLater_healer") or scene.selected_recruits() != FOUNDERS:
		return "Keyboard did not restore the original order. " + failure
	if not await _activate_with_key("EditHero_healer") or not await _activate_with_key("Offense_wizard_blast"):
		return failure
	var lock := scene.find_child("Order_order_aggressive", true, false) as BaseButton
	var support := scene.find_child("Order_order_support", true, false) as BaseButton
	if lock == null or not lock.disabled or lock.text != "Requires Bonk" or support == null or support.disabled:
		return "Blast should leave Support available and Pursue and bonk locked by Bonk."
	var later := scene.find_child("PartyLater_healer", true, false) as BaseButton
	later.grab_focus()
	if not await _save_capture("04-recruitment-loadout"):
		return failure
	if not await _activate_with_key("StartAdventure") or not _screen_is("routes"):
		return failure
	var started: Dictionary = scene.get("_run")
	if started.get("party", []) != FOUNDERS:
		return "The route did not retain the deployment order."
	print("Captured recruitment and opened field reports using keyboard actions.")
	return ""


func _activate_with_key(node_name: String) -> bool:
	var control := scene.find_child(node_name, true, false) as BaseButton
	if control == null or control.disabled or not control.is_visible_in_tree():
		failure = node_name + " is not available."
		return false
	control.grab_focus()
	await _key(KEY_ENTER)
	return true


func _capture_creation_states() -> String:
	const LONG_NAME := "The Very Unlikely Company of the Last Lantern"
	var edit := scene.find_child("GuildName", true, false) as LineEdit
	var create := scene.find_child("CreateGuild", true, false) as BaseButton
	var feedback := scene.find_child("GuildNameFeedback", true, false) as Label
	if edit == null or create == null or feedback == null or not create.disabled or not edit.has_focus():
		return "Fresh creation should focus the name and disable the action."
	await _key(KEY_ENTER)
	if not _screen_is("guild_creation") or feedback.text != "Enter a guild name." or not edit.has_focus():
		return "Submitting a blank name should show feedback and keep focus."
	if not await _save_capture("02-empty-name-feedback"):
		return failure
	for character in LONG_NAME:
		await _key(character.unicode_at(0))
	if edit.text != LONG_NAME or create.disabled:
		return "Long guild name keyboard entry failed: " + edit.text
	if not await _save_capture("03-long-name"):
		return failure
	await _key(KEY_ENTER)
	if not _screen_is("commissions"):
		return failure
	print("Checked creation with keyboard entry and reached the commission board.")
	return ""


func _screen_is(expected: String) -> bool:
	if scene.current_screen() != expected:
		failure = "Expected %s, got %s." % [expected, scene.current_screen()]
		return false
	return true


func _outcome_is(expected: String) -> bool:
	var outcome := scene.find_child("RunOutcome", true, false)
	if outcome == null or outcome.get_meta("outcome", "") != expected:
		failure = "Expected result outcome " + expected
		return false
	return true


# Overrides used by the stock test driver. Nonbattle button actions are clicks.
func _press(name: String) -> void:
	if not await _press_button(name):
		_check(false, failure)


func _click_commit() -> void:
	await _press("Commit")


# The stock test driver requests exploratory battle screenshots; suppress these.
func _capture(_name: String) -> void:
	pass


func _press_button(name: String) -> bool:
	var button := scene.find_child(name, true, false) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		failure = name + " is not available."
		return false
	var parent := button.get_parent()
	while parent != null and parent != viewport:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await process_frame
	await _click(button.get_global_transform_with_canvas() * (button.size * 0.5))
	return true


func _click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = point
		event.global_position = point
		event.pressed = down
		viewport.push_input(event, true)
		await process_frame


func _key(code: int, target: Viewport = null) -> void:
	if target == null:
		target = viewport
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.unicode = code if code < 128 else 0
		event.pressed = down
		target.push_input(event, true)
		await process_frame


func _save_capture(name: String) -> bool:
	if scene.find_child("TerminalCastReplay", true, false) != null:
		await _key(KEY_SHIFT)
		await process_frame
		if scene.find_child("TerminalCastReplay", true, false) != null:
			failure = "Terminal replay obscures " + name
			return false
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != SIZE \
			or image.save_png(output.path_join(name + ".png")) != OK:
		failure = "Could not save " + name
		return false
	print("Captured " + name)
	return true


func _finish_capture(message: String) -> void:
	if not message.is_empty():
		push_error(message)
	quit(0 if message.is_empty() else 1)
