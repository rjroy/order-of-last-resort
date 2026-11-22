extends Control
## A separate battle view, using the shared board and emitting only player intent.

signal action_selected(ability_id: String)
signal order_selected(hero_id: String, order_id: String)
signal target_selected(target_id: String)
signal clear_requested
signal commit_requested
signal restart_requested

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
var _upgrade_dialog: AcceptDialog
var _upgrade_text: Label
var _summary: Label
var _inspection: Label
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
	if _round.text != round_label:
		_round.text = round_label
		_layout_header()
	_restart.visible = view.get("can_restart", true)
	_upgrade_text.text = view.get("upgrades_text", "")
	_upgrades.visible = not _restart.visible and not _upgrade_text.text.is_empty()
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


func render_ink(cues: Dictionary) -> void:
	if is_instance_valid(_ink):
		_ink.render(cues)


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

	_bleed = Surround.new()
	add_child(_bleed)
	_bleed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_host = Control.new()
	_board_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_host)
	_scenery = TextureRect.new()
	_scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scenery)
	_scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The leaf edge, shaded margins, and separating rules sit above the painting,
	# but never take input from the mounted board or the controls.
	var book := Control.new()
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.draw.connect(_draw_book.bind(book))
	add_child(book)
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(book.queue_redraw)
	_build_header()
	_build_footer()
	_build_leaf()


func _build_header() -> void:
	_header = Control.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)
	_title = _label("", 36, PARCHMENT, true)
	_header.add_child(_title)
	_round = _label("", 19, GOLD, true)
	_header.add_child(_round)
	_objective = _label("", 15, PARCHMENT)
	_header.add_child(_objective)
	_restart = _button("Restart", "Restart mission")
	_header.add_child(_restart)
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	_upgrades = _button("ShowLoadout", "Outing upgrades")
	_header.add_child(_upgrades)
	_upgrades.hide()
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
		_upgrade_dialog.popup_centered(Vector2i(540, 310))
		scroll.grab_focus())
	_upgrade_dialog.visibility_changed.connect(func() -> void:
		if not _upgrade_dialog.visible and _upgrades.is_visible_in_tree():
			_upgrades.grab_focus())


func _build_footer() -> void:
	_footer = VBoxContainer.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_theme_constant_override("separation", 4)
	add_child(_footer)
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
	var controls := HBoxContainer.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_theme_constant_override("separation", 8)
	_footer.add_child(controls)
	_actions = _menu("Actions", "Actions")
	controls.add_child(_actions)
	_actions.get_popup().id_pressed.connect(func(index: int) -> void:
		if index >= 0 and index < _action_rows.size():
			action_selected.emit(str(_action_rows[index].id)))
	_targets = _menu("Targets", "Choose target")
	_targets.hide()
	controls.add_child(_targets)
	_targets.get_popup().id_pressed.connect(func(index: int) -> void:
		if index >= 0 and index < _target_rows.size():
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
	_clear.pressed.connect(func() -> void: clear_requested.emit())
	_commit = _button("Commit", "Commit round 1", true)
	_commit.custom_minimum_size.x = 182
	controls.add_child(_commit)
	_commit.pressed.connect(func() -> void: commit_requested.emit())


func _build_leaf() -> void:
	_leaf = PanelContainer.new()
	_leaf.name = "ExtraDetails"
	_leaf.z_index = 5
	_leaf.mouse_filter = Control.MOUSE_FILTER_STOP
	_leaf.add_theme_stylebox_override("panel", _surface(Color("#2f2218"), Color("#c59857"), 12, 12))
	add_child(_leaf)
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
	_expanded = "" if _expanded == section else section
	_orders.set_pressed_no_signal(_expanded == "orders")
	_forecast.set_pressed_no_signal(_expanded == "forecast")
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
	if not _expanded.is_empty() and event.is_action_pressed("ui_cancel"):
		var source := _orders if _expanded == "orders" else _forecast
		var focused := get_viewport().gui_get_focus_owner()
		if focused == source or (focused != null and _leaf.is_ancestor_of(focused)):
			_toggle_leaf(_expanded)
			source.grab_focus()
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
		picker.select(items.find_custom(func(item: Dictionary) -> bool: return item.id == row.order_id))


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
	_order_widgets[hero] = {"row": row, "note": note, "picker": picker, "choices": []}
	picker.item_selected.connect(func(index: int) -> void:
		var items: Array = _order_widgets[hero].choices
		if index >= 0 and index < items.size():
			order_selected.emit(hero, str(items[index].id)))


func _layout_page() -> void:
	if not _built or not is_instance_valid(_footer) or not is_instance_valid(_leaf):
		return
	var width := size.x - EDGE * 2.0
	var height := size.y - EDGE * 2.0
	if minf(width, height) <= 0.0:
		return
	var margin := EDGE + 26.0
	var content_width := size.x - margin * 2.0
	var footer_top := size.y - EDGE - 83.0
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
	_footer.size = Vector2(content_width, 72.0)
	var leaf_height := 210.0 if _expanded == "orders" else 242.0
	_leaf.position = Vector2(margin, footer_top - leaf_height - 5.0)
	_leaf.size = Vector2(minf(maxf(content_width, 0), 510.0), leaf_height)


func _layout_header() -> void:
	var width := _header.size.x
	var round_width := maxf(103.0, _round.get_theme_font("font").get_string_size(
		_round.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 2.0)
	_title.size = Vector2(maxf(0.0, width - 154.0), 44.0)
	_round.position = Vector2(0, 39.0)
	_round.size = Vector2(round_width, 22.0)
	_objective.position = Vector2(round_width + 4.0, 41.0)
	_objective.size = Vector2(maxf(0.0, width - 158.0 - _objective.position.x), 24.0)
	_restart.position = Vector2(maxf(0.0, width - 141.0), 10.0)
	_restart.size = Vector2(141.0, 39.0)
	_upgrades.position = Vector2(maxf(0.0, width - 150.0), 10.0)
	_upgrades.size = Vector2(150.0, 39.0)


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
