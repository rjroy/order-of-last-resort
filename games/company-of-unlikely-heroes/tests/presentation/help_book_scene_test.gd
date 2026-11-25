extends SceneTree

# Run with a fresh, private XDG_DATA_HOME; see the test handoff for the command.
# This test changes player settings, so it refuses to run outside that sandbox.
var failures: Array[String] = []
var scene: Node
var profile_path := "user://help_test_guild.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sandbox := OS.get_environment("OLR_TEST_SANDBOX")
	if sandbox.is_empty() or not sandbox.is_absolute_path() \
			or OS.get_environment("XDG_DATA_HOME") != sandbox \
			or not OS.get_user_data_dir().begins_with(sandbox.trim_suffix("/") + "/"):
		push_error("Set OLR_TEST_SANDBOX and XDG_DATA_HOME to the same fresh absolute directory.")
		quit(1)
		return
	root.size = Vector2i(1280, 820)
	await _launch(PackedStringArray())
	var name_edit := scene.find_child("GuildName", true, false) as LineEdit
	_check(name_edit != null and name_edit.is_visible_in_tree(), "Fresh profile opens guild naming")
	if name_edit != null:
		await _test_founding_hints(name_edit, true)
		name_edit.text = "A guild in progress"
		name_edit.grab_focus()
		name_edit.select(2, 7)
		await process_frame
		var caret := name_edit.caret_column
		var selection_from := name_edit.get_selection_from_column()
		var selection_to := name_edit.get_selection_to_column()
		_check(name_edit.has_selection() and selection_from == 2 and selection_to == 7,
			"Name fixture has a nonempty substring selected")
		if await _mouse_open_help():
			await _check_index()
			await _escape()
			_check(scene.current_screen() == "guild_creation", "Escape returns to guild naming")
			_check(name_edit.is_inside_tree() and name_edit.text == "A guild in progress"
				and name_edit.caret_column == caret, "Help preserves unfinished name and caret")
			_check(root.gui_get_focus_owner() == name_edit, "Help restores name input focus")
			_check(name_edit.has_selection() and name_edit.get_selection_from_column() == selection_from
				and name_edit.get_selection_to_column() == selection_to,
				"Mouse-opened Help restores the name's selected substring")
		if await _mouse_open_help():
			await _mouse_close_help()
			_check(scene.current_screen() == "guild_creation", "Mouse close returns to guild naming")
			_check(name_edit.is_inside_tree() and name_edit.text == "A guild in progress"
				and name_edit.caret_column == caret, "Mouse close preserves unfinished name and caret")
			_check(root.gui_get_focus_owner() == name_edit, "Mouse close restores name input focus")
			_check(name_edit.has_selection() and name_edit.get_selection_from_column() == selection_from
				and name_edit.get_selection_to_column() == selection_to,
				"Mouse close restores the name's selected substring")
	await _test_options()
	# Reload both the scene and preferences, not merely the open Options panel.
	await _launch(PackedStringArray())
	if await _open_options():
		var hints := _button("Show hints")
		_check(hints != null and not hints.button_pressed, "Hints preference survives a scene reload")
		await _close_options()
	name_edit = scene.find_child("GuildName", true, false) as LineEdit
	if name_edit != null:
		await _test_founding_hints(name_edit, false)
		name_edit.text = "Test Company"
		name_edit.text_changed.emit(name_edit.text)
		await process_frame
		var create := _named_button("CreateGuild")
		_check(create != null and not create.disabled and not FileAccess.file_exists(profile_path),
			"Valid guild draft is ready and no profile exists")
		if create != null and not create.disabled and await _mouse_open_help():
			create.pressed.emit()
			await process_frame
			_check(scene.current_screen() == "guild_creation" and not FileAccess.file_exists(profile_path),
				"Queued Create guild callback cannot create a profile while Help is open")
			await _escape()
			if scene.current_screen() == "guild_creation":
				await _mouse_click_control(create, "Create guild after Help")
				_check(FileAccess.file_exists(profile_path),
					"Clicking Create guild after Help closes creates the profile")
		_check(scene.current_screen() == "battle", "New guild enters the teaching mission with hints off")
		if scene.current_screen() == "battle":
			var skip := _button_containing("skip")
			_check(skip != null, "Skip remains available with optional hints off")
			_check(not _visible_text().strip_edges().is_empty(), "Lesson instructions remain visible with hints off")
			if await _open_help():
				_check(_button_containing("objective") != null, "Book remains available with hints off")
				await _escape()
			await _activate(skip, "Skip")
			_check(scene.current_screen() == "commissions", "Skip reaches the commission board")
			if scene.current_screen() == "commissions":
				await _test_petition_filter()
	# A fixed standalone encounter gives a stable, known objective and legal target.
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	await _test_battle()
	await _test_modal_accessibility_activation()
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: help_book_scene_test")
	else:
		for failure in failures:
			push_error("FAIL: help_book_scene_test: " + failure)
	quit(0 if failures.is_empty() else 1)


func _launch(args: PackedStringArray) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_profile_path(profile_path)
	scene.configure_launch(args)
	root.add_child(scene)
	await process_frame
	await process_frame


func _test_options() -> void:
	if not await _open_options():
		return
	var hints := _button("Show hints")
	_check(hints != null and hints.toggle_mode, "Options offers a Show hints switch")
	if hints != null and hints.toggle_mode:
		_check(hints.button_pressed, "Hints are on by default")
		hints.grab_focus()
		for down in [true, false]:
			var event := InputEventAction.new()
			event.action = "ui_accept"
			event.pressed = down
			root.push_input(event, true)
			await process_frame
		_check(not hints.button_pressed, "Show hints can be turned off")
	await _close_options()


func _test_founding_hints(name_edit: LineEdit, enabled: bool) -> void:
	# The next action must be present without hover or focus when hints are on.
	await _move_mouse(Vector2(1275, 815))
	name_edit.grab_focus()
	await process_frame
	var text := _visible_text().to_lower()
	if enabled:
		_check("guild name" in text and "create" in text,
			"Next-action hint tells the player to enter a guild name and create it")
	else:
		_check(not ("guild name" in text and "then create" in text),
			"Disabling hints hides the next-action explanation")
	name_edit.text = "Hint test"
	name_edit.text_changed.emit(name_edit.text)
	await process_frame
	var create := _named_button("CreateGuild")
	if create == null:
		_check(false, "Create guild exists for focus and hover hints")
		return
	var hint := create.tooltip_text.strip_edges()
	if enabled:
		_check(not hint.is_empty() and "guild" in hint.to_lower()
			and ("practice" in hint.to_lower() or "lesson" in hint.to_lower()),
			"Create guild hint explains the consequence of creating a guild")
	else:
		_check(hint.is_empty(), "Disabling hints removes the create-guild hover tooltip")
	create.grab_focus()
	await process_frame
	if enabled and not hint.is_empty():
		_check(hint in _visible_text(), "Keyboard focus reveals the control explanation without hovering")
	elif not enabled:
		_check("begin the practice lesson" not in _visible_text().to_lower(),
			"Keyboard focus does not show the optional explanation when disabled")
	name_edit.grab_focus()
	await _move_mouse(create.get_global_transform_with_canvas() * (create.size / 2.0))
	if enabled and not hint.is_empty():
		_check(hint in _visible_text(), "Pointer hover reveals the same control explanation")
	elif not enabled:
		_check("begin the practice lesson" not in _visible_text().to_lower(),
			"Pointer hover does not show the optional explanation when disabled")
	await _move_mouse(Vector2(1275, 815))


func _test_petition_filter() -> void:
	var entry := _named_button("Petitions")
	if not await _mouse_click_control(entry, "Guild petitions"):
		return
	var filter := scene.find_child("PetitionHeroFilter", true, false) as OptionButton
	_check(filter != null and filter.is_visible_in_tree(), "Petitions exposes the hero filter")
	if filter == null or not filter.is_visible_in_tree():
		return
	var bard := -1
	for i in filter.item_count:
		if "bard" in filter.get_item_text(i).to_lower():
			bard = i
	_check(bard >= 0, "Petitions filter offers Bard")
	if bard < 0:
		return
	filter.grab_focus()
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	var popup := filter.get_popup()
	_check(popup.visible, "Keyboard opens the petitions filter")
	if not popup.visible:
		return
	for attempt in popup.item_count + 1:
		if popup.get_focused_item() == bard:
			break
		await _key(KEY_DOWN, true)
		await _key(KEY_DOWN, false)
	if popup.get_focused_item() != bard:
		_check(false, "Keyboard reaches Bard in petitions filter")
		popup.hide()
		return
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	await process_frame
	filter = scene.find_child("PetitionHeroFilter", true, false) as OptionButton
	if filter == null:
		_check(false, "Petitions filter remains present after selecting Bard")
		return
	_check(filter.get_item_text(filter.selected).to_lower().contains("bard"),
		"Petitions applies the Bard filter")
	var scroll := scene.find_child("PetitionScroll", true, false) as ScrollContainer
	var scroll_before := scroll.scroll_vertical if scroll != null else -1
	filter.grab_focus()
	await process_frame
	if await _mouse_open_help():
		await _mouse_close_help()
		var restored := scene.find_child("PetitionHeroFilter", true, false) as OptionButton
		_check(restored == filter and restored.is_visible_in_tree()
			and restored.get_item_text(restored.selected).to_lower().contains("bard"),
			"Help preserves the petitions filter and selection")
		_check(root.gui_get_focus_owner() == filter, "Help restores petitions filter focus")
		_check(scroll == null or (scroll.is_inside_tree() and scroll.scroll_vertical == scroll_before),
			"Help preserves petitions scroll position")


func _test_battle() -> void:
	_check(scene.current_screen() == "battle", "Standalone fixture opens battle")
	if scene.current_screen() != "battle":
		return
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var staged: bool = await driver.command("wizard", "wizard_pull", "healer")
	_check(staged, "Can stage an aimed direct command: " + driver.error)
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var planned: Dictionary = scene.get("_planned_state").duplicate(true)
	var forecast: Dictionary = scene.get("_plan").duplicate(true)
	var actor: String = scene.get("_actor_id")
	var target: String = scene.get("_target_id")
	var focus := scene.find_child("Commit", true, false) as Control
	if focus != null:
		focus.grab_focus()
		await process_frame
	if await _open_help():
		var objective := _button_containing("objective")
		if await _activate(objective, "Objective index entry"):
			var text := _visible_text().to_lower()
			_check("exit" in text and "plate" in text and "gate" in text,
				"Objective page describes this battle's exit, plate and gate")
		await _escape()
		_check(scene.battle_snapshot() == before, "Help does not advance battle")
		_check(scene.get("_planned_state") == planned and scene.get("_plan") == forecast,
			"Help preserves uncommitted command and forecast")
		_check(scene.get("_actor_id") == actor and scene.get("_target_id") == target,
			"Help preserves selected actor and target")
		if focus != null:
			_check(root.gui_get_focus_owner() == focus, "Help restores battle keyboard focus")
	var forecast_button := _named_button("ForecastDetails")
	if await _activate(forecast_button, "Forecast"):
		var page = scene.get("_storybook_page")
		var forecast_panel: Control = page.get("_forecast_scroll") if is_instance_valid(page) else null
		_check(forecast_panel != null and forecast_panel.is_visible_in_tree(),
			"Forecast secondary panel opens before Help")
		if forecast_panel != null and forecast_panel.is_visible_in_tree():
			forecast_panel.grab_focus()
			await process_frame
			if await _open_help():
				await _mouse_close_help()
				_check(forecast_panel.is_visible_in_tree(), "Mouse close restores the open forecast panel")
				_check(root.gui_get_focus_owner() == forecast_panel, "Mouse close restores forecast panel focus")
				_check(scene.battle_snapshot() == before and scene.get("_planned_state") == planned
					and scene.get("_plan") == forecast, "Forecast and staged command survive Help over secondary panel")
				_check(scene.get("_actor_id") == actor and scene.get("_target_id") == target,
					"Help over forecast preserves selected actor and target")
	await _test_battle_options(before, planned, actor)


func _test_battle_options(before: Dictionary, planned: Dictionary, actor: String) -> void:
	var menus: Array[MenuButton] = []
	var options_count := 0
	for node in scene.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.text.to_lower() == "options":
			options_count += 1
			if node is MenuButton:
				menus.append(node)
	_check(options_count == 1 and menus.size() == 1,
		"Battle exposes one Options control and it is the native menu")
	if menus.size() != 1:
		return
	var button := menus[0]
	button.grab_focus()
	await process_frame
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	var menu := button.get_popup()
	_check(menu.visible, "Keyboard opens battle Options")
	if not menu.visible:
		return
	var expected := {"Show Grid": 0, "Show Nameplates": 1, "Show Grid Labels": 2,
		"Always show health bar": 3, "Show hints": 4}
	var hints_index := -1
	var help_index := -1
	var check_count := 0
	for i in menu.item_count:
		if menu.is_item_checkable(i):
			check_count += 1
		if menu.get_item_text(i).to_lower() == "help (f1)":
			help_index = i
	_check(check_count == 5, "Battle Options has five checkable entries")
	_check(help_index >= 0 and not menu.is_item_checkable(help_index)
		and not menu.is_item_disabled(help_index), "Battle Options offers Help (F1)")
	for label in expected:
		var index := -1
		for i in menu.item_count:
			if menu.get_item_text(i).to_lower() == label.to_lower():
				index = i
				break
		_check(index >= 0, "Battle Options contains " + label)
		if index >= 0:
			_check(menu.is_item_checkable(index) and menu.get_item_id(index) == expected[label],
				label + " is checkable and retains its option ID")
			if label == "Show hints":
				hints_index = index
	if hints_index < 0:
		menu.hide()
		return
	_check(not menu.is_item_checked(hints_index), "Battle menu shares the persisted hints-off choice")
	for attempt in menu.item_count + 1:
		if menu.get_focused_item() == hints_index:
			break
		await _key(KEY_DOWN, true)
		await _key(KEY_DOWN, false)
	if menu.get_focused_item() != hints_index:
		_check(false, "Keyboard navigation reaches Show hints")
		menu.hide()
		return
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	await process_frame
	_check(menu.is_item_checked(hints_index), "Keyboard toggles hints on through the native menu")
	_check(scene.battle_snapshot() == before and scene.get("_planned_state") == planned
		and scene.get("_actor_id") == actor, "Changing hints preserves the battle and planned command")
	if help_index >= 0:
		for attempt in menu.item_count + 1:
			if menu.get_focused_item() == help_index:
				break
			await _key(KEY_DOWN, true)
			await _key(KEY_DOWN, false)
		if menu.get_focused_item() == help_index:
			await _key(KEY_ENTER, true)
			await _key(KEY_ENTER, false)
			await process_frame
			_check(_button_containing("credits") != null, "Keyboard Help action opens the help index")
			await _key(KEY_ESCAPE, true)
			await _key(KEY_ESCAPE, false)
			await process_frame
			await process_frame
			_check(menu.visible, "Closing Help restores its source Options popup")
			_check(root.gui_get_focus_owner() == button or menu.has_focus(),
				"Closing Help restores focus to Options or its popup")
			_check(scene.battle_snapshot() == before and scene.get("_planned_state") == planned,
				"Help from Options preserves the battle and planned command")
		else:
			_check(false, "Keyboard navigation reaches Help (F1) in Options")
	if menu.visible and DisplayServer.get_name() == "X11":
		menu.grab_focus()
		await process_frame
		_check(menu.has_focus(), "Options popup has focus before native F1")
		var handles := PackedStringArray([
			ProjectSettings.globalize_path("res://tests/support/help_f1_x11.py"),
			str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, root.get_window_id())),
			str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, menu.get_window_id())),
		])
		var output := []
		var status := OS.execute("python3", handles, output, true)
		_check(status == 0, "Native F1 is sent only to the focused test window: " + str(output))
		await create_timer(0.1).timeout
		await process_frame
		await process_frame
		_check(_button_containing("credits") != null,
			"F1 delivered to the focused Options popup opens Help")
		if _button_containing("credits") != null:
			await _key(KEY_ESCAPE, true)
			await _key(KEY_ESCAPE, false)
			await process_frame
			await process_frame
			_check(menu.visible, "Closing popup F1 Help restores the same Options popup")
			_check(root.gui_get_focus_owner() == button or menu.has_focus(),
				"Closing popup F1 Help restores Options focus")
			_check(scene.battle_snapshot() == before and scene.get("_planned_state") == planned,
				"F1 from the popup preserves battle and planned command")
	elif not menu.visible:
		_check(false, "Options popup is open for its F1 check")
	else:
		print("SKIP: native popup F1 requires graphical X11, XTEST and python3")
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	button.grab_focus()
	await _key(KEY_F1, true)
	await _key(KEY_F1, false)
	_check(_button_containing("credits") != null, "F1 opens the help index during battle")
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	_check(root.gui_get_focus_owner() == button, "Closing F1 Help restores the prior focus")
	_check(scene.battle_snapshot() == before and scene.get("_planned_state") == planned,
		"F1 Help preserves the battle and planned command")
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	var reloaded := _named_button("Options") as MenuButton
	if reloaded == null:
		_check(false, "Reloaded battle has its native Options menu")
	else:
		var popup := reloaded.get_popup()
		var index := popup.get_item_index(4)
		_check(index >= 0 and popup.is_item_checked(index), "Battle hint choice persists after reload")
	await _launch(PackedStringArray())
	if await _open_options():
		var hints := _button("Show hints")
		_check(hints != null and hints.button_pressed, "Battle hint choice is shared with guild Options")
		await _close_options()


func _test_modal_accessibility_activation() -> void:
	# Accessibility activation can invoke the action even while ordinary input
	# is blocked; use the same pressed signal that the control's callback sees.
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	var staged: bool = await driver.command("wizard", "wizard_pull", "healer")
	_check(staged, "Accessibility fixture stages an aimed command: " + driver.error)
	var commit := _named_button("Commit")
	_check(commit != null and commit.is_visible_in_tree() and not commit.disabled,
		"Accessibility fixture has an enabled Commit")
	if commit != null and not commit.disabled and await _mouse_open_help():
		var before: Dictionary = scene.battle_snapshot().duplicate(true)
		var draft: Dictionary = scene.get("_planned_state").duplicate(true)
		var options := _named_button("Options") as MenuButton
		_check(options != null, "Battle has a native Options menu behind Help")
		if options != null:
			options.show_popup()
			await process_frame
			await process_frame
			var popup := options.get_popup()
			_check(not popup.visible and _button_containing("credits") != null,
				"Native Options popup cannot cover Help or grab its input")
			if popup.visible:
				popup.hide()
				await process_frame
		commit.pressed.emit()
		await process_frame
		_check(scene.battle_snapshot() == before and scene.get("_planned_state") == draft,
			"Commit accessibility callback cannot advance battle while Help is open")
		await _escape()
		if scene.battle_snapshot() == before and is_instance_valid(commit) and not commit.disabled:
			commit.pressed.emit()
			await process_frame
			_check(scene.battle_snapshot() != before, "Commit works again after Help closes")
	# Reset so a failing Commit guard does not corrupt the separate forfeit case.
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	staged = await driver.command("wizard", "wizard_pull", "healer")
	_check(staged, "Forfeit accessibility fixture stages a command: " + driver.error)
	var forfeit := _named_button("Forfeit")
	if not await _mouse_click_control(forfeit, "Forfeit"):
		return
	var confirm := _named_button("ConfirmForfeit")
	var cancel := _named_button("CancelForfeit")
	_check(confirm != null and confirm.is_visible_in_tree() and not confirm.disabled,
		"Forfeit confirmation has an enabled affirmative action")
	var page: Control = scene.get("_storybook_page")
	var surface: Control = page.get("_surface_root") if is_instance_valid(page) else null
	_check(surface != null and bool(surface.get("_inert")),
		"Forfeit confirmation already makes the battle surface inaccessible")
	if confirm == null or not confirm.is_visible_in_tree() or not await _mouse_open_help():
		return
	_check(surface != null and is_instance_valid(surface) and bool(surface.get("_inert")),
		"Help does not expose the battle surface already inert under Forfeit")
	var before: Dictionary = scene.battle_snapshot().duplicate(true)
	var draft: Dictionary = scene.get("_planned_state").duplicate(true)
	confirm.pressed.emit()
	await process_frame
	_check(scene.current_screen() == "battle" and scene.battle_snapshot() == before
		and scene.get("_planned_state") == draft and is_instance_valid(confirm)
		and confirm.is_visible_in_tree(),
		"Confirm Forfeit accessibility callback cannot end battle while Help is open")
	await _escape()
	_check(surface != null and is_instance_valid(surface) and bool(surface.get("_inert")),
		"Closing Help preserves the preexisting inert battle surface under Forfeit")
	if is_instance_valid(confirm) and confirm.is_visible_in_tree() and scene.battle_snapshot() == before:
		confirm.pressed.emit()
		await process_frame
		_check(scene.battle_snapshot().get("outcome") == "defeat",
			"Confirm Forfeit works again after Help closes")
	elif is_instance_valid(cancel) and cancel.is_visible_in_tree():
		cancel.pressed.emit()


func _check_index() -> void:
	for topic in ["found", "commission", "deploy", "report", "combat", "standing",
			"command", "forecast", "objective", "debrief", "reward"]:
		_check(topic in _visible_text().to_lower(), "Help index includes " + topic)
	var illustrated := _button_containing("commission")
	if await _activate(illustrated, "Commission index entry"):
		var has_figure := false
		var has_caption := false
		for node in scene.find_children("*", "TextureRect", true, false):
			if node.is_visible_in_tree() and node.texture != null \
					and node.texture.resource_path.begins_with("res://assets/help/"):
				has_figure = true
				var parent := node.get_parent()
				if parent != null:
					for label in parent.find_children("*", "Label", true, false):
						if label.is_visible_in_tree() and not label.text.strip_edges().is_empty():
							has_caption = true
		_check(has_figure, "Illustrated commission page displays a shipped help texture")
		_check(has_caption, "Illustration has a visible caption in its figure container")
		var index := _button_containing("index")
		await _activate(index, "Return to help index")
	var credits := _button_containing("credits")
	if await _activate(credits, "Credits index entry"):
		var text := _visible_text().to_lower()
		_check("made with godot engine" in text, "Credits say Made with Godot Engine")
		_check("godot" in text and ("contributors" in text or "contributor" in text),
			"Credits thank Godot contributors")
		_check("game designer" in text, "Credits identify the game designer")
		var expected := {
			"Ronald Roy": "https://rjroy.github.io/",
			"Godot Engine license": "https://godotengine.org/license/",
			"OpenCode": "https://opencode.ai/",
			"OpenAI": "https://openai.com/",
			"Mirli": "https://mirli.app/",
		}
		for link: LinkButton in scene.find_children("*", "LinkButton", true, false):
			if not link.is_visible_in_tree():
				continue
			_check(link.uri == expected.get(link.text, ""), "Credit destination: " + link.text)
			expected.erase(link.text)
			var panel := link.get_parent()
			while not panel is PanelContainer:
				panel = panel.get_parent()
			var paper := panel.get_theme_stylebox("panel") as StyleBoxFlat
			for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
				var ink := link.get_theme_color(state).srgb_to_linear().get_luminance()
				var page := paper.bg_color.srgb_to_linear().get_luminance()
				_check((page + 0.05) / (ink + 0.05) >= 4.5, "Readable credit link: " + state)
		_check(expected.is_empty(), "Missing credit links: " + str(expected.keys()))


func _open_help() -> bool:
	var help := _button("?")
	if help == null:
		_check(false, "A visible ? help button is available")
		return false
	_check(help.focus_mode != Control.FOCUS_NONE, "? accepts keyboard focus")
	return await _activate(help, "?")


func _mouse_open_help() -> bool:
	var help := _button("?")
	if not await _mouse_click_control(help, "?"):
		return false
	var opened := _button_containing("credits") != null
	_check(opened, "Mouse click on ? opens the Help index")
	return opened


func _open_options() -> bool:
	return await _activate(_button("Options"), "Options")


func _close_options() -> void:
	await _escape()


func _escape() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		root.push_input(event, true)
		await process_frame


func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	root.push_input(event, true)
	await process_frame


func _mouse_click_control(control: Control, description: String) -> bool:
	if control == null or not control.is_visible_in_tree() \
			or (control is BaseButton and (control as BaseButton).disabled):
		_check(false, description + " is visible and enabled")
		return false
	var point := control.get_global_transform_with_canvas() * (control.size / 2.0)
	await _move_mouse(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event, true)
		await process_frame
	return true


func _mouse_close_help() -> void:
	var close := _button("Close")
	if close == null or close.disabled:
		_check(false, "Help has a visible enabled Close button for mouse use")
		return
	var point := close.get_global_transform_with_canvas() * (close.size / 2.0)
	await _move_mouse(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event, true)
		await process_frame
	_check(_button("Close") == null, "Mouse click closes the help overlay")


func _move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await process_frame


func _activate(button: BaseButton, description: String) -> bool:
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check(false, description + " is visible and enabled")
		return false
	button.pressed.emit()
	await process_frame
	await process_frame
	return true


func _named_button(name: String) -> BaseButton:
	return scene.find_child(name, true, false) as BaseButton


func _button(text: String) -> BaseButton:
	for node in scene.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.text.strip_edges().to_lower() == text.to_lower():
			return node
	return null


func _button_containing(text: String) -> BaseButton:
	for node in scene.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and text.to_lower() in node.text.to_lower():
			return node
	return null


func _visible_text() -> String:
	var result := ""
	for node in scene.find_children("*", "", true, false):
		if node is Label and node.is_visible_in_tree():
			result += " " + node.text
		elif node is RichTextLabel and node.is_visible_in_tree():
			result += " " + node.text
		elif node is Button and node.is_visible_in_tree():
			result += " " + node.text
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
