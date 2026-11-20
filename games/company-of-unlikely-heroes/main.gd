extends Control

const Rules = preload("res://rules.gd")
const BridgeArt = preload("res://bridge_art.gd")

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
	"direct": {"name": "Direct", "text": "Give up to three heroes direct commands each round."},
	"standing": {"name": "Standing", "text": "All three heroes follow their standing orders."}
}
const TARGETED := ["move", "knight_push", "healer_bonk", "wizard_pull"]
const ACTION_HELP := {
	"move": "Step to an open neighboring tile.",
	"knight_push": "Push a neighboring unit or obstacle one tile. Collision deals damage.",
	"knight_aura": "Covers everyone within one tile; reflects to the nearest enemy or obstacle.",
	"healer_bonk": "Hurt an adjacent enemy or obstacle. Enemies also turn their attention to the healer.",
	"healer_heal": "Heals the nearest other hero, even if they are already at full health.",
	"wizard_blast": "Hits and knocks down the nearest unit, friend or foe. Obstacles can take the hit.",
	"wizard_pull": "Draws the target to the wizard’s tile. Recoil hurts and knocks down the wizard."
}
const HERO_COLOR := {"knight": Color("#a7cdcd"), "healer": Color("#e6cfa2"), "wizard": Color("#d9b3ce")}

var _rules = Rules.new()
var _state: Dictionary
# These drafts are a UI affordance. Only the engine can reserve an actual slot.
var _drafts: Dictionary = {}
var _planned_state: Dictionary
var _plan: Dictionary
var _editor_actor: Dictionary
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
var _hover_cell: Variant = null
var _position_pattern := RegEx.new()

var _display_font: SystemFont
var _board: BridgeArt
var _actor_select: OptionButton
var _ability_select: OptionButton
var _target_select: OptionButton
var _preview_button: Button
var _clear_button: Button
var _commit_button: Button
var _status: Label
var _round_text: Label
var _objective: Label
var _hover_text: Label
var _command_note: Label
var _action_help: Label
var _forecast: RichTextLabel
var _last_title: Label
var _last_result: RichTextLabel


func _ready() -> void:
	_position_pattern.compile("\\((-?\\d+),\\s*(-?\\d+)\\)")
	_make_theme()
	_build_ui()
	_reset("hybrid")


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
	var place := _label(header, "The last ferryman", 29, PAPER, true)
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_round_text = _label(header, "", 16, GOLD)
	_round_text.name = "RoundText"
	_round_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_objective = _label(parent, "", 14, MUTED)
	_board = BridgeArt.new()
	_board.name = "BridgeBoard"
	_board.custom_minimum_size.y = 405
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_board)
	_board.cell_selected.connect(_select_board)
	_board.cell_hovered.connect(_inspect_board)
	_board.hover_cleared.connect(_clear_inspection)
	var key := _row(parent, 14)
	_key(key, "Safe bank", Color("#a0a67a"))
	_key(key, "Bridge gap", Color("#5c918e"))
	_key(key, "Blocked", Color("#b38b60"))
	_key(key, "Target", MINT)
	_key(key, "Net HP loss", RUST)
	_key(key, "Forecast end", GOLD)
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
	var orders := _row(parent, 10)
	for role in ["knight", "healer", "wizard"]:
		var order := _stack(orders, 4)
		order.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := _row(order, 5)
		var label := _label(head, _name_for(role), 14, HERO_COLOR[role])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_order_notes[role] = _label(head, "", 12, MUTED)
		var picker := _picker(order, role.capitalize() + "Order")
		picker.tooltip_text = "Choose what the %s does unless directly commanded." % role
		picker.item_selected.connect(_select_order.bind(role))
		_orders[role] = picker


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
	_state = _rules.new_game(mode)
	_drafts.clear()
	_last_events.clear()
	_last_round = 0
	_unpreviewed_edit = false
	_actor_id = ""
	for unit in _state.units:
		if unit.team == "heroes":
			_actor_id = unit.id
			break
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
	for unit in _state.units:
		if unit.team != "heroes":
			continue
		_add_choice(_actor_select, _name_for(unit.id), unit.id)
		_actor_select.set_item_disabled(_actor_select.item_count - 1, unit.hp <= 0)
	var current := _find(_actor_id)
	if current.is_empty() or current.hp <= 0:
		_actor_id = ""
		for unit in _state.units:
			if unit.team == "heroes" and unit.hp > 0:
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
	_target_select.clear()
	_targets = _rules.targets(context, _actor_id, _ability_id) if _actor_can_act() else []
	var selected_exists := false
	for choice in _targets:
		var location := BridgeArt.coordinate(choice.position)
		var label := location if _ability_id == "move" else "%s  ·  %s" % [_name_for(choice.id), location]
		_add_choice(_target_select, label, choice.id)
		selected_exists = selected_exists or choice.id == _target_id
	if _targets.is_empty():
		var prompt := "No legal targets" if _ability_id in TARGETED else "Automatic or not needed"
		if _ability_id.is_empty():
			prompt = "No hero available"
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
		and (_ability_id not in TARGETED or not _target_id.is_empty())


func _can_stage_command() -> bool:
	return _ongoing() and _state.mode != "standing" and _ready_to_command() \
		and _actor_can_act()


func _actor_can_act() -> bool:
	return _editor_actor.get("hp", 0) > 0 and not _editor_actor.get("knocked_down", false)


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
	_round_text.text = "Round %d / %d" % [_state.round, _state.bridge_deadline]
	var ferry := _find_ferryman(_state)
	_objective.text = "Get the ferryman to %s before the bridge fails.   ·   Ferryman %d/%d HP at %s" % [
		BridgeArt.coordinate(_state.exit), ferry.hp, ferry.max_hp, BridgeArt.coordinate(ferry.position)]
	match str(_state.outcome):
		"victory":
			_objective.text = "Rescued! The ferryman reached the safe bank."
		"defeat":
			_objective.text = "Rescue failed. The ferryman fell or the ferry departed."
	_command_note.text = "%d direct slot%s left" % [_planned_state.manual_remaining, "" if _planned_state.manual_remaining == 1 else "s"]
	if _state.mode == "standing":
		_command_note.text = "Standing orders only"
	elif not active:
		_command_note.text = "Rescue ended"
	_actor_select.disabled = not manual
	_ability_select.disabled = not manual
	_target_select.disabled = not manual or _targets.is_empty()
	_preview_button.disabled = not _can_stage_command()
	_preview_button.text = "Preview changes" if _unpreviewed_edit else "Preview command"
	_clear_button.disabled = not manual or not _drafts.has(_actor_id)
	_commit_button.disabled = not active
	_commit_button.text = "Commit round %d" % _state.round if active else "Rescue complete" if _state.victory else "Rescue failed"
	_action_help.text = ACTION_HELP.get(_ability_id, "")
	if _ability_id in TARGETED and _targets.is_empty() and manual:
		_action_help.text = "No legal target when this hero acts."
	if manual and _editor_actor.get("knocked_down", false):
		_action_help.text = "This hero must get up and cannot act this round."
	elif manual and not _actor_can_act():
		_action_help.text = "This hero falls before their turn."
	if _state.mode == "standing":
		_action_help.text = "Change standing orders below the map to revise the forecast."
	elif not active:
		_action_help.text = "Restart to try another rescue."
	_refresh_orders(active)
	_refresh_forecast()
	_refresh_board()


func _refresh_orders(active: bool) -> void:
	for hero in _orders:
		var picker: OptionButton = _orders[hero]
		picker.clear()
		for choice in _rules.options(_state, hero):
			if choice.kind == "order":
				_add_choice(picker, choice.label, choice.id)
		_pick(picker, _state.orders.get(hero, ""))
		var unit := _find(hero)
		picker.disabled = not active or unit.is_empty() or unit.hp <= 0
		var note: Label = _order_notes[hero]
		note.text = "Down" if unit.get("knocked_down", false) else ""
		if unit.get("hp", 0) <= 0:
			note.text = "Fallen"
		elif _drafts.has(hero):
			note.text = "Direct this round"
		note.add_theme_color_override("font_color", GOLD if _drafts.has(hero) else MUTED)


func _refresh_forecast() -> void:
	if not _ongoing():
		_forecast.text = "[color=#e3b970][b]%s[/b][/color]\n%s" % [
			"Safe on the far bank" if _state.victory else "The rescue is lost",
			"Restart or change mode for another attempt."]
	else:
		var command_lines: PackedStringArray = []
		for hero in _drafts:
			var draft: Dictionary = _drafts[hero]
			var action := _choice_name(hero, draft.ability_id)
			var target := _target_description(hero, draft.ability_id, draft.target_id)
			command_lines.append("%s: %s%s" % [_name_for(hero), action, target])
		var summary := "No direct commands queued." if command_lines.is_empty() else "  ·  ".join(command_lines)
		var unpreviewed := "\n[color=#f0b495]Command edits are not in this forecast yet.[/color]" if _unpreviewed_edit and _can_stage_command() else ""
		_forecast.text = "[color=#e3b970][b]%s[/b][/color]%s\n%s" % [summary, unpreviewed, _event_lines(_plan.events)]
	_forecast.scroll_to_line(0)
	_last_title.text = "Last round" if _last_round == 0 else "Round %d result" % _last_round
	_last_result.text = "[color=#c0c7ad]Nothing resolved yet.[/color]" if _last_events.is_empty() else _last_report()
	_last_result.scroll_to_line(0)


func _last_report() -> String:
	var losses: PackedStringArray = []
	for event in _last_events:
		if event.type == "damage":
			losses.append("%s −%d HP" % [_name_for(event.target_id), event.amount])
	var cost := "[color=#f0b495][b]%s[/b][/color]" % "  ·  ".join(losses) if not losses.is_empty() \
		else "[color=#cae1b6]No damage taken or dealt.[/color]"
	return cost + "\n" + _event_lines(_last_events)


func _event_lines(events: Array) -> String:
	if events.is_empty():
		return "No actions predicted."
	var lines: PackedStringArray = []
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var ink := "#f0b495" if event.type in ["damage", "defeat"] else ("#cae1b6" if event.type in ["heal", "victory"] else "#f1dfb8")
		var line := _readable(event.text)
		if event.type == "heal" and line.ends_with(" for 0."):
			line = line.trim_suffix(" for 0.") + " (already at full health)."
		lines.append("[color=#9ba792]%02d[/color]  [color=%s]%s[/color]" % [index + 1, ink, line])
	return "\n".join(lines)


func _readable(text: String) -> String:
	text = text.replace("civilian", "ferryman")
	for location in _position_pattern.search_all(text):
		var p := Vector2i(location.get_string(1).to_int(), location.get_string(2).to_int())
		text = text.replace(location.get_string(), BridgeArt.coordinate(p))
	return text.substr(0, 1).to_upper() + text.substr(1) if not text.is_empty() else text


func _choice_name(hero: String, id: String) -> String:
	for choice in _rules.options(_state, hero):
		if choice.id == id:
			return choice.label
	return ""


func _target_description(hero: String, ability: String, target: String) -> String:
	if target.is_empty():
		return ""
	var context := _rules.state_before_action(_planned_state, hero)
	for choice in _rules.targets(context, hero, ability):
		if choice.id == target:
			var location := BridgeArt.coordinate(choice.position)
			return " to " + location if ability == "move" else " → %s at %s" % [_name_for(target), location]
	return " (target no longer legal)"


func _refresh_board() -> void:
	_painted_cells = _terrain()
	var units: Array = []
	for unit in _state.units:
		if unit.hp <= 0 and unit.team != "civilian":
			continue
		var art := {"id": unit.id, "role": "ferryman" if unit.team == "civilian" else unit["class"],
			"cell": unit.position, "hp": unit.hp, "max_hp": unit.max_hp,
			"prone": unit.knocked_down or unit.hp <= 0, "guarded": unit.get("aura", false)}
		if unit.id == "harpooner":
			art["variant"] = "spear"
		units.append(art)
	var overlay: Dictionary = {}
	if _ongoing():
		if _state.mode != "standing" and not _actor_id.is_empty():
			var selected := _find(_actor_id)
			overlay["selected"] = selected.position
			if _actor_can_act():
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
	overlay["obstacles"] = _state.obstacles.filter(
		func(obstacle: Dictionary) -> bool: return _painted_cells.get(obstacle.position, "") == "obstacle")
	_board.set_render_state(_painted_cells, units, overlay)
	if _hover_cell != null:
		_inspect_board(_hover_cell)


func _terrain() -> Dictionary:
	var cells: Dictionary = {}
	for y in range(_state.height):
		for x in range(_state.width):
			cells[Vector2i(x, y)] = "stone"
	for tile in _state.terrain:
		cells[tile.position] = "broken" if tile.type in ["gap", "collapsed"] else tile.type
	# The safe bank is land connected to the exit without stepping on the bridge.
	var shore := [_state.exit]
	cells[_state.exit] = "exit"
	var index := 0
	while index < shore.size():
		var at: Vector2i = shore[index]
		index += 1
		for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + direction
			if cells.get(next, "") == "stone":
				cells[next] = "safe"
				shore.append(next)
	for obstacle in _state.obstacles:
		if obstacle.hp > 0 and cells.get(obstacle.position, "") != "broken":
			cells[obstacle.position] = "obstacle"
	return cells


func _select_board(cell: Vector2i) -> void:
	if not _ongoing() or _state.mode == "standing":
		return
	for target in _targets:
		if target.position == cell and _ability_id in TARGETED:
			_pick(_target_select, target.id)
			_target_id = target.id
			_note_unpreviewed_edit()
			_refresh()
			return
	for unit in _state.units:
		if unit.position == cell and unit.team == "heroes" and unit.hp > 0:
			_pick(_actor_select, unit.id)
			_select_actor(_actor_select.selected)
			return


func _inspect_board(cell: Vector2i) -> void:
	_hover_cell = cell
	var place := BridgeArt.coordinate(cell)
	if _ongoing() and _state.mode != "standing":
		for target in _targets:
			if target.position == cell:
				var target_name := "Move destination" if _ability_id == "move" else _name_for(target.id) + " target"
				_hover_text.text = "%s  ·  %s when %s acts" % [place, target_name, _name_for(_actor_id)]
				_board.tooltip_text = _hover_text.text
				return
	for unit in _state.units:
		if unit.position == cell and unit.hp > 0:
			_hover_text.text = "%s  ·  %s  %d/%d HP" % [place, _name_for(unit.id), unit.hp, unit.max_hp]
			_board.tooltip_text = _hover_text.text
			return
	for obstacle in _state.obstacles:
		if obstacle.position == cell and obstacle.hp > 0 and _painted_cells.get(cell, "") == "obstacle":
			_hover_text.text = "%s  ·  %s  %d/%d HP" % [place, _name_for(obstacle.id), obstacle.hp, obstacle.max_hp]
			_board.tooltip_text = _hover_text.text
			return
	var tile: String = _painted_cells.get(cell, "")
	var labels := {"stone": "Stone", "safe": "Safe bank", "exit": "Ferry landing", "broken": "Bridge gap", "bridge": "Bridge"}
	_hover_text.text = "%s  ·  %s" % [place, labels.get(tile, tile.capitalize())]
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


func _find_ferryman(source: Dictionary) -> Dictionary:
	for unit in source.units:
		if unit.team == "civilian":
			return unit
	return {}


func _name_for(id: String) -> String:
	return "Ferryman" if id == "civilian" else id.capitalize()


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


func _key(parent: Control, title: String, color: Color) -> void:
	var entry := _row(parent, 6)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(8, 8)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = color
	entry.add_child(swatch)
	_label(entry, title, 12, MUTED)


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
