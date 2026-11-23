extends "res://presentation/guild_book_page.gd"
## Opt-in book furniture. Unpolished leaves retain the ordinary page.

enum Surface { BINDING, CLOTH, POSTING }

const BookMaterial = preload("res://presentation/guild_book_material.gdshader")
const FOCUS_GOLD := Color("#aa660e")

var _strong_face: SystemFont
var _surface_pixel: ImageTexture


func _draw() -> void:
	# A white pixel provides UVs for the live material; it carries no artwork.
	draw_texture_rect(_surface_pixel, Rect2(Vector2.ZERO, size), false)


func bind_cover(horizontal: int, top: int, bottom: int) -> void:
	for side in ["left", "right"]:
		add_theme_constant_override("margin_" + side, horizontal)
	add_theme_constant_override("margin_top", top)
	add_theme_constant_override("margin_bottom", bottom)
	_strong_face = _face.duplicate()
	_strong_face.font_weight = 700
	var pixel := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	pixel.fill(Color.WHITE)
	_surface_pixel = ImageTexture.create_from_image(pixel)
	_set_material(self, Surface.BINDING)


func material_panel(parent: Control, kind: Surface, horizontal: int, top: int, bottom: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var inset_style := StyleBoxEmpty.new()
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		inset_style.set_content_margin(side, horizontal)
	inset_style.set_content_margin(SIDE_TOP, top)
	inset_style.set_content_margin(SIDE_BOTTOM, bottom)
	panel.add_theme_stylebox_override("panel", inset_style)
	parent.add_child(panel)
	_set_material(panel, kind)
	panel.draw.connect(func() -> void:
		panel.draw_texture_rect(_surface_pixel, Rect2(Vector2.ZERO, panel.size), false))
	return panel


func strong_text(parent: Control, words: String, points: int, color := INK) -> Label:
	var label := text(parent, words, points, color, "display")
	label.add_theme_font_override("font", _strong_face)
	return label


func _focus_ring(color: Color) -> StyleBoxFlat:
	var ring := _box(Color.TRANSPARENT, color, 3, 6)
	ring.draw_center = false
	ring.set_expand_margin_all(1)
	return ring


func _set_material(surface: Control, kind: Surface) -> void:
	var skin := ShaderMaterial.new()
	skin.shader = BookMaterial
	skin.set_shader_parameter("surface_kind", kind)
	skin.set_shader_parameter("surface_size", surface.size)
	surface.material = skin
	surface.resized.connect(func() -> void: skin.set_shader_parameter("surface_size", surface.size))
