extends "res://presentation/guild_bound_page.gd"
## Route presentation takes only the disclosed reports, not the expedition state.

const PRINT_RULE := Color("#927b56")
const INK_GREEN := Color("#214334")
const ROUTE_NAMES := ["Route A", "Route B"]
const ACTION_FILLS := {"normal": "#1e4132", "hover": "#2b5642", "pressed": "#183329"}

var _compact := false
var _immediate_copy: Array[Label] = []
var _alignment_queued := false


func populate(page: VBoxContainer, context: String, known_destination: bool, reports: Array[Dictionary]) -> void:
	var viewport := get_viewport_rect().size
	_compact = viewport.x < 1100 or viewport.y < 700
	bind_cover(34 if _compact else 51, 26 if _compact else 33, 29 if _compact else 43)
	page.add_theme_constant_override("separation", 10 if _compact else 14)
	var heading := stack(page, 0)
	strong_text(heading, "Field reports", 39 if _compact else 52)
	text(heading, context, 18 if _compact else 23, INK, "display")
	rule(page, PRINT_RULE)

	var spread := row(page, 27 if _compact else 49)
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions: Array[Button] = []
	var illustrated := reports.any(func(report: Dictionary) -> bool: return report.sketch != null)
	for index in reports.size():
		actions.append(_build_report(spread, index, reports[index], known_destination, illustrated))
	for index in range(1, actions.size()):
		var left := actions[index - 1]
		var right := actions[index]
		left.focus_neighbor_right = left.get_path_to(right)
		right.focus_neighbor_left = right.get_path_to(left)

	rule(page)
	text(page, "Both roads lead to your destination." if known_destination
		else "The clue describes what may follow, not the exact mission.", 17 if _compact else 21, INK, "italic")
	if not actions.is_empty():
		actions[0].grab_focus()
	_queue_alignment()


func _build_report(parent: Control, index: int, report: Dictionary, known_destination: bool, illustrated: bool) -> Button:
	var leaf := stack(parent, 8 if _compact else 10)
	leaf.name = "RouteCard_%d" % index
	leaf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var route_name: String = ROUTE_NAMES[index]
	text(leaf, route_name, 32 if _compact else 42, RUST, "italic")
	if illustrated:
		_mount_sketch(leaf, report.sketch)

	var region := detail_scroll(leaf, "RouteDetails_%d" % index, 120 if _compact else 140, "Scroll " + route_name + " report")
	var copy := stack(region, 4 if _compact else 5)
	copy.name = "RouteText_%d" % index
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strong_text(copy, "Immediate mission", 17 if _compact else 20, INK_GREEN)
	var description := text(copy, report.description, 18 if _compact else 21, INK, "display")
	description.custom_minimum_size.y = 56 if _compact else 74
	_immediate_copy.append(description)
	description.resized.connect(_queue_alignment)
	rule(copy, PRINT_RULE)
	var farther := "Known destination" if known_destination else "Farther ahead"
	if not report.kind_label.is_empty():
		farther += "  ·  " + report.kind_label
	strong_text(copy, farther, 17 if _compact else 20, INK_GREEN)
	text(copy, report.clue, 18 if _compact else 21, INK, "display")
	var choose := button(leaf, "Route_%d" % index, "Take " + route_name, "ClothButton")
	choose.accessibility_description = "Immediate mission: %s\n%s: %s" % [report.description, farther, report.clue]
	_style_action(choose)
	choose.pressed.connect(report.take)
	return choose


func _queue_alignment() -> void:
	if _alignment_queued:
		return
	_alignment_queued = true
	_align_immediate_copy.call_deferred()


func _align_immediate_copy() -> void:
	_alignment_queued = false
	if not is_inside_tree():
		return
	var limit := 64.0 if _compact else 100.0
	var height := 56.0 if _compact else 74.0
	# Align the two clue headers for comparable copy, but don't add pages of
	# blank padding beside long custom reports. Each report can scroll.
	for description in _immediate_copy:
		height = maxf(height, minf(limit, description.get_minimum_size().y))
	for description in _immediate_copy:
		description.custom_minimum_size.y = height


func _mount_sketch(leaf: VBoxContainer, sketch: Texture2D) -> void:
	var dimensions := Vector2(267, 168) if _compact else Vector2(404, 238)
	if sketch == null:
		space(leaf, dimensions.y)
		return
	var drawing := plate(leaf, sketch, dimensions, "sketch") as PanelContainer
	drawing.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var plate_image := drawing.get_child(0) as TextureRect
	plate_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var mount := _box(Color("#f1d4ac"), Color("#c2a177"), 1, 3, 1, 1)
	mount.shadow_color = Color(0.32, 0.21, 0.12, 0.25)
	mount.shadow_offset = Vector2(0, 3)
	mount.shadow_size = 4
	drawing.add_theme_stylebox_override("panel", mount)


func _style_action(action: Button) -> void:
	action.custom_minimum_size.y = 45 if _compact else 57
	action.add_theme_font_override("font", _strong_face)
	action.add_theme_font_size_override("font_size", 24 if _compact else 31)
	for state in ACTION_FILLS:
		action.add_theme_stylebox_override(state, _box(Color(ACTION_FILLS[state]), Color("#193226"), 2, 5, 10, 5))
	var focus := _focus_ring(FOCUS_GOLD)
	focus.set_expand_margin_all(3)
	action.add_theme_stylebox_override("focus", focus)
