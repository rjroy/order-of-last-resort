extends Control

const Rules = preload("res://rules.gd")
const BridgeArt = preload("res://bridge_art.gd")
const Catalog = preload("res://content/catalog.gd")
const DEFAULT_MISSION := "ferryman"

const PAPER := Color("#f1dfb8")
const MUTED := Color("#c0c7ad")
const TEAL := Color("#263c3a")
const LINE := Color("#536353")
const GOLD := Color("#e3b970")
const MINT := Color("#cae1b6")
const RUST := Color("#f0b495")
const DARK_TEXT := Color("#2f281e")

const MODES := {
	"hybrid": {"name": "Hybrid", "text": "Give one hero a direct command each round."},
	"direct": {"name": "Direct", "text": "Give each hero a direct command each round."},
	"standing": {"name": "Standing", "text": "The heroes follow their standing orders."}
}

var _rules = Rules.new()
var _opening_state: Dictionary
var _state: Dictionary
# These drafts are a UI affordance. Only the engine can reserve an actual slot.
var _drafts: Dictionary = {}
var _planned_state: Dictionary
var _plan: Dictionary
var _editor_actor: Dictionary
var _editor_can_act := false
var _last_events: Array = []
var _last_round := 0
var _unpreviewed_edit := false
var _actor_id := ""
var _ability_id := ""
var _target_id := ""
var _targets: Array = []
var _modes: Dictionary = {}
var _orders: Dictionary = {}
var _order_notes: Dictionary = {}
var _painted_cells: Dictionary = {}
var _tile_labels: Dictionary = {}
var _safe_cells: Dictionary = {}
var _hover_cell: Variant = null

var _display_font: SystemFont
var _board: BridgeArt
var _actor_select: OptionButton
var _ability_select: OptionButton
var _target_select: OptionButton
var _preview_button: Button
var _clear_button: Button
var _commit_button: Button
var _status: Label
var _mission_title: Label
var _round_text: Label
var _objective: Label
var _hover_text: Label
var _command_note: Label
var _action_help: Label
var _forecast: RichTextLabel
var _last_title: Label
var _last_result: RichTextLabel
var _order_grid: GridContainer


func _ready() -> void:
	_make_theme()
	var launch := _read_launch_options(OS.get_cmdline_user_args())
	if launch.has("error"):
		_show_launch_error(launch.error)
		return
	var mission_id: String = launch.mission
	var path: String = launch.content if not launch.content.is_empty() else Catalog.DEFAULT_PATH
	var content := Catalog.read_source(path)
	if content.has("error"):
		_show_launch_error(content.error)
		return
	var definitions: Dictionary = content.definitions
	if not definitions.missions.has(mission_id):
		_show_launch_error("No mission named \"%s\". Available missions: %s." % [
			mission_id, ", ".join(definitions.missions.keys())])
		return
	_opening_state = _rules.new_game("hybrid", definitions, mission_id)
	if _opening_state.is_empty():
		_show_launch_error("The mission \"%s\" could not be set up. Check the content file." % mission_id)
		return
	_state = _rules.start_in_mode(_opening_state, "hybrid")
	_build_ui()
	_begin_attempt()


func _read_launch_options(args: PackedStringArray) -> Dictionary:
	var launch := {"content": "", "mission": DEFAULT_MISSION}
	var seen: Dictionary = {}
	for arg in args:
		var key := arg.get_slice("=", 0).trim_prefix("--")
		if not arg.begins_with("--") or not launch.has(key):
			continue
		var value := arg.substr(arg.find("=") + 1) if "=" in arg else ""
		if value.strip_edges().is_empty() or seen.has(key):
			return {"error": "Use --%s=<value> once, with a nonempty value." % key}
		launch[key] = value
		seen[key] = true
	return launch


func _show_launch_error(message: String) -> void:
	printerr("Could not start the game: " + message)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	var padding := MarginContainer.new()
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 34)
	add_child(padding)
	var page := _stack(padding, 12)
	_label(page, "Could not start the game", 29, PAPER, true)
	_label(page, "Check your launch options and try again.", 14, MUTED)
	var detail := _log(page, "LaunchErrorText", 72, true)
	detail.bbcode_enabled = false
	detail.add_theme_color_override("default_color", RUST)
	detail.text = message


func _build_ui() -> void:
	var padding := MarginContainer.new()
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		padding.add_theme_constant_override("margin_" + side, 34)
	for side in ["top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 22)
	add_child(padding)
	var page := _stack(padding, 13)
	_build_masthead(page)
	_rule(page)
	var columns := _row(page, 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var map_column := _stack(columns, 9)
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_map(map_column)
	_build_orders(map_column)
	_build_desk(columns)


func _build_masthead(parent: Control) -> void:
	var head := _row(parent, 16)
	var titles := _stack(head, 4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(titles, "The Company of Unlikely Heroes", 39, PAPER, true)
	_status = _label(titles, "", 14, MUTED)
	_status.name = "StatusText"
	var controls := _stack(head, 6)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	var buttons := _row(controls, 6)
	var names := {"hybrid": "ModeHybrid", "direct": "ModeDirect", "standing": "ModeStanding"}
	for mode in MODES:
		var button := _button(buttons, names[mode], MODES[mode].name)
		button.toggle_mode = true
		button.custom_minimum_size.x = 73
		button.tooltip_text = MODES[mode].text + " Changing mode restarts the rescue."
		button.pressed.connect(_switch_mode.bind(mode))
		_modes[mode] = button
	var restart := _button(buttons, "Restart", "Restart")
	restart.tooltip_text = "Start the rescue again in the current mode."
	restart.pressed.connect(func() -> void: _reset(_state.mode))


func _build_map(parent: VBoxContainer) -> void:
	var header := _row(parent, 8)
	_mission_title = _label(header, "", 29, PAPER, true)
	_mission_title.name = "MissionTitle"
	_mission_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_round_text = _label(header, "", 16, GOLD)
	_round_text.name = "RoundText"
	_round_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_objective = _label(parent, "", 14, MUTED)
	_objective.name = "ObjectiveText"
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board = BridgeArt.new()
	_board.name = "BridgeBoard"
	_board.custom_minimum_size.y = 405
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_board)
	_board.cell_selected.connect(_select_board)
	_board.cell_hovered.connect(_inspect_board)
	_board.hover_cleared.connect(_clear_inspection)
	var key := _row(parent, 14)
	_legend_key(key, "safe", "Safe bank", Color("#a0a67a"))
	_legend_key(key, "broken", "Bridge gap", Color("#5c918e"))
	_legend_key(key, "obstacle", "Blocked", Color("#b38b60"))
	_legend_key(key, "target", "Target", MINT)
	_legend_key(key, "impact", "Net HP loss", RUST)
	_legend_key(key, "path", "Forecast end", GOLD)
	_hover_text = _label(key, "", 13, PAPER)
	_hover_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hover_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hover_text.clip_text = true


func _build_orders(parent: VBoxContainer) -> void:
	_rule(parent)
	var heading := _row(parent, 12)
	_label(heading, "Standing orders", 22, PAPER, true)
	var note := _label(heading, "These stay in place between rounds.", 13, MUTED)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	_order_grid = GridContainer.new()
	_order_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order_grid.add_theme_constant_override("h_separation", 10)
	scroll.add_child(_order_grid)


func _sync_order_controls() -> void:
	var roster := _roster()
	var ids := roster.map(func(unit: Dictionary) -> String: return unit.id)
	if _orders.keys() == ids:
		return
	for control in _order_grid.get_children():
		_order_grid.remove_child(control)
		control.queue_free()
	_orders.clear()
	_order_notes.clear()
	_order_grid.columns = clampi(roster.size(), 1, 3)
	for unit in roster:
		var id: String = unit.id
		var profile: Dictionary = _rules.entity_profile(_state, id)
		var order := _stack(_order_grid, 4)
		order.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := _row(order, 5)
		var label := _label(head, _name_for(id), 14, Color.from_string(profile.get("color", ""), PAPER))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = label.text
		_order_notes[id] = _label(head, "", 12, MUTED)
		var picker := _picker(order, id.to_pascal_case() + "Order")
		picker.set_meta("actor_id", id)
		picker.tooltip_text = "Choose what %s does unless directly commanded." % label.text
		picker.item_selected.connect(_select_order.bind(id))
		_orders[id] = picker
	var visible_rows := clampi(ceili(roster.size() / 3.0), 1, 2)
	var first_order := _order_grid.get_child(0) as Control if not roster.is_empty() else null
	var row_height := first_order.get_combined_minimum_size().y if first_order != null else 0.0
	var scroll := _order_grid.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = row_height * visible_rows + _order_grid.get_theme_constant("v_separation") * (visible_rows - 1)


func _build_desk(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 423
	panel.add_theme_stylebox_override("panel", _box(Color("#1d302e"), LINE, 1, 0, 15, 12))
	parent.add_child(panel)
	var desk := _stack(panel, 8)
	var header := _row(desk, 10)
	var title := _label(header, "Direct command", 24, PAPER, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_note = _label(header, "", 13, GOLD)
	_command_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var selection := _row(desk, 8)
	var who := _stack(selection, 3)
	who.custom_minimum_size.x = 112
	_label(who, "Hero", 13, MUTED)
	_actor_select = _picker(who, "ActorSelect")
	_actor_select.item_selected.connect(_select_actor)
	var what := _stack(selection, 3)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(what, "Action", 13, MUTED)
	_ability_select = _picker(what, "AbilitySelect")
	_ability_select.item_selected.connect(_select_ability)
	var target := _stack(desk, 3)
	_label(target, "Target", 13, MUTED)
	_target_select = _picker(target, "TargetSelect")
	_target_select.item_selected.connect(_select_target)
	_action_help = _label(desk, "", 13, MUTED)
	_action_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_help.custom_minimum_size.y = 34
	_action_help.max_lines_visible = 2
	var draft_controls := _row(desk, 8)
	_preview_button = _button(draft_controls, "Preview", "Preview command")
	_preview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_button.pressed.connect(_stage_command)
	_clear_button = _button(draft_controls, "ClearCommand", "Clear command")
	_clear_button.pressed.connect(_clear_command)
	_rule(desk)
	var heading := _row(desk, 8)
	var forecast_title := _label(heading, "Round forecast", 24, PAPER, true)
	forecast_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint := _label(heading, "In execution order", 13, MUTED)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_forecast = _log(desk, "PreviewText", 142, true)
	_last_title = _label(desk, "Last round", 18, PAPER, true)
	_last_result = _log(desk, "LastResult", 63)
	_commit_button = _button(desk, "Commit", "Commit round")
	_commit_button.custom_minimum_size.y = 43
	_commit_button.theme_type_variation = &"CommitButton"
	_commit_button.pressed.connect(_commit)


func _reset(mode: String) -> void:
	_state = _rules.start_in_mode(_opening_state, mode)
	_begin_attempt()


func _begin_attempt() -> void:
	_drafts.clear()
	_last_events.clear()
	_last_round = 0
	_unpreviewed_edit = false
	_actor_id = ""
	_sync_actors()
	_sync_command()
	_refresh(true)


func _switch_mode(mode: String) -> void:
	if mode != _state.mode:
		_reset(mode)
	else:
		_modes[mode].set_pressed_no_signal(true)


func _sync_actors() -> void:
	_actor_select.clear()
	var roster := _roster()
	for unit in roster:
		_add_choice(_actor_select, _name_for(unit.id), unit.id)
		_actor_select.set_item_disabled(_actor_select.item_count - 1, unit.hp <= 0)
	var current := _find(_actor_id)
	if current.is_empty() or current.hp <= 0:
		_actor_id = ""
		for unit in roster:
			if unit.hp > 0:
				_actor_id = unit.id
				break
	_pick(_actor_select, _actor_id)


func _sync_command() -> void:
	_ability_select.clear()
	for choice in _rules.options(_state, _actor_id):
		if choice.kind == "action":
			_add_choice(_ability_select, choice.label, choice.id)
	var draft: Dictionary = _drafts.get(_actor_id, {})
	_pick(_ability_select, draft.get("ability_id", ""))
	_ability_id = _picked(_ability_select)
	_target_id = draft.get("target_id", "")


func _sync_targets(auto_pick: bool) -> void:
	# In Hybrid, previewing the selected hero will replace another hero's draft.
	var editor_plan := _planned_state
	if _state.mode == "hybrid" and not _drafts.has(_actor_id):
		editor_plan = _state
	var context := _rules.state_before_action(editor_plan, _actor_id)
	_editor_actor = _find(_actor_id, context)
	_editor_can_act = _rules.can_act(context, _actor_id)
	_target_select.clear()
	var target_kind := _target_kind()
	var selectable := _is_selectable(target_kind)
	_targets = _rules.targets(context, _actor_id, _ability_id) if selectable and _editor_can_act else []
	var selected_exists := false
	for choice in _targets:
		var location := BridgeArt.coordinate(choice.position)
		var label := location if target_kind == "cell" else "%s  ·  %s" % [_name_for(choice.id), location]
		_add_choice(_target_select, label, choice.id)
		selected_exists = selected_exists or choice.id == _target_id
	if _targets.is_empty():
		var prompt := "No target needed"
		if _actor_id.is_empty():
			prompt = "No hero available"
		elif _ability_id.is_empty():
			prompt = "No action available"
		elif selectable:
			prompt = "No legal targets"
		elif target_kind == "automatic":
			prompt = "Automatic"
		_add_choice(_target_select, prompt, "")
	elif not selected_exists and (not auto_pick or not _target_id.is_empty()):
		_add_choice(_target_select, "Choose a target", "")
		_target_select.set_item_disabled(_target_select.item_count - 1, true)
	_pick(_target_select, _target_id if selected_exists else "")
	_target_id = _picked(_target_select)


func _select_actor(index: int) -> void:
	if _actor_select.is_item_disabled(index):
		return
	_actor_id = str(_actor_select.get_item_metadata(index))
	_unpreviewed_edit = false
	_sync_command()
	_refresh(true)


func _select_ability(index: int) -> void:
	_ability_id = str(_ability_select.get_item_metadata(index))
	_target_id = ""
	_unpreviewed_edit = true
	_refresh(true)


func _select_target(index: int) -> void:
	_target_id = str(_target_select.get_item_metadata(index))
	_note_unpreviewed_edit()
	_refresh()


func _select_order(index: int, hero: String) -> void:
	var order_id := str(_orders[hero].get_item_metadata(index))
	_state = _rules.set_order(_state, hero, order_id)
	_refresh()


func _stage_command() -> void:
	if not _can_stage_command():
		_refresh()
		return
	if _state.mode == "hybrid":
		_drafts.clear()
	_drafts[_actor_id] = {"ability_id": _ability_id, "target_id": _target_id}
	_unpreviewed_edit = false
	_refresh()


func _note_unpreviewed_edit() -> void:
	var previous: Dictionary = _drafts.get(_actor_id, {})
	_unpreviewed_edit = previous.get("ability_id", "") != _ability_id \
		or previous.get("target_id", "") != _target_id


func _clear_command() -> void:
	_drafts.erase(_actor_id)
	_unpreviewed_edit = false
	_refresh()


func _ready_to_command() -> bool:
	return not _actor_id.is_empty() and not _ability_id.is_empty() \
		and (not _is_selectable(_target_kind()) or not _target_id.is_empty())


func _target_kind(ability := "") -> String:
	if ability.is_empty():
		ability = _ability_id
	return _rules.ability_definition(_state, ability).get("targeting", {}).get("kind", "")


func _is_selectable(target_kind: String) -> bool:
	return target_kind == "cell" or target_kind == "entity"


func _can_stage_command() -> bool:
	var has_slot: bool = _state.mode == "hybrid" or _drafts.has(_actor_id) \
		or _planned_state.manual_remaining > 0
	return _ongoing() and _state.mode != "standing" and _ready_to_command() \
		and _editor_can_act and has_slot


func _commit() -> void:
	if not _ongoing() or not _plan.get("valid", false):
		return
	_last_round = _state.round
	_last_events = _plan.events.duplicate(true)
	_state = _rules.commit_round(_planned_state, _plan)
	_drafts.clear()
	_unpreviewed_edit = false
	_sync_actors()
	_sync_command()
	_refresh(true)


func _refresh(auto_pick_target := false) -> void:
	_planned_state = _state
	for hero in _drafts:
		var draft: Dictionary = _drafts[hero]
		_planned_state = _rules.choose_manual(_planned_state, hero, draft.ability_id, draft.target_id)
	_plan = _rules.preview_round(_planned_state)
	_sync_targets(auto_pick_target)
	if _unpreviewed_edit:
		_note_unpreviewed_edit()
	var active := _ongoing()
	var manual: bool = active and _state.mode != "standing" and not _actor_id.is_empty()
	for mode in _modes:
		_modes[mode].set_pressed_no_signal(mode == _state.mode)
	_status.text = "%s  ·  %s" % [MODES[_state.mode].name, MODES[_state.mode].text]
	_refresh_objective()
	_command_note.text = "%d direct slot%s left" % [_planned_state.manual_remaining, "" if _planned_state.manual_remaining == 1 else "s"]
	if _state.mode == "standing":
		_command_note.text = "Standing orders only"
	elif not active:
		_command_note.text = "Rescue ended"
	_actor_select.disabled = not manual
	_ability_select.disabled = not manual or _ability_select.item_count == 0
	_target_select.disabled = not manual or _targets.is_empty()
	_preview_button.disabled = not _can_stage_command()
	_preview_button.text = "Preview changes" if _unpreviewed_edit else "Preview command"
	_clear_button.disabled = not manual or not _drafts.has(_actor_id)
	_commit_button.disabled = not active or not _plan.get("valid", false)
	_commit_button.text = "Commit round %d" % _state.round if active else "Rescue complete" if _state.outcome == "victory" else "Rescue failed"
	_action_help.text = _rules.ability_definition(_state, _ability_id).get("help", "")
	if _is_selectable(_target_kind()) and _targets.is_empty() and manual:
		_action_help.text = "No legal target when this hero acts."
	if manual and _editor_actor.get("hp", 0) > 0 and not _editor_can_act:
		_action_help.text = "This hero must get up and cannot act this round."
	elif manual and not _editor_can_act:
		_action_help.text = "This hero falls before their turn."
	if _state.mode == "standing":
		_action_help.text = "Change standing orders below the map to revise the forecast."
	elif not active:
		_action_help.text = "Restart to try another rescue."
	_action_help.tooltip_text = _action_help.text
	_refresh_orders(active)
	_refresh_forecast()
	_refresh_board()


func _refresh_objective() -> void:
	var mission: Dictionary = _rules.mission_definition(_state)
	var objective: Dictionary = mission.objective
	var subject := _find(_state.objective.subject)
	var destination := BridgeArt.coordinate(_state.objective.destination)
	var deadline: int = _rules.deadline(_state)
	_mission_title.text = mission.title
	_mission_title.tooltip_text = mission.title
	_round_text.text = "Round %d / %d" % [_state.round, deadline]
	var text_key: String = "text" if _ongoing() else _state.outcome + "_text"
	var subject_label := _name_for(subject.id)
	_objective.text = str(objective[text_key]).format({
		"subject": subject_label.to_lower(),
		"subject_label": subject_label,
		"destination": destination,
		"hp": subject.hp,
		"max_hp": subject.max_hp,
		"position": BridgeArt.coordinate(subject.position),
		"deadline": deadline,
	})


func _refresh_orders(active: bool) -> void:
	_sync_order_controls()
	for hero in _orders:
		var picker: OptionButton = _orders[hero]
		picker.clear()
		for choice in _rules.options(_state, hero):
			if choice.kind == "order":
				_add_choice(picker, choice.label, choice.id)
		_pick(picker, _state.orders.get(hero, ""))
		var unit := _find(hero)
		picker.disabled = not active or unit.get("hp", 0) <= 0 or picker.item_count == 0
		var note: Label = _order_notes[hero]
		note.text = "Down" if _rules.has_status_handler(_state, hero, "skip_action") else ""
		if unit.get("hp", 0) <= 0:
			note.text = "Fallen"
		elif _drafts.has(hero):
			note.text = "Direct this round"
		note.add_theme_color_override("font_color", GOLD if _drafts.has(hero) else MUTED)


func _refresh_forecast() -> void:
	if not _ongoing():
		_forecast.text = "[color=#e3b970][b]%s[/b][/color]\n%s" % [
			_escape_log_text(_objective.text),
			"Restart or change mode for another attempt."]
	else:
		var command_lines: PackedStringArray = []
		for hero in _drafts:
			var draft: Dictionary = _drafts[hero]
			var action: String = _rules.ability_definition(_state, draft.ability_id).label
			var target := _target_description(hero, draft.ability_id, draft.target_id)
			command_lines.append("%s: %s%s" % [_name_for(hero), action, target])
		var summary := "No direct commands queued." if command_lines.is_empty() else "  ·  ".join(command_lines)
		var unpreviewed := "\n[color=#f0b495]Command edits are not in this forecast yet.[/color]" if _unpreviewed_edit and _can_stage_command() else ""
		_forecast.text = "[color=#e3b970][b]%s[/b][/color]%s\n%s" % [_escape_log_text(summary), unpreviewed, _event_lines(_plan.events)]
	_forecast.scroll_to_line(0)
	_last_title.text = "Last round" if _last_round == 0 else "Round %d result" % _last_round
	_last_result.text = "[color=#c0c7ad]Nothing resolved yet.[/color]" if _last_events.is_empty() else _last_report()
	_last_result.scroll_to_line(0)


func _last_report() -> String:
	var losses: PackedStringArray = []
	for event in _last_events:
		if event.type == "damage":
			losses.append("%s −%d HP" % [_name_for(event.target_id), event.amount])
	var cost := "[color=#f0b495][b]%s[/b][/color]" % _escape_log_text("  ·  ".join(losses)) if not losses.is_empty() \
		else "[color=#cae1b6]No damage taken or dealt.[/color]"
	return cost + "\n" + _event_lines(_last_events)


func _event_lines(events: Array) -> String:
	if events.is_empty():
		return "No actions predicted."
	var lines: PackedStringArray = []
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var ink := "#f0b495" if event.type in ["damage", "defeat"] else ("#cae1b6" if event.type in ["heal", "victory"] else "#f1dfb8")
		lines.append("[color=#9ba792]%02d[/color]  [color=%s]%s[/color]" % [
			index + 1, ink, _escape_log_text(event.text)])
	return "\n".join(lines)


func _escape_log_text(text: String) -> String:
	return text.replace("[", "[lb]")


func _target_description(hero: String, ability: String, target: String) -> String:
	if target.is_empty():
		return ""
	var context := _rules.state_before_action(_planned_state, hero)
	for choice in _rules.targets(context, hero, ability):
		if choice.id == target:
			var location := BridgeArt.coordinate(choice.position)
			return " to " + location if _target_kind(ability) == "cell" else " → %s at %s" % [_name_for(target), location]
	return " (target no longer legal)"


func _refresh_board() -> void:
	_painted_cells = _terrain()
	var units: Array = []
	for unit in _state.units:
		var is_objective: bool = unit.id == _state.objective.subject
		if unit.hp <= 0 and not is_objective:
			continue
		var profile: Dictionary = _rules.entity_profile(_state, unit.id)
		units.append({"id": unit.id, "art_key": profile.art_key, "variant": profile.get("art_variant", ""),
			"cell": unit.position, "hp": unit.hp, "max_hp": unit.max_hp, "objective": is_objective,
			"prone": unit.hp <= 0 or _rules.has_status_handler(_state, unit.id, "skip_action"),
			"guarded": _rules.has_status_handler(_state, unit.id, "reflect")})
	var overlay := {"exit": _state.objective.destination, "safe": _safe_cells, "obstacles": []}
	for obstacle in _state.obstacles:
		if obstacle.hp <= 0:
			continue
		overlay.obstacles.append({"id": obstacle.id, "position": obstacle.position,
			"hp": obstacle.hp, "max_hp": obstacle.max_hp,
			"art_key": _rules.entity_profile(_state, obstacle.id).art_key})
	if _ongoing():
		if _state.mode != "standing" and not _actor_id.is_empty():
			var selected := _find(_actor_id)
			overlay["selected"] = selected.position
			if _editor_can_act:
				var positions: Array = []
				for target in _targets:
					positions.append(target.position)
					if _target_id == target.id:
						overlay["chosen_target"] = target.position
				overlay["targets"] = positions
		var hits: Array = []
		var paths: Array = []
		for entity in _state.units + _state.obstacles:
			var predicted := _find(entity.id, _plan.result)
			if predicted.is_empty():
				continue
			if predicted.hp < entity.hp:
				hits.append(entity.position)
			if predicted.position != entity.position:
				paths.append([entity.position, predicted.position])
		overlay["impact"] = hits
		overlay["paths"] = paths
	_board.set_render_state(_painted_cells, units, overlay)
	if _hover_cell != null:
		_inspect_board(_hover_cell)


func _terrain() -> Dictionary:
	var cells: Dictionary = {}
	_tile_labels.clear()
	_safe_cells.clear()
	var tile_defs: Dictionary = _rules.definitions(_state).tiles
	var default_tile: Dictionary = tile_defs[_state.default_tile]
	for y in range(_state.height):
		for x in range(_state.width):
			var cell := Vector2i(x, y)
			cells[cell] = default_tile.art_key
			_tile_labels[cell] = default_tile.label
	for tile in _state.terrain:
		var definition: Dictionary = tile_defs[tile.type]
		cells[tile.position] = definition.art_key
		_tile_labels[tile.position] = definition.label
	var destination: Vector2i = _state.objective.destination
	var eligible: Dictionary = {}
	var board: Dictionary = _rules.definitions(_state).boards[_state.board_id]
	for at in board.get("shore_cells", []):
		eligible[Vector2i(int(at[0]), int(at[1]))] = true
	if eligible.has(destination):
		_highlight_safe_bank(eligible, destination)
	return cells


func _highlight_safe_bank(eligible: Dictionary, destination: Vector2i) -> void:
	var shore := [destination]
	_safe_cells[destination] = true
	var index := 0
	while index < shore.size():
		var at: Vector2i = shore[index]
		index += 1
		for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + direction
			if eligible.has(next) and not _safe_cells.has(next):
				_safe_cells[next] = true
				shore.append(next)


func _select_board(cell: Vector2i) -> void:
	if not _ongoing() or _state.mode == "standing":
		return
	for target in _targets:
		if target.position == cell:
			_pick(_target_select, target.id)
			_target_id = target.id
			_note_unpreviewed_edit()
			_refresh()
			return
	for unit in _roster():
		if unit.position == cell and unit.hp > 0:
			_pick(_actor_select, unit.id)
			_select_actor(_actor_select.selected)
			return


func _inspect_board(cell: Vector2i) -> void:
	_hover_cell = cell
	var place := BridgeArt.coordinate(cell)
	if _ongoing() and _state.mode != "standing":
		var target_kind := _target_kind()
		for target in _targets:
			if target.position == cell:
				var target_name := "Move destination" if target_kind == "cell" else _name_for(target.id) + " target"
				_hover_text.text = "%s  ·  %s when %s acts" % [place, target_name, _name_for(_actor_id)]
				_board.tooltip_text = _hover_text.text
				return
	for unit in _state.units:
		if unit.position == cell and unit.hp > 0:
			_hover_text.text = "%s  ·  %s  %d/%d HP" % [place, _name_for(unit.id), unit.hp, unit.max_hp]
			_board.tooltip_text = _hover_text.text
			return
	for obstacle in _state.obstacles:
		if obstacle.position == cell and obstacle.hp > 0:
			_hover_text.text = "%s  ·  %s  %d/%d HP" % [place, _name_for(obstacle.id), obstacle.hp, obstacle.max_hp]
			_board.tooltip_text = _hover_text.text
			return
	var label: String = _tile_labels.get(cell, "")
	if cell == _state.objective.destination:
		var destination := _presentation("exit", "Destination")
		label = destination if _safe_cells.has(cell) else "%s  ·  %s" % [label, destination]
	elif _safe_cells.has(cell):
		label = _presentation("safe", label)
	_hover_text.text = "%s  ·  %s" % [place, label]
	_board.tooltip_text = _hover_text.text


func _clear_inspection() -> void:
	_hover_cell = null
	_hover_text.text = ""
	_board.tooltip_text = ""


func _ongoing() -> bool:
	return _state.outcome == "ongoing"


func _find(id: String, source: Dictionary = {}) -> Dictionary:
	if source.is_empty():
		source = _state
	for entity in source.units + source.obstacles:
		if entity.id == id:
			return entity
	return {}


func _roster() -> Array:
	return _state.units.filter(func(unit: Dictionary) -> bool:
		return _rules.has_capability(_state, unit.id, "commandable"))


func _name_for(id: String) -> String:
	return _rules.display_name(_state, id)


func _make_theme() -> void:
	_display_font = SystemFont.new()
	_display_font.font_names = PackedStringArray(["Noto Serif Display", "Georgia", "Nimbus Roman", "Liberation Serif"])
	_display_font.font_weight = 600
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Noto Sans", "Segoe UI", "Liberation Sans"])
	var skin := Theme.new()
	skin.default_font = body
	skin.default_font_size = 14
	for kind in ["Button", "OptionButton"]:
		skin.set_stylebox("normal", kind, _box(TEAL, LINE))
		skin.set_stylebox("hover", kind, _box(Color("#354a42"), Color("#829277")))
		skin.set_stylebox("pressed", kind, _box(GOLD, GOLD))
		skin.set_stylebox("disabled", kind, _box(Color("#202d2a"), Color("#394942")))
		skin.set_stylebox("focus", kind, _focus_box())
		skin.set_color("font_color", kind, PAPER)
		skin.set_color("font_hover_color", kind, PAPER)
		skin.set_color("font_pressed_color", kind, DARK_TEXT)
		skin.set_color("font_disabled_color", kind, Color("#85918a"))
	skin.set_type_variation("CommitButton", "Button")
	skin.set_stylebox("normal", "CommitButton", _box(GOLD, Color("#f0cf96")))
	skin.set_stylebox("hover", "CommitButton", _box(Color("#f0cd88"), Color("#fff0bf")))
	skin.set_stylebox("pressed", "CommitButton", _box(Color("#be9559"), Color("#f8d99d")))
	for face in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		skin.set_color(face, "CommitButton", DARK_TEXT)
	skin.set_stylebox("panel", "PopupMenu", _box(Color("#253733"), Color("#8e9573"), 1, 2, 6, 4))
	skin.set_stylebox("hover", "PopupMenu", _box(Color("#3b5145"), LINE))
	skin.set_color("font_color", "PopupMenu", PAPER)
	skin.set_color("font_hover_color", "PopupMenu", PAPER)
	skin.set_color("font_disabled_color", "PopupMenu", MUTED)
	skin.set_constant("v_separation", "PopupMenu", 8)
	skin.set_stylebox("scroll", "VScrollBar", _box(Color("#202e2a"), Color("#35453e"), 1, 1, 3, 0))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		skin.set_stylebox(state, "VScrollBar", _box(Color("#85937c"), Color("#85937c"), 0, 1, 3, 0))
	theme = skin


func _box(fill: Color, edge: Color, width := 1, radius := 2, horizontal := 10.0, vertical := 5.0) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = edge
	result.set_border_width_all(width)
	result.set_corner_radius_all(radius)
	result.content_margin_left = horizontal
	result.content_margin_right = horizontal
	result.content_margin_top = vertical
	result.content_margin_bottom = vertical
	return result


func _focus_box() -> StyleBoxFlat:
	var result := _box(Color.TRANSPARENT, Color("#f8dba0"), 2)
	result.draw_center = false
	return result


func _stack(parent: Control, spacing: int) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", spacing)
	parent.add_child(result)
	return result


func _row(parent: Control, spacing: int) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", spacing)
	parent.add_child(result)
	return result


func _label(parent: Control, text: String, type_size: int, color: Color, display := false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", type_size)
	result.add_theme_color_override("font_color", color)
	if display:
		result.add_theme_font_override("font", _display_font)
	parent.add_child(result)
	return result


func _rule(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.color = LINE
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


func _button(parent: Control, node_name: String, title: String) -> Button:
	var result := Button.new()
	result.name = node_name
	result.text = title
	result.custom_minimum_size.y = 34
	parent.add_child(result)
	return result


func _picker(parent: Control, node_name: String) -> OptionButton:
	var result := OptionButton.new()
	result.name = node_name
	result.fit_to_longest_item = false
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result.custom_minimum_size.y = 34
	parent.add_child(result)
	return result


func _log(parent: Control, node_name: String, height: float, expand := false) -> RichTextLabel:
	var result := RichTextLabel.new()
	result.name = node_name
	result.bbcode_enabled = true
	result.custom_minimum_size.y = height
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	result.add_theme_font_size_override("normal_font_size", 14)
	result.add_theme_color_override("default_color", PAPER)
	result.add_theme_constant_override("line_separation", 3)
	result.add_theme_stylebox_override("normal", _box(Color("#162725"), Color("#46574c"), 1, 0, 10, 7))
	parent.add_child(result)
	return result


func _presentation(art_key: String, fallback: String) -> String:
	return _presentation_entry(art_key).get("label", fallback)


func _presentation_entry(art_key: String) -> Dictionary:
	return _rules.definitions(_state).get("presentation", {}).get(art_key, {})


func _legend_key(parent: Control, art_key: String, fallback_label: String, fallback_color: Color) -> void:
	var definition := _presentation_entry(art_key)
	var title: String = definition.get("label", fallback_label)
	var color := Color.from_string(definition.get("color", ""), fallback_color)
	var entry := _row(parent, 6)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(8, 8)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = color
	entry.add_child(swatch)
	var caption := _label(entry, title, 12, MUTED)
	caption.custom_minimum_size.x = minf(caption.get_minimum_size().x, 105.0)
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.tooltip_text = title


func _add_choice(picker: OptionButton, text: String, key: String) -> void:
	picker.add_item(text)
	picker.set_item_metadata(picker.item_count - 1, key)


func _pick(picker: OptionButton, key: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == key:
			picker.select(index)
			return
	picker.select(0 if picker.item_count > 0 else -1)


func _picked(picker: OptionButton) -> String:
	return str(picker.get_selected_metadata()) if picker.selected >= 0 else ""
