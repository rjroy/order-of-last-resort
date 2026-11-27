extends RefCounted
## The company can be arranged and equipped here; departure is a controller decision.

signal back_requested
signal recruit_toggled(id: String)
signal hero_edit_requested(id: String)
signal recruit_list_requested
signal reorder_requested(id: String, delta: int)
signal offense_requested(id: String, ability_id: String)
signal utility_requested(hero_id: String, ability_id: String)
signal order_requested(id: String, order_id: String)
signal depart_requested

const BoundPage = preload("res://presentation/book/guild_bound_page.gd")
const Prep = preload("res://presentation/book/guild_prep_widgets.gd")
const PRINT_RULE := Color("#937c55")
const FOCUS_INK := Color("#8b4a0c")
const DEPART_COLORS := {"normal": "#1e4132", "hover": "#2b5642", "pressed": "#183329"}

var _book: BoundPage
var _parent: VBoxContainer
var _editing_id := ""
var _compact := false


func build(book: BoundPage, parent: VBoxContainer, model: Dictionary) -> void:
	_book = book
	_parent = parent
	var viewport := _book.get_viewport_rect().size
	_compact = viewport.x < 1100 or viewport.y < 700
	_book.bind_cover(26 if _compact else 39, 20 if _compact else 23, 26 if _compact else 30)
	var spread := _book.spread(parent, 0.43, 12)
	var party: Array = model.get("party", [])
	var hero := _selected_hero(party, str(model.get("selected_hero_id", "")))
	_editing_id = str(hero.get("id", "")) if model.get("folio", "recruits") == "loadout" else ""
	_build_deployment(spread[0], model, party)
	_build_folio(spread[1], model, party, hero)


func focus_control(name: String) -> Control:
	return _parent.find_child(name, true, false) as Control if is_instance_valid(_parent) else null


func _build_deployment(parent: VBoxContainer, model: Dictionary, party: Array) -> void:
	parent.add_theme_constant_override("separation", 4 if _compact else 7)
	var back := Prep.back(_book, parent)
	back.add_theme_font_override("font", Prep.serif())
	back.add_theme_font_size_override("font_size", 18 if _compact else 20)
	back.add_theme_color_override("font_color", Prep.INK)
	_apply_focus(back)
	back.pressed.connect(func() -> void: back_requested.emit())
	_book.strong_text(parent, "Choose your company", 33 if _compact else 43)
	var context := _commission_context(model)
	if not context.is_empty():
		Prep.text(_book, parent, context, 18 if _compact else 22, Prep.QUIET).name = "CommissionContext"
	_book.rule(parent, PRINT_RULE)
	_book.strong_text(parent, "Deployment order", 29 if _compact else 37)
	Prep.text(_book, parent, "Heroes act from top to bottom.", 17 if _compact else 22, Prep.QUIET, "italic")
	var party_size := int(model.get("party_size", 0))
	Prep.text(_book, parent, "%d of %d selected" % [party.size(), party_size],
		19 if _compact else 23, Prep.FOREST).name = "PartyCount"
	_book.rule(parent, PRINT_RULE)
	var scroll := _book.scroll(parent, "DeploymentScroll")
	var list := _book.stack(scroll, 5 if _compact else 7)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in party_size:
		_build_slot(list, party[index] if index < party.size() else {}, index, party.size())


func _build_slot(parent: Control, hero: Dictionary, index: int, filled: int) -> void:
	var id := str(hero.get("id", ""))
	var selected := not id.is_empty() and id == _editing_id
	var fill := Color("#f3d9ae") if selected else Color.TRANSPARENT
	var mounted := Prep.mount(parent, selected, false, false, fill, 9, 5)
	mounted.name = "DeploymentSlot_%d" % (index + 1)
	var row := _book.row(mounted, 8 if _compact else 14)
	var portrait_side := 85.0 if _compact else 126.0
	row.custom_minimum_size.y = portrait_side if not id.is_empty() else 44
	var number := _book.strong_text(row, "%02d" % (index + 1), 27 if _compact else 38, BoundPage.RUST)
	number.autowrap_mode = TextServer.AUTOWRAP_OFF
	number.custom_minimum_size.x = 34 if _compact else 47
	number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if id.is_empty():
		var place := Prep.line(_book, row, "Open place", 23, Prep.QUIET, "italic")
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		place.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_book.rule(parent, PRINT_RULE)
		return
	Prep.picture(_book, row, hero.get("portrait") as Texture2D, portrait_side)
	var copy := _book.stack(row, 2 if _compact else 4)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := str(hero.get("name", ""))
	_book.strong_text(copy, title, 21 if _compact else 29)
	var epithet := str(hero.get("epithet", ""))
	if not epithet.is_empty():
		Prep.text(_book, copy, epithet, 16 if _compact else 18, Prep.QUIET)
	if selected:
		Prep.text(_book, copy, "Editing loadout", 17 if _compact else 21, Prep.GOLD, "italic").name = "EditingLoadout_" + id
	else:
		var edit := _paper_button(copy, "EditHero_" + id, "Edit loadout", 17 if _compact else 21)
		edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		edit.accessibility_name = "Edit loadout: " + title
		edit.tooltip_text = edit.accessibility_name
		edit.pressed.connect(func() -> void: hero_edit_requested.emit(id))
	var tools := _book.row(copy, 6 if _compact else 8)
	for delta in [-1, 1]:
		var direction := "Earlier" if delta == -1 else "Later"
		var button := _paper_button(tools, "Party%s_%s" % [direction, id], direction, 16 if _compact else 19)
		button.custom_minimum_size.x = 68 if _compact else 84
		button.accessibility_name = "Move %s %s" % [title, direction.to_lower()]
		button.tooltip_text = button.accessibility_name
		_book.set_disabled(button, index + delta < 0 or index + delta >= filled)
		button.pressed.connect(func() -> void: reorder_requested.emit(id, delta))
	_book.rule(parent, PRINT_RULE)


func _build_folio(parent: VBoxContainer, model: Dictionary, party: Array, hero: Dictionary) -> void:
	parent.add_theme_constant_override("separation", 0)
	var utility := Control.new()
	utility.name = "HelpUtilitySlot"
	utility.custom_minimum_size = Vector2(166, 42)
	utility.size_flags_horizontal = Control.SIZE_SHRINK_END
	utility.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(utility)
	var hint := Control.new()
	hint.name = "HelpHintSlot"
	hint.custom_minimum_size.y = 24
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hint)
	var sheet := _book.material_panel(parent, BoundPage.Surface.POSTING, 21 if _compact else 31,
		24 if _compact else 30, 18 if _compact else 24)
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var live := _book.stack(sheet, 9)
	if _editing_id.is_empty():
		_build_recruits(live, model, party)
	else:
		_build_loadout(live, model, hero)
	_book.rule(live, PRINT_RULE)
	var feedback := str(model.get("feedback", ""))
	if not feedback.is_empty():
		Prep.text(_book, live, feedback, 17, BoundPage.RUST).name = "RecruitmentFeedback"
	var can_depart := bool(model.get("can_depart", false))
	var reason := str(model.get("depart_blocked_reason", ""))
	if not can_depart and not reason.is_empty() and reason != feedback:
		Prep.text(_book, live, reason, 17, Prep.QUIET).name = "DepartureRequirement"
	var forward := Prep.primary(_book, live, "StartAdventure", "Read field reports", 25 if _compact else 32)
	forward.custom_minimum_size.y = 44 if _compact else 57
	_style_departure(forward)
	forward.accessibility_description = "" if can_depart else reason
	_book.set_disabled(forward, not can_depart)
	forward.pressed.connect(func() -> void: depart_requested.emit())


func _build_recruits(parent: VBoxContainer, model: Dictionary, party: Array) -> void:
	_book.strong_text(parent, "Available recruits", 31 if _compact else 38)
	var party_size := int(model.get("party_size", 0))
	var full := party.size() >= party_size
	var guidance := "Choose %d heroes. Use Edit loadout to change a deployed hero’s gear or orders." % party_size
	if full:
		guidance = "Remove a hero to make room for another. Use Edit loadout to change gear or orders."
	Prep.text(_book, parent, guidance, 18, Prep.QUIET)
	_book.rule(parent, PRINT_RULE)
	var scroll := _book.scroll(parent, "RecruitScroll")
	var list := _book.stack(scroll, 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picked: Array = party.map(func(member: Dictionary) -> String: return str(member.id))
	for hero: Dictionary in model.get("heroes", []):
		_build_recruit(list, hero, str(hero.id) in picked, full)


func _build_recruit(parent: Control, hero: Dictionary, picked: bool, full: bool) -> void:
	var id := str(hero.id)
	var title := str(hero.get("name", ""))
	var mounted := Prep.mount(parent, false, false, false,
		Prep.GREEN_PAPER if picked else Color("#faebce"), 10, 8)
	mounted.name = "RecruitCard_" + id
	var row := _book.row(mounted, 12)
	Prep.picture(_book, row, hero.get("portrait") as Texture2D, 68 if _compact else 94)
	var copy := _book.stack(row, 3)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_book.strong_text(copy, title, 22 if _compact else 27)
	var epithet := str(hero.get("epithet", ""))
	if not epithet.is_empty():
		Prep.text(_book, copy, epithet, 16 if _compact else 18, Prep.QUIET)
	var summary := str(hero.get("summary", ""))
	if not summary.is_empty():
		Prep.text(_book, copy, summary, 16 if _compact else 18, Prep.QUIET)
	if picked:
		Prep.text(_book, copy, "In company", 15 if _compact else 18, Prep.FOREST, "italic")
	var toggle := _paper_button(row, "Recruit_" + id, "Remove" if picked else "Recruit", 18 if _compact else 21)
	toggle.custom_minimum_size.x = 84 if _compact else 100
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.accessibility_name = ("Remove " if picked else "Recruit ") + title
	toggle.accessibility_description = "All deployment places are filled." if full and not picked else summary
	toggle.tooltip_text = toggle.accessibility_name
	_book.set_disabled(toggle, full and not picked)
	toggle.pressed.connect(func() -> void: recruit_toggled.emit(id))


func _build_loadout(parent: VBoxContainer, model: Dictionary, hero: Dictionary) -> void:
	var heading := _book.row(parent, 12)
	var identity := _book.stack(heading, 2)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _book.strong_text(identity, str(hero.get("name", "")), 31 if _compact else 42)
	title.name = "LoadoutHero"
	var epithet := str(hero.get("epithet", ""))
	if not epithet.is_empty():
		Prep.text(_book, identity, epithet, 18 if _compact else 21, Prep.QUIET)
	var open_recruits := _paper_button(heading, "RecruitList", "Available recruits", 17 if _compact else 21)
	open_recruits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open_recruits.accessibility_name = "Return to available recruits"
	open_recruits.pressed.connect(func() -> void: recruit_list_requested.emit())
	var scroll := _book.detail_scroll(parent, "LoadoutScroll", 0, "Scroll loadout")
	var panel := _book.stack(scroll, 5 if _compact else 14)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_group(panel, "Offense", model.get("offense", []), "Offense")
	_loadout_group(panel, "Utility", model.get("utility", []), "Utility")
	_loadout_group(panel, "Starting order", model.get("orders", []), "Order")


func _loadout_group(parent: VBoxContainer, title: String, entries: Array, kind: String) -> void:
	_book.rule(parent, PRINT_RULE)
	_book.strong_text(parent, title, 25 if _compact else 30)
	if kind != "Order":
		for entry: Dictionary in entries:
			if bool(entry.get("selected", false)):
				_loadout_row(parent, entry, kind, entries.size())
		for entry: Dictionary in entries:
			if not bool(entry.get("selected", false)):
				_loadout_row(parent, entry, kind, entries.size())
		return
	for entry: Dictionary in entries:
		_loadout_row(parent, entry, kind, entries.size())


func _loadout_row(parent: Control, entry: Dictionary, kind: String, count: int) -> void:
	var id := str(entry.id)
	var label := _action_label(id, str(entry.get("label", "")))
	var selected := bool(entry.get("selected", false))
	var enabled := bool(entry.get("enabled", true))
	var reason := str(entry.get("reason", "")).replace("Requires: ", "Requires ")
	var help := _action_help(id, str(entry.get("help", "")))
	var locked := not enabled and not reason.is_empty()
	var fill := Color("#ead9b9") if locked else (Prep.GREEN_PAPER if selected else Color("#faebce"))
	var sheet := Prep.mount(parent, false, false, false, fill, 8, 4)
	if selected and not locked:
		var frame := sheet.get_theme_stylebox("panel") as StyleBoxFlat
		frame.border_color = Color("#487058")
	var row := _book.row(sheet, 7)
	Prep.mark(row, selected and not locked, locked)
	var title := _book.strong_text(row, label, 21 if _compact else 26, Prep.QUIET if locked else Prep.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var long_reason := locked and reason.length() > 21
	if kind == "Utility" and count == 1:
		var status := Prep.line(_book, row, reason if locked else "Equipped", 18,
			Prep.QUIET if locked else Prep.FOREST)
		status.name = "UtilityStatus_" + id
		status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.tooltip_text = help
	else:
		var chosen_caption := "Selected" if kind == "Order" else "Equipped"
		var normal_caption := "Select" if kind == "Order" else ("Equip Bonk" if id == "healer_bonk" else "Equip")
		var button_text := ("Needs an ability" if long_reason else reason) if locked else \
			(chosen_caption if selected else normal_caption)
		var control_name := "%s_%s" % [kind, id]
		var action := _paper_button(row, control_name, button_text, 17 if _compact else 20)
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		action.accessibility_name = ("%s: %s" % [reason if locked else chosen_caption, label]) if locked or selected \
			else ("Select starting order: " + label if kind == "Order" else "Equip " + label)
		action.accessibility_description = reason if locked else help
		action.tooltip_text = help
		_book.set_disabled(action, not enabled)
		if locked or selected:
			if locked:
				action.add_theme_stylebox_override("disabled", Prep.text_status(fill))
				action.add_theme_color_override("font_disabled_color", Prep.QUIET)
			else:
				action.add_theme_stylebox_override("normal", Prep.text_status(Prep.GREEN_PAPER))
				action.add_theme_color_override("font_color", Prep.FOREST)
		var hero_id := _editing_id
		match kind:
			"Offense":
				action.pressed.connect(func() -> void: offense_requested.emit(hero_id, id))
			"Utility":
				action.pressed.connect(func() -> void: utility_requested.emit(hero_id, id))
			"Order":
				action.pressed.connect(func() -> void: order_requested.emit(hero_id, id))
	var show_help := not locked and not help.is_empty() and (
		(kind == "Offense" and (selected or id == "wizard_blast")) or (kind == "Utility" and count > 1))
	if long_reason or show_help:
		var context := _book.row(parent, 0)
		_book.space(context, 36)
		var detail := Prep.text(_book, context, reason if long_reason else help, 17 if _compact else 21, Prep.QUIET)
		detail.name = ("OrderRequirement_" if long_reason else "AbilityHelp_") + id
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_book.space(context, 12 if _compact else 47)


func _paper_button(parent: Control, id: String, caption: String, points: int) -> Button:
	var button := Prep.small_button(_book, parent, id, caption)
	button.custom_minimum_size.y = 30 if _compact else 35
	button.add_theme_font_size_override("font_size", points)
	_apply_focus(button)
	return button


func _style_departure(action: Button) -> void:
	for state in DEPART_COLORS:
		action.add_theme_stylebox_override(state, BoundPage._box(
			Color(DEPART_COLORS[state]), Color("#193226"), 2, 5, 12, 6))
	_apply_focus(action)


func _apply_focus(control: Button) -> void:
	var focus := _book._focus_ring(FOCUS_INK)
	focus.set_expand_margin_all(2)
	control.add_theme_stylebox_override("focus", focus)


static func _action_label(id: String, label: String) -> String:
	match id:
		"healer_bonk":
			return "Bonk"
		"healer_heal":
			return "Heal"
		_:
			return label


static func _action_help(id: String, help: String) -> String:
	if id == "wizard_blast":
		return "Hits the nearest damageable target, even an ally or obstacle."
	return help


static func _selected_hero(party: Array, id: String) -> Dictionary:
	for hero: Dictionary in party:
		if hero.get("id", "") == id:
			return hero
	return {}


static func _commission_context(model: Dictionary) -> String:
	var commission: Dictionary = model.get("commission", {})
	var parts := PackedStringArray()
	var title := str(model.get("commission_title", commission.get("title", "")))
	if not title.is_empty():
		parts.append(title)
	var count := int(model.get("mission_count", commission.get("length", 0)))
	if count > 0:
		parts.append("%d missions" % count)
	return "  ·  ".join(parts)
