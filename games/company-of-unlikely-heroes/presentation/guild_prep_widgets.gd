extends RefCounted
## Printed material and native controls shared by petitions and commission preparation.

const Book = preload("res://presentation/guild_book_page.gd")
const INK := Color("#302419")
const QUIET := Color("#5e4a34")
const RULE := Color("#a28562")
const GOLD := Color("#9b500d")
const FOREST := Color("#173d2d")
const PAPER := Color("#f6e2bc")
const LOCKED := Color("#e8d4ad")
const GREEN_PAPER := Color("#e9e5c4")


class Sheet extends PanelContainer:
	var active := false
	var pinned := false
	var folded := false

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, size)
		var inner := area.grow(-4)
		if active:
			draw_rect(inner, Color("#c87819"), false, 1.6)
		elif pinned:
			draw_rect(inner, Color(0.53, 0.36, 0.16, 0.24), false, 1)
		if folded:
			var tip := area.end.x - 2
			var crease := PackedVector2Array([Vector2(tip - 27, 2), Vector2(tip, 26), Vector2(tip - 26, 22)])
			var shadow := crease.duplicate()
			for index in shadow.size():
				shadow[index] += Vector2(-1, 3)
			draw_colored_polygon(shadow, Color(0.40, 0.24, 0.12, 0.18))
			draw_colored_polygon(crease, Color("#e8cda0"))
			draw_polyline(PackedVector2Array([crease[0], crease[2], crease[1]]), Color("#b6946b"), 1, true)
		if pinned:
			var tack := Vector2(15, 14)
			draw_circle(tack + Vector2(1, 2), 8.2, Color(0.35, 0.21, 0.10, 0.22), true, -1.0, true)
			draw_circle(tack, 7.5, Color("#644222"), true, -1.0, true)
			draw_circle(tack, 6.1, Color("#b78a43"), true, -1.0, true)
			draw_circle(tack + Vector2(-1, -1), 4.5, Color("#d1a85c"), true, -1.0, true)
			draw_circle(tack + Vector2(-2.1, -2.6), 1.9, Color("#f9de9d"), true, -1.0, true)


## The illustration/copy sets the minimum size. The overlay is a single native button.
class ActionSlip extends Container:
	var paper: Control
	var action: Button

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO if paper == null else paper.get_combined_minimum_size()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN and paper != null and action != null:
			var area := Rect2(Vector2.ZERO, size)
			fit_child_in_rect(paper, area)
			fit_child_in_rect(action, area)


static func text(book: Book, parent: Control, words: String, size: int, tint := INK,
		face := "display") -> Label:
	return book.text(parent, words, size, tint, face)


## Fixed-width words must contribute their true width to a horizontal container.
static func line(book: Book, parent: Control, words: String, size: int, tint := INK,
		face := "display") -> Label:
	var label := text(book, parent, words, size, tint, face)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


static func back(book: Book, parent: Control) -> Button:
	var button := book.button(parent, "BackToCommissions", "Commission board", "QuietButton")
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size.y = 31
	button.add_theme_constant_override("icon_max_width", 17)
	# A drawn back arrow belongs to the live navigation, not to the concept image.
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><path d="M7 3 2 8l5 5M2 8h12" fill="none" stroke="#302419" stroke-width="1.35"/></svg>'
	var ink := Image.new()
	ink.load_svg_from_string(svg)
	button.icon = ImageTexture.create_from_image(ink)
	button.accessibility_name = "Back to commission board"
	return button


static func mount(parent: Control, active := false, pinned := true, folded := true,
		fill := PAPER, px := 18, py := 13) -> PanelContainer:
	var sheet := Sheet.new()
	sheet.active = active
	sheet.pinned = pinned
	sheet.folded = folded
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edge := GOLD if active else (Color.TRANSPARENT if fill.a == 0.0 else Color("#b89972"))
	var surface := _box(fill, edge, 2 if active else 1, 6, px, py)
	if pinned or folded:
		surface.shadow_size = 3
		surface.shadow_offset = Vector2(0, 2)
		surface.shadow_color = Color(0.30, 0.18, 0.08, 0.22)
	sheet.add_theme_stylebox_override("panel", surface)
	parent.add_child(sheet)
	return sheet


static func petition_slip(book: Book, parent: Control, id: String, selected: bool) -> ActionSlip:
	var slip := ActionSlip.new()
	slip.name = "PetitionSlip_" + id
	slip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slip)
	slip.paper = mount(slip, selected, false, false, PAPER, 14, 8)
	slip.paper.minimum_size_changed.connect(slip.update_minimum_size)
	slip.action = book.button(slip, "Petition_" + id, "")
	slip.action.toggle_mode = true
	slip.action.set_pressed_no_signal(selected)
	var transparent := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "disabled"]:
		slip.action.add_theme_stylebox_override(state, transparent)
	slip.action.add_theme_stylebox_override("hover", _ring(Color("#a16c3e"), 1, -5))
	slip.action.add_theme_stylebox_override("hover_pressed", _ring(Color("#a16c3e"), 1, -5))
	slip.action.add_theme_stylebox_override("focus", _ring(Color("#633825"), 3, -7))
	return slip


static func primary(book: Book, parent: Control, name_text: String, caption: String,
		point_size := 24) -> Button:
	var button := book.button(parent, name_text, caption, "ClothButton")
	button.custom_minimum_size.y = 50
	button.add_theme_font_size_override("font_size", point_size)
	button.add_theme_font_override("font", serif())
	return button


static func small_button(book: Book, parent: Control, name_text: String, caption: String) -> Button:
	var button := book.button(parent, name_text, caption)
	button.custom_minimum_size.y = 35
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_font_override("font", serif())
	return button


static func picture(book: Book, parent: Control, texture: Texture2D, side: float) -> void:
	if texture != null:
		var portrait := book.plate(parent, texture, Vector2(side, side), "portrait")
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func action_plate(parent: Control, texture: Texture2D) -> TextureRect:
	var print := TextureRect.new()
	print.texture = texture
	print.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	print.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	print.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	print.size_flags_vertical = Control.SIZE_EXPAND_FILL
	print.custom_minimum_size.y = 184
	parent.add_child(print)
	return print


static func mark(parent: Control, selected: bool, locked: bool) -> Control:
	var symbol := StateMark.new()
	symbol.selected = selected
	symbol.locked = locked
	symbol.custom_minimum_size = Vector2(26, 25)
	symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(symbol)
	return symbol


class StateMark extends Control:
	var selected := false
	var locked := false

	func _draw() -> void:
		var center := size * 0.5
		if locked:
			var shackle := center - Vector2(0, 3)
			draw_arc(shackle, 5, PI, TAU, 13, QUIET, 2, true)
			draw_rect(Rect2(center - Vector2(7, 2), Vector2(14, 11)), QUIET)
			draw_circle(center + Vector2(0, 2), 1.45, LOCKED, true, -1, true)
			draw_line(center + Vector2(0, 2), center + Vector2(0, 5), LOCKED, 1.25, true)
		elif selected:
			draw_circle(center, 10, FOREST, true, -1, true)
			draw_polyline(PackedVector2Array([center + Vector2(-4, 0), center + Vector2(-1, 3),
				center + Vector2(5, -4)]), Book.CREAM, 2, true)
		else:
			draw_arc(center, 8.5, 0, TAU, 24, RULE, 1.6, true)


static func serif() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["P052", "Palatino Linotype", "Book Antiqua", "Georgia"])
	return font


static func text_status(fill: Color) -> StyleBoxFlat:
	return _box(fill, Color.TRANSPARENT, 0, 0, 8, 4)


static func _ring(color: Color, width: int, inset: float) -> StyleBoxFlat:
	var line := _box(Color.TRANSPARENT, color, width, 5, 0, 0)
	line.draw_center = false
	line.set_expand_margin_all(inset)
	return line


static func _box(fill: Color, edge: Color, width: int, radius: int, x: int, y: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = x
	style.content_margin_right = x
	style.content_margin_top = y
	style.content_margin_bottom = y
	return style
