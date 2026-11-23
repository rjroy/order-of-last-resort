extends "res://presentation/guild_bound_page.gd"
## Single-leaf diagnostics. The caller owns the error, its context and any action.

const INK_RULE := Color("#8e7753")

var _compact: bool


func heading(page: VBoxContainer, title: String, context: String) -> void:
	var viewport_size := get_viewport_rect().size
	_compact = viewport_size.x < 1080 or viewport_size.y < 720
	bind_cover(60 if _compact else 102, 56 if _compact else 99, 44 if _compact else 68, true)
	page.add_theme_constant_override("separation", 0)
	strong_text(page, title, 47 if _compact else 63)
	space(page, 4 if _compact else 14)
	text(page, context, 25 if _compact else 32, INK, "display")
	space(page, 17 if _compact else 25)
	rule(page, INK_RULE)
	space(page, 16 if _compact else 22)


func error_detail(page: VBoxContainer, node_name: String, message: String) -> void:
	var label := _detail_text(page, node_name, message, 29 if _compact else 43,
		RUST, "Scroll error details", 0.16)
	label.add_theme_font_override("font", _strong_face)


func file_detail(page: VBoxContainer, node_name: String, instruction: String, path: String) -> void:
	space(page, 8 if _compact else 14)
	text(page, instruction, 23 if _compact else 32, INK, "display")
	space(page, 11 if _compact else 23)
	var label := _detail_text(page, node_name, path, 20 if _compact else 26,
		SUBTLE, "Scroll the full profile path", 0.16)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Liberation Mono", "Consolas", "DejaVu Sans Mono", "monospace"])
	label.add_theme_font_override("font", mono)


func primary_action(page: VBoxContainer, node_name: String, caption: String, action: Callable) -> void:
	space(page, 26 if _compact else 49)
	var control := button(page, node_name, caption, "ClothButton")
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	control.custom_minimum_size = Vector2(265, 54) if _compact else Vector2(335, 67)
	control.add_theme_font_override("font", _strong_face)
	control.add_theme_font_size_override("font_size", 27 if _compact else 36)
	var focus := _focus_ring(FOCUS_GOLD)
	focus.set_expand_margin_all(3)
	control.add_theme_stylebox_override("focus", focus)
	control.pressed.connect(action)
	control.grab_focus()


func _detail_text(page: VBoxContainer, node_name: String, words: String, points: int, tint: Color,
		scroll_caption: String, maximum_fraction: float) -> Label:
	var region := detail_scroll(page, node_name + "Scroll", 0, scroll_caption)
	region.size_flags_vertical = Control.SIZE_FILL
	var bar := region.get_v_scroll_bar()
	bar.add_theme_stylebox_override("focus", _focus_ring(FOCUS_GOLD))
	var label := text(region, words, points, tint, "display")
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Follow the wrapped text's natural height until it needs a keyboard-scrollable viewport.
	var fit := func() -> void:
		var limit := floorf(get_viewport_rect().size.y * maximum_fraction)
		region.custom_minimum_size.y = minf(label.get_combined_minimum_size().y, limit)
	label.minimum_size_changed.connect(fit)
	fit.call_deferred()
	return label
