extends PanelContainer
## The battle page reserves a strip for this lesson without covering the board.

signal skip_requested
signal continue_requested

const Lesson := preload("res://presentation/battle/practice_lesson.gd")

var _heading: Label
var _instruction: Label
var _continue: Button
var _help_covered := false


func set_help_covered(covered: bool) -> void:
	_help_covered = covered


func _init() -> void:
	name = "PracticeInstructions"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("#f1deb4")
	paper.border_color = Color("#9a7043")
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(6)
	paper.content_margin_left = 14
	paper.content_margin_right = 10
	paper.content_margin_top = 7
	paper.content_margin_bottom = 7
	add_theme_stylebox_override("panel", paper)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var skip := _button(row, "SkipPractice", "Skip practice")
	skip.tooltip_text = "Go to the commission board. Practice does not change your guild."
	skip.pressed.connect(func() -> void:
		if not _help_covered:
			skip_requested.emit())
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	_heading = _label(copy, 14, Color("#744624"))
	_instruction = _label(copy, 16, Color("#362419"))
	_instruction.name = "PracticeInstruction"
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.accessibility_live = AccessibilityServer.LIVE_POLITE
	_continue = _button(row, "ContinuePractice", "Commission board")
	_continue.pressed.connect(func() -> void:
		if not _help_covered:
			continue_requested.emit())
	_continue.hide()


func render(step: Lesson.Step, forecast_open: bool, reviewed: bool, caster_selected: bool) -> void:
	var title := ""
	var copy := ""
	match step:
		Lesson.Step.ORDER:
			title = "1 of 4 · Set a standing order"
			copy = "Open Standing orders and set Pip, the Enthusiastic Caster, to Blast nearest. That’s what Pip will do when you don’t give a direct command."
		Lesson.Step.MOVE:
			title = "2 of 4 · Give one direct command"
			copy = ("Choose an empty tile one step away." if caster_selected else
				"Select Pip on the board, then choose an empty tile one step away.")
			copy += " This Move replaces Blast for one round. Nothing moves yet."
		Lesson.Step.FORECAST_MOVE:
			title = "3 of 4 · Compare and commit"
			if reviewed:
				copy = "Marta’s Support restores her own HP. Edwin’s Guard sends the arrow aimed at Marta back at the Archer. Commit round 1 to play it out."
			else:
				copy = _read_forecast(forecast_open) + " to see who follows standing orders while you command Pip."
		Lesson.Step.FORECAST_BLAST:
			title = "4 of 4 · See the standing order return"
			copy = "The Move lasted one round. Blast nearest is back and will hit the Archer. "
			copy += "Commit round 2 to see it land." if reviewed else _read_forecast(forecast_open) + " to check."
		Lesson.Step.COMPLETE:
			title = "Practice complete"
			copy = "Pip moved once, then went back to Blast. Your guild is unchanged. Take a commission when you’re ready."
	_set_text(_heading, title)
	_set_text(_instruction, copy)
	_continue.visible = step == Lesson.Step.COMPLETE


func focus_continue() -> void:
	_continue.grab_focus()


func _read_forecast(already_open: bool) -> String:
	return "Close and reopen Forecast" if already_open else "Open Forecast"


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Control, node_name: String, caption: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size.y = 38
	parent.add_child(button)
	return button
