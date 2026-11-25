extends MarginContainer
## The physical leaf and the print/ink vocabulary. No adventure state lives here.

const INK := Color("#31291f")
const SUBTLE := Color("#5c4f3b")
const RUST := Color("#783b2c")
const FOREST := Color("#25443c")
const BRASS := Color("#b99151")
const PAPER := Color("#efe2c6")
const PALE := Color("#f6ead1")
const RULE := Color("#b5a27c")
const CREAM := Color("#fff0cc")
const RARITY := {"common": SUBTLE, "uncommon": FOREST, "rare": Color("#3e5673"),
	"legendary": Color("#774f20")}

var _gutter := -1.0
var _face: SystemFont
var _italic: SystemFont
var _fibers: PackedVector2Array
var _preparation_paper := false
var _help_covered := false


func set_help_covered(covered: bool) -> void:
	_help_covered = covered
	queue_accessibility_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		AccessibilityServer.update_set_flag(get_accessibility_element(), AccessibilityServer.FLAG_HIDDEN, _help_covered)


func build(gutter_at: float) -> VBoxContainer:
	_gutter = gutter_at
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		add_theme_constant_override("margin_" + side, 49)
	for side in ["top", "bottom"]:
		add_theme_constant_override("margin_" + side, 38)
	_face = SystemFont.new()
	_face.font_names = PackedStringArray(["P052", "Palatino Linotype", "Book Antiqua", "Georgia"])
	_face.font_weight = 400
	_italic = _face.duplicate()
	_italic.font_italic = true
	theme = _leaf_theme()
	var grain := RandomNumberGenerator.new()
	grain.seed = 19343
	_fibers.resize(5300)
	for i in _fibers.size():
		_fibers[i] = Vector2(grain.randf(), grain.randf())
	return stack(self, 16)


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	if _preparation_paper:
		_draw_preparation_binding(bounds)
		return
	draw_rect(bounds, Color("#20211d"))
	_draw_box(bounds.grow(-10), Color("#3e3327"), Color("#806441"), 3, 15)
	_draw_box(bounds.grow(-17), Color("#aa8c5d"), Color("#4f3e2a"), 2, 12)
	_draw_box(bounds.grow(-22), Color("#ccb487"), Color("#947953"), 1, 8)
	for i in 3:
		var y := size.y - 22 - i * 2.0
		draw_line(Vector2(27, y), Vector2(size.x - 27, y), Color("#a68a61"))
	_draw_box(Rect2(24, 21, size.x - 48, size.y - 49), PAPER, Color("#cab58a"), 1, 6)
	var leaf := Rect2(28, 24, size.x - 56, size.y - 57)
	for i in _fibers.size():
		var point := leaf.position + leaf.size * _fibers[i]
		draw_line(point, point + Vector2(0.8 + (i % 5) * 0.55, (i % 3) * 0.2),
			Color(0.23, 0.14, 0.06, 0.032 if i % 3 else 0.052))
	if _gutter > 0.0:
		var x := lerpf(49.0, size.x - 49.0, _gutter)
		for i in range(-10, 12):
			var opacity := 0.004 + (1.0 - absf(float(i)) / 12.0) * (0.095 if i <= 0 else 0.035)
			var shade := Color(0.23, 0.13, 0.05, opacity) if i <= 0 else Color(1.0, 0.98, 0.86, opacity)
			draw_rect(Rect2(x + i, 25, 1, size.y - 56), shade)


## Keep the warmer hand-bound cover local to the two approved preparation leaves.
func use_preparation_paper(gutter_at: float) -> void:
	_preparation_paper = true
	_gutter = gutter_at
	for side in ["left", "right"]:
		add_theme_constant_override("margin_" + side, 42)
	for side in ["top", "bottom"]:
		add_theme_constant_override("margin_" + side, 27)
	if get_child_count() != 0:
		var content := get_child(0) as VBoxContainer
		if content != null:
			content.add_theme_constant_override("separation", 10)
	queue_redraw()


func _draw_preparation_binding(bounds: Rect2) -> void:
	draw_rect(bounds, Color("#1d1715"))
	_draw_box(bounds.grow(-4), Color("#483027"), Color("#7b5240"), 1, 16)
	_draw_box(bounds.grow(-8), Color("#6b4832"), Color("#a5805a"), 1, 14)
	for layer in 4:
		_draw_box(bounds.grow(-11.0 - layer * 2.4), Color("#e3c99a").lightened(layer * 0.045),
			Color("#9e7951").lightened(layer * 0.11), 1, 12 - layer)
	var leaf := bounds.grow(-20.0)
	_draw_box(leaf, Color("#f6e5c5"), Color("#d6b886"), 1, 8)
	for layer in 8:
		draw_style_box(_preparation_edge(layer), leaf.grow(-0.5 - layer * 2.1))
	# Fixed seed: translucent fibers and flecks move with the leaf, not the viewport.
	for i in _fibers.size():
		var point := leaf.position + leaf.size * _fibers[i]
		var tone := Color(0.34, 0.20, 0.07, 0.035 + (i % 5) * 0.008)
		draw_line(point, point + Vector2(0.45 + (i % 7) * 0.51, (i % 3) * 0.28), tone)
	if _gutter > 0.0:
		var x := lerpf(42.0, size.x - 42.0, _gutter)
		for offset in range(-14, 11):
			var fade := 1.0 - absf(float(offset)) / 15.0
			draw_rect(Rect2(x + offset, 22, 1, size.y - 44), Color(0.36, 0.21, 0.09, fade * 0.052))


static func _preparation_edge(layer: int) -> StyleBoxFlat:
	var edge := _box(Color.TRANSPARENT, Color(0.53, 0.33, 0.13, 0.095 - layer * 0.011), 2, 7)
	edge.draw_center = false
	return edge


func _draw_box(rect: Rect2, fill: Color, edge: Color, width: int, radius: int) -> void:
	draw_style_box(_box(fill, edge, width, radius), rect)


func spread(parent: Control, left_weight: float, opening := 44) -> Array[VBoxContainer]:
	var leaves := row(parent, opening)
	leaves.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := stack(leaves, 12)
	var right := stack(leaves, 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = left_weight
	right.size_flags_stretch_ratio = 1.0 - left_weight
	return [left, right]


func stack(parent: Control, gap: int) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", gap)
	parent.add_child(content)
	return content


func row(parent: Control, gap: int) -> HBoxContainer:
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", gap)
	parent.add_child(content)
	return content


func text(parent: Control, words: String, points: int, color := INK, type := "body") -> Label:
	var stamp := Label.new()
	stamp.text = words
	stamp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stamp.add_theme_font_size_override("font_size", points)
	stamp.add_theme_color_override("font_color", color)
	if type != "body":
		stamp.add_theme_font_override("font", _italic if type == "italic" else _face)
	parent.add_child(stamp)
	return stamp


func rule(parent: Control, color := RULE, height := 1) -> ColorRect:
	var stroke := ColorRect.new()
	stroke.color = color
	stroke.custom_minimum_size.y = height
	stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stroke)
	return stroke


func space(parent: BoxContainer, amount: float, expand := false) -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent is VBoxContainer:
		gap.custom_minimum_size.y = amount
		if expand:
			gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		gap.custom_minimum_size.x = amount
		if expand:
			gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(gap)
	return gap


func inset(parent: Control, fill: Color, edge: Color, px: int, py: int) -> PanelContainer:
	var material := PanelContainer.new()
	material.add_theme_stylebox_override("panel", _box(fill, edge, 1, 2, px, py))
	parent.add_child(material)
	return material


func scroll(parent: Control, node_name: String) -> ScrollContainer:
	var scrollbox := ScrollContainer.new()
	scrollbox.name = node_name
	scrollbox.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scrollbox.follow_focus = true
	scrollbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scrollbox)
	return scrollbox


func detail_scroll(parent: Control, node_name: String, height: float, caption: String) -> ScrollContainer:
	var region := scroll(parent, node_name)
	region.custom_minimum_size.y = height
	var bar := region.get_v_scroll_bar()
	bar.accessibility_name = caption
	bar.focus_mode = Control.FOCUS_NONE
	bar.changed.connect(func() -> void:
		bar.focus_mode = Control.FOCUS_ALL if bar.max_value - bar.min_value > bar.page else Control.FOCUS_NONE)
	bar.gui_input.connect(func(event: InputEvent) -> void:
		var direction := 0
		if event.is_action_pressed("ui_up", true):
			direction = -1
		elif event.is_action_pressed("ui_down", true):
			direction = 1
		if direction != 0:
			region.scroll_vertical += direction * 30
			bar.accept_event())
	return region


func set_disabled(action: BaseButton, disabled: bool) -> void:
	action.disabled = disabled
	action.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL


func button(parent: Control, node_name: String, caption: String, kind := "Button") -> Button:
	var action := Button.new()
	action.name = node_name
	action.text = caption
	action.theme_type_variation = kind
	action.custom_minimum_size.y = 42
	action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(action)
	return action


func plate(parent: Control, image: Texture2D, area: Vector2, kind := "crop") -> Control:
	var mount := PanelContainer.new()
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.custom_minimum_size = area
	var fill := Color("#f0d2a7") if kind in ["sketch", "study"] else Color("#dcccaa")
	mount.add_theme_stylebox_override("panel", _box(fill, RULE, 1, 0, 1, 1))
	parent.add_child(mount)
	if image == null:
		return mount
	var print := TextureRect.new()
	print.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print.texture = image
	print.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	print.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if kind in ["sketch", "study"] \
		else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if kind == "portrait":
		var image_size := image.get_size()
		var width := minf(image_size.x, image_size.y)
		var square := AtlasTexture.new()
		square.atlas = image
		square.region = Rect2((image_size.x - width) / 2.0, (image_size.y - width) * 0.18, width, width)
		square.filter_clip = true
		print.texture = square
	mount.add_child(print)
	return mount


func _leaf_theme() -> Theme:
	var skin := Theme.new()
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Noto Sans", "Segoe UI", "Liberation Sans"])
	skin.default_font = body
	skin.default_font_size = 16
	skin.set_type_variation("ClothButton", "Button")
	skin.set_type_variation("QuietButton", "Button")
	skin.set_type_variation("CoverButton", "Button")
	_button_ink(skin, "Button", Color("#eadbbd"), Color("#dac7a4"), RULE, INK)
	_button_ink(skin, "OptionButton", PALE, Color("#e8d8b6"), Color("#907b56"), INK)
	_button_ink(skin, "ClothButton", FOREST, Color("#365c50"), Color("#192f2a"), CREAM)
	_button_ink(skin, "QuietButton", Color.TRANSPARENT, Color("#e3d0a8"), Color.TRANSPARENT, FOREST)
	_button_ink(skin, "CoverButton", Color("#322c20"), Color("#49402d"), BRASS, CREAM)
	skin.set_stylebox("normal", "LineEdit", _box(PALE, Color("#8e794f"), 1, 2, 14, 8))
	skin.set_stylebox("focus", "LineEdit", _focus())
	skin.set_font_size("font_size", "LineEdit", 20)
	skin.set_color("font_color", "LineEdit", INK)
	skin.set_color("font_placeholder_color", "LineEdit", SUBTLE)
	skin.set_color("font_selected_color", "LineEdit", CREAM)
	skin.set_color("selection_color", "LineEdit", FOREST)
	skin.set_color("caret_color", "LineEdit", FOREST)
	skin.set_stylebox("panel", "PopupMenu", _box(PALE, Color("#8e794f"), 1, 2, 10, 8))
	skin.set_stylebox("hover", "PopupMenu", _box(Color("#decdaa"), RULE, 0, 0, 6, 3))
	skin.set_color("font_color", "PopupMenu", INK)
	skin.set_color("font_hover_color", "PopupMenu", INK)
	skin.set_color("font_disabled_color", "PopupMenu", SUBTLE)
	skin.set_constant("v_separation", "PopupMenu", 13)
	skin.set_icon("arrow", "OptionButton", _arrow())
	skin.set_stylebox("scroll", "VScrollBar", _box(Color("#e2d2af"), RULE, 1, 1, 4, 0))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		skin.set_stylebox(state, "VScrollBar", _box(Color("#887047"), RULE, 0, 1, 4, 0))
	return skin


func _button_ink(skin: Theme, kind: String, fill: Color, hover: Color, edge: Color, fg: Color) -> void:
	skin.set_stylebox("normal", kind, _box(fill, edge, 1, 2, 12, 6))
	skin.set_stylebox("hover", kind, _box(hover, edge, 1, 2, 12, 6))
	skin.set_stylebox("pressed", kind, _box(hover.darkened(0.11), edge, 1, 2, 12, 6))
	skin.set_stylebox("disabled", kind, _box(Color("#e3d6bc"), Color("#cab899"), 1, 2, 12, 6))
	skin.set_stylebox("focus", kind, _focus(BRASS if kind in ["ClothButton", "CoverButton"] else RUST))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		skin.set_color(state, kind, fg)
	skin.set_color("font_disabled_color", kind, SUBTLE)


func _focus(color := RUST) -> StyleBoxFlat:
	var ring := _box(Color.TRANSPARENT, color, 3, 3)
	ring.draw_center = false
	ring.set_expand_margin_all(-1)
	return ring


func _arrow() -> Texture2D:
	var arrow := Image.create_empty(14, 9, false, Image.FORMAT_RGBA8)
	for x in 13:
		var y := mini(x, 12 - x) / 2
		arrow.set_pixel(x, y, INK)
		arrow.set_pixel(x, y + 1, INK)
	return ImageTexture.create_from_image(arrow)


static func _box(fill: Color, edge: Color, width := 1, radius := 2,
		horizontal := 0, vertical := 0) -> StyleBoxFlat:
	var material := StyleBoxFlat.new()
	material.bg_color = fill
	material.border_color = edge
	material.set_border_width_all(width)
	material.set_corner_radius_all(radius)
	material.content_margin_left = horizontal
	material.content_margin_right = horizontal
	material.content_margin_top = vertical
	material.content_margin_bottom = vertical
	return material
