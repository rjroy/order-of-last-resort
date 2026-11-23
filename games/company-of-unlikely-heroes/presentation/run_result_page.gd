extends "res://presentation/guild_bound_page.gd"
## The final leaf reads what happened, then lets the scene handle the return.

const PRINT_RULE := Color("#8e7753")
const ACTION_FILLS := {"normal": "#1e4132", "hover": "#2b5642", "pressed": "#183329"}
const DISCARD_FILLS := {"normal": "#754532", "hover": "#88533c", "pressed": "#5c3527"}
const CONFLICT_TEXT := "The guild or its current board changed. This return was not saved. Discard this outing to load the current ledger; its pending payout will not be credited."

var _compact := false


func populate(page: VBoxContainer, model: Dictionary) -> void:
	var viewport_size := get_viewport_rect().size
	_compact = viewport_size.x < 1100 or viewport_size.y < 700
	bind_cover(29 if _compact else 46, 26 if _compact else 41, 33 if _compact else 48)
	var leaves := spread(page, 0.51, 27 if _compact else 38)
	_build_closing_leaf(leaves[0], model)
	_build_return_leaf(leaves[1], model)


func _build_closing_leaf(leaf: VBoxContainer, model: Dictionary) -> void:
	leaf.add_theme_constant_override("separation", 14 if _compact else 18)
	var success: bool = model.outcome == "victory"
	var masthead := row(leaf, 12 if _compact else 19)
	var stamp := OutcomeStamp.new()
	stamp.success = success
	var side := 78 if _compact else 114
	stamp.custom_minimum_size = Vector2(side, side)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	masthead.add_child(stamp)
	var lettering := stack(masthead, 2)
	lettering.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outcome := strong_text(lettering, "%s\n%s" % [model.outing, "complete" if success else "failed"],
		43 if _compact else 58)
	outcome.name = "RunOutcome"
	outcome.set_meta("outcome", model.outcome)
	outcome.add_theme_constant_override("line_spacing", -6)
	var mission := text(lettering, model.mission_title, 20 if _compact else 28, SUBTLE, "italic")
	_bound_text(mission, "ResultMissionTitle")
	rule(leaf, PRINT_RULE)

	if model.image != null:
		var frame := AspectRatioContainer.new()
		frame.ratio = model.image.get_size().aspect()
		frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
		frame.alignment_vertical = AspectRatioContainer.ALIGNMENT_BEGIN
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		leaf.add_child(frame)
		var art := plate(frame, model.image, Vector2.ZERO, "study" if model.sketch else "crop") as PanelContainer
		art.name = "ResultMissionArt"
		var mount := _box(Color("#f0d5b0"), Color("#b09365"), 1, 3, 1, 1)
		mount.shadow_color = Color(0.33, 0.21, 0.10, 0.23)
		mount.shadow_size = 4
		mount.shadow_offset = Vector2(0, 3)
		art.add_theme_stylebox_override("panel", mount)


func _build_return_leaf(parent: VBoxContainer, model: Dictionary) -> void:
	parent.add_theme_constant_override("separation", 0)
	# Align the receipt with the painting and keep its action close to the ledger.
	var room := clampf((get_viewport_rect().size.y - 700.0) / 120.0, 0.0, 1.0)
	space(parent, 27 if _compact else lerpf(115, 162, room))
	var paper := material_panel(parent, Surface.POSTING, 18 if _compact else 29,
		29 if _compact else 32, 18 if _compact else 25)
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var leaf := stack(paper, 8 if _compact else 13)
	var content := detail_scroll(leaf, "ResultDetailsScroll", 180 if _compact else 230, "Scroll the outing result and return details")
	var record := stack(content, 8 if _compact else 12)
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if model.conflict or not model.return_error.is_empty():
		strong_text(record, "Return not saved", 22 if _compact else 26, RUST).name = "ReturnNotSaved"
		var message: String = CONFLICT_TEXT if model.conflict else model.return_error + " Try returning again."
		text(record, message, 18 if _compact else 21, RUST, "display").name = "ReturnDiagnostic"
		rule(record, PRINT_RULE)
	strong_text(record, "Outing receipt" if not model.receipt.is_empty() else "What happened", 31 if _compact else 36)
	if not model.mission_text.is_empty():
		text(record, model.mission_text, 19 if _compact else 24, INK, "display").name = "ResultMissionText"
	if not model.receipt.is_empty():
		_build_receipt(record, model.receipt)

	rule(leaf, PRINT_RULE)
	var action: Button
	if model.conflict:
		action = button(leaf, "ReloadGuild", "Discard outing and load current guild", "ClothButton")
		action.pressed.connect(model.discard)
	else:
		var caption := "Return to guild" if model.return_error.is_empty() else "Retry return"
		action = button(leaf, "ReturnToGuild", caption, "ClothButton")
		action.pressed.connect(model.return)
		if not model.return_error.is_empty():
			action.accessibility_description = "Retry saving this outing’s return."
	_style_action(action, model.conflict)
	if not model.conflict:
		var direction := "Back to guild recruitment." if model.guild_name.is_empty() else (
			"Back to %s’s commission board." % model.guild_name)
		_bound_text(text(leaf, direction, 18 if _compact else 20, SUBTLE, "italic"), "ResultReturnContext")
	if not _compact:
		space(parent, lerpf(30, 99, room))
	action.grab_focus()


func _build_receipt(parent: VBoxContainer, receipt: Array) -> void:
	rule(parent, PRINT_RULE)
	var ledger := stack(parent, 6 if _compact else 8)
	for item: Dictionary in receipt:
		var total: bool = item.id == "Total"
		if total:
			rule(ledger, PRINT_RULE)
		var entry := row(ledger, 11)
		entry.name = "Receipt" + item.id
		var size := (29 if _compact else 36) if total else (20 if _compact else 25)
		var caption: String = item.id + item.note
		var heading := strong_text(entry, caption, size) if total else text(entry, caption, size, INK, "display")
		heading.name = "ReceiptLabel"
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := strong_text(entry, item.value, size) if total else text(entry, item.value, size, INK, "display")
		value.name = "ReceiptValue"
		value.autowrap_mode = TextServer.AUTOWRAP_OFF


func _bound_text(label: Label, node_name: String) -> void:
	label.name = node_name
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.accessibility_name = label.text
	label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_PASS


func _style_action(action: Button, conflict: bool) -> void:
	action.add_theme_font_override("font", _strong_face)
	action.add_theme_font_size_override("font_size", (20 if _compact else 24) if conflict else (24 if _compact else 31))
	action.custom_minimum_size.y = 46 if _compact else 57
	var fills := DISCARD_FILLS if conflict else ACTION_FILLS
	for state in fills:
		var fill := Color(fills[state])
		action.add_theme_stylebox_override(state, _box(fill, fill.darkened(0.32), 2, 5, 13, 5))
	var focus := _focus_ring(FOCUS_GOLD)
	focus.set_expand_margin_all(3)
	action.add_theme_stylebox_override("focus", focus)


class OutcomeStamp extends Control:
	var success := false

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) * 0.43
		var ink := Color("#264936") if success else Color("#874732")
		if success:
			for side in [-1, 1]:
				var stem := PackedVector2Array()
				for index in 27:
					var angle := lerpf(0.05, 2.52, index / 26.0)
					stem.append(center + Vector2(side * sin(angle), cos(angle)) * radius * 0.85)
				draw_polyline(stem, ink, 1.7, true)
				for index in 8:
					var angle := lerpf(0.23, 2.47, index / 7.0)
					var out := Vector2(side * sin(angle), cos(angle))
					var tangent := Vector2(side * cos(angle), -sin(angle))
					var spot := center + out * radius * 0.85
					_leaf(spot, (out + tangent * 0.9).normalized(), radius * 0.25, ink)
					if index < 7:
						_leaf(spot, (tangent - out * 0.78).normalized(), radius * 0.20, ink)
			_stroke(center, radius, [Vector2(-0.55, -0.02), Vector2(-0.20, 0.36), Vector2(0.56, -0.47)], ink)
		else:
			for segment in 5:
				var start := segment * TAU / 5.0 + 0.13
				draw_arc(center, radius, start, start + 1.05, 18, ink, 4.6, true)
			draw_arc(center, radius - 6.0, 0.0, TAU, 58, ink, 1.3, true)
			_stroke(center, radius, [Vector2(-0.43, -0.43), Vector2(0.43, 0.43)], ink)
			_stroke(center, radius, [Vector2(0.43, -0.43), Vector2(-0.43, 0.43)], ink)

	func _stroke(center: Vector2, radius: float, points: Array, ink: Color) -> void:
		var line := PackedVector2Array()
		for point: Vector2 in points:
			line.append(center + point * radius)
		draw_polyline(line, ink, radius * 0.16, true)

	func _leaf(spot: Vector2, direction: Vector2, length: float, ink: Color) -> void:
		var end := spot + direction * length
		var mid := spot.lerp(end, 0.51)
		var edge := direction.orthogonal() * length * 0.26
		draw_colored_polygon(PackedVector2Array([spot, mid + edge, end, mid - edge]), ink)
