extends RefCounted
## A view of what the guild can purchase, not what its company has equipped.

signal back_requested
signal petition_selected(id: String)
signal purchase_requested(id: String)
signal filter_changed(hero_id: String)

const GuildBookPage = preload("res://presentation/guild_book_page.gd")
const Prep = preload("res://presentation/guild_prep_widgets.gd")
const ViewModel = preload("res://presentation/guild_petition_view_model.gd")

var _book: GuildBookPage
var _parent: VBoxContainer
var _compact := false
var _selected_id := ""
var _register_ids := PackedStringArray()


func build(book: GuildBookPage, parent: VBoxContainer, model: Dictionary) -> void:
	_book = book
	_parent = parent
	_compact = book.get_viewport_rect().size.x < 1100
	_book.use_preparation_paper(0.55)
	var balance := int(model.get("balance", 0))
	_build_header(parent, balance, str(model.get("return_summary", "")))
	var spread := _book.spread(parent, 0.55, 24)
	var options: Array = model.get("hero_filter_options", [])
	var hero_filter := str(model.get("hero_filter", ""))
	var groups := _groups(model.get("petitions", []), options, hero_filter)
	var selected := _selected_row(groups, str(model.get("selected_id", "")))
	_selected_id = str(selected.get("id", ""))
	_register_ids.clear()
	_build_register(spread[0], groups, options, hero_filter)
	_build_preview(spread[1], selected, balance, str(model.get("feedback", "")))


func focus_control(name: String) -> Control:
	if not is_instance_valid(_parent):
		return null
	var control := _parent.find_child(name, true, false) as Control
	if control == null and name.begins_with("Petition_"):
		return _parent.find_child("Petition_" + _selected_id, true, false) as Control \
			if not _selected_id.is_empty() else _parent.find_child("PetitionHeroFilter", true, false) as Control
	return control


func _build_header(parent: VBoxContainer, balance: int, return_summary: String) -> void:
	var header := _book.stack(parent, 3)
	var back := Prep.back(_book, header)
	back.pressed.connect(func() -> void: back_requested.emit())
	var heading := _book.row(header, 16)
	var title := Prep.line(_book, heading, "Guild unlocks", 49)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var points := _book.row(heading, 8)
	points.name = "GuildPointBalance"
	points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Prep.line(_book, points, str(balance), 48, GuildBookPage.RUST)
	var unit := Prep.line(_book, points, "guild point" if balance == 1 else "guild points", 26)
	unit.name = "GuildPointUnit"
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not return_summary.is_empty():
		var account := Prep.text(_book, header, return_summary, 20, Prep.QUIET)
		account.name = "PetitionReturnSummary"
	_book.rule(parent, Prep.RULE)


func _build_register(parent: VBoxContainer, groups: Dictionary, options: Array, hero_filter: String) -> void:
	var heading := _book.row(parent, 12)
	var title := Prep.text(_book, heading, "Petition register", 28 if _compact else 33)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_build_filter(heading, options, hero_filter)
	var scroll := _book.scroll(parent, "PetitionScroll")
	var entries := _book.stack(scroll, 11)
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if groups.is_empty():
		Prep.text(_book, entries, "No petitions are posted for this hero.", 20, Prep.QUIET)
	for hero_id: String in groups:
		var rows: Array = groups[hero_id]
		var section := _book.stack(entries, 6)
		if not hero_id.is_empty():
			section.name = "PetitionGroup_" + hero_id
			_build_group_heading(section, rows[0])
		for row: Dictionary in rows:
			_register_ids.append(str(row.id))
			_build_slip(section, row)


func _build_filter(parent: Control, options: Array, hero_filter: String) -> void:
	if options.is_empty():
		return
	var filter := OptionButton.new()
	filter.name = "PetitionHeroFilter"
	filter.custom_minimum_size.y = 40
	filter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	filter.accessibility_name = "Filter petitions by hero"
	filter.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	filter.add_item("All heroes")
	filter.set_item_metadata(0, "")
	var selected := 0
	for option: Dictionary in options:
		var id := str(option.id)
		if id.is_empty():
			continue
		filter.add_item(str(option.label))
		var index := filter.item_count - 1
		filter.set_item_metadata(index, id)
		if id == hero_filter:
			selected = index
	filter.select(selected)
	parent.add_child(filter)
	filter.item_selected.connect(func(index: int) -> void:
		filter_changed.emit(str(filter.get_item_metadata(index))))


func _build_group_heading(parent: Control, record: Dictionary) -> void:
	var heading := _book.row(parent, 10)
	Prep.picture(_book, heading, record.get("portrait") as Texture2D, 36 if _compact else 44)
	var label := Prep.text(_book, heading, str(record.get("recipient_label", "")), 24, Prep.QUIET)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_book.rule(parent, Prep.RULE)


func _build_slip(parent: Control, record: Dictionary) -> void:
	var id := str(record.id)
	var selected := id == _selected_id
	var slip := Prep.petition_slip(_book, parent, id, selected)
	var copy := _book.stack(slip.paper, 3)
	var heading := _book.row(copy, 10)
	var title := Prep.text(_book, heading, str(record.get("short_title", record.get("title", ""))),
		22 if _compact else 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost_text := _points(int(record.get("cost", 0))) if _has_price(record) else ""
	if not cost_text.is_empty():
		var cost_label := Prep.line(_book, heading, cost_text, 18, Prep.QUIET)
		cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var subline := _book.row(copy, 8)
	var summary := Prep.text(_book, subline, str(record.get("short_summary", "")), 17, Prep.QUIET)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var stamp := _status_label(record)
	if selected and stamp == "Available":
		stamp = "Selected"
	var tag := Prep.mount(subline, false, false, false,
		Prep.GREEN_PAPER if _owned(record) else (Color("#f5d9a9") if selected else Color.TRANSPARENT),
		6, 1)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_END
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var status := Prep.line(_book, tag, stamp, 16, Prep.FOREST if _owned(record) else Prep.QUIET, "italic")
	status.name = "PetitionStatus_" + id
	slip.action.accessibility_name = str(record.get("title", ""))
	if not cost_text.is_empty():
		slip.action.accessibility_name += ", " + cost_text
	slip.action.accessibility_description = str(record.get("summary", ""))
	slip.action.accessibility_description += " " + stamp
	var requirement := str(record.get("requirement", ""))
	if not requirement.is_empty():
		slip.action.accessibility_description += ". " + requirement
	# The selected row is the register's Tab stop; all rows remain clickable.
	slip.action.focus_mode = Control.FOCUS_ALL if selected else Control.FOCUS_CLICK
	slip.action.pressed.connect(func() -> void: petition_selected.emit(id))
	slip.action.gui_input.connect(_register_input.bind(slip.action, id))


func _register_input(event: InputEvent, action: Button, id: String) -> void:
	var index := _register_ids.find(id)
	var target := index
	if event.is_action_pressed("ui_up", true):
		target = maxi(0, index - 1)
	elif event.is_action_pressed("ui_down", true):
		target = mini(_register_ids.size() - 1, index + 1)
	elif event.is_action_pressed("ui_home"):
		target = 0
	elif event.is_action_pressed("ui_end"):
		target = _register_ids.size() - 1
	else:
		return
	action.accept_event()
	if target != index:
		petition_selected.emit(_register_ids[target])


func _build_preview(parent: VBoxContainer, record: Dictionary, balance: int, feedback: String) -> void:
	if record.is_empty():
		Prep.text(_book, parent, "Choose a petition to read it here.", 24, Prep.QUIET)
		return
	var sheet := Prep.mount(parent, false, true, true, Color("#f7e0ba"), 22, 19)
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var live := _book.stack(sheet, 10)
	var scroll := _book.detail_scroll(live, "PetitionPreviewScroll", 0, "Scroll purchase details")
	var body := _book.stack(scroll, 9)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := str(record.get("preview_title", record.get("title", "")))
	var painting := ViewModel.action_plate(str(record.id))
	if painting != null:
		_build_preview_heading(body, title)
		var print := Prep.action_plate(body, painting)
		print.name = "PetitionActionPlate"
		print.custom_minimum_size.y = 145 if _compact else 215
	else:
		var heading := _book.row(body, 14)
		var portrait := record.get("portrait") as Texture2D
		if portrait != null:
			var art := _book.plate(heading, portrait, Vector2.ONE * (84 if _compact else 120), "portrait")
			art.name = "PetitionRecipientPortrait"
			art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var copy := _book.stack(heading, 4)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_build_preview_heading(copy, title, str(record.get("recipient_label", "")))
	var details: Array = record.get("details", [])
	for line_index in details.size():
		if line_index == 1:
			_book.rule(body, Prep.RULE)
		var detail := Prep.text(_book, body, str(details[line_index]), 20 if _compact else 23)
		detail.name = "PetitionEffect_%d" % line_index
	var requirement := str(record.get("requirement", ""))
	if not requirement.is_empty():
		Prep.text(_book, body, requirement, 19, Prep.GOLD).name = "PetitionRequirement"
	var note := str(record.get("note", ""))
	if not note.is_empty():
		Prep.text(_book, body, note, 19, Prep.QUIET, "italic").name = "PetitionNote"
	if not feedback.is_empty():
		Prep.text(_book, live, feedback, 16, Prep.INK).name = "PetitionFeedback"
	_build_purchase(live, record, balance)


func _build_preview_heading(parent: Control, title: String, recipient := "") -> void:
	Prep.text(_book, parent, title, 33 if _compact else 40).name = "PetitionPreviewTitle"
	if not recipient.is_empty() and recipient != title:
		Prep.text(_book, parent, recipient, 18, Prep.QUIET).name = "PetitionRecipient"


func _build_purchase(parent: Control, record: Dictionary, balance: int) -> void:
	var id := str(record.id)
	var cost := int(record.get("cost", 0))
	var enabled := bool(record.get("can_buy", false)) and not _owned(record)
	var caption := "%s · %s" % [str(record.get("buy_label", "Purchase")), _points(cost)]
	var next := _points(balance - cost) + " after purchase"
	if _owned(record):
		caption = "Already recruited" if record.get("grant_kind") == "recruit" else "Already purchased"
		next = ""
	elif not _has_price(record):
		caption = "Future petition"
		next = ""
	elif not enabled:
		next = str(record.get("requirement", ""))
		if next.is_empty() and balance < cost:
			next = "Need " + _points(cost - balance) + " more"
	var buy := Prep.primary(_book, parent, "PurchasePetition_" + id, caption)
	_book.set_disabled(buy, not enabled)
	buy.pressed.connect(func() -> void: purchase_requested.emit(id))
	if not next.is_empty():
		var remainder := Prep.text(_book, parent, next, 19, Prep.QUIET)
		remainder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buy.accessibility_description = next


static func _groups(rows: Array, options: Array, hero_filter: String) -> Dictionary:
	var groups := {}
	for option: Dictionary in options:
		var id := str(option.id)
		if not id.is_empty() and (hero_filter.is_empty() or id == hero_filter):
			groups[id] = []
	for row: Dictionary in rows:
		var id := str(row.get("hero_id", ""))
		if not hero_filter.is_empty() and hero_filter != id:
			continue
		if not groups.has(id):
			groups[id] = []
		groups[id].append(row)
	for id in groups.keys():
		var entries: Array = groups[id]
		if entries.is_empty():
			groups.erase(id)
			continue
		var recruit := entries.filter(func(row: Dictionary) -> bool: return row.get("grant_kind") == "recruit")
		var training := entries.filter(func(row: Dictionary) -> bool: return row.get("grant_kind") != "recruit")
		groups[id] = recruit + training
	return groups


static func _selected_row(groups: Dictionary, selected_id: String) -> Dictionary:
	var first: Dictionary = {}
	for rows: Array in groups.values():
		for row: Dictionary in rows:
			if first.is_empty():
				first = row
			if row.get("id", "") == selected_id:
				return row
	return first


static func _status_label(row: Dictionary) -> String:
	match row.get("status", "available"):
		"owned":
			return "Owned"
		"locked":
			return "Requires unlock"
		"unaffordable":
			return "Need points"
		"teaser":
			return "Future petition"
	return "Available"


static func _owned(row: Dictionary) -> bool:
	return bool(row.get("owned", row.get("purchased", row.get("status", "") == "owned")))


static func _has_price(row: Dictionary) -> bool:
	return bool(row.get("purchasable", row.get("status", "") != "teaser"))


static func _points(amount: int) -> String:
	return "%d %s" % [amount, "point" if amount == 1 else "points"]
