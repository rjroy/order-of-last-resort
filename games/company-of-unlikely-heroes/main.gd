extends Control

const Rules = preload("res://rules.gd")
const BridgeArt = preload("res://bridge_art.gd")
const BattleCues = preload("res://battle_cues.gd")
const Catalog = preload("res://content/catalog.gd")
const Adventure = preload("res://adventure.gd")
const Upgrades = preload("res://rules/upgrades.gd")
const Commissions = preload("res://commissions.gd")
const GuildProfile = preload("res://guild_profile.gd")
const DEFAULT_ADVENTURE := "first_outing"

const PAPER := Color("#f1dfb8")
const MUTED := Color("#c0c7ad")
const TEAL := Color("#263c3a")
const LINE := Color("#536353")
const GOLD := Color("#e3b970")
const MINT := Color("#cae1b6")
const RUST := Color("#f0b495")
const DARK_TEXT := Color("#2f281e")
const RARITY_INK := {"common": MUTED, "uncommon": MINT, "rare": Color("#bccbf5"), "legendary": GOLD}

var _rules = Rules.new()
var _definitions: Dictionary
var _adventure: Dictionary
var _adventure_id := DEFAULT_ADVENTURE
var _run: Dictionary
var _picked_recruits: Array = []
var _screen := ""
var _screen_root: Control
var _launch_args: Variant
var _profile_path := GuildProfile.DEFAULT_PATH
var _guild_profile: Dictionary
var _commission: Dictionary
var _practice_from_guild := false
var _fixed_mission := ""
var _opening_state: Dictionary
var _state: Dictionary
# The editor only becomes a command after the rules reserve it for the preview.
var _planned_state: Dictionary
var _plan: Dictionary
var _editor_actor: Dictionary
var _editor_can_act := false
var _editor_move_blocked := false
var _editor_knocked_down := false
var _editor_skip_label := ""
var _last_events: Array = []
var _last_round := 0
var _unpreviewed_edit := false
var _actor_id := ""
var _ability_id := ""
var _target_id := ""
var _targets: Array = []
var _orders: Dictionary = {}
var _order_notes: Dictionary = {}
var _painted_cells: Dictionary = {}
var _tile_labels: Dictionary = {}
var _safe_cells: Dictionary = {}
var _corpse_markers: Dictionary = {}
var _objective_markers: Dictionary = {}
var _hover_cell: Variant = null

var _display_font: SystemFont
var _board: BridgeArt
var _board_cues: BattleCues
var _legend: HFlowContainer
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
var _objective_progress: Label
var _initiative: Label
var _hover_text: Label
var _command_note: Label
var _action_help: Label
var _forecast: RichTextLabel
var _objective_forecast: Label
var _last_title: Label
var _last_result: RichTextLabel
var _order_grid: GridContainer


func _ready() -> void:
	_make_theme()
	var args: PackedStringArray = OS.get_cmdline_user_args() if _launch_args == null else _launch_args
	var launch := _read_launch_options(args)
	if launch.has("error"):
		_show_launch_error(launch.error)
		return
	var path: String = launch.content if not launch.content.is_empty() else Catalog.DEFAULT_PATH
	var content := Catalog.read_source(path)
	if content.has("error"):
		_show_launch_error(content.error)
		return
	_definitions = content.definitions
	_fixed_mission = launch.mission
	var adventures: Dictionary = _definitions.get("adventures", {})
	if not adventures.is_empty() and not adventures.has(_adventure_id):
		var ids: Array = adventures.keys()
		ids.sort()
		_adventure_id = ids[0]
	_adventure = adventures.get(_adventure_id, {})
	if _fixed_mission.is_empty() and _adventure.is_empty() and not launch.content.is_empty():
		if not _definitions.missions.has("ferryman"):
			_show_launch_error("This content has no first_outing adventure. " + _fixed_mission_help())
			return
		_fixed_mission = "ferryman"
	if not _fixed_mission.is_empty():
		if not _definitions.missions.has(_fixed_mission):
			_show_launch_error("No mission named \"%s\". %s" % [_fixed_mission, _fixed_mission_help()])
			return
		if _requires_party(_fixed_mission):
			var guild_adventure := _adventure_for_mission(_fixed_mission)
			var via_commissions := guild_adventure.is_empty()
			if via_commissions:
				guild_adventure = _commission_roster_for_mission(_fixed_mission)
			if guild_adventure.is_empty():
				_show_launch_error("The mission \"%s\" is not standalone, and this content has no guild route to it. %s" % [
					_fixed_mission, _fixed_mission_help()])
			else:
				var party_size := int(guild_adventure.party_size)
				var flags := "--mission or --fixed-outings" if via_commissions else "--mission"
				_show_launch_error("The mission \"%s\" needs a guild party. Launch without %s and choose %d %s at the guild. %s" % [
					_fixed_mission, flags, party_size, "recruit" if party_size == 1 else "recruits", _fixed_mission_help()])
			return
		var default_party: Array = _definitions.missions[_fixed_mission].get("default_party", [])
		_opening_state = Rules.open_mission(_definitions, _fixed_mission, default_party)
		if _opening_state.is_empty():
			_show_launch_error("The mission \"%s\" could not be set up. Check your content file." % _fixed_mission)
			return
		_show_battle(_opening_state.duplicate(true))
		return
	if not launch.fixed_outings and not _definitions.get("commission_settings", {}).is_empty():
		_open_commission_hub()
		return
	if _adventure.is_empty():
		_show_launch_error("The content has no first_outing adventure. " + _fixed_mission_help())
		return
	_show_guild()


func _requires_party(mission_id: String) -> bool:
	var mission: Dictionary = _definitions.missions[mission_id]
	var encounter: Dictionary = _definitions.encounters[mission.encounter]
	return not encounter.get("party_slots", []).is_empty() and mission.get("default_party", []).is_empty()


func _adventure_for_mission(mission_id: String) -> Dictionary:
	for entry in _definitions.get("adventures", {}).values():
		if mission_id in entry.get("missions", []):
			return entry
	return {}


func _commission_roster_for_mission(mission_id: String) -> Dictionary:
	if not _definitions.get("mission_reports", {}).has(mission_id):
		return {}
	# Catalog validation checks each reported mission can deploy the commission roster.
	var roster_id: String = _definitions.get("commission_settings", {}).get("roster_adventure", "")
	return _definitions.get("adventures", {}).get(roster_id, {})


func _fixed_mission_help() -> String:
	var ids: PackedStringArray = []
	for id in _definitions.missions:
		if not _requires_party(id):
			ids.append(id)
	if ids.is_empty():
		return "This content has no standalone missions."
	ids.sort()
	return "Use --mission=<id> for a standalone mission: %s." % ", ".join(ids)


func configure_launch(args: PackedStringArray) -> void:
	assert(not is_inside_tree(), "Set launch options before adding the scene.")
	_launch_args = args.duplicate()


func configure_profile_path(path: String) -> void:
	assert(not is_inside_tree(), "Set the profile path before adding the scene.")
	_profile_path = path


func current_screen() -> String:
	return _screen


func selected_recruits() -> Array:
	return _picked_recruits.duplicate()


func battle_snapshot() -> Dictionary:
	return _state.duplicate(true) if _screen == "battle" else {}


func _read_launch_options(args: PackedStringArray) -> Dictionary:
	var launch := {"content": "", "mission": "", "fixed_outings": false}
	var seen: Dictionary = {}
	for arg in args:
		var key := arg.get_slice("=", 0).trim_prefix("--")
		if arg.begins_with("--") and key == "fixed-outings":
			if arg != "--fixed-outings" or launch.fixed_outings:
				return {"error": "Use --fixed-outings once, without a value."}
			launch.fixed_outings = true
			continue
		if not arg.begins_with("--") or key not in ["content", "mission"]:
			continue
		var value := arg.substr(arg.find("=") + 1) if "=" in arg else ""
		if value.strip_edges().is_empty() or seen.has(key):
			return {"error": "Use --%s=<value> once, with a nonempty value." % key}
		launch[key] = value
		seen[key] = true
	return launch


func _show_launch_error(message: String) -> void:
	printerr("Could not start the game: " + message)
	_screen = "error"
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	var page := _page("error", 34)
	_label(page, "Could not start the game", 29, PAPER, true)
	_label(page, "Check your launch options and try again.", 14, MUTED)
	var detail := _log(page, "LaunchErrorText", 72, true)
	detail.bbcode_enabled = false
	detail.add_theme_color_override("default_color", RUST)
	detail.text = message


func _page(screen: String, top_margin := 22) -> VBoxContainer:
	_screen = screen
	if is_instance_valid(_screen_root):
		remove_child(_screen_root)
		_screen_root.queue_free()
	var padding := MarginContainer.new()
	_screen_root = padding
	padding.name = screen.to_pascal_case() + "Screen"
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		padding.add_theme_constant_override("margin_" + side, 34)
	for side in ["top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, top_margin)
	add_child(padding)
	return _stack(padding, 13)


func _open_commission_hub(board_refresh_failed := false) -> void:
	_practice_from_guild = false
	_commission = {}
	_picked_recruits.clear()
	_run = {}
	_state = {}
	print_verbose("Loading the guild profile.")
	_guild_profile = GuildProfile.load_profile(_profile_path)
	if _guild_profile.has("error"):
		print_verbose("Could not load the guild profile: %s" % _guild_profile.error)
		_show_profile_error(str(_guild_profile.error))
	elif _guild_profile.is_empty():
		print_verbose("No guild profile found.")
		_show_guild_creation(board_refresh_failed)
	else:
		print_verbose("Guild profile loaded.")
		_show_commissions(board_refresh_failed)


func _show_profile_error(message: String) -> void:
	var page := _page("profile_error", 48)
	_guild_masthead(page, "Could not open the guild", "The saved profile hasn’t been changed.",
		"PracticeOutings", "Practice outings", _open_practice_outings)
	_wrapped_label(page, message, 17, RUST)
	_wrapped_label(page, "Check the guild profile file and try again:", 16, MUTED)
	_wrapped_label(page, ProjectSettings.globalize_path(_profile_path), 15, PAPER)
	var retry := _primary_button(page, "ReloadGuild", "Reload profile")
	retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	retry.pressed.connect(_open_commission_hub)
	retry.grab_focus()


func _show_guild_creation(after_missing_profile := false) -> void:
	var page := _page("guild_creation", 48)
	_guild_masthead(page, "Name your guild", ProjectSettings.get_setting("application/config/name"),
		"PracticeOutings", "Practice outings", _open_practice_outings)
	if after_missing_profile:
		_wrapped_label(page, "The previous guild profile could not be found. Create a guild to choose another commission.", 16, RUST)
	var form_panel := _panel(page, 568)
	form_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var form := _stack(form_panel, 15)
	_wrapped_label(form, "Your guild keeps its name between outings. Once it’s founded, choose a commission and recruit your company.", 17, PAPER)
	_rule(form)
	_label(form, "Guild name", 15, MUTED)
	var input := LineEdit.new()
	input.name = "GuildName"
	input.placeholder_text = "Enter a guild name"
	input.accessibility_name = "Guild name"
	input.max_length = GuildProfile.MAX_NAME_LENGTH
	input.custom_minimum_size.y = 46
	form.add_child(input)
	var create := _primary_button(form, "CreateGuild", "Create guild")
	create.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	create.disabled = true
	var feedback := _wrapped_label(form, "", 15, RUST)
	feedback.hide()
	input.text_changed.connect(func(value: String) -> void:
		create.disabled = value.strip_edges().is_empty()
		feedback.hide())
	input.text_submitted.connect(func(_value: String) -> void:
		if not create.disabled:
			_create_guild(input.text, feedback))
	create.pressed.connect(func() -> void: _create_guild(input.text, feedback))
	input.grab_focus()


func _create_guild(guild_name: String, feedback: Label) -> void:
	print_verbose("Creating a guild profile.")
	var created := GuildProfile.create(_profile_path, guild_name, randi())
	if created.has("error"):
		print_verbose("Could not create the guild profile: %s" % created.error)
		feedback.text = str(created.error)
		feedback.show()
		return
	_guild_profile = created
	print_verbose("Guild profile created.")
	_show_commissions()


func _show_commissions(board_refresh_failed := false) -> void:
	var page := _page("commissions", 48)
	_guild_masthead(page, "Commission board", str(_guild_profile.name),
		"PracticeOutings", "Practice outings", _open_practice_outings)
	if board_refresh_failed:
		_wrapped_label(page, "The board wasn’t refreshed. These commissions are from the current saved guild.", 16, RUST)
	_wrapped_label(page, "Choose a destination. The mission count includes the final mission.", 17, MUTED)
	var cards := _row(page, 20)
	var offers := Commissions.board(_definitions, int(_guild_profile.board_seed))
	for index in range(offers.size()):
		var offer: Dictionary = offers[index]
		var title := _mission_title_for(offer.destination_id)
		var card := _guild_card(cards, 360)
		var copy := _guild_card_text(card, "CommissionText_%d" % index)
		_wrapped_label(copy, title, 32, PAPER, true)
		_label(copy, "%d missions" % offer.length, 16, GOLD)
		_rule(copy)
		_wrapped_label(copy, offer.description, 18, PAPER)
		var choose := _primary_button(card, "Commission_%d" % index, "Choose " + title)
		choose.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		choose.accessibility_name = "Choose commission: " + title
		choose.accessibility_description = "%d missions. %s" % [offer.length, offer.description]
		choose.pressed.connect(_select_commission.bind(offer))


func _select_commission(offer: Dictionary) -> void:
	_commission = offer
	_adventure = _definitions.adventures[_definitions.commission_settings.roster_adventure]
	_show_guild()


func _open_practice_outings() -> void:
	_practice_from_guild = true
	_picked_recruits.clear()
	_adventure = _definitions.adventures[_adventure_id]
	_show_guild()


func _guild_masthead(page: VBoxContainer, title: String, subtitle: String,
		link_name := "", link_text := "", action := Callable()) -> void:
	var line := _row(page, 18)
	var titles := _stack(line, 3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wrapped_label(titles, title, 44, PAPER, true)
	_wrapped_label(titles, subtitle, 17, GOLD)
	if action.is_valid():
		var nav := LinkButton.new()
		nav.name = link_name
		nav.text = link_text
		nav.custom_minimum_size.y = 43
		nav.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(nav)
		nav.pressed.connect(action)
	_rule(page)


func _guild_card(parent: Control, height: float) -> VBoxContainer:
	var panel := _panel(parent, 0)
	panel.custom_minimum_size.y = height
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(Color("#1d302e"), LINE, 1, 2, 23, 21))
	return _stack(panel, 13)


func _guild_card_text(card: VBoxContainer, node_name: String) -> VBoxContainer:
	var scroll := _scroll(card)
	scroll.name = node_name
	var bar := scroll.get_v_scroll_bar()
	bar.focus_mode = Control.FOCUS_ALL
	bar.accessibility_name = "Scroll card text"
	var copy := _stack(scroll, 13)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return copy


func _show_guild(focus_name := "") -> void:
	_state = {}
	var previous_scroll := find_child("RecruitScroll", true, false) as ScrollContainer if _screen == "guild" else null
	var scroll_position := previous_scroll.scroll_vertical if previous_scroll != null else 0
	var previous_slots := find_child("DeploymentScroll", true, false) as ScrollContainer if _screen == "guild" else null
	var slot_position := previous_slots.scroll_vertical if previous_slots != null else 0
	var page := _page("guild", 36)
	if _commission.is_empty():
		_build_practice_itinerary(page)
	else:
		_guild_masthead(page, "Choose your company",
			"%s  ·  %s  ·  %d missions" % [
				_guild_profile.name, _mission_title_for(_commission.destination_id), _commission.length],
			"BackToCommissions", "Commission board", _open_commission_hub)
	var columns := _row(page, 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var roster := _stack(columns, 10)
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(roster, "Choose your company" if _commission.is_empty() else "Available recruits", 30, PAPER, true)
	_wrapped_label(roster, "Take %d distinct recruits. Each round, you can command one hero; the others follow standing orders." % _adventure.party_size, 15, MUTED)
	var scroll := _scroll(roster)
	scroll.name = "RecruitScroll"
	var recruits := _stack(scroll, 10)
	recruits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for recruit_id in _adventure.roster:
		_build_recruit(recruits, recruit_id)
	var marching_panel := _panel(columns, 393)
	var scroll_slots: bool = _adventure.party_size > 3
	marching_panel.size_flags_vertical = Control.SIZE_FILL if scroll_slots else Control.SIZE_SHRINK_BEGIN
	var marching := _stack(marching_panel, 12)
	_label(marching, "Deployment order", 26, PAPER, true)
	_wrapped_label(marching, "The top hero acts first. This order places your party and sets who acts first in each mission.", 14, MUTED)
	var count := _label(marching, "%d / %d selected" % [_picked_recruits.size(), _adventure.party_size], 15, GOLD)
	count.name = "PartyCount"
	_rule(marching)
	var slots := marching
	var deployment_scroll: ScrollContainer
	if scroll_slots:
		deployment_scroll = _scroll(marching)
		deployment_scroll.name = "DeploymentScroll"
		slots = _stack(deployment_scroll, 12)
		slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for slot in range(_adventure.party_size):
		_build_party_slot(slots, slot)
	var departure := "Read field reports" if not _commission.is_empty() else "Depart for " + _mission_title_for(_adventure.missions[0])
	var start := _primary_button(marching, "StartAdventure", departure)
	start.disabled = _picked_recruits.size() != _adventure.party_size
	start.pressed.connect(_start_adventure)
	var focus: Button
	if not focus_name.is_empty():
		focus = find_child(focus_name, true, false) as Button
		if focus != null and focus.disabled and focus_name.begins_with("Party"):
			var opposite := focus_name.replace("Earlier_", "Later_") if "Earlier_" in focus_name else focus_name.replace("Later_", "Earlier_")
			focus = find_child(opposite, true, false) as Button
		if focus != null and not focus.disabled:
			focus.grab_focus()
	scroll.set_deferred("scroll_vertical", scroll_position)
	if deployment_scroll != null:
		_restore_deployment_scroll.call_deferred(deployment_scroll, slot_position, focus)


func _restore_deployment_scroll(scroll: ScrollContainer, position: int, focus: Button) -> void:
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	scroll.scroll_vertical = position
	if is_instance_valid(focus) and focus.has_focus() and scroll.is_ancestor_of(focus):
		scroll.ensure_control_visible(focus)


func _build_practice_itinerary(page: VBoxContainer) -> void:
	if _practice_from_guild:
		_guild_masthead(page, "Practice outings", ProjectSettings.get_setting("application/config/name"),
			"BackToCommissions", "Back to guild", _open_commission_hub)
	else:
		_label(page, ProjectSettings.get_setting("application/config/name"), 42, PAPER, true)
	var itinerary := _row(page, 24)
	var selection := _stack(itinerary, 4)
	selection.custom_minimum_size.x = 294
	_label(selection, "Adventure", 13, MUTED)
	var adventure_select := _picker(selection, "AdventureSelect")
	for id in _definitions.get("adventures", {}):
		_add_choice(adventure_select, _definitions.adventures[id].label, id)
	_pick(adventure_select, _adventure_id)
	adventure_select.tooltip_text = _adventure.label
	adventure_select.item_selected.connect(_select_adventure.bind(adventure_select))
	var route := _stack(itinerary, 4)
	route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(route, "%d missions" % _adventure.missions.size() if _adventure.missions.size() != 1 else "1 mission", 13, MUTED)
	_wrapped_label(route, _route_titles(), 15, PAPER)
	_rule(page)


func _select_adventure(index: int, selector: OptionButton) -> void:
	var id := str(selector.get_item_metadata(index))
	if id == _adventure_id or not _definitions.adventures.has(id):
		return
	_adventure_id = id
	_adventure = _definitions.adventures[id]
	_picked_recruits = _picked_recruits.filter(func(recruit: String) -> bool: return recruit in _adventure.roster)
	_picked_recruits.resize(mini(_picked_recruits.size(), int(_adventure.party_size)))
	_show_guild("AdventureSelect")


func _build_recruit(parent: VBoxContainer, id: String) -> void:
	var profile := Catalog.profile(_definitions, id)
	var picked := id in _picked_recruits
	var entry := _stack(_panel(parent, 0, GOLD if picked else LINE), 6)
	var header := _row(entry, 8)
	var title := _label(header, profile.label, 21, PAPER, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hp := _label(header, "%d HP" % profile.max_hp, 14, MINT)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var toggle := _button(header, "Recruit_" + id, "Remove" if picked else "Recruit")
	toggle.set_meta("recruit_id", id)
	toggle.custom_minimum_size.x = 95
	toggle.tooltip_text = ("Remove %s from the party" if picked else "Recruit %s") % profile.label
	toggle.disabled = not picked and _picked_recruits.size() == _adventure.party_size
	toggle.pressed.connect(_toggle_recruit.bind(id))
	var abilities: PackedStringArray = []
	for ability_id in profile.abilities:
		abilities.append(_definitions.abilities[ability_id].label)
	_wrapped_label(entry, "Actions: " + ", ".join(abilities), 14, PAPER)
	var order: Dictionary = _definitions.orders.get(profile.get("default_order", ""), {})
	_wrapped_label(entry, "Default order: " + str(order.get("label", "None")), 13, MUTED)
	var description: String = profile.get("description", "")
	if not description.is_empty():
		toggle.tooltip_text += "\n" + description


func _build_party_slot(parent: VBoxContainer, slot: int) -> void:
	var line := _row(parent, 8)
	_label(line, "%d" % (slot + 1), 15, GOLD).custom_minimum_size.x = 19
	var id: String = _picked_recruits[slot] if slot < _picked_recruits.size() else ""
	var name_text: String = "Open place" if id.is_empty() else Catalog.profile(_definitions, id).label
	var label := _label(line, name_text, 17, MUTED if id.is_empty() else PAPER)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.custom_minimum_size.y = 34
	if id.is_empty():
		return
	for delta in [-1, 1]:
		var direction := "Earlier" if delta < 0 else "Later"
		var button := _button(line, "Party%s_%s" % [direction, id], direction)
		button.tooltip_text = "%s goes %s" % [name_text, direction.to_lower()]
		button.disabled = slot + delta < 0 or slot + delta >= _picked_recruits.size()
		button.pressed.connect(_move_recruit.bind(id, delta, str(button.name)))


func _toggle_recruit(id: String) -> void:
	if id in _picked_recruits:
		_picked_recruits.erase(id)
	elif _picked_recruits.size() < _adventure.party_size and id in _adventure.roster:
		_picked_recruits.append(id)
	_show_guild("Recruit_" + id)


func _move_recruit(id: String, delta: int, focus_name: String) -> void:
	var old_index := _picked_recruits.find(id)
	var new_index := old_index + delta
	if old_index < 0 or new_index < 0 or new_index >= _picked_recruits.size():
		return
	_picked_recruits.remove_at(old_index)
	_picked_recruits.insert(new_index, id)
	_show_guild(focus_name)


func _route_titles() -> String:
	var titles: PackedStringArray = []
	for mission_id in _adventure.missions:
		titles.append(_mission_title_for(mission_id))
	return "  →  ".join(titles)


func _mission_title_for(mission_id: String) -> String:
	return _definitions.missions[mission_id].title


func _start_adventure() -> void:
	if not _commission.is_empty():
		_run = Adventure.start_commission(_definitions, _commission, _picked_recruits)
		if _run.get("phase") == "route":
			_show_routes()
		return
	_run = Adventure.start_adventure(_definitions, _adventure_id, _picked_recruits)
	if not _run.is_empty():
		_begin_mission()


func _show_routes() -> void:
	var page := _page("routes", 48)
	var title := _mission_title_for(_run.destination_id)
	var next := int(_run.mission_index) + 1
	var total := Adventure.mission_count(_run)
	var penultimate := next == total - 1
	_guild_masthead(page, "Field reports", "%s  ·  Mission %d of %d" % [title, next, total])
	_wrapped_label(page, "Choose where to go next. Both roads lead to your destination." if penultimate
		else "Choose your next mission. Each report includes a clue about what may follow.", 17, MUTED)
	var cards := _row(page, 20)
	var first: Button
	for index in range(_run.reports.size()):
		var report: Dictionary = _run.reports[index]
		var card := _guild_card(cards, 416)
		var copy := _guild_card_text(card, "RouteText_%d" % index)
		var route_name := "Route A" if index == 0 else "Route B"
		_label(copy, route_name, 29, PAPER, true)
		_rule(copy)
		_label(copy, "Immediate mission", 15, GOLD)
		_wrapped_label(copy, report.description, 18, PAPER)
		_rule(copy)
		_label(copy, "Known destination" if penultimate else "Farther ahead", 15, GOLD)
		_wrapped_label(copy, report.hint_text, 17, PAPER)
		var choice := "Take %s to %s" % [route_name, title] if penultimate else "Take " + route_name
		var choose := _primary_button(card, "Route_%d" % index, choice)
		choose.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		choose.accessibility_description = "Next: %s. Farther ahead: %s" % [report.description, report.hint_text]
		choose.pressed.connect(_choose_route.bind(str(report.mission_id)))
		if index == 0:
			first = choose
	if first != null:
		first.grab_focus()


func _choose_route(mission_id: String) -> void:
	if _screen != "routes":
		return
	var selected := Adventure.choose_route(_run, mission_id)
	if selected.get("phase") == "ready":
		_run = selected
		_begin_mission()


func _begin_mission() -> void:
	if _run.get("phase") != "ready":
		return
	var deployed := Adventure.begin_mission(_run)
	if deployed.phase == "mission":
		_run = deployed
		_show_battle(_run.mission)


func _show_debrief() -> void:
	var result: Dictionary = _run.last_result
	var pending: bool = _run.phase == "reward"
	var next_title := ""
	if _commission.is_empty():
		next_title = _mission_title_for(_run.mission_ids[_run.mission_index])
	elif _run.phase == "ready":
		next_title = _mission_title_for(_run.destination_id)
	var chosen: Dictionary = _run.get("chosen_reward", {})
	if pending or not chosen.is_empty():
		_show_reward_debrief(next_title, pending, chosen)
		return
	var page := _page("debrief", 44)
	_label(page, "%s cleared" % _mission_title_for(result.mission_id), 44, PAPER, true)
	_wrapped_label(page, "Review the party before leaving for %s. You decide when to continue." % next_title, 16, MUTED)
	_rule(page)
	var panel := _stack(_panel(page, 0), 12)
	_build_carry_report(panel)
	_add_continue(panel, next_title).grab_focus()


func _show_reward_debrief(next_title: String, pending: bool, chosen: Dictionary) -> void:
	var page := _page("debrief", 38)
	_wrapped_label(page, "%s cleared" % _mission_title_for(_run.last_result.mission_id), 44, PAPER, true)
	if not next_title.is_empty():
		_wrapped_label(page, "Next mission: " + next_title, 16, MUTED)
	_rule(page)
	var columns := _row(page, 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rewards := _stack(columns, 10)
	rewards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(rewards, "Choose one reward" if pending else "Reward claimed", 29, PAPER, true)
	_wrapped_label(rewards, "The chosen hero keeps their upgrade until you return to the guild." if pending \
		else "This upgrade is ready for the next mission and stays with the hero for the outing.", 16, MUTED)
	var list := _stack(_scroll(rewards), 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var first_offer: Button
	var offers: Array = _run.reward_offers if pending else [chosen]
	for offer in offers:
		var button := _build_reward_entry(list, offer, pending)
		if first_offer == null:
			first_offer = button
	_rule(list)
	var carry := _scroll(columns)
	carry.custom_minimum_size.x = 376
	var company := _panel(carry, 0)
	company.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var company_report := _stack(company, 12)
	_build_carry_report(company_report)
	var scout_note: String = _run.get("scout_note", "")
	if pending and not scout_note.is_empty():
		_rule(company_report)
		_label(company_report, "Your scout’s note", 22, PAPER, true)
		_wrapped_label(company_report, scout_note, 16, PAPER)
	_rule(page)
	var footer := _row(page, 16)
	var reminder := _wrapped_label(footer, "Choose a reward before continuing." if pending \
		else "Your company can now read the next field reports." if next_title.is_empty() \
		else "Your company can now depart.", 15, MUTED)
	reminder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reminder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var advance := _add_continue(footer, next_title)
	if pending and first_offer != null:
		first_offer.grab_focus()
	elif not advance.disabled:
		advance.grab_focus()


func _build_reward_entry(parent: VBoxContainer, offer: Dictionary, pending: bool) -> Button:
	var hero_id: String = offer.hero_id
	var upgrade_id: String = offer.upgrade_id
	var upgrade: Dictionary = _definitions.upgrades[upgrade_id]
	var hero := Catalog.profile(_definitions, hero_id)
	var rarity: String = upgrade.rarity.capitalize()
	var owned := int(_run.upgrades_by_id.get(hero_id, {}).get(upgrade_id, 0))
	var progress := "%d of %d acquired" % [owned, upgrade.cap]
	if pending:
		progress += "  ·  %d of %d if chosen" % [owned + 1, upgrade.cap]
	_rule(parent)
	var entry := _stack(_panel(parent, 0, Color.TRANSPARENT if pending else Color("#68866a")), 5)
	var line := _row(entry, 16)
	var ledger := _stack(line, 4)
	ledger.custom_minimum_size.x = 156
	_wrapped_label(ledger, hero.label, 21, Color.from_string(hero.get("color", ""), PAPER), true)
	_label(ledger, rarity, 14, RARITY_INK.get(upgrade.rarity, MUTED))
	var effect := _stack(line, 3)
	effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wrapped_label(effect, upgrade.label, 23, PAPER, true)
	_wrapped_label(effect, upgrade.description, 15, PAPER)
	_wrapped_label(effect, progress, 14, MUTED)
	if not pending:
		_label(line, "Awarded", 15, MINT).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return null
	var button := _button(line, "Reward_" + hero_id, "Take reward")
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(112, 44)
	button.accessibility_name = "Award %s to %s" % [upgrade.label, hero.label]
	button.accessibility_description = "%s. %s. %s. This is your one reward for the mission." % [
		rarity, upgrade.description, progress]
	button.set_meta("hero_id", hero_id)
	button.set_meta("upgrade_id", upgrade_id)
	button.pressed.connect(_claim_reward.bind(hero_id, upgrade_id))
	return button


func _claim_reward(hero_id: String, upgrade_id: String) -> void:
	if _screen != "debrief" or _run.phase != "reward":
		return
	var chosen := Adventure.choose_reward(_run, hero_id, upgrade_id)
	if chosen.phase in ["ready", "route"]:
		_run = chosen
		_show_debrief()


func _add_continue(parent: Control, next_title: String) -> Button:
	var caption := "Continue"
	if not next_title.is_empty():
		caption = "Continue to " + next_title
	elif _run.phase == "route":
		caption = "Read field reports"
	var advance := _primary_button(parent, "ContinueAdventure", caption)
	advance.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	advance.disabled = _run.phase not in ["ready", "route"]
	if advance.disabled:
		advance.accessibility_description = "Choose one reward first."
		advance.add_theme_stylebox_override("disabled", _box(Color("#202d2a"), LINE))
		advance.add_theme_color_override("font_disabled_color", MUTED)
	advance.pressed.connect(_continue_after_debrief)
	return advance


func _continue_after_debrief() -> void:
	if _run.phase == "route":
		_show_routes()
	else:
		_begin_mission()


func _build_carry_report(panel: VBoxContainer) -> void:
	_label(panel, "What carries forward", 26, PAPER, true)
	var report := _label(panel, "", 16, PAPER)
	report.name = "CarryReport"
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var lines: PackedStringArray = []
	for id in _run.party:
		var before: Dictionary = _run.last_result.heroes_by_id[id]
		var after: Dictionary = _run.carry_by_id[id]
		var max_hp := Adventure.next_mission_max_hp(_run, id)
		var next_hp := Adventure.next_mission_hp(_run, id)
		var wounds := "  ·  Wounded" if next_hp < max_hp else ""
		var recovery := ""
		if before.hp <= 0 and after.hp > 0:
			recovery = "  ·  Back on their feet"
		elif before.knocked_down:
			recovery = "  ·  Recovered from knockdown"
		var order: Dictionary = _definitions.orders.get(after.order, {})
		lines.append("%s   %d/%d HP → %d/%d HP%s%s\nStanding order: %s" % [
			before.label, before.hp, before.max_hp, next_hp, max_hp,
			wounds, recovery, order.get("label", "None")])
	report.text = "\n\n".join(lines)


func _show_result() -> void:
	var result: Dictionary = _run.last_result
	var page := _page("result", 44)
	var success: bool = result.outcome == "victory"
	var outing := "Adventure" if _commission.is_empty() else "Commission"
	var outcome := _label(page, "%s %s" % [outing, "complete" if success else "failed"], 44, MINT if success else RUST, true)
	outcome.name = "RunOutcome"
	outcome.set_meta("outcome", result.outcome)
	_label(page, _mission_title_for(result.mission_id), 22, PAPER, true)
	if not result.text.is_empty():
		_wrapped_label(page, result.text, 16, PAPER)
	_rule(page)
	if _commission.is_empty():
		_wrapped_label(page, "Return to the guild to recruit a fresh party.", 16, MUTED)
	else:
		_wrapped_label(page, "Return to %s for a fresh commission board." % _guild_profile.name, 16, MUTED)
	var return_button := _primary_button(page, "ReturnToGuild", "Return to guild")
	return_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return_button.pressed.connect(_return_to_guild)
	return_button.grab_focus()


func _return_to_guild() -> void:
	if not _commission.is_empty():
		if _run.get("phase") != "finished":
			return
		var next_seed := randi()
		if next_seed == int(_guild_profile.board_seed):
			next_seed ^= 1
		print_verbose("Refreshing the commission board after %s." % _run.outcome)
		var renewed := GuildProfile.renew(_profile_path, _guild_profile, next_seed)
		if renewed.has("error"):
			print_verbose("Could not refresh the commission board: %s" % renewed.error)
		else:
			print_verbose("Commission board refreshed.")
		_open_commission_hub(renewed.has("error"))
		return
	var guild := Adventure.return_to_guild(_run)
	if guild.phase != "guild":
		return
	_run = guild
	_picked_recruits.clear()
	_show_guild()


func _show_battle(opening: Dictionary) -> void:
	_state = opening
	_orders.clear()
	_order_notes.clear()
	_hover_cell = null
	var page := _page("battle")
	_build_masthead(page)
	_rule(page)
	var columns := _row(page, 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var map_column := _stack(columns, 9)
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_map(map_column)
	_build_orders(map_column)
	_build_desk(columns)
	_begin_attempt()


func _build_masthead(parent: Control) -> void:
	var head := _row(parent, 16)
	var titles := _stack(head, 4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(titles, ProjectSettings.get_setting("application/config/name"), 30, PAPER, true)
	_status = _label(titles, "", 14, MUTED)
	_status.name = "StatusText"
	if not _fixed_mission.is_empty():
		var restart := _button(head, "Restart", "Restart mission")
		restart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		restart.pressed.connect(_restart_fixed)
	elif _run.get("upgrades_by_id", {}).values().any(func(owned: Dictionary) -> bool: return not owned.is_empty()):
		_build_loadout(head)


func _build_loadout(parent: Control) -> void:
	var button := _button(parent, "ShowLoadout", "Outing upgrades")
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size.y = 43
	var dialog := AcceptDialog.new()
	dialog.name = "OutingLoadout"
	dialog.title = "Outing upgrades"
	dialog.borderless = true
	dialog.ok_button_text = "Close"
	parent.add_child(dialog)
	var panel := _stack(_panel(dialog, 0), 12)
	_label(panel, "Outing upgrades", 28, PAPER, true)
	_wrapped_label(panel, "These upgrades stay with your heroes until you return to the guild.", 15, MUTED)
	var content := _stack(_scroll(panel), 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for unit in _roster():
		var owned: Dictionary = _run.upgrades_by_id.get(unit.id, {})
		if owned.is_empty():
			continue
		var profile: Dictionary = _rules.entity_profile(_state, unit.id)
		_rule(content)
		_label(content, _name_for(unit.id), 23, Color.from_string(profile.get("color", ""), PAPER), true)
		for id in owned:
			var upgrade: Dictionary = _definitions.upgrades[id]
			_wrapped_label(content, "%s  ·  %s  ·  %d of %d acquired" % [
				upgrade.label, upgrade.rarity.capitalize(), owned[id], upgrade.cap], 16, PAPER)
			_wrapped_label(content, upgrade.description, 15, MUTED)
	button.pressed.connect(func() -> void: dialog.popup_centered(Vector2i(600, 300)))


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
	_objective.max_lines_visible = 3
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objective_progress = _wrapped_label(parent, "", 14, GOLD)
	_objective_progress.name = "ObjectiveProgress"
	_initiative = _label(parent, "", 13, PAPER)
	_initiative.name = "InitiativeText"
	_initiative.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_board = BridgeArt.new()
	_board.name = "BridgeBoard"
	_board.custom_minimum_size.y = 315
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_board)
	_board.cell_selected.connect(_select_board)
	_board.cell_hovered.connect(_inspect_board)
	_board.hover_cleared.connect(_clear_inspection)
	_board_cues = BattleCues.new()
	_board_cues.name = "ObjectiveMarkers"
	_board.add_child(_board_cues)
	_board_cues.attach_to(_board)
	_legend = HFlowContainer.new()
	_legend.name = "MapLegend"
	_legend.add_theme_constant_override("h_separation", 14)
	_legend.add_theme_constant_override("v_separation", 4)
	parent.add_child(_legend)
	_hover_text = _label(parent, "Point at a tile to inspect it.", 13, MUTED)
	_hover_text.name = "TileInspection"
	_hover_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _build_orders(parent: VBoxContainer) -> void:
	_rule(parent)
	var heading := _row(parent, 12)
	_label(heading, "Standing orders", 22, PAPER, true)
	var note := _label(heading, "Used unless the hero has a direct command.", 13, MUTED)
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
	_order_grid.columns = clampi(roster.size(), 1, 4)
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
		_order_notes[id] = _label(order, "", 12, MUTED)
		var picker := _picker(order, id.to_pascal_case() + "Order")
		picker.set_meta("actor_id", id)
		picker.tooltip_text = "Choose what %s does unless directly commanded." % label.text
		picker.item_selected.connect(_select_order.bind(id))
		_orders[id] = picker
	var first_order := _order_grid.get_child(0) as Control if not roster.is_empty() else null
	var row_height := first_order.get_combined_minimum_size().y if first_order != null else 0.0
	var scroll := _order_grid.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = row_height


func _build_desk(parent: HBoxContainer) -> void:
	var panel := _panel(parent, 423)
	var desk := _stack(panel, 8)
	var header := _row(desk, 10)
	var title := _label(header, "Direct command", 24, PAPER, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_note = _wrapped_label(desk, "", 14, GOLD)
	_command_note.name = "CommandedHero"
	var selection := _row(desk, 8)
	var who := _stack(selection, 3)
	who.custom_minimum_size.x = 148
	_label(who, "Hero", 13, MUTED)
	_actor_select = _picker(who, "ActorSelect")
	_actor_select.item_selected.connect(_select_actor)
	var what := _stack(selection, 3)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(what, "Action", 13, MUTED)
	_ability_select = _picker(what, "AbilitySelect")
	_ability_select.allow_reselect = true
	_ability_select.item_selected.connect(_select_ability)
	var target := _stack(desk, 3)
	_label(target, "Target", 13, MUTED)
	_target_select = _picker(target, "TargetSelect")
	_target_select.allow_reselect = true
	_target_select.item_selected.connect(_select_target)
	_action_help = _label(desk, "", 13, MUTED)
	_action_help.name = "ActionHelp"
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
	_objective_forecast = _wrapped_label(desk, "", 13, GOLD)
	_objective_forecast.name = "ObjectiveForecast"
	_forecast = _log(desk, "PreviewText", 142, true)
	_last_title = _label(desk, "Last round", 18, PAPER, true)
	_last_result = _log(desk, "LastResult", 63)
	_commit_button = _primary_button(desk, "Commit", "Commit round")
	_commit_button.tooltip_text = "Resolve the round as shown in the forecast."
	_commit_button.pressed.connect(_commit)


func _restart_fixed() -> void:
	_state = _opening_state.duplicate(true)
	_clear_inspection()
	_begin_attempt()


func _begin_attempt() -> void:
	_planned_state = _state
	_last_events.clear()
	_last_round = 0
	_unpreviewed_edit = false
	_actor_id = ""
	_sync_actors()
	_sync_command()
	_refresh(true)


func _sync_actors() -> void:
	_actor_select.clear()
	var roster := _roster()
	for unit in roster:
		_add_choice(_actor_select, _name_for(unit.id), unit.id)
		var index := _actor_select.item_count - 1
		_actor_select.set_item_disabled(index, unit.hp <= 0)
		var upgrades := _owned_upgrade_labels(unit.id)
		if not upgrades.is_empty():
			_actor_select.set_item_tooltip(index, "Outing upgrades: " + upgrades)
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
			_add_choice(_ability_select, _action_definition(choice.id).get("label", choice.label), choice.id)
	var draft: Dictionary = _planned_state.overrides.get(_actor_id, {})
	_pick(_ability_select, draft.get("ability_id", ""))
	_ability_id = _picked(_ability_select)
	_target_id = draft.get("target_id", "")


func _sync_targets(auto_pick: bool) -> void:
	# A preview for the editor's hero replaces any queued override.
	var editor_plan := _planned_state if _planned_state.overrides.has(_actor_id) else _state
	var context := _rules.state_before_action(editor_plan, _actor_id)
	_editor_actor = _find(_actor_id, context)
	_editor_can_act = _rules.can_act(context, _actor_id)
	_editor_move_blocked = _rules.has_status_handler(context, _actor_id, "stop_move")
	_editor_knocked_down = _rules.knocked_down(context, _actor_id)
	_editor_skip_label = ", ".join(_rules.status_labels(context, _actor_id, "skip_action"))
	_target_select.clear()
	var target_kind := _target_kind()
	var selectable := _is_selectable(target_kind)
	var summon := _is_summon()
	_targets = _rules.targets(context, _actor_id, _ability_id) if selectable and _editor_can_act else []
	var selected_exists := false
	for choice in _targets:
		var location := BridgeArt.coordinate(choice.position)
		var label := location if target_kind == "cell" else "%s  ·  %s" % [choice.label, location]
		_add_choice(_target_select, label, choice.id)
		selected_exists = selected_exists or choice.id == _target_id
	if _targets.is_empty():
		var prompt := "No target needed"
		if not _ongoing():
			prompt = "Mission ended"
		elif _actor_id.is_empty():
			prompt = "No hero available"
		elif _ability_id.is_empty():
			prompt = "No action available"
		elif not _editor_can_act:
			if _editor_actor.get("hp", 0) <= 0:
				prompt = "Falls before acting"
			else:
				prompt = "Knocked down" if _editor_knocked_down else "Skips turn"
		elif summon and _rules.summon_capped(context, _actor_id, _ability_id):
			prompt = "Summon already alive"
		elif summon and target_kind == "entity":
			prompt = "No unoccupied enemy corpse"
		elif target_kind == "cell":
			if not summon and _editor_move_blocked:
				prompt = "Held in place"
			else:
				prompt = "No open adjacent tile" if summon or _rules.has_capability(context, _actor_id, "mobile") else "Cannot move"
		elif selectable:
			prompt = "No legal targets"
		elif target_kind == "automatic":
			prompt = "Random opponent (automatic)" if _action_definition(_ability_id).get("handler") == "perform" else "Automatic"
		_add_choice(_target_select, prompt, "")
	elif not selected_exists and (not auto_pick or not _target_id.is_empty()):
		_add_choice(_target_select, "Choose a target", "")
		_target_select.set_item_disabled(_target_select.item_count - 1, true)
	_pick(_target_select, _target_id if selected_exists else "")
	_target_id = _picked(_target_select)


func _select_actor(index: int) -> void:
	if _actor_select.is_item_disabled(index):
		return
	var actor_id := str(_actor_select.get_item_metadata(index))
	if actor_id == _actor_id:
		return
	_actor_id = actor_id
	_unpreviewed_edit = false
	_sync_command()
	_refresh(true)


func _select_ability(index: int) -> void:
	var ability_id := str(_ability_select.get_item_metadata(index))
	if _ability_id != ability_id:
		_target_id = ""
	_ability_id = ability_id
	_unpreviewed_edit = true
	_refresh(true)


func _select_target(index: int) -> void:
	_target_id = str(_target_select.get_item_metadata(index))
	_note_unpreviewed_edit()
	_refresh()


func _select_order(index: int, hero: String) -> void:
	var order_id := str(_orders[hero].get_item_metadata(index))
	_state = _rules.set_order(_state, hero, order_id)
	_planned_state = _rules.set_order(_planned_state, hero, order_id)
	_refresh()


func _stage_command() -> void:
	if not _can_stage_command():
		_refresh()
		return
	_planned_state = _rules.choose_manual(_rules.clear_manual(_planned_state), _actor_id, _ability_id, _target_id)
	_unpreviewed_edit = false
	_refresh()


func _note_unpreviewed_edit() -> void:
	var previous: Dictionary = _planned_state.overrides.get(_actor_id, {})
	_unpreviewed_edit = previous.get("ability_id", "") != _ability_id \
		or previous.get("target_id", "") != _target_id


func _clear_command() -> void:
	if not _unpreviewed_edit:
		_planned_state = _rules.clear_manual(_planned_state)
	_unpreviewed_edit = false
	_sync_command()
	_refresh(true)


func _ready_to_command() -> bool:
	return not _actor_id.is_empty() and not _ability_id.is_empty() \
		and (not _is_selectable(_target_kind()) or not _target_id.is_empty())


func _target_kind(ability := "") -> String:
	if ability.is_empty():
		ability = _ability_id
	return _action_definition(ability).get("targeting", {}).get("kind", "")


func _action_definition(ability: String, actor := "") -> Dictionary:
	var actor_id := _actor_id if actor.is_empty() else actor
	var definition: Dictionary = _rules.ability_definition(_state, ability, actor_id)
	if ability == "healer_heal" and definition.get("handler") == "heal" \
			and Upgrades.amount(_state, _find(actor_id), "me_or_you") > 0:
		return definition.merged({
			"label": "Heal self or split among allies",
			"help": "If hurt, heal self; otherwise split among other living deployed heroes, unused shares lost."
		}, true)
	return definition


func _is_summon() -> bool:
	return _action_definition(_ability_id).get("handler") == "summon"


func _is_selectable(target_kind: String) -> bool:
	return target_kind == "cell" or target_kind == "entity"


func _can_stage_command() -> bool:
	return _ongoing() and _ready_to_command() and _editor_can_act


func _commit() -> void:
	if not _can_commit():
		return
	_last_round = _state.round
	_last_events = _plan.events.duplicate(true)
	_state = _rules.commit_round(_planned_state, _plan)
	_planned_state = _state
	_unpreviewed_edit = false
	if not _ongoing() and _fixed_mission.is_empty():
		_run = Adventure.settle_mission(_run, _state)
		match _run.phase:
			"reward":
				_show_debrief()
				return
			"route":
				_show_routes()
				return
			"ready":
				if _commission.is_empty():
					_show_debrief()
				else:
					_begin_mission()
				return
			"finished":
				_show_result()
				return
	_sync_actors()
	_sync_command()
	_refresh(true)


func _refresh(auto_pick_target := false) -> void:
	_plan = _rules.preview_round(_planned_state)
	_sync_targets(auto_pick_target)
	if _unpreviewed_edit:
		_note_unpreviewed_edit()
	var active := _ongoing()
	var manual := active and not _actor_id.is_empty()
	_status.text = "Fixed mission  ·  One direct command per round" if not _fixed_mission.is_empty() \
		else "Mission %d of %d  ·  One direct command per round" % [_run.mission_index + 1, Adventure.mission_count(_run)]
	_refresh_objective()
	_refresh_initiative()
	var commanded := _commanded_hero()
	_command_note.set_meta("actor_id", commanded)
	_command_note.text = ("Commanded: " + _name_for(commanded)) if not commanded.is_empty() else "No direct command queued"
	_actor_select.disabled = not manual
	_ability_select.disabled = not manual or _ability_select.item_count == 0
	_target_select.disabled = not manual or _targets.is_empty()
	_preview_button.disabled = not _can_stage_command()
	_preview_button.text = "Preview replacement" if not commanded.is_empty() and commanded != _actor_id else "Preview command"
	_clear_button.disabled = not active or (commanded.is_empty() and not _unpreviewed_edit)
	_clear_button.text = "Discard edit" if _unpreviewed_edit else "Clear command"
	_commit_button.disabled = not _can_commit()
	_commit_button.text = "Commit round %d" % _state.round if active else "Mission complete" if _state.outcome == "victory" else "Mission failed"
	_action_help.text = _command_help(active, manual)
	_action_help.tooltip_text = _action_help.text
	_refresh_orders(active)
	_refresh_forecast()
	_refresh_board()


func _command_help(active: bool, manual: bool) -> String:
	if not active:
		return "Restart this mission to try again." if not _fixed_mission.is_empty() else "This mission has ended."
	if not manual:
		return ""
	if not _editor_can_act:
		if _editor_actor.get("hp", 0) <= 0:
			return "This hero falls before acting. Change an earlier order or choose another hero."
		if _editor_knocked_down:
			if _rules.knocked_down(_state, _actor_id):
				return "This hero is down and spends this turn getting up. Choose another hero."
			return "This hero will be knocked down before acting. Change an earlier order or choose another hero."
		return "%s. Change an earlier order or choose another hero." % _editor_skip_label
	var target_kind := _target_kind()
	var action := _action_definition(_ability_id)
	var help: String = action.get("help", "")
	if _ability_id == "knight_shield_throw" and action.get("handler") == "attack" \
			and action.get("params", {}).has("damage") and action.get("targeting", {}).has("range"):
		help = "Deal %d damage from up to %d tiles away. Retrieve the shield before guarding or throwing again." % [
			action.params.damage, action.targeting.range]
	var shield: Variant = _rules.shield_position(_state, _actor_id)
	if shield is Vector2i:
		help = "Shield at %s. %s" % [BridgeArt.coordinate(shield), help]
	if _is_summon():
		if _target_select.disabled:
			return _target_select.text + ". " + help
		return help
	if target_kind == "cell":
		if _editor_move_blocked:
			return "Don't Go prevents Move this turn. Other actions remain available."
		if not _rules.has_capability(_state, _actor_id, "mobile"):
			return "This hero cannot move. Choose another action or hero."
		if _targets.is_empty():
			return "No open tile up, down, left, or right when this hero acts. Choose another action or hero."
		if _editor_actor.position != _find(_actor_id).position:
			return "This hero will act from %s. Choose a highlighted tile." % BridgeArt.coordinate(_editor_actor.position)
		return "Choose a highlighted tile up, down, left, or right."
	if target_kind == "entity" and _targets.is_empty():
		return "No legal target when this hero acts. Choose another action or hero."
	return help


func _can_commit() -> bool:
	return _ongoing() and not _unpreviewed_edit and _plan.get("valid", false)


func _commanded_hero() -> String:
	return "" if _planned_state.overrides.is_empty() else str(_planned_state.overrides.keys()[0])


func _refresh_objective() -> void:
	var mission: Dictionary = _rules.mission_definition(_state)
	var objective: Dictionary = mission.objective
	var deadline: int = _rules.deadline(_state)
	_mission_title.text = mission.title
	_mission_title.tooltip_text = mission.title
	_round_text.text = "Round %d / %d" % [_state.round, deadline] if deadline > 0 else "Round %d · No deadline" % _state.round
	var text_key: String = "text" if _ongoing() else _state.outcome + "_text"
	var values := {"deadline": deadline}
	var progress: Dictionary = _rules.objective_progress(_state)
	_objective_progress.text = _objective_progress_text(_state, progress)
	if _state.objective.handler == "leave_zone" and _ongoing():
		_objective_progress.text += "  ·  Damaging standing orders remain active."
	match _state.objective.handler:
		"escort":
			var subject := _find(_state.objective.subject)
			var subject_label := _name_for(subject.id)
			var destination := BridgeArt.coordinate(_state.objective.destination)
			var position := BridgeArt.coordinate(subject.position)
			values.merge({"subject": subject_label.to_lower(), "subject_label": subject_label,
				"destination": destination, "hp": subject.hp, "max_hp": subject.max_hp,
				"position": position})
		"defeat_all":
			values.merge({"remaining": progress.alive, "total": progress.total})
	_objective.text = str(objective.get(text_key, objective.text)).format(values)
	_objective.tooltip_text = _objective.text
	_objective_progress.visible = not _objective_progress.text.is_empty()


func _objective_progress_text(state: Dictionary, progress: Dictionary) -> String:
	match state.objective.handler:
		"escort":
			var subject := _find(state.objective.subject, state)
			return "%s  ·  %d/%d HP  ·  %s → %s" % [
				_name_for(subject.id), subject.hp, subject.max_hp,
				BridgeArt.coordinate(subject.position), BridgeArt.coordinate(state.objective.destination)]
		"defeat_all":
			return "%d / %d targets remaining" % [progress.alive, progress.total]
		"leave_zone":
			var subject := _find(state.objective.subject, state)
			return "%s  ·  %d/%d HP  ·  %s" % [
				_name_for(subject.id), subject.hp, subject.max_hp, BridgeArt.coordinate(subject.position)] \
				if not subject.is_empty() else ""
	return progress.get("text", "")


func _refresh_initiative() -> void:
	var labels: PackedStringArray = []
	var ids: PackedStringArray = []
	for unit in _rules.initiative(_state):
		labels.append("%s. %s" % [labels.size() + 1, _name_for(unit.id)])
		ids.append(unit.id)
	_initiative.text = "Initiative: " + "   ".join(labels) if not labels.is_empty() else "Initiative: none"
	_initiative.tooltip_text = _initiative.text
	_initiative.set_meta("actor_ids", ids)


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
		var is_commanded: bool = hero == _commanded_hero()
		var detail := "%d/%d HP" % [unit.hp, unit.max_hp]
		if unit.hp <= 0:
			detail += " · Fallen"
		elif _rules.knocked_down(_state, hero):
			detail += " · Down"
		elif _rules.has_status_handler(_state, hero, "skip_action"):
			detail += " · Skips turn"
		elif _rules.has_status_handler(_state, hero, "stop_move"):
			detail += " · Held"
		if is_commanded:
			detail += " · Direct"
		note.text = detail
		note.add_theme_color_override("font_color", GOLD if is_commanded else RUST if unit.hp < unit.max_hp else MUTED)


func _refresh_forecast() -> void:
	_refresh_objective_forecast()
	if not _ongoing():
		_forecast.text = "[color=#e3b970][b]%s[/b][/color]\n%s" % [
			_escape_log_text(_objective.text),
			"Restart this mission for another attempt." if not _fixed_mission.is_empty() else ""]
	else:
		var summary := "Standing orders only this round."
		var hero := _commanded_hero()
		if not hero.is_empty():
			var draft: Dictionary = _planned_state.overrides[hero]
			var action: String = _action_definition(draft.ability_id, hero).label
			var target := _target_description(hero, draft.ability_id, draft.target_id)
			summary = "%s: %s%s" % [_name_for(hero), action, target]
		var unpreviewed := ""
		if _unpreviewed_edit:
			var next_step := "Preview" if _can_stage_command() else "Change"
			unpreviewed = "\n[color=#f0b495]Edit not queued. %s or discard it before committing.[/color]" % next_step
		_forecast.text = "[color=#e3b970][b]%s[/b][/color]%s%s\n%s" % [
			_escape_log_text(summary), unpreviewed, _forecast_upgrade_details(), _event_lines(_plan.events)]
	_forecast.scroll_to_line(0)
	_last_title.text = "Last round" if _last_round == 0 else "Round %d result" % _last_round
	_last_result.text = "[color=#c0c7ad]Nothing resolved yet.[/color]" if _last_events.is_empty() else _last_report()
	_last_result.scroll_to_line(0)


func _refresh_objective_forecast() -> void:
	var text := ""
	var outcome := ""
	var ink := GOLD
	if _ongoing() and _plan.get("valid", false):
		var projected: Dictionary = _plan.result
		outcome = projected.outcome
		if outcome in ["victory", "defeat"]:
			text = "Forecast: Victory this round." if outcome == "victory" else "Forecast: Defeat this round."
			ink = MINT if outcome == "victory" else RUST
			for event in _plan.events:
				if event.type == outcome:
					text += " " + str(event.text)
					break
		elif projected.objective.handler != "defeat_all":
			var next := _objective_progress_text(projected, _rules.objective_progress(projected))
			var now := _objective_progress_text(_state, _rules.objective_progress(_state))
			if not next.is_empty() and next != now:
				text = "After this round: " + next
		if not text.is_empty() and _unpreviewed_edit:
			text += " (Edit not previewed.)"
	_objective_forecast.text = text
	_objective_forecast.tooltip_text = text
	_objective_forecast.add_theme_color_override("font_color", ink)
	_objective_forecast.set_meta("outcome", outcome)
	_objective_forecast.visible = not text.is_empty()


func _forecast_upgrade_details() -> String:
	var lines: PackedStringArray = []
	for member in _roster():
		var current: Variant = _rules.shield_position(_state, member.id)
		var predicted: Variant = _rules.shield_position(_plan.result, member.id)
		if predicted is Vector2i:
			var timing := " after this round" if predicted != current else ""
			lines.append("%s’s shield: %s%s." % [_name_for(member.id), BridgeArt.coordinate(predicted), timing])
		elif current is Vector2i:
			lines.append("%s recovers their shield from %s." % [_name_for(member.id), BridgeArt.coordinate(current)])
		var focused: String = _rules.nominated_target(_plan.result, member.id)
		if not focused.is_empty():
			lines.append("%s’s summons pursue %s." % [_name_for(member.id), _name_for(focused)])
	return "" if lines.is_empty() else "\n" + _escape_log_text("\n".join(lines))


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
	var definition := _action_definition(ability, hero)
	if target.is_empty():
		if definition.get("handler") == "perform":
			for event in _plan.events:
				if event.get("unit_id") == hero and event.get("ability_id") == ability:
					return " → %s" % event.target_label if event.has("target_label") else " (no eligible listener)"
		return ""
	var context := _rules.state_before_action(_planned_state, hero)
	for choice in _rules.targets(context, hero, ability):
		if choice.id == target:
			var location := BridgeArt.coordinate(choice.position)
			if definition.get("targeting", {}).get("kind") == "cell":
				return (" at " if definition.get("handler") == "summon" else " to ") + location
			return " → %s at %s" % [choice.label, location]
	return " (target no longer legal)"


func _refresh_board() -> void:
	_painted_cells = _terrain()
	var units: Array = []
	_corpse_markers = _rules.corpse_markers(_state)
	for corpse in _corpse_markers.values():
		var profile: Dictionary = _rules.entity_profile(_state, corpse.id)
		units.append({"id": corpse.id, "art_key": profile.art_key, "variant": profile.get("art_variant", ""),
			"label": "Corpse", "cell": corpse.position, "hp": 0, "max_hp": 0, "prone": true})
	var shared_art := _shared_enemy_art()
	for unit in _state.units:
		var is_objective: bool = unit.id == _state.objective.get("subject") \
			or unit.id in _state.objective.get("subjects", [])
		if unit.hp <= 0 and not is_objective:
			continue
		var profile: Dictionary = _rules.entity_profile(_state, unit.id)
		var show_label: bool = "commandable" in profile.capabilities or "minion" in profile.capabilities
		var art_variant := str(profile.get("art_variant", ""))
		var caption := _name_for(unit.id) if show_label else str(profile.label) \
			if is_objective or shared_art.has([profile.art_key, art_variant]) else ""
		var figure := {"id": unit.id, "art_key": profile.art_key, "variant": art_variant,
			"label": caption, "color": profile.get("color", ""),
			"cell": unit.position, "hp": unit.hp, "max_hp": unit.max_hp, "objective": is_objective,
			"prone": unit.hp <= 0 or _rules.knocked_down(_state, unit.id),
			"guarded": _rules.has_status_handler(_state, unit.id, "reflect"),
			"shield_away": _rules.shield_position(_state, unit.id) is Vector2i}
		if "minion" in profile.capabilities:
			var directed := _find(_rules.nominated_target(_state, unit.id))
			if not directed.is_empty() and directed.position.x != unit.position.x:
				figure["facing"] = -1 if directed.position.x < unit.position.x else 1
		units.append(figure)
	var overlay := {"safe": _safe_cells, "obstacles": [], "shields": [], "forecast_shields": []}
	for member in _roster():
		var shield: Variant = _rules.shield_position(_state, member.id)
		if shield is Vector2i:
			overlay.shields.append(shield)
		if _ongoing():
			var predicted: Variant = _rules.shield_position(_plan.result, member.id)
			if predicted is Vector2i and predicted != shield:
				overlay.forecast_shields.append(predicted)
	var board: Dictionary = _rules.definitions(_state).boards[_state.board_id]
	var zone_id: String = _state.objective.get("zone", "")
	var native_exit: bool = _state.objective.handler == "escort"
	_objective_markers = _rules.objective_markers(_state).duplicate()
	if _state.objective.handler == "leave_zone":
		overlay["objective_zone"] = board.get("zones", {}).get(zone_id, [])
		for at in overlay.objective_zone:
			var cell := Vector2i(int(at[0]), int(at[1]))
			if not _objective_markers.has(cell):
				_objective_markers[cell] = {"kind": "zone", "label": "Village square"}
	if native_exit:
		overlay["exit"] = _state.objective.destination
		if not _objective_markers.has(overlay.exit):
			_objective_markers[overlay.exit] = {"kind": "exit", "label": _presentation("exit", "Destination")}
	for obstacle in _state.obstacles:
		if obstacle.hp <= 0:
			continue
		overlay.obstacles.append({"id": obstacle.id, "position": obstacle.position,
			"hp": obstacle.hp, "max_hp": obstacle.max_hp,
			"art_key": _rules.entity_profile(_state, obstacle.id).art_key})
	if _ongoing():
		var commanded := _find(_commanded_hero())
		if not commanded.is_empty():
			overlay["commanded"] = commanded.position
		if not _actor_id.is_empty():
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
		var hooked: Dictionary = {}
		for event in _plan.events:
			if event.type == "pull" and event.has("from_position"):
				hooked[event.target_id] = true
		for entity in _state.units + _state.obstacles:
			var predicted := _find(entity.id, _plan.result)
			if predicted.is_empty():
				continue
			if predicted.hp < entity.hp:
				hits.append(entity.position)
			if predicted.position != entity.position and not hooked.has(entity.id):
				paths.append([entity.position, predicted.position])
		paths.append_array(_hooked_paths(hooked))
		overlay["impact"] = hits
		overlay["paths"] = paths
	_board.set_render_state(_painted_cells, units, overlay)
	_board_cues.update_markers(_objective_markers, native_exit)
	_refresh_map_legend(native_exit)
	if _hover_cell != null:
		_inspect_board(_hover_cell)


func _shared_enemy_art() -> Dictionary:
	var first_roles := {}
	var shared := {}
	for unit in _state.units:
		var profile: Dictionary = _rules.entity_profile(_state, unit.id)
		if profile.get("team") == "heroes":
			continue
		var art := [profile.art_key, str(profile.get("art_variant", ""))]
		var role: String = unit.character_id
		if not first_roles.has(art):
			first_roles[art] = role
		elif first_roles[art] != role:
			shared[art] = true
	return shared


func _refresh_map_legend(native_exit: bool) -> void:
	var kinds: PackedStringArray = []
	for marker in _objective_markers.values():
		if not marker.kind in kinds:
			kinds.append(marker.kind)
	if _legend.has_meta("objective_kinds") and _legend.get_meta("objective_kinds") == kinds:
		return
	_legend.set_meta("objective_kinds", kinds)
	for entry in _legend.get_children():
		_legend.remove_child(entry)
		entry.queue_free()
	for kind in kinds:
		var mark: Array = BattleCues.MARKS.get(kind, ["", "Objective", GOLD])
		var glyph: String = mark[0]
		var title: String = mark[1]
		if kind == "exit" and native_exit:
			glyph = ""
			title = _presentation("exit", "Destination")
		_legend_key(_legend, kind, title, mark[2], glyph)
	if native_exit:
		_legend_key(_legend, "safe", "Safe bank", Color("#a0a67a"))
		_legend_key(_legend, "broken", "Bridge gap", Color("#5c918e"))
	_legend_key(_legend, "obstacle", "Blocked", Color("#b38b60"))
	_legend_key(_legend, "target", "Target", MINT)
	_legend_key(_legend, "impact", "Net HP loss", RUST)
	_legend_key(_legend, "path", "Forecast end", GOLD)


func _hooked_paths(hooked: Dictionary) -> Array:
	# Replay position-bearing events in order, so a move before or after a hook
	# does not become a misleading straight line to the final position.
	var positions: Dictionary = {}
	for entity in _state.units + _state.obstacles:
		positions[entity.id] = entity.position
	var paths: Array = []
	for event in _plan.events:
		match event.type:
			"move":
				_trace_position(positions, paths, hooked, event.unit_id, event.position)
			"push", "repel":
				_trace_position(positions, paths, hooked, event.target_id, event.position)
			"pull":
				if event.has("from_position"):
					positions[event.target_id] = event.from_position
				_trace_position(positions, paths, hooked, event.target_id, event.position)
				if event.has("recoil_position"):
					_trace_position(positions, paths, hooked, event.unit_id, event.recoil_position)
			"swap":
				_trace_position(positions, paths, hooked, event.unit_id, event.position)
				_trace_position(positions, paths, hooked, event.target_id, event.target_position)
	return paths


func _trace_position(positions: Dictionary, paths: Array, hooked: Dictionary, id: String, destination: Vector2i) -> void:
	if hooked.has(id) and positions.has(id) and positions[id] != destination:
		paths.append([positions[id], destination])
	positions[id] = destination


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
	if not _state.objective.has("destination"):
		return cells
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
	if not _ongoing():
		return
	var matching := _targets_at(cell)
	if matching.size() > 1:
		_target_select.show_popup()
		return
	if matching.size() == 1:
		_pick(_target_select, matching[0].id)
		_select_target(_target_select.selected)
		return
	for unit in _roster():
		if unit.position == cell and unit.hp > 0:
			_pick(_actor_select, unit.id)
			_select_actor(_actor_select.selected)
			return


func _inspect_board(cell: Vector2i) -> void:
	_hover_cell = cell
	var marker: Dictionary = _objective_markers.get(cell, {})
	var place := BridgeArt.coordinate(cell) if marker.is_empty() else \
		"%s  ·  %s" % [BridgeArt.coordinate(cell), marker.label]
	var shield_note := _shield_tile_note(cell)
	var target_note := ""
	if _ongoing():
		var target_kind := _target_kind()
		var matching := _targets_at(cell)
		if not matching.is_empty():
			if target_kind == "cell":
				target_note = "Summon destination" if _is_summon() else "Move destination"
			else:
				target_note = "Legal target" if matching.size() == 1 else "%d targets; choose in Target" % matching.size()
			target_note = "  ·  %s when %s acts" % [target_note, _name_for(_actor_id)]
	for unit in _state.units:
		if unit.position == cell and unit.hp > 0:
			var text := "%s%s  ·  %s  %d/%d HP" % [place, shield_note, _name_for(unit.id), unit.hp, unit.max_hp]
			for label in _rules.status_labels(_state, unit.id):
				text += "  ·  " + label
			var focus_id: String = _rules.nominated_target(_state, unit.id)
			if not focus_id.is_empty():
				var prefix := "Summons pursue " if _rules.has_capability(_state, unit.id, "commandable") else "Pursuing "
				text += "  ·  " + prefix + _name_for(focus_id)
			_set_inspection(text + target_note, _enemy_inspection_notes(unit.id))
			return
	for obstacle in _state.obstacles:
		if obstacle.position == cell and obstacle.hp > 0:
			_set_inspection("%s%s  ·  %s  %d/%d HP%s" % [
				place, shield_note, _name_for(obstacle.id), obstacle.hp, obstacle.max_hp, target_note])
			return
	var label: String = _tile_labels.get(cell, "")
	if _safe_cells.has(cell) and marker.is_empty():
		label = _presentation("safe", label)
	if _corpse_markers.has(cell):
		label = "%s  ·  %s corpse" % [label, _name_for(_corpse_markers[cell].id)]
	_set_inspection("%s%s  ·  %s%s" % [place, shield_note, label, target_note])


func _set_inspection(text: String, details := PackedStringArray()) -> void:
	_hover_text.text = text if details.is_empty() else text + "  ·  " + details[0]
	var full := text if details.is_empty() else text + "\n" + "\n".join(details)
	_hover_text.tooltip_text = full
	_board.tooltip_text = full


func _enemy_inspection_notes(id: String) -> PackedStringArray:
	var profile: Dictionary = _rules.entity_profile(_state, id)
	if profile.get("team") != "enemies":
		return []
	var definitions: Dictionary = _rules.definitions(_state)
	var notes := BattleCues.trait_notes(profile, definitions)
	var behavior: Dictionary = definitions.behaviors.get(profile.get("behavior", ""), {})
	var options: Dictionary = behavior.get("params", {})
	if behavior.get("handler") == "retreat_attack":
		notes.append("Retreats from nearby heroes.")
	for key in ["heal_ability", "swap_ability"]:
		if options.has(key):
			var ability: Dictionary = definitions.abilities[options[key]]
			notes.append(ability.help)
	if behavior.get("handler") == "use_ability" and options.has("ability"):
		var ability: Dictionary = definitions.abilities[options.ability]
		if ability.get("handler") == "blast":
			notes.append(ability.help)
	return notes


func _shield_tile_note(cell: Vector2i) -> String:
	var notes: PackedStringArray = []
	for member in _roster():
		var current: Variant = _rules.shield_position(_state, member.id)
		if current == cell:
			notes.append("%s’s dropped shield" % _name_for(member.id))
		elif _ongoing() and _rules.shield_position(_plan.result, member.id) == cell:
			notes.append("%s’s shield landing (forecast)" % _name_for(member.id))
	return "" if notes.is_empty() else "  ·  " + "  ·  ".join(notes)


func _targets_at(cell: Vector2i) -> Array:
	return _targets.filter(func(target: Dictionary) -> bool: return target.position == cell)


func _clear_inspection() -> void:
	_hover_cell = null
	_hover_text.text = "Point at a tile to inspect it."
	_hover_text.tooltip_text = ""
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


func _owned_upgrade_labels(hero: String) -> String:
	var owned: Dictionary = _run.get("upgrades_by_id", {}).get(hero, {})
	var labels: PackedStringArray = []
	for id in owned:
		labels.append("%s (%d)" % [_definitions.upgrades[id].label, owned[id]])
	return ", ".join(labels)


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
	skin.set_stylebox("normal", "LineEdit", _box(Color("#162725"), LINE, 1, 2, 13, 7))
	skin.set_stylebox("focus", "LineEdit", _focus_box())
	skin.set_font_size("font_size", "LineEdit", 17)
	skin.set_color("font_color", "LineEdit", PAPER)
	skin.set_color("font_placeholder_color", "LineEdit", MUTED)
	skin.set_color("font_selected_color", "LineEdit", DARK_TEXT)
	skin.set_color("selection_color", "LineEdit", GOLD)
	skin.set_color("caret_color", "LineEdit", PAPER)
	skin.set_stylebox("focus", "LinkButton", _focus_box())
	skin.set_font_size("font_size", "LinkButton", 16)
	for face in ["font_color", "font_focus_color", "font_pressed_color"]:
		skin.set_color(face, "LinkButton", GOLD)
	skin.set_color("font_hover_color", "LinkButton", PAPER)
	skin.set_stylebox("panel", "PopupMenu", _box(Color("#253733"), Color("#8e9573"), 1, 2, 6, 4))
	skin.set_stylebox("hover", "PopupMenu", _box(Color("#3b5145"), LINE))
	skin.set_color("font_color", "PopupMenu", PAPER)
	skin.set_color("font_hover_color", "PopupMenu", PAPER)
	skin.set_color("font_disabled_color", "PopupMenu", MUTED)
	skin.set_constant("v_separation", "PopupMenu", 8)
	skin.set_stylebox("panel", "AcceptDialog", _box(Color("#152724"), LINE, 1, 2, 8, 8))
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


func _scroll(parent: Control) -> ScrollContainer:
	var result := ScrollContainer.new()
	result.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result.follow_focus = true
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result


func _panel(parent: Node, width: float, border := LINE) -> PanelContainer:
	var result := PanelContainer.new()
	result.custom_minimum_size.x = width
	result.add_theme_stylebox_override("panel", _box(Color("#1d302e"), border, 1, 2, 15, 12))
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


func _wrapped_label(parent: Control, text: String, type_size: int, color: Color, display := false) -> Label:
	var result := _label(parent, text, type_size, color, display)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


func _primary_button(parent: Control, node_name: String, title: String) -> Button:
	var result := _button(parent, node_name, title)
	result.custom_minimum_size.y = 43
	result.theme_type_variation = &"CommitButton"
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


func _legend_key(parent: Control, art_key: String, fallback_label: String, fallback_color: Color, glyph := "") -> void:
	var definition := _presentation_entry(art_key) if glyph.is_empty() else {}
	var title: String = definition.get("label", fallback_label)
	var color := Color.from_string(definition.get("color", ""), fallback_color)
	var entry := _row(parent, 6)
	if glyph.is_empty():
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(8, 8)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = color
		entry.add_child(swatch)
	else:
		_label(entry, glyph, 12, color)
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
