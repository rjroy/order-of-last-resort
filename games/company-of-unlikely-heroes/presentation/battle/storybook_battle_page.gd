extends Control
## A separate battle view, using the shared board and emitting only player intent.

signal hero_selected(hero_id: String)
signal action_selected(ability_id: String)
signal order_selected(hero_id: String, order_id: String)
signal target_selected(target_id: String)
signal cancel_targeting_requested
signal clear_requested
signal commit_requested
signal restart_requested
signal forfeit_requested
signal grid_visibility_changed(shown: bool)
signal grid_labels_visibility_changed(shown: bool)
signal nameplate_visibility_changed(shown: bool)
signal always_show_health_bar_changed(shown: bool)
signal forecast_visibility_changed(opened: bool)
signal hints_visibility_changed(shown: bool)
signal help_from_popup_requested(source: Control)
signal help_shortcut_requested
signal help_from_dialog_requested(dialog: Window, focus: Control)
signal sound_effects_volume_changed(value: float)
signal master_volume_changed(value: float)
signal music_volume_changed(value: float)

enum DisplayOption { GRID, NAMEPLATES, GRID_LABELS, ALWAYS_SHOW_HEALTH_BAR, SHOW_HINTS }

const DisplayPreferences := preload("res://presentation/settings/battle_display_preferences.gd")
const VolumeControls := preload("res://presentation/settings/volume_controls.gd")
const HELP_MENU_ID := 1000000
const SOUND_VOLUME_MENU_ID := 1000001
const Ink := preload("res://presentation/battle/storybook_battle_ink.gd")
const Surround := preload("res://presentation/battle/storybook_battle_surround.gd")
const SceneryRegistration := preload("res://presentation/battle/storybook_scenery.gdshader")
const Prep := preload("res://presentation/book/guild_prep_widgets.gd")
const CastSprites := preload("res://presentation/cast/cast_sprites.gd")
const BridgeArt := preload("res://presentation/battle/bridge_art.gd")
const GATE_BOARD := "frontier_gate_board"
const FIELD_BOARD := "frontier_field"
const GATE_ART := "res://assets/storybook-gate/"
const FIELD_ART := "res://assets/storybook-field/frontier-field-surround-rgba.png"
const BOARD_SURROUNDS := {
	"village_square": "res://assets/storybook-surrounds/village_square.png",
	"village_lane": "res://assets/storybook-surrounds/village_lane.png",
	"village_approach": "res://assets/storybook-surrounds/village_approach.png",
	"road": "res://assets/storybook-surrounds/road.png",
	"bridge": "res://assets/storybook-surrounds/bridge.png",
	"frontier_wagon_board": "res://assets/storybook-surrounds/frontier_wagon_board.png",
	"frontier_sheep_board": "res://assets/storybook-surrounds/frontier_sheep_board.png",
	"frontier_ritual_board": "res://assets/storybook-surrounds/frontier_ritual_board.png",
	"frontier_treasure_board": "res://assets/storybook-surrounds/frontier_treasure_board.png",
	"frontier_field": FIELD_ART,
	"frontier_line_board": "res://assets/storybook-surrounds/frontier_line_board.png",
	"frontier_bridge_board": "res://assets/storybook-surrounds/frontier_bridge_board.png",
}
const EDGE := 16.0
const CONTENT_MARGIN := EDGE + 26.0
const DARK := Color("#231910")
const PARCHMENT := Color("#f7e9c7")
const MUTED := Color("#dfc9a2")
const GOLD := Color("#ffda88")
const PAPER := Color("#f3dbad")
const PAPER_INK := Color("#362419")
const PAPER_MUTED := Color("#614831")
const LEAF_WIDTH := 416.0
const FORECAST_LEAF_HEIGHT := 304.0
const LEAF_GAP := 15.0
const LEAF_RAIL_GAP := 7.0
const FORFEIT_LEAF_WIDTH := 480.0
const ACTION_BAND_HEIGHT := 56.0
const DRAFT_SLOT_HEIGHT := 55.0
const DOSE_SLOT_HEIGHT := 72.0
const NOTE_SLOT_HEIGHT := 47.0
const PREVIEW_BAND_HEIGHT := DOSE_SLOT_HEIGHT + NOTE_SLOT_HEIGHT
const ROUND_BAND_HEIGHT := 47.0
const FOOTER_GAP := 5.0
const FOOTER_HEIGHT := ACTION_BAND_HEIGHT + PREVIEW_BAND_HEIGHT + ROUND_BAND_HEIGHT + 2.0 * FOOTER_GAP


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
var _options: MenuButton
var _sound_volume_dialog: AcceptDialog
var _volume_controls
var _help_utility_slot: Control
var _pending_display_option := -1
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
var _draft_scroll: ScrollContainer
var _summary: Label
var _aim_prompt: Label
var _inspection: Label
var _unavailable_note: Label
var _dose_scroll: ScrollContainer
var _locked_dose: Label
var _orders: Button
var _forecast: Button
var _clear: Button
var _commit: Button
var _leaf: PanelContainer
var _leaf_sheet: VBoxContainer
var _leaf_heading: Label
var _order_instructions: Label
var _orders_scroll: ScrollContainer
var _order_entries: VBoxContainer
var _forecast_scroll: ScrollContainer
var _forecast_text: Label
var _field_notes: Label
var _bleed: Surround
var _scenery: TextureRect
var _scenery_registration: ShaderMaterial
var _surround_behind_foreground := false
var _props: Dictionary = {}
var _header: Control
var _footer: VBoxContainer
var _book: Control
var _rail_top := 0.0
var _hero_picker: OptionButton
var _hero_rows: Array = []
var _selected_hero_index := 0
var _cancel_targeting: Button
var _action_rows: Array = []
var _action_buttons: Dictionary = {}
var _action_box: HBoxContainer
var _action_scroll: ScrollContainer
var _displayed_aim := ""
var _target_rows: Array = []
var _target_choice_buttons: Array = []
var _target_choice_box: HBoxContainer
var _target_choice_scroll: ScrollContainer
var _choice_selected_cell: Variant = null
var _order_rows: Array = []
var _order_widgets: Dictionary = {}
var _expanded := ""
var _popup_epoch := 0
var _dismissed_pickers: Array[OptionButton] = []
var _display: SystemFont
var _built := false
var _show_hints := true
var _help_covered := false
var _practice_controls: Control


func set_help_covered(covered: bool) -> void:
	_help_covered = covered
	if is_instance_valid(_practice_controls) and _practice_controls.has_method("set_help_covered"):
		_practice_controls.set_help_covered(covered)
	queue_accessibility_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		AccessibilityServer.update_set_flag(get_accessibility_element(), AccessibilityServer.FLAG_HIDDEN, _help_covered)


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
	elif BOARD_SURROUNDS.has(trusted_board_id):
		set_scene_art(CastSprites.load_texture(BOARD_SURROUNDS[trusted_board_id]), {})
		_surround_behind_foreground = trusted_board_id != FIELD_BOARD and _scenery.texture != null
		if _surround_behind_foreground:
			# Terrain, scenery, tactical ink/figures, then the book and controls.
			# Gate and the accepted Field retain their original composition.
			board.set_foreground_above_scenery(true)
			_scenery.z_index = 1
			_book.z_index = 4
			_header.z_index = 4
			_footer.z_index = 4
	_board_host.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.accessibility_name = "Battle board"
	board.accessibility_description = "Use arrow keys to inspect a tile. Enter selects a hero, moves to a marked destination, or targets the ability you are aiming."
	_ink = Ink.new()
	_ink.name = "StorybookInk"
	board.add_child(_ink)
	_ink.mount(board)
	_ink.set_scene_props(_props)
	_ink.set_scenery_coordinates(_scenery.texture != null and not _surround_behind_foreground)
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
	_forfeit.visible = active and not is_instance_valid(_practice_controls)
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
	var command: String = view.get("command_summary", "")
	if command.is_empty():
		command = "Standing orders only" if active else _victory_summary() if outcome == "victory" else "Mission failed"
	if command != _summary.text:
		_draft_scroll.scroll_vertical = 0
		_summary.text = command
	var draft_rule := "One Direct Order per round. A new command replaces the current draft."
	_summary.tooltip_text = _summary.text + ("\n" + draft_rule if active else "")
	_summary.accessibility_description = draft_rule if active else ""
	_summary.accessibility_live = AccessibilityServer.LIVE_POLITE
	var aimed: String = view.get("aimed_action_id", "")
	_aim_prompt.text = view.get("aim_prompt", "")
	_aim_prompt.tooltip_text = _aim_prompt.text
	_aim_prompt.accessibility_live = AccessibilityServer.LIVE_POLITE if not aimed.is_empty() else AccessibilityServer.LIVE_OFF
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
	if _expanded == "forecast":
		_leaf_heading.text = "Round forecast" if active else "Round result"
	_forecast_scroll.accessibility_name = "Round forecast in execution order" if active else "Resolved round events"
	_forecast_text.text = view.get("forecast", "")
	var objective_details: String = view.get("objective_details", "")
	if _board_id != FIELD_BOARD and not objective.is_empty() and objective_details.begins_with(objective):
		objective_details = objective_details.trim_prefix(objective).strip_edges()
	_field_notes.visible = active and not objective_details.is_empty() and objective_details != objective
	_field_notes.text = "Mission notes: " + objective_details if _field_notes.visible else ""
	_refresh_hero_picker(view.get("heroes", []), view.get("selected_hero_id", ""), active)
	_refresh_action_buttons(view.get("actions", []), aimed)
	_cancel_targeting.visible = active and not aimed.is_empty()
	_refresh_targets(view.get("targets", []), active, view.get("selected_cell", null))
	_refresh_orders(rows)
	_clear.disabled = not active or not view.get("can_clear", false)
	_clear.text = view.get("clear_label", "Clear command")
	_clear.accessibility_description = "Discard the draft and clear the hero selection." \
		if _clear.text == "Clear command" else "Return to the board without a selected hero."
	_commit.disabled = not active or not view.get("can_commit", false)
	_commit.accessibility_description = "Finish targeting or cancel before committing." if not aimed.is_empty() else \
		"Resolve this round using the current preview."
	_commit.tooltip_text = _commit.accessibility_description if active else ""
	_commit.text = "Commit round %d" % int(view.get("round", 1)) if active else (
		"Mission complete" if outcome == "victory" else "Mission failed")


func _victory_summary() -> String:
	return "The company made it through" if _board_id == GATE_BOARD else "Mission complete"


func is_forfeit_confirmation_open() -> bool:
	return is_instance_valid(_forfeit_modal) and _forfeit_modal.is_visible_in_tree()


func battle_controls_blocked() -> bool:
	return _help_covered or is_forfeit_confirmation_open() or _upgrade_dialog.visible or _sound_volume_dialog.visible


func set_display_options(grid_shown: bool, nameplates_shown: bool, grid_labels_shown: bool,
		always_show_health_bar: bool = false) -> void:
	_build()
	var popup := _options.get_popup()
	popup.set_item_checked(popup.get_item_index(DisplayOption.GRID), grid_shown)
	popup.set_item_checked(popup.get_item_index(DisplayOption.NAMEPLATES), nameplates_shown)
	popup.set_item_checked(popup.get_item_index(DisplayOption.GRID_LABELS), grid_labels_shown)
	popup.set_item_checked(popup.get_item_index(DisplayOption.ALWAYS_SHOW_HEALTH_BAR), always_show_health_bar)


func render_ink(cues: Dictionary) -> void:
	if is_instance_valid(_ink):
		_ink.render(cues)


func _render_locked_dose(text: String) -> void:
	if _locked_dose.text != text:
		_dose_scroll.scroll_vertical = 0
	_locked_dose.text = text
	_locked_dose.accessibility_name = text
	_locked_dose.tooltip_text = text
	_locked_dose.visible = not text.is_empty()
	_dose_scroll.visible = _locked_dose.visible
	_inspection.offset_top = DOSE_SLOT_HEIGHT if _dose_scroll.visible else 0.0
	_unavailable_note.offset_top = _inspection.offset_top


## Scenery uses full-page coordinates with transparent space for the live grid.
## Props supply normalized anchors and display sizes at the authored board scale.
func set_scene_art(surround: Texture2D, props: Dictionary) -> void:
	_build()
	_scenery.texture = surround
	_scenery.material = _scenery_registration if surround != null else null
	_props = props.duplicate(true)
	if is_instance_valid(_ink):
		_ink.set_scene_props(_props)
		_ink.set_scenery_coordinates(surround != null and not _surround_behind_foreground)


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
	_scenery_registration = ShaderMaterial.new()
	_scenery_registration.shader = SceneryRegistration
	_surface_root.add_child(_scenery)
	_scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The leaf edge, shaded margins, and separating rules sit above the painting,
	# but never take input from the mounted board or the controls.
	_book = Control.new()
	_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.draw.connect(_draw_book.bind(_book))
	_surface_root.add_child(_book)
	_book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_header()
	_build_footer()
	_build_target_choices()
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
	_help_utility_slot = Control.new()
	_help_utility_slot.name = "HelpUtilitySlot"
	_help_utility_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_utility_slot.custom_minimum_size = Vector2(44, 41)
	_header.add_child(_help_utility_slot)
	_options = _menu("Options", "Options")
	_show_hints = DisplayPreferences.load_show_hints()
	_options.accessibility_description = "Battlefield grid, grid labels, nameplates, and health bar display options."
	_style_rail_button(_options)
	_options.custom_minimum_size = Vector2(104, 41)
	_header.add_child(_options)
	var options_popup := _options.get_popup()
	options_popup.add_check_item("Show Grid", DisplayOption.GRID)
	options_popup.add_check_item("Show Grid Labels", DisplayOption.GRID_LABELS)
	options_popup.add_check_item("Show Nameplates", DisplayOption.NAMEPLATES)
	options_popup.add_check_item("Always show health bar", DisplayOption.ALWAYS_SHOW_HEALTH_BAR)
	options_popup.add_check_item("Show hints", DisplayOption.SHOW_HINTS)
	options_popup.add_item("Volume…", SOUND_VOLUME_MENU_ID)
	options_popup.add_separator()
	options_popup.add_item("Help (F1)", HELP_MENU_ID)
	_set_help_shortcut(options_popup)
	options_popup.set_item_checked(options_popup.get_item_index(DisplayOption.SHOW_HINTS),
		DisplayPreferences.load_show_hints())
	options_popup.hide_on_checkable_item_selection = false
	options_popup.visibility_changed.connect(_battle_popup_visibility_changed.bind(options_popup))
	options_popup.popup_hide.connect(_restore_options_focus)
	options_popup.id_pressed.connect(_queue_display_option)
	options_popup.window_input.connect(_handle_options_window_input)
	options_popup.window_input.connect(_popup_help_input.bind(_options, options_popup))
	_build_sound_volume_dialog()
	_restart = _button("Restart", "Restart mission")
	_restart.custom_minimum_size.x = 141.0
	_header.add_child(_restart)
	_restart.pressed.connect(_request_battle_action.bind(restart_requested, _restart))
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
	_upgrade_dialog.add_button("Help (F1)", false, "help")
	_upgrade_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"help":
			_open_upgrade_help())
	_upgrade_dialog.window_input.connect(func(event: InputEvent) -> void:
		if _is_help_key(event):
			_upgrade_dialog.set_input_as_handled()
			_open_upgrade_help())
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
		if _help_covered or is_forfeit_confirmation_open():
			return
		_upgrade_dialog.popup_centered(Vector2i(540, 310))
		scroll.grab_focus())
	_upgrade_dialog.visibility_changed.connect(func() -> void:
		if not _help_covered and not is_forfeit_confirmation_open() and not _upgrade_dialog.visible and _upgrades.is_visible_in_tree():
			_upgrades.grab_focus())


func _open_upgrade_help() -> void:
	if _help_covered:
		return
	var focus := _upgrade_dialog.gui_get_focus_owner()
	_upgrade_dialog.hide()
	help_from_dialog_requested.emit(_upgrade_dialog, focus)


func _is_help_key(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1


func _popup_help_input(event: InputEvent, source: Control, popup: PopupMenu) -> void:
	if not _is_help_key(event):
		return
	popup.set_meta("help_restore_row", popup.get_focused_item())
	popup.set_input_as_handled()
	popup.hide()
	help_from_popup_requested.emit(source)


func _set_help_shortcut(popup: PopupMenu) -> void:
	var shortcut := Shortcut.new()
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	shortcut.events = [key]
	popup.set_item_shortcut(popup.get_item_index(HELP_MENU_ID), shortcut)


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
	_forfeit_panel = Prep.mount(center, false, false, true, Color("#fae7c2"), 29, 24)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	_forfeit_panel.add_child(content)
	var heading := _label("Forfeit mission?", 37, PAPER_INK)
	heading.add_theme_font_override("font", _display)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(heading)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := StyleBoxLine.new()
	ink.color = Color("#a75a43")
	ink.thickness = 2
	rule.add_theme_stylebox_override("separator", ink)
	content.add_child(rule)
	_forfeit_copy = _label("", 22, PAPER_INK)
	_forfeit_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forfeit_copy.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	content.add_child(_forfeit_copy)
	var help_note := _label("Press F1 for Help.", 16, PAPER_MUTED)
	help_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(help_note)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.y = 4
	content.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_theme_constant_override("separation", 17)
	content.add_child(buttons)
	_forfeit_cancel = _button("CancelForfeit", "Cancel")
	_style_forfeit_choice(_forfeit_cancel, Color("#204a36"), Color("#2c5c45"), Color("#173929"), Color("#142d20"))
	buttons.add_child(_forfeit_cancel)
	_forfeit_confirm = _button("ConfirmForfeit", "Forfeit mission")
	_style_forfeit_choice(_forfeit_confirm, Color("#862b22"), Color("#96372b"), Color("#682219"), Color("#591e17"))
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


func _style_forfeit_choice(button: Button, fill: Color, hover: Color, pressed: Color, edge: Color) -> void:
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 57
	button.add_theme_font_override("font", _display)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _surface(fill, edge, 13, 8))
	button.add_theme_stylebox_override("hover", _surface(hover, edge, 13, 8))
	button.add_theme_stylebox_override("pressed", _surface(pressed, edge, 13, 8))
	button.add_theme_stylebox_override("focus", _focus_outline(Color("#a25717"), 4.0))


func _open_forfeit_confirmation() -> void:
	if _help_covered or not _forfeit.is_visible_in_tree() or is_forfeit_confirmation_open():
		return
	_forfeit_copy.text = "This mission will count as a defeat."
	if not _restart.visible:
		_forfeit_copy.text += "\nYour outing will end."
	_forfeit_modal.accessibility_description = _forfeit_copy.text
	_forfeit_cancel.accessibility_description = _forfeit_copy.text
	_popup_epoch += 1
	_dismissed_pickers.clear()
	_forfeit_modal.show()
	_surface_root.set_inert(true)
	_dismiss_battle_popups()
	_forfeit_cancel.grab_focus()


func _close_forfeit_confirmation() -> void:
	_surface_root.set_inert(false)
	_forfeit_modal.hide()


func _cancel_forfeit() -> void:
	if _help_covered or not is_forfeit_confirmation_open():
		return
	_close_forfeit_confirmation()
	_reexpose_dismissed_pickers()
	if _forfeit.is_visible_in_tree():
		_forfeit.grab_focus()


func _confirm_forfeit() -> void:
	if _help_covered or not is_forfeit_confirmation_open() or not _forfeit.is_visible_in_tree():
		return
	_close_forfeit_confirmation()
	forfeit_requested.emit()
	# Standalone defeat renders on this page; an outing replaces the page.
	if not _forfeit.visible and _restart.is_visible_in_tree():
		_restart.grab_focus()


func _request_battle_action(intent: Signal, source: BaseButton) -> void:
	if not battle_controls_blocked() and source.is_visible_in_tree() and not source.disabled:
		intent.emit()


func _queue_display_option(option: int) -> void:
	if _help_covered:
		return
	if option == HELP_MENU_ID:
		help_from_popup_requested.emit(_options)
		return
	if option == SOUND_VOLUME_MENU_ID:
		_options.get_popup().hide()
		_open_sound_volume.call_deferred()
		return
	# Godot emits id_pressed before window_input. Wait for the originating
	# event; assistive activation has no window event and uses the deferred call.
	_apply_display_option()
	_pending_display_option = option
	_apply_display_option.call_deferred()


func _build_sound_volume_dialog() -> void:
	_sound_volume_dialog = AcceptDialog.new()
	_sound_volume_dialog.name = "SoundEffectsDialog"
	_sound_volume_dialog.title = "Volume"
	_sound_volume_dialog.min_size = Vector2i(360, 300)
	add_child(_sound_volume_dialog)
	_sound_volume_dialog.get_ok_button().text = "Close"
	_sound_volume_dialog.close_requested.connect(func(): _restore_options_focus.call_deferred())
	_sound_volume_dialog.confirmed.connect(func(): _restore_options_focus.call_deferred())
	_volume_controls = VolumeControls.new()
	_sound_volume_dialog.add_child(_volume_controls)
	_volume_controls.volume_changed.connect(_volume_changed)


func _open_sound_volume() -> void:
	if not _help_covered and not is_forfeit_confirmation_open():
		_volume_controls.refresh()
		_sound_volume_dialog.popup_centered()
		_volume_controls.focus_master()


func _volume_changed(category: String, value: float) -> void:
	match category:
		"master": master_volume_changed.emit(value)
		"music": music_volume_changed.emit(value)
		"sfx": sound_effects_volume_changed.emit(value)


func _handle_options_window_input(event: InputEvent) -> void:
	if event.is_echo() and event.is_action_pressed("ui_accept", true):
		_pending_display_option = -1
	else:
		_apply_display_option()


func _apply_display_option() -> void:
	var option := _pending_display_option
	_pending_display_option = -1
	if option < 0:
		return
	var popup := _options.get_popup()
	if not popup.visible or not _battle_popup_accepts_selection(popup):
		return
	var index := popup.get_item_index(option)
	if index < 0:
		return
	var shown := not popup.is_item_checked(index)
	popup.set_item_checked(index, shown)
	match option:
		DisplayOption.GRID:
			grid_visibility_changed.emit(shown)
		DisplayOption.GRID_LABELS:
			grid_labels_visibility_changed.emit(shown)
		DisplayOption.NAMEPLATES:
			nameplate_visibility_changed.emit(shown)
		DisplayOption.ALWAYS_SHOW_HEALTH_BAR:
			always_show_health_bar_changed.emit(shown)
		DisplayOption.SHOW_HINTS:
			_show_hints = shown
			DisplayPreferences.save_show_hints(shown)
			_update_action_tooltips()
			hints_visibility_changed.emit(shown)


func _restore_options_focus() -> void:
	_pending_display_option = -1
	if not _help_covered and not is_forfeit_confirmation_open() and _options.is_visible_in_tree():
		_options.grab_focus()


func _dismiss_battle_popups() -> void:
	_upgrade_dialog.hide()
	_options.get_popup().hide()
	var hero_popup := _hero_picker.get_popup()
	if hero_popup.visible:
		_dismissed_pickers.append(_hero_picker)
		hero_popup.hide()
	for widgets: Dictionary in _order_widgets.values():
		var picker: OptionButton = widgets.picker
		var popup := picker.get_popup()
		if popup.visible:
			_dismissed_pickers.append(picker)
			popup.hide()


func _reexpose_dismissed_pickers() -> void:
	for picker in _dismissed_pickers:
		if not is_instance_valid(picker) or not picker.is_visible_in_tree():
			continue
		# Closing an open popup under the inert surface can leave its picker
		# defunct to AT-SPI. Re-enter the tree to publish fresh accessibility
		# elements without changing the picker, popup epoch, or standing order.
		var row := picker.get_parent()
		var index := picker.get_index()
		row.remove_child(picker)
		row.add_child(picker)
		row.move_child(picker, index)
	_dismissed_pickers.clear()


func _battle_popup_visibility_changed(popup: PopupMenu) -> void:
	if not popup.visible:
		return
	if popup == _options.get_popup():
		popup.position.x = maxi(0, int(get_viewport_rect().size.x) - popup.size.x - 12)
	var source: Control
	if popup == _hero_picker.get_popup():
		source = _hero_picker
		popup.position.x = clampi(popup.position.x, 0, maxi(0, int(get_viewport_rect().size.x) - popup.size.x))
	else:
		for widgets: Dictionary in _order_widgets.values():
			if widgets.picker.get_popup() == popup:
				source = widgets.picker
				break
	if is_instance_valid(source):
		var launcher := source.get_global_rect()
		var popup_rect := Rect2(Vector2(popup.position), Vector2(popup.size))
		if popup_rect.intersects(launcher):
			var above := launcher.position.y - popup_rect.size.y - 2.0
			var below := launcher.end.y + 2.0
			popup.position.y = int(above if above >= 0.0 else below)
	# A native menu can still receive an assistive click queued before the
	# background was hidden from accessibility.
	if battle_controls_blocked():
		popup.hide()
		if is_forfeit_confirmation_open() and get_viewport().gui_get_focus_owner() not in [_forfeit_cancel, _forfeit_confirm]:
			_forfeit_cancel.grab_focus()
	else:
		popup.set_meta(&"_battle_popup_epoch", _popup_epoch)


func _battle_popup_accepts_selection(popup: PopupMenu) -> bool:
	# Godot hides the popup before signaling a valid selection. Keep accepting
	# its callbacks until Forfeit invalidates them, and rearm only on reopening.
	return not battle_controls_blocked() and popup.get_meta(&"_battle_popup_epoch", 0) == _popup_epoch


func _build_footer() -> void:
	_footer = VBoxContainer.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_theme_constant_override("separation", int(FOOTER_GAP))
	_surface_root.add_child(_footer)
	_build_action_band()
	_build_preview_band()
	_build_round_band()


func _build_action_band() -> void:
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = ACTION_BAND_HEIGHT
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_theme_constant_override("separation", 8)
	_footer.add_child(toolbar)
	_hero_picker = OptionButton.new()
	_hero_picker.name = "DirectOrderHero"
	_hero_picker.fit_to_longest_item = false
	_hero_picker.clip_text = true
	_hero_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hero_picker.accessibility_name = "Direct Order hero"
	_hero_picker.accessibility_description = "Switch heroes without discarding the current draft. Switching cancels targeting."
	_style_rail_button(_hero_picker)
	_hero_picker.custom_minimum_size.x = 188
	_hero_picker.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	toolbar.add_child(_hero_picker)
	var popup := _hero_picker.get_popup()
	popup.visibility_changed.connect(_battle_popup_visibility_changed.bind(popup))
	popup.window_input.connect(_popup_help_input.bind(_hero_picker, popup))
	_hero_picker.item_selected.connect(_select_hero_item)
	_action_scroll = _horizontal_button_scroll()
	_action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_scroll.accessibility_name = "Direct Order abilities"
	toolbar.add_child(_action_scroll)
	_action_box = HBoxContainer.new()
	_action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_box.add_theme_constant_override("separation", 6)
	_action_scroll.add_child(_action_box)
	var cancel_slot := Control.new()
	cancel_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cancel_slot.custom_minimum_size = Vector2(146.0, 44.0)
	cancel_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	toolbar.add_child(cancel_slot)
	_cancel_targeting = _button("CancelTargeting", "Cancel targeting")
	_style_rail_button(_cancel_targeting)
	_cancel_targeting.accessibility_description = "Stop aiming without discarding the current draft. You can also press Escape."
	_cancel_targeting.tooltip_text = _cancel_targeting.accessibility_description
	cancel_slot.add_child(_cancel_targeting)
	_cancel_targeting.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cancel_targeting.pressed.connect(_request_battle_action.bind(cancel_targeting_requested, _cancel_targeting))
	_cancel_targeting.hide()


func _build_preview_band() -> void:
	# Fixed slots size the board, not the text inside them. Keep the dose in
	# its own column so a long inspection cannot steal any of its measure.
	var preview := HBoxContainer.new()
	preview.custom_minimum_size.y = PREVIEW_BAND_HEIGHT
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_constant_override("separation", 18)
	_footer.add_child(preview)
	var plan_notes := _preview_column(preview, 1.0)
	var field_notes := _preview_column(preview, 1.27)
	_summary = _label("", 18, PARCHMENT, true)
	_draft_scroll = _preview_reader(plan_notes, "DraftSummary", "Draft summary", DRAFT_SLOT_HEIGHT, _summary)
	_aim_prompt = _preview_label(plan_notes, 15, GOLD, DRAFT_SLOT_HEIGHT, PREVIEW_BAND_HEIGHT)
	_aim_prompt.name = "AimPrompt"
	_inspection = _preview_label(field_notes, 15, MUTED, DOSE_SLOT_HEIGHT, PREVIEW_BAND_HEIGHT)
	_unavailable_note = _preview_label(field_notes, 15, GOLD, DOSE_SLOT_HEIGHT, PREVIEW_BAND_HEIGHT)
	_unavailable_note.hide()
	_build_dose_note(field_notes)


func _build_dose_note(parent: Control) -> void:
	_locked_dose = _label("", 15, PARCHMENT)
	_locked_dose.name = "LockedDose"
	_dose_scroll = _preview_reader(parent, "DoseNote", "Locked dose", DOSE_SLOT_HEIGHT, _locked_dose)
	_dose_scroll.add_theme_stylebox_override("panel", _surface(Color("#30241d"), Color("#ab8967"), 8, 0))
	_locked_dose.hide()
	_dose_scroll.hide()


func _preview_reader(parent: Control, node_name: String, title: String, height: float, text: Label) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.draw_focus_border = true
	scroll.accessibility_name = title
	scroll.accessibility_description = "If the text does not fit, use Up and Down to read it."
	scroll.add_theme_stylebox_override("focus", _focus_outline(GOLD))
	parent.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	scroll.offset_bottom = height
	scroll.gui_input.connect(_preview_reader_input.bind(scroll, text))
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	text.add_theme_constant_override("line_spacing", 1)
	scroll.add_child(text)
	return scroll


func _preview_reader_input(event: InputEvent, scroll: ScrollContainer, text: Label) -> void:
	if battle_controls_blocked() or not scroll.get_v_scroll_bar().visible:
		return
	var step := text.get_line_height() + text.get_theme_constant("line_spacing")
	if event.is_action_pressed("ui_up", true):
		scroll.scroll_vertical -= step
	elif event.is_action_pressed("ui_down", true):
		scroll.scroll_vertical += step
	else:
		return
	scroll.accept_event()


func _preview_column(parent: Container, weight: float) -> Control:
	var column := Control.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.clip_contents = true
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = weight
	parent.add_child(column)
	return column


func _preview_label(parent: Control, pixels: int, tint: Color, top: float, bottom: float) -> Label:
	var label := _label("", pixels, tint)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.add_theme_constant_override("line_spacing", 1)
	parent.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = top
	label.offset_bottom = bottom
	return label


func _horizontal_button_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events = false
	return scroll


func _build_round_band() -> void:
	var controls := HBoxContainer.new()
	controls.custom_minimum_size.y = ROUND_BAND_HEIGHT
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_theme_constant_override("separation", 8)
	_footer.add_child(controls)
	_orders = _button("StandingOrders", "Standing orders")
	_orders.toggle_mode = true
	_style_rail_button(_orders, true)
	controls.add_child(_orders)
	_orders.pressed.connect(_toggle_leaf.bind("orders"))
	_forecast = _button("ForecastDetails", "Forecast")
	_forecast.toggle_mode = true
	_style_rail_button(_forecast, true)
	controls.add_child(_forecast)
	_forecast.pressed.connect(_toggle_leaf.bind("forecast"))
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(space)
	_clear = _button("ClearCommand", "Clear command")
	_style_rail_button(_clear)
	controls.add_child(_clear)
	_clear.pressed.connect(_request_battle_action.bind(clear_requested, _clear))
	_commit = _button("Commit", "Commit round 1")
	_style_rail_button(_commit, false, true)
	_commit.add_theme_font_override("font", _display)
	_commit.add_theme_font_size_override("font_size", 21)
	controls.add_child(_commit)
	_commit.pressed.connect(_request_battle_action.bind(commit_requested, _commit))
	for button: Button in [_orders, _forecast, _clear, _commit]:
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _build_leaf() -> void:
	_leaf = Prep.mount(_surface_root, false, true, true, PAPER, 26, 14)
	_leaf.name = "ExtraDetails"
	_leaf.z_index = 5
	_leaf.mouse_filter = Control.MOUSE_FILTER_STOP
	_leaf.mouse_force_pass_scroll_events = false
	# Text can report a transient wrapped minimum as its pane is shown.
	# Keep it from growing the sheet outside the fitted layout.
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.clip_contents = true
	_leaf.add_child(body)
	_leaf_sheet = VBoxContainer.new()
	_leaf_sheet.add_theme_constant_override("separation", 5)
	body.add_child(_leaf_sheet)
	_leaf_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_leaf_heading = _label("Standing orders", 23, PAPER_INK)
	_leaf_heading.add_theme_font_override("font", _display)
	_leaf_sheet.add_child(_leaf_heading)
	_order_instructions = _label("An order stays in place when a direct command takes its turn.", 14, PAPER_MUTED)
	_order_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_instructions.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_leaf_sheet.add_child(_order_instructions)
	_orders_scroll = _leaf_scroll(_leaf_sheet)
	_order_entries = VBoxContainer.new()
	_order_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order_entries.add_theme_constant_override("separation", 4)
	_orders_scroll.add_child(_order_entries)
	# An initial layout can precede wrapping the instructions at the new width.
	_leaf_sheet.minimum_size_changed.connect(_relayout_orders, CONNECT_DEFERRED)
	_order_entries.minimum_size_changed.connect(_relayout_orders, CONNECT_DEFERRED)
	_forecast_scroll = _leaf_scroll(_leaf_sheet)
	_forecast_scroll.focus_mode = Control.FOCUS_ALL
	_forecast_scroll.draw_focus_border = true
	_forecast_scroll.accessibility_name = "Round forecast in execution order"
	_forecast_scroll.add_theme_stylebox_override("panel", _surface(Color.TRANSPARENT, Color.TRANSPARENT, 8, 5, 0))
	_forecast_scroll.add_theme_stylebox_override("focus", _focus_outline(Color("#88471d")))
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	_forecast_scroll.add_child(content)
	_forecast_text = _label("", 16, PAPER_INK)
	_forecast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	content.add_child(_forecast_text)
	_field_notes = _label("", 14, PAPER_MUTED)
	_field_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_field_notes.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_field_notes.hide()
	content.add_child(_field_notes)
	_leaf.hide()


func _relayout_orders() -> void:
	if _expanded == "orders":
		_layout_page()


func _leaf_scroll(sheet: VBoxContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	sheet.add_child(scroll)
	var bar := scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", _surface(Color("#e4c796"), Color("#c8aa7b"), 4, 4))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, _surface(Color("#986d46"), Color("#805936"), 4, 4))
	return scroll


func _toggle_leaf(section: String) -> void:
	# Assistive activation can bypass GUI input and toggle a button directly.
	if _help_covered or _upgrade_dialog.visible or _sound_volume_dialog.visible:
		return
	var was_forecast := _expanded == "forecast"
	if not is_forfeit_confirmation_open():
		_expanded = "" if _expanded == section else section
	_orders.set_pressed_no_signal(_expanded == "orders")
	_forecast.set_pressed_no_signal(_expanded == "forecast")
	if is_forfeit_confirmation_open():
		return
	_leaf_heading.text = "Standing orders" if _expanded == "orders" else (
		"Round forecast" if _forecast.text == "Forecast" else "Round result")
	_order_instructions.visible = _expanded == "orders"
	_orders_scroll.visible = _expanded == "orders"
	_forecast_scroll.visible = _expanded == "forecast"
	_leaf.visible = not _expanded.is_empty()
	_update_target_choice_visibility()
	_layout_page()
	if was_forecast != (_expanded == "forecast"):
		forecast_visibility_changed.emit(_expanded == "forecast")
	if _expanded == "forecast":
		_forecast_scroll.grab_focus()
	elif _expanded == "orders":
		for value: Dictionary in _order_widgets.values():
			if not value.picker.disabled:
				value.picker.grab_focus()
				break


func close_forecast() -> void:
	if _expanded == "forecast":
		_toggle_leaf("forecast")


func mount_practice_controls(controls: Control) -> void:
	_build()
	assert(not is_instance_valid(_practice_controls) and controls.get_parent() == null)
	_practice_controls = controls
	_surface_root.add_child(controls)
	controls.z_index = 6
	controls.minimum_size_changed.connect(_layout_page, CONNECT_DEFERRED)
	_forfeit.hide()
	_layout_page()


func _input(event: InputEvent) -> void:
	if is_forfeit_confirmation_open():
		_forfeit_input(event)
		return
	for popup: PopupMenu in [_options.get_popup(), _hero_picker.get_popup()]:
		if not popup.visible:
			continue
		# The menu gets its own input. Dismiss events reaching the board must
		# not select a cell or fall through to Escape's clear-command shortcut.
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed
				and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]):
			get_viewport().set_input_as_handled()
			popup.hide()
			return
	if not _expanded.is_empty() and event.is_action_pressed("ui_cancel"):
		var source := _orders if _expanded == "orders" else _forecast
		var focused := get_viewport().gui_get_focus_owner()
		if focused == source or (focused != null and _leaf.is_ancestor_of(focused)):
			_toggle_leaf(_expanded)
			source.grab_focus()
			get_viewport().set_input_as_handled()


func _forfeit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		help_shortcut_requested.emit()
		return
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


func _refresh_hero_picker(rows: Array, selected_hero: String, active: bool) -> void:
	var selected := rows.find_custom(func(row: Dictionary) -> bool: return row.id == selected_hero) + 1
	if rows != _hero_rows or _hero_picker.item_count == 0:
		_hero_rows = rows.duplicate(true)
		_hero_picker.clear()
		_hero_picker.add_item("Choose a hero")
		_hero_picker.set_item_disabled(0, true)
		for row: Dictionary in rows:
			_hero_picker.add_item(row.label)
			_hero_picker.set_item_metadata(_hero_picker.item_count - 1, row.id)
	if selected != _selected_hero_index:
		_action_scroll.scroll_horizontal = 0
	_selected_hero_index = selected
	_hero_picker.select(selected)
	_hero_picker.disabled = not active or rows.is_empty()
	_hero_picker.tooltip_text = _hero_picker.text + "\n" + _hero_picker.accessibility_description


func _select_hero_item(index: int) -> void:
	if index <= 0 or index >= _hero_picker.item_count or _hero_picker.disabled \
			or not _battle_popup_accepts_selection(_hero_picker.get_popup()):
		_hero_picker.select(_selected_hero_index)
		return
	hero_selected.emit(str(_hero_picker.get_item_metadata(index)))


func _refresh_action_buttons(rows: Array, aimed: String) -> void:
	if rows == _action_rows and aimed == _displayed_aim:
		return
	_action_rows = rows.duplicate(true)
	_displayed_aim = aimed
	var incoming := rows.map(func(row: Dictionary) -> String: return row.id)
	for id: String in _action_buttons.keys():
		if id not in incoming:
			var old: Button = _action_buttons[id]
			_action_box.remove_child(old)
			old.queue_free()
			_action_buttons.erase(id)
	for index in rows.size():
		var row: Dictionary = rows[index]
		var id: String = row.id
		if not _action_buttons.has(id):
			var control := _button(("DirectOrder_" + id).validate_node_name(), "")
			control.set_meta(&"ability_id", id)
			control.clip_text = true
			control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_style_rail_button(control, true)
			_action_box.add_child(control)
			control.pressed.connect(_select_action_button.bind(id, control))
			control.focus_entered.connect(_show_unavailable_note.bind(control))
			control.mouse_entered.connect(_show_unavailable_note.bind(control))
			control.focus_exited.connect(_refresh_unavailable_note, CONNECT_DEFERRED)
			control.mouse_exited.connect(_refresh_unavailable_note, CONNECT_DEFERRED)
			_action_buttons[id] = control
		var button: Button = _action_buttons[id]
		_action_box.move_child(button, index)
		_set_button_label(button, str(row.label))
		button.disabled = not row.enabled
		if button.toggle_mode:
			button.set_pressed_no_signal(false)
		button.toggle_mode = row.kind in ["cell", "entity"]
		if button.toggle_mode:
			button.set_pressed_no_signal(aimed == id)
		var effect := "Choose a marked target." if button.toggle_mode else "Stage this Direct Order immediately."
		if button.disabled:
			effect = str(row.reason)
		button.accessibility_description = effect + (" " + str(row.help) if not str(row.help).is_empty() else "")
	_update_action_tooltips()
	_refresh_unavailable_note()


func _select_action_button(id: String, source: Button) -> void:
	# Clicking the already-aimed action restarts its aim, rather than toggling it off.
	if source.toggle_mode:
		source.set_pressed_no_signal(_displayed_aim == id)
	if not battle_controls_blocked() and source.is_visible_in_tree() and not source.disabled:
		action_selected.emit(id)


func _set_button_label(button: Button, label: String) -> void:
	button.text = label
	button.accessibility_name = label
	button.custom_minimum_size.x = clampf(_button_label_width(button, label), 69.0, 264.0)


func _button_label_width(button: Button, label: String) -> float:
	var width := button.get_theme_font("font").get_string_size(
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
	var padding := button.get_theme_stylebox("normal").get_minimum_size().x
	return ceilf(width + padding + 4.0)


func _update_action_tooltips() -> void:
	for row: Dictionary in _action_rows:
		var button: Button = _action_buttons[row.id]
		var lines: PackedStringArray = [str(row.label)]
		if button.disabled:
			lines.append(str(row.reason))
		if _show_hints and not str(row.help).is_empty():
			lines.append(str(row.help))
		button.tooltip_text = "\n".join(lines)


func _unavailable_reason(source: Control) -> String:
	if not source is Button or not source.disabled or not source.is_visible_in_tree() or battle_controls_blocked():
		return ""
	var id: String = source.get_meta(&"ability_id", "")
	for row: Dictionary in _action_rows:
		if row.id == id:
			return "%s — %s" % [row.label, row.reason]
	return ""


func _show_unavailable_note(source: Control) -> void:
	# Disabled native Buttons still receive tab focus; present the same
	# reason in the notebook for both focus and pointer hover.
	var reason := _unavailable_reason(source)
	if not reason.is_empty():
		_render_unavailable_note(reason)


func _refresh_unavailable_note() -> void:
	if not is_inside_tree():
		return
	var reason := _unavailable_reason(get_viewport().gui_get_focus_owner())
	if reason.is_empty():
		reason = _unavailable_reason(get_viewport().gui_get_hovered_control())
	_render_unavailable_note(reason)


func _render_unavailable_note(reason: String) -> void:
	_unavailable_note.text = reason
	_unavailable_note.tooltip_text = reason
	_unavailable_note.visible = not reason.is_empty()
	_inspection.visible = reason.is_empty()


func _refresh_targets(rows: Array, active: bool, selected_cell: Variant = null) -> void:
	_choice_selected_cell = selected_cell
	if not active:
		rows = []
	if rows == _target_rows and _target_choice_buttons.size() == rows.size():
		_place_target_choices()
		return
	var newly_opened := not rows.is_empty() and _target_rows.is_empty()
	var focus_was_choice := _target_choice_buttons.has(get_viewport().gui_get_focus_owner())
	_target_rows = rows.duplicate(true)
	for button: Button in _target_choice_buttons:
		_target_choice_box.remove_child(button)
		button.queue_free()
	_target_choice_buttons.clear()
	for target: Dictionary in rows:
		var button := _button("OccupantChoice", "")
		button.set_meta(&"target_id", target.id)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_style_rail_button(button)
		_target_choice_box.add_child(button, true)
		_set_button_label(button, str(target.label))
		button.tooltip_text = button.text
		button.accessibility_description = "Choose this occupant at %s." % BridgeArt.coordinate(target.position)
		button.pressed.connect(_emit_target_choice.bind(str(target.id), button))
		_target_choice_buttons.append(button)
	_update_target_choice_visibility()
	_place_target_choices()
	if battle_controls_blocked():
		return
	if _target_choice_scroll.visible and (newly_opened or focus_was_choice):
		(_target_choice_buttons[0] as Button).grab_focus()
	elif focus_was_choice and is_instance_valid(_board):
		_board.grab_focus()


func _update_target_choice_visibility() -> void:
	# An open Forecast or Standing orders leaf must not be covered or
	# intercepted by the floating choice. The choice itself stays valid and
	# returns when the leaf closes.
	_target_choice_scroll.visible = _expanded.is_empty() and not _target_rows.is_empty()


func _emit_target_choice(id: String, source: Button) -> void:
	if not battle_controls_blocked() and source.is_visible_in_tree():
		target_selected.emit(id)


## The contextual choice floats above the board, anchored beside the clicked
## target cell. Deterministic candidate order with edge flipping keeps the
## panel inside the viewport and the footer band, near the target, and never
## over the target cell or the selected hero.
const CHOICE_GAP := 8.0


func _build_target_choices() -> void:
	# Added after the footer so the panel draws above the board and rail, and
	# before the leaf and forfeit overlays so those stay on top when opened.
	# The z layer matches the interactive chrome: above the book and footer
	# frames on surround boards, below the forfeit confirmation modal.
	_target_choice_scroll = _horizontal_button_scroll()
	_target_choice_scroll.accessibility_name = "Choose an occupant"
	_target_choice_scroll.z_index = 6
	_target_choice_scroll.hide()
	_surface_root.add_child(_target_choice_scroll)
	_target_choice_box = HBoxContainer.new()
	_target_choice_box.add_theme_constant_override("separation", 6)
	_target_choice_scroll.add_child(_target_choice_box)


func _place_target_choices() -> void:
	if not is_instance_valid(_board) or _target_rows.is_empty():
		return
	var box := _target_choice_scroll
	var available := _choice_available_rect()
	var ideal := _target_choice_box.get_combined_minimum_size()
	box.size = Vector2(minf(ideal.x, available.size.x), ideal.y if ideal.x <= available.size.x else ACTION_BAND_HEIGHT)
	# Board geometry and the covered-hero rect are identical for every
	# candidate, so compute them once and share the results.
	var transform := _board.get_global_transform_with_canvas()
	var cell_size := _cell_size_global()
	var center: Vector2 = transform * _board.cell_center(_target_rows[0].position)
	var cell_rect := Rect2(center - cell_size * 0.5, cell_size)
	var selected_rect: Variant = null
	if _choice_selected_cell is Vector2i:
		var selected_center: Vector2 = transform * _board.cell_center(_choice_selected_cell)
		selected_rect = Rect2(selected_center - cell_size * 0.5, cell_size)
	var box_size := box.size
	var candidates := [
		Vector2(center.x - box_size.x * 0.5, cell_rect.end.y + CHOICE_GAP),
		Vector2(center.x - box_size.x * 0.5, cell_rect.position.y - CHOICE_GAP - box_size.y),
		Vector2(cell_rect.end.x + CHOICE_GAP, center.y - box_size.y * 0.5),
		Vector2(cell_rect.position.x - CHOICE_GAP - box_size.x, center.y - box_size.y * 0.5),
	]
	var chosen: Variant = null
	for candidate in candidates:
		var clamped := _clamp_into_area(candidate, box_size, available)
		if _choice_placement_ok(Rect2(clamped, box_size), cell_rect, selected_rect, available):
			chosen = clamped
			break
	if chosen == null:
		# Degenerate layout: keep the first candidate inside the available area.
		chosen = _clamp_into_area(candidates[0], box_size, available)
	box.global_position = chosen


func _choice_placement_ok(rect: Rect2, cell_rect: Rect2, selected_rect: Variant, available: Rect2) -> bool:
	if not available.encloses(rect) or rect.intersects(cell_rect):
		return false
	# A null selected rect means no selected hero to keep clear.
	if selected_rect != null and rect.intersects(selected_rect):
		return false
	return true


func _choice_available_rect() -> Rect2:
	var area := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	if is_instance_valid(_footer):
		var top: float = _footer.get_global_rect().position.y
		if top > area.position.y:
			area.size.y = minf(area.size.y, top)
	var header_end := _header.get_global_rect().end.y
	if header_end < area.end.y:
		area.size.y -= header_end
		area.position.y = header_end
	return area


func _clamp_into_area(point: Vector2, box_size: Vector2, area: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, area.position.x, maxf(area.position.x, area.end.x - box_size.x)),
		clampf(point.y, area.position.y, maxf(area.position.y, area.end.y - box_size.y)))


func _cell_size_global() -> Vector2:
	var diagonal: Vector2 = _board.cell_center(Vector2i(1, 1)) - _board.cell_center(Vector2i(0, 0))
	return Vector2(absf(diagonal.x), absf(diagonal.y))


func _refresh_orders(rows: Array) -> void:
	if rows == _order_rows:
		return
	_order_rows = rows.duplicate(true)
	var incoming := rows.map(func(row: Dictionary) -> String: return row.hero_id)
	for hero in _order_widgets.keys():
		if hero not in incoming:
			for control: Control in [_order_widgets[hero].row, _order_widgets[hero].rule]:
				_order_entries.remove_child(control)
				control.queue_free()
			_order_widgets.erase(hero)
	for row: Dictionary in rows:
		var hero: String = row.hero_id
		if not _order_widgets.has(hero):
			_add_order(hero, row.hero_label)
		var widgets: Dictionary = _order_widgets[hero]
		var note: Label = widgets.note
		var detail: Label = widgets.detail
		var picker: OptionButton = widgets.picker
		note.text = row.hero_label
		detail.text = str(row.get("hp", "")) + (" · Overridden this round" if row.get("overridden", false) else "")
		var items: Array = row.get("choices", [])
		if items != widgets.choices:
			widgets.choices = items.duplicate(true)
			picker.clear()
			for item: Dictionary in items:
				picker.add_item(item.label)
			picker.add_separator()
			picker.add_item("Help (F1)", HELP_MENU_ID)
			_set_help_shortcut(picker.get_popup())
		picker.disabled = not row.get("enabled", true) or items.is_empty()
		widgets.selected_index = items.find_custom(func(item: Dictionary) -> bool: return item.id == row.order_id)
		picker.select(widgets.selected_index)
		picker.tooltip_text = "%s · %s\n%s" % [note.text, detail.text, picker.text]


func _add_order(hero: String, label: String) -> void:
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := StyleBoxLine.new()
	line.color = Color("#b58c59")
	rule.add_theme_stylebox_override("separator", line)
	_order_entries.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_order_entries.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	row.add_child(copy)
	var note := _label("", 16, PAPER_INK)
	copy.add_child(note)
	var detail := _label("", 13, PAPER_MUTED)
	copy.add_child(detail)
	var picker := OptionButton.new()
	picker.name = hero.to_pascal_case() + "Order"
	picker.accessibility_name = label + " standing order"
	picker.custom_minimum_size = Vector2(171, 33)
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.add_theme_constant_override("modulate_arrow", 1)
	picker.add_theme_constant_override("arrow_margin", 9)
	picker.add_theme_stylebox_override("normal", _surface(Color("#f9e6bf"), Color("#a5845b"), 10, 4))
	picker.add_theme_stylebox_override("hover", _surface(Color("#fff0cc"), Color("#925f37"), 10, 4))
	picker.add_theme_stylebox_override("pressed", _surface(Color("#eed5a5"), Color("#925f37"), 10, 4))
	picker.add_theme_stylebox_override("disabled", _surface(Color("#e7cfa5"), Color("#b39773"), 10, 4))
	picker.add_theme_stylebox_override("focus", _focus_outline(Color("#8f4d1e")))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		picker.add_theme_color_override(state, PAPER_INK)
	picker.add_theme_color_override("font_disabled_color", PAPER_MUTED)
	row.add_child(picker)
	var popup := picker.get_popup()
	popup.visibility_changed.connect(_battle_popup_visibility_changed.bind(popup))
	popup.window_input.connect(_popup_help_input.bind(picker, popup))
	var widgets := {"row": row, "rule": rule, "note": note, "detail": detail, "picker": picker,
		"choices": [], "selected_index": -1}
	_order_widgets[hero] = widgets
	picker.item_selected.connect(func(index: int) -> void:
		# OptionButton updates its display before delivering even a stale click.
		if not _battle_popup_accepts_selection(popup):
			picker.select(widgets.selected_index)
			return
		var items: Array = widgets.choices
		if index == items.size() + 1:
			picker.select(widgets.selected_index)
			help_from_popup_requested.emit(picker)
			return
		if index >= 0 and index < items.size():
			order_selected.emit(hero, str(items[index].id)))


func _layout_page() -> void:
	if not _built or not is_instance_valid(_forfeit_panel):
		return
	var width := size.x - EDGE * 2.0
	if minf(width, size.y - EDGE * 2.0) <= 0.0:
		return
	var margin := clampf(size.x * 0.034, 22.0, CONTENT_MARGIN)
	var content_width := maxf(0.0, size.x - margin * 2.0)
	var footer_top := size.y - EDGE - 11.0 - FOOTER_HEIGHT
	_rail_top = footer_top - 9.0
	var board_top := EDGE + 65.0
	if is_instance_valid(_practice_controls) and _practice_controls.visible:
		var practice_height := maxf(70.0, _practice_controls.get_combined_minimum_size().y)
		_practice_controls.position = Vector2(margin, board_top + 4.0)
		_practice_controls.size = Vector2(content_width, practice_height)
		board_top += practice_height + 8.0
	else:
		board_top += 26.0
	var arena := Rect2(Vector2(EDGE, board_top), Vector2(width, maxf(0.0, _rail_top - board_top - 2.0)))
	var board_extent := Vector2(_dimensions) * BridgeArt.TILE + BridgeArt.GUTTER * 2.0
	var region := arena
	if not _expanded.is_empty():
		var leaf_width := minf(content_width, LEAF_WIDTH)
		var leaf_x := size.x - margin - leaf_width
		var beside := Rect2(arena.position, Vector2(maxf(0.0, leaf_x - LEAF_GAP - arena.position.x),
			arena.size.y))
		var leaf_height := _orders_leaf_height(arena, beside, board_extent) if _expanded == "orders" else \
			minf(FORECAST_LEAF_HEIGHT, arena.size.y * 0.56)
		_leaf.size = Vector2(leaf_width, leaf_height)
		_leaf.position = Vector2(leaf_x, _rail_top - LEAF_RAIL_GAP - _leaf.size.y)
		# Pick the larger fit, not a fixed grid aspect or a presumed spare corner.
		var above := Rect2(arena.position, Vector2(arena.size.x,
			maxf(0.0, _leaf.position.y - LEAF_GAP - arena.position.y)))
		region = beside if _board_scale(beside, board_extent) >= _board_scale(above, board_extent) else above
	var fitted_scale := _board_scale(region, board_extent)
	var map_size := board_extent * fitted_scale
	_board_host.position = region.get_center() - map_size * 0.5
	_board_host.size = map_size
	_bleed.place(_board_host.get_rect())
	if fitted_scale > 0.0:
		var grid_start := (_board_host.position + BridgeArt.GUTTER * fitted_scale) / size
		var grid_end := (_board_host.get_rect().end - BridgeArt.GUTTER * fitted_scale) / size
		_scenery_registration.set_shader_parameter("aperture", Vector4(grid_start.x, grid_start.y, grid_end.x, grid_end.y))
		_scenery_registration.set_shader_parameter("board_scale_wings",
			_surround_behind_foreground and not _expanded.is_empty())
		var cell_width := BridgeArt.TILE.x * fitted_scale
		_scenery_registration.set_shader_parameter("right_fade", Vector2(
			(_board_host.get_rect().end.x + 0.05 * cell_width) / size.x,
			(_board_host.get_rect().end.x + 0.90 * cell_width) / size.x))
	_header.position = Vector2(margin, EDGE + 5.0)
	_header.size = Vector2(content_width, 57.0)
	_layout_header()
	var compact := content_width < 660.0
	var clear_width := maxf(_button_label_width(_clear, "Clear command"), _button_label_width(_clear, "Clear selection"))
	var scale := clampf((content_width - 32.0) / (383.0 + clear_width), 0.0, 1.0)
	_hero_picker.custom_minimum_size.x = (162.0 if compact else 188.0) * scale
	_orders.custom_minimum_size.x = (140.0 if compact else 152.0) * scale
	_forecast.custom_minimum_size.x = (88.0 if compact else 113.0) * scale
	_clear.custom_minimum_size.x = clear_width * scale
	_commit.custom_minimum_size.x = (155.0 if compact else 211.0) * scale
	_footer.position = Vector2(margin, footer_top)
	_footer.size = Vector2(content_width, FOOTER_HEIGHT)
	_forfeit_panel.custom_minimum_size.x = minf(FORFEIT_LEAF_WIDTH, content_width)
	_place_target_choices()
	_book.queue_redraw()


func _orders_leaf_height(arena: Rect2, beside: Rect2, board_extent: Vector2) -> float:
	var room := _rail_top - LEAF_RAIL_GAP - arena.position.y
	# A board that fits beside the leaf does not consume its vertical space.
	# Otherwise keep at least half the original board scale above the leaf.
	var minimum_scale := _board_scale(arena, board_extent) * 0.5
	if _board_scale(beside, board_extent) < minimum_scale:
		room -= LEAF_GAP + board_extent.y * minimum_scale
	var paper_padding := _leaf.get_theme_stylebox("panel").get_minimum_size().y
	var desired := paper_padding + _leaf_sheet.get_combined_minimum_size().y \
		+ _order_entries.get_combined_minimum_size().y
	return minf(ceilf(desired), maxf(0.0, room))


func _board_scale(region: Rect2, extent: Vector2) -> float:
	return minf(region.size.x / extent.x, region.size.y / extent.y)


func _layout_header() -> void:
	var width := _header.size.x
	var round_width := maxf(103.0, _round.get_theme_font("font").get_string_size(
		_round.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 2.0)
	var text_edge := width
	text_edge = maxf(0.0, text_edge - _help_utility_slot.custom_minimum_size.x)
	_help_utility_slot.position = Vector2(text_edge, 10.0)
	_help_utility_slot.size = _help_utility_slot.custom_minimum_size
	text_edge -= 12.0
	for button: Button in [_forfeit, _restart, _upgrades, _options]:
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
	var rail_width := width - EDGE * 2.0
	var rail_height := maxf(0.0, height - EDGE - _rail_top)
	var rail := Rect2(EDGE, _rail_top, rail_width, rail_height)
	_wash(canvas, rail, Color("#4b2d1e"), Color("#281910"))
	canvas.draw_line(rail.position, Vector2(rail.end.x, rail.position.y), Color("#c39453"), 2.0)
	var stitch := _rail_top + 4.0
	canvas.draw_dashed_line(Vector2(EDGE + 2, stitch), Vector2(width - EDGE - 2, stitch),
		Color("#9a694568"), 1.0, 3.0, true)
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


func _button(node_name: String, label: String) -> Button:
	var result := Button.new()
	result.name = node_name
	result.text = label
	result.focus_mode = Control.FOCUS_ALL
	result.custom_minimum_size.y = 41
	return result


func _style_rail_button(control: BaseButton, tab := false, primary := false) -> void:
	var dark := "#38271c"
	var hover := "#513927"
	var pressed := "#2a1b14"
	control.custom_minimum_size.y = 44 if not primary else 47
	control.add_theme_stylebox_override("normal", _sign("#e9b75f" if primary else dark, primary))
	control.add_theme_stylebox_override("hover", _sign("#ffd787" if primary else hover, primary))
	control.add_theme_stylebox_override("pressed", _sign("#f0d5a4" if tab else "#c68f46" if primary else pressed,
		tab or primary))
	control.add_theme_stylebox_override("hover_pressed", _sign("#f8e2b8" if tab else "#d39e52" if primary else hover,
		tab or primary))
	control.add_theme_stylebox_override("disabled", _surface(Color("#38291f"), Color("#79614a"), 12, 6))
	control.add_theme_stylebox_override("focus", _focus_outline(Color("#fff1cd"), 2.0))
	control.add_theme_color_override("font_disabled_color", Color("#c9b291"))
	if primary:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			control.add_theme_color_override(state, PAPER_INK)
	elif tab:
		for state in ["font_pressed_color", "font_hover_pressed_color"]:
			control.add_theme_color_override(state, PAPER_INK)


func _focus_outline(tint: Color, outset := 0.0) -> StyleBoxFlat:
	var focus := _surface(Color.TRANSPARENT, tint, 0, 0, 2)
	focus.draw_center = false
	focus.set_expand_margin_all(outset)
	return focus


func _sign(fill: String, light: bool) -> StyleBoxTexture:
	var image := Image.new()
	# Nine-slice keeps the clipped corners and fine incised line at one scale.
	image.load_svg_from_string("""
<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36">
  <path d="M6 1h24l5 5v24l-5 5H6l-5-5V6z" fill="%s" stroke="#22160e" stroke-width="2"/>
  <path d="M8 4h20l4 4v20l-4 4H8l-4-4V8z" fill="none" stroke="%s"/>
  <path d="M9 5h18l4 4M5 9v18" fill="none" stroke="#ffe1a1" stroke-opacity="%s"/>
</svg>
""" % [fill, "#966329" if light else "#be985e", ".85" if light else ".26"])
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
	result.icon = get_theme_icon("arrow", "OptionButton")
	result.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	result.add_theme_constant_override("h_separation", 9)
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
	for checked in [false, true]:
		var mark := '<path d="M3 7l3 3 5-6" fill="none" stroke="#fff0cc" stroke-width="2"/>' if checked else ""
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><rect x="1" y="1" width="12" height="12" rx="2" fill="#38271b" stroke="#f2d6a4" stroke-width="1.5"/>%s</svg>' % mark
		var image := Image.new()
		if image.load_svg_from_string(svg) == OK:
			skin.set_icon("checked" if checked else "unchecked", "PopupMenu", ImageTexture.create_from_image(image))
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
