extends RefCounted

const DARK := Color("#2b1e17")


static func color_for(category: String) -> Color:
	match category:
		"beneficial": return Color("#acd499")
		"harmful": return Color("#eca397")
		_: return Color("#e1bceb")


static func draw_committed(canvas: CanvasItem, center: Vector2, radius: float,
		category: String, reaction_id: String, age := 0.0, opacity := 1.0) -> void:
	var pigment := Color(color_for(category), opacity)
	var outline := Color(DARK, opacity)
	# The resolved seal uses solid paper, dark ink, and short impact strokes.
	# Forecasts are higher on the figure, dark, and dashed even on this same tile.
	canvas.draw_circle(center, radius + 2.0, outline, true, -1.0, true)
	canvas.draw_circle(center, radius, pigment, true, -1.0, true)
	canvas.draw_arc(center, radius * 0.84, 0.0, TAU, 32, Color(DARK, opacity * 0.32), 1.0, true)
	draw_symbol(canvas, center, radius * 0.59, category, reaction_id, outline, pigment, age)
	for angle: float in [-2.65, -2.14, 2.18]:
		var ray := Vector2.from_angle(angle)
		var start := center + ray * (radius + 4.0)
		var finish := start + ray * (4.0 + 4.0 * exp(-age * 8.0))
		canvas.draw_line(start, finish, outline, 4.0, true)
		canvas.draw_line(start, finish, pigment, 2.0, true)


static func draw_symbol(canvas: CanvasItem, center: Vector2, unit: float,
		category: String, reaction_id: String, ink: Color, ground: Color, age: float) -> void:
	var stroke := maxf(1.2, unit * 0.19)
	if category == "beneficial":
		canvas.draw_line(center - Vector2(unit, 0), center + Vector2(unit, 0), ink, stroke, true)
		canvas.draw_line(center - Vector2(0, unit), center + Vector2(0, unit), ink, stroke, true)
		return
	if category == "harmful":
		canvas.draw_line(center - Vector2(0, unit), center + Vector2(0, unit * 0.29), ink, stroke, true)
		canvas.draw_circle(center + Vector2(0, unit * 0.82), stroke * 0.65, ink, true, -1.0, true)
		return
	match str(reaction_id):
		"upward_rain":
			for index in 3:
				var x := float(index - 1) * 0.68
				var lift := sin(age * 10.0 + float(index) * 2.0) * 0.18
				var tip := center + Vector2(x + 0.10, -0.60 + lift) * unit
				canvas.draw_line(tip, tip + Vector2(-0.25, 1.35) * unit, ink, stroke, true)
				canvas.draw_polyline(PackedVector2Array([tip + Vector2(-0.29, 0.29) * unit, tip,
					tip + Vector2(0.18, 0.36) * unit]), ink, stroke, true)
		"cork_moon":
			var crescent := PackedVector2Array()
			for index in 13:
				var theta := lerpf(0.98, TAU - 0.98, float(index) / 12.0)
				crescent.append(center + Vector2.from_angle(theta) * unit * 0.94)
			var top := crescent[-1]
			var bottom := crescent[0]
			var hollow := center + Vector2(-0.95, 0) * unit
			for index in range(1, 12):
				var t := float(index) / 12.0
				crescent.append(top.lerp(hollow, t).lerp(hollow.lerp(bottom, t), t))
			canvas.draw_colored_polygon(crescent, ink)
			var satellite := center + Vector2(0.72, -0.16 + 0.23 * sin(age * 4.0)) * unit
			canvas.draw_circle(satellite, unit * 0.21, ink, true, -1.0, true)
		"fine_bubbles":
			for index in 3:
				var origin: Vector2 = [Vector2(-0.52, 0.40), Vector2(0.49, 0.25), Vector2(0.0, -0.58)][index]
				var radius: float = [0.45, 0.33, 0.38][index]
				origin.y += 0.11 * sin(age * 8.0 + float(index) * 2.0)
				canvas.draw_arc(center + origin * unit, unit * radius, 0.0, TAU, 18, ink, stroke * 0.84, true)
		"spectral_napkin":
			var wave := sin(age * 8.0) * 0.13
			var corners := PackedVector2Array([Vector2(-0.94, -0.39), Vector2(0.12, -0.91),
				Vector2(0.96, -0.34 + wave), Vector2(0.67, 0.33), Vector2(0.48, 0.82 + wave),
				Vector2(0.13, 0.68), Vector2(-0.13, 0.99), Vector2(-0.90, 0.39)])
			for index in corners.size():
				corners[index] = center + corners[index] * unit
			canvas.draw_colored_polygon(corners, ink)
			canvas.draw_polyline(PackedVector2Array([corners[1], center + Vector2(0.04, 0.24) * unit,
				corners[7]]), ground, stroke * 0.7, true)
		_:
			canvas.draw_circle(center, unit * 0.36, ink, true, -1.0, true)
