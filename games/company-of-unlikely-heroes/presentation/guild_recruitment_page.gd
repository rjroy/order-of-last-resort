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

const GuildBookPage = preload("res://presentation/guild_book_page.gd")
const Prep = preload("res://presentation/guild_prep_widgets.gd")

var _book: GuildBookPage
var _parent: VBoxContainer
var _editing_id := ""


func build(book: GuildBookPage, parent: VBoxContainer, model: Dictionary) -> void:
	_book = book
	_parent = parent
	_book.use_preparation_paper(0.43)
	var spread := _book.spread(parent, 0.43, 22)
	var party: Array = model.get("party", [])
	var hero := _selected_hero(party, str(model.get("selected_hero_id", "")))
	_editing_id = str(hero.get("id", "")) if model.get("folio", "recruits") == "loadout" else ""
	_build_deployment(spread[0], model, party)
	_build_folio(spread[1], model, party, hero)


func focus_control(name: String) -> Control:
	return _parent.find_child(name, true, false) as Control if is_instance_valid(_parent) else null


func _build_deployment(parent: VBoxContainer, model: Dictionary, party: Array) -> void:
	var compact := _book.get_viewport_rect().size.x < 1100
	if compact:
		parent.add_theme_constant_override("separation", 6)
	var back := Prep.back(_book, parent)
	back.pressed.connect(func() -> void: back_requested.emit())
	Prep.text(_book, parent, "Choose your company", 34 if compact else 42)
	var context := _commission_context(model)
	if not context.is_empty():
		Prep.text(_book, parent, context, 20, Prep.QUIET).name = "CommissionContext"
	_book.rule(parent, Prep.RULE)
	Prep.text(_book, parent, "Deployment order", 34)
	Prep.text(_book, parent, "Heroes act from top to bottom.", 19, Prep.QUIET, "italic")
	var party_size := int(model.get("party_size", 0))
	Prep.text(_book, parent, "%d of %d selected" % [party.size(), party_size], 21, Prep.FOREST).name = "PartyCount"
	_book.rule(parent, Prep.RULE)
	var scroll := _book.scroll(parent, "DeploymentScroll")
	var list := _book.stack(scroll, 5 if compact else 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in party_size:
		_build_slot(list, party[index] if index < party.size() else {}, index, party.size(), compact)


func _build_slot(parent: Control, hero: Dictionary, index: int, filled: int, compact: bool) -> void:
	var id := str(hero.get("id", ""))
	var selected := not id.is_empty() and id == _editing_id
	var fill := Color("#f6dfb5") if selected else Color.TRANSPARENT
	var mounted := Prep.mount(parent, selected, false, false, fill, 10, 5)
	var row := _book.row(mounted, 9 if compact else 11)
	var portrait_side := 83.0 if compact else 121.0
	row.custom_minimum_size.y = portrait_side if not id.is_empty() else 44
	var number := Prep.line(_book, row, "%02d" % (index + 1), 27 if compact else 31, GuildBookPage.RUST)
	number.custom_minimum_size.x = 34 if compact else 44
	number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if id.is_empty():
		var place := Prep.line(_book, row, "Open place", 23, Prep.QUIET, "italic")
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		place.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_book.rule(parent, Prep.RULE)
		return
	Prep.picture(_book, row, hero.get("portrait") as Texture2D, portrait_side)
	var copy := _book.stack(row, 2 if compact else 3)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := str(hero.get("name", ""))
	Prep.text(_book, copy, title, 22 if compact else 26)
	var edit := _book.button(copy, "EditHero_" + id, "Edit loadout")
	edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	edit.custom_minimum_size.y = 32 if compact else 35
	edit.accessibility_name = "Edit loadout: " + title
	edit.tooltip_text = edit.accessibility_name
	if selected:
		edit.accessibility_description = "Editing loadout"
	edit.pressed.connect(func() -> void: hero_edit_requested.emit(id))
	var tools := _book.row(copy, 6)
	for delta in [-1, 1]:
		var direction := "Earlier" if delta == -1 else "Later"
		var button := Prep.small_button(_book, tools, "Party%s_%s" % [direction, id], direction)
		if compact:
			button.custom_minimum_size.y = 32
		button.accessibility_name = "Move %s %s" % [title, direction.to_lower()]
		button.tooltip_text = button.accessibility_name
		_book.set_disabled(button, index + delta < 0 or index + delta >= filled)
		button.pressed.connect(func() -> void: reorder_requested.emit(id, delta))
	if selected:
		var state := Prep.text(_book, tools, "Editing" if compact else "Editing loadout",
			16 if compact else 18, Prep.GOLD, "italic")
		state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_book.rule(parent, Prep.RULE)


func _build_folio(parent: VBoxContainer, model: Dictionary, party: Array, hero: Dictionary) -> void:
	_book.space(parent, 32)
	var sheet := Prep.mount(parent, false, true, true, Color("#f7e3c0"), 22, 18)
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var live := _book.stack(sheet, 9)
	if _editing_id.is_empty():
		_build_recruits(live, model, party)
	else:
		_build_loadout(live, model, hero)
	_book.rule(live, Prep.RULE)
	var feedback := str(model.get("feedback", ""))
	if not feedback.is_empty():
		Prep.text(_book, live, feedback, 17, GuildBookPage.RUST).name = "RecruitmentFeedback"
	var can_depart := bool(model.get("can_depart", false))
	var reason := str(model.get("depart_blocked_reason", ""))
	if not can_depart and not reason.is_empty() and reason != feedback:
		Prep.text(_book, live, reason, 17, Prep.QUIET).name = "DepartureRequirement"
	var forward := Prep.primary(_book, live, "StartAdventure", "Read field reports", 28)
	forward.accessibility_description = "" if can_depart else reason
	_book.set_disabled(forward, not can_depart)
	forward.pressed.connect(func() -> void: depart_requested.emit())


func _build_recruits(parent: VBoxContainer, model: Dictionary, party: Array) -> void:
	Prep.text(_book, parent, "Available recruits", 35)
	var party_size := int(model.get("party_size", 0))
	var full := party.size() >= party_size
	var guidance := "Choose %d heroes. Use Edit loadout to change a deployed hero’s gear or orders." % party_size
	if full:
		guidance = "Remove a hero to make room for another. Use Edit loadout to change gear or orders."
	Prep.text(_book, parent, guidance, 18, Prep.QUIET)
	_book.rule(parent, Prep.RULE)
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
		Prep.GREEN_PAPER if picked else Color("#faebce"), 10, 7)
	mounted.name = "RecruitCard_" + id
	var row := _book.row(mounted, 12)
	Prep.picture(_book, row, hero.get("portrait") as Texture2D, 82)
	var copy := _book.stack(row, 3)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Prep.text(_book, copy, title, 24)
	var summary := str(hero.get("summary", ""))
	if not summary.is_empty():
		Prep.text(_book, copy, summary, 16, Prep.QUIET)
	var toggle := Prep.small_button(_book, row, "Recruit_" + id, "Remove" if picked else "Recruit")
	toggle.custom_minimum_size.x = 88
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.accessibility_name = ("Remove " if picked else "Recruit ") + title
	toggle.accessibility_description = "The three places are filled." if full and not picked else summary
	toggle.tooltip_text = toggle.accessibility_name
	_book.set_disabled(toggle, full and not picked)
	toggle.pressed.connect(func() -> void: recruit_toggled.emit(id))


func _build_loadout(parent: VBoxContainer, model: Dictionary, hero: Dictionary) -> void:
	var heading := _book.row(parent, 12)
	var title := Prep.text(_book, heading, str(hero.get("name", "")), 39)
	title.name = "LoadoutHero"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var open_recruits := _book.button(heading, "RecruitList", "Available recruits", "QuietButton")
	open_recruits.custom_minimum_size.y = 34
	open_recruits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open_recruits.accessibility_name = "Return to available recruits"
	open_recruits.pressed.connect(func() -> void: recruit_list_requested.emit())
	var scroll := _book.detail_scroll(parent, "LoadoutScroll", 0, "Scroll loadout")
	var panel := _book.stack(scroll, 7)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_group(panel, "Offense", model.get("offense", []), "Offense")
	_loadout_group(panel, "Utility", model.get("utility", []), "Utility")
	_loadout_group(panel, "Starting order", model.get("orders", []), "Order")


func _loadout_group(parent: VBoxContainer, title: String, entries: Array, kind: String) -> void:
	_book.rule(parent, Prep.RULE)
	Prep.text(_book, parent, title, 29)
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
	var fill := Prep.LOCKED if locked else (Prep.GREEN_PAPER if selected else Color("#faebce"))
	var sheet := Prep.mount(parent, false, false, false, fill, 8, 4)
	var row := _book.row(sheet, 7)
	Prep.mark(row, selected and not locked, locked)
	var title := Prep.text(_book, row, label, 22, Prep.QUIET if locked else Prep.INK)
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
		var normal_caption := "Select" if kind == "Order" else "Equip"
		var button_text := ("Needs an ability" if long_reason else reason) if locked else \
			(chosen_caption if selected else normal_caption)
		var control_name := "%s_%s" % [kind, id]
		var action := Prep.small_button(_book, row, control_name, button_text)
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		action.accessibility_name = ("%s: %s" % [reason if locked else chosen_caption, label]) if locked or selected \
			else ("Select starting order: " + label if kind == "Order" else "Equip " + label)
		action.accessibility_description = reason if locked else help
		action.tooltip_text = help
		_book.set_disabled(action, not enabled)
		if locked or selected:
			if locked:
				action.add_theme_stylebox_override("disabled", Prep.text_status(Prep.LOCKED))
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
		var detail := Prep.text(_book, context, reason if long_reason else help, 18, Prep.QUIET)
		detail.name = ("OrderRequirement_" if long_reason else "AbilityHelp_") + id
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL


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
