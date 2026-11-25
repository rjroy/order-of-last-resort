extends "res://presentation/book/guild_bound_page.gd"
## Compose the authored postings. Offer selection and save state stay with the scene.

const PRINT_RULE := Color("#8c7654")
const LONG_STAMP := Color("#97471f")

var _compact := false
var _illustrated_postings: Array[Dictionary] = []
var _fit_queued := false


func populate(page: VBoxContainer, model: Dictionary) -> void:
	var viewport_size := get_viewport_rect().size
	_compact = viewport_size.x < 1100 or viewport_size.y < 700
	bind_cover(26 if _compact else 32, 24 if _compact else 39, 30 if _compact else 43)
	page.add_theme_constant_override("separation", 10 if _compact else 16)
	_build_header(page, model.guild_name, model.balance, model.petitions)
	var hint := Control.new()
	hint.name = "HelpHintSlot"
	hint.custom_minimum_size.y = 24
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(hint)
	rule(page, PRINT_RULE)
	_build_board_status(page, model.refresh_failed, model.receipt)

	var postings := row(page, 10 if _compact else 12)
	postings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions: Array[Button] = []
	for index in model.postings.size():
		actions.append(_build_posting(postings, index, model.postings[index]))
	for index in range(1, actions.size()):
		var left := actions[index - 1]
		var right := actions[index]
		left.focus_neighbor_right = left.get_path_to(right)
		right.focus_neighbor_left = right.get_path_to(left)
	var foot := row(page, 12)
	space(foot, 8 if _compact else 14)
	var note := text(foot, "The mission count includes the final mission.", 17 if _compact else 21, INK, "italic")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var replay_practice: Callable = model.get("replay_practice", Callable())
	if replay_practice.is_valid():
		var replay := button(foot, "ReplayPractice", "Replay practice", "QuietButton")
		replay.tooltip_text = "Repeat the Founders’ Drill with the three starter heroes. No guild progress changes."
		replay.accessibility_description = replay.tooltip_text
		replay.pressed.connect(replay_practice)
	if not actions.is_empty():
		actions[0].grab_focus()
	_queue_illustration_fit()


func _build_header(page: Control, guild_name: String, points: int, open_petitions: Callable) -> void:
	var masthead := row(page, 24)
	var inset_title := MarginContainer.new()
	inset_title.add_theme_constant_override("margin_left", 8 if _compact else 14)
	inset_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_child(inset_title)
	var heading := stack(inset_title, -3)
	strong_text(heading, "Commission board", 41 if _compact else 50)
	var guild := text(heading, guild_name, 19 if _compact else 24, SUBTLE, "display")
	guild.max_lines_visible = 2
	guild.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	guild.tooltip_text = guild_name
	var ledger := row(masthead, 14 if _compact else 24)
	ledger.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if open_petitions.is_valid():
		var balance := text(ledger, "Guild points: %d" % points, 19 if _compact else 25, INK, "display")
		balance.autowrap_mode = TextServer.AUTOWRAP_OFF
		balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var petitions := button(ledger, "Petitions", "Guild petitions")
		petitions.custom_minimum_size = Vector2(147, 39) if _compact else Vector2(202, 49)
		_style_button(petitions, 20 if _compact else 25, false)
		petitions.pressed.connect(open_petitions)
	var utility := Control.new()
	utility.name = "HelpUtilitySlot"
	utility.custom_minimum_size = Vector2(166, 42)
	utility.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ledger.add_child(utility)


func _build_board_status(page: Control, refresh_failed: bool, receipt: String) -> void:
	if not refresh_failed and receipt.is_empty():
		return
	var notices := stack(page, 4)
	if refresh_failed:
		text(notices, "The board wasn’t refreshed. These commissions are from the current saved guild.",
			17 if _compact else 20, RUST, "display")
	if not receipt.is_empty():
		text(notices, receipt, 16 if _compact else 19, SUBTLE, "display")


func _build_posting(row_of_postings: Control, index: int, offer: Dictionary) -> Button:
	var sheet := material_panel(row_of_postings, Surface.POSTING,
		14 if _compact else 20, 27 if _compact else 29, 17 if _compact else 25)
	sheet.name = "CommissionCard_%d" % index
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var contents := stack(sheet, 10 if _compact else 11)
	var illustration: Control
	if offer.painting != null:
		illustration = plate(contents, offer.painting, Vector2.ZERO)

	var region := detail_scroll(contents, "CommissionDetails_%d" % index, 88 if _compact else 100,
		"Scroll details for " + offer.title)
	var detail := stack(region, 8 if _compact else 9)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var destination := strong_text(detail, offer.title, 30 if _compact else 38)
	destination.add_theme_constant_override("line_spacing", -5)
	destination.custom_minimum_size.y = 60 if _compact else 73
	_mission_stamp(detail, offer.length)
	text(detail, offer.description, 18 if _compact else 20, INK, "display").name = "CommissionText_%d" % index
	if illustration != null:
		_illustrated_postings.append({"art": illustration, "region": region, "detail": detail})
		region.resized.connect(_queue_illustration_fit)
		detail.minimum_size_changed.connect(_queue_illustration_fit)

	rule(contents, PRINT_RULE)
	var choose := button(contents, "Commission_%d" % index, "Choose commission", "ClothButton")
	choose.custom_minimum_size.y = 45 if _compact else 53
	choose.accessibility_name = "Choose commission: " + offer.title
	choose.accessibility_description = "%d missions. %s" % [offer.length, offer.description]
	_style_button(choose, 22 if _compact else 30, true)
	choose.pressed.connect(offer.choose)
	return choose


func _queue_illustration_fit() -> void:
	if _illustrated_postings.is_empty() or _fit_queued:
		return
	_fit_queued = true
	_fit_illustrations.call_deferred()


func _fit_illustrations() -> void:
	_fit_queued = false
	if not is_inside_tree():
		return
	# Keep paired paintings aligned. Give the longest actual posting the space
	# it needs before spending the remainder on art. The scroll region still
	# handles copy that cannot fit at smaller sizes or unusually long content.
	var height := 145.0 if _compact else 229.0
	for posting in _illustrated_postings:
		var budget: float = posting.art.size.y + posting.region.size.y
		if posting.region.size.x <= 0.0 or budget <= 0.0:
			return # The region's resize signal will retry after container layout.
		var text_height: float = posting.detail.get_combined_minimum_size().y
		height = minf(height, floorf(budget - text_height))
	height = maxf(height, 52.0 if _compact else 80.0)
	for posting in _illustrated_postings:
		posting.art.custom_minimum_size.y = height


func _mission_stamp(detail: Control, length: int) -> void:
	var long_offer := length == 10
	var badge := PanelContainer.new()
	var fill := Color("#f5e4c1") if long_offer else Color("#f0d9af")
	var edge := LONG_STAMP if long_offer else Color("#a68958")
	badge.add_theme_stylebox_override("panel", _box(fill, edge, 2 if long_offer else 1, 4, 12,
		3 if _compact else 5))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	detail.add_child(badge)
	text(badge, "%d missions" % length, 19 if _compact else 23,
		LONG_STAMP if long_offer else INK, "display").autowrap_mode = TextServer.AUTOWRAP_OFF


func _style_button(action: Button, points: int, primary: bool) -> void:
	action.add_theme_font_override("font", _face)
	action.add_theme_font_size_override("font_size", points)
	var fills := [Color("#1d3f32"), Color("#2a5242"), Color("#172f26")] if primary \
		else [Color("#f4e2bd"), Color("#faeccd"), Color("#e4cda2")]
	var edge := Color("#152b22") if primary else Color("#7e623d")
	for index in fills.size():
		var state: String = ["normal", "hover", "pressed"][index]
		var face := _box(fills[index], edge, 2 if primary else 1, 5, 10, 4)
		if not primary and index != 2:
			face.shadow_color = Color(0.25, 0.14, 0.06, 0.24)
			face.shadow_size = 3
			face.shadow_offset = Vector2(0, 2)
		action.add_theme_stylebox_override(state, face)
	var focus := _focus_ring(FOCUS_GOLD)
	focus.set_expand_margin_all(3)
	action.add_theme_stylebox_override("focus", focus)
