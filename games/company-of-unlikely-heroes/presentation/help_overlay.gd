extends CanvasLayer
## Independent of the current page: opening the book never rebuilds game state.

const Preferences = preload("res://battle_display_preferences.gd")
const Prep = preload("res://presentation/guild_prep_widgets.gd")
const VolumeControls = preload("res://presentation/volume_controls.gd")
const TOPICS := {
	"Found a guild": ["Name your guild and choose Create guild. Your guild keeps its points and purchases between commissions.", ""],
	"Choose a commission": ["Choose a destination and commission length. Choosing a commission starts recruitment; it does not start a battle. The illustrated commission is an example.", "commission-selection"],
	"Recruit and deploy": ["Recruit three different heroes. Earlier and Later change their deployment and action order. Edit loadout changes their equipped abilities and starting order.", "recruitment"],
	"Field reports": ["Read both reports and choose a route. Each report describes the next mission and only hints at what follows. The reports shown are examples.", "field-reports"],
	"Combat controls": ["Select a hero and a destination to plan a move, or choose Actions and a target. The command is only a preview until you commit.", "battle-controls"],
	"Battle board": ["Select a hero or a target on the board. The highlighted cells show the current choices.", "battle-board"],
	"Commit a round": ["Commit plays the forecasted round. Until then you can change or clear your command.", "battle-commit"],
	"Standing orders": ["Each hero follows their standing order every round unless you directly command that hero. Change orders using Standing orders.", ""],
	"Direct command": ["One hero can receive a direct command for this round. The other heroes follow their standing orders; the replaced order returns next round.", "battle-controls"],
	"Forecast": ["Open Forecast to compare the planned actions in initiative order. Change or clear the command before committing; nothing resolves until Commit.", "battle-forecast"],
	"Mission objective": ["The current battle objective appears here.", ""],
	"Debrief and rewards": ["After a road victory, review the party and choose one offered reward before continuing. Survivors carry wounds and standing orders; fallen heroes return at 1 HP. Rewards last only for the outing.", ""],
	"Practice lesson": ["Replay the practice lesson from the commission board. Practice has no payout or lasting wounds and does not replace a live commission.", ""],
	"Credits": ["Made with Godot Engine\n\nThank you to the Godot contributors.\nhttps://godotengine.org/license/", ""],
}
const CAPTIONS := {
	"commission-selection": "Example: choose a destination from the commission board.",
	"recruitment": "Recruit three heroes and arrange their deployment order.",
	"field-reports": "Example: compare the disclosed reports before choosing a route.",
	"battle-controls": "Select a hero, then plan an action using the battle controls.",
	"battle-forecast": "The forecast shows the planned round before it is committed.",
	"battle-board": "The board shows heroes, targets and highlighted choices.",
	"battle-commit": "Commit plays the planned round.",
}

var _bar: HBoxContainer
var _help: Button
var _options: Button
var _shade: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer
var _prior_focus: Control
var _last_game_focus: Control
var _hints := true
var _tip: Label
var _current_screen := ""
var _hint_controls: Dictionary = {}
var _original_tooltips: Dictionary = {}
var _screen_root: Control
var _screen_focus_behavior: int
var _screen_mouse_behavior: int
var _screen_input := false
var _overlay_kind := ""
var _return_to_options := false
var _popup_source: Control
var _popup_focus_row := -1
var _popup_rows: Dictionary = {}
var _last_screen_root: Control
var _dialog_source: Window
var _dialog_focus: Control
var _selection_edit: LineEdit
var _selection_start := -1
var _selection_end := -1
var _selection_caret := 0
var _board_focus_cell: Variant = null
var _covered_connections: Array[Dictionary] = []
var _cover_active := false
const FILTER_HELP_ID := 1000000


func _ready() -> void:
	_hints = Preferences.load_show_hints()
	get_viewport().gui_focus_changed.connect(_focus_changed)
	get_tree().node_added.connect(_node_added)
	_bar = HBoxContainer.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_constant_override("separation", 12)
	_bar.position = Vector2(1100, 22)
	add_child(_bar)
	_help = _button("?", "Open the help book")
	_help.accessibility_description = "Open Help. Keyboard shortcut: F1."
	_options = _button("Options", "Change player options")
	_bar.add_child(_help)
	_bar.add_child(_options)
	_bar.move_child(_help, 1)
	_help.custom_minimum_size = Vector2(44, 41)
	_options.custom_minimum_size = Vector2(104, 41)
	_help.pressed.connect(_open_help)
	_options.pressed.connect(_open_options)
	_tip = Label.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.position = Vector2(8, 54)
	_tip.add_theme_color_override("font_color", Color("#fff1c9"))
	_tip.add_theme_color_override("font_shadow_color", Color("#18110d"))
	_tip.add_theme_constant_override("shadow_offset_x", 1)
	_tip.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_tip)
	_shade = ColorRect.new()
	_shade.color = Color(0.08, 0.06, 0.04, 0.48)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.hide()
	add_child(_shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 72
	_panel.offset_right = -72
	_panel.offset_top = 52
	_panel.offset_bottom = -52
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("#f3e3be")
	paper.border_color = Color("#6c4b32")
	paper.set_border_width_all(5)
	paper.set_corner_radius_all(5)
	_panel.add_theme_stylebox_override("panel", paper)
	_shade.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_panel.add_child(margin)
	_body = VBoxContainer.new()
	margin.add_child(_body)
	# Keep the global help button above the overlay, even on secondary surfaces.
	move_child(_bar, -1)
	_install_hints(get_parent())


func _process(_delta: float) -> void:
	var game := get_parent()
	var screen: String = game.current_screen()
	if not _shade.visible:
		_record_selection(get_viewport().gui_get_focus_owner())
		_record_board_focus(get_viewport().gui_get_focus_owner())
	if not _shade.visible:
		_options.visible = screen != "battle"
		_bar.size = _bar.get_combined_minimum_size()
		for popup in _popup_rows:
			if is_instance_valid(popup) and popup.visible and popup.get_focused_item() >= 0:
				_popup_rows[popup] = popup.get_focused_item()
	if screen != _current_screen:
		_current_screen = screen
		_update_next_step()
	if not _hints:
		for control in _hint_controls:
			if is_instance_valid(control) and not control.tooltip_text.is_empty():
				_original_tooltips[control] = control.tooltip_text
				control.tooltip_text = ""
	var root: Control = game.get("_screen_root")
	if is_instance_valid(root):
		if root != _last_screen_root:
			_last_screen_root = root
			_update_next_step()
		var slot := root.find_child("HelpUtilitySlot", true, false) as Control
		if _shade.visible:
			_bar.position = Vector2(get_viewport().get_visible_rect().size.x - 54, 6)
		elif is_instance_valid(slot):
			_bar.position = slot.get_global_rect().position
		if not _shade.visible:
			var viewport_size := get_viewport().get_visible_rect().size
			_bar.position.x = clampf(_bar.position.x, 0, maxf(0, viewport_size.x - _bar.size.x))
			_bar.position.y = clampf(_bar.position.y, 0, maxf(0, viewport_size.y - _bar.size.y))
		if screen == "battle":
			_tip.position = Vector2(42, 82)
			_tip.add_theme_color_override("font_color", Color("#fff1c9"))
			_tip.visible = _hints and not is_instance_valid(root.get("_practice_controls"))
		else:
			var hint_slot := root.find_child("HelpHintSlot", true, false) as Control
			if is_instance_valid(hint_slot):
				_tip.position = hint_slot.get_global_rect().position
			_tip.add_theme_color_override("font_color", Color("#35241b"))
			_tip.visible = _hints and is_instance_valid(hint_slot)


func _focus_changed(control: Control) -> void:
	if control != null and not is_ancestor_of(control):
		_last_game_focus = control
	if _hints and control != null and _hint_controls.has(control):
		_tip.text = _hint_controls[control]


func _button(text: String, description := "") -> Button:
	var button := Button.new()
	button.text = text
	button.accessibility_name = description if not description.is_empty() else text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", Prep.serif())
	button.add_theme_font_size_override("font_size", 17)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("#302419"))
	button.add_theme_stylebox_override("normal", _button_style(Color("#f2dcb5"), Color("#b5976f")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#fceac7"), Color("#865833")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#ddbe87"), Color("#814818")))
	button.add_theme_stylebox_override("hover_pressed", _button_style(Color("#e9ca94"), Color("#814818")))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#9b500d")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(3)
	button.add_theme_stylebox_override("focus", focus)
	return button


func _button_style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _begin_overlay() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	_record_selection(focus)
	_record_board_focus(focus)
	_prior_focus = _last_game_focus if focus == _help or focus == _options else focus
	_screen_root = get_parent().get("_screen_root")
	if is_instance_valid(_screen_root):
		_cover_active = true
		_guard_covered_actions(_screen_root)
		if _screen_root.has_method("set_help_covered"):
			_screen_root.set_help_covered(true)
		_screen_focus_behavior = _screen_root.focus_behavior_recursive
		_screen_mouse_behavior = _screen_root.mouse_behavior_recursive
		_screen_input = _screen_root.is_processing_input()
		_screen_root.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		_screen_root.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		_screen_root.set_process_input(false)
	_shade.show()
	_options.hide()
	_clear_body()


func _clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _open_help() -> void:
	if not _shade.visible:
		_begin_overlay()
		_return_to_options = false
	elif _overlay_kind == "options":
		_return_to_options = true
	_overlay_kind = "help"
	_set_panel_compact(false)
	_show_index()


func _show_index() -> void:
	_show_topic("")


func _show_topic(topic: String) -> void:
	_clear_body()
	_add_header("Help book" if topic.is_empty() else topic)
	var spread := HBoxContainer.new()
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spread.add_theme_constant_override("separation", 28)
	_body.add_child(spread)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 214
	spread.add_child(navigation)
	var index := _button("Index")
	navigation.add_child(index)
	index.pressed.connect(_show_index)
	var index_scroll := ScrollContainer.new()
	index_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	index_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	navigation.add_child(index_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index_scroll.add_child(list)
	var selected_entry: Button = index
	for entry_name in TOPICS:
		var entry := _button(entry_name)
		entry.toggle_mode = true
		entry.set_pressed_no_signal(entry_name == topic)
		list.add_child(entry)
		entry.pressed.connect(_show_topic.bind(entry_name))
		if entry_name == topic:
			selected_entry = entry
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spread.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var copy := Label.new()
	copy.add_theme_color_override("font_color", Color("#35241b"))
	copy.add_theme_font_size_override("font_size", 18)
	copy.add_theme_font_override("font", Prep.serif())
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.text = "Choose a topic from the contents to learn more." if topic.is_empty() else TOPICS[topic][0]
	if topic == "Mission objective":
		var page = get_parent().get("_storybook_page")
		if get_parent().current_screen() == "battle" and is_instance_valid(page):
			var objective: Label = page.get("_objective")
			if is_instance_valid(objective):
				copy.text = objective.tooltip_text
		else:
			copy.text = "Your current objective appears here during a battle. Read field reports to learn about the next mission."
	content.add_child(copy)
	if topic == "Practice lesson" and get_parent().current_screen() == "commissions" \
			and get_parent().has_method("can_replay_practice") and get_parent().can_replay_practice():
		var replay := _button("Replay practice")
		content.add_child(replay)
		replay.pressed.connect(func() -> void:
			_return_to_options = false
			_close()
			get_parent().replay_practice())
	var image_path: String = "" if topic.is_empty() else TOPICS[topic][1]
	if not image_path.is_empty():
		var path := "res://assets/help/" + image_path + ".png"
		if ResourceLoader.exists(path):
			var figure := VBoxContainer.new()
			figure.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			content.add_child(figure)
			var image := TextureRect.new()
			image.texture = load(path)
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			figure.add_child(image)
			var caption := Label.new()
			caption.text = CAPTIONS.get(image_path, topic)
			caption.add_theme_color_override("font_color", Color("#523b29"))
			caption.add_theme_font_override("font", Prep.serif())
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			figure.add_child(caption)
			if image.texture != null:
				var fit := func() -> void:
					if not is_instance_valid(image) or not is_instance_valid(scroll):
						return
					var native := image.texture.get_size()
					var width := minf(520.0, minf(native.x, maxf(1.0, scroll.size.x - 24.0)))
					figure.custom_minimum_size.x = width
					image.custom_minimum_size = Vector2(width, width * native.y / native.x)
				scroll.resized.connect(fit)
				fit.call_deferred()
	if topic == "Credits":
		var link := LinkButton.new()
		link.text = "https://godotengine.org/license/"
		link.uri = "https://godotengine.org/license/"
		content.add_child(link)
	selected_entry.grab_focus()


func _add_header(title: String) -> void:
	var row := HBoxContainer.new()
	_body.add_child(row)
	var label := Label.new()
	label.text = title
	label.add_theme_font_override("font", Prep.serif())
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color("#35241b"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var close := _button("Close")
	row.add_child(close)
	close.pressed.connect(_close)


func _open_options() -> void:
	if not _shade.visible:
		_begin_overlay()
	_overlay_kind = "options"
	_set_panel_compact(true)
	_panel.offset_top = -245
	_panel.offset_bottom = 245
	_add_header("Options")
	var hints := CheckButton.new()
	hints.text = "Show hints"
	hints.button_pressed = _hints
	hints.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hints.add_theme_font_override("font", Prep.serif())
	hints.add_theme_font_size_override("font_size", 20)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		hints.add_theme_color_override(state, Color("#302419"))
	_body.add_child(hints)
	hints.toggled.connect(func(enabled: bool) -> void:
		_hints = enabled
		Preferences.save_show_hints(enabled)
		_update_next_step()
		_refresh_hints())
	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_label.add_theme_font_override("font", Prep.serif())
	volume_label.add_theme_font_size_override("font_size", 20)
	volume_label.add_theme_color_override("font_color", Color("#302419"))
	_body.add_child(volume_label)
	var controls := VolumeControls.new()
	_body.add_child(controls)
	for label in controls.find_children("*", "Label", true, false):
		label.add_theme_font_override("font", Prep.serif())
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color("#302419"))
	controls.volume_changed.connect(_volume_changed)
	if get_parent().current_screen() == "battle":
		_add_display_option("Show Grid", Preferences.load_grid_visible(), "_set_grid_visible")
		_add_display_option("Show Grid Labels", Preferences.load_grid_labels_visible(), "_set_grid_labels_visible")
		_add_display_option("Show Nameplates", Preferences.load_nameplates_visible(), "_set_nameplates_visible")
		_add_display_option("Always show health bar", Preferences.load_always_show_health_bar(), "_set_always_show_health_bar")
	hints.grab_focus()


func _volume_changed(category: String, value: float) -> void:
	match category:
		"master": get_parent().call("_set_master_volume", value)
		"music": get_parent().call("_set_music_volume", value)
		"sfx": get_parent().call("_set_sound_effects_volume", value)


func _set_panel_compact(compact: bool) -> void:
	if compact:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_panel.offset_left = -290
		_panel.offset_right = 290
		_panel.offset_top = -120
		_panel.offset_bottom = 120
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_panel.offset_left = 72
		_panel.offset_right = -72
		_panel.offset_top = 52
		_panel.offset_bottom = -52


func _add_display_option(text: String, checked: bool, method: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = checked
	_body.add_child(toggle)
	toggle.toggled.connect(func(value: bool) -> void:
		get_parent().call(method, value)
		var page = get_parent().get("_storybook_page")
		if is_instance_valid(page):
			page.set_display_options(Preferences.load_grid_visible(), Preferences.load_nameplates_visible(),
				Preferences.load_grid_labels_visible(), Preferences.load_always_show_health_bar()))


func _close() -> void:
	if _overlay_kind == "help" and _return_to_options:
		_return_to_options = false
		_clear_body()
		_open_options()
		return
	_overlay_kind = ""
	_shade.hide()
	_options.show()
	_cover_active = false
	_restore_covered_actions()
	if is_instance_valid(_screen_root):
		if _screen_root.has_method("set_help_covered"):
			_screen_root.set_help_covered(false)
		_screen_root.focus_behavior_recursive = _screen_focus_behavior as Control.FocusBehaviorRecursive
		_screen_root.mouse_behavior_recursive = _screen_mouse_behavior as Control.MouseBehaviorRecursive
		_screen_root.set_process_input(_screen_input)
	if is_instance_valid(_prior_focus) and _prior_focus.is_inside_tree() and _prior_focus.is_visible_in_tree():
		_prior_focus.grab_focus()
		if _prior_focus == _selection_edit:
			_selection_edit.caret_column = _selection_caret
			if _selection_start >= 0:
				_selection_edit.select(_selection_start, _selection_end)
		if _prior_focus == get_parent().get("_board") and _board_focus_cell != null:
			get_parent().set("_storybook_focus_cell", _board_focus_cell)
			get_parent().call("_refresh_board")
	if is_instance_valid(_popup_source) and _popup_source.is_visible_in_tree():
		_restore_popup.call_deferred(_popup_source, _popup_focus_row)
	_popup_source = null
	_popup_focus_row = -1
	if is_instance_valid(_dialog_source):
		_restore_dialog.call_deferred(_dialog_source, _dialog_focus)
	_dialog_source = null
	_dialog_focus = null


func _restore_dialog(dialog: Window, focus: Control) -> void:
	if not is_instance_valid(dialog) or not dialog.is_inside_tree():
		return
	dialog.popup()
	if is_instance_valid(focus) and focus.is_inside_tree():
		focus.grab_focus()


func _restore_popup(source: Control, focused_row: int) -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree():
		return
	source.show_popup()
	var popup: PopupMenu = source.get_popup()
	await get_tree().process_frame
	if is_instance_valid(popup) and popup.visible and focused_row >= 0 and focused_row < popup.item_count:
		popup.set_focused_item(focused_row)


func _record_selection(control: Control) -> void:
	if not control is LineEdit:
		return
	_selection_edit = control
	_selection_caret = control.caret_column
	_selection_start = control.get_selection_from_column() if control.has_selection() else -1
	_selection_end = control.get_selection_to_column() if control.has_selection() else -1


func _record_board_focus(control: Control) -> void:
	var game := get_parent()
	if game.current_screen() == "battle" and control == game.get("_board"):
		_board_focus_cell = game.get("_storybook_focus_cell")


func _input(event: InputEvent) -> void:
	if not _shade.visible and event is InputEventMouseButton and event.pressed:
		_record_selection(get_viewport().gui_get_focus_owner())
		_record_board_focus(get_viewport().gui_get_focus_owner())
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_open_help()
		get_viewport().set_input_as_handled()
		return
	if _shade.visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _update_next_step() -> void:
	var steps := {
		"guild_creation": "Enter a guild name, then create your guild.",
		"commissions": "Choose a commission to recruit your company.",
		"guild": "Recruit three heroes, then read the field reports.",
		"routes": "Read the reports and choose a route.",
		"battle": "Select a hero to plan a command, then compare the forecast.",
		"debrief": "Review the debrief and choose a reward before continuing.",
	}
	_tip.text = steps.get(_current_screen, "") if _hints else ""
	if _hints and _current_screen == "guild":
		var game := get_parent()
		var party: Array = game.get("_picked_recruits")
		var adventure: Dictionary = game.get("_adventure")
		if game.get("_recruitment_folio") == "loadout":
			_tip.text = "Choose equipped abilities and a compatible standing order, then return to recruits."
		elif party.size() == int(adventure.get("party_size", 3)):
			_tip.text = "Review deployment order and loadouts, then read the field reports."
			for hero in party:
				if not game.call("_loadout_compatible", str(hero)):
					_tip.text = "Edit the incompatible loadout before reading the field reports."
					break
	if _hints and _current_screen == "debrief":
		var root: Control = get_parent().get("_screen_root")
		if is_instance_valid(root):
			var slot := root.find_child("HelpHintSlot", true, false)
			if slot != null:
				_tip.text = slot.get_meta("help_next_step", _tip.text)
	_tip.visible = _hints


func _install_hints(node: Node) -> void:
	for child in node.get_children():
		if child == self:
			continue
		_register_hint(child)
		_install_hints(child)


func _node_added(node: Node) -> void:
	if node.has_signal("hints_visibility_changed"):
		node.hints_visibility_changed.connect(_battle_hints_changed)
	if node.has_signal("help_from_popup_requested"):
		node.help_from_popup_requested.connect(_open_from_popup)
	if node.has_signal("help_shortcut_requested"):
		node.help_shortcut_requested.connect(_open_help)
	if node.has_signal("help_from_dialog_requested"):
		node.help_from_dialog_requested.connect(_open_from_dialog)
	if node is PopupMenu and get_parent().is_ancestor_of(node):
		_popup_rows[node] = -1
		node.tree_exiting.connect(_forget_popup.bind(node))
		node.window_input.connect(_remember_popup_input.bind(node))
	if node is Window and get_parent().is_ancestor_of(node):
		node.visibility_changed.connect(_covered_window_visibility_changed.bind(node))
	if node != self and get_parent().is_ancestor_of(node) and not is_ancestor_of(node):
		_install_new_hint.call_deferred(node)


func _open_from_popup(source: Control) -> void:
	var popup: PopupMenu = source.get_popup()
	var row: int = popup.get_focused_item()
	if popup.has_meta("help_restore_row"):
		row = popup.get_meta("help_restore_row")
		popup.remove_meta("help_restore_row")
	elif not popup.visible or row < 0:
		row = _popup_rows.get(popup, row)
	_open_help()
	_popup_source = source
	_popup_focus_row = row
	_prior_focus = source


func _remember_popup_input(_event: InputEvent, popup: PopupMenu) -> void:
	if popup.visible and popup.get_focused_item() >= 0:
		_popup_rows[popup] = popup.get_focused_item()


func _forget_popup(popup: PopupMenu) -> void:
	_popup_rows.erase(popup)


func _open_from_dialog(dialog: Window, focus: Control) -> void:
	_open_help()
	_dialog_source = dialog
	_dialog_focus = focus


func _battle_hints_changed(enabled: bool) -> void:
	_hints = enabled
	_update_next_step()
	_refresh_hints()


func _install_new_hint(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	_register_hint(node)
	if node is OptionButton and node.name == "PetitionHeroFilter":
		_install_filter_help(node)
	if _cover_active and is_instance_valid(_screen_root) and _screen_root.is_ancestor_of(node):
		_guard_covered_actions(node)


func _guard_covered_actions(node: Node) -> void:
	# Suppress only player-action signals. Focus, accessibility, visibility and
	# layout signals must keep flowing while the covered surface is inert.
	var actions: Array[StringName] = []
	if node is BaseButton:
		actions.append_array([&"pressed", &"button_down", &"button_up", &"toggled"])
	if node is OptionButton:
		actions.append(&"item_selected")
	if node is PopupMenu:
		actions.append_array([&"id_pressed", &"index_pressed"])
	if node is LineEdit:
		actions.append(&"text_submitted")
	if node is AcceptDialog:
		actions.append_array([&"confirmed", &"canceled", &"custom_action"])
	for action in actions:
		if not node.has_signal(action):
			continue
		for connection in node.get_signal_connection_list(action):
			var callback: Callable = connection.callable
			_covered_connections.append({"node": node, "signal": action,
				"callable": callback, "flags": connection.flags})
			node.disconnect(action, callback)
	for child in node.get_children(true):
		_guard_covered_actions(child)


func _restore_covered_actions() -> void:
	for connection in _covered_connections:
		var node: Object = connection.node
		var callback: Callable = connection.callable
		if is_instance_valid(node) and callback.is_valid() \
				and not node.is_connected(connection.signal, callback):
			node.connect(connection.signal, callback, connection.flags)
	_covered_connections.clear()


func _covered_window_visibility_changed(window: Window) -> void:
	if not _cover_active or not window.visible or not is_instance_valid(_screen_root) \
			or not _screen_root.is_ancestor_of(window):
		return
	var focused := get_viewport().gui_get_focus_owner()
	window.hide()
	if focused != null and is_ancestor_of(focused):
		_restore_overlay_focus.call_deferred(focused)


func _restore_overlay_focus(focus: Control) -> void:
	if _cover_active and is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus()


func _install_filter_help(filter: OptionButton) -> void:
	var popup := filter.get_popup()
	var selection := {"index": filter.selected}
	filter.item_selected.connect(func(index: int) -> void:
		if index < popup.get_item_index(FILTER_HELP_ID):
			selection.index = index)
	popup.add_separator()
	popup.add_item("Help (F1)", FILTER_HELP_ID)
	var shortcut := Shortcut.new()
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	shortcut.events = [key]
	popup.set_item_shortcut(popup.get_item_index(FILTER_HELP_ID), shortcut)
	popup.id_pressed.connect(func(id: int) -> void:
		if id == FILTER_HELP_ID:
			filter.select(selection.index)
			_open_from_popup(filter))
	popup.window_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
			popup.set_meta("help_restore_row", popup.get_focused_item())
			popup.set_input_as_handled()
			popup.hide()
			_open_from_popup(filter))


func _register_hint(child: Node) -> void:
	if not child is BaseButton or _hint_controls.has(child):
		return
	var hint := _hint_for(child)
	if hint.is_empty():
		return
	_hint_controls[child] = hint
	_original_tooltips[child] = child.tooltip_text
	if child.tooltip_text.is_empty():
		child.set_meta("help_owns_tooltip", true)
		child.tooltip_text = hint if _hints else ""
	elif not _hints:
		child.tooltip_text = ""
	child.mouse_entered.connect(_show_hint.bind(child))
	child.mouse_exited.connect(_update_next_step)
	child.tree_exiting.connect(_forget_hint.bind(child))


func _hint_for(button: BaseButton) -> String:
	var text: String = button.text.to_lower()
	var node_name := str(button.name).to_lower()
	if button is OptionButton and "order" in node_name:
		return "Choose this hero's standing order; it returns after a direct command."
	if node_name == "targets":
		return "Choose the target for the selected direct action."
	if node_name == "actions":
		return "Choose a direct action for the selected hero this round."
	if "create guild" in text:
		return "Create your guild and begin the practice lesson." if get_parent().get("_uses_builtin_catalog") \
			else "Create your guild and choose a commission."
	if "replay practice" in text: return "Repeat the lesson without changing guild progress."
	if "choose commission" in text: return "Choose this destination and recruit your company."
	if "recruit" in text: return "Add or remove this hero from your company."
	if "field reports" in text: return "Review the available routes before choosing a mission."
	if "route" in text: return "Take this route into the described mission."
	if "commit" in text: return "Play the forecasted round. Until then you can change your command."
	if "forecast" in text: return "See the planned actions in order without playing the round."
	if "standing order" in text or text == "orders": return "Choose what each hero does when not directly commanded."
	if "actions" in text: return "Choose a direct action for the selected hero this round."
	if "clear command" in text: return "Remove the direct command so all heroes follow their orders."
	if "reward" in text: return "Choose this temporary reward for the rest of the outing."
	if "continue" in text: return "Continue to the next part of the commission."
	if "forfeit" in text: return "End this mission as a defeat after confirmation."
	return ""


func _show_hint(control: Control) -> void:
	if _hints and _hint_controls.has(control):
		_tip.text = _hint_controls[control]


func _forget_hint(control: Control) -> void:
	_hint_controls.erase(control)
	_original_tooltips.erase(control)


func _refresh_hints() -> void:
	for control in _hint_controls:
		if not is_instance_valid(control):
			continue
		if _hints:
			control.tooltip_text = _original_tooltips.get(control, "")
			if control.tooltip_text.is_empty():
				control.tooltip_text = _hint_controls[control]
		else:
			if not control.tooltip_text.is_empty():
				_original_tooltips[control] = control.tooltip_text
			control.tooltip_text = ""
