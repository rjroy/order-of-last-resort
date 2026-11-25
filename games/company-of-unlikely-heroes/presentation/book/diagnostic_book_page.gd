extends "res://presentation/book/guild_bound_page.gd"
## Single-leaf diagnostics. The caller owns the error, its context and any action.

const INK_RULE := Color("#8e7753")

var _compact: bool


func heading(page: VBoxContainer, title: String, context: String, launch := false) -> void:
	var viewport_size := get_viewport_rect().size
	_compact = viewport_size.x < 1080 or viewport_size.y < 720
	var margin := (48 if _compact else 70) if launch else (60 if _compact else 102)
	var top := (49 if _compact else 75) if launch else (56 if _compact else 99)
	bind_cover(margin, top, 44 if _compact else 68, true)
	page.add_theme_constant_override("separation", 0)
	var title_size := (42 if _compact else 55) if launch else (47 if _compact else 63)
	strong_text(page, title, title_size)
	space(page, 4 if _compact else 14)
	text(page, context, 25 if _compact else 32, INK, "display")
	space(page, 17 if _compact else 25)
	rule(page, INK_RULE, 2 if launch else 1)
	space(page, (24 if _compact else 37) if launch else (16 if _compact else 22))


func launch_detail(page: VBoxContainer, node_name: String, words: String) -> void:
	var block := row(page, 17 if _compact else 23)
	var stroke := ColorRect.new()
	stroke.custom_minimum_size.x = 4
	stroke.color = RUST
	stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(stroke)
	var region := _diagnostic_scroll(block, node_name, "Scroll launch error details")
	region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail := RichTextLabel.new()
	detail.name = node_name
	detail.accessibility_name = words
	detail.bbcode_enabled = false
	detail.scroll_active = false
	detail.fit_content = true
	detail.selection_enabled = true
	detail.focus_mode = Control.FOCUS_CLICK
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_override("normal_font", _face)
	detail.add_theme_font_size_override("normal_font_size", 23 if _compact else 29)
	detail.add_theme_color_override("default_color", INK)
	detail.add_theme_color_override("selection_color", FOREST)
	detail.add_theme_color_override("font_selected_color", CREAM)
	detail.add_theme_constant_override("line_separation", 5)
	_print_launch_detail(detail, words)
	region.add_child(detail)
	_fit_detail(region, detail, 0.57)


func _print_launch_detail(detail: RichTextLabel, words: String) -> void:
	var syntax := RegEx.create_from_string("(?<!\\S)--[a-z][a-z-]*(?:=<[^>\\n]+>)?|'[a-z][a-z_0-9]*'")
	var mono := _mono_face()
	mono.font_weight = 700
	var cursor := 0
	# add_text is literal, even when filenames or catalog IDs contain brackets.
	for token in syntax.search_all(words):
		detail.add_text(words.substr(cursor, token.get_start() - cursor))
		detail.push_font(mono)
		detail.add_text(token.get_string())
		detail.pop()
		cursor = token.get_end()
	detail.add_text(words.substr(cursor))


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
	label.add_theme_font_override("font", _mono_face())


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
	var region := _diagnostic_scroll(page, node_name, scroll_caption)
	var label := text(region, words, points, tint, "display")
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit_detail(region, label, maximum_fraction)
	return label


func _diagnostic_scroll(parent: Control, node_name: String, caption: String) -> ScrollContainer:
	var region := detail_scroll(parent, node_name + "Scroll", 0, caption)
	region.size_flags_vertical = Control.SIZE_FILL
	region.get_v_scroll_bar().add_theme_stylebox_override("focus", _focus_ring(FOCUS_GOLD))
	return region


func _fit_detail(region: ScrollContainer, content: Control, maximum_fraction: float) -> void:
	# Follow the wrapped text's natural height until it needs a keyboard-scrollable viewport.
	var fit := func() -> void:
		var limit := floorf(get_viewport_rect().size.y * maximum_fraction)
		region.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, limit)
	content.minimum_size_changed.connect(fit)
	fit.call_deferred()


func _mono_face() -> SystemFont:
	var face := SystemFont.new()
	face.font_names = PackedStringArray(["Liberation Mono", "Consolas", "DejaVu Sans Mono", "monospace"])
	return face
