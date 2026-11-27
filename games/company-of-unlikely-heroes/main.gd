extends Control

const Rules = preload("res://rules/rules.gd")
const BridgeArt = preload("res://presentation/battle/bridge_art.gd")
const BattleCues = preload("res://presentation/battle/battle_cues.gd")
const BattleDisplayPreferences = preload("res://presentation/settings/battle_display_preferences.gd")
const CastCues = preload("res://presentation/cast/cast_cues.gd")
const SoundEffects = preload("res://presentation/audio/sound_effects.gd")
const BackgroundMusic = preload("res://presentation/audio/background_music.gd")
const Catalog = preload("res://content/catalog.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")
const GuildProfile = preload("res://guild/guild_profile.gd")
const Progression = preload("res://guild/guild_progression.gd")
const GuildBookPage = preload("res://presentation/book/guild_book_page.gd")
const GuildBookArt = preload("res://presentation/book/guild_book_art.gd")
const GuildCreationPage = preload("res://presentation/book/guild_creation_page.gd")
const GuildBoundPage = preload("res://presentation/book/guild_bound_page.gd")
const CommissionBoardPage = preload("res://presentation/book/commission_board_page.gd")
const FieldReportsPage = preload("res://presentation/book/field_reports_page.gd")
const MissionDebriefPage = preload("res://presentation/book/mission_debrief_page.gd")
const RunResultPage = preload("res://presentation/book/run_result_page.gd")
const DiagnosticBookPage = preload("res://presentation/book/diagnostic_book_page.gd")
const ReceiptCopy = preload("res://presentation/book/guild_receipt_copy.gd")
const GuildPetitionViewModel = preload("res://presentation/book/guild_petition_view_model.gd")
const PracticeEncounter = preload("res://content/practice/practice_encounter.gd")
const PracticeLesson = preload("res://presentation/battle/practice_lesson.gd")
const PracticeInstructions = preload("res://presentation/help/practice_instructions.gd")
const TERMINAL_REPLAY_STALL_MS := 3200

const PAPER := Color("#f1dfb8")
const MUTED := Color("#c0c7ad")
const TEAL := Color("#263c3a")
const LINE := Color("#536353")
const GOLD := Color("#e3b970")
const MINT := Color("#cae1b6")
const DARK_TEXT := Color("#2f281e")

var _rules = Rules.new()
var _definitions: Dictionary
var _adventure: Dictionary
var _run: Dictionary
var _picked_recruits: Array = []
var _screen := ""
var _screen_root: Control
var _book: GuildBookPage
var _launch_args: Variant
var _uses_builtin_catalog := false
var _profile_path := GuildProfile.DEFAULT_PATH
var _profile_path_configured := false
var _guild_profile: Dictionary
var _commission: Dictionary
var _petition_page
var _recruitment_page
var _petition_selected := ""
var _petition_hero_filter := ""
var _petition_scroll_position := 0
var _petition_input_revision := 0
var _guild_feedback := ""
var _return_error := ""
var _return_conflict := false
var _return_seed: Variant = null
var _loadouts: Dictionary = {}
var _selected_hero_id := ""
var _recruitment_folio := "recruits"
var _fixed_mission := ""
var _storybook_page: Control
var _practice: PracticeLesson
var _practice_instructions: PracticeInstructions
var _grid_visible := true
var _grid_labels_visible := true
var _nameplates_visible := true
var _always_show_health_bar := false
var _storybook_inspection := ""
var _storybook_inspected_cell: Variant = null
var _storybook_focus_cell: Variant = null
var _opening_state: Dictionary
var _state: Dictionary
# The one staged command lives in _planned_state, independently of selection and aim.
var _planned_state: Dictionary
var _plan: Dictionary
var _draft_summary := ""
var _draft_target_cell: Variant = null
var _editor_actions: Dictionary = {}
var _editor_unavailable_reason := ""
var _last_events: Array = []
var _actor_id := ""
var _aimed_ability_id := ""
var _occupant_cell: Variant = null
var _painted_cells: Dictionary = {}
var _tile_labels: Dictionary = {}
var _safe_cells: Dictionary = {}
var _corpse_markers: Dictionary = {}
var _objective_markers: Dictionary = {}

var _display_font: SystemFont
var _board: BridgeArt
var _board_cues: BattleCues
var _terminal_replay: PanelContainer
var _terminal_board: BridgeArt
var _terminal_replay_until := 0
var _terminal_remaining_ms := 0.0
var _sound_effects
var _music


func _ready() -> void:
	set_process(false)
	_sound_effects = SoundEffects.new()
	_sound_effects.name = "SoundEffects"
	add_child(_sound_effects)
	_music = BackgroundMusic.new()
	_music.name = "BackgroundMusic"
	add_child(_music)
	_make_theme()
	_grid_visible = BattleDisplayPreferences.load_grid_visible()
	_grid_labels_visible = BattleDisplayPreferences.load_grid_labels_visible()
	_nameplates_visible = BattleDisplayPreferences.load_nameplates_visible()
	_always_show_health_bar = BattleDisplayPreferences.load_always_show_health_bar()
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
	_uses_builtin_catalog = launch.content.is_empty()
	if not _uses_builtin_catalog and not _profile_path_configured:
		_profile_path = GuildProfile.CUSTOM_PATH
	_fixed_mission = launch.mission
	if _fixed_mission.is_empty() and not launch.content.is_empty() \
			and _definitions.get("commission_settings", {}).is_empty():
		var standalone: Array = _definitions.missions.keys().filter(func(id: String) -> bool: return not _requires_party(id))
		if standalone.size() != 1:
			_show_launch_error("This content has no commissions and no single mission with an authored party. " + _fixed_mission_help())
			return
		_fixed_mission = standalone[0]
	if not _fixed_mission.is_empty():
		if not _definitions.missions.has(_fixed_mission):
			_show_launch_error("No mission named \"%s\". %s" % [_fixed_mission, _fixed_mission_help()])
			return
		if _requires_party(_fixed_mission) and not launch.has("party"):
			var encounter: Dictionary = _definitions.encounters[_definitions.missions[_fixed_mission].encounter]
			var count: int = encounter.get("party_slots", []).size()
			_show_launch_error("Mission '%s' needs exactly %d party heroes. Use --mission=%s --party=<hero,...> in deployment order." % [
				_fixed_mission, count, _fixed_mission])
			return
		var party: Array = launch.get("party", _definitions.missions[_fixed_mission].get("default_party", []))
		var setup := _standalone_setup(_fixed_mission, party, launch.loadouts)
		if setup.has("error"):
			_show_launch_error(setup.error, setup.get("guidance", ""))
			return
		_opening_state = setup.state
		if _opening_state.is_empty():
			_show_launch_error("The mission \"%s\" could not be set up. Check your content file." % _fixed_mission)
			return
		_show_battle(_opening_state.duplicate(true))
		return
	if not _definitions.get("commission_settings", {}).is_empty():
		_open_commission_hub()
		return
	_show_launch_error("The content has no commissions. " + _fixed_mission_help())


func _requires_party(mission_id: String) -> bool:
	var mission: Dictionary = _definitions.missions[mission_id]
	var encounter: Dictionary = _definitions.encounters[mission.encounter]
	return not encounter.get("party_slots", []).is_empty() and mission.get("default_party", []).is_empty()


func _fixed_mission_help() -> String:
	var ids: PackedStringArray = []
	for id in _definitions.missions:
		if not _requires_party(id):
			ids.append(id)
	if ids.is_empty():
		return "Use --mission=<id> --party=<hero,...> to select a mission and its party."
	ids.sort()
	return "Use --mission=<id> for an authored party (%s), or supply --party=<hero,...> for any mission." % ", ".join(ids)


func _standalone_setup(mission_id: String, party: Array, overrides: Dictionary) -> Dictionary:
	var encounter: Dictionary = _definitions.encounters[_definitions.missions[mission_id].encounter]
	var count: int = encounter.get("party_slots", []).size()
	if party.size() != count:
		return {
			"error": "Mission '%s' needs exactly %d party heroes; received %d." % [mission_id, count, party.size()],
			"guidance": "Use --party=<hero,...> in deployment order.",
		}
	var seen := {}
	for id in party:
		var hero := Catalog.profile(_definitions, id)
		if id.is_empty() or hero.is_empty():
			return {"error": "Unknown or empty party hero '%s'. Use character IDs in --party." % id}
		if seen.has(id):
			return {"error": "Party hero '%s' appears more than once." % id}
		if hero.get("team") != "heroes" or "commandable" not in hero.get("capabilities", []):
			return {"error": "Party member '%s' is not a commandable hero." % id}
		for placement in encounter.placements:
			if placement.id == id:
				return {"error": "Party hero '%s' conflicts with an encounter placement." % id}
		seen[id] = true
	for id in overrides:
		if id not in party:
			return {"error": "Loadout hero '%s' is not in the selected party." % id}
	var kits := {}
	if not overrides.is_empty():
		var errors := Catalog.validate_playtest_progression(_definitions)
		if not errors.is_empty():
			return {"error": "Cannot use --loadout with this content: " + "; ".join(errors)}
		for id in overrides:
			var result := Progression.playtest_kit(_definitions, id, overrides[id], _uses_builtin_catalog)
			if result.has("error"):
				return result
			kits[id] = result.kit
	var state := Rules.open_mission(_definitions, mission_id, party)
	if state.is_empty():
		return {"error": "Mission '%s' could not be set up with that party. Check the content." % mission_id}
	if not kits.is_empty():
		state["_guild"] = Catalog.FrozenCatalog.new({"kits": kits})
		for id in kits:
			state.orders[id] = kits[id].default_order
	return {"state": state}


func configure_launch(args: PackedStringArray) -> void:
	assert(not is_inside_tree(), "Set launch options before adding the scene.")
	_launch_args = args.duplicate()


func configure_profile_path(path: String) -> void:
	assert(not is_inside_tree(), "Set the profile path before adding the scene.")
	_profile_path = path
	_profile_path_configured = true


func current_screen() -> String:
	return _screen


func selected_recruits() -> Array:
	return _picked_recruits.duplicate()


func battle_snapshot() -> Dictionary:
	return _state.duplicate(true) if _screen == "battle" else {}


func _read_launch_options(args: PackedStringArray) -> Dictionary:
	var launch := {"content": "", "mission": "", "storybook": false, "loadouts": {}}
	var seen: Dictionary = {}
	for arg in args:
		var key := arg.get_slice("=", 0).trim_prefix("--")
		if arg.begins_with("--") and key == "storybook":
			if arg != "--storybook" or launch.storybook:
				return {"error": "Use --storybook once, without a value."}
			launch.storybook = true
			continue
		if arg.begins_with("--") and key == "test-ui":
			return {"error": "--test-ui is no longer supported. Launch without it to use the battle book."}
		if arg.begins_with("--") and key == "fixed-outings":
			return {"error": "--fixed-outings is no longer supported. Launch a commission or standalone mission."}
		if not arg.begins_with("--") or key not in ["content", "mission", "party", "loadout"]:
			continue
		var value := arg.substr(arg.find("=") + 1) if "=" in arg else ""
		if value.strip_edges().is_empty() or (key != "loadout" and seen.has(key)):
			return {"error": "Use --%s=<value> once, with a nonempty value." % key}
		if key == "party":
			launch.party = Array(value.split(",", true))
		elif key == "loadout":
			var parts := value.split(":", true)
			if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
				return {"error": "Use --loadout=hero:offense=id,utility=id,order=id (fields optional)."}
			var hero: String = parts[0]
			if launch.loadouts.has(hero):
				return {"error": "Loadout for '%s' was supplied more than once." % hero}
			var fields := {}
			for assignment in parts[1].split(",", true):
				var pair := assignment.split("=", true)
				if pair.size() != 2 or pair[0] not in ["offense", "utility", "order"] or pair[1].is_empty() or fields.has(pair[0]):
					return {"error": "Invalid or duplicate loadout slot or order field '%s' for '%s'; use offense, utility, or order with a nonempty ID." % [assignment, hero]}
				fields[pair[0]] = pair[1]
			launch.loadouts[hero] = fields
		else:
			launch[key] = value
		seen[key] = true
	if launch.mission.is_empty() and (launch.has("party") or not launch.loadouts.is_empty()):
		return {"error": "--party and --loadout require --mission=<id>."}
	return launch


func _show_launch_error(message: String, guidance := "") -> void:
	printerr("Could not start the game: " + message + ("" if guidance.is_empty() else " " + guidance))
	_screen = "error"
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	var notice := DiagnosticBookPage.new()
	var page := _book_page("error", -1.0, notice)
	notice.heading(page, "Could not start the game", "Check your launch options and try again.", true)
	notice.launch_detail(page, "LaunchErrorText", message + ("" if guidance.is_empty() else "\n" + guidance))


func _book_page(screen: String, gutter := -1.0, book: GuildBookPage = null) -> VBoxContainer:
	_clear_terminal_replay()
	# Interstitial pages and results keep the last battle's music until the
	# player actually returns to the guild. The initial reports remain main.
	if screen not in ["routes", "debrief", "result"]:
		_music.set_context("main")
	if _screen == "petitions" and is_instance_valid(_screen_root):
		var scroll := _screen_root.find_child("PetitionScroll", true, false) as ScrollContainer
		if scroll != null:
			_petition_scroll_position = scroll.scroll_vertical
	_screen = screen
	if is_instance_valid(_screen_root):
		remove_child(_screen_root)
		_screen_root.queue_free()
	_book = GuildBookPage.new() if book == null else book
	_book.name = screen.to_pascal_case() + "Screen"
	_screen_root = _book
	add_child(_book)
	return _book.build(gutter)


func _book_heading(page: Control, title: String, detail: String,
		link_name := "", link_text := "", action := Callable()) -> void:
	var head := _book.row(page, 20)
	var copy := _book.stack(head, 3)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_book.text(copy, title, 45, GuildBookPage.INK, "display")
	if not detail.is_empty():
		var context := _book.text(copy, detail, 16, GuildBookPage.SUBTLE)
		context.max_lines_visible = 2
		context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		context.tooltip_text = detail
	if action.is_valid():
		var link := _book.button(head, link_name, link_text, "QuietButton")
		link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		link.pressed.connect(action)
	_book.rule(page)


func _open_commission_hub(board_refresh_failed := false) -> void:
	_commission = {}
	_picked_recruits.clear()
	_run = {}
	_state = {}
	print_verbose("Loading the guild profile.")
	_guild_profile = {} if _profile_path_configured else GuildProfile.migrate_location(_profile_path)
	if _guild_profile.is_empty():
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
	var notice := DiagnosticBookPage.new()
	var page := _book_page("profile_error", -1.0, notice)
	notice.heading(page, "Could not open the guild", "The saved profile hasn’t been changed.")
	notice.error_detail(page, "ProfileErrorText", message)
	notice.file_detail(page, "ProfilePath", "Check the guild profile file and try again:",
		ProjectSettings.globalize_path(_profile_path))
	notice.primary_action(page, "ReloadGuild", "Reload profile", _open_commission_hub)


func _show_guild_creation(after_missing_profile := false) -> void:
	var opening := GuildCreationPage.new()
	var page := _book_page("guild_creation", 0.5, opening)
	opening.populate(page, str(ProjectSettings.get_setting("application/config/name")),
		_destination_plate("wrong_side_of_the_door"), after_missing_profile, _create_guild)


func _create_guild(guild_name: String) -> String:
	print_verbose("Creating a guild profile.")
	var created := GuildProfile.create(_profile_path, guild_name, randi()) if _profile_path_configured \
		else GuildProfile.create_default(_profile_path, guild_name, randi())
	if created.has("error"):
		print_verbose("Could not create the guild profile: %s" % created.error)
		return str(created.error)
	_guild_profile = created
	print_verbose("Guild profile created.")
	if not _begin_practice():
		_show_commissions()
	return ""


func can_replay_practice() -> bool:
	return _screen == "commissions" and _practice_available()


func replay_practice() -> void:
	if can_replay_practice():
		_begin_practice()


func _practice_available() -> bool:
	return _uses_builtin_catalog and not _guild_profile.is_empty() and not _guild_profile.has("error") \
		and _commission.is_empty() and _run.is_empty() and _practice == null


func _begin_practice() -> bool:
	if not _practice_available():
		return false
	print_verbose("Opening the Founders’ Drill.")
	var opening := PracticeEncounter.open()
	if opening.is_empty():
		print_verbose("The Founders’ Drill could not be opened.")
		return false
	_practice = PracticeLesson.new()
	_show_battle(opening)
	var orders := _storybook_page.find_child("StandingOrders", true, false) as Button
	orders.grab_focus()
	return true


func _leave_practice(reason: String) -> void:
	if _screen != "battle" or _practice == null:
		return
	if reason == "completed" and _ongoing():
		return
	print_verbose("Leaving the Founders’ Drill (%s); guild profile unchanged." % reason)
	_practice = null
	_practice_instructions = null
	_show_commissions()
	_state = {}
	_planned_state = {}
	_plan = {}
	_last_events.clear()


func _show_commissions(board_refresh_failed := false) -> void:
	var board := CommissionBoardPage.new()
	var page := _book_page("commissions", -1.0, board)
	var postings: Array[Dictionary] = []
	for offer: Dictionary in Commissions.board(_definitions, int(_guild_profile.board_seed)):
		postings.append({
			"title": _mission_title_for(offer.destination_id),
			"painting": _destination_plate(offer.destination_id),
			"length": offer.length,
			"description": offer.description,
			"choose": _select_commission.bind(offer),
		})
	board.populate(page, {
		"guild_name": _guild_profile.name,
		"refresh_failed": board_refresh_failed,
		"balance": GuildProfile.balance(_guild_profile),
		"receipt": _receipt_summary(_guild_profile.get("last_receipt", {})) if _uses_builtin_catalog else "",
		"petitions": _show_petitions if _uses_builtin_catalog else Callable(),
		"replay_practice": replay_practice if can_replay_practice() else Callable(),
		"postings": postings,
	})


func _select_commission(offer: Dictionary) -> void:
	_commission = offer
	var mission: Dictionary = _definitions.missions[offer.destination_id]
	_adventure = {"roster": _definitions.commission_settings.recruitment_roster,
		"party_size": _definitions.encounters[mission.encounter].party_slots.size()}
	if _uses_builtin_catalog:
		_picked_recruits.clear()
		_loadouts.clear()
		_selected_hero_id = ""
		_recruitment_folio = "recruits"
		_guild_feedback = ""
		_show_recruitment()
		return
	_show_guild()


func _receipt_summary(receipt: Dictionary) -> String:
	return ReceiptCopy.summary(receipt)


func _show_petitions(focus_name := "") -> void:
	var page := _book_page("petitions")
	var petitions := GuildProfile.petitions(_definitions, _guild_profile)
	var rows := GuildPetitionViewModel.rows(_definitions, petitions)
	var filter_options: Array = [{"id": "", "label": "All"}]
	var hero_options: Array = []
	var seen_heroes: Array = []
	var specs: Dictionary = _definitions.get("guild_progression", {}).get("petitions", {})
	var visible_rows: Array = []
	var selected_visible := false
	for index in rows.size():
		var row: Dictionary = rows[index]
		var petition: Dictionary = petitions[index]
		var hero_id := str(petition.get("hero_id", ""))
		for key in ["hero_id", "grant_kind", "recipient_label", "missing_prerequisites",
				"missing_prerequisite_labels", "recipient_locked", "affordable"]:
			if petition.has(key):
				row[key] = petition[key]
		row["prerequisites"] = specs.get(str(row.id), {}).get("prerequisites", [])
		row["purchased"] = str(row.id) in _guild_profile.get("purchased_ids", [])
		if not hero_id.is_empty() and hero_id not in seen_heroes:
			seen_heroes.append(hero_id)
			hero_options.append({"id": hero_id, "label": str(petition.get("recipient_label", hero_id))})
		if _petition_hero_filter.is_empty() or hero_id == _petition_hero_filter:
			visible_rows.append(row)
			if str(row.id) == _petition_selected:
				selected_visible = true
	var ordered_options := GuildPetitionViewModel.ordered_hero_options(hero_options,
		_guild_profile.get("recruited_ids", []))
	filter_options.append_array(ordered_options)
	visible_rows = GuildPetitionViewModel.ordered_rows(visible_rows, ordered_options)
	if not selected_visible:
		_petition_selected = str(visible_rows[0].id) if not visible_rows.is_empty() else ""
	var script = load("res://presentation/book/guild_petitions_page.gd")
	if script == null:
		_show_launch_error("Guild petitions page is missing.")
		return
	_petition_page = script.new()
	_petition_page.back_requested.connect(_back_from_petitions)
	_petition_page.petition_selected.connect(_select_petition)
	_petition_page.purchase_requested.connect(_purchase_petition)
	_petition_page.filter_changed.connect(_filter_petitions)
	_petition_page.build(_book, page, {
		"balance": GuildProfile.balance(_guild_profile),
		"return_summary": _receipt_summary(_guild_profile.get("last_receipt", {})),
		"selected_id": _petition_selected, "feedback": _guild_feedback, "petitions": visible_rows,
		"hero_filter": _petition_hero_filter, "hero_filter_options": filter_options,
	})
	_focus_presenter(_petition_page, focus_name if not focus_name.is_empty() else "Petition_" + _petition_selected)
	var scroll := _petition_page.focus_control("PetitionScroll") as ScrollContainer
	_restore_petition_scroll(scroll, _screen_root, _petition_scroll_position, _petition_selected)


func _restore_petition_scroll(scroll: ScrollContainer, page: Control, position: int, selected_id: String) -> void:
	if scroll == null:
		return
	var opening_position := scroll.scroll_vertical
	var opening_input := _petition_input_revision
	var tree := get_tree()
	# Let the rebuilt register finish layout, but yield to any newer interaction.
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(page) or page != _screen_root or _screen != "petitions" \
			or not is_instance_valid(scroll) or scroll.scroll_vertical != opening_position \
			or _petition_input_revision != opening_input:
		return
	var bar := scroll.get_v_scroll_bar()
	var selected := scroll.find_child("Petition_" + selected_id, true, false) as Control
	if selected != null:
		# Convert the row to content coordinates so restoration and reveal are one write.
		var top := opening_position + selected.get_global_rect().position.y - scroll.get_global_rect().position.y
		var bottom := ceili(top + selected.size.y - bar.page)
		position = clampi(position, mini(bottom, floori(top)), floori(top))
	scroll.scroll_vertical = clampi(position, 0, maxi(0, int(bar.max_value - bar.page)))


func _back_from_petitions() -> void:
	_show_commissions()
	var petitions := _screen_root.find_child("Petitions", true, false) as Control
	if petitions != null:
		petitions.grab_focus()


func _filter_petitions(hero_id: String) -> void:
	if not hero_id.is_empty():
		var found := false
		for petition in GuildProfile.petitions(_definitions, _guild_profile):
			if str(petition.get("hero_id", "")) == hero_id:
				found = true
				break
		if not found:
			return
	_petition_hero_filter = hero_id
	_guild_feedback = ""
	_show_petitions("PetitionHeroFilter")


func _select_petition(id: String) -> void:
	_petition_selected = id
	_guild_feedback = ""
	_show_petitions("Petition_" + id)


func _purchase_petition(id: String) -> void:
	print_verbose("Purchasing guild petition %s." % id)
	var updated := GuildProfile.purchase(_profile_path, _guild_profile, _definitions, id)
	if updated.has("error"):
		_guild_feedback = "Purchase not saved: " + str(updated.error)
		print_verbose(_guild_feedback)
	else:
		_guild_profile = updated
		_guild_feedback = "Petition purchased."
		print_verbose("Guild petition purchased.")
	_petition_selected = id
	_show_petitions("PurchasePetition_" + id if updated.has("error") else "Petition_" + id)


func _hero_row(id: String) -> Dictionary:
	var hero := Catalog.profile(_definitions, id)
	var portrait := GuildBookArt.class_portrait(_portrait_identity(id))
	return {"id": id, "name": str(hero.get("label", id)), "portrait": portrait,
		"summary": _recruit_summary(hero, id), "selected": id in _picked_recruits}


func _recruit_summary(hero: Dictionary, id: String) -> String:
	var summary := str(hero.get("description", ""))
	if not summary.is_empty():
		return summary
	var loadout: Dictionary = _loadouts.get(id, {})
	if loadout.is_empty():
		loadout = GuildProfile.default_loadout(_definitions, _guild_profile, id)
	var labels := PackedStringArray()
	for slot in ["offense", "utility"]:
		var ability_id: String = loadout.get("slots", {}).get(slot, "")
		var ability: Dictionary = _definitions.abilities.get(ability_id, {})
		if not ability.is_empty():
			labels.append(str(ability.get("label", ability_id)))
	return " · ".join(labels)


func _loadout_for(id: String) -> Dictionary:
	if not _loadouts.has(id):
		_loadouts[id] = GuildProfile.default_loadout(_definitions, _guild_profile, id).duplicate(true)
	return _loadouts[id]


func _loadout_compatible(id: String) -> bool:
	var loadout := _loadout_for(id)
	for option in GuildProfile.order_options(_definitions, _guild_profile, id, loadout):
		if str(option.id) == str(loadout.get("order_id", "")):
			return bool(option.compatible)
	return false


func _option_row(id: String, selected: bool, enabled := true, reason := "", order := false) -> Dictionary:
	var definition: Dictionary = _definitions.get("orders" if order else "abilities", {}).get(id, {})
	return {"id": id, "label": str(definition.get("label", id)),
		"help": str(definition.get("help", definition.get("description", ""))), "selected": selected,
		"enabled": enabled, "reason": reason}


func _show_recruitment(focus_name := "") -> void:
	var folio_scroll_name := "LoadoutScroll" if _recruitment_folio == "loadout" else "RecruitScroll"
	var previous_scroll: ScrollContainer
	if _screen == "guild":
		previous_scroll = _screen_root.find_child(folio_scroll_name, true, false) as ScrollContainer
	var folio_position := previous_scroll.scroll_vertical if previous_scroll != null else 0
	var book := GuildBoundPage.new()
	var page := _book_page("guild", -1.0, book)
	var available: Array = GuildProfile.roster(_definitions, _guild_profile)
	var heroes: Array = []
	var party: Array = []
	for id in available:
		heroes.append(_hero_row(str(id)))
	for id in _picked_recruits:
		party.append(_hero_row(str(id)))
	var offense: Array = []
	var utility: Array = []
	var orders: Array = []
	if _selected_hero_id in available:
		var loadout := _loadout_for(_selected_hero_id)
		var slots: Dictionary = loadout.get("slots", {})
		var options: Dictionary = GuildProfile.slot_options(_definitions, _guild_profile, _selected_hero_id)
		for id in options.get("offense", []):
			offense.append(_option_row(str(id), str(slots.get("offense", "")) == str(id)))
		for id in options.get("utility", []):
			utility.append(_option_row(str(id), str(slots.get("utility", "")) == str(id)))
		for option in GuildProfile.order_options(_definitions, _guild_profile, _selected_hero_id, loadout):
			var missing: Array = option.get("missing_abilities", [])
			var names := PackedStringArray()
			for ability_id in missing:
				names.append("Bonk" if ability_id == "healer_bonk" else
					str(_definitions.abilities.get(ability_id, {}).get("label", ability_id)))
			var reason := "" if missing.is_empty() else "Requires: " + ", ".join(names)
			orders.append(_option_row(str(option.id), str(loadout.get("order_id", "")) == str(option.id),
				bool(option.compatible), reason, true))
	var blocked := ""
	if _picked_recruits.size() != int(_adventure.party_size):
		blocked = "Choose %d recruits." % int(_adventure.party_size)
	else:
		for id in _picked_recruits:
			if not _loadout_compatible(str(id)):
				blocked = "Choose a compatible standing order for %s." % _hero_row(str(id)).name
				break
	var script = load("res://presentation/book/guild_recruitment_page.gd")
	if script == null:
		_show_launch_error("Guild recruitment page is missing.")
		return
	_recruitment_page = script.new()
	_recruitment_page.back_requested.connect(_back_from_recruitment)
	_recruitment_page.recruit_toggled.connect(_guild_toggle_recruit)
	_recruitment_page.hero_edit_requested.connect(_edit_hero)
	_recruitment_page.recruit_list_requested.connect(_recruit_list)
	_recruitment_page.reorder_requested.connect(_guild_move_recruit)
	_recruitment_page.offense_requested.connect(_change_offense)
	_recruitment_page.utility_requested.connect(_change_utility)
	_recruitment_page.order_requested.connect(_change_guild_order)
	_recruitment_page.depart_requested.connect(_start_guild_commission)
	_recruitment_page.build(book, page, {
		"commission": _commission, "commission_title": _mission_title_for(_commission.destination_id),
		"guild_name": str(_guild_profile.name), "mission_count": int(_commission.length),
		"party_size": int(_adventure.party_size), "party": party, "heroes": heroes,
		"selected_hero_id": _selected_hero_id, "folio": _recruitment_folio,
		"offense": offense, "utility": utility, "orders": orders,
		"can_depart": blocked.is_empty(), "depart_blocked_reason": blocked, "feedback": _guild_feedback,
	})
	var focused := _focus_presenter(_recruitment_page, focus_name if not focus_name.is_empty() else
		("Recruit_" + str(available[0]) if not available.is_empty() else "BackToCommissions"))
	var folio_scroll := book.find_child(folio_scroll_name, true, false) as ScrollContainer
	if folio_scroll != null and focused != null and folio_scroll.is_ancestor_of(focused):
		_reveal_rebuilt_folio_focus(folio_scroll, focused, folio_position)


func _reveal_rebuilt_folio_focus(scroll: ScrollContainer, focused: Control, position: int) -> void:
	# Follow-focus runs before the rebuilt folio has bounds.
	await get_tree().process_frame
	if is_instance_valid(scroll) and scroll.is_inside_tree() \
			and is_instance_valid(focused) and focused.has_focus():
		_restore_book_scroll(scroll, position, focused)


func _focus_presenter(presenter, control_name: String) -> Control:
	var control: Control = presenter.focus_control(control_name)
	if control is BaseButton and control.disabled:
		if control_name.begins_with("PartyEarlier_"):
			control = presenter.focus_control(control_name.replace("Earlier_", "Later_"))
		elif control_name.begins_with("PartyLater_"):
			control = presenter.focus_control(control_name.replace("Later_", "Earlier_"))
		else:
			control = presenter.focus_control("RecruitList")
	if control is BaseButton and control.disabled:
		control = null
	if control != null:
		control.grab_focus()
	return control


func _guild_toggle_recruit(id: String) -> void:
	if id in _picked_recruits:
		_picked_recruits.erase(id)
	elif id in GuildProfile.roster(_definitions, _guild_profile) and _picked_recruits.size() < int(_adventure.party_size):
		_picked_recruits.append(id)
	_show_recruitment("Recruit_" + id)


func _back_from_recruitment() -> void:
	_commission = {}
	_picked_recruits.clear()
	_loadouts.clear()
	_run = {}
	_selected_hero_id = ""
	_recruitment_folio = "recruits"
	_guild_feedback = ""
	_show_commissions()


func _guild_move_recruit(id: String, delta: int) -> void:
	var index := _picked_recruits.find(id)
	var target := index + delta
	if index >= 0 and absi(delta) == 1 and target >= 0 and target < _picked_recruits.size():
		_picked_recruits.remove_at(index)
		_picked_recruits.insert(target, id)
	var direction := "Earlier" if delta < 0 else "Later"
	_show_recruitment("Party%s_%s" % [direction, id])


func _edit_hero(id: String) -> void:
	if id not in _picked_recruits:
		return
	_selected_hero_id = id
	_recruitment_folio = "loadout"
	_show_recruitment("RecruitList")


func _recruit_list() -> void:
	_recruitment_folio = "recruits"
	_show_recruitment("EditHero_" + _selected_hero_id)


func _save_loadout_preferences() -> bool:
	var party_loadouts: Dictionary = {}
	for id in _picked_recruits:
		party_loadouts[id] = _loadout_for(str(id))
		if not _loadout_compatible(str(id)):
			_guild_feedback = "Choose a compatible standing order for %s before saving." % _hero_row(str(id)).name
			return false
	print_verbose("Saving guild loadout preferences.")
	var updated := GuildProfile.save_loadouts(_profile_path, _guild_profile, _definitions, party_loadouts)
	if updated.has("error"):
		_guild_feedback = "Preferences not saved: " + str(updated.error)
		print_verbose(_guild_feedback)
		return false
	_guild_profile = updated
	_guild_feedback = ""
	print_verbose("Guild loadout preferences saved.")
	return true


func _change_offense(id: String, ability_id: String) -> void:
	_change_slot(id, "offense", ability_id)


func _change_utility(id: String, ability_id: String) -> void:
	_change_slot(id, "utility", ability_id)


func _change_slot(id: String, slot_id: String, ability_id: String) -> void:
	if id != _selected_hero_id or id not in _picked_recruits or slot_id not in ["offense", "utility"] \
			or ability_id not in GuildProfile.slot_options(_definitions, _guild_profile, id).get(slot_id, []):
		return
	_loadout_for(id).slots[slot_id] = ability_id
	var compatible := _loadout_compatible(id)
	if compatible:
		_save_loadout_preferences()
	else:
		_guild_feedback = "Choose a compatible standing order before saving."
	var focus_name := "Utility_" + ability_id if slot_id == "utility" and compatible \
		else "Order_" + str(_loadout_for(id).get("order_id", ""))
	if not compatible:
		for option in GuildProfile.order_options(_definitions, _guild_profile, id, _loadout_for(id)):
			if bool(option.compatible):
				focus_name = "Order_" + str(option.id)
				break
	_show_recruitment(focus_name)


func _change_guild_order(id: String, order_id: String) -> void:
	if id != _selected_hero_id:
		return
	for option in GuildProfile.order_options(_definitions, _guild_profile, id, _loadout_for(id)):
		if str(option.id) == order_id and option.compatible:
			_loadout_for(id)["order_id"] = order_id
			_save_loadout_preferences()
			_show_recruitment("RecruitList")
			return


func _start_guild_commission() -> void:
	if _picked_recruits.size() != int(_adventure.party_size):
		return
	for id in _picked_recruits:
		if not _loadout_compatible(str(id)):
			_show_recruitment()
			return
	if not _save_loadout_preferences():
		_show_recruitment()
		return
	var party_loadouts: Dictionary = {}
	for id in _picked_recruits:
		party_loadouts[id] = _loadout_for(str(id))
	var started := Adventure.start_guild_commission(_definitions, _commission, _picked_recruits, _guild_profile, party_loadouts)
	if started.get("phase") != "route":
		_guild_feedback = "The commission could not be started. Check your company and try again."
		_show_recruitment()
		return
	_run = started
	_return_seed = null
	_return_error = ""
	_return_conflict = false
	_show_routes()


func _show_guild(focus_name := "") -> void:
	_state = {}
	var previous_scroll := find_child("RecruitScroll", true, false) as ScrollContainer if _screen == "guild" else null
	var scroll_position := previous_scroll.scroll_vertical if previous_scroll != null else 0
	var previous_slots := find_child("DeploymentScroll", true, false) as ScrollContainer if _screen == "guild" else null
	var slot_position := previous_slots.scroll_vertical if previous_slots != null else 0
	var page := _book_page("guild", 0.64)
	_book_heading(page, "Choose your company",
		"%s  ·  %s  ·  %d missions" % [
			_guild_profile.name, _mission_title_for(_commission.destination_id), _commission.length],
		"BackToCommissions", "Commission board", _open_commission_hub)
	var leaves := _book.spread(page, 0.64, 42)
	var roster := leaves[0]
	_book.text(roster, "Available recruits",
		28, GuildBookPage.INK, "display")
	_book.text(roster, "Take %d recruits. Each round, you command one hero; the others follow standing orders." % _adventure.party_size,
		15, GuildBookPage.SUBTLE)
	var scroll := _book.scroll(roster, "RecruitScroll")
	scroll.follow_focus = false
	var recruits := GridContainer.new()
	recruits.columns = 2
	recruits.add_theme_constant_override("h_separation", 13)
	recruits.add_theme_constant_override("v_separation", 11)
	scroll.add_child(recruits)
	recruits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for recruit_id in _adventure.roster:
		_build_recruit(recruits, recruit_id)
	var marching := leaves[1]
	_book.text(marching, "Deployment order", 30, GuildBookPage.INK, "display")
	_book.text(marching, "The top hero acts first. This order also sets where your party starts.", 15, GuildBookPage.SUBTLE)
	var count := _book.text(marching, "%d of %d selected" % [_picked_recruits.size(), _adventure.party_size],
		15, GuildBookPage.FOREST)
	count.name = "PartyCount"
	_book.rule(marching)
	var deployment_scroll := _book.scroll(marching, "DeploymentScroll")
	var slots := _book.stack(deployment_scroll, 8)
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for slot in range(_adventure.party_size):
		_build_party_slot(slots, slot)
	if _adventure.party_size <= 3:
		var landscape := _destination_plate(str(_commission.destination_id))
		if landscape != null:
			_book.plate(marching, landscape, Vector2(0, 130))
			_book.text(marching, _mission_title_for(_commission.destination_id), 17,
				GuildBookPage.SUBTLE, "italic")
	_book.rule(marching)
	var start := _book.button(marching, "StartAdventure", "Read field reports", "ClothButton")
	_book.set_disabled(start, _picked_recruits.size() != _adventure.party_size)
	start.pressed.connect(_start_adventure)
	var focus: Control
	if not focus_name.is_empty():
		focus = find_child(focus_name, true, false) as Control
		if focus is BaseButton and focus.disabled and focus_name.begins_with("Party"):
			var opposite := focus_name.replace("Earlier_", "Later_") if "Earlier_" in focus_name else focus_name.replace("Later_", "Earlier_")
			focus = find_child(opposite, true, false) as Button
		if focus is BaseButton and not focus.disabled:
			focus.grab_focus()
	else:
		var first_action := "Recruit_" + str(_adventure.roster[0])
		focus = find_child(first_action, true, false) as Control
		if focus != null:
			focus.grab_focus()
	_restore_book_scroll.call_deferred(scroll, scroll_position, focus)
	_restore_book_scroll.call_deferred(deployment_scroll, slot_position, focus)


func _restore_book_scroll(scroll: ScrollContainer, position: int, focus: Control) -> void:
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	scroll.scroll_vertical = position
	if scroll.follow_focus and is_instance_valid(focus) and focus.has_focus() and scroll.is_ancestor_of(focus):
		scroll.ensure_control_visible(focus)


func _build_recruit(parent: GridContainer, id: String) -> void:
	var profile := Catalog.profile(_definitions, id)
	var picked := id in _picked_recruits
	var sheet := _book.inset(parent, Color("#dee0c5") if picked else GuildBookPage.PALE,
		Color("#7d8d6b") if picked else GuildBookPage.RULE, 8, 8)
	sheet.name = "RecruitCard_" + id
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry := _book.row(sheet, 10)
	var portrait := GuildBookArt.class_portrait(_portrait_identity(id))
	if portrait != null:
		var photo := _book.plate(entry, portrait, Vector2(112, 116), "portrait")
		photo.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var copy := _book.stack(entry, 4)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_book.text(copy, profile.label, 23, GuildBookPage.INK, "display")
	var class_text := _portrait_subtitle(id, str(profile.label))
	var stats := "%d HP" % profile.max_hp
	if not class_text.is_empty():
		stats = class_text + "  ·  " + stats
	_book.text(copy, stats, 13, GuildBookPage.FOREST)
	var abilities: PackedStringArray = []
	for ability_id in profile.abilities:
		abilities.append(_definitions.abilities[ability_id].label)
	_book.text(copy, ", ".join(abilities), 13)
	var order: Dictionary = _definitions.orders.get(profile.get("default_order", ""), {})
	_book.text(copy, "Order: " + str(order.get("label", "None")), 13, GuildBookPage.SUBTLE)
	var toggle := _book.button(copy, "Recruit_" + id, "Remove" if picked else "Recruit",
		"Button" if picked else "ClothButton")
	toggle.custom_minimum_size.y = 34
	toggle.set_meta("recruit_id", id)
	toggle.custom_minimum_size.x = 95
	toggle.tooltip_text = ("Remove %s from the party" if picked else "Recruit %s") % profile.label
	toggle.accessibility_name = toggle.tooltip_text
	_book.set_disabled(toggle, not picked and _picked_recruits.size() == _adventure.party_size)
	toggle.pressed.connect(_toggle_recruit.bind(id))
	toggle.focus_entered.connect(_keep_recruit_card_visible.bind(sheet, toggle))
	var description: String = profile.get("description", "")
	if not description.is_empty():
		toggle.tooltip_text += "\n" + description
		toggle.accessibility_description = description


func _keep_recruit_card_visible(card: Control, toggle: Button) -> void:
	# On a page rebuild, wait for the grid to be sized and the scroll position restored.
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(toggle) or not toggle.has_focus():
		return
	var scroll := card.get_parent().get_parent() as ScrollContainer
	var pane := scroll.get_global_rect()
	var sheet := card.get_global_rect()
	if sheet.position.y < pane.position.y:
		scroll.scroll_vertical += floori(sheet.position.y - pane.position.y)
	elif sheet.end.y > pane.end.y:
		scroll.scroll_vertical += ceili(sheet.end.y - pane.end.y)


func _build_party_slot(parent: VBoxContainer, slot: int) -> void:
	var line := _book.row(parent, 6)
	var number := _book.text(line, "%02d" % (slot + 1), 24, GuildBookPage.RUST, "display")
	number.custom_minimum_size.x = 29
	var id: String = _picked_recruits[slot] if slot < _picked_recruits.size() else ""
	var profile := Catalog.profile(_definitions, id) if not id.is_empty() else {}
	var name_text: String = profile.get("label", "Open place")
	var portrait := GuildBookArt.class_portrait(_portrait_identity(id))
	if portrait != null:
		_book.plate(line, portrait, Vector2(39, 39), "portrait")
	var label := _book.text(line, name_text, 19, GuildBookPage.SUBTLE if id.is_empty() else GuildBookPage.INK, "display")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size.y = 49
	_book.rule(parent)
	if id.is_empty():
		return
	for delta in [-1, 1]:
		var direction := "Earlier" if delta < 0 else "Later"
		var button := _book.button(line, "Party%s_%s" % [direction, id], direction)
		button.add_theme_font_size_override("font_size", 13)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.tooltip_text = "%s goes %s" % [name_text, direction.to_lower()]
		button.accessibility_name = button.tooltip_text
		_book.set_disabled(button, slot + delta < 0 or slot + delta >= _picked_recruits.size())
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


func _mission_title_for(mission_id: String) -> String:
	return _definitions.missions[mission_id].title


func _destination_plate(mission_id: String) -> Texture2D:
	return GuildBookArt.destination(mission_id) if _uses_builtin_catalog else null


func _report_plate(immediate_id: String) -> Texture2D:
	return GuildBookArt.report(immediate_id) if _uses_builtin_catalog else null


func _portrait_identity(character_id: String) -> String:
	# This is a declaration by the character, not an inherited rules class.
	return str(_definitions.characters.get(character_id, {}).get("guild_portrait", ""))


func _portrait_subtitle(character_id: String, character_label: String) -> String:
	var class_label := GuildBookArt.class_label(_portrait_identity(character_id))
	return "" if class_label == character_label else class_label


func _start_adventure() -> void:
	_run = Adventure.start_commission(_definitions, _commission, _picked_recruits)
	if _run.get("phase") == "route":
		_show_routes()


func _show_routes() -> void:
	var reports_page := FieldReportsPage.new()
	var page := _book_page("routes", -1.0, reports_page)
	var next := int(_run.mission_index) + 1
	var total := Adventure.mission_count(_run)
	var penultimate := next == total - 1
	var reports: Array[Dictionary] = []
	for report: Dictionary in _run.reports:
		var kind: Dictionary = _definitions.get("mission_kinds", {}).get(report.get("hint_kind", ""), {})
		reports.append({
			"description": report.description,
			"clue": report.hint_text,
			"kind_label": "" if penultimate else str(kind.get("label", "")),
			"sketch": _report_plate(str(report.mission_id)),
			"take": _choose_route.bind(str(report.mission_id)),
		})
	reports_page.populate(page, "%s  ·  Mission %d of %d" % [_mission_title_for(_run.destination_id), next, total],
		penultimate, reports)


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
	var next_mission := ""
	if _run.phase == "ready":
		next_mission = str(_run.destination_id)
	var chosen: Dictionary = _run.get("chosen_reward", {})
	var offers: Array[Dictionary] = []
	if pending:
		for offer: Dictionary in _run.reward_offers:
			offers.append(_debrief_reward(offer))
	var book := MissionDebriefPage.new()
	var page := _book_page("debrief", -1.0, book)
	book.populate(page, {
		"mission": _mission_title_for(result.mission_id),
		"pending": pending,
		"offers": offers,
		"claimed": {} if chosen.is_empty() else _debrief_reward(chosen),
		"receipt": _receipt_summary(Adventure.receipt(_run)) if _uses_builtin_catalog else "",
		"carry": _debrief_carry_lines(pending),
		"scout_note": str(_run.get("scout_note", "")),
		"next_title": "" if next_mission.is_empty() else _mission_title_for(next_mission),
		"next_is_fork": _run.phase == "route",
		"can_continue": _run.phase in ["ready", "route"],
		"advance": _continue_after_debrief,
	})


func _debrief_reward(offer: Dictionary) -> Dictionary:
	var hero_id: String = offer.hero_id
	var upgrade_id: String = offer.upgrade_id
	var upgrade: Dictionary = _definitions.upgrades[upgrade_id]
	var hero := Catalog.profile(_definitions, hero_id)
	var owned := int(_run.upgrades_by_id.get(hero_id, {}).get(upgrade_id, 0))
	return {
		"hero_id": hero_id, "upgrade_id": upgrade_id,
		"hero_name": hero.label, "class_name": _portrait_subtitle(hero_id, str(hero.label)),
		"rarity": upgrade.rarity, "label": upgrade.label, "description": upgrade.description,
		"progress": "%d of %d acquired  ·  %d remaining" % [owned, upgrade.cap, int(upgrade.cap) - owned],
		"portrait": GuildBookArt.class_portrait(_portrait_identity(hero_id)),
		"art": GuildBookArt.upgrade(upgrade_id) if _uses_builtin_catalog else null,
		"claim": _claim_reward.bind(hero_id, upgrade_id),
	}


func _claim_reward(hero_id: String, upgrade_id: String) -> void:
	if _screen != "debrief" or _run.phase != "reward":
		return
	var chosen := Adventure.choose_reward(_run, hero_id, upgrade_id)
	if chosen.phase in ["ready", "route"]:
		_run = chosen
		_show_debrief()


func _continue_after_debrief() -> void:
	if _screen == "debrief":
		if _run.phase == "route":
			_show_routes()
		elif _run.phase == "ready":
			_begin_mission()


func _debrief_carry_lines(compact: bool) -> String:
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
		var name_text: String = before.label
		var class_text := _portrait_subtitle(str(id), name_text)
		if not class_text.is_empty():
			name_text += " (%s)" % class_text
		var line := "%s   %d/%d HP → %d/%d HP%s%s" % [
			name_text, before.hp, before.max_hp, next_hp, max_hp,
			wounds, recovery]
		line += "  ·  Order: %s" % order.get("label", "None") if compact \
			else "\nStanding order: %s" % order.get("label", "None")
		lines.append(line)
	return ("\n" if compact else "\n\n").join(lines)


func _show_result() -> void:
	var result: Dictionary = _run.last_result
	var painting := _destination_plate(str(result.mission_id))
	var image := painting if painting != null else _report_plate(str(result.mission_id))
	var book := RunResultPage.new()
	var page := _book_page("result", -1.0, book)
	book.populate(page, {
		"outcome": result.outcome,
		"outing": "Commission",
		"mission_title": _mission_title_for(str(result.mission_id)),
		"mission_text": str(result.get("text", "")),
		"image": image,
		"sketch": painting == null,
		"receipt": ReceiptCopy.rows(Adventure.receipt(_run)) if _uses_builtin_catalog else [],
		"guild_name": str(_guild_profile.get("name", "")),
		"return_error": _return_error if _uses_builtin_catalog else "",
		"conflict": _return_conflict if _uses_builtin_catalog else false,
		"return": _return_to_guild,
		"discard": _discard_conflicted_return,
	})


func _return_to_guild() -> void:
	if not _commission.is_empty():
		if _run.get("phase") != "finished" or _return_conflict:
			return
		if _uses_builtin_catalog:
			if _return_seed == null:
				_return_seed = randi()
				if _return_seed == int(_guild_profile.board_seed):
					_return_seed = int(_return_seed) ^ 1
			print_verbose("Settling guild return after %s." % _run.outcome)
			var settled := GuildProfile.settle_return(_profile_path, _guild_profile, _run, int(_return_seed))
			if settled.has("error"):
				_return_error = str(settled.error)
				var current := GuildProfile.load_profile(_profile_path)
				_return_conflict = not current.is_empty() and not current.has("error") \
					and (current.get("guild_id") != _guild_profile.get("guild_id") \
					or current.get("board_generation") != _guild_profile.get("board_generation"))
				print_verbose("Could not settle guild return: %s" % _return_error)
				_show_result()
				return
			print_verbose("Guild return settled.")
			_guild_profile = settled
			_return_error = ""
			_return_conflict = false
			_return_seed = null
			_open_commission_hub()
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


func _discard_conflicted_return() -> void:
	if not _return_conflict or _run.get("phase") != "finished":
		return
	print_verbose("Discarding an unpaid outing after a guild ledger conflict.")
	_return_error = ""
	_return_conflict = false
	_return_seed = null
	_open_commission_hub()


func _show_battle(opening: Dictionary) -> void:
	_state = opening
	var is_final: bool = _practice == null and _fixed_mission.is_empty() \
		and _run.get("phase") == "mission" \
		and int(_run.get("mission_index", -1)) == Adventure.mission_count(_run) - 1 \
		and opening.get("mission_id", "") == _run.get("destination_id", "")
	_music.set_context("destination" if is_final else "road")
	_show_storybook_battle()


func _show_storybook_battle() -> void:
	_clear_terminal_replay()
	_screen = "battle"
	if is_instance_valid(_screen_root):
		remove_child(_screen_root)
		_screen_root.queue_free()
	var page_script = load("res://presentation/battle/storybook_battle_page.gd")
	if page_script == null:
		_show_launch_error("Storybook page is missing. Restore presentation/battle/storybook_battle_page.gd.")
		return
	_storybook_page = page_script.new()
	_screen_root = _storybook_page
	add_child(_storybook_page)
	_storybook_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board = BridgeArt.new()
	_board.sound_beat.connect(_sound_effects.dispatch_beat)
	_board.set_performance_sound(_sound_effects.dispatch_performance)
	_board.name = "BridgeBoard"
	_board.focus_mode = Control.FOCUS_ALL
	var trusted_board_id: String = _state.board_id if _uses_builtin_catalog else ""
	_board.set_painting(trusted_board_id)
	_board.set_grid_visible(_grid_visible)
	_board.set_grid_labels_visible(_grid_labels_visible)
	_board.set_nameplates_visible(_nameplates_visible)
	_board.set_always_show_health_bar(_always_show_health_bar)
	_storybook_page.mount_board(_board, trusted_board_id, Vector2i(_state.width, _state.height))
	_storybook_page.set_display_options(_grid_visible, _nameplates_visible, _grid_labels_visible,
		_always_show_health_bar)
	_board_cues = null
	if trusted_board_id != "frontier_gate_board" or _state.objective.handler != "pressure_gate":
		_board_cues = BattleCues.new()
		_board_cues.name = "ObjectiveMarkers"
		_board.add_child(_board_cues)
		_board_cues.attach_to(_board)
	_board.cell_selected.connect(_select_board)
	_board.cell_hovered.connect(_inspect_board)
	_board.hover_cleared.connect(_clear_inspection)
	_board.gui_input.connect(_storybook_board_input)
	_board.focus_entered.connect(_storybook_board_focused)
	_board.focus_exited.connect(_storybook_board_unfocused)
	_storybook_page.hero_selected.connect(_storybook_select_hero)
	_storybook_page.action_selected.connect(_storybook_action)
	_storybook_page.order_selected.connect(_storybook_order)
	_storybook_page.target_selected.connect(_storybook_target)
	_storybook_page.cancel_targeting_requested.connect(_cancel_targeting)
	_storybook_page.clear_requested.connect(_clear_command)
	_storybook_page.commit_requested.connect(_commit)
	_storybook_page.restart_requested.connect(_restart_fixed)
	_storybook_page.forfeit_requested.connect(_forfeit)
	_storybook_page.grid_visibility_changed.connect(_set_grid_visible)
	_storybook_page.grid_labels_visibility_changed.connect(_set_grid_labels_visible)
	_storybook_page.nameplate_visibility_changed.connect(_set_nameplates_visible)
	_storybook_page.always_show_health_bar_changed.connect(_set_always_show_health_bar)
	_storybook_page.sound_effects_volume_changed.connect(_set_sound_effects_volume)
	_storybook_page.master_volume_changed.connect(_set_master_volume)
	_storybook_page.music_volume_changed.connect(_set_music_volume)
	if _practice != null:
		_practice_instructions = PracticeInstructions.new()
		_practice_instructions.skip_requested.connect(_leave_practice.bind("skipped"))
		_practice_instructions.continue_requested.connect(_leave_practice.bind("completed"))
		_storybook_page.mount_practice_controls(_practice_instructions)
		_storybook_page.forecast_visibility_changed.connect(_practice_forecast_visibility_changed)
	_begin_attempt()


func _practice_forecast_visibility_changed(opened: bool) -> void:
	if _practice == null:
		return
	_practice.forecast_visibility_changed(opened, _plan, _is_aiming())
	_render_storybook()


func _practice_allows_action(ability: String) -> bool:
	return _practice == null or _practice.allows_action(_state, _actor_id, ability)


func _can_change_battle_order(hero: String) -> bool:
	return _ongoing() and _find(hero).get("hp", 0) > 0 \
		and (_practice == null or _practice.allows_order(_state, hero))


func _set_grid_visible(shown: bool) -> void:
	_grid_visible = shown
	_board.set_grid_visible(shown)
	if is_instance_valid(_terminal_board):
		_terminal_board.set_grid_visible(shown)
	BattleDisplayPreferences.save_grid_visible(shown)


func _set_sound_effects_volume(value: float) -> void:
	_sound_effects.set_volume(value)


func _set_master_volume(value: float) -> void:
	BattleDisplayPreferences.save_master_volume(value)
	_sound_effects.set_master_volume(value)
	_music.set_master_volume(value)


func _set_music_volume(value: float) -> void:
	BattleDisplayPreferences.save_music_volume(value)
	_music.set_volume(value)


func _set_grid_labels_visible(shown: bool) -> void:
	_grid_labels_visible = shown
	_board.set_grid_labels_visible(shown)
	if is_instance_valid(_terminal_board):
		_terminal_board.set_grid_labels_visible(shown)
	BattleDisplayPreferences.save_grid_labels_visible(shown)


func _set_nameplates_visible(shown: bool) -> void:
	_nameplates_visible = shown
	_board.set_nameplates_visible(shown)
	if is_instance_valid(_terminal_board):
		_terminal_board.set_nameplates_visible(shown)
	BattleDisplayPreferences.save_nameplates_visible(shown)


func _set_always_show_health_bar(shown: bool) -> void:
	_always_show_health_bar = shown
	_board.set_always_show_health_bar(shown)
	if is_instance_valid(_terminal_board):
		_terminal_board.set_always_show_health_bar(shown)
	BattleDisplayPreferences.save_always_show_health_bar(shown)


func _storybook_board_focused() -> void:
	_anchor_board_cursor()
	_refresh_board()


func _anchor_board_cursor() -> void:
	var selected := _find(_actor_id)
	_storybook_focus_cell = selected.get("position")
	if _storybook_focus_cell == null:
		for unit: Dictionary in _roster():
			if unit.hp > 0:
				_storybook_focus_cell = unit.position
				break


func _storybook_board_unfocused() -> void:
	_storybook_focus_cell = null
	_refresh_board()


func _storybook_board_input(event: InputEvent) -> void:
	if _battle_controls_blocked():
		return
	if not event is InputEventKey or not event.pressed:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		if _storybook_focus_cell is Vector2i:
			_select_board(_storybook_focus_cell)
			_board.accept_event()
		return
	var direction := Vector2i.ZERO
	if event.is_action_pressed("ui_left"):
		direction = Vector2i.LEFT
	elif event.is_action_pressed("ui_right"):
		direction = Vector2i.RIGHT
	elif event.is_action_pressed("ui_up"):
		direction = Vector2i.UP
	elif event.is_action_pressed("ui_down"):
		direction = Vector2i.DOWN
	if direction == Vector2i.ZERO or not _storybook_focus_cell is Vector2i:
		return
	var next: Vector2i = _storybook_focus_cell + direction
	if _painted_cells.has(next):
		_storybook_focus_cell = next
		_inspect_board(next)
		_refresh_board()
	_board.accept_event()


func _storybook_action(ability: String) -> void:
	if _battle_controls_blocked() or not _ongoing():
		return
	var action: Dictionary = _editor_actions.get(ability, {})
	if not action.get("enabled", false):
		return
	if _is_selectable(action.kind):
		_aimed_ability_id = ability
		_occupant_cell = null
		_refresh_targeting()
		_board.grab_focus()
	else:
		_stage_command(ability)


func _storybook_target(target: String) -> void:
	# The floating choice selects an occupant of the pending tile, not an ability.
	if _battle_controls_blocked() or not _ongoing() or _occupant_cell == null:
		return
	if _aimed_targets_at(_occupant_cell).any(func(choice: Dictionary) -> bool: return choice.id == target):
		_stage_command(_aimed_ability_id, target)


func _storybook_order(hero: String, order: String) -> void:
	if _battle_controls_blocked() or not _can_change_battle_order(hero):
		return
	if not _rules.options(_state, hero).any(
			func(choice: Dictionary) -> bool: return choice.kind == "order" and choice.id == order):
		return
	_state = _rules.set_order(_state, hero, order)
	_planned_state = _rules.set_order(_planned_state, hero, order)
	if _practice != null and order != PracticeLesson.BLAST_ORDER:
		_clear_command()
		return
	_refresh()


func _storybook_select_board(cell: Vector2i) -> void:
	if _is_aiming():
		var targets := _aimed_targets_at(cell)
		if targets.size() == 1:
			_stage_command(_aimed_ability_id, targets[0].id)
		elif targets.size() > 1 or _occupant_cell != null:
			_occupant_cell = cell if targets.size() > 1 else null
			_render_storybook()
		return
	var hero := _living_hero_at(cell)
	if not hero.is_empty():
		_storybook_select_hero(hero)
		return
	# Normal destination clicks are only Move, using the board at the hero's turn.
	var move: Dictionary = _editor_actions.get("move", {})
	for target: Dictionary in move.get("targets", []):
		if target.position == cell:
			_stage_command("move", target.id)
			return


func _storybook_select_hero(hero: String) -> void:
	if _battle_controls_blocked() or not _ongoing() or _find(hero).get("hp", 0) <= 0 \
			or not _rules.has_capability(_state, hero, "commandable"):
		return
	_actor_id = hero
	_reset_targeting()
	if _board.has_focus():
		_anchor_board_cursor()
	_refresh_selection()


func _render_storybook() -> void:
	var mission: Dictionary = _rules.mission_definition(_state)
	var objective: Dictionary = mission.objective
	var progress: Dictionary = _rules.objective_progress(_state)
	var heroes: Array = []
	var orders: Array = []
	var commanded := _commanded_hero()
	for unit in _roster():
		var hero_label := _name_for(unit.id)
		if unit.hp > 0:
			heroes.append({"id": unit.id, "label": hero_label})
		var choices: Array = []
		for choice in _rules.options(_state, unit.id):
			if choice.kind == "order":
				choices.append({"id": choice.id, "label": choice.label})
		orders.append({"hero_id": unit.id, "hero_label": hero_label,
			"order_id": _state.orders.get(unit.id, ""), "choices": choices,
			"enabled": _can_change_battle_order(unit.id), "overridden": _ongoing() and unit.id == commanded,
			"hp": "%d/%d HP" % [unit.hp, unit.max_hp]})
	var events: PackedStringArray = []
	if _ongoing():
		var objective_forecast := _objective_forecast_text()
		if not objective_forecast.is_empty():
			events.append(objective_forecast)
	for event in (_plan.get("events", []) if _ongoing() else _last_events):
		events.append(str(event.text))
	var target_choices: Array = []
	if _occupant_cell != null:
		target_choices = _aimed_targets_at(_occupant_cell)
	# The floating choice control anchors beside the clicked cell and must
	# also avoid covering the selected hero.
	var selected_cell: Variant = null
	var selected_unit := _find(_actor_id)
	if not selected_unit.is_empty():
		selected_cell = selected_unit.position
	var text_key: String = "text" if _ongoing() else _state.outcome + "_text"
	var values := _objective_format_values(progress)
	var details := str(objective.text).format(values)
	var headline := str(objective.get(text_key, objective.text)).format(values)
	if _state.get("_voluntary_defeat", false):
		headline = _rules.mission_result_text(_state)
	elif _ongoing() and _state.objective.handler == "pressure_gate":
		headline = "Get a hero to the exit at %s." % BridgeArt.coordinate(_state.objective.exit)
	elif _ongoing() and _state.objective.handler != "pressure_gate":
		var first_sentence := headline.find(". ")
		if first_sentence >= 0:
			headline = headline.substr(0, first_sentence + 1)
	var inspection := _storybook_inspection
	if not _editor_unavailable_reason.is_empty():
		inspection = _editor_unavailable_reason if inspection.is_empty() else _editor_unavailable_reason + " · " + inspection
	var upgrades: PackedStringArray = []
	for unit in _roster():
		var owned: Dictionary = _run.get("upgrades_by_id", {}).get(unit.id, {})
		if owned.is_empty():
			continue
		upgrades.append(_name_for(unit.id))
		for id in owned:
			var upgrade: Dictionary = _definitions.upgrades[id]
			upgrades.append("%s · %s · %d of %d acquired\n%s" % [
				upgrade.label, upgrade.rarity.capitalize(), owned[id], upgrade.cap, upgrade.description])
	var deadline: int = _rules.deadline(_state)
	var round_label := "Round %d / %d" % [_state.round, deadline] if deadline > 0 else "Round %d" % _state.round
	var status := _objective_progress_text(_state, progress) if _ongoing() else ""
	if _ongoing() and _state.objective.handler == "leave_zone":
		status += "  ·  Damaging standing orders remain active."
	_storybook_page.render({"title": mission.title, "round": _state.round, "round_label": round_label,
		"objective": headline, "objective_details": details,
		"objective_status": status,
		"heroes": heroes, "selected_hero_id": _actor_id, "aimed_action_id": _aimed_ability_id,
		"actions": _editor_actions.values(), "orders": orders, "aim_prompt": _aim_prompt(),
		"targets": target_choices, "selected_cell": selected_cell,
		"command_summary": _draft_summary, "inspection": inspection,
		"locked_dose": _locked_dose_text(),
		"forecast": "\n".join(events), "can_clear": not commanded.is_empty() or not _actor_id.is_empty(),
		"clear_label": "Clear selection" if commanded.is_empty() else "Clear command",
		"can_commit": _can_commit(), "outcome": _state.outcome,
		"can_restart": not _fixed_mission.is_empty(), "upgrades_text": "\n".join(upgrades)})
	if _practice != null:
		_practice_instructions.render(_practice.step(_state, _plan, _is_aiming()),
			_practice.forecast_open, _practice.can_commit(), _actor_id == PracticeLesson.CASTER)


func _aim_prompt() -> String:
	if not _ongoing():
		return ""
	if _actor_id.is_empty():
		return "Choose a hero on the board or in the Direct Order selector."
	if not _is_aiming():
		var instruction := "Click a marked destination to Move, or choose an ability."
		if _board_targets().is_empty():
			instruction = "Choose an ability or select another hero."
		return instruction if _commanded_hero().is_empty() else instruction + " A new command replaces this preview."
	var aimed: Dictionary = _editor_actions.get(_aimed_ability_id, {})
	if aimed.is_empty():
		return "This ability is no longer available. Cancel targeting or choose another ability."
	var instruction := "Choose a marked tile." if _commanded_hero().is_empty() else "Choose a tile to replace this preview."
	if not _is_selectable(aimed.kind):
		instruction = "This form has no aimed target. Select the ability again to use it."
	elif aimed.targets.is_empty():
		instruction = "No legal targets. Cancel targeting or choose another ability."
	elif _occupant_cell != null:
		instruction = "Choose an occupant at %s." % BridgeArt.coordinate(_occupant_cell)
	return "Aiming: %s · %s" % [aimed.label, instruction]


func _locked_dose_text() -> String:
	var aiming := _is_aiming()
	var notes: PackedStringArray = []
	for action: Dictionary in _editor_actions.values():
		if aiming and action.id != _aimed_ability_id:
			continue
		var dose: Dictionary = action.dose
		if dose.is_empty():
			continue
		var reaction := "%s · %s" % [dose.category.capitalize(), dose.description]
		if aiming:
			return reaction
		notes.append("%s: %s" % [action.label, reaction])
	return "\n".join(notes)


func _restart_fixed() -> void:
	if _battle_controls_blocked() or _fixed_mission.is_empty():
		return
	_state = _opening_state.duplicate(true)
	_begin_attempt()


func _begin_attempt() -> void:
	_board.clear_action_playback()
	_planned_state = _state
	_last_events.clear()
	_actor_id = ""
	_reset_targeting()
	_storybook_inspected_cell = null
	_sync_actors()
	if _board.has_focus():
		_anchor_board_cursor()
	_refresh()


func _sync_actors() -> void:
	var current := _find(_actor_id)
	if current.is_empty() or current.hp <= 0:
		_actor_id = ""
		for unit in _roster():
			if unit.hp > 0:
				_actor_id = unit.id
				break


func _editor_context() -> Dictionary:
	# A preview for the editor's hero replaces any queued override.
	var editor_plan := _planned_state if _planned_state.overrides.has(_actor_id) else _state
	return _rules.state_before_action(editor_plan, _actor_id)


func _refresh_selection() -> void:
	var context := _editor_context()
	_editor_unavailable_reason = ""
	_editor_actions.clear()
	if _ongoing() and not _actor_id.is_empty():
		if not _rules.can_act(context, _actor_id):
			_editor_unavailable_reason = _unavailable_hero_reason(context)
		for choice: Dictionary in _rules.options(context, _actor_id):
			if choice.kind == "action":
				_editor_actions[choice.id] = _command_option(context, choice)
	# Changing a standing order can invalidate the aimed form. Keep the
	# attempt pending until the player explicitly stages, cancels, or switches.
	if _occupant_cell != null and _aimed_targets_at(_occupant_cell).size() < 2:
		_occupant_cell = null
	_refresh_targeting()


func _command_option(context: Dictionary, choice: Dictionary) -> Dictionary:
	var definition := _rules.command_ability(context, _actor_id, choice.id)
	var kind: String = definition.get("targeting", {}).get("kind", "")
	var targets: Array = []
	var reason := ""
	if not _practice_allows_action(choice.id):
		reason = "Not available in this part of practice."
	elif not _editor_unavailable_reason.is_empty():
		reason = _editor_unavailable_reason
	elif definition.get("command_blocked", false):
		reason = "Cannot use this ability when this hero acts."
	elif _is_selectable(kind):
		targets = _rules.targets(context, _actor_id, choice.id)
		if targets.is_empty():
			if definition.get("handler") == "repeat_batch" and _rules.dose_forecast(context, _actor_id, choice.id).is_empty():
				reason = "Empty bottle. Use a dose that causes a reaction first."
			else:
				reason = "No legal target when this hero acts."
	var dose := _rules.dose_forecast(context, _actor_id, choice.id) if reason.is_empty() else {}
	return {"id": choice.id, "label": definition.get("label", choice.label), "kind": kind,
		"enabled": reason.is_empty(), "reason": reason, "help": definition.get("help", ""),
		"targets": targets, "dose": dose}


func _stage_command(ability: String, target := "") -> void:
	var previous: Dictionary = _planned_state.overrides.get(_actor_id, {})
	var candidate := _rules.choose_manual(_rules.clear_manual(_planned_state), _actor_id, ability, target)
	var staged: Dictionary = candidate.overrides.get(_actor_id, {})
	if staged.is_empty():
		return
	_planned_state = candidate
	if ability == "move" and staged != previous:
		_sound_effects.planning(_actor_id)
	_reset_targeting()
	_refresh()
	_board.grab_focus()


func _clear_command() -> void:
	if _battle_controls_blocked() or not _ongoing():
		return
	_planned_state = _rules.clear_manual(_planned_state)
	_actor_id = ""
	_reset_targeting()
	_anchor_board_cursor()
	_refresh()
	_board.grab_focus()


func _reset_targeting() -> void:
	_aimed_ability_id = ""
	_occupant_cell = null


func _cancel_targeting() -> void:
	if _battle_controls_blocked() or not _is_aiming():
		return
	_reset_targeting()
	_refresh_targeting()
	_board.grab_focus()


func _is_aiming() -> bool:
	return not _aimed_ability_id.is_empty()


func _is_selectable(target_kind: String) -> bool:
	return target_kind == "cell" or target_kind == "entity"


func _commit() -> void:
	if _battle_controls_blocked() or not _can_commit():
		return
	var round_number: int = _state.round
	var committed := _rules.commit_round(_planned_state, _plan)
	if committed == _planned_state:
		return
	_last_events = _plan.events.duplicate(true)
	var cues := CastCues.build(_state, committed, _last_events, true)
	var handoff_corpses := {}
	for event: Dictionary in _last_events:
		if event.type == "play_dead":
			var corpse := _corpse_figure(event.target_id, event.position)
			corpse["play_dead_corpse"] = true
			# A Bomber's only defeat clip is its blast, not a body.
			corpse["inert_corpse"] = corpse.get("cast_key") == "bomber"
			handoff_corpses[event.target_id] = corpse
	_board.prepare_committed_presentation(cues, handoff_corpses)
	_state = committed
	_planned_state = _state
	_reset_targeting()
	_storybook_inspected_cell = null
	_set_inspection("")
	if not _ongoing() and _fixed_mission.is_empty() and _practice == null:
		_run = Adventure.settle_mission(_run, _state)
		if _run.phase in ["reward", "route", "ready", "finished"]:
			var replay := _take_terminal_board(cues)
			_show_settled_mission()
			if replay != null:
				_show_terminal_replay(replay)
			return
	_sync_actors()
	if _board.has_focus():
		_anchor_board_cursor()
		_storybook_inspected_cell = _storybook_focus_cell
	_refresh()
	_board.play_committed_actions(cues)
	_refresh_board()
	if _practice != null:
		print_verbose("Committed practice round %d." % round_number)
		if _ongoing():
			_storybook_page.close_forecast()
			var forecast := _storybook_page.find_child("ForecastDetails", true, false) as Button
			forecast.grab_focus()
		else:
			_practice_instructions.focus_continue()


func _forfeit() -> void:
	if _screen != "battle" or not _ongoing() or _practice != null:
		return
	_state = _rules.forfeit(_state)
	_planned_state = _state
	_last_events.clear()
	_reset_targeting()
	_storybook_inspected_cell = null
	_board.clear_action_playback()
	if _fixed_mission.is_empty():
		_run = Adventure.settle_mission(_run, _state)
		if _run.phase == "finished":
			_show_settled_mission()
			return
	_refresh()


func _battle_controls_blocked() -> bool:
	return is_instance_valid(_storybook_page) and _storybook_page.battle_controls_blocked()


func _show_settled_mission() -> void:
	match _run.phase:
		"reward":
			_show_debrief()
		"route":
			_show_routes()
		"ready":
			_begin_mission()
		"finished":
			_show_result()


func _take_terminal_board(cues: Array) -> BridgeArt:
	_refresh_board()
	_board.play_committed_actions(cues)
	_refresh_board()
	if not _board.committed_visuals_pending():
		return null
	# Keep the resolved board only, not its controls or callbacks into the
	# battle editor. A commission can deploy a new board synchronously.
	var replay := _board
	replay.cell_selected.disconnect(_select_board)
	replay.cell_hovered.disconnect(_inspect_board)
	replay.hover_cleared.disconnect(_clear_inspection)
	replay.gui_input.disconnect(_storybook_board_input)
	replay.focus_entered.disconnect(_storybook_board_focused)
	replay.focus_exited.disconnect(_storybook_board_unfocused)
	replay.release_focus()
	replay.name = "ReplayBoard"
	replay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay.focus_mode = Control.FOCUS_NONE
	replay.tooltip_text = ""
	replay.get_parent().remove_child(replay)
	replay.custom_minimum_size.y = 315
	replay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return replay


func _show_terminal_replay(board: BridgeArt) -> void:
	if _screen == "battle":
		# A new report can deploy immediately. Keep any usual cast replay, but
		# never show the last battle's reaction over the new live board.
		board.hide_committed_reactions()
		if not board.committed_visuals_pending():
			board.queue_free()
			return
	var panel := PanelContainer.new()
	panel.name = "TerminalCastReplay"
	panel.z_index = 10
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color("#172321"), LINE, 12))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -660
	panel.offset_top = -462
	panel.offset_right = -26
	panel.offset_bottom = -26
	var stack := _stack(panel, 6)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label(stack, "Final actions  ·  Press a key or click to skip", 15, MUTED)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(board)
	_terminal_replay = panel
	_terminal_board = board
	_terminal_remaining_ms = _terminal_playback_remaining_ms()
	_terminal_replay_until = Time.get_ticks_msec() + TERMINAL_REPLAY_STALL_MS
	set_process(true)


func _process(_delta: float) -> void:
	if not _terminal_board.committed_visuals_pending():
		_clear_terminal_replay()
		return
	# A long, progressing queue should finish; only a stuck timeline is bounded.
	var remaining := _terminal_playback_remaining_ms()
	if remaining < _terminal_remaining_ms:
		_terminal_remaining_ms = remaining
		_terminal_replay_until = Time.get_ticks_msec() + TERMINAL_REPLAY_STALL_MS
	elif Time.get_ticks_msec() >= _terminal_replay_until:
		_clear_terminal_replay()


func _terminal_playback_remaining_ms() -> float:
	return _terminal_board.committed_visuals_remaining_ms()


func _input(event: InputEvent) -> void:
	if _screen == "petitions" and event.is_pressed():
		_petition_input_revision += 1
	if _terminal_replay != null and event.is_pressed() and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch \
			or event is InputEventJoypadButton):
		_clear_terminal_replay()


func _unhandled_key_input(event: InputEvent) -> void:
	if _screen != "battle" or _battle_controls_blocked() or not event.is_pressed() or event.is_echo():
		return
	if event.keycode != KEY_ESCAPE:
		# Other unhandled keys stay available to every further consumer.
		return
	if _occupant_cell != null:
		_occupant_cell = null
		_refresh_targeting()
		_board.grab_focus()
	elif _is_aiming():
		_cancel_targeting()
	elif not _actor_id.is_empty():
		_actor_id = ""
		_anchor_board_cursor()
		_refresh_selection()
		_board.grab_focus()
	# Escape never discards the draft; Clear command is the explicit discard.
	get_viewport().set_input_as_handled()


func _clear_terminal_replay() -> void:
	if _terminal_replay == null:
		return
	_terminal_board.clear_action_playback()
	remove_child(_terminal_replay)
	_terminal_replay.queue_free()
	_terminal_replay = null
	_terminal_board = null
	set_process(false)


func _refresh() -> void:
	_plan = _rules.preview_round(_planned_state)
	if _practice != null:
		_practice.preview_changed(_plan)
	_update_draft_display()
	_refresh_selection()


func _refresh_targeting() -> void:
	_refresh_board()
	_sync_inspection()
	_render_storybook()


func _unavailable_hero_reason(context: Dictionary) -> String:
	if _find(_actor_id, context).get("hp", 0) <= 0:
		return "This hero falls before acting. Change an earlier order or choose another hero."
	if _rules.knocked_down(context, _actor_id):
		if _rules.knocked_down(_state, _actor_id):
			return "This hero is down and spends this turn getting up. Choose another hero."
		return "This hero will be knocked down before acting. Change an earlier order or choose another hero."
	var labels := ", ".join(_rules.status_labels(context, _actor_id, "skip_action"))
	if labels.is_empty():
		labels = "This hero cannot act"
	return "%s. Change an earlier order or choose another hero." % labels


func _can_commit() -> bool:
	return _ongoing() and not _is_aiming() and _plan.get("valid", false) \
		and (_practice == null or _practice.can_commit())


func _commanded_hero() -> String:
	return "" if _planned_state.overrides.is_empty() else str(_planned_state.overrides.keys()[0])


func _objective_format_values(progress: Dictionary) -> Dictionary:
	var values := {"deadline": _rules.deadline(_state)}
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
	return values


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


func _objective_forecast_text() -> String:
	var text := ""
	if _ongoing() and _plan.get("valid", false):
		var projected: Dictionary = _plan.result
		var outcome: String = projected.outcome
		if outcome in ["victory", "defeat"]:
			text = "Forecast: Victory this round." if outcome == "victory" else "Forecast: Defeat this round."
			for event in _plan.events:
				if event.type == outcome:
					text += " " + str(event.text)
					break
		elif projected.objective.handler != "defeat_all":
			var next := _objective_progress_text(projected, _rules.objective_progress(projected))
			var now := _objective_progress_text(_state, _rules.objective_progress(_state))
			if not next.is_empty() and next != now:
				text = "After this round: " + next
		if not text.is_empty() and _is_aiming():
			text += " (Pending target not included.)"
	return text


func _update_draft_display() -> void:
	_draft_target_cell = null
	if not _ongoing():
		_draft_summary = "Victory" if _state.outcome == "victory" else "Defeat"
		return
	var hero := _commanded_hero()
	if hero.is_empty():
		_draft_summary = "Standing orders only · One Direct Order per round."
		return
	for event: Dictionary in _plan.get("events", []):
		if event.get("unit_id") == hero and event.get("reason") == "direct_form_changed":
			_draft_summary = "%s: Action form changed. Choose the Direct Order again." % _name_for(hero)
			return
	var draft: Dictionary = _planned_state.overrides[hero]
	var before := _rules.state_before_action(_planned_state, hero)
	var action := _rules.command_ability(before, hero, draft.ability_id)
	var target: Dictionary = {}
	if not draft.target_id.is_empty():
		for choice: Dictionary in _rules.targets(before, hero, draft.ability_id):
			if choice.id == draft.target_id:
				target = choice
				_draft_target_cell = target.position
				break
	var destination := _target_description(hero, draft, target, action)
	var action_label: String = action.get("label", draft.ability_id)
	if draft.ability_id == "move" and action_label == "Move one tile":
		action_label = "Move"
	_draft_summary = "%s: %s%s" % [_name_for(hero), action_label, destination]
	var order_id: String = _planned_state.orders.get(hero, "")
	if not order_id.is_empty():
		var order: Dictionary = _rules.definitions(_state).orders.get(order_id, {})
		_draft_summary += "\nReplaces %s this round" % str(order.get("label", order_id))


func _target_description(hero: String, draft: Dictionary, target: Dictionary,
		definition: Dictionary) -> String:
	if draft.target_id.is_empty():
		if definition.get("handler") == "perform":
			for event in _plan.events:
				if event.get("unit_id") == hero and event.get("ability_id") == draft.ability_id:
					return " → %s" % event.target_label if event.has("target_label") else " (no eligible listener)"
		return ""
	if target.is_empty():
		return " → %s (no longer legal)" % _name_for(draft.target_id)
	var location := BridgeArt.coordinate(target.position)
	if definition.get("targeting", {}).get("kind") == "cell":
		return " → " + location
	return " → %s at %s" % [target.label, location]


func _corpse_figure(id: String, cell: Vector2i) -> Dictionary:
	var profile: Dictionary = _rules.entity_profile(_state, id)
	var marker := {"id": id, "art_key": profile.art_key, "variant": profile.get("art_variant", ""),
		"label": "Corpse", "cell": cell, "hp": 0, "max_hp": 0, "prone": true}
	var actor := _find(id)
	if not actor.is_empty():
		var cast_key := CastCues.cast_key_for(_state, actor, profile)
		var presentation := CastCues.presentation_for(_state, actor, profile)
		if cast_key == "harpooner" or presentation.get("defeat") is String:
			marker["cast_key"] = cast_key
			if CastCues.has_presentation(_state, actor):
				marker["cast_lifecycle"] = presentation
	return marker


func _refresh_board() -> void:
	_painted_cells = _terrain()
	var units: Array = []
	var playback_cues: Array = _board.action_playback_snapshot()
	_corpse_markers = _rules.corpse_markers(_state)
	for corpse in _corpse_markers.values():
		units.append(_corpse_figure(corpse.id, corpse.position))
	var shared_art := _shared_enemy_art()
	for unit in _state.units:
		var is_objective: bool = unit.id == _state.objective.get("subject") \
			or unit.id in _state.objective.get("subjects", [])
		var visual_defeat: bool = unit.hp <= 0 and not is_objective \
			and not CastCues.guild_hero_key(_state, unit).is_empty()
		var playback_only: bool = unit.hp <= 0 and not is_objective and not visual_defeat \
			and not units.any(func(row): return row.id == unit.id) \
			and playback_cues.any(func(cue): return cue.get("unit_id") == unit.id \
				and (cue.get("ordinary_role") == "defeat" or cue.get("clip") == "defeat"))
		if unit.hp <= 0 and not is_objective and not visual_defeat and not playback_only:
			continue
		var profile: Dictionary = _rules.entity_profile(_state, unit.id)
		var show_label: bool = "commandable" in profile.capabilities or "minion" in profile.capabilities
		var art_variant := str(profile.get("art_variant", ""))
		var caption := _name_for(unit.id) if show_label else str(profile.label) \
			if is_objective or shared_art.has([profile.art_key, art_variant]) else ""
		var shield_cell: Variant = _rules.shield_position(_state, unit.id)
		var figure := {"id": unit.id, "art_key": profile.art_key, "variant": art_variant,
			"label": caption, "color": profile.get("color", ""),
			"cell": unit.position, "hp": unit.hp, "max_hp": unit.max_hp, "objective": is_objective,
			"prone": unit.hp <= 0 or _rules.knocked_down(_state, unit.id),
			"guarded": _rules.has_status_handler(_state, unit.id, "reflect"),
			"shield_away": shield_cell is Vector2i, "shield_cell": shield_cell}
		var tactics := {}
		for status: String in BridgeArt.TACTICAL_STATUSES:
			if unit.get("statuses", {}).has(status):
				tactics[status] = true
		if not tactics.is_empty():
			figure["tactical_statuses"] = tactics
		if visual_defeat:
			figure["visual_defeat"] = true
			figure["label"] = ""
		if playback_only:
			figure["playback_only"] = true
			figure["transient"] = true
			figure["label"] = ""
		var cast_key := CastCues.cast_key_for(_state, unit, profile)
		if not cast_key.is_empty():
			figure["cast_key"] = cast_key
			if not CastCues.guild_hero_key(_state, unit).is_empty():
				figure["guild_knockdown_art"] = true
			var presentation := CastCues.presentation_for(_state, unit, profile)
			if CastCues.has_presentation(_state, unit):
				figure["cast_lifecycle"] = presentation
				var held := CastCues.held_clip_for(_state, unit, presentation)
				if not held.is_empty():
					figure["cast_hold"] = held
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
	elif _state.objective.handler == "herd_sheep":
		overlay["pen_zone"] = _state.objective.pen
	elif _state.objective.handler == "pressure_gate":
		var gate: Vector2i = _state.objective.gate
		overlay["pressure_gate"] = {"cell": gate, "open": _rules.tile_definition(_state, gate).passable}
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
			if not _is_aiming() and _planned_state.overrides[commanded.id].ability_id == "move":
				overlay["quiet_manual_move"] = true
		var positions := {}
		for target: Dictionary in _board_targets():
			positions[target.position] = true
		overlay["targets"] = positions.keys()
		if not _is_aiming() and _draft_target_cell is Vector2i:
			overlay["chosen_target"] = _draft_target_cell
		var hits: Array = []
		var paths: Array = []
		var displaced: Dictionary = {}
		for event in _plan.events:
			if event.type in ["pull", "push", "repel"] and event.has("from_position"):
				displaced[event.target_id] = true
		for entity in _state.units + _state.obstacles:
			var predicted := _find(entity.id, _plan.result)
			if predicted.is_empty():
				continue
			if predicted.hp < entity.hp:
				hits.append(entity.position)
			var manual_move: bool = entity.id == _commanded_hero() \
				and _planned_state.overrides[entity.id].ability_id == "move"
			if predicted.position != entity.position and not displaced.has(entity.id) and not manual_move:
				paths.append([entity.position, predicted.position])
		paths.append_array(_ordered_displacement_paths(displaced))
		overlay["impact"] = hits
		overlay["paths"] = paths
	_board.set_render_state(_painted_cells, units, overlay)
	if _board_cues != null:
		_board_cues.update_markers(_objective_markers, native_exit)
	var ink := {}
	if _board.has_focus() and _storybook_focus_cell is Vector2i:
		ink["focus_cell"] = _storybook_focus_cell
	if _ongoing():
		ink["alchemy"] = _plan.get("events", []).filter(func(event: Dictionary) -> bool:
			return event.type == "alchemy_reaction")
	var selected := _find(_actor_id)
	if _ongoing() and not selected.is_empty():
		ink["selected_cell"] = selected.position
	if _ongoing() and not _commanded_hero().is_empty():
		var hero := _commanded_hero()
		var draft: Dictionary = _planned_state.overrides[hero]
		if draft.ability_id == "move":
			var before := _find(hero, _rules.state_before_action(_planned_state, hero))
			var moves: Array = _plan.events.filter(func(event: Dictionary) -> bool:
				return event.type == "move" and event.get("unit_id") == hero \
					and event.get("ability_id") == "move")
			if not before.is_empty() and moves.size() == 1 and before.position != moves[0].position:
				var destination: Vector2i = moves[0].position
				ink["move"] = {"from": before.position, "to": destination,
					"cast_key": CastCues.cast_key_for(_state, _find(hero), _rules.entity_profile(_state, hero))}
				ink["context_cell"] = destination
				ink["context_text"] = "Move to " + BridgeArt.coordinate(destination)
	if _uses_builtin_catalog and _state.board_id == "frontier_gate_board" and _state.objective.handler == "pressure_gate":
		var gate: Vector2i = _state.objective.gate
		var now_open: bool = _rules.tile_definition(_state, gate).passable
		var next_open: bool = _rules.tile_definition(_plan.result, gate).passable
		ink["gate_actual"] = {"cell": gate, "open": now_open}
		ink["landmarks"] = [
			{"cell": _state.objective.plate, "kind": "plate", "label": "Pressure plate"},
			{"cell": _state.objective.exit, "kind": "exit", "label": "Exit"}]
		if _ongoing() and now_open != next_open:
			ink["gate"] = {"cell": gate, "opens": next_open}
	_storybook_page.render_ink(ink)

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


func _ordered_displacement_paths(displaced: Dictionary) -> Array:
	# Replay position-bearing events in order, so a move before or after a displacement
	# does not become a misleading straight line to the final position.
	var positions: Dictionary = {}
	for entity in _state.units + _state.obstacles:
		positions[entity.id] = entity.position
	var paths: Array = []
	for event in _plan.events:
		match event.type:
			"move":
				_trace_position(positions, paths, displaced, event.unit_id, event.position)
			"summon":
				positions[event.summon_id] = event.position
			"push", "pull", "repel":
				# A shift can affect a piece that was not on the opening board.
				if event.has("from_position"):
					positions[event.target_id] = event.from_position
				_trace_position(positions, paths, displaced, event.target_id, event.position)
				if event.has("recoil_position"):
					_trace_position(positions, paths, displaced, event.unit_id, event.recoil_position)
			"swap":
				_trace_position(positions, paths, displaced, event.unit_id, event.position)
				_trace_position(positions, paths, displaced, event.target_id, event.target_position)
	return paths


func _trace_position(positions: Dictionary, paths: Array, displaced: Dictionary, id: String, destination: Vector2i) -> void:
	if displaced.has(id) and positions.has(id) and positions[id] != destination:
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
	if not _battle_controls_blocked() and _ongoing():
		_storybook_select_board(cell)


func _inspect_board(cell: Vector2i) -> void:
	if _battle_controls_blocked():
		return
	_storybook_inspected_cell = cell
	_sync_inspection()
	_render_storybook()


func _sync_inspection() -> void:
	if not _painted_cells.has(_storybook_inspected_cell):
		_set_inspection("")
		return
	var cell: Vector2i = _storybook_inspected_cell
	var marker: Dictionary = _objective_markers.get(cell, {})
	var place := BridgeArt.coordinate(cell) if marker.is_empty() else \
		"%s  ·  %s" % [BridgeArt.coordinate(cell), marker.label]
	var shield_note := _shield_tile_note(cell)
	var target_note := ""
	if _board_targets().any(func(target: Dictionary) -> bool: return target.position == cell):
		target_note = "Legal target" if _is_aiming() else "Move destination"
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
	_storybook_inspection = text if details.is_empty() else text + "  ·  " + details[0]
	_board.tooltip_text = text if details.is_empty() else text + "\n" + "\n".join(details)


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


func _board_targets() -> Array:
	if _is_aiming():
		return _editor_actions.get(_aimed_ability_id, {}).get("targets", [])
	var moves: Array = _editor_actions.get("move", {}).get("targets", [])
	return moves.filter(func(target: Dictionary) -> bool: return _living_hero_at(target.position).is_empty())


func _aimed_targets_at(cell: Vector2i) -> Array:
	var targets: Array = _editor_actions.get(_aimed_ability_id, {}).get("targets", [])
	return targets.filter(func(target: Dictionary) -> bool: return target.position == cell)


func _living_hero_at(cell: Vector2i) -> String:
	for unit: Dictionary in _roster():
		if unit.position == cell and unit.hp > 0:
			return unit.id
	return ""


func _clear_inspection() -> void:
	if _battle_controls_blocked():
		return
	_storybook_inspected_cell = null
	_set_inspection("")
	_render_storybook()


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


func _presentation(art_key: String, fallback: String) -> String:
	return _presentation_entry(art_key).get("label", fallback)


func _presentation_entry(art_key: String) -> Dictionary:
	return _rules.definitions(_state).get("presentation", {}).get(art_key, {})
