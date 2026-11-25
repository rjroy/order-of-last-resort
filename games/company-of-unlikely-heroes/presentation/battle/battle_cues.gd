extends Control
## Objective stamps and short inspection copy. Victory, timing and occupancy come from Rules.

const BridgeArt = preload("res://presentation/battle/bridge_art.gd")
const MARKS := {
	"plate": ["P", "Plate", Color("#dbcb99")],
	"gate": ["G", "Gate", Color("#dbcb99")],
	"exit": ["E", "Exit", Color("#f0cb79")],
	"pen": ["P", "Pen", Color("#b8dfa7")],
	"collapse": ["!", "Collapse", Color("#f0b495")],
	"treasure": ["T", "Treasure", Color("#f0cb79")],
	"ritual": ["R", "Ritual circle", Color("#d6c4ee")],
	"destination": ["D", "Destination", Color("#b8dfa7")],
	"zone": ["", "Village square", Color("#c0e6d7")],
}

const INK := Color("#223632")

var _board: BridgeArt
var _markers: Dictionary = {}
var _use_native_exit := false


func attach_to(board: BridgeArt) -> void:
	_board = board
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.resized.connect(queue_redraw)
	board.foreground_layer_changed.connect(_set_foreground_layer)
	_set_foreground_layer(board.foreground_above_scenery())


func _set_foreground_layer(enabled: bool) -> void:
	# Cues are appended after the figures; at the same depth they cover both
	# deck and figures, while the storybook ink remains above them.
	z_index = BridgeArt.FOREGROUND_Z_INDEX if enabled else 0


func update_markers(markers: Dictionary, use_native_exit: bool) -> void:
	_markers = markers
	_use_native_exit = use_native_exit
	set_meta("markers", _markers)
	queue_redraw()


func _draw() -> void:
	if _markers.is_empty() or not is_instance_valid(_board):
		return
	var step: Vector2 = _board.cell_center(Vector2i.ONE) - _board.cell_center(Vector2i.ZERO)
	if minf(step.x, step.y) <= 0:
		return
	var radius := clampf(step.y * 0.13, 5.0, 10.0)
	var font := get_theme_default_font()
	for at: Vector2i in _markers:
		var kind: String = _markers[at].kind
		if kind == "zone" or (kind == "exit" and _use_native_exit):
			continue
		var mark: Array = MARKS.get(kind, ["•", "Objective", Color("#e3b970")])
		var center: Vector2 = _board.cell_center(at) + step * Vector2(-0.29, -0.28)
		var ink: Color = mark[2]
		draw_circle(center, radius + 1.0, ink, true, -1.0, true)
		draw_circle(center, radius - 0.5, INK, true, -1.0, true)
		var glyph: String = mark[0]
		var font_size := int(radius * 1.55)
		var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := center + Vector2(-width / 2.0,
			(font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
		draw_string(font, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)


static func trait_notes(profile: Dictionary, definitions: Dictionary) -> PackedStringArray:
	var notes: PackedStringArray = []
	for rule in profile.get("traits", []):
		match str(rule.kind):
			"adjacent_guard":
				notes.append("Adjacent %s takes %d less damage." % [
					_character_label(definitions, rule.protects), int(rule.reduction)])
			"adjacent_damage_bonus":
				notes.append("Adjacent %s gets +%d attack damage." % [
					_character_label(definitions, rule.benefits), int(rule.damage)])
			"death_blast":
				var radius := "adjacent characters" if int(rule.range) == 1 else "characters within %d tiles" % int(rule.range)
				notes.append("On death: %d damage to %s, friend or foe." % [int(rule.damage), radius])
			"retaliate":
				var range_text := "still adjacent" if int(rule.range) == 1 else "still within %d tiles" % int(rule.range)
				notes.append("After surviving a hit, deals %d damage back if the attacker is %s." % [
					int(rule.damage), range_text])
			"ally_death_bonus":
				var bonuses: PackedStringArray = []
				if rule.has("damage"):
					bonuses.append("+%d attack damage" % int(rule.damage))
				if rule.has("reduction"):
					var reduction := "%d less damage taken" % int(rule.reduction)
					if rule.has("max_reduction"):
						reduction += " (max %d)" % int(rule.max_reduction)
					bonuses.append(reduction)
				if rule.has("movement"):
					bonuses.append("+%d movement step%s" % [int(rule.movement), "" if int(rule.movement) == 1 else "s"])
				notes.append("Each other bandit’s defeat grants %s." % ", ".join(bonuses))
	return notes


static func _character_label(definitions: Dictionary, id: String) -> String:
	return definitions.get("characters", {}).get(id, {}).get("label", id.capitalize())
