extends "res://presentation/guild_bound_page.gd"
## The opening spread. Profile writes and navigation stay with the scene.

const GuildProfile = preload("res://guild_profile.gd")
const NAME_HINT := "1 to %d characters." % GuildProfile.MAX_NAME_LENGTH

var _input: LineEdit
var _create: Button
var _message: Label
var _invalid_name := false


func populate(page: VBoxContainer, title: String, painting: Texture2D, after_missing_profile: bool,
		create_profile: Callable) -> void:
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1100 or viewport_size.y < 700
	bind_cover(28 if compact else 34, 22 if compact else 26, 27 if compact else 38)
	var leaves := spread(page, 0.5, 40 if compact else 56)
	_mount_cover(leaves[0], title, painting, compact)
	_build_form(leaves[1], after_missing_profile, create_profile, compact)


func _mount_cover(leaf: Control, title: String, painting: Texture2D, compact: bool) -> void:
	var cloth := material_panel(leaf, Surface.CLOTH, 29 if compact else 40,
		22 if compact else 29, 22 if compact else 34)
	cloth.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var print := stack(cloth, 8 if compact else 11)
	rule(print, Color("#cda663"))
	var title_ink := text(print, title, 44 if compact else 64, CREAM, "display")
	title_ink.add_theme_font_override("font", _strong_face)
	title_ink.add_theme_constant_override("line_spacing", -2)
	if painting != null:
		var front := plate(print, painting, Vector2(0, 180 if compact else 260))
		front.name = "GuildCoverPlate"
		front.add_theme_stylebox_override("panel", _box(Color("#b8945d"), Color("#d7b378"), 1, 2, 2, 2))
		front.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		space(print, 80, true)
	text(print, "The guild book", 22 if compact else 26, CREAM, "italic")
	rule(print, Color("#cda663"))


func _build_form(leaf: Control, after_missing_profile: bool, create_profile: Callable,
		compact: bool) -> void:
	leaf.add_theme_constant_override("separation", 0)
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_top", 61 if compact else 101)
	margins.add_theme_constant_override("margin_right", 5)
	leaf.add_child(margins)
	var form := stack(margins, 0)
	strong_text(form, "Name your guild", 40 if compact else 54)
	space(form, 10 if compact else 14)
	var intro := text(form, "Once it’s founded, you can take commissions and recruit your company. "
		+ "Your guild keeps its name between outings.", 21 if compact else 25, INK, "display")
	intro.add_theme_constant_override("line_spacing", 3)
	space(form, 17 if compact else 35)
	var caption := strong_text(form, "Guild name", 19 if compact else 24)
	space(form, 7 if compact else 12)

	_input = LineEdit.new()
	_input.name = "GuildName"
	_input.placeholder_text = "Enter a guild name"
	_input.accessibility_name = caption.text
	_input.accessibility_description = NAME_HINT
	_input.max_length = GuildProfile.MAX_NAME_LENGTH
	_input.keep_editing_on_text_submit = true
	_input.custom_minimum_size.y = 44 if compact else 56
	_input.add_theme_font_override("font", _strong_face)
	_input.add_theme_font_size_override("font_size", 21 if compact else 23)
	_input.add_theme_stylebox_override("normal", _field_box())
	_input.add_theme_stylebox_override("focus", _focus_ring(FOCUS_GOLD))
	form.add_child(_input)
	space(form, 6 if compact else 9)
	_message = text(form, NAME_HINT, 18 if compact else 21, SUBTLE, "italic")
	_message.name = "GuildNameFeedback"
	space(form, 18 if compact else 30)

	_create = button(form, "CreateGuild", "Create guild", "ClothButton")
	_create.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_create.custom_minimum_size = Vector2(230, 49) if compact else Vector2(310, 62)
	_style_action(_create, 25 if compact else 32)
	set_disabled(_create, true)
	if after_missing_profile:
		space(form, 16)
		text(form, "The previous guild profile could not be found. Create a guild to choose another commission.", 17, RUST)

	_input.text_changed.connect(_name_changed)
	_input.text_submitted.connect(func(_value: String) -> void: _submit(create_profile))
	_create.pressed.connect(_submit.bind(create_profile))
	_input.grab_focus()


func _name_changed(value: String) -> void:
	set_disabled(_create, value.strip_edges().is_empty())
	_show_message()


func _submit(create_profile: Callable) -> void:
	if _input.text.strip_edges().is_empty():
		_show_message("Enter a guild name.", true)
		return
	var error: String = create_profile.call(_input.text)
	if not error.is_empty():
		_show_message(error)


func _show_message(error := "", invalid_name := false) -> void:
	var next := NAME_HINT if error.is_empty() else error
	if _message.text != next:
		_message.text = next
		_message.add_theme_color_override("font_color", SUBTLE if error.is_empty() else RUST)
		_input.accessibility_description = NAME_HINT if error.is_empty() else NAME_HINT + " " + error
	if _invalid_name != invalid_name:
		_invalid_name = invalid_name
		_input.add_theme_stylebox_override("normal", _field_box(RUST) if invalid_name else _field_box())
		_input.add_theme_stylebox_override("focus", _focus_ring(RUST if invalid_name else FOCUS_GOLD))


func _style_action(action: Button, points: int) -> void:
	action.add_theme_font_override("font", _strong_face)
	action.add_theme_font_size_override("font_size", points)
	action.add_theme_stylebox_override("normal", _action_box(Color("#1f3d32"), Color("#152a22")))
	action.add_theme_stylebox_override("hover", _action_box(Color("#2a513f"), Color("#1b3529")))
	action.add_theme_stylebox_override("pressed", _action_box(Color("#182f27"), Color("#152a22"), false))
	action.add_theme_stylebox_override("disabled", _action_box(Color("#e3d1ae"), Color("#bba581"), false))
	var focus := _focus_ring(FOCUS_GOLD)
	focus.set_expand_margin_all(3)
	action.add_theme_stylebox_override("focus", focus)


func _action_box(fill: Color, edge: Color, lifted := true) -> StyleBoxFlat:
	var box := _box(fill, edge, 2, 6, 16, 6)
	if lifted:
		box.shadow_color = Color(0.18, 0.105, 0.045, 0.24)
		box.shadow_size = 3
		box.shadow_offset = Vector2(0, 2)
	return box


func _field_box(edge := Color("#85683d")) -> StyleBoxFlat:
	return _box(Color("#fcf1d8"), edge, 1, 5, 13, 7)
