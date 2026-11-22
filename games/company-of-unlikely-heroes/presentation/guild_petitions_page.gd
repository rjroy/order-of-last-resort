extends RefCounted
## A view of what the guild can purchase, not what its company has equipped.

signal back_requested
signal petition_selected(id: String)
signal purchase_requested(id: String)

const GuildBookPage = preload("res://presentation/guild_book_page.gd")
const Art = preload("res://presentation/guild_book_art.gd")
const Prep = preload("res://presentation/guild_prep_widgets.gd")

var _book: GuildBookPage
var _parent: VBoxContainer


func build(book: GuildBookPage, parent: VBoxContainer, model: Dictionary) -> void:
	_book = book
	_parent = parent
	_book.use_preparation_paper(0.55)
	var balance := int(model.get("balance", 0))
	_build_header(parent, balance, str(model.get("return_summary", "")))
	var spread := _book.spread(parent, 0.55, 24)
	var rows: Array = model.get("petitions", [])
	var selected_id := str(model.get("selected_id", ""))
	var selected: Dictionary = _selected_row(rows, selected_id)
	_build_register(spread[0], rows, str(selected.get("id", "")))
	_build_preview(spread[1], selected, balance, str(model.get("feedback", "")))


func focus_control(name: String) -> Control:
	return _parent.find_child(name, true, false) as Control if is_instance_valid(_parent) else null


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


func _build_register(parent: VBoxContainer, rows: Array, selected_id: String) -> void:
	Prep.text(_book, parent, "Available petitions", 33)
	var scroll := _book.scroll(parent, "PetitionScroll")
	var entries := _book.stack(scroll, 14)
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var teaser: Dictionary = {}
	for row: Dictionary in rows:
		if _is_teaser(row):
			teaser = row
			break
	var teaser_added := false
	if rows.is_empty():
		Prep.text(_book, entries, "No petitions are posted yet.", 20, Prep.QUIET)
	for row: Dictionary in rows:
		if _is_teaser(row):
			continue
		_build_slip(entries, row, selected_id)
		if _is_bard(row):
			_build_dependent_note(entries, teaser, _owned(row))
			teaser_added = true
	if not teaser_added and not teaser.is_empty():
		_build_dependent_note(entries, teaser, false)


func _build_slip(parent: Control, record: Dictionary, selected_id: String) -> void:
	var id := str(record.id)
	var selected := id == selected_id
	var slip := Prep.petition_slip(_book, parent, id, selected)
	var content := _book.row(slip.paper, 15)
	var portrait_side := 175.0 if _book.get_viewport_rect().size.x >= 1100 else 104.0
	content.custom_minimum_size.y = portrait_side
	Prep.picture(_book, content, record.get("portrait") as Texture2D, portrait_side)
	var copy := _book.stack(content, 5)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cost := int(record.get("cost", 0))
	var heading := _book.row(copy, 12)
	var title := Prep.text(_book, heading, str(record.get("short_title", record.get("title", ""))), 27)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost_label := Prep.line(_book, heading, _points(cost), 20)
	cost_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	Prep.text(_book, copy, str(record.get("short_summary", record.get("summary", ""))), 21)
	var stamp := "Owned" if _owned(record) else ("Selected" if selected else str(record.get("status_text", "")))
	if not stamp.is_empty() and (selected or _owned(record) or not _can_buy(record)):
		if _owned(record) and selected:
			stamp = "Owned · Selected"
		var tag := Prep.mount(copy, false, false, false,
			Prep.GREEN_PAPER if _owned(record) else Color("#f5d9a9"), 10, 3)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var status := Prep.line(_book, tag, stamp, 17, Prep.FOREST if _owned(record) else Prep.GOLD, "italic")
		status.name = "PetitionStatus_" + id
	slip.action.accessibility_name = str(record.get("title", "")) + ", " + _points(cost)
	slip.action.accessibility_description = str(record.get("summary", ""))
	if not stamp.is_empty():
		slip.action.accessibility_description += ". " + stamp
	slip.action.pressed.connect(func() -> void: petition_selected.emit(id))


func _build_dependent_note(parent: Control, teaser: Dictionary, bard_available: bool) -> void:
	var branch := _book.row(parent, 0)
	branch.name = "SongWeavingNote"
	var line := BranchLine.new()
	line.custom_minimum_size.x = 55
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	branch.add_child(line)
	var sheet := Prep.mount(branch, false, false, false, Prep.LOCKED, 16, 8)
	var row := _book.row(sheet, 10)
	Prep.mark(row, false, true)
	var copy := _book.stack(row, 1)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Prep.text(_book, copy, str(teaser.get("title", "Song Weaving")), 25)
	var state := "Future petition" if bard_available else "Locked · Requires the Bad Bard"
	Prep.text(_book, copy, state, 17, Prep.QUIET)
	Prep.text(_book, copy, "Switch songs to echo the previous song.", 18, Prep.QUIET)


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
	Prep.text(_book, body, title, 40).name = "PetitionPreviewTitle"
	var painting := record.get("plate") as Texture2D
	if painting == null:
		var plate_id := str(record.get("plate_id", ""))
		if plate_id.is_empty():
			plate_id = "bard" if _is_bard(record) else "healer_blast"
		painting = Art.petition(plate_id)
	if painting != null:
		Prep.action_plate(body, painting).name = "PetitionActionPlate"
	var details: Array = record.get("details", [])
	for line_index in details.size():
		if line_index == 1:
			_book.rule(body, Prep.RULE)
		var detail := Prep.text(_book, body, str(details[line_index]), 23)
		detail.name = "PetitionEffect_%d" % line_index
	var note := str(record.get("note", ""))
	if not note.is_empty():
		Prep.text(_book, body, note, 19, Prep.QUIET, "italic").name = "PetitionNote"
	if not feedback.is_empty():
		Prep.text(_book, live, feedback, 16, Prep.INK).name = "PetitionFeedback"
	_build_purchase(live, record, balance)


func _build_purchase(parent: Control, record: Dictionary, balance: int) -> void:
	var id := str(record.id)
	var cost := int(record.get("cost", 0))
	var enabled := _can_buy(record) and not _owned(record)
	var caption := str(record.get("buy_label", "Purchase · " + _points(cost)))
	var next := _points(balance - cost) + " after purchase"
	if _owned(record):
		caption = "Already purchased"
		next = str(record.get("status_text", ""))
	elif not enabled:
		next = str(record.get("status_text", ""))
		if next.is_empty() and balance < cost:
			next = "Need " + _points(cost - balance) + " more"
	var buy := Prep.primary(_book, parent, "PurchasePetition_" + id, caption)
	_book.set_disabled(buy, not enabled)
	buy.pressed.connect(func() -> void: purchase_requested.emit(id))
	if not next.is_empty():
		var remainder := Prep.text(_book, parent, next, 19, Prep.QUIET)
		remainder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buy.accessibility_description = next


static func _selected_row(rows: Array, selected_id: String) -> Dictionary:
	var first: Dictionary = {}
	for row: Dictionary in rows:
		if _is_teaser(row):
			continue
		if first.is_empty():
			first = row
		if row.get("id", "") == selected_id:
			return row
	return first


static func _is_bard(row: Dictionary) -> bool:
	return "bard" in str(row.get("id", "")).to_lower() \
		or "bard" in str(row.get("title", "")).to_lower()


static func _is_teaser(row: Dictionary) -> bool:
	return bool(row.get("teaser", false)) or row.get("id", "") == "song_weaving"


static func _owned(row: Dictionary) -> bool:
	return bool(row.get("owned", row.get("purchased", row.get("status", "") == "owned")))


static func _can_buy(row: Dictionary) -> bool:
	return bool(row.get("can_buy", row.get("purchasable", row.get("status", "") == "available")))


static func _points(amount: int) -> String:
	return "%d %s" % [amount, "point" if amount == 1 else "points"]


class BranchLine extends Control:
	func _draw() -> void:
		var middle := size.y * 0.5
		draw_polyline(PackedVector2Array([Vector2(25, -14), Vector2(25, middle),
			Vector2(size.x, middle)]), Prep.QUIET, 2, true)
