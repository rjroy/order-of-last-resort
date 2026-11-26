extends Control

const ReactionMarks = preload("res://presentation/battle/reaction_marks.gd")

var category := "beneficial"
var reaction_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(72, 72)
	resized.connect(queue_redraw)


func _draw() -> void:
	ReactionMarks.draw_committed(self, size / 2.0, minf(size.x, size.y) * 0.30, category, reaction_id)
