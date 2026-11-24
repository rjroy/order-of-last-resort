extends "res://tools/capture_guild_book.gd"
## Graphical review of the normal stock game at 1280 × 820. From the repository root:
## mkdir -p "$PWD/.lore/local/onboarding-review"
## review="$(mktemp -d "$PWD/.lore/local/onboarding-review/run.XXXXXX")"
## mkdir -p "$review/xdg/"{data,config,cache}
## XDG_DATA_HOME="$review/xdg/data" XDG_CONFIG_HOME="$review/xdg/config" \
## XDG_CACHE_HOME="$review/xdg/cache" godot --path games/company-of-unlikely-heroes \
##   --script res://tools/capture_onboarding_review.gd -- --output="$review/frames"
## Use a graphical session, not --headless. Screenshots, profile and settings are disposable.

const REVIEW_NAME := "The Last Lantern Company"
const REVIEW_SEED := 677
const Preferences := preload("res://battle_display_preferences.gd")
const StorybookDriver := preload("res://tests/support/storybook_driver.gd")

var _profile := "user://onboarding_review_guild.json"


func _run() -> void:
	var error := _prepare_review()
	if not error.is_empty():
		viewport.free()
		_finish_capture(error)
		return
	viewport.size = SIZE
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	create_timer(75.0).timeout.connect(func() -> void:
		_finish_capture("Timed out while capturing onboarding. Last failure: " + failure))
	await _mount_review(PackedStringArray())
	if not await _review_opening() or not await _review_practice() \
			or not await _review_guild() or not await _review_standalone():
		_finish_capture(failure if not failure.is_empty() else "Capture stopped before completing the review.")
		return
	print("Onboarding review frames: " + output)
	_finish_capture("")


func _prepare_review() -> String:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("--output="):
		return "Supply --output=<fresh absolute review frames directory>."
	if DisplayServer.get_name() == "headless":
		return "A graphical renderer is required."
	var repo := ProjectSettings.globalize_path("res://../../").simplify_path()
	var local := repo.path_join(".lore/local/onboarding-review")
	output = args[0].trim_prefix("--output=").simplify_path()
	var review := output.get_base_dir()
	if not output.is_absolute_path() or not review.begins_with(local + "/") \
			or output.get_file() != "frames":
		return "Output must be .lore/local/onboarding-review/<fresh run>/frames."
	for kind in ["data", "config", "cache"]:
		var path := review.path_join("xdg").path_join(kind)
		if OS.get_environment("XDG_" + kind.to_upper() + "_HOME") != path \
				or not DirAccess.dir_exists_absolute(path) or _has_symlink(repo, path):
			return "Set each XDG directory as shown in the script header: " + path
	if not OS.get_user_data_dir().begins_with(review.path_join("xdg/data") + "/") \
			or FileAccess.file_exists(_profile) or FileAccess.file_exists(Preferences.PATH):
		return "Refusing to use non-isolated or previously used profile/preferences."
	if _has_symlink(repo, output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		return "Cannot create a symlink-free review output at " + output
	var folder := DirAccess.open(output)
	if folder == null or not folder.get_files().is_empty() or not folder.get_directories().is_empty():
		return "The frames directory must be empty."
	return ""


func _has_symlink(repo: String, target: String) -> bool:
	var path := repo
	for component in target.trim_prefix(repo + "/").split("/"):
		var parent := DirAccess.open(path)
		if parent != null and parent.is_link(component):
			return true
		path = path.path_join(component)
	return false


func _mount_review(args: PackedStringArray) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(args)
	# The ordinary game flow, without importing a legacy profile into the review.
	scene.configure_profile_path(_profile)
	viewport.add_child(scene)
	await process_frame
	await process_frame


func _review_opening() -> bool:
	if not _screen_is("guild_creation"):
		return false
	var edit := _node("GuildName") as LineEdit
	if not await _click_control(edit, "Guild name"):
		return false
	for character in REVIEW_NAME:
		await _key(character.unicode_at(0))
	if not _expect(edit.text == REVIEW_NAME, "Typing in Guild name did not reach the form."):
		return false
	if not await _save_capture("01-guild-name-hints-on") or not await _open_help() \
			or not await _save_capture("02-help-contents") \
			or not await _press_topic("Choose a commission") \
			or not await _save_capture("03-help-commission-figure"):
		return false
	if not _expect(_figure_visible(), "The commission topic has no shipped figure."):
		return false
	await _key(KEY_ESCAPE)
	if not _expect(edit.text == REVIEW_NAME and edit.has_focus(),
			"Closing Help did not restore the typed guild name and focus."):
		return false
	if not await _open_options(true) or not await _save_capture("04-guild-options") \
			or not await _set_open_hints(false):
		return false
	await _key(KEY_ESCAPE)
	# The guild still gets founded through its actual form, with a repeatable board draw.
	seed(REVIEW_SEED)
	return await _press_button("CreateGuild") and _screen_is("battle")


func _review_practice() -> bool:
	var instruction := _node("PracticeInstruction") as Label
	if not _expect(_shown(_node("SkipPractice") as Control), "Practice has no Skip control.") \
			or not _expect(_shown(instruction) and not instruction.text.is_empty(), "Practice instructions are missing.") \
			or not _expect(not Preferences.load_show_hints(), "Optional hints are still enabled.") \
			or not await _save_capture("05-practice-instructions-hints-off") \
			or not await _press_button("StandingOrders") \
			or not await _save_capture("06-practice-standing-orders"):
		return false
	var picker := _node("WizardOrder") as OptionButton
	if not await _choose_order(picker, "Blast nearest") \
			or not _expect(scene.battle_snapshot().get("orders", {}).get("wizard") == "order_blast",
				"Practice did not apply the Wizard's Blast order."):
		return false
	var orders := _node("StandingOrders") as BaseButton
	if orders.button_pressed and not await _press_button("StandingOrders"):
		return false
	var player := StorybookDriver.new(self, scene)
	var opening: Dictionary = scene.battle_snapshot()
	var targets: Array = player.rules.targets(player.rules.state_before_action(opening, "wizard"), "wizard", "move")
	var board = _node("BridgeBoard")
	if not _expect(not targets.is_empty() and board != null, "Practice has no legal Wizard move.") \
			or not await player.select_actor("wizard"):
		return _expect(false, player.error if not player.error.is_empty() else failure)
	await _click(board.get_global_transform_with_canvas() * board.cell_center(targets[0].position))
	var draft: Dictionary = scene.get("_planned_state").get("overrides", {}).get("wizard", {})
	if not _expect(draft.get("ability_id") == "move", "The chosen tile did not stage a Wizard move.") \
			or not await _press_button_if_closed("ForecastDetails") \
			or not _expect(_shown(_node("ExtraDetails") as Control), "The Forecast sheet did not open.") \
			or not await _save_capture("07-practice-forecast-hints-off") \
			or not await _capture_battle_options():
		return false
	return await _press_button("SkipPractice") and _screen_is("commissions")


func _review_guild() -> bool:
	if not await _open_options(false) or not await _set_open_hints(true):
		return false
	await _key(KEY_ESCAPE)
	if not await _save_capture("09-commission-board-hints-on") \
			or not await _press_button("Petitions") or not _screen_is("petitions") \
			or not await _save_capture("10-guild-petitions") or not await _open_help() \
			or not await _save_capture("11-help-from-petitions"):
		return false
	await _key(KEY_ESCAPE)
	if not await _press_button("BackToCommissions") or not _screen_is("commissions") \
			or not await _press_button("Commission_0") or not _screen_is("guild"):
		return false
	for id in FOUNDERS:
		if not await _press_button("Recruit_" + id):
			return false
	if not _expect(scene.selected_recruits() == FOUNDERS, "Recruitment did not fill all three slots.") \
			or not await _save_capture("12-recruitment") or not await _press_button("EditHero_healer") \
			or not _expect(_shown(_node("LoadoutHero") as Control), "Healer loadout did not open.") \
			or not await _save_capture("13-healer-loadout") or not await _open_help() \
			or not await _press_topic("Recruit and deploy") \
			or not await _save_capture("14-help-recruitment-figure") \
			or not _expect(_figure_visible(), "The recruitment topic has no shipped figure."):
		return false
	await _key(KEY_ESCAPE)
	return await _press_button("StartAdventure") and _screen_is("routes") \
		and await _save_capture("15-field-reports")


func _review_standalone() -> bool:
	await _mount_review(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	if not _screen_is("battle") or not await _save_capture("16-standalone-battle-hints-on") \
			or not await _open_help() or not await _press_topic("Mission objective") \
			or not await _save_capture("17-help-contextual-objective"):
		return false
	await _key(KEY_ESCAPE)
	if not await _stage_gate_forecast() or not await _save_capture("18-standalone-live-forecast") \
			or not await _open_help() or not await _press_topic("Forecast") \
			or not await _save_capture("19-help-forecast-figure") \
			or not _expect(_figure_visible(), "The forecast topic has no shipped figure."):
		return false
	return await _press_topic("Combat controls") and await _save_capture("20-help-combat-controls") \
		and await _press_topic("Battle board") and await _save_capture("21-help-battle-board") \
		and await _press_topic("Commit a round") and await _save_capture("22-help-commit-controls")


func _stage_gate_forecast() -> bool:
	# Match the shipped figure: commit to B2, then preview B2 → C2 before opening Forecast.
	var board = _node("BridgeBoard")
	if not _expect(board != null, "The standalone battle has no interactive board."):
		return false
	for cell in [Vector2i(0, 1), Vector2i(1, 1)]:
		await _click(board.get_global_transform_with_canvas() * board.cell_center(cell))
	if not await _press_button("Commit") \
			or not _expect(scene.battle_snapshot().get("round", 0) == 2, "Could not reach round 2."):
		return false
	var deadline := Time.get_ticks_msec() + 5000
	while not (board.action_playback_snapshot() as Array).is_empty():
		if Time.get_ticks_msec() >= deadline:
			return _expect(false, "Standalone playback did not settle.")
		await process_frame
	for cell in [Vector2i(1, 1), Vector2i(2, 1)]:
		await _click(board.get_global_transform_with_canvas() * board.cell_center(cell))
	var draft: Dictionary = scene.get("_planned_state").get("overrides", {}).get("knight", {})
	return _expect(draft.get("ability_id") == "move", "Knight's plate move was not staged.") \
		and await _press_button_if_closed("ForecastDetails")


func _choose_order(picker: OptionButton, caption: String) -> bool:
	if not await _click_control(picker, "Wizard standing-order picker"):
		return false
	var popup := picker.get_popup()
	if not _expect(popup.visible, "Wizard's standing-order menu failed to open."):
		return false
	var wanted := -1
	for index in popup.item_count:
		if popup.get_item_text(index) == caption and not popup.is_item_disabled(index):
			wanted = index
			break
	if not _expect(wanted >= 0, "Wizard's standing-order menu lacks " + caption):
		return false
	# Dispatch to the viewport that embeds the native popup, as for a player's click.
	var point := Vector2(popup.position) \
		+ Vector2(popup.size.x * 0.5, popup.size.y * (wanted + 0.5) / popup.item_count)
	await _click(point)
	return _expect(not popup.visible, "Selecting the requested order did not close its menu.")


func _open_help() -> bool:
	return await _press_caption("?") \
		and _expect(_button_with_caption("Choose a commission", _node("GlobalHelp")) != null,
			"Help Contents did not open.")


func _press_topic(caption: String) -> bool:
	var overlay := _node("GlobalHelp")
	return _expect(overlay != null, "Global Help is missing.") \
		and await _click_control(_button_with_caption(caption, overlay), caption)


func _open_options(hints_expected: bool) -> bool:
	if not await _press_caption("Options"):
		return false
	var toggle := _button_with_caption("Show hints")
	return _expect(toggle != null and toggle.button_pressed == hints_expected,
		"Options did not open with the expected hints preference.")


func _capture_battle_options() -> bool:
	var button := _node("Options") as MenuButton
	if not await _click_control(button, "Battle Options"):
		return false
	var popup := button.get_popup()
	var captions := ["Show Grid", "Show Grid Labels", "Show Nameplates", "Always show health bar", "Show hints"]
	if not _expect(popup.visible and popup.item_count == captions.size() + 2,
			"Battle Options did not open with five settings, a separator, and Help."):
		return false
	for index in captions.size():
		if not _expect(popup.get_item_text(index) == captions[index] and popup.is_item_checkable(index),
				"Battle Options is missing " + captions[index]):
			return false
	if not _expect(not popup.is_item_checked(captions.size() - 1), "Battle Options shows hints enabled.") \
			or not _expect(popup.is_item_separator(captions.size())
				and popup.get_item_text(captions.size() + 1) == "Help (F1)"
				and not popup.is_item_checkable(captions.size() + 1), "Battle Options is missing the separated Help command.") \
			or not await _save_capture("08-battle-options-hints-off"):
		return false
	var skip := _node("SkipPractice") as Control
	var popup_rect := Rect2(Vector2(popup.position), Vector2(popup.size))
	var skip_rect := Rect2(skip.get_global_transform_with_canvas().origin, skip.size)
	print("Battle Options overlaps practice Skip: ", popup_rect.intersects(skip_rect))
	# Help is the final one-line command. Use its native popup row rather than signaling it.
	await _click(popup_rect.end - Vector2(popup_rect.size.x * 0.5, 14))
	if not _expect(not popup.visible and _button_with_caption("Choose a commission", _node("GlobalHelp")) != null,
			"Battle Options Help did not open the book.") \
			or not _screen_is("battle") \
			or not await _save_capture("08a-help-from-practice-options"):
		return false
	await _key(KEY_ESCAPE)
	await process_frame
	if not _screen_is("battle") or not _expect(popup.visible, "Closing Help did not restore Battle Options.") \
			or not _expect(_shown(_node("ExtraDetails") as Control), "Closing Help did not preserve the practice forecast."):
		return false
	await _key(KEY_ESCAPE)
	return _screen_is("battle") and _expect(not popup.visible, "Second Escape did not close Battle Options.")


func _set_open_hints(enabled: bool) -> bool:
	var toggle := _button_with_caption("Show hints")
	if not await _click_control(toggle, "Show hints"):
		return false
	return _expect(Preferences.load_show_hints() == enabled, "The hints choice was not saved.")


func _figure_visible() -> bool:
	for candidate in scene.find_children("*", "TextureRect", true, false):
		var image := candidate as TextureRect
		if _shown(image) and image.texture != null and image.texture.resource_path.begins_with("res://assets/help/"):
			return true
	return false


func _press_button_if_closed(node_name: String) -> bool:
	var button := _node(node_name) as BaseButton
	return (button != null and button.toggle_mode and button.button_pressed) or await _press_button(node_name)


func _press_caption(caption: String) -> bool:
	return await _click_control(_button_with_caption(caption), caption)


func _button_with_caption(caption: String, scope: Node = null) -> Button:
	var match_button: Button
	var container := scene if scope == null else scope
	for candidate in container.find_children("*", "Button", true, false):
		var button := candidate as Button
		if _shown(button) and button.text.strip_edges().to_lower() == caption.to_lower():
			if match_button == null or not button is MenuButton:
				match_button = button
	return match_button


func _click_control(control: Control, caption: String) -> bool:
	var button := control as BaseButton
	if not _expect(_shown(control) and (button == null or not button.disabled),
			"%s is not available." % caption):
		return false
	var parent := control.get_parent()
	while parent != null and parent != viewport:
		if parent is ScrollContainer:
			parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await process_frame
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	if not _expect(Rect2(Vector2.ZERO, Vector2(SIZE)).has_point(point),
			"%s is outside the capture viewport." % caption):
		return false
	await _click(point)
	await process_frame
	return true


func _shown(control: Control) -> bool:
	return control != null and control.is_visible_in_tree()


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		failure = message
	return condition
