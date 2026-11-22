extends Control
## A separate battle view, using the shared board and emitting only player intent.

signal action_selected(ability_id: String)
signal order_selected(hero_id: String, order_id: String)
signal target_selected(target_id: String)
signal clear_requested
signal commit_requested
signal restart_requested
signal forfeit_requested

const Ink := preload("res://presentation/storybook_battle_ink.gd")
const Surround := preload("res://presentation/storybook_battle_surround.gd")
const CastSprites := preload("res://presentation/cast_sprites.gd")
const BridgeArt := preload("res://bridge_art.gd")
const GATE_BOARD := "frontier_gate_board"
const FIELD_BOARD := "frontier_field"
const GATE_ART := "res://assets/storybook-gate/"
const FIELD_ART := "res://assets/storybook-field/frontier-field-surround-rgba.png"
const EDGE := 16.0
const DARK := Color("#231910")
const PARCHMENT := Color("#f7e9c7")
const MUTED := Color("#dfc9a2")
const GOLD := Color("#ffda88")


class BattleSurface extends Control:
	var _inert := false

	func set_inert(inert: bool) -> void:
		_inert = inert
		focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED if inert else FOCUS_BEHAVIOR_INHERITED
		mouse_behavior_recursive = MOUSE_BEHAVIOR_DISABLED if inert else MOUSE_BEHAVIOR_INHERITED
		queue_accessibility_update()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
			AccessibilityServer.update_set_flag(get_accessibility_element(), AccessibilityServer.FLAG_HIDDEN, _inert)


class ForfeitDialog extends ColorRect:
	func _notification(what: int) -> void:
		if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
			var element := get_accessibility_element()
			AccessibilityServer.update_set_role(element, AccessibilityServer.ROLE_DIALOG)
			AccessibilityServer.update_set_flag(element, AccessibilityServer.FLAG_MODAL, true)


var _surface_root: BattleSurface
var _board: Control
var _board_id := ""
var _dimensions := Vector2i(7, 5)
var _board_host: Control
var _ink: Ink
var _title: Label
var _round: Label
var _objective: Label
var _restart: Button
var _upgrades: Button
var _forfeit: Button
var _forfeit_modal: ForfeitDialog
var _forfeit_panel: PanelContainer
var _forfeit_copy: Label
var _forfeit_cancel: Button
var _forfeit_confirm: Button
var _upgrade_dialog: AcceptDialog
var _upgrade_text: Label
var _summary: Label
var _inspection: Label
var _locked_dose: Label
var _actions: MenuButton
var _targets: MenuButton
var _orders: Button
var _forecast: Button
var _clear: Button
var _commit: Button
var _leaf: PanelContainer
var _order_entries: VBoxContainer
var _forecast_scroll: ScrollContainer
var _forecast_heading: Label
var _forecast_text: Label
var _field_notes: Label
var _bleed: Surround
var _scenery: TextureRect
var _props: Dictionary = {}
var _header: Control
var _footer: VBoxContainer
var _action_rows: Array = []
var _target_rows: Array = []
var _order_rows: Array = []
var _order_widgets: Dictionary = {}
var _expanded := ""
var _popup_epoch := 0
var _display: SystemFont
var _built := false


func _ready() -> void:
	_build()
	_layout_page()


func mount_board(board: Control, trusted_board_id: String, board_dimensions := Vector2i(7, 5)) -> void:
	_build()
	assert(_board == null and board.get_parent() == null, "Supply one unmounted BridgeArt board.")
	_board = board
	_board_id = trusted_board_id
	_dimensions = board_dimensions
	_bleed.set_painting(trusted_board_id)
	_bleed.set_quiet_edges(trusted_board_id != GATE_BOARD and trusted_board_id != FIELD_BOARD)
	if trusted_board_id == GATE_BOARD:
		_load_gate_art()
	elif trusted_board_id == FIELD_BOARD:
		set_scene_art(CastSprites.load_texture(FIELD_ART), {})
		# Leave room for longer combat commands without making the orders wrap.
		_summary.size_flags_stretch_ratio = 1.65
	_board_host.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.accessibility_name = "Battle board"
	board.accessibility_description = "Use arrow keys to inspect a cell. Enter selects a hero or target."
	_ink = Ink.new()
	_ink.name = "StorybookInk"
	board.add_child(_ink)
	_ink.mount(board)
	_ink.set_scene_props(_props)
	_ink.set_scenery_coordinates(_scenery.texture != null)
	_layout_page()


func render(view: Dictionary) -> void:
	_build()
	var outcome: String = view.get("outcome", "ongoing")
	var active := outcome == "ongoing"
	_title.text = view.get("title", "")
	var round_label: String = view.get("round_label", "Round %d" % int(view.get("round", 1)))
	_round.text = round_label
	_restart.visible = view.get("can_restart", true)
	_restart.accessibility_description = "Mission ended in defeat." if outcome == "defeat" else ""
	_upgrade_text.text = view.get("upgrades_text", "")
	_upgrades.visible = not _restart.visible and not _upgrade_text.text.is_empty()
	_forfeit.visible = active
	if not active and is_forfeit_confirmation_open():
		_close_forfeit_confirmation()
	_layout_header()
	var objective: String = view.get("objective", "")
	var status: String = view.get("objective_status", "")
	if active and _board_id == GATE_BOARD and status.begins_with("Gate "):
		status = status.get_slice(" · ", 0)
	_objective.text = objective
	if not status.is_empty():
		_objective.text += ("   ·   " if not objective.is_empty() else "") + status
	_objective.tooltip_text = view.get("objective_details", _objective.text) if active else _objective.text
	var selected_hero: String = view.get("selected_hero", "")
	var command: String = view.get("command_summary", "")
	_summary.text = command if not command.is_empty() else (
		"Standing orders only" if active else _victory_summary() if outcome == "victory" else "Mission failed")
	_summary.tooltip_text = _summary.text
	_summary.accessibility_live = AccessibilityServer.LIVE_POLITE if outcome == "defeat" else AccessibilityServer.LIVE_OFF
	var rows: Array = view.get("orders", [])
	_inspection.text = view.get("inspection", "")
	if _inspection.text.is_empty() and active:
		var company := PackedStringArray()
		for row: Dictionary in rows:
			if row.get("overridden", false):
				continue
			for choice: Dictionary in row.get("choices", []):
				if choice.id == row.order_id:
					company.append("%s: %s" % [row.hero_label, choice.label])
					break
		_inspection.text = "   ·   ".join(company)
	_inspection.tooltip_text = _inspection.text
	_render_locked_dose(str(view.get("locked_dose", "")))
	_forecast.text = "Forecast" if active else "Round result"
	_forecast_heading.text = "Round forecast" if active else "Round result"
	_forecast_scroll.accessibility_name = "Round forecast in execution order" if active else "Resolved round events"
	_forecast_text.text = view.get("forecast", "")
	var objective_details: String = view.get("objective_details", "")
	if _board_id != FIELD_BOARD and not objective.is_empty() and objective_details.begins_with(objective):
		objective_details = objective_details.trim_prefix(objective).strip_edges()
	_field_notes.visible = active and not objective_details.is_empty() and objective_details != objective
	_field_notes.text = "Mission notes: " + objective_details if _field_notes.visible else ""
	_refresh_actions(view.get("actions", []), selected_hero, view.get("selected_action_id", ""), active)
	_refresh_targets(view.get("targets", []), active)
	_refresh_orders(rows)
	_clear.disabled = not active or not view.get("can_clear", false)
	_clear.text = view.get("clear_label", "Clear command")
	_commit.disabled = not active or not view.get("can_commit", false)
	_commit.text = "Commit round %d" % int(view.get("round", 1)) if active else (
		"Mission complete" if outcome == "victory" else "Mission failed")


func _victory_summary() -> String:
	return "The company made it through" if _board_id == GATE_BOARD else "Mission complete"


func is_forfeit_confirmation_open() -> bool:
	return is_instance_valid(_forfeit_modal) and _forfeit_modal.is_visible_in_tree()


func render_ink(cues: Dictionary) -> void:
	if is_instance_valid(_ink):
		_ink.render(cues)


func play_committed_reactions(reactions: Array) -> void:
	if is_instance_valid(_ink):
		_ink.play_committed_reactions(reactions)


func _render_locked_dose(text: String) -> void:
	var show_note := not text.is_empty()
	if _locked_dose.visible and not show_note and _locked_dose.has_focus() and not _actions.disabled:
		_actions.grab_focus()
	_locked_dose.text = text
	_locked_dose.accessibility_name = text
	_actions.accessibility_description = text
	_locked_dose.visible = show_note
	_summary.visible = not show_note
	_inspection.visible = not show_note


## Scenery uses full-page coordinates with transparent space for the live grid.
## Props supply normalized anchors and display sizes at the authored board scale.
func set_scene_art(surround: Texture2D, props: Dictionary) -> void:
	_build()
	_scenery.texture = surround
	_props = props.duplicate(true)
	if is_instance_valid(_ink):
		_ink.set_scene_props(_props)
		_ink.set_scenery_coordinates(surround != null)


func _load_gate_art() -> void:
	var props := {}
	for entry: Array in [
		["gate_open", "gate-open.png", Vector2(156, 213)],
		["gate_closed", "gate-shut.png", Vector2(156, 213)],
		["exit", "exit-arch.png", Vector2(114, 162)],
		["plate", "pressure-plate.png", Vector2(120, 60)],
	]:
		var texture := CastSprites.load_texture(GATE_ART + entry[1])
		if texture != null:
			var pixels := texture.get_size()
			props[entry[0]] = {"texture": texture, "anchor": entry[2] / pixels, "size": pixels / 3.0}
	set_scene_art(CastSprites.load_texture(GATE_ART + "gate-scenery-surround-wall-rgba.png"), props)


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	resized.connect(_layout_page)

	_surface_root = BattleSurface.new()
	_surface_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface_root)
	_surface_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bleed = Surround.new()
	_surface_root.add_child(_bleed)
	_bleed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_host = Control.new()
	_board_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface_root.add_child(_board_host)
	_scenery = TextureRect.new()
	_scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface_root.add_child(_scenery)
	_scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The leaf edge, shaded margins, and separating rules sit above the painting,
	# but never take input from the mounted board or the controls.
	var book := Control.new()
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.draw.connect(_draw_book.bind(book))
	_surface_root.add_child(book)
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(book.queue_redraw)
	_build_header()
	_build_footer()
	_build_leaf()
	_build_forfeit_confirmation()


func _build_header() -> void:
	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface_root.add_child(_header)
	_title = _label("", 36, PARCHMENT, true)
	_header.add_child(_title)
	_round = _label("", 19, GOLD, true)
	_header.add_child(_round)
	_objective = _label("", 15, PARCHMENT)
	_header.add_child(_objective)
	_restart = _button("Restart", "Restart mission")
	_restart.custom_minimum_size.x = 141.0
	_header.add_child(_restart)
	_restart.pressed.connect(_request_battle_action.bind(restart_requested))
	_upgrades = _button("ShowLoadout", "Outing upgrades")
	_upgrades.custom_minimum_size.x = 150.0
	_header.add_child(_upgrades)
	_upgrades.hide()
	_forfeit = _button("Forfeit", "Forfeit")
	_forfeit.custom_minimum_size.x = 96.0
	_forfeit.tooltip_text = "End this mission as a defeat"
	_header.add_child(_forfeit)
	_forfeit.hide()
	_forfeit.pressed.connect(_open_forfeit_confirmation)
	_upgrade_dialog = AcceptDialog.new()
	_upgrade_dialog.name = "OutingLoadout"
	_upgrade_dialog.title = "Outing upgrades"
	_upgrade_dialog.ok_button_text = "Close"
	_header.add_child(_upgrade_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(496, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.accessibility_name = "Upgrades carried by the company"
	_upgrade_dialog.add_child(scroll)
	_upgrade_text = _label("", 16, PARCHMENT)
	_upgrade_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_upgrade_text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	scroll.add_child(_upgrade_text)
	_upgrades.pressed.connect(func() -> void:
		if is_forfeit_confirmation_open():
			return
		_upgrade_dialog.popup_centered(Vector2i(540, 310))
		scroll.grab_focus())
	_upgrade_dialog.visibility_changed.connect(func() -> void:
		if not is_forfeit_confirmation_open() and not _upgrade_dialog.visible and _upgrades.is_visible_in_tree():
			_upgrades.grab_focus())


func _build_forfeit_confirmation() -> void:
	_forfeit_modal = ForfeitDialog.new()
	_forfeit_modal.name = "ForfeitConfirmation"
	_forfeit_modal.accessibility_name = "Forfeit mission?"
	_forfeit_modal.color = Color("#170e0abc")
	_forfeit_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_forfeit_modal.mouse_force_pass_scroll_events = false
	_forfeit_modal.z_index = 20
	add_child(_forfeit_modal)
	_forfeit_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forfeit_modal.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_forfeit_panel = PanelContainer.new()
	_forfeit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forfeit_panel.add_theme_stylebox_override("panel", _surface(Color("#2f2218"), Color("#c59857"), 22, 18))
	center.add_child(_forfeit_panel)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	_forfeit_panel.add_child(content)
	content.add_child(_label("Forfeit mission?", 26, GOLD, true))
	_forfeit_copy = _label("", 17, PARCHMENT)
	_forfeit_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forfeit_copy.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	content.add_child(_forfeit_copy)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.y = 6
	content.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	content.add_child(buttons)
	_forfeit_cancel = _button("CancelForfeit", "Cancel")
	_forfeit_cancel.custom_minimum_size.x = 92
	buttons.add_child(_forfeit_cancel)
	_forfeit_confirm = _button("ConfirmForfeit", "Forfeit mission")
	_forfeit_confirm.add_theme_stylebox_override("normal", _surface(Color("#4e2e23"), Color("#c28d6b"), 12, 6))
	_forfeit_confirm.add_theme_stylebox_override("hover", _surface(Color("#673e30"), Color("#dfaa87"), 12, 6))
	_forfeit_confirm.add_theme_stylebox_override("pressed", _surface(Color("#41261e"), Color("#dfaa87"), 12, 6))
	buttons.add_child(_forfeit_confirm)
	for button: Button in [_forfeit_cancel, _forfeit_confirm]:
		var other := _forfeit_confirm if button == _forfeit_cancel else _forfeit_cancel
		var peer := button.get_path_to(other)
		button.focus_next = peer
		button.focus_previous = peer
		button.focus_neighbor_left = peer if button == _forfeit_confirm else NodePath(".")
		button.focus_neighbor_right = peer if button == _forfeit_cancel else NodePath(".")
		button.focus_neighbor_top = NodePath(".")
		button.focus_neighbor_bottom = NodePath(".")
	_forfeit_cancel.pressed.connect(_cancel_forfeit)
	_forfeit_confirm.pressed.connect(_confirm_forfeit)
	_forfeit_modal.hide()


func _open_forfeit_confirmation() -> void:
	if not _forfeit.is_visible_in_tree() or is_forfeit_confirmation_open():
		return
	_forfeit_copy.text = "This mission will count as a defeat."
	if not _restart.visible:
		_forfeit_copy.text += "\nYour outing will end."
	_forfeit_modal.accessibility_description = _forfeit_copy.text
	_forfeit_cancel.accessibility_description = _forfeit_copy.text
	_popup_epoch += 1
	_forfeit_modal.show()
	_surface_root.set_inert(true)
	_dismiss_battle_popups()
	_forfeit_cancel.grab_focus()


func _close_forfeit_confirmation() -> void:
	_surface_root.set_inert(false)
	_forfeit_modal.hide()


func _cancel_forfeit() -> void:
	if not is_forfeit_confirmation_open():
		return
	_close_forfeit_confirmation()
	if _forfeit.is_visible_in_tree():
		_forfeit.grab_focus()


func _confirm_forfeit() -> void:
	if not is_forfeit_confirmation_open() or not _forfeit.is_visible_in_tree():
		return
	_close_forfeit_confirmation()
	forfeit_requested.emit()
	# Standalone defeat renders on this page; an outing replaces the page.
	if not _forfeit.visible and _restart.is_visible_in_tree():
		_restart.grab_focus()


func _request_battle_action(intent: Signal) -> void:
	if not is_forfeit_confirmation_open():
		intent.emit()


func _dismiss_battle_popups() -> void:
	_upgrade_dialog.hide()
	_actions.get_popup().hide()
	_targets.get_popup().hide()
	for widgets: Dictionary in _order_widgets.values():
		widgets.picker.get_popup().hide()


func _battle_popup_visibility_changed(popup: PopupMenu) -> void:
	if not popup.visible:
		return
	# A native menu can still receive an assistive click queued before the
	# background was hidden from accessibility.
	if is_forfeit_confirmation_open():
		popup.hide()
		if get_viewport().gui_get_focus_owner() not in [_forfeit_cancel, _forfeit_confirm]:
			_forfeit_cancel.grab_focus()
	else:
		popup.set_meta(&"_battle_popup_epoch", _popup_epoch)


func _battle_popup_accepts_selection(popup: PopupMenu) -> bool:
	# Godot hides the popup before signaling a valid selection. Keep accepting
	# its callbacks until Forfeit invalidates them, and rearm only on reopening.
	return not is_forfeit_confirmation_open() and popup.get_meta(&"_battle_popup_epoch", 0) == _popup_epoch


func _build_footer() -> void:
	_footer = VBoxContainer.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_theme_constant_override("separation", 4)
	_footer.minimum_size_changed.connect(_layout_page, CONNECT_DEFERRED)
	_surface_root.add_child(_footer)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 16)
	_footer.add_child(line)
	_summary = _label("", 18, PARCHMENT, true)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_summary)
	_inspection = _label("", 15, MUTED)
	_inspection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspection.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(_inspection)
	# While a recipient is undecided, give the recipe the whole margin rather
	# than competing with the command summary and cell inspection for one line.
	_locked_dose = _label("", 16, PARCHMENT)
	_locked_dose.name = "LockedDose"
	_locked_dose.focus_mode = Control.FOCUS_ALL
	_locked_dose.mouse_filter = Control.MOUSE_FILTER_PASS
	_locked_dose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locked_dose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_locked_dose.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var note_style := _surface(Color("#30241d"), Color("#ab8967"), 12, 3)
	var note_focus := _surface(Color("#30241d"), GOLD, 12, 3, 2)
	_locked_dose.add_theme_stylebox_override("normal", note_style)
	_locked_dose.focus_entered.connect(func() -> void:
		_locked_dose.add_theme_stylebox_override("normal", note_focus))
	_locked_dose.focus_exited.connect(func() -> void:
		_locked_dose.add_theme_stylebox_override("normal", note_style))
	line.add_child(_locked_dose)
	_locked_dose.hide()
	var controls := HBoxContainer.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_theme_constant_override("separation", 8)
	_footer.add_child(controls)
	_actions = _menu("Actions", "Actions")
	controls.add_child(_actions)
	var actions_popup := _actions.get_popup()
	actions_popup.visibility_changed.connect(_battle_popup_visibility_changed.bind(actions_popup))
	actions_popup.id_pressed.connect(func(index: int) -> void:
		if _battle_popup_accepts_selection(actions_popup) and index >= 0 and index < _action_rows.size():
			action_selected.emit(str(_action_rows[index].id)))
	_targets = _menu("Targets", "Choose target")
	_targets.hide()
	controls.add_child(_targets)
	var targets_popup := _targets.get_popup()
	targets_popup.visibility_changed.connect(_battle_popup_visibility_changed.bind(targets_popup))
	targets_popup.id_pressed.connect(func(index: int) -> void:
		if _battle_popup_accepts_selection(targets_popup) and index >= 0 and index < _target_rows.size():
			target_selected.emit(str(_target_rows[index].id)))
	_orders = _button("StandingOrders", "Standing orders")
	_orders.toggle_mode = true
	controls.add_child(_orders)
	_orders.pressed.connect(_toggle_leaf.bind("orders"))
	_forecast = _button("ForecastDetails", "Forecast")
	_forecast.toggle_mode = true
	controls.add_child(_forecast)
	_forecast.pressed.connect(_toggle_leaf.bind("forecast"))
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(space)
	_clear = _button("ClearCommand", "Clear command")
	controls.add_child(_clear)
	_clear.pressed.connect(_request_battle_action.bind(clear_requested))
	_commit = _button("Commit", "Commit round 1", true)
	_commit.custom_minimum_size.x = 182
	controls.add_child(_commit)
	_commit.pressed.connect(_request_battle_action.bind(commit_requested))


func _build_leaf() -> void:
	_leaf = PanelContainer.new()
	_leaf.name = "ExtraDetails"
	_leaf.z_index = 5
	_leaf.mouse_filter = Control.MOUSE_FILTER_STOP
	_leaf.add_theme_stylebox_override("panel", _surface(Color("#2f2218"), Color("#c59857"), 12, 12))
	_surface_root.add_child(_leaf)
	_order_entries = VBoxContainer.new()
	_order_entries.add_theme_constant_override("separation", 6)
	_leaf.add_child(_order_entries)
	var title := _label("Standing orders", 22, GOLD, true)
	_order_entries.add_child(title)
	_order_entries.add_child(_label("An order stays in place when a direct command takes its turn.", 14, MUTED))
	_forecast_scroll = ScrollContainer.new()
	_forecast_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_forecast_scroll.follow_focus = true
	_forecast_scroll.focus_mode = Control.FOCUS_ALL
	_forecast_scroll.accessibility_name = "Round forecast in execution order"
	_leaf.add_child(_forecast_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	_forecast_scroll.add_child(content)
	_forecast_heading = _label("Round forecast", 22, GOLD, true)
	content.add_child(_forecast_heading)
	_forecast_text = _label("", 16, PARCHMENT)
	_forecast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	content.add_child(_forecast_text)
	_field_notes = _label("", 14, MUTED)
	_field_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_field_notes.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_field_notes.hide()
	content.add_child(_field_notes)
	_leaf.hide()


func _toggle_leaf(section: String) -> void:
	# Assistive activation can bypass GUI input and toggle a button directly.
	if not is_forfeit_confirmation_open():
		_expanded = "" if _expanded == section else section
	_orders.set_pressed_no_signal(_expanded == "orders")
	_forecast.set_pressed_no_signal(_expanded == "forecast")
	if is_forfeit_confirmation_open():
		return
	_order_entries.visible = _expanded == "orders"
	_forecast_scroll.visible = _expanded == "forecast"
	_leaf.visible = not _expanded.is_empty()
	_layout_page()
	if _expanded == "forecast":
		_forecast_scroll.grab_focus()
	elif _expanded == "orders":
		for value: Dictionary in _order_widgets.values():
			if not value.picker.disabled:
				value.picker.grab_focus()
				break


func _input(event: InputEvent) -> void:
	if is_forfeit_confirmation_open():
		_forfeit_input(event)
		return
	if not _expanded.is_empty() and event.is_action_pressed("ui_cancel"):
		var source := _orders if _expanded == "orders" else _forecast
		var focused := get_viewport().gui_get_focus_owner()
		if focused == source or (focused != null and _leaf.is_ancestor_of(focused)):
			_toggle_leaf(_expanded)
			source.grab_focus()
			get_viewport().set_input_as_handled()


func _forfeit_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventAction
			or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return  # The full-page scrim handles pointer input in the GUI.
	if event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_cancel"):
			_cancel_forfeit()
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != _forfeit_cancel and focused != _forfeit_confirm:
		_forfeit_cancel.grab_focus()
	for action in ["ui_accept", "ui_focus_next", "ui_focus_prev", "ui_left", "ui_right", "ui_up", "ui_down"]:
		if event.is_action(action) and not event.is_echo():
			return  # Let the modal buttons handle activation and their focus links.
	get_viewport().set_input_as_handled()


func _refresh_actions(rows: Array, hero: String, chosen: String, active: bool) -> void:
	_actions.disabled = not active or rows.is_empty()
	_actions.text = "Actions" if hero.is_empty() else "%s’s actions" % hero
	var current := -1
	for index in rows.size():
		if rows[index].id == chosen:
			current = index
	if rows != _action_rows:
		_action_rows = rows.duplicate(true)
		var popup := _actions.get_popup()
		popup.clear()
		for index in rows.size():
			var row: Dictionary = rows[index]
			var label: String = row.label
			if row.get("kind") == "automatic":
				label += " (automatic)"
			popup.add_radio_check_item(label, index)
			popup.set_item_disabled(index, not row.get("enabled", true))
			popup.set_item_tooltip(index, row.get("help", ""))
	var popup := _actions.get_popup()
	for index in popup.item_count:
		popup.set_item_checked(index, index == current)


func _refresh_targets(rows: Array, active: bool) -> void:
	_targets.visible = active and not rows.is_empty()
	if rows == _target_rows:
		return
	_target_rows = rows.duplicate(true)
	var popup := _targets.get_popup()
	popup.clear()
	for index in rows.size():
		popup.add_item(rows[index].label, index)


func _refresh_orders(rows: Array) -> void:
	if rows == _order_rows:
		return
	_order_rows = rows.duplicate(true)
	var incoming := rows.map(func(row: Dictionary) -> String: return row.hero_id)
	for hero in _order_widgets.keys():
		if hero not in incoming:
			var old: Control = _order_widgets[hero].row
			_order_entries.remove_child(old)
			old.queue_free()
			_order_widgets.erase(hero)
	for row: Dictionary in rows:
		var hero: String = row.hero_id
		if not _order_widgets.has(hero):
			_add_order(hero, row.hero_label)
		var widgets: Dictionary = _order_widgets[hero]
		var note: Label = widgets.note
		var picker: OptionButton = widgets.picker
		note.text = "%s  %s%s" % [row.hero_label, row.get("hp", ""),
			"  (overridden this round)" if row.get("overridden", false) else ""]
		var items: Array = row.get("choices", [])
		if items != widgets.choices:
			widgets.choices = items.duplicate(true)
			picker.clear()
			for item: Dictionary in items:
				picker.add_item(item.label)
		picker.disabled = not row.get("enabled", true) or items.is_empty()
		widgets.selected_index = items.find_custom(func(item: Dictionary) -> bool: return item.id == row.order_id)
		picker.select(widgets.selected_index)


func _add_order(hero: String, label: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_order_entries.add_child(row)
	var note := _label("", 14, PARCHMENT)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	var picker := OptionButton.new()
	picker.name = hero.to_pascal_case() + "Order"
	picker.accessibility_name = label + " standing order"
	picker.custom_minimum_size = Vector2(164, 32)
	row.add_child(picker)
	var popup := picker.get_popup()
	popup.visibility_changed.connect(_battle_popup_visibility_changed.bind(popup))
	var widgets := {"row": row, "note": note, "picker": picker, "choices": [], "selected_index": -1}
	_order_widgets[hero] = widgets
	picker.item_selected.connect(func(index: int) -> void:
		# OptionButton updates its display before delivering even a stale click.
		if not _battle_popup_accepts_selection(popup):
			picker.select(widgets.selected_index)
			return
		var items: Array = widgets.choices
		if index >= 0 and index < items.size():
			order_selected.emit(hero, str(items[index].id)))


func _layout_page() -> void:
	if not _built or not is_instance_valid(_forfeit_panel):
		return
	var width := size.x - EDGE * 2.0
	var height := size.y - EDGE * 2.0
	if minf(width, height) <= 0.0:
		return
	var margin := EDGE + 26.0
	var content_width := size.x - margin * 2.0
	var footer_height := maxf(72.0, _footer.get_combined_minimum_size().y) if _locked_dose.visible else 72.0
	var footer_top := size.y - EDGE - 11.0 - footer_height
	var board_top := EDGE + 65.0
	var max_height := maxf(0.0, footer_top - board_top - 7.0)
	var board_extent := Vector2(_dimensions) * BridgeArt.TILE + BridgeArt.GUTTER * 2.0
	var ratio := board_extent.x / board_extent.y
	var map_width := minf(width, max_height * ratio)
	var map_height := map_width / ratio
	_board_host.position = Vector2((size.x - map_width) * 0.5, board_top + (max_height - map_height) * 0.5)
	_board_host.size = Vector2(map_width, map_height)
	_bleed.place(_board_host.get_rect())
	_header.position = Vector2(margin, EDGE + 5.0)
	_header.size = Vector2(content_width, 57.0)
	_layout_header()
	_footer.position = Vector2(margin, footer_top)
	_footer.size = Vector2(content_width, footer_height)
	var leaf_height := 210.0 if _expanded == "orders" else 242.0
	_leaf.position = Vector2(margin, footer_top - leaf_height - 5.0)
	_leaf.size = Vector2(minf(maxf(content_width, 0), 510.0), leaf_height)
	_forfeit_panel.custom_minimum_size.x = minf(432.0, maxf(0.0, content_width))


func _layout_header() -> void:
	var width := _header.size.x
	var round_width := maxf(103.0, _round.get_theme_font("font").get_string_size(
		_round.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 2.0)
	var text_edge := width
	for button: Button in [_forfeit, _restart, _upgrades]:
		if not button.visible:
			continue
		var button_width := button.get_combined_minimum_size().x
		text_edge = maxf(0.0, text_edge - button_width)
		button.position = Vector2(text_edge, 10.0)
		button.size = Vector2(button_width, 41.0)
		text_edge -= 12.0
	_title.size = Vector2(maxf(0.0, text_edge), 44.0)
	_round.position = Vector2(0, 39.0)
	_round.size = Vector2(round_width, 22.0)
	_objective.position = Vector2(round_width + 4.0, 41.0)
	_objective.size = Vector2(maxf(0.0, text_edge - _objective.position.x), 24.0)


func _draw_book(canvas: Control) -> void:
	var rect := Rect2(Vector2.ZERO, canvas.size)
	if minf(rect.size.x, rect.size.y) <= EDGE * 2.0:
		return
	var width := rect.size.x
	var height := rect.size.y
	# Fade wash out below and to the right of the title, not over the whole sky.
	var cap := PackedVector2Array([Vector2(EDGE, EDGE), Vector2(width * 0.43, EDGE),
		Vector2(width * 0.75, EDGE), Vector2(width * 0.71, 132), Vector2(EDGE, 132)])
	canvas.draw_polygon(cap, PackedColorArray([Color(DARK, 0.91), Color(DARK, 0.57),
		Color(DARK, 0.0), Color(DARK, 0.0), Color(DARK, 0.0)]))
	_wash(canvas, Rect2(Vector2(EDGE, height - EDGE - 102), Vector2(width - EDGE * 2, 102)),
		Color(DARK, 0.0), Color(DARK, 0.80))
	_wash(canvas, Rect2(Vector2(EDGE, height - EDGE - 100), Vector2(width - EDGE * 2, 49)),
		Color(DARK, 0.0), Color(DARK, 0.45))
	canvas.draw_rect(Rect2(Vector2(EDGE, height - EDGE - 51), Vector2(width - EDGE * 2, 51)),
		Color(DARK, 0.45))
	var layers := [
		[0.0, 5.0, Color("#3a2519")],
		[4.0, 3.0, Color("#624027")],
		[7.0, 9.0, Color("#c2a67e")],
		[8.0, 1.0, Color("#f0d9ac")],
		[10.0, 1.0, Color("#80664b")],
		[12.0, 1.0, Color("#ebce9e")],
		[14.0, 1.0, Color("#9c7b55")],
		[15.0, 1.0, Color("#49311f")],
	]
	for layer: Array in layers:
		var depth: float = layer[0]
		var weight: float = layer[1]
		var at := depth + weight * 0.5
		canvas.draw_rect(rect.grow(-at), layer[2], false, weight)
	for side in 4:
		var extent := width if side % 2 == 0 else height
		for index in range(5, int(extent) - 8, 13):
			var v := float(index)
			var depth := 8.0 + sin(v * 1.7) * 3.6
			var from := Vector2(v, depth) if side == 0 else Vector2(width - depth, v) if side == 1 else (
				Vector2(v, height - depth) if side == 2 else Vector2(depth, v))
			var length := 2.5 + absf(sin(v * 0.71)) * 5.0
			var direction := Vector2(length, 0) if side % 2 == 0 else Vector2(0, length)
			canvas.draw_line(from, from + direction, Color("#966e4f", 0.48), 1.0)


func _wash(canvas: Control, rect: Rect2, top: Color, bottom: Color) -> void:
	var a := rect.position
	var b := Vector2(rect.end.x, a.y)
	var c := rect.end
	var d := Vector2(a.x, c.y)
	canvas.draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([top, top, bottom, bottom]))


func _button(node_name: String, label: String, primary := false) -> Button:
	var result := Button.new()
	result.name = node_name
	result.text = label
	result.focus_mode = Control.FOCUS_ALL
	result.custom_minimum_size.y = 41
	if primary:
		result.add_theme_stylebox_override("normal", _sign("#e9bb72"))
		result.add_theme_stylebox_override("hover", _sign("#ffda8f"))
		result.add_theme_stylebox_override("pressed", _sign("#c68f46"))
		for key in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
			result.add_theme_color_override(key, DARK)
	return result


func _sign(fill: String) -> StyleBoxTexture:
	var image := Image.new()
	# Nine-slice keeps the clipped corners and fine incised line at one scale.
	image.load_svg_from_string("""
<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36">
  <path d="M6 1h24l5 5v24l-5 5H6l-5-5V6z" fill="%s" stroke="#4b2f19" stroke-width="2"/>
  <path d="M8 4h20l4 4v20l-4 4H8l-4-4V8z" fill="none" stroke="#a2753c"/>
  <path d="M9 5h18l4 4M5 9v18" fill="none" stroke="#ffe1a1" stroke-opacity=".75"/>
</svg>
""" % fill)
	var panel := StyleBoxTexture.new()
	panel.texture = ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set_texture_margin(side, 11)
		panel.set_content_margin(side, 12 if side in [SIDE_LEFT, SIDE_RIGHT] else 6)
	return panel


func _menu(node_name: String, label: String) -> MenuButton:
	var result := MenuButton.new()
	result.name = node_name
	result.text = label
	result.focus_mode = Control.FOCUS_ALL
	result.custom_minimum_size.y = 41
	result.flat = false
	return result


func _label(text: String, pixels: int, color: Color, display := false) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result.add_theme_font_size_override("font_size", pixels)
	result.add_theme_color_override("font_color", color)
	if display:
		result.add_theme_font_override("font", _display)
		result.add_theme_color_override("font_shadow_color", Color("#24170e", 0.8))
		result.add_theme_constant_override("shadow_offset_y", 1)
	return result


func _make_theme() -> Theme:
	var skin := Theme.new()
	var book := SystemFont.new()
	book.font_names = PackedStringArray(["Noto Serif", "Georgia", "Liberation Serif"])
	skin.default_font = book
	skin.default_font_size = 16
	_display = SystemFont.new()
	_display.font_names = PackedStringArray(["Noto Serif", "Georgia", "Liberation Serif"])
	_display.font_weight = 600
	for kind in ["Button", "MenuButton", "OptionButton"]:
		skin.set_stylebox("normal", kind, _surface(Color("#37271c"), Color("#ad8858"), 12, 6))
		skin.set_stylebox("hover", kind, _surface(Color("#53402a"), Color("#d5ae72"), 12, 6))
		skin.set_stylebox("pressed", kind, _surface(Color("#4b3625"), Color("#efc67f"), 12, 6))
		skin.set_stylebox("disabled", kind, _surface(Color("#392d23"), Color("#74604a"), 12, 6))
		skin.set_stylebox("focus", kind, _surface(Color.TRANSPARENT, GOLD, 12, 6, 2))
		for key in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
			skin.set_color(key, kind, PARCHMENT)
		skin.set_color("font_disabled_color", kind, Color("#c5af90"))
	skin.set_stylebox("panel", "PopupMenu", _surface(Color("#2f2218"), Color("#b6905b"), 9, 6))
	skin.set_stylebox("hover", "PopupMenu", _surface(Color("#5a412b"), Color.TRANSPARENT, 9, 6))
	skin.set_color("font_color", "PopupMenu", PARCHMENT)
	skin.set_color("font_hover_color", "PopupMenu", PARCHMENT)
	skin.set_color("font_disabled_color", "PopupMenu", MUTED)
	skin.set_constant("v_separation", "PopupMenu", 9)
	return skin


func _surface(fill: Color, border: Color, horizontal: int, vertical: int, stroke := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(stroke)
	style.set_corner_radius_all(4)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style
