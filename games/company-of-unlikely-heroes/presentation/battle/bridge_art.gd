extends Control
## An ink-and-wash battle map. The caller owns all cells, occupants, and rules.

signal cell_selected(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal hover_cleared
signal grid_labels_visibility_changed
signal foreground_layer_changed(enabled: bool)
signal sound_beat(kind: String, unit_id: String, ability_id: String, handler: String, recipe: String)
signal committed_reactions_changed

const CastSprites := preload("res://presentation/cast/cast_sprites.gd")
const CastPlayback := preload("res://presentation/cast/cast_playback.gd")
const FittedCastBindings := preload("res://presentation/cast/fitted_cast_bindings.gd")
const BoardPainting := preload("res://presentation/battle/board_painting.gd")

const TILE := Vector2(96, 80)
const GUTTER := Vector2(31, 34)
const FOOT := Vector2(49, 62)
const SHIELD_MARK_CENTER := Vector2(17, 27)
const FOREGROUND_Z_INDEX := 2
const REACTION_MS := 1450.0
const COVER_STATUSES := ["keep_your_head_down", "lend_a_shield"]
const TACTICAL_STATUSES := ["keep_your_head_down", "lend_a_shield", "inspired"]
const INK := Color("#282725")
const PARCHMENT := Color("#f5e5bd")
const RIVER := Color("#28474b")
const FOAM := Color("#b4c6ad")
const STONE := Color("#afa087")
const BRIDGE := Color("#beaa89")
const SAFE := Color("#a0a67a")
const SHORE_WASH := Color("#7eac5b", 0.36)
const AMBER := Color("#ffdc86")
const MINT := Color("#d7edbc")
const CORAL := Color("#ffc1a2")
const ZONE_WASH := Color("#5bacaa", 0.35)
const ZONE_EDGE := Color("#375e5a")
const ZONE_CHALK := Color("#c0e6d7")
const PAINTED_GRID := Color("#272318", 0.57)
const GAP_WASH := Color("#18292b", 0.40)
const GAP_TICKS := Color("#e8e3c5", 0.63)
const PEN_WASH := Color("#2c6553", 0.30)
const PEN_EDGE := Color("#d8e8b8")
const SUMMON_SPRITES := {
	"skeleton": {"path": "res://assets/summons/skeleton.png", "pivot": Vector2(68, 233)},
	"zombie": {"path": "res://assets/summons/zombie.png", "pivot": Vector2(52, 204)},
}
const SUMMON_TEXTURE_SCALE := 1.0 / 3.0
const SHIELD_WALL_SPRITES := {
	"row": {"path": "res://assets/cast/props/shield-wall/row.png",
		"size": Vector2(692, 239), "pivot": Vector2(352, 202), "ground": Vector2(48, 62)},
	"column": {"path": "res://assets/cast/props/shield-wall/column.png",
		"size": Vector2(253, 698), "pivot": Vector2(89, 413), "ground": Vector2(40, 62)},
	"crest_east": {"path": "res://assets/cast/props/shield-wall/crest-east.png",
		"size": Vector2(261, 697), "pivot": Vector2(131, 414), "ground": Vector2(48, 62)},
}
const TILE_FACE := [
	Vector2(2, 2), Vector2(42, 1), Vector2(68, 2), Vector2(91, 1), Vector2(95, 6),
	Vector2(94, 37), Vector2(95, 62), Vector2(91, 78), Vector2(64, 79), Vector2(40, 77),
	Vector2(5, 79), Vector2(1, 75), Vector2(2, 51), Vector2(1, 16),
]

var _cells: Dictionary = {}
var _units: Array = []
var _overlay: Dictionary = {}
var _objective_zone: Dictionary[Vector2i, bool] = {}
var _pen_zone: Dictionary[Vector2i, bool] = {}
var _painting: BoardPainting.Plate
var _grid_visible := true
var _grid_labels_visible := true
var _nameplates_visible := true
var _always_show_health_bar := false
var _bounds := Rect2i()
var _hover: Variant = null
var _map_origin := Vector2.ZERO
var _map_scale := 1.0
var _map_size := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _summon_textures: Dictionary[String, Texture2D] = {}
var _shield_wall_textures: Dictionary[String, Texture2D] = {}
var _cast := CastSprites.new()
var _playback := CastPlayback.new()
var _figures := Node2D.new()
var _tactical := Node2D.new()
var _foreground_above_scenery := false
var _ink_canvas: CanvasItem = self
var _units_by_id: Dictionary = {}
var _targets_by_id: Dictionary = {}
var _ready_clips: Array[CastSprites.Clip] = []
var _ready_samples: Array[Dictionary] = []
var _ready_rates: Dictionary[String, float] = {}
var _ready_ms := 0.0
var _pull_facing: Dictionary[String, float] = {}
var _pull_recovery_facing: Dictionary[String, float] = {}
var _defeat_facing: Dictionary[String, float] = {}
var _pressure_gate_prop_installed := false
var _performance_sound: Callable
var _presentation_ms := 0.0
var _reaction_marks: Array[Dictionary] = []
var _recipient_marks: Array[Dictionary] = []
var _show_reaction_marks := true
# Enrollment spans queued actions; the current HP and retained row do not
# survive the retirement of an instance, even if the next Raise reuses its ID.
var _hp_tracking: Dictionary = {}
var _committed_hp: Dictionary = {}
var _committed_statuses: Dictionary = {}
var _tracked_opening_rows: Dictionary = {}
var _undead_transitions: Array[Dictionary] = []
var _play_dead_corpses: Dictionary = {}
var _prone_recalls: Dictionary = {}
var _next_prone_recall := 0
var _committed_shields: Dictionary = {}
var _capture_actual_draw := false
var _draw_frame_serial := 0
var _actual_draw: Dictionary = {}
var _actual_reactions: Array[Dictionary] = []


func set_performance_sound(dispatch: Callable) -> void:
	_performance_sound = dispatch


func set_actual_draw_capture_enabled(enabled: bool) -> void:
	_capture_actual_draw = enabled
	if not enabled:
		_actual_draw.clear()
		_actual_reactions.clear()
	_figures.queue_redraw()
	committed_reactions_changed.emit()


## Opt-in evidence from successful paint calls, not queued animation metadata.
## Read after frame_post_draw and pair it with the visible viewport image.
func actual_draw_snapshot() -> Dictionary:
	if _actual_draw.is_empty():
		return {}
	var snapshot := _actual_draw.duplicate(true)
	snapshot["reactions"] = _actual_reactions.duplicate(true)
	return snapshot


func record_actual_draw_reactions(reactions: Array[Dictionary]) -> void:
	if _capture_actual_draw:
		_actual_reactions = reactions


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout)
	mouse_exited.connect(_clear_hover)
	for role: String in SUMMON_SPRITES:
		_summon_textures[role] = CastSprites.load_texture(SUMMON_SPRITES[role].path)
	for orientation: String in SHIELD_WALL_SPRITES:
		var path: String = SHIELD_WALL_SPRITES[orientation].path
		_shield_wall_textures[path] = CastSprites.load_texture(path)
	_cast.load_manifest()
	_tactical.name = "TacticalForeground"
	_tactical.draw.connect(_draw_tactical_layer)
	add_child(_tactical)
	_figures.name = "CastAndUnitMarkers"
	_figures.draw.connect(_draw_figures)
	add_child(_figures)
	_set_ready_clips()
	_layout()


## Used for transparent-aperture scenery that must cover terrain gutters but
## remain behind all tactical marks, objects, coordinates and figures.
func set_foreground_above_scenery(enabled: bool) -> void:
	_foreground_above_scenery = enabled
	_tactical.z_index = FOREGROUND_Z_INDEX if enabled else 0
	_figures.z_index = FOREGROUND_Z_INDEX if enabled else 0
	queue_redraw()
	_tactical.queue_redraw()
	foreground_layer_changed.emit(enabled)


func foreground_above_scenery() -> bool:
	return _foreground_above_scenery


## The caller supplies a board ID only when launched from the built-in catalog.
func set_painting(board_id: String) -> void:
	_painting = BoardPainting.open(board_id) if not board_id.is_empty() else null
	queue_redraw()


func set_grid_visible(shown: bool) -> void:
	if _grid_visible != shown:
		_grid_visible = shown
		queue_redraw()


func set_grid_labels_visible(shown: bool) -> void:
	if _grid_labels_visible != shown:
		_grid_labels_visible = shown
		queue_redraw()
		grid_labels_visibility_changed.emit()


func are_grid_labels_visible() -> bool:
	return _grid_labels_visible


func set_nameplates_visible(shown: bool) -> void:
	if _nameplates_visible != shown:
		_nameplates_visible = shown
		_figures.queue_redraw()


func set_always_show_health_bar(shown: bool) -> void:
	if _always_show_health_bar != shown:
		_always_show_health_bar = shown
		_figures.queue_redraw()


## Set only while a replacement pressure-gate prop is actually installed.
func set_pressure_gate_prop_installed(installed: bool) -> void:
	_pressure_gate_prop_installed = installed
	queue_redraw()


## cells: Vector2i -> "stone", "bridge", "broken", "safe", "exit", "obstacle", or "water".
## An absent cell is scenery only. The canvas emits input for supplied cells; it never authorizes moves.
## units: {id, art_key, cell, hp, max_hp, prone}; optional facing (-1 left, 1 right),
## cast_key, guarded, shield_away, shield_cell, tactical_statuses, objective, variant, label and color.
## pursuit_target: {id: String, label: String}, supplied only for a living tracked target.
## overlay: selected/chosen_target/commanded (Vector2i), targets/impact/threat (arrays of Vector2i),
## paths (each an array of Vector2i), exit (Vector2i), safe (a set of Vector2i),
## objective_zone (array of [x, y] pairs or Vector2i), obstacles (id, art_key, position, hp, max_hp,
## optional cells including position), forecast_obstacle_cells (array of Vector2i),
## pen_zone (array of Vector2i), pressure_gate ({cell: Vector2i, open: bool}),
## shields/forecast_shields (arrays of Vector2i), quiet_manual_move (bool).
func set_render_state(cells: Dictionary, units: Array, overlay: Dictionary = {}) -> void:
	_cells = cells.duplicate()
	_units = units.duplicate(true)
	_overlay = overlay.duplicate(true)
	var previous_units := _units_by_id.duplicate()
	_units_by_id.clear()
	_targets_by_id.clear()
	for unit: Dictionary in _units:
		_units_by_id[unit.id] = unit
		_targets_by_id[unit.id] = unit.cell
	for obstacle: Dictionary in _overlay.get("obstacles", []):
		_targets_by_id[obstacle.id] = obstacle.position
	for id in previous_units:
		var previous: Dictionary = previous_units[id]
		var current: Dictionary = _units_by_id.get(id, {})
		if int(previous.get("hp", 1)) > 0 and int(current.get("hp", 1)) <= 0 \
				and current.get("visual_defeat", false) and _pull_facing.has(id):
			# The refreshed board is already dead, but the lethal cue can still
			# be waiting for its attacker's impact.
			_defeat_facing[id] = _pull_facing[id]
		elif current.is_empty() or int(current.get("hp", 1)) > 0:
			_defeat_facing.erase(id)
		if bool(previous.get("prone", false)) \
				and (not bool(current.get("prone", false)) or int(current.get("hp", 1)) <= 0):
			if not current.is_empty() and int(current.get("hp", 1)) > 0:
				_remember_pull_recovery_facing(id)
			_playback.clear_pull_recoil(id)
		elif not bool(previous.get("prone", false)) and bool(current.get("prone", false)):
			_pull_recovery_facing.erase(id)
		if current.is_empty() or int(current.get("hp", 1)) <= 0:
			_pull_recovery_facing.erase(id)
	for id in _pull_facing.keys():
		var unit: Dictionary = _units_by_id.get(id, {})
		if not bool(unit.get("prone", false)) or int(unit.get("hp", 1)) <= 0:
			_pull_facing.erase(id)
			_playback.clear_pull_recoil(id)
	for id in _defeat_facing.keys():
		if not _units_by_id.get(id, {}).get("visual_defeat", false):
			_defeat_facing.erase(id)
	_set_ready_clips()
	_objective_zone.clear()
	for at in _overlay.get("objective_zone", []):
		if at is Vector2i:
			_objective_zone[at] = true
		elif at is Array and at.size() == 2:
			_objective_zone[Vector2i(int(at[0]), int(at[1]))] = true
	_pen_zone.clear()
	for at: Vector2i in _overlay.get("pen_zone", []):
		_pen_zone[at] = true
	_bounds = Rect2i()
	var first := true
	for value in _cells:
		var cell: Vector2i = value
		var rect := Rect2i(cell, Vector2i.ONE)
		_bounds = rect if first else _bounds.merge(rect)
		first = false
	if _hover != null and not _cells.has(_hover):
		_clear_hover()
	_layout()


## Capture just the rows whose committed effects need to outlive the old snapshot.
## Call on the opening board, before installing the already resolved board.
func prepare_committed_presentation(cues: Array, corpses: Dictionary = {}) -> void:
	for cue: Dictionary in cues:
		var use: Dictionary = cue.get("performance", {})
		for effect: Dictionary in use.get("effects", []):
			var id: String = effect.target_id
			var unit: Dictionary = _units_by_id.get(id, {})
			match effect.kind:
				"shield_wall_placed":
					# Zero HP masks the resolved row until the placement beat. Retain
					# its footprint in case it is absent from the resolved board.
					_hp_tracking[id] = true
					_committed_hp[id] = 0
					_tracked_opening_rows[id] = {"id": id, "position": effect.cell, "cells": effect.cells,
						"art_key": effect.art_key, "hp": effect.hp_after, "max_hp": effect.hp_after,
						"facing": effect.get("facing", Vector2i.ZERO)}
				"damage", "heal", "collapse_fall":
					var opening: Dictionary = unit if not unit.is_empty() else _obstacle_row(id)
					if not _hp_tracking.has(id) and (use.branch in ["converted", "boundary", "reaction"] \
							or use.has("dose") or opening.get("cells", []).size() > 1):
						_hp_tracking[id] = true
						if not opening.is_empty():
							_committed_hp[id] = opening.hp
							_tracked_opening_rows[id] = opening
				"status", "primary_improvement", "status_expired":
					if effect.get("status_id") in TACTICAL_STATUSES and not _committed_statuses.has(id):
						_committed_statuses[id] = unit.get("tactical_statuses", {}).duplicate()
				"play_dead":
					var zombie: Dictionary = _units_by_id.get(effect.retired_id, {})
					if not zombie.is_empty():
						_undead_transitions.append({"kind": effect.kind, "zombie_id": effect.retired_id,
							"zombie": zombie.merged({"cell": effect.cell}, true),
								"corpse_id": id, "prior_corpse": unit,
								"corpse": corpses.get(id, {})})
				"recall":
					if unit.get("prone", false):
						var token := _next_prone_recall
						_next_prone_recall += 1
						effect["board_prone_recall"] = token
						_prone_recalls[token] = {"id": id, "companion": null}
				"summon":
					var corpse_id: String = effect.get("corpse_id", "")
					var corpse := _before_corpse_raise(corpse_id)
					if not corpse.is_empty():
						_undead_transitions.append({"kind": effect.kind, "zombie_id": id,
							"corpse_id": corpse_id, "corpse": corpse})
				"shield_drop":
					if use.form_id == "lend_a_shield" and not _committed_shields.has(use.actor_id):
						_committed_shields[use.actor_id] = _units_by_id.get(use.actor_id, {}).get("shield_cell")


## Only committed cues belong here. A state refresh replaces the board, not the timeline.
func play_committed_actions(cues: Array) -> void:
	var obstacle_visuals := _obstacle_visuals()
	var prepared := []
	for value in cues:
		var cue: Variant = value
		if cue is Dictionary:
			var id := str(cue.get("unit_id", ""))
			if cue.get("control") == "clear_pull_recoil":
				_remember_pull_recovery_facing(id)
				_pull_facing.erase(id)
				_defeat_facing.erase(id)
			elif cue.get("hero_defeat", false) and _units_by_id.get(id, {}).get("visual_defeat", false):
				var facing: Variant = cue.get("facing")
				if (facing is int or facing is float) and absf(float(facing)) == 1.0:
					_defeat_facing[id] = float(facing)
				elif _defeat_facing.has(id):
					cue = cue.duplicate(true)
					cue["facing"] = _defeat_facing[id]
			elif cue.get("hero_knockdown") == "seated_recover":
				var facing: Variant = cue.get("facing")
				if not ((facing is int or facing is float) and absf(float(facing)) == 1.0) \
						and _pull_recovery_facing.has(id):
					cue = cue.duplicate(true)
					cue["facing"] = _pull_recovery_facing[id]
				_pull_recovery_facing.erase(id)
			elif cue.get("hero_knockdown") in ["down", "recover"]:
				_pull_recovery_facing.erase(id)
		prepared.append(cue)
	_playback.enqueue(prepared, _cast)
	if not _playback.pending():
		_clear_committed_projection()
	_sync_playback_geometry()
	_set_processing()
	_figures.queue_redraw()
	if obstacle_visuals != _obstacle_visuals():
		_queue_tactical_redraw()


func clear_action_playback() -> void:
	var obstacle_visuals := _obstacle_visuals()
	_playback.clear()
	_clear_committed_projection()
	_undead_transitions.clear()
	_play_dead_corpses.clear()
	_recipient_marks.clear()
	_reaction_marks.clear()
	committed_reactions_changed.emit()
	_pull_facing.clear()
	_pull_recovery_facing.clear()
	_defeat_facing.clear()
	_set_processing()
	_figures.queue_redraw()
	if obstacle_visuals != _obstacle_visuals():
		_queue_tactical_redraw()


func _clear_committed_projection() -> void:
	_hp_tracking.clear()
	_committed_hp.clear()
	_committed_statuses.clear()
	_tracked_opening_rows.clear()
	_committed_shields.clear()
	_prone_recalls.clear()


func _remember_pull_recovery_facing(id: String) -> void:
	var facing: float = _pull_facing.get(id, _playback.pull_recoil_facing(id))
	if facing != 0.0:
		_pull_recovery_facing[id] = facing


func action_playback_snapshot() -> Array:
	return _playback.snapshot()


func action_playback_pending() -> bool:
	return _playback.pending()


func committed_visuals_pending() -> bool:
	return _playback.pending() or not _recipient_marks.is_empty() \
		or (_show_reaction_marks and not _reaction_marks.is_empty())


func action_playback_remaining_ms() -> float:
	return _playback.remaining_ms()


func committed_visuals_remaining_ms() -> float:
	var remaining := _playback.remaining_ms()
	for mark in _recipient_marks:
		remaining = maxf(remaining, float(mark.at) + CastPlayback.FEEDBACK_MS - _presentation_ms)
	if _show_reaction_marks:
		for mark in _reaction_marks:
			remaining = maxf(remaining, float(mark.at) + REACTION_MS - _presentation_ms)
	return remaining


func hide_committed_reactions() -> void:
	_show_reaction_marks = false
	_reaction_marks.clear()
	committed_reactions_changed.emit()
	_set_processing()


## Same aged marks used by the ink painter; cells are sampled at dose delivery.
func committed_reaction_marks() -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	for mark in _reaction_marks:
		marks.append(mark.merged({"age_ms": _presentation_ms - float(mark.at)}, true))
	return marks


func _set_ready_clips() -> void:
	_ready_clips.clear()
	_ready_samples.clear()
	_ready_rates.clear()
	for unit in _units:
		var id := str(unit.get("id", ""))
		var rate := _ready_rate(id)
		_ready_rates[id] = rate
		if bool(unit.get("prone", false)) or int(unit.get("hp", 1)) <= 0 \
				or bool(unit.get("shield_away", false)):
			continue
		var clip := _cast.clip_for(str(unit.get("cast_key", "")), "ready")
		if clip != null and clip.loop and clip.frames.size() > 1:
			_ready_samples.append({"clip": clip, "rate": rate})
			if not _ready_clips.has(clip):
				_ready_clips.append(clip)
	_set_processing()


func _ready_rate(id: String) -> float:
	if id.is_empty():
		return 1.0
	# Mix the stable string hash so similar placement IDs do not produce
	# nearly identical rates. Keep the full range rather than discrete buckets.
	var value := id.hash() & 0xffffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	value = value ^ (value >> 16)
	return 0.94 + 0.12 * float(value) / 4294967295.0


func _set_processing() -> void:
	set_process(committed_visuals_pending() or not _ready_clips.is_empty())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var previous_ms := _ready_ms
	var delta_ms := delta * 1000.0
	_ready_ms += delta_ms
	var opening_ms := _presentation_ms
	_presentation_ms += delta_ms
	var reaction_redraw := not _reaction_marks.is_empty()
	var redraw := _playback.pending() or not _recipient_marks.is_empty()
	if _playback.pending():
		var obstacle_visuals := _obstacle_visuals()
		var beats: Array = _playback.advance(delta_ms)
		var presentation := _playback.presentation_beats()
		for beat: Dictionary in presentation:
			reaction_redraw = _apply_presentation_beat(beat, opening_ms + float(beat.offset)) or reaction_redraw
		if not _prone_recalls.is_empty():
			for token in _prone_recalls.keys():
				var child: CastPlayback.Entry = _prone_recalls[token].companion
				if child != null and child.elapsed_ms >= child.duration_ms:
					_prone_recalls.erase(token)
		_dispatch_playback_sound(beats, presentation)
		if not _playback.pending():
			_clear_committed_projection()
			for id in _play_dead_corpses.keys():
				if _units_by_id.get(id, {}).get("label") != "Corpse":
					_play_dead_corpses.erase(id)
		if obstacle_visuals != _obstacle_visuals():
			_queue_tactical_redraw()
		_sync_playback_geometry()
		for entry in _playback.active():
			if entry.cue.get("hero_defeat", false) and entry.facing != 0.0 \
					and _units_by_id.get(entry.cue.unit_id, {}).get("visual_defeat", false):
				_defeat_facing[entry.cue.unit_id] = entry.facing
	elif not redraw:
		for sample in _ready_samples:
			var clip: CastSprites.Clip = sample.clip
			var rate: float = sample.rate
			if clip.frame_index(previous_ms * rate) != clip.frame_index(_ready_ms * rate):
				redraw = true
				break
	_recipient_marks = _recipient_marks.filter(func(mark): return _presentation_ms - mark.at < CastPlayback.FEEDBACK_MS)
	_reaction_marks = _reaction_marks.filter(func(mark): return _presentation_ms - mark.at < REACTION_MS)
	if reaction_redraw:
		committed_reactions_changed.emit()
	_set_processing()
	if redraw:
		_figures.queue_redraw()


func _dispatch_playback_sound(legacy: Array, normalized: Array) -> void:
	var i := 0
	var j := 0
	while i < legacy.size() or j < normalized.size():
		var old: Dictionary = legacy[i] if i < legacy.size() else {}
		var beat: Dictionary = normalized[j] if j < normalized.size() else {}
		var matching: bool = (old.get("kind") == "impact" and beat.get("kind") == "impact" \
			and beat.has("cue_order") and beat.cue_order == old.get("cue_order")) \
			or (old.get("kind") == "step" and beat.get("kind") == "motion_land" \
			and beat.has("motion_order") and beat.motion_order == old.get("motion_order"))
		if not beat.is_empty() and (matching or old.is_empty() \
				or beat.offset < old.offset or (beat.offset == old.offset \
				and _sound_order(beat) <= _sound_order(old))):
			var handled := _performance_sound.is_valid() and bool(_performance_sound.call(beat))
			j += 1
			if not matching:
				continue
			if handled:
				i += 1
				continue
		sound_beat.emit(old.kind, old.unit_id, old.ability_id, old.handler, old.recipe)
		i += 1


static func _sound_order(beat: Dictionary) -> int:
	return int(beat.get("motion_order", beat.get("cue_order", -1)))


func _apply_presentation_beat(beat: Dictionary, at: float) -> bool:
	var reaction_redraw := false
	var use_normalized_ink := _uses_normalized_recipient_ink(beat)
	for effect: Dictionary in beat.effects:
		var id: String = effect.target_id
		var cell: Variant = effect.get("cell")
		var ink := ""
		match effect.kind:
			"shield_wall_placed", "collapse_fall":
				if _hp_tracking.has(id):
					_committed_hp[id] = effect.hp_after
			"damage", "heal":
				if _hp_tracking.has(id) and not effect.get("hp_superseded", false):
					var delta: int = int(effect.get("amount", 0)) * (-1 if effect.kind == "damage" else 1)
					var hp: int = _committed_hp.get(id, 0)
					_committed_hp[id] = int(effect.get("hp_after", maxi(0, hp + delta)))
				if int(effect.get("amount", 0)) > 0:
					ink = "hit" if effect.kind == "damage" else "heal"
			"status", "primary_improvement", "status_expired":
				var status: String = effect.get("status_id", "")
				if status in TACTICAL_STATUSES and _committed_statuses.has(id):
					if effect.get("consumed", false) or effect.kind == "status_expired":
						_committed_statuses[id].erase(status)
					else:
						_committed_statuses[id][status] = true
						ink = "guard" if status in COVER_STATUSES else "status"
				elif effect.get("removed", false):
					ink = "status"
			"alchemy_reaction":
				if _show_reaction_marks and cell is Vector2i:
					_reaction_marks.append({"at": at, "position": cell, "target_id": id,
						"reaction_id": effect.reaction_id, "category": effect.category})
					reaction_redraw = true
			"push", "pull", "repel", "move", "recall", "swap":
				if beat.kind == "motion_land":
					cell = effect.get("to", cell)
					ink = "shift"
					if effect.kind == "recall" and effect.has("board_prone_recall"):
						_land_prone_recall(effect.board_prone_recall, int(beat.cue_order))
			"shield_drop":
				if _committed_shields.has(effect.source_id):
					_committed_shields[effect.source_id] = cell
			"shield_retrieve":
				if _committed_shields.has(effect.target_id):
					_committed_shields[effect.target_id] = null
			"play_dead":
				if beat.kind == "handoff":
					_cross_undead_transition(effect.kind, effect.retired_id, id)
					# Raise may reuse this ID, but must not inherit the prior life's HP
					# or its retained living row during the intervening corpse state.
					_committed_hp.erase(effect.retired_id)
					_tracked_opening_rows.erase(effect.retired_id)
			"summon":
				_cross_undead_transition(effect.kind, id, effect.get("corpse_id", ""))
				if _hp_tracking.has(id) and effect.has("hp_after"):
					_committed_hp[id] = effect.hp_after
			"fit", "rally", "taunt", "nominate":
				ink = "status"
		if use_normalized_ink and not ink.is_empty() and cell is Vector2i and _cells.has(cell):
			_recipient_marks.append({"at": at, "cell": cell, "target_id": id, "kind": ink})
	if beat.kind == "impact" and use_normalized_ink and beat.has("dose") \
			and not beat.effects.any(func(effect): return effect.target_id == beat.dose.recipient_id \
				and effect.kind in ["damage", "heal"]):
		# A capped heal or absorbed dose still arrived, but this is not an HP spark.
		_recipient_marks.append({"at": at, "cell": beat.dose.cell,
			"target_id": beat.dose.recipient_id, "kind": "status"})
	return reaction_redraw


static func _uses_normalized_recipient_ink(performance: Dictionary) -> bool:
	# Repeat can replay a fitted dose without itself being a conversion. The
	# ordinary source clip's usual contact ink doesn't describe this delivery.
	return performance.get("branch") == "converted" or FittedCastBindings.replays_fitted_dose(performance)


func _land_prone_recall(token: int, cue_order: int) -> void:
	if not _prone_recalls.has(token):
		return
	var companion := _playback.companion_for(cue_order)
	if companion == null:
		_prone_recalls.erase(token)
	else:
		_prone_recalls[token].companion = companion


func _before_corpse_raise(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	for index in range(_undead_transitions.size() - 1, -1, -1):
		var transition := _undead_transitions[index]
		if transition.corpse_id == id:
			return transition.corpse if transition.kind == "play_dead" else {}
	var corpse: Dictionary = _play_dead_corpses.get(id, _units_by_id.get(id, {}))
	return corpse if corpse.get("label") == "Corpse" else {}


func _cross_undead_transition(kind: String, zombie_id: String, corpse_id: String) -> void:
	for index in _undead_transitions.size():
		var transition := _undead_transitions[index]
		if transition.kind != kind or transition.zombie_id != zombie_id or transition.corpse_id != corpse_id:
			continue
		if kind == "play_dead" and not transition.corpse.is_empty():
			_play_dead_corpses[corpse_id] = transition.corpse
		else:
			_play_dead_corpses.erase(corpse_id)
		_undead_transitions.remove_at(index)
		return


## Invalidate tactical ink when a visible obstacle's footprint or HP changes.
func _obstacle_visuals() -> Array:
	var visuals := []
	for obstacle: Dictionary in _presentation_obstacles():
		var position: Variant = _obstacle_position(obstacle)
		if position != null:
			visuals.append([position, obstacle.get("cells", []), obstacle.hp, obstacle.art_key,
				obstacle.get("facing", Vector2i.ZERO)])
	return visuals


func _obstacle_row(id: String) -> Dictionary:
	for row: Dictionary in _overlay.get("obstacles", []):
		if row.id == id:
			return row
	return {}


func _presentation_obstacles() -> Array:
	if _committed_hp.is_empty():
		return _overlay.get("obstacles", [])
	var obstacles: Array = _overlay.get("obstacles", []).duplicate()
	for id in _tracked_opening_rows:
		var opening: Dictionary = _tracked_opening_rows[id]
		if opening.has("position") and not obstacles.any(func(row): return row.id == id):
			obstacles.append(opening)
	return obstacles.map(_project_committed_row)


func _obstacle_position(obstacle: Dictionary) -> Variant:
	var id := str(obstacle.get("id", ""))
	var cell: Vector2i = _playback.actor_cell(id, obstacle.position) \
		if _playback.movement_source(id) is Vector2i or _playback.has_settled_position(id) \
		else obstacle.position
	if obstacle.hp <= 0 or not _cells.has(cell):
		return null
	var position := _tile_origin(cell)
	var destination: Variant = _playback.movement_destination(id)
	if destination is Vector2i:
		position = position.lerp(_tile_origin(destination), _playback.movement_fraction(id))
	return position


## The returned rectangle is relative to the wall's center tile.
static func shield_wall_sprite_spec(obstacle: Dictionary) -> Dictionary:
	var center: Vector2i = obstacle.position
	var orientation := "column"
	for cell: Vector2i in obstacle.get("cells", []):
		if cell.x != center.x:
			orientation = "row"
			break
	var facing: Variant = obstacle.get("facing", Vector2i.ZERO)
	if orientation == "column" and facing is Vector2i and facing.x > 0:
		orientation = "crest_east"
	var sprite: Dictionary = SHIELD_WALL_SPRITES[orientation]
	return {"texture_path": sprite.path,
		"rect": Rect2(sprite.ground - sprite.pivot / 3.0, sprite.size / 3.0)}


func _queue_tactical_redraw() -> void:
	if _foreground_above_scenery:
		_tactical.queue_redraw()
	else:
		queue_redraw()


func _layout() -> void:
	_map_size = Vector2(_bounds.size) * TILE + GUTTER * 2.0
	_map_scale = minf(size.x / _map_size.x, size.y / _map_size.y)
	_map_origin = (size - _map_size * _map_scale) * 0.5
	queue_redraw()
	_figures.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell: Variant = cell_at(event.position)
		if cell == null:
			_clear_hover()
		elif cell != _hover:
			_hover = cell
			cell_hovered.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell: Variant = cell_at(event.position)
		if cell != null:
			cell_selected.emit(cell)
			accept_event()


func _clear_hover() -> void:
	if _hover == null:
		return
	_hover = null
	hover_cleared.emit()
	queue_redraw()


## Returns null in the gutter or in a hole in the caller's cell map.
func cell_at(point: Vector2) -> Variant:
	if _map_scale <= 0.0:
		return null
	var local := ((point - _map_origin) / _map_scale - GUTTER) / TILE
	var cell := Vector2i(floori(local.x), floori(local.y)) + _bounds.position
	return cell if _cells.has(cell) else null


func cell_center(cell: Vector2i) -> Vector2:
	return _map_origin + (_tile_origin(cell) + TILE * 0.5) * _map_scale


static func coordinate(cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0:
		return "%d,%d" % [cell.x, cell.y]
	return "%s%d" % [_column_name(cell.x), cell.y + 1]


@warning_ignore("integer_division")
static func _column_name(column: int) -> String:
	if column < 0:
		return str(column)
	var label := ""
	var value := column + 1
	while value > 0:
		value -= 1
		label = String.chr(65 + value % 26) + label
		value /= 26
	return label


func _tile_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell - _bounds.position) * TILE + GUTTER


func _at(point: Vector2, angle := 0.0, local_scale := Vector2.ONE) -> void:
	_ink_canvas.draw_set_transform(_map_origin + point * _map_scale, angle, local_scale * _map_scale)


func _draw() -> void:
	_ink_canvas = self
	draw_rect(Rect2(Vector2.ZERO, size), Color("#203639"))
	if _map_scale <= 0.0:
		return
	_at(Vector2.ZERO)
	var painted: bool = _painting != null and _bounds.position == Vector2i.ZERO \
		and _bounds.size == _painting.dimensions
	var cells := _cells.keys()
	cells.sort_custom(_reading_order)
	if painted:
		_painting.draw(self, _map_size, GUTTER, TILE)
	else:
		_draw_water()
		for cell: Vector2i in cells:
			_at(_tile_origin(cell))
			_draw_escapement(cell)
	if _foreground_above_scenery:
		_tactical.queue_redraw()
	else:
		_draw_tactical()


func _draw_tactical_layer() -> void:
	if not _foreground_above_scenery or _map_scale <= 0.0:
		return
	_ink_canvas = _tactical
	_draw_tactical()
	_ink_canvas = self


func _draw_tactical() -> void:
	var painted: bool = _painting != null and _bounds.position == Vector2i.ZERO \
		and _bounds.size == _painting.dimensions
	var cells := _cells.keys()
	cells.sort_custom(_reading_order)
	var shore: Dictionary = _overlay.get("safe", {})
	var gate: Dictionary = _overlay.get("pressure_gate", {})
	for cell: Vector2i in cells:
		_at(_tile_origin(cell))
		if painted:
			_draw_painted_tile(cell)
		else:
			_draw_tile(cell)
		if shore.has(cell):
			_piece(TILE_FACE, SHORE_WASH)
		if _objective_zone.has(cell):
			_draw_objective_square()
		if _pen_zone.has(cell):
			_draw_pen(cell)
		if _overlay.get("exit") == cell:
			_draw_exit()
		if gate.get("cell") == cell and not _pressure_gate_prop_installed:
			_draw_pressure_gate(gate.open)
	if painted and _grid_visible:
		for cell: Vector2i in cells:
			_at(_tile_origin(cell))
			_draw_painted_grid(cell)
	_at(Vector2.ZERO)
	for path in _overlay.get("paths", []):
		_draw_path(path)
	for value in cells:
		var cell: Vector2i = value
		_at(_tile_origin(cell))
		_draw_overlays(cell)
	for obstacle: Dictionary in _presentation_obstacles():
		var position: Variant = _obstacle_position(obstacle)
		if position is Vector2:
			if obstacle.art_key == "shield_wall":
				var spec := shield_wall_sprite_spec(obstacle)
				var texture: Texture2D = _shield_wall_textures.get(spec.texture_path)
				_at(position)
				if texture != null:
					_ink_canvas.draw_texture_rect(texture, spec.rect, false)
			else:
				for cell: Vector2i in obstacle.get("cells", [obstacle.position]):
					var offset := Vector2(cell - obstacle.position) * TILE
					_at(position + offset)
					_draw_object_segment(obstacle.art_key)
			# Keep the wall's shared health bar clear of an adjacent Knight.
			_at(position + Vector2(0, -13) if obstacle.art_key == "shield_wall" else position)
			_draw_health(obstacle, false, false)
	if not _cells.is_empty() and _grid_labels_visible:
		_at(Vector2.ZERO)
		_draw_coordinates()


func _draw_painted_tile(cell: Vector2i) -> void:
	match str(_cells[cell]):
		"bridge":
			_draw_deck(cell)
		"broken", "water":
			_ink_canvas.draw_rect(Rect2(Vector2.ZERO, TILE), GAP_WASH)
			# Mark the drop even where the painted rock or shoreline wanders into the cell.
			_line([Vector2(6, 19), Vector2(6, 6), Vector2(19, 6)], GAP_TICKS, 1.55)
			_line([TILE - Vector2(6, 19), TILE - Vector2(6, 6), TILE - Vector2(19, 6)], GAP_TICKS, 1.55)


func _draw_painted_grid(cell: Vector2i) -> void:
	# Draw a shared edge only once. The grid works without masking the deck or foreground art.
	_line([Vector2(0, TILE.y), Vector2.ZERO, Vector2(TILE.x, 0)], PAINTED_GRID, 1.6)
	if not _cells.has(cell + Vector2i.RIGHT):
		_line([Vector2(TILE.x, 0), TILE], PAINTED_GRID, 1.6)
	if not _cells.has(cell + Vector2i.DOWN):
		_line([Vector2(0, TILE.y), TILE], PAINTED_GRID, 1.6)


func _draw_deck(cell: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) + 371
	var left := str(_cells.get(cell + Vector2i.LEFT, ""))
	var right := str(_cells.get(cell + Vector2i.RIGHT, ""))
	var top := 0.0 if _cells.get(cell + Vector2i.UP) == "bridge" else 5.0
	var bottom := TILE.y if _cells.get(cell + Vector2i.DOWN) == "bridge" else TILE.y - 6.0
	# The narrow crossing leaves some water visible above and below the boards.
	if _solid(left) and _solid(right) and left != "bridge" and right != "bridge":
		top = 13.0
		bottom = 66.0
		_draw_deck_sill(0.0, 1.0)
		_draw_deck_sill(TILE.x, -1.0)
	var x0 := 2.0 if not _solid(left) else 0.0
	var x1 := TILE.x - 2.0 if not _solid(right) else TILE.x
	_ink_canvas.draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color("#4d3c30"))
	for i in range(8):
		var a := lerpf(x0, x1, i / 8.0)
		var b := lerpf(x0, x1, (i + 1) / 8.0)
		var crack := bottom - rng.randf_range(1.2, 3.0)
		var oak := Color("#aa885b").lerp(Color("#644b36") if i % 3 == 0 else Color("#d8b785"),
			rng.randf_range(0.08, 0.48))
		_piece([Vector2(a + 0.6, top + 0.8), Vector2(b - 0.5, top + 1.0),
			Vector2(b - 0.8, crack), Vector2(a + 0.5, bottom - 1.3)], oak)
		for j in range(3):
			var grain_x := rng.randf_range(a + 2.0, b - 2.0)
			var grain_y := rng.randf_range(top + 4.0, bottom - 16.0)
			_line([Vector2(grain_x, grain_y), Vector2(grain_x - 0.6, grain_y + 9.0)],
				Color("#523e29", 0.35), 0.85)
		if top > 0.0:
			_ink_canvas.draw_circle(Vector2((a + b) * 0.5, top + 5.0), 1.15, Color("#523e29"))
		if bottom < TILE.y:
			_ink_canvas.draw_circle(Vector2((a + b) * 0.5, bottom - 6.0), 1.15, Color("#523e29"))
	if top > 0.0:
		_line([Vector2(x0, top + 1.0), Vector2(x1, top + 1.0)], Color("#e1c696", 0.76), 1.25)
	if bottom < TILE.y:
		_line([Vector2(x0, bottom - 1.0), Vector2(x1, bottom - 1.0)], Color("#644933"), 2.7)


func _draw_deck_sill(edge: float, inward: float) -> void:
	# The stone ends cover the irregular painted banks only while the deck exists.
	var outer := edge - inward * 23.0
	var inner := edge + inward * 6.0
	_piece([Vector2(outer, 17), Vector2(inner, 10), Vector2(inner, 64),
		Vector2(outer + inward * 3.0, 68), Vector2(outer - inward * 2.0, 43)],
		Color("#9a896a"), Color("#514638"), 2.1)
	_line([Vector2(outer, 18), Vector2(inner, 12)], Color("#d9bf93"), 1.8)
	_line([Vector2(outer, 33), Vector2(edge - inward * 12.0, 37),
		Vector2(inner, 32)], Color("#665c49"), 1.4)
	_line([Vector2(outer, 51), Vector2(edge - inward * 10.0, 47),
		Vector2(inner, 54)], Color("#685c48"), 1.5)


func _draw_pen(cell: Vector2i) -> void:
	_ink_canvas.draw_rect(Rect2(Vector2.ZERO, TILE), PEN_WASH)
	for edge in [
		[Vector2i.UP, Vector2.ZERO, Vector2(TILE.x, 0)],
		[Vector2i.RIGHT, Vector2(TILE.x, 0), TILE],
		[Vector2i.DOWN, TILE, Vector2(0, TILE.y)],
		[Vector2i.LEFT, Vector2(0, TILE.y), Vector2.ZERO],
	]:
		if not _pen_zone.has(cell + edge[0]):
			_line([edge[1], edge[2]], ZONE_EDGE, 5.7)
			_line([edge[1], edge[2]], PEN_EDGE, 2.5)


func _draw_pressure_gate(open: bool) -> void:
	# The threshold is always usable ground in the painting. The slatted panel comes from state.
	if not open:
		_wash(Vector2(35, 11), Vector2(25, 60), Color("#342825", 0.32))
		_piece([Vector2(41, 14), Vector2(54, 11), Vector2(55, 67), Vector2(42, 68)],
			Color("#765140"), Color("#342b27"), 2.0)
		for y in [21, 32, 43, 54, 64]:
			_line([Vector2(43, y + 1), Vector2(53, y - 1)], Color("#ca9f70"), 1.6)
		_line([Vector2(48, 16), Vector2(49, 65)], Color("#3c322c"), 1.7)
	for y in [12, 68]:
		_ink_canvas.draw_circle(Vector2(48, y), 5.5, Color("#3b3328"), true, -1.0, true)
		_ink_canvas.draw_circle(Vector2(47, y - 1), 2.5, Color("#b69667"), true, -1.0, true)


func _presentation_units() -> Array:
	if _committed_hp.is_empty() and _committed_statuses.is_empty() and _undead_transitions.is_empty() \
			and _play_dead_corpses.is_empty() \
			and _prone_recalls.is_empty() and _committed_shields.is_empty():
		return _units
	var by_id := _units_by_id.duplicate()
	for id in _play_dead_corpses:
		var corpse: Dictionary = _play_dead_corpses[id]
		var current: Dictionary = by_id.get(id, {})
		if current.get("label") == "Corpse" and current.get("cell") == corpse.cell:
			by_id[id] = corpse
		elif _playback.pending() and current.is_empty() \
				and not by_id.values().any(func(row): return row.hp > 0 and row.cell == corpse.cell):
			by_id[id] = corpse
	# Undo outstanding exchanges newest first. A Raise can reuse the retired
	# zombie's ID; a set of hidden IDs cannot represent several such exchanges.
	for index in range(_undead_transitions.size() - 1, -1, -1):
		var transition := _undead_transitions[index]
		if transition.kind == "summon":
			by_id.erase(transition.zombie_id)
			by_id[transition.corpse_id] = transition.corpse
		else:
			by_id[transition.zombie_id] = transition.zombie
			by_id.erase(transition.corpse_id)
			if not transition.prior_corpse.is_empty():
				by_id[transition.corpse_id] = transition.prior_corpse
	for id in _tracked_opening_rows:
		var old: Dictionary = _tracked_opening_rows[id]
		var current: Dictionary = by_id.get(id, {})
		if old.has("cell") and int(_committed_hp.get(id, 0)) > 0 \
				and int(current.get("hp", 0)) <= 0:
			by_id[id] = old
	return by_id.values().map(_project_committed_row)


func _project_committed_row(original: Dictionary) -> Dictionary:
	var id: String = original.id
	var row := original
	if _committed_hp.has(id):
		row = row.merged({"hp": _committed_hp[id]}, true)
	if _committed_statuses.has(id):
		row = row.merged({"tactical_statuses": _committed_statuses[id]}, true)
	if _committed_shields.has(id):
		row = row.merged({"shield_away": _committed_shields[id] is Vector2i,
			"shield_cell": _committed_shields[id]}, true)
	# Recall itself does not recover the skeleton. Its authored tuck needs
	# a standing minion. Carry the prior prone pose across the paired cue,
	# then settle to the ordinary recovery (if any) without playing a stand.
	if not _prone_recalls.is_empty() and _prone_recalls.values().any(func(hold): return hold.id == id):
		row = row.merged({"prone": true}, true)
	return row


func _presentation_cell(unit: Dictionary) -> Vector2i:
	var id: String = unit.id
	var waiting: Variant = _playback.waiting_swap_cell(id)
	if waiting is Vector2i:
		return waiting
	if unit.get("cast_key") == "ferryman" or unit.has("cast_lifecycle") \
			or _playback.movement_source(id) is Vector2i or _playback.has_settled_position(id):
		return _playback.actor_cell(id, unit.cell)
	return unit.cell


func _figure_frame(active: Array[CastPlayback.Entry]) -> Dictionary:
	var actions := {}
	var occupants: Array = []
	var visual_units := {}
	for original: Dictionary in _presentation_units():
		if _playback.has_pending_reveal(original.id):
			continue
		visual_units[original.id] = original
		if original.get("playback_only", false) \
				and not _playback.has_pending_ordinary_role(str(original.id), "defeat") \
				and not _playback.has_pending_clip(str(original.id), "defeat"):
			continue
		var occupant := original
		var key := str(original.get("cast_key", ""))
		var id := str(original.get("id", ""))
		var ordinary_defeat := _ordinary_defeat_clip(original)
		var hero_defeat: Dictionary = _playback.pending_hero_defeat(id)
		var cell := _presentation_cell(original)
		if cell != original.cell:
			occupant = original.duplicate()
			occupant["cell"] = cell
			occupant.erase("cast_hold")
		if original.has("cast_lifecycle") and int(original.get("hp", 1)) > 0 \
				and bool(original.get("prone", false)) and _playback.has_waiting_upright_hit(id):
			if occupant == original:
				occupant = original.duplicate()
			occupant["prone"] = false
		if (original.get("visual_defeat", false) and not hero_defeat.is_empty()) \
				or (not ordinary_defeat.is_empty() and int(original.get("hp", 1)) <= 0 \
				and _playback.has_pending_ordinary_role(id, "defeat")) \
				or (not original.has("cast_lifecycle") and key == "harpooner" and int(original.get("hp", 1)) <= 0 \
				and _playback.has_pending_clip(id, "defeat")) \
				or (not original.has("cast_lifecycle") and key == "ferryman" and bool(original.get("prone", false)) \
				and _playback.has_pending_clip(id, "down")):
			# The final corpse row is authoritative, but its appearance belongs
			# after the complete committed action and defeat timeline.
			if occupant == original:
				occupant = original.duplicate()
			occupant["pre_defeat"] = true
			occupant["label"] = ""
			if not hero_defeat.is_empty():
				occupant["prone"] = bool(hero_defeat.get("was_prone", false))
		occupants.append(occupant)
	for entry in active:
		if entry.elapsed_ms >= entry.clip.total_ms:
			continue
		if entry.cue.get("silent_action", false):
			continue
		var id: String = entry.cue.unit_id
		if entry.cue.get("reveal_at_start", false) and not entry.presentation_impact_emitted:
			continue
		var unit: Dictionary = visual_units.get(id, {})
		if entry.cue.get("requires_existing_figure", false) \
				and (unit.is_empty() or int(unit.get("hp", 0)) <= 0):
			# A companion pose belongs to the actual living minion. In particular
			# a Play Dead tail must not recreate the zombie after its handoff.
			continue
		if not unit.is_empty():
			if str(unit.get("cast_key", "")) != entry.cue.cast_key:
				continue
			# The final board can include a later fall, or a fall caused by the
			# dose itself. Show this committed gesture before returning to it.
			var dose_gesture := _is_dose_gesture(entry)
			var ordinary_defeat := _ordinary_defeat_clip(unit)
			var before_ordinary_defeat := not ordinary_defeat.is_empty() \
				and _playback.has_pending_ordinary_role(id, "defeat")
			var ordinary_hit := _ordinary_hit_gesture(unit, entry)
			var ordinary_recover: bool = entry.cue.get("ordinary_presentation", false) \
				and entry.cue.get("ordinary_role") == "recover"
			var hero_reaction := _is_guild_reaction(entry)
			var hero_defeat: bool = entry.cue.get("hero_defeat", false)
			var before_hero_defeat: bool = unit.get("visual_defeat", false) \
				and not _playback.pending_hero_defeat(id).is_empty()
			var before_hero_down: bool = unit.get("guild_knockdown_art", false) \
				and _playback.hero_pending_pose(id) == "ready"
			var legacy_lifecycle := not unit.has("cast_lifecycle")
			var harpoon_reaction: bool = legacy_lifecycle and entry.cue.cast_key == "harpooner" \
				and entry.cue.clip in ["hit", "defeat"]
			var before_harpoon_defeat: bool = legacy_lifecycle and entry.cue.cast_key == "harpooner" \
				and _playback.has_pending_clip(id, "defeat")
			var ferryman_reaction: bool = legacy_lifecycle and entry.cue.cast_key == "ferryman" \
				and (entry.cue.clip in ["flinch", "down", "recover"] or _playback.has_pending_clip(id, "down"))
			if int(unit.get("hp", 1)) <= 0 and not dose_gesture and not harpoon_reaction \
					and not before_harpoon_defeat and not ferryman_reaction and not before_ordinary_defeat \
					and not before_hero_defeat and not hero_defeat:
				continue
			if bool(unit.get("prone", false)) and not _is_pull_gesture(entry) and not dose_gesture \
					and not harpoon_reaction and not before_harpoon_defeat and not ferryman_reaction \
					and not before_ordinary_defeat and not ordinary_hit and not ordinary_recover \
					and not hero_reaction and not before_hero_down and not hero_defeat and not before_hero_defeat:
				continue
			# A previous shield throw cannot remove a shield that has since been recovered.
			if not entry.cue.get("ordinary_presentation", false) and entry.cue.clip == "shield_away" \
					and not bool(unit.get("shield_away", false)):
				continue
		elif _is_guild_reaction(entry):
			# Living-only fall and recovery art must not recreate a removed hero.
			continue
		actions[id] = entry
		if unit.is_empty():
			var source: Variant = entry.cue.get("actor_cell", entry.cue.get("source_cell"))
			if source is Vector2i and _cells.has(source):
				# A unit that acted and fell can finish the cue without regaining HP or a label.
				occupants.append({"id": id, "cast_key": entry.cue.cast_key, "transient": true,
					"art_key": entry.cue.cast_key, "cell": source,
					"shield_away": entry.cue.get("shield_away", false)})
	for index in occupants.size():
		var occupant: Dictionary = occupants[index]
		var action: CastPlayback.Entry = actions.get(occupant.id)
		if action != null and _uses_action_cell(occupant, action) \
				and not _playback.has_settled_position(occupant.id):
			var cast_cell: Variant = action.cue.get("actor_cell", action.cue.get("source_cell"))
			if cast_cell is Vector2i and cast_cell != occupant.cell:
				occupant = occupant.duplicate()
				occupant["cell"] = cast_cell
				occupants[index] = occupant
	occupants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("visual_defeat", false)) != bool(b.get("visual_defeat", false)):
			return bool(a.get("visual_defeat", false))
		return _reading_order(a.cell, b.cell))
	return {"occupants": occupants, "actions": actions}


func _draw_figures() -> void:
	if _map_scale <= 0.0:
		return
	if _capture_actual_draw:
		_draw_frame_serial += 1
		_actual_draw = {"frame_serial": _draw_frame_serial, "presentation_ms": _presentation_ms,
			"actors": {}, "props": [], "marks": [], "recipients": [], "shields": []}
	_ink_canvas = _figures
	var active := _playback.active()
	var frame := _figure_frame(active)
	var occupants: Array = frame.occupants
	var actions: Dictionary = frame.actions
	var marked_units := occupants.filter(func(unit: Dictionary) -> bool:
		return _cells.has(unit.cell) and not unit.get("transient", false) and not unit.get("visual_defeat", false))
	for unit in occupants:
		if _cells.has(unit.cell):
			_draw_unit_shadow(unit)
	# Paint every nameplate before any figure so neighboring models can cover the text.
	for unit in marked_units:
		_draw_unit_nameplate(unit)
	for unit in occupants:
		if _cells.has(unit.cell):
			_draw_unit(unit, actions.get(unit.id))
	for entry in active:
		_draw_committed_feedback(entry)
	for mark in _recipient_marks:
		_at(_unit_foot(mark.cell))
		_draw_recipient_ink(mark.kind, (_presentation_ms - float(mark.at)) / CastPlayback.FEEDBACK_MS)
		if _capture_actual_draw:
			_actual_draw.recipients.append(mark)
	for unit in marked_units:
		_at(_tile_origin(unit.cell))
		var action: CastPlayback.Entry = actions.get(unit.id)
		var down := bool(unit.get("prone", false)) or int(unit.get("hp", 1)) <= 0
		if not unit.get("pre_defeat", false):
			_draw_health(unit, down and (action == null or (not _is_dose_gesture(action) \
				and not _ordinary_hit_gesture(unit, action))))
		_draw_unit_marker(unit)
	# Loose equipment is a tile marker, even when a unit occupies that tile.
	for cell in _overlay.get("forecast_shields", []):
		if _cells.has(cell):
			_at(_tile_origin(cell))
			_draw_shield_marker(true)
	for cell in _presentation_shields():
		if _cells.has(cell) and not _playback.shield_in_transit(cell):
			_at(_tile_origin(cell))
			_draw_shield_marker(false)
			if _capture_actual_draw:
				_actual_draw.shields.append(cell)
	_ink_canvas = self


func _presentation_shields() -> Array:
	var cells: Array = _overlay.get("shields", [])
	if _committed_shields.is_empty():
		return cells
	cells = cells.duplicate()
	for id in _committed_shields:
		cells.erase(_units_by_id.get(id, {}).get("shield_cell"))
		if _committed_shields[id] is Vector2i:
			cells.append(_committed_shields[id])
	return cells


static func _reading_order(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x if a.y == b.y else a.y < b.y


func _draw_water() -> void:
	_ink_canvas.draw_rect(Rect2(Vector2.ZERO, _map_size), RIVER)
	_rng.seed = 4602
	for y in range(6, int(_map_size.y) - 8, 14):
		for x in range(6, int(_map_size.x) - 8, 35):
			var p := Vector2(x + _rng.randf_range(-5, 5), y + _rng.randf_range(-4, 4))
			var length := minf(_rng.randf_range(11, 67), _map_size.x - p.x - 3)
			var pigment := Color("#688c81") if _rng.randf() > 0.38 else Color("#132f37")
			pigment.a = _rng.randf_range(0.08, 0.27)
			_wash(p, Vector2(length, _rng.randf_range(2, 7)), pigment)
			if _rng.randf() > 0.50:
				var q := p + Vector2(1, 3)
				var pale := Color(FOAM, _rng.randf_range(0.10, 0.24))
				_line([q, q + Vector2(length * 0.28, 0), q + Vector2(length * 0.64, 2),
					q + Vector2(length * 0.87, 1)], pale, _rng.randf_range(0.5, 1.4))
	for y in range(4, int(_map_size.y) - 5, 6):
		for x in range(4, int(_map_size.x) - 5, 9):
			var p := Vector2(x + _rng.randf_range(-3, 3), y + _rng.randf_range(-2, 2))
			_ink_canvas.draw_line(p, p + Vector2(_rng.randf_range(0.4, 2.8), 0), Color(FOAM, 0.085), 0.65)
	_ink_canvas.draw_rect(Rect2(Vector2(2, 2), _map_size - Vector2(4, 4)), Color("#7d906f"), false, 1.0)
	_ink_canvas.draw_rect(Rect2(Vector2(6, 6), _map_size - Vector2(12, 12)), Color("#182f32"), false, 1.0)
	for corner in [Vector2(9, 9), Vector2(_map_size.x - 9, 9),
			Vector2(9, _map_size.y - 9), _map_size - Vector2(9, 9)]:
		var p: Vector2 = corner
		_line([p + Vector2(-3, 0), p + Vector2(0, -3), p + Vector2(3, 0),
			p + Vector2(0, 3), p + Vector2(-3, 0)], Color("#98a47c"), 0.9)


func _draw_escapement(cell: Vector2i) -> void:
	var terrain := str(_cells[cell])
	if not _solid(terrain):
		return
	if not _solid(str(_cells.get(cell + Vector2i.DOWN, ""))):
		var edge := 74.0
		_piece([Vector2(0, edge), Vector2(94, edge), Vector2(96, 85), Vector2(88, 93),
			Vector2(68, 94), Vector2(59, 90), Vector2(37, 95), Vector2(24, 92),
			Vector2(12, 96), Vector2(1, 88)], Color("#534b3d"), Color("#263738"), 1.7)
		_line([Vector2(3, 85), Vector2(16, 88), Vector2(33, 85), Vector2(52, 88),
			Vector2(70, 84), Vector2(94, 85)], Color("#8a7559"), 1.3)
		for x in [11, 25, 40, 58, 70, 89]:
			_line([Vector2(x, 79), Vector2(x - 2, 84), Vector2(x + 1, 91)], Color("#323734"), 1.0)
		_line([Vector2(7, 99), Vector2(24, 96), Vector2(46, 99), Vector2(63, 95)], Color(FOAM, 0.33), 1.0)
		_line([Vector2(47, 103), Vector2(68, 99), Vector2(86, 99)], Color(FOAM, 0.21), 1.1)
	if not _solid(str(_cells.get(cell + Vector2i.RIGHT, ""))):
		_piece([Vector2(91, 0), Vector2(99, 5), Vector2(102, 21), Vector2(97, 40),
			Vector2(101, 62), Vector2(99, 76), Vector2(97, 88), Vector2(89, 81)],
			Color("#6a5d46"), Color("#263738"), 1.4)


func _draw_tile(cell: Vector2i) -> void:
	_rng.seed = hash(cell) + 991
	var terrain := str(_cells[cell])
	if terrain == "water":
		_draw_water_grid_marks()
		return
	if terrain == "broken":
		_draw_broken()
		return
	var base := STONE
	if terrain == "bridge":
		base = BRIDGE
	elif terrain == "safe" or terrain == "exit":
		base = SAFE
	var tile_tint := base.lerp(INK if _rng.randf() < 0.50 else PARCHMENT, _rng.randf_range(0.02, 0.13))
	if _grid_visible:
		_piece(TILE_FACE, tile_tint, Color("#514b3e"), 1.3)
		_line([Vector2(4, 7), Vector2(26, 4), Vector2(56, 5), Vector2(88, 4)], Color(PARCHMENT, 0.50), 1.4)
		_line([Vector2(5, 75), Vector2(34, 73), Vector2(62, 76), Vector2(88, 74)], Color(INK, 0.30), 1.3)
	else:
		# Keep the terrain tint while filling the inset gaps left by the grid.
		_ink_canvas.draw_rect(Rect2(Vector2.ZERO, TILE), tile_tint)
	for i in range(12):
		var p := Vector2(_rng.randf_range(5, 72), _rng.randf_range(7, 69))
		var tint := Color(PARCHMENT, _rng.randf_range(0.06, 0.20)) if i % 3 > 0 else Color(INK, 0.11)
		_wash(p, Vector2(_rng.randf_range(7, 18), _rng.randf_range(3, 10)), tint)
	for i in range(28):
		var p := Vector2(_rng.randf_range(6, 90), _rng.randf_range(5, 74))
		_ink_canvas.draw_line(p, p + Vector2(_rng.randf_range(0.4, 3.5), -0.5), Color(INK, 0.18), 0.8, true)
	match terrain:
		"safe", "exit":
			_draw_safe()
		"obstacle":
			_draw_obstacle()
		_:
			_draw_masonry(terrain == "bridge")


func _draw_water_grid_marks() -> void:
	# A mapped water cell has a faint survey mark; unmapped river has no tile.
	if not _grid_visible:
		return
	_line([Vector2(4, 15), Vector2(4, 4), Vector2(17, 4)], Color(FOAM, 0.39), 1.0)
	_line([Vector2(79, 76), Vector2(92, 76), Vector2(92, 65)], Color(FOAM, 0.39), 1.0)


func _draw_masonry(bridge: bool) -> void:
	var seam := Color(INK, 0.37)
	var c := _rng.randf_range(25, 47)
	_line([Vector2(1, c + 1), Vector2(22, c - 1), Vector2(49, c + 2), Vector2(72, c),
		Vector2(94, c + 1)], seam, 1.05)
	var split := _rng.randf_range(31, 63)
	_line([Vector2(split, 4), Vector2(split - 2, c - 13), Vector2(split + 2, c + 1)], seam, 1.0)
	_line([Vector2(72, c), Vector2(69, 66), Vector2(73, 75)], Color(INK, 0.22), 0.9)
	if not bridge:
		return
	_piece([Vector2(2, 5), Vector2(20, 2), Vector2(44, 4), Vector2(73, 2), Vector2(93, 4),
		Vector2(93, 11), Vector2(74, 12), Vector2(42, 11), Vector2(22, 13), Vector2(3, 12)],
		Color("#d4bd95"), Color("#766650"), 0.9)
	for x in [21, 44, 73]:
		_line([Vector2(x, 4), Vector2(x - 1, 11)], Color("#766650"), 1.0)
	_line([Vector2(94, 55), Vector2(82, 57), Vector2(76, 64), Vector2(65, 66),
		Vector2(60, 77)], Color("#645644"), 1.25)
	_line([Vector2(77, 62), Vector2(71, 54), Vector2(67, 53)], Color("#645644"), 0.9)


func _draw_broken() -> void:
	_draw_water_grid_marks()
	var chip := _rng.randf_range(-10, 13)
	_piece([Vector2(2, 3), Vector2(37 + chip, 3), Vector2(34 + chip, 10), Vector2(44 + chip, 15),
		Vector2(27, 19), Vector2(24, 31), Vector2(15, 32), Vector2(17, 46),
		Vector2(3, 49)], Color("#a08f74"), Color("#3c4238"), 1.4)
	_piece([Vector2(92, 27), Vector2(94, 75), Vector2(53 + chip * 0.5, 77), Vector2(59 + chip * 0.5, 68),
		Vector2(55, 63), Vector2(70, 58), Vector2(72, 51), Vector2(84, 48), Vector2(80, 41)],
		Color("#8f8069"), Color("#3c4238"), 1.4)
	_line([Vector2(4, 42), Vector2(13, 41), Vector2(12, 29), Vector2(23, 27),
		Vector2(27, 17), Vector2(38 + chip, 14)], Color(FOAM, 0.52), 1.8)
	_line([Vector2(58 + chip * 0.5, 76), Vector2(63 + chip * 0.5, 69), Vector2(61, 63), Vector2(73, 58),
		Vector2(75, 51), Vector2(88, 48)], Color("#dbc6a1"), 1.45)
	_line([Vector2(55, 55), Vector2(63, 51), Vector2(72, 45), Vector2(86, 43)], Color(FOAM, 0.30), 1.0)
	_piece([Vector2(32, 41 + chip), Vector2(38, 36 + chip), Vector2(49, 37 + chip),
		Vector2(46, 47 + chip), Vector2(36, 48 + chip)],
		Color("#698078"), Color("#344a45"), 1.0)
	if chip < 6.0:
		_piece([Vector2(62, 26), Vector2(69, 22), Vector2(74, 25), Vector2(71, 31), Vector2(65, 34)],
			Color("#6f8276"), Color("#344a45"), 1.0)


func _draw_safe() -> void:
	for i in range(12):
		var p := Vector2(_rng.randf_range(5, 65), _rng.randf_range(5, 62))
		_wash(p, Vector2(_rng.randf_range(8, 26), _rng.randf_range(5, 13)), Color("#65794f", 0.25))
	for i in range(10):
		var p := Vector2(_rng.randf_range(10, 86), _rng.randf_range(9, 65))
		_line([p + Vector2(-4, -3), p, p + Vector2(0, -6), p, p + Vector2(4, -4)],
			Color("#596747", 0.85), 0.85)
	_line([Vector2(7, 65), Vector2(26, 58), Vector2(48, 61), Vector2(67, 67), Vector2(89, 61)],
		Color("#d0c69a", 0.54), 2.4)


func _draw_exit() -> void:
	# Shuttered guide lantern and arrow are kept to the left of the unit silhouette.
	_ink_canvas.draw_circle(Vector2(17, 24), 13.0, Color(AMBER, 0.20), true, -1.0, true)
	_line([Vector2(13, 55), Vector2(12, 20), Vector2(16, 17), Vector2(24, 18)], INK, 3.1)
	_line([Vector2(13, 49), Vector2(13, 27)], Color("#a08a56"), 1.0)
	_piece([Vector2(18, 21), Vector2(25, 21), Vector2(24, 31), Vector2(19, 32)],
		Color("#f8cb66"), INK, 1.1)
	_line([Vector2(21, 22), Vector2(21, 30)], Color("#fff3b8"), 1.1)
	_piece([Vector2(5, 39), Vector2(22, 38), Vector2(27, 43), Vector2(22, 47), Vector2(5, 46)],
		Color("#554f3a"), INK, 1.0)
	_line([Vector2(9, 43), Vector2(21, 43), Vector2(18, 40), Vector2(21, 43), Vector2(18, 45)],
		PARCHMENT, 1.1)
	_caption("EXIT", Vector2(86, 70), MINT, 10)


func _draw_objective_square() -> void:
	# A continuous chalk square reads as part of the floor, not as tactical brackets.
	# Keep the side rules outside the figure's center and below every preview.
	_piece([Vector2(11, 11), Vector2(51, 10), Vector2(85, 11), Vector2(86, 42),
		Vector2(84, 69), Vector2(46, 70), Vector2(10, 69)], ZONE_WASH, ZONE_EDGE, 4.3)
	_line([Vector2(11, 11), Vector2(51, 10), Vector2(85, 11), Vector2(86, 42),
		Vector2(84, 69), Vector2(46, 70), Vector2(10, 69), Vector2(11, 11)], ZONE_CHALK, 1.7)
	for x in [15, 81]:
		_piece([Vector2(x - 3, 39), Vector2(x, 35), Vector2(x + 3, 39), Vector2(x, 43)],
			ZONE_CHALK, ZONE_EDGE, 1.2)


func _draw_obstacle() -> void:
	_wash(Vector2(14, 62), Vector2(69, 11), Color(INK, 0.38))
	_piece([Vector2(18, 30), Vector2(61, 28), Vector2(65, 60), Vector2(21, 63)],
		Color("#946746"), INK, 1.8)
	_piece([Vector2(61, 28), Vector2(79, 17), Vector2(80, 47), Vector2(65, 60)],
		Color("#6a4c34"), INK, 1.6)
	_piece([Vector2(18, 30), Vector2(37, 18), Vector2(79, 17), Vector2(61, 28)],
		Color("#c09862"), INK, 1.5)
	for y in [37, 46, 54]:
		_line([Vector2(20, y), Vector2(42, y - 2), Vector2(63, y - 3)], Color("#4c3b2e"), 1.15)
		_line([Vector2(63, y - 3), Vector2(79, y - 13)], Color("#4c3b2e"), 1.05)
	_piece([Vector2(21, 55), Vector2(53, 29), Vector2(61, 28), Vector2(64, 34),
		Vector2(29, 61), Vector2(22, 62)], Color("#b58a58"), INK, 1.3)
	_line([Vector2(32, 24), Vector2(54, 24), Vector2(70, 22)], Color("#684a32"), 1.0)
	_line([Vector2(40, 44), Vector2(43, 43), Vector2(47, 42)], Color("#e2b57f"), 1.05)
	_line([Vector2(71, 49), Vector2(76, 43), Vector2(69, 44), Vector2(75, 37)], Color("#3c3129"), 1.15)


func _draw_object_segment(art_key: String) -> void:
	match art_key:
		"obstacle", "crate":
			_draw_obstacle()
		"shield_wall":
			_draw_shield_marker(false, TILE * 0.5, 2.0)


static func _solid(terrain: String) -> bool:
	return terrain != "" and terrain != "water" and terrain != "broken"


func _draw_path(path: Array) -> void:
	for index in range(1, path.size()):
		if not _cells.has(path[index - 1]) or not _cells.has(path[index]):
			continue
		var a := _tile_origin(path[index - 1]) + TILE * 0.5
		var b := _tile_origin(path[index]) + TILE * 0.5
		_ink_canvas.draw_dashed_line(a, b, INK, 5.0, 7.0, true, true)
		_ink_canvas.draw_dashed_line(a, b, AMBER, 2.0, 7.0, true, true)
		var n := (b - a).normalized()
		var arrow := b - n * 18.0
		_piece([arrow + n * 5.0, arrow - n * 5.0 + n.orthogonal() * 5.0,
			arrow - n * 5.0 - n.orthogonal() * 5.0], AMBER, INK, 1.1)


func _draw_overlays(cell: Vector2i) -> void:
	var threatened: Array = _overlay.get("threat", [])
	var targets: Array = _overlay.get("targets", [])
	var impacts: Array = _overlay.get("impact", [])
	if cell in threatened:
		_brackets(CORAL, 9, 2.0)
		_line([Vector2(72, 17), Vector2(81, 9), Vector2(88, 17), Vector2(81, 25), Vector2(72, 17)], CORAL, 1.8)
	if cell in _overlay.get("forecast_obstacle_cells", []):
		_ink_canvas.draw_rect(Rect2(Vector2(13, 16), TILE - Vector2(26, 32)), Color(AMBER, 0.13))
		_brackets(AMBER, 12, 1.7)
	if cell in targets:
		if _overlay.get("quiet_manual_move", false):
			_ink_canvas.draw_circle(Vector2(50, 15), 3.0, MINT, true, -1.0, true)
		else:
			_brackets(MINT, 6, 2.0)
			_piece([Vector2(45, 15), Vector2(50, 10), Vector2(55, 15), Vector2(50, 20)], MINT, INK, 1.15)
	if _overlay.get("chosen_target", null) == cell:
		_brackets(MINT, 2, 2.8)
	if cell in impacts:
		_brackets(CORAL, 5, 2.3)
		_line([Vector2(74, 14), Vector2(83, 23)], INK, 4.2)
		_line([Vector2(83, 14), Vector2(74, 23)], INK, 4.2)
		_line([Vector2(74, 14), Vector2(83, 23)], CORAL, 2.0)
		_line([Vector2(83, 14), Vector2(74, 23)], CORAL, 2.0)
	if _overlay.get("selected", null) == cell:
		_brackets(AMBER, 2, 3.0)
	elif _hover == cell:
		_brackets(PARCHMENT, 3, 1.65)


func _brackets(color: Color, pad: float, weight: float) -> void:
	for corner in [Vector2(0, 0), Vector2(TILE.x, 0), TILE, Vector2(0, TILE.y)]:
		var direction := Vector2(1 if corner.x == 0 else -1, 1 if corner.y == 0 else -1)
		var p: Vector2 = corner + direction * pad
		var points := [p + Vector2(0, direction.y * 16), p, p + Vector2(direction.x * 19, 0)]
		_line(points, INK, weight + 2.5)
		_line(points, color, weight)


func _draw_shield_marker(forecast: bool, center := SHIELD_MARK_CENTER, marker_scale := 1.0) -> void:
	var shape := []
	for offset: Vector2 in [Vector2(-8, -8), Vector2(8, -8), Vector2(7, 1),
			Vector2(4, 6), Vector2(0, 9), Vector2(-4, 6), Vector2(-7, 1)]:
		shape.append(center + offset * marker_scale)
	var fill := INK if forecast else AMBER
	if forecast:
		_piece(shape, fill, INK, 5.0)
	_piece(shape, fill, AMBER if forecast else INK, 2.25)
	if not forecast:
		_ink_canvas.draw_circle(center - Vector2(0, marker_scale), 2.5 * marker_scale, INK, true, -1.0, true)


func _draw_coordinates() -> void:
	for column in range(_bounds.position.x, _bounds.end.x):
		var x := _tile_origin(Vector2i(column, _bounds.position.y)).x + TILE.x * 0.5
		_axis_mark(_column_name(column), Vector2(x, 25))
	for row in range(_bounds.position.y, _bounds.end.y):
		var y := _tile_origin(Vector2i(_bounds.position.x, row)).y + TILE.y * 0.5 + 4.0
		_axis_mark(str(row + 1) if row >= 0 else str(row), Vector2(17, y))


func _axis_mark(label: String, p: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_ink_canvas.draw_string(font, p - Vector2(width * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PARCHMENT)


func _caption(label: String, right_baseline: Vector2, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := right_baseline - Vector2(width, 0)
	_ink_canvas.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, INK)
	_ink_canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _unit_facing(unit: Dictionary) -> float:
	var role := str(unit.get("art_key", ""))
	var default_facing := -1 if role in ["enemy", "goblin", "hookhand", "bruiser"] else 1
	return -1.0 if float(unit.get("facing", default_facing)) < 0.0 else 1.0


func _unit_foot(cell: Vector2i) -> Vector2:
	return _tile_origin(cell) + FOOT


func _draw_unit_shadow(unit: Dictionary) -> void:
	_at(_visual_foot(unit))
	_wash(Vector2(-29, -1), Vector2(59, 9), Color("#24312a", 0.27))
	_wash(Vector2(-22, 0), Vector2(48, 5), Color("#222824", 0.40))
	if bool(unit.get("guarded", false)):
		_ink_canvas.draw_arc(Vector2(0, -1), 24, PI * 0.07, PI * 0.93, 20, AMBER, 2.0, true)


func _draw_unit(unit: Dictionary, action: CastPlayback.Entry) -> void:
	var role := str(unit.art_key)
	var prone := _figure_prone(unit)
	var foot := _visual_foot(unit)
	var facing := _unit_facing(unit)
	if _draw_cast(unit, foot, facing, prone, action):
		return
	if prone:
		_at(foot + Vector2(-28 * facing, -13), 1.43 * facing, Vector2(facing * 0.80, 0.80))
	else:
		_at(foot, 0.0, Vector2(facing * 0.90, 0.90))
	match role:
		"knight":
			_knight(not unit.get("shield_away", false))
		"healer":
			_healer()
		"wizard":
			_wizard()
		"ferryman":
			_ferryman()
		"skeleton", "zombie":
			_draw_summon(role)
		"goblin":
			_goblin()
		"hookhand":
			_hookhand()
		"bruiser":
			_bruiser()
		"village_troll":
			_village_troll()
		_:
			_enemy(str(unit.get("variant", "")))
	if _capture_actual_draw:
		_record_drawn_actor(unit, foot, facing, prone, "", null, -1)


func _visual_foot(unit: Dictionary) -> Vector2:
	var foot := _unit_foot(unit.cell)
	var id := str(unit.get("id", ""))
	var source: Variant = _playback.movement_source(id)
	var destination: Variant = _playback.movement_destination(id)
	if source is Vector2i and destination is Vector2i:
		foot = _unit_foot(source).lerp(_unit_foot(destination), _playback.movement_fraction(id))
	return foot


static func _figure_prone(unit: Dictionary) -> bool:
	return bool(unit.get("prone", false)) or (int(unit.get("hp", 1)) <= 0 \
		and not unit.get("pre_defeat", false))


func _draw_cast(unit: Dictionary, foot: Vector2, facing: float, prone: bool, action: CastPlayback.Entry) -> bool:
	var cast_key := str(unit.get("cast_key", ""))
	if cast_key.is_empty():
		return false
	var key := "ready"
	var time_ms := _ready_ms
	var turned_down := prone and not bool(unit.get("pre_defeat", false))
	var defeat_tail := _ordinary_defeat_tail(unit)
	var held := _cast.clip_for(cast_key, str(unit.get("cast_hold", "")))
	var pending_hero_pose := _playback.hero_pending_pose(str(unit.get("id", "")))
	var hero_hold := str(pending_hero_pose)
	if hero_hold.is_empty() and prone:
		var seated := _pull_facing.has(unit.id) or (bool(unit.get("pre_defeat", false)) \
			and _defeat_facing.has(unit.id))
		hero_hold = "seated" if seated and cast_key in ["wizard", "alchemist"] else "down"
	var hold_key := "pull" if hero_hold == "seated" else "down"
	if cast_key == "knight" and bool(unit.get("shield_away", false)):
		hold_key = "down_unshielded"
	var can_hold_hero := bool(unit.get("guild_knockdown_art", false)) \
		and (int(unit.get("hp", 1)) > 0 or bool(unit.get("pre_defeat", false))) \
		and action == null and not hero_hold.is_empty() \
		and (hero_hold == "ready" or _cast.clip_for(cast_key, hold_key) != null)
	if unit.get("inert_corpse", false):
		time_ms = 0.0 # A Bomber's defeat is an explosion, never a corpse pose.
	elif action != null and (_is_guild_reaction(action) or action.cue.get("hero_defeat", false)):
		key = action.cue.clip
		if cast_key == "knight" and bool(action.cue.get("shield_away", false)):
			key += "_unshielded"
		time_ms = action.elapsed_ms + action.sample_offset_ms
		turned_down = false
		facing = action.facing if action.facing != 0.0 else facing
	elif bool(unit.get("visual_defeat", false)) and not bool(unit.get("pre_defeat", false)):
		key = "defeat_unshielded" if cast_key == "knight" and bool(unit.get("shield_away", false)) else "defeat"
		time_ms = INF
		turned_down = false
		facing = _defeat_facing.get(unit.id, facing)
	elif can_hold_hero:
		if hero_hold == "ready":
			key = "shield_away" if cast_key == "knight" and bool(unit.get("shield_away", false)) else "ready"
		else:
			key = hold_key
			time_ms = INF
			if hero_hold == "seated":
				facing = _pull_facing.get(unit.id, _defeat_facing.get(unit.id, facing))
		turned_down = false
	elif not unit.has("cast_lifecycle") and cast_key == "knight" and bool(unit.get("shield_away", false)):
		# Equipment is authoritative. Never show a second shield on the unit.
		key = "shield_away"
		var unshielded := _knight_action_while_shield_away(action)
		if not unshielded.is_empty():
			key = unshielded
			time_ms = action.elapsed_ms
			turned_down = false
			facing = action.facing if action.facing != 0.0 else facing
	elif action != null and action.elapsed_ms < action.clip.total_ms:
		key = action.cue.clip
		time_ms = action.elapsed_ms
		turned_down = false
		facing = action.facing if action.facing != 0.0 else facing
	elif defeat_tail != null:
		key = defeat_tail.cue.clip
		time_ms = INF
		turned_down = false
		facing = defeat_tail.facing if defeat_tail.facing != 0.0 else facing
	elif not unit.has("cast_lifecycle") and cast_key in ["wizard", "alchemist"] and prone \
			and _pull_facing.has(unit.id):
		# Pull ends seated. Hold its authored stumble instead of rotating a standing pose.
		key = "pull"
		time_ms = INF
		turned_down = false
		facing = _pull_facing[unit.id]
	elif held != null and not bool(unit.get("pre_defeat", false)):
		key = unit.cast_hold
		time_ms = _ready_ms if held.loop else INF
		turned_down = false
	elif not _ordinary_defeat_clip(unit).is_empty() and int(unit.get("hp", 1)) <= 0 \
			and not bool(unit.get("pre_defeat", false)):
		key = _ordinary_defeat_clip(unit)
		time_ms = INF
		turned_down = false
	elif not unit.has("cast_lifecycle") and cast_key == "harpooner" \
			and int(unit.get("hp", 1)) <= 0 and not bool(unit.get("pre_defeat", false)):
		key = "defeat"
		time_ms = INF
		turned_down = false
	elif not unit.has("cast_lifecycle") and cast_key == "ferryman" \
			and (prone or (_playback.has_pending_clip(str(unit.get("id", "")), "recover") \
			and not _playback.has_pending_clip(str(unit.get("id", "")), "down"))) \
			and not bool(unit.get("pre_defeat", false)):
		key = "down"
		time_ms = INF
		turned_down = false
	elif prone and not bool(unit.get("pre_defeat", false)):
		time_ms = 0.0
	if key == "ready" and time_ms == _ready_ms:
		time_ms *= _ready_rates.get(str(unit.get("id", "")), 1.0)
	var clip := _cast.clip_for(cast_key, key)
	if clip == null and cast_key == "blacksmith" and unit.get("guild_knockdown_art", false):
		# Retain the stock hero's silhouette if a lifecycle take is missing.
		# The prone convention is only a fallback, never the authored defeat.
		key = "ready"
		clip = _cast.clip_for(cast_key, key)
		turned_down = prone and not unit.get("pre_defeat", false)
		time_ms = 0.0 if turned_down else _ready_ms * _ready_rates.get(unit.id, 1.0)
	if clip == null:
		return false
	if turned_down:
		_at(foot + Vector2(-28 * facing, -13), 1.43 * facing, Vector2(facing * 0.80, 0.80))
	else:
		_at(foot, 0.0, Vector2(facing, 1.0))
	var index := clip.frame_index(time_ms)
	var painted := _cast.paint(_ink_canvas, clip, index)
	if painted and _capture_actual_draw:
		_record_drawn_actor(unit, foot, facing, turned_down, key, clip, index)
	return painted


func _knight_action_while_shield_away(action: CastPlayback.Entry) -> String:
	if action == null or action.elapsed_ms >= action.clip.total_ms:
		return ""
	if action.is_shield_throw():
		return action.cue.clip # Keep the actual release take through recovery.
	var key: String = action.cue.clip
	if key in ["rescue_line", "bonk"]:
		key += "_unshielded"
	var compatible := key in ["rescue_line_unshielded", "bonk_unshielded",
		"keep_your_head_down_unshielded", "fitted_pull_unshielded", "safety_distance_unshielded"]
	return key if compatible and _cast.clip_for("knight", key) != null else ""


func _record_drawn_actor(unit: Dictionary, foot: Vector2, facing: float, turned_down: bool,
		key: String, clip: CastSprites.Clip, index: int) -> void:
	_actual_draw.actors[unit.id] = {"actor_id": unit.id, "cast_key": unit.get("cast_key", ""),
		"clip": key, "atlas": clip.path if clip != null else "", "frame_index": index,
		"source_frame": clip.source_frames[index] if clip != null else -1,
		"rect": clip.frames[index] if clip != null else Rect2(), "cell": unit.cell, "foot": foot,
		"facing": facing, "turned_down": turned_down, "shield_away": unit.get("shield_away", false)}


func _target_cell(id: String, at: Variant) -> Variant:
	return at if at is Vector2i else _targets_by_id.get(id)


func _ordinary_defeat_clip(unit: Dictionary) -> String:
	var lifecycle: Variant = unit.get("cast_lifecycle", {})
	var key: String = unit.get("cast_key", "")
	if lifecycle is Dictionary and lifecycle.get("defeat") is String:
		var clip: String = lifecycle.defeat
		if not clip.is_empty() and _cast.clip_for(key, clip) != null:
			return clip
	return ""


func _ordinary_hit_gesture(unit: Dictionary, entry: CastPlayback.Entry) -> bool:
	var lifecycle: Variant = unit.get("cast_lifecycle", {})
	return entry.cue.get("ordinary_presentation", false) and lifecycle is Dictionary \
		and entry.cue.get("ordinary_role") == "hit" and lifecycle.get("hit") == entry.cue.clip \
		and int(unit.get("hp", 1)) > 0


func _ordinary_defeat_tail(unit: Dictionary) -> CastPlayback.Entry:
	var clip := _ordinary_defeat_clip(unit)
	if clip.is_empty():
		return null
	for entry in _playback.active():
		if entry.cue.get("unit_id") == unit.get("id") and entry.cue.get("clip") == clip \
				and entry.cue.get("ordinary_presentation", false) and entry.cue.get("ordinary_role") == "defeat" \
				and entry.elapsed_ms >= entry.clip.total_ms:
			return entry
	return null


func _is_pull_gesture(entry: CastPlayback.Entry) -> bool:
	return not entry.cue.get("ordinary_presentation", false) \
		and ((entry.cue.cast_key in ["wizard", "alchemist"] and entry.cue.clip == "pull") \
		or (entry.cue.cast_key == "alchemist" and entry.cue.clip == "pull_upright"))


func _is_guild_reaction(entry: CastPlayback.Entry) -> bool:
	return not entry.cue.get("ordinary_presentation", false) \
		and entry.cue.get("hero_knockdown") in ["down", "recover", "seated_recover"]


func _is_dose_gesture(entry: CastPlayback.Entry) -> bool:
	return not entry.cue.get("ordinary_presentation", false) \
		and ((entry.cue.cast_key == "alchemist" and entry.cue.clip in ["potion", "acid", "etching_paste"]) \
		or (entry.cue.cast_key == "rogue" and entry.cue.clip == "potion"))


func _uses_action_cell(unit: Dictionary, entry: CastPlayback.Entry) -> bool:
	# The retained hero row is already at the death cell. Move only its
	# earlier gesture, not the defeat or the held pose that follows it.
	return entry.is_shield_throw() or entry.cue.get("requires_existing_figure", false) \
		or (unit.get("visual_defeat", false) and unit.get("cast_key") == entry.cue.cast_key \
			and not entry.cue.get("hero_defeat", false) \
			and not _playback.pending_hero_defeat(entry.cue.unit_id).is_empty())


func _sync_playback_geometry() -> void:
	for entry in _playback.active():
		var unit: Dictionary = _units_by_id.get(entry.cue.unit_id, {})
		if entry.cue.get("requires_existing_figure", false):
			for visible: Dictionary in _presentation_units():
				if visible.id == entry.cue.unit_id:
					unit = visible
					break
		var source: Variant = entry.cue.get("source_cell", entry.cue.get("actor_cell"))
		if not source is Vector2i:
			source = unit.get("cell")
		var target: Variant = _target_cell(entry.cue.target_id, entry.cue.get("target_cell"))
		if not source is Vector2i:
			continue
		if entry.facing == 0.0:
			entry.facing = _unit_facing(unit)
			if target is Vector2i and target.x != source.x:
				entry.facing = -1.0 if target.x < source.x else 1.0
		if _is_pull_gesture(entry) and bool(unit.get("prone", false)) and int(unit.get("hp", 1)) > 0 \
				and entry.cue.get("pull_recoil_down", false):
			_pull_facing[entry.cue.unit_id] = entry.facing
		if entry.gift == null or entry.gift_from != null or entry.flight_progress() < 0.0 \
				or not target is Vector2i:
			continue
		# Keep the launch on the rendered hand, including an earlier gesture
		# using its action cell rather than the retained hero's death cell.
		var hand_foot := _unit_foot(source)
		if _playback.movement_source(entry.cue.unit_id) is Vector2i:
			hand_foot = _visual_foot({"id": entry.cue.unit_id, "cell": source})
		var nudge := entry.clip.release_offset * Vector2(entry.facing, 1.0) * entry.clip.scale
		entry.gift_from = hand_foot + nudge
		var landing: Vector2i = entry.cue.get("shield_drop_cell", target)
		entry.gift_to = _tile_origin(landing) + SHIELD_MARK_CENTER if _is_lent_shield(entry) \
			else _unit_foot(landing) + Vector2(0, -29)
		if entry.gift.tip is Vector2:
			var tip_offset: Vector2 = (entry.gift.tip - entry.gift.anchor) * entry.gift.scale \
				* Vector2(entry.facing, 1.0)
			var path: Vector2 = entry.gift_to - entry.gift_from
			if not path.is_zero_approx() and not tip_offset.is_zero_approx():
				entry.gift_point_first = true
				entry.gift_angle = path.angle() - tip_offset.angle()
				entry.gift_to -= tip_offset.rotated(entry.gift_angle)


static func _is_lent_shield(entry: CastPlayback.Entry) -> bool:
	return entry.is_shield_throw() and entry.cue.get("performance", {}).get("form_id") == "lend_a_shield"


func _gift_position(entry: CastPlayback.Entry, flight: float) -> Vector2:
	var start: Vector2 = entry.gift_from
	var landing: Vector2 = entry.gift_to
	var height := 8.0 if _is_lent_shield(entry) else 24.0
	return start.lerp(landing, flight) - Vector2(0, sin(PI * flight) * height)


func _gift_rotation(entry: CastPlayback.Entry, flight: float) -> float:
	# An authored tip steers the detached artwork. The lent shield tips
	# forward on a low path rather than tumbling like the hostile throw.
	var turn := PI / 3.0 if _is_lent_shield(entry) else TAU
	return entry.gift_angle if entry.gift_point_first else entry.facing * flight * turn


func _gift_pose(entry: CastPlayback.Entry) -> Dictionary:
	var flight := entry.flight_progress()
	if entry.gift_from == null or flight < 0.0 or flight >= 1.0:
		return {}
	return {"position": _gift_position(entry, flight), "rotation": _gift_rotation(entry, flight),
		"frame": entry.gift.frame_index(entry.elapsed_ms - entry.clip.release_ms)}


func _draw_committed_feedback(entry: CastPlayback.Entry) -> void:
	var flight := entry.flight_progress()
	if entry.gift_from != null and flight >= 0.0 and flight < 1.0:
		var position := _gift_position(entry, flight)
		var rotation := _gift_rotation(entry, flight)
		var index := entry.gift.frame_index(entry.elapsed_ms - entry.clip.release_ms)
		_at(position, rotation, Vector2(entry.facing, 1.0))
		if _cast.paint(_ink_canvas, entry.gift, index) and _capture_actual_draw:
			_actual_draw.props.append({"actor_id": entry.cue.unit_id, "cast_key": entry.cue.cast_key,
				"clip": entry.clip.release_clip, "atlas": entry.gift.path, "frame_index": index,
				"source_frame": entry.gift.source_frames[index], "rect": entry.gift.frames[index],
				"position": position, "rotation": rotation, "target_cell": entry.cue.get("shield_drop_cell",
					entry.cue.get("target_cell"))})
	var progress := entry.progress()
	if progress < 0.0 or progress >= 1.0 or _uses_normalized_recipient_ink(entry.cue.get("performance", {})):
		return
	var recipients: Array = entry.cue.get("recipients", [{"id": entry.cue.target_id,
		"cell": entry.cue.get("target_cell"), "kind": entry.cue.get("kind", "")}])
	var marked := {}
	for recipient: Dictionary in recipients:
		var cell: Variant = _target_cell(str(recipient.get("id", "")), recipient.get("cell"))
		if cell is Vector2i and _cells.has(cell) and not marked.has(cell):
			marked[cell] = true
			_at(_tile_origin(cell) + FOOT)
			_draw_recipient_ink(str(recipient.get("kind", "")), progress)
			if _capture_actual_draw:
				_actual_draw.recipients.append({"cell": cell, "kind": recipient.get("kind", ""),
					"target_id": recipient.get("id", ""), "source_id": entry.cue.unit_id})


func _draw_recipient_ink(kind: String, progress: float) -> void:
	var color := PARCHMENT
	match kind:
		"hit", "damage":
			color = CORAL
		"heal":
			color = MINT
		"guard", "summon":
			color = AMBER
		"shift":
			color = ZONE_CHALK
	var opacity := 1.0 - progress * progress
	var reach := 4.0 + 8.0 * (1.0 - pow(1.0 - progress, 3.0))
	for side: float in [-1.0, 1.0]:
		var lower := Vector2(side * (24.0 + reach), -12)
		var upper := Vector2(side * (19.0 + reach), -26)
		_line([lower + Vector2(side * 9, 2), lower], Color(INK, opacity * 0.75), 5.0)
		_line([upper + Vector2(side * 5, -6), upper], Color(INK, opacity * 0.75), 5.0)
		_line([lower + Vector2(side * 9, 2), lower], Color(color, opacity), 2.3)
		_line([upper + Vector2(side * 5, -6), upper], Color(color, opacity), 2.3)
		if kind == "heal":
			var center := Vector2(side * (25.0 + reach), -33)
			_line([center - Vector2(4, 0), center + Vector2(4, 0)], Color(color, opacity), 1.7)
			_line([center - Vector2(0, 4), center + Vector2(0, 4)], Color(color, opacity), 1.7)


func _draw_summon(role: String) -> void:
	var texture: Texture2D = _summon_textures.get(role)
	if texture != null:
		var pivot: Vector2 = SUMMON_SPRITES[role].pivot
		var rect := Rect2(-pivot * SUMMON_TEXTURE_SCALE, texture.get_size() * SUMMON_TEXTURE_SCALE)
		_ink_canvas.draw_texture_rect(texture, rect, false)


func _draw_unit_nameplate(unit: Dictionary) -> void:
	if not _nameplates_visible:
		return
	var label: String = unit.get("label", "")
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	# Small identification labels distinguish recruits sharing a provisional drawing.
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	if width > 86.0:
		label = label.get_slice(" ", 0)
		if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > 86.0:
			label = label.left(8) + "…"
		width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_at(_tile_origin(unit.cell))
	# Give the tactical caption the line nearest the figure when both are present.
	var baseline := 89.0 if unit.has("pursuit_target") else 78.0
	_caption(label, Vector2(49.0 + width * 0.5, baseline),
		Color.from_string(unit.get("color", ""), PARCHMENT), 13)


func _draw_unit_marker(unit: Dictionary) -> void:
	_at(_tile_origin(unit.cell))
	if int(unit.get("hp", 0)) > 0:
		var statuses: Dictionary = unit.get("tactical_statuses", {})
		if COVER_STATUSES.any(func(id): return statuses.has(id)):
			_caption("COVER", Vector2(42, 12), AMBER, 10)
			if _capture_actual_draw:
				_actual_draw.marks.append({"kind": "cover", "target_id": unit.id, "cell": unit.cell})
		if statuses.has("inspired"):
			_caption("INSPIRED", Vector2(57, 23), MINT, 10)
			if _capture_actual_draw:
				_actual_draw.marks.append({"kind": "inspired", "target_id": unit.id, "cell": unit.cell})
		_draw_pursuit_target(unit)
	if _overlay.get("commanded") == unit.cell:
		if _overlay.get("quiet_manual_move", false):
			_ink_canvas.draw_circle(Vector2(85, 13), 3.0, AMBER, true, -1.0, true)
		else:
			_caption("CMD", Vector2(90, 17), AMBER, 11)


func _draw_pursuit_target(unit: Dictionary) -> void:
	var target: Dictionary = unit.get("pursuit_target", {})
	if target.is_empty():
		return
	var caption := "After: %s" % target.label
	var font := ThemeDB.fallback_font
	var font_size := 14
	var max_width := TILE.x - 10.0
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while width > max_width and font_size > 12:
		font_size -= 1
		width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if width > max_width:
		var shortened := caption
		while width > max_width:
			shortened = shortened.left(-1)
			caption = shortened + "…"
			width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_caption(caption, Vector2((TILE.x + width) * 0.5, 74), CORAL, font_size)
	if _capture_actual_draw:
		_actual_draw.marks.append({"kind": "pursuit_target", "unit_id": unit.id,
			"target_id": target.id, "text": caption, "cell": unit.cell})


func _draw_health(unit: Dictionary, prone: bool, character := true) -> void:
	var maximum := maxi(0, int(unit.get("max_hp", 0)))
	var hp := clampi(int(unit.get("hp", maximum)), 0, maximum)
	if maximum > 0 and character and (_always_show_health_bar or hp < maximum):
		var top := Vector2(79, 34)
		var length := 27.0
		var inner := 3.0
		var filled := length * float(hp) / maximum
		var fill := CORAL if hp < maximum and hp * 2 <= maximum else (AMBER if unit.get("objective", false) else MINT)
		_ink_canvas.draw_rect(Rect2(top - Vector2(2, 2), Vector2(inner + 4, length + 4)), INK)
		_ink_canvas.draw_rect(Rect2(top, Vector2(inner, length)), Color("#725344"))
		_ink_canvas.draw_rect(Rect2(top + Vector2(0, length - filled), Vector2(inner, filled)), fill)
		if maximum < 9:
			for index in range(1, maximum):
				var y := top.y + length * float(index) / maximum
				_ink_canvas.draw_line(Vector2(top.x, y), Vector2(top.x + inner, y), INK, 1.0)
	elif maximum > 0 and not character:
		var width := 27.0
		var top := Vector2(49 - width * 0.5, 63 if not unit.get("label", "").is_empty() else 69)
		_ink_canvas.draw_rect(Rect2(top - Vector2(2, 2), Vector2(width + 4, 7)), INK)
		_ink_canvas.draw_rect(Rect2(top, Vector2(width, 3)), Color("#725344"))
		var fill := CORAL if hp < maximum and hp * 2 <= maximum else (AMBER if unit.get("objective", false) else MINT)
		_ink_canvas.draw_rect(Rect2(top, Vector2(width * float(hp) / maximum, 3)), fill)
		if maximum < 9:
			for index in range(1, maximum):
				var x := top.x + width * float(index) / maximum
				_ink_canvas.draw_line(Vector2(x, top.y), Vector2(x, top.y + 3), INK, 1.0)
	var condition := _condition_caption(unit, prone)
	if not condition.is_empty():
		_caption(condition, Vector2(85, 19), CORAL, 11)
		if _capture_actual_draw and character:
			_actual_draw.marks.append({"kind": condition.to_lower(),
				"target_id": unit.id, "cell": unit.cell})


static func _condition_caption(unit: Dictionary, prone: bool) -> String:
	if not prone or unit.get("play_dead_corpse", false):
		return ""
	return "FALLEN" if int(unit.get("hp", unit.get("max_hp", 0))) <= 0 else "DOWN"


func _knight(with_shield: bool) -> void:
	var steel := Color("#969b8e")
	var light := Color("#d1c39e")
	var blue := Color("#4f6b70")
	var brass := Color("#c3a265")
	_piece([Vector2(-14, -47), Vector2(-24, -39), Vector2(-28, -14), Vector2(-33, -7),
		Vector2(-20, -7), Vector2(-13, -12), Vector2(-6, -28)], blue, INK, 1.8)
	_line([Vector2(-22, -34), Vector2(-24, -19), Vector2(-28, -11)], Color("#788684"), 1.3)
	_piece([Vector2(-16, -27), Vector2(-3, -25), Vector2(-4, -14), Vector2(-11, -5),
		Vector2(-6, -3), Vector2(-7, 1), Vector2(-23, 1), Vector2(-23, -4), Vector2(-18, -12)],
		steel, INK, 1.8)
	_piece([Vector2(-1, -25), Vector2(11, -27), Vector2(12, -15), Vector2(8, -9), Vector2(9, -4),
		Vector2(17, -2), Vector2(16, 2), Vector2(2, 2), Vector2(-1, -1)], Color("#74776f"), INK, 1.8)
	_line([Vector2(-21, -4), Vector2(-14, -5), Vector2(-12, -10), Vector2(-17, -11)], light, 1.4)
	_piece([Vector2(-13, -43), Vector2(4, -48), Vector2(13, -41), Vector2(12, -24),
		Vector2(1, -17), Vector2(-14, -24), Vector2(-18, -34)], steel, INK, 1.8)
	_line([Vector2(-10, -30), Vector2(-4, -26), Vector2(4, -25)], Color("#58594f"), 1.4)
	_piece([Vector2(-24, -39), Vector2(-22, -48), Vector2(-16, -51), Vector2(-8, -48),
		Vector2(-3, -40), Vector2(-7, -32), Vector2(-20, -34)], light, INK, 1.7)
	_line([Vector2(-22, -40), Vector2(-17, -44), Vector2(-11, -42), Vector2(-8, -37)], Color("#77796c"), 1.4)
	_piece([Vector2(-9, -51), Vector2(-12, -58), Vector2(-9, -64), Vector2(-3, -65), Vector2(4, -62),
		Vector2(6, -56), Vector2(9, -53), Vector2(6, -49), Vector2(2, -45), Vector2(-4, -47)],
		Color("#cb9c70"), INK, 1.45)
	_piece([Vector2(-12, -54), Vector2(-15, -62), Vector2(-11, -68), Vector2(-4, -70), Vector2(5, -67),
		Vector2(8, -60), Vector2(3, -58), Vector2(-3, -60), Vector2(-8, -55)], steel, INK, 1.6)
	_line([Vector2(-12, -63), Vector2(-5, -66), Vector2(3, -64)], light, 1.3)
	_line([Vector2(-1, -56), Vector2(3, -57), Vector2(5, -55)], INK, 1.15)
	_ink_canvas.draw_circle(Vector2(3, -54), 0.9, INK, true, -1.0, true)
	_line([Vector2(0, -49), Vector2(3, -51), Vector2(5, -50)], INK, 1.0)
	if not with_shield:
		_piece([Vector2(7, -43), Vector2(15, -43), Vector2(19, -33), Vector2(18, -25),
			Vector2(22, -20), Vector2(20, -16), Vector2(14, -15), Vector2(10, -24), Vector2(8, -32)],
			steel, INK, 1.7)
		_line([Vector2(14, -23), Vector2(18, -24)], light, 1.2)
		return
	_piece([Vector2(2, -48), Vector2(15, -50), Vector2(30, -43), Vector2(27, -27),
		Vector2(24, -17), Vector2(14, -9), Vector2(4, -16), Vector2(-2, -26), Vector2(-4, -40)],
		brass, INK, 2.1)
	_piece([Vector2(3, -43), Vector2(14, -46), Vector2(26, -41), Vector2(23, -25), Vector2(19, -17),
		Vector2(14, -13), Vector2(6, -19), Vector2(1, -29), Vector2(0, -39)], blue, Color("#6b644a"), 1.0)
	_line([Vector2(4, -40), Vector2(12, -43), Vector2(21, -40)], Color("#e0c593"), 1.2)
	_line([Vector2(14, -19), Vector2(13, -35), Vector2(14, -39)], brass, 1.5)
	_piece([Vector2(13, -31), Vector2(7, -35), Vector2(9, -28), Vector2(14, -25), Vector2(21, -32),
		Vector2(22, -36), Vector2(17, -34)], brass)
	_line([Vector2(29, -40), Vector2(25, -36), Vector2(25, -32)], Color("#e6c99b"), 1.1)
	for point in [Vector2(2, -45), Vector2(26, -42), Vector2(12, -13), Vector2(2, -22)]:
		_ink_canvas.draw_circle(point, 1.0, light, true, -1.0, true)


func _healer() -> void:
	var flax := Color("#dfc69a")
	var rose := Color("#a75a48")
	var moss := Color("#66715a")
	var leather := Color("#99704d")
	_piece([Vector2(-15, -25), Vector2(2, -26), Vector2(13, -17), Vector2(8, -7), Vector2(16, -4),
		Vector2(16, 1), Vector2(1, 1), Vector2(-3, -4), Vector2(-2, -14), Vector2(-8, -12),
		Vector2(-11, -3), Vector2(-17, 1), Vector2(-28, 0), Vector2(-27, -4), Vector2(-20, -8)],
		Color("#575446"), INK, 1.7)
	_piece([Vector2(-13, -47), Vector2(-25, -39), Vector2(-24, -28), Vector2(-20, -16), Vector2(-21, -9),
		Vector2(-14, -11), Vector2(-7, -8), Vector2(-3, -12), Vector2(11, -10), Vector2(17, -14),
		Vector2(15, -32), Vector2(13, -43), Vector2(4, -48)], flax, INK, 1.8)
	_piece([Vector2(-17, -38), Vector2(-21, -27), Vector2(-17, -20), Vector2(-18, -11), Vector2(-12, -14),
		Vector2(-10, -36)], Color("#b29971"))
	_piece([Vector2(2, -42), Vector2(11, -39), Vector2(13, -20), Vector2(8, -11), Vector2(-2, -13),
		Vector2(-5, -20), Vector2(-3, -30)], moss, INK, 1.1)
	_line([Vector2(-18, -42), Vector2(-10, -38), Vector2(0, -30), Vector2(7, -17)], Color("#745032"), 3.2)
	_line([Vector2(-17, -42), Vector2(-10, -38), Vector2(1, -30), Vector2(6, -20)], Color("#d7ad6d"), 0.85)
	_piece([Vector2(-15, -52), Vector2(-22, -57), Vector2(-22, -63), Vector2(-16, -66),
		Vector2(-11, -64), Vector2(-7, -59), Vector2(-9, -51)], Color("#3e312a"), INK, 1.4)
	_piece([Vector2(-15, -56), Vector2(-12, -63), Vector2(-4, -66), Vector2(4, -63), Vector2(8, -57),
		Vector2(10, -54), Vector2(6, -51), Vector2(3, -46), Vector2(-4, -47), Vector2(-12, -50)],
		Color("#d1a075"), INK, 1.65)
	_piece([Vector2(-15, -52), Vector2(-18, -60), Vector2(-14, -67), Vector2(-6, -69),
		Vector2(3, -67), Vector2(8, -61), Vector2(2, -61), Vector2(-3, -63), Vector2(-8, -57),
		Vector2(-11, -50)], Color("#43362c"), INK, 1.1)
	_line([Vector2(-14, -62), Vector2(-10, -66), Vector2(-4, -67)], Color("#a27451"), 1.0)
	_line([Vector2(1, -57), Vector2(5, -56)], INK, 1.25)
	_line([Vector2(0, -51), Vector2(4, -51)], Color("#663d2b"), 0.95)
	_piece([Vector2(7, -43), Vector2(12, -43), Vector2(17, -37), Vector2(27, -40), Vector2(30, -36),
		Vector2(19, -28), Vector2(12, -29), Vector2(6, -35)], flax, INK, 1.5)
	_piece([Vector2(25, -39), Vector2(30, -44), Vector2(35, -42), Vector2(35, -37), Vector2(29, -33)],
		Color("#e9d7ae"), INK, 1.15)
	_line([Vector2(30, -42), Vector2(33, -37)], Color("#8c7558"), 0.85)
	_piece([Vector2(-22, -27), Vector2(-5, -30), Vector2(3, -25), Vector2(2, -14),
		Vector2(-2, -8), Vector2(-18, -8), Vector2(-25, -14)], leather, INK, 1.8)
	_piece([Vector2(-24, -28), Vector2(-6, -30), Vector2(3, -25), Vector2(-1, -18), Vector2(-23, -18)],
		Color("#ead2a4"), INK, 1.15)
	_line([Vector2(-12, -27), Vector2(-12, -20)], rose, 2.4)
	_line([Vector2(-16, -24), Vector2(-8, -24)], rose, 2.4)
	_line([Vector2(-21, -14), Vector2(-17, -11), Vector2(-7, -11)], Color("#d2a775"), 1.0)


func _wizard() -> void:
	var plum := Color("#74586c")
	var plum_light := Color("#9a7582")
	var auburn := Color("#af643f")
	var gold := Color("#d4a759")
	_piece([Vector2(-16, -30), Vector2(5, -33), Vector2(11, -20), Vector2(10, -7), Vector2(18, -5),
		Vector2(17, 0), Vector2(4, 2), Vector2(0, -4), Vector2(0, -16), Vector2(-8, -17),
		Vector2(-13, -4), Vector2(-16, 1), Vector2(-28, 0), Vector2(-29, -4), Vector2(-21, -8)],
		Color("#554433"), INK, 1.5)
	_piece([Vector2(-11, -44), Vector2(-19, -43), Vector2(-24, -31), Vector2(-20, -20), Vector2(-28, -8),
		Vector2(-17, -9), Vector2(-13, -13), Vector2(-5, -10), Vector2(0, -12), Vector2(9, -11),
		Vector2(17, -14), Vector2(13, -21), Vector2(10, -36), Vector2(3, -45)], plum, INK, 1.9)
	_line([Vector2(-13, -39), Vector2(-13, -30), Vector2(-12, -25), Vector2(-16, -16)], plum_light, 1.6)
	_line([Vector2(2, -36), Vector2(2, -27), Vector2(7, -17)], Color("#4a3c48"), 1.15)
	_piece([Vector2(-14, -53), Vector2(-20, -47), Vector2(-17, -43), Vector2(-22, -41), Vector2(-16, -38),
		Vector2(-7, -41), Vector2(-5, -38), Vector2(3, -44), Vector2(8, -48), Vector2(7, -54)],
		auburn, INK, 1.5)
	_piece([Vector2(-6, -56), Vector2(1, -59), Vector2(8, -55), Vector2(9, -51), Vector2(12, -49),
		Vector2(8, -46), Vector2(6, -42), Vector2(1, -43), Vector2(-6, -47)], Color("#e6b586"), INK, 1.3)
	_line([Vector2(2, -48), Vector2(5, -46), Vector2(8, -47)], Color("#5f3b34"), 1.1)
	_ink_canvas.draw_arc(Vector2(6, -52), 3.0, 0, TAU, 12, INK, 1.1, true)
	_ink_canvas.draw_arc(Vector2(-1, -52), 2.4, 0, TAU, 12, INK, 1.0, true)
	_ink_canvas.draw_circle(Vector2(7, -52), 0.75, INK, true, -1.0, true)
	_piece([Vector2(-24, -52), Vector2(-28, -55), Vector2(-23, -59), Vector2(-17, -61),
		Vector2(-16, -67), Vector2(-21, -73), Vector2(-28, -70), Vector2(-26, -77),
		Vector2(-19, -80), Vector2(-11, -77), Vector2(0, -64), Vector2(12, -67),
		Vector2(21, -64), Vector2(20, -60), Vector2(12, -57), Vector2(-6, -53), Vector2(-15, -50)],
		plum, INK, 1.8)
	_line([Vector2(-26, -54), Vector2(-15, -55), Vector2(-1, -58), Vector2(18, -62)], plum_light, 1.5)
	_line([Vector2(-17, -62), Vector2(-11, -61), Vector2(-1, -65)], gold, 2.6)
	_line([Vector2(-26, -74), Vector2(-20, -77), Vector2(-13, -75)], Color("#bd917f"), 1.2)
	_piece([Vector2(4, -40), Vector2(10, -43), Vector2(14, -39), Vector2(20, -42), Vector2(21, -49),
		Vector2(26, -50), Vector2(29, -44), Vector2(29, -38), Vector2(20, -31), Vector2(12, -32)],
		plum_light, INK, 1.45)
	_piece([Vector2(22, -48), Vector2(19, -53), Vector2(20, -56), Vector2(24, -54), Vector2(27, -59),
		Vector2(29, -58), Vector2(28, -54), Vector2(32, -57), Vector2(34, -55), Vector2(28, -48)],
		Color("#e6b586"), INK, 1.0)
	_piece([Vector2(-14, -36), Vector2(4, -39), Vector2(11, -29), Vector2(9, -20), Vector2(-9, -20),
		Vector2(-16, -26)], Color("#935e47"), INK, 1.5)
	_line([Vector2(-12, -36), Vector2(-7, -30), Vector2(-8, -22), Vector2(8, -23)], Color("#ddc29a"), 1.35)
	_line([Vector2(-9, -32), Vector2(-1, -34), Vector2(6, -31)], gold, 1.1)
	# A tight, crooked spark rather than a large effect that could look like a preview.
	_line([Vector2(32, -60), Vector2(38, -62), Vector2(37, -68), Vector2(34, -69),
		Vector2(31, -66), Vector2(34, -65)], Color("#f2cb78"), 1.5)


func _ferryman() -> void:
	var ochre := Color("#c89956")
	var dull_gold := Color("#8b673f")
	var linen := Color("#d7c4a2")
	_line([Vector2(-28, -8), Vector2(-33, -38), Vector2(-37, -60)], INK, 4.0)
	_line([Vector2(-28, -8), Vector2(-33, -38), Vector2(-37, -60)], Color("#a17b51"), 1.85)
	_piece([Vector2(-37, -57), Vector2(-40, -61), Vector2(-43, -71), Vector2(-41, -75),
		Vector2(-36, -73), Vector2(-34, -65), Vector2(-35, -58)], Color("#b79a68"), INK, 1.2)
	_piece([Vector2(-11, -23), Vector2(7, -24), Vector2(13, -15), Vector2(10, -6), Vector2(18, -3),
		Vector2(18, 1), Vector2(3, 2), Vector2(-1, -2), Vector2(-2, -12), Vector2(-8, -9),
		Vector2(-12, 1), Vector2(-26, 0), Vector2(-28, -4), Vector2(-20, -8)], Color("#5e5948"), INK, 1.6)
	_piece([Vector2(-12, -49), Vector2(1, -48), Vector2(12, -42), Vector2(17, -32),
		Vector2(13, -19), Vector2(8, -16), Vector2(-6, -13), Vector2(-19, -19), Vector2(-22, -31),
		Vector2(-31, -32), Vector2(-33, -41), Vector2(-26, -45), Vector2(-20, -40)], ochre, INK, 1.8)
	_piece([Vector2(-6, -46), Vector2(3, -43), Vector2(7, -35), Vector2(3, -16), Vector2(-6, -14),
		Vector2(-8, -28), Vector2(-8, -35)], dull_gold, Color("#685039"), 1.05)
	_line([Vector2(-18, -34), Vector2(-16, -29), Vector2(-18, -26), Vector2(-14, -19)], Color("#efd198"), 1.2)
	_line([Vector2(-16, -22), Vector2(-4, -24), Vector2(8, -25), Vector2(14, -23)], Color("#584634"), 2.1)
	_piece([Vector2(-6, -56), Vector2(-2, -61), Vector2(8, -60), Vector2(13, -55), Vector2(12, -51),
		Vector2(16, -48), Vector2(12, -46), Vector2(10, -41), Vector2(1, -42), Vector2(-4, -48)],
		Color("#c69c73"), INK, 1.4)
	_piece([Vector2(-5, -49), Vector2(0, -50), Vector2(3, -45), Vector2(9, -47), Vector2(13, -46),
		Vector2(11, -40), Vector2(5, -36), Vector2(-1, -40)], linen, INK, 1.15)
	_line([Vector2(7, -53), Vector2(11, -52)], INK, 1.1)
	_line([Vector2(3, -43), Vector2(5, -40), Vector2(7, -43)], Color("#8f7d65"), 0.95)
	_piece([Vector2(-11, -55), Vector2(-8, -58), Vector2(-5, -65), Vector2(1, -69), Vector2(10, -65),
		Vector2(13, -58), Vector2(20, -55), Vector2(18, -52), Vector2(8, -54), Vector2(0, -52),
		Vector2(-8, -51)], dull_gold, INK, 1.6)
	_line([Vector2(-8, -56), Vector2(-2, -56), Vector2(7, -58), Vector2(14, -55)], Color("#e0b777"), 1.35)
	_line([Vector2(11, -29), Vector2(17, -25), Vector2(21, -26), Vector2(23, -23), Vector2(18, -20),
		Vector2(8, -23)], INK, 1.35)
	_line([Vector2(-29, -41), Vector2(-33, -44), Vector2(-35, -41), Vector2(-34, -36)],
		linen, 2.3)


func _enemy(variant: String) -> void:
	var rust := Color("#a55447")
	var hide := Color("#826a50")
	var cowl := Color("#495750")
	var iron := Color("#a4a69a")
	var long_reach := variant == "spear" or variant == "rear"
	if long_reach:
		_line([Vector2(-28, -3), Vector2(35, -59)], INK, 4.1)
		_line([Vector2(-28, -3), Vector2(35, -59)], Color("#bea16c"), 1.8)
		_piece([Vector2(31, -57), Vector2(36, -70), Vector2(47, -74), Vector2(42, -63)],
			iron, INK, 1.4)
	else:
		_piece([Vector2(19, -29), Vector2(23, -47), Vector2(32, -53), Vector2(40, -50), Vector2(40, -42),
			Vector2(32, -39), Vector2(24, -26)], iron, INK, 1.65)
		_line([Vector2(28, -45), Vector2(33, -50), Vector2(38, -48)], Color("#ded1aa"), 1.1)
	_piece([Vector2(-17, -27), Vector2(6, -27), Vector2(15, -15), Vector2(14, -8), Vector2(22, -3),
		Vector2(21, 0), Vector2(7, 1), Vector2(4, -3), Vector2(3, -12), Vector2(-7, -15), Vector2(-13, -7),
		Vector2(-12, -2), Vector2(-19, 2), Vector2(-29, 1), Vector2(-29, -3), Vector2(-22, -8)],
		hide, INK, 1.8)
	_piece([Vector2(-16, -48), Vector2(-24, -42), Vector2(-25, -32), Vector2(-18, -27), Vector2(-14, -19),
		Vector2(-1, -17), Vector2(10, -23), Vector2(12, -29), Vector2(23, -28), Vector2(27, -34),
		Vector2(23, -39), Vector2(13, -37), Vector2(8, -48), Vector2(-4, -52)], cowl, INK, 1.9)
	_piece([Vector2(-24, -40), Vector2(-21, -37), Vector2(-26, -32), Vector2(-32, -24), Vector2(-26, -25),
		Vector2(-27, -18), Vector2(-15, -26), Vector2(-12, -33), Vector2(7, -37), Vector2(9, -43),
		Vector2(-2, -45), Vector2(-15, -45)], rust, INK, 1.3)
	_line([Vector2(-27, -29), Vector2(-20, -33), Vector2(-13, -35)], Color("#d48365"), 1.1)
	_piece([Vector2(-12, -49), Vector2(-16, -57), Vector2(-13, -62), Vector2(-5, -66), Vector2(5, -65),
		Vector2(12, -59), Vector2(15, -52), Vector2(11, -49), Vector2(11, -43), Vector2(6, -39),
		Vector2(-4, -42)], cowl, INK, 1.85)
	_line([Vector2(-13, -57), Vector2(-9, -61), Vector2(-2, -63), Vector2(7, -61)], Color("#809283"), 1.4)
	_piece([Vector2(1, -55), Vector2(10, -56), Vector2(12, -51), Vector2(10, -48),
		Vector2(9, -44), Vector2(3, -45), Vector2(-1, -48)], Color("#8e966d"), INK, 1.1)
	_line([Vector2(4, -52), Vector2(9, -53)], Color("#f1d79b"), 1.3)
	_line([Vector2(6, -48), Vector2(10, -48)], INK, 1.0)
	_piece([Vector2(-20, -29), Vector2(-24, -24), Vector2(-20, -18), Vector2(-14, -19),
		Vector2(-11, -26), Vector2(-15, -30)], hide, INK, 1.2)
	_line([Vector2(21, -36), Vector2(23, -31), Vector2(25, -32)], Color("#c6ae82"), 1.55)


func _goblin() -> void:
	var olive := Color("#a1ac68")
	var shadow := Color("#6d784b")
	var leather := Color("#704f3b")
	# Sprung knees, a torn tunic and two outsized ears make a small zigzag silhouette.
	_piece([Vector2(-8, -25), Vector2(8, -23), Vector2(19, -15), Vector2(16, -7),
		Vector2(24, -4), Vector2(23, 0), Vector2(10, 0), Vector2(9, -12), Vector2(1, -13),
		Vector2(-11, -8), Vector2(-16, -3), Vector2(-16, 1), Vector2(-28, 1), Vector2(-27, -4),
		Vector2(-21, -7), Vector2(-15, -17)], leather, INK, 1.7)
	_piece([Vector2(-9, -36), Vector2(0, -36), Vector2(7, -32), Vector2(8, -23),
		Vector2(12, -15), Vector2(2, -16), Vector2(-2, -12), Vector2(-10, -17),
		Vector2(-19, -14), Vector2(-17, -25)], Color("#bb863f"), INK, 1.7)
	_line([Vector2(-13, -24), Vector2(-1, -22), Vector2(7, -23)], Color("#644830"), 2.8)
	_piece([Vector2(-13, -35), Vector2(-5, -33), Vector2(-10, -24), Vector2(-16, -22),
		Vector2(-25, -25), Vector2(-25, -31), Vector2(-20, -30)], shadow, INK, 1.5)
	_piece([Vector2(-7, -42), Vector2(-26, -51), Vector2(-21, -39), Vector2(-16, -36),
		Vector2(-9, -37), Vector2(-2, -31), Vector2(9, -34), Vector2(11, -39), Vector2(20, -42),
		Vector2(11, -44), Vector2(14, -53), Vector2(5, -48), Vector2(-2, -48)], olive, INK, 1.8)
	_line([Vector2(-22, -46), Vector2(-17, -41), Vector2(-12, -40)], shadow, 1.6)
	_line([Vector2(-8, -44), Vector2(-2, -46), Vector2(6, -46)], Color("#d4cb85"), 1.25)
	_line([Vector2(2, -41), Vector2(7, -43)], INK, 2.0)
	_line([Vector2(3, -36), Vector2(7, -37)], INK, 1.35)
	_piece([Vector2(-10, -35), Vector2(-2, -33), Vector2(7, -34), Vector2(4, -28),
		Vector2(-7, -29), Vector2(-15, -23), Vector2(-15, -31)], Color("#a5503e"), INK, 1.4)
	# The little blade stays down by its hip, not on the harpooner's reach diagonal.
	_piece([Vector2(15, -24), Vector2(24, -33), Vector2(31, -34), Vector2(29, -25),
		Vector2(20, -17), Vector2(12, -17)], Color("#b9b9a3"), INK, 1.55)
	_line([Vector2(21, -20), Vector2(28, -26), Vector2(29, -31)], Color("#f0d6a4"), 1.3)
	_piece([Vector2(0, -30), Vector2(6, -30), Vector2(10, -25), Vector2(16, -26),
		Vector2(19, -23), Vector2(16, -19), Vector2(8, -19), Vector2(2, -23)], olive, INK, 1.5)


func _hookhand() -> void:
	var coat := Color("#4d7370")
	var seam := Color("#81a096")
	var iron := Color("#acbab1")
	var skin := Color("#bc8867")
	_piece([Vector2(-20, -18), Vector2(14, -20), Vector2(17, -11), Vector2(15, -6),
		Vector2(23, -3), Vector2(24, 1), Vector2(8, 2), Vector2(3, -4), Vector2(1, -12),
		Vector2(-9, -13), Vector2(-13, -5), Vector2(-12, 1), Vector2(-31, 1), Vector2(-28, -6),
		Vector2(-25, -13)], Color("#615147"), INK, 1.9)
	# Wide oilskin shoulders and elbow; a single upright hook instead of a polearm.
	_piece([Vector2(-36, -29), Vector2(-37, -40), Vector2(-28, -53), Vector2(-12, -57),
		Vector2(8, -56), Vector2(18, -50), Vector2(21, -40), Vector2(28, -45), Vector2(37, -38),
		Vector2(33, -28), Vector2(24, -23), Vector2(15, -26), Vector2(19, -12), Vector2(5, -13),
		Vector2(-5, -10), Vector2(-11, -17), Vector2(-25, -13), Vector2(-27, -23)],
		coat, INK, 2.25)
	_piece([Vector2(-35, -39), Vector2(-28, -51), Vector2(-13, -55), Vector2(8, -54),
		Vector2(17, -48), Vector2(14, -39), Vector2(5, -38), Vector2(-5, -44), Vector2(-16, -34),
		Vector2(-22, -40)], Color("#6e8980"), INK, 1.45)
	_line([Vector2(-32, -42), Vector2(-27, -48), Vector2(-18, -50)], seam, 1.65)
	_line([Vector2(-5, -43), Vector2(-2, -32), Vector2(-4, -16)], Color("#2b4a48"), 1.8)
	for y in [-34, -28, -22]:
		_ink_canvas.draw_circle(Vector2(2, y), 1.4, Color("#cba66f"), true, -1.0, true)
	_piece([Vector2(-7, -51), Vector2(-11, -61), Vector2(-5, -67), Vector2(7, -66),
		Vector2(14, -59), Vector2(14, -54), Vector2(17, -51), Vector2(12, -48), Vector2(9, -42),
		Vector2(1, -42), Vector2(-6, -45)], skin, INK, 1.75)
	_piece([Vector2(-10, -54), Vector2(-14, -61), Vector2(-10, -69), Vector2(-1, -72),
		Vector2(9, -69), Vector2(16, -62), Vector2(13, -58), Vector2(0, -59)],
		Color("#733d38"), INK, 1.6)
	_line([Vector2(-10, -61), Vector2(-1, -64), Vector2(13, -62)], Color("#b56a55"), 1.55)
	_line([Vector2(6, -55), Vector2(11, -56)], INK, 1.7)
	_line([Vector2(2, -47), Vector2(6, -50), Vector2(10, -49)], Color("#5d4033"), 1.5)
	_piece([Vector2(26, -42), Vector2(27, -52), Vector2(36, -52), Vector2(40, -45),
		Vector2(38, -38), Vector2(31, -35)], Color("#6a5d50"), INK, 1.85)
	_piece([Vector2(29, -48), Vector2(28, -58), Vector2(31, -67), Vector2(37, -72),
		Vector2(44, -72), Vector2(51, -67), Vector2(53, -60), Vector2(49, -53), Vector2(42, -51),
		Vector2(46, -57), Vector2(46, -62), Vector2(42, -65), Vector2(37, -63), Vector2(35, -57),
		Vector2(36, -47)], iron, INK, 2.0)
	_line([Vector2(31, -57), Vector2(33, -66), Vector2(38, -69), Vector2(44, -70),
		Vector2(49, -66)], Color("#ebdcb4"), 1.5)
	_piece([Vector2(-35, -29), Vector2(-26, -28), Vector2(-23, -24), Vector2(-27, -19),
		Vector2(-34, -20), Vector2(-37, -24)], skin, INK, 1.5)


func _bruiser() -> void:
	var mail := Color("#7a726c")
	var brass := Color("#be965c")
	var wool := Color("#884840")
	var skin := Color("#c49571")
	# A low, wide stance anchors the slab hammer and the big, squared gauntlets.
	_piece([Vector2(-25, -23), Vector2(17, -22), Vector2(23, -16), Vector2(21, -7),
		Vector2(31, -4), Vector2(30, 1), Vector2(9, 2), Vector2(6, -2), Vector2(8, -12),
		Vector2(-8, -12), Vector2(-14, -3), Vector2(-14, 1), Vector2(-35, 1),
		Vector2(-36, -4), Vector2(-29, -9)], Color("#5e4942"), INK, 2.15)
	_piece([Vector2(-27, -43), Vector2(-16, -50), Vector2(8, -49), Vector2(22, -44),
		Vector2(28, -34), Vector2(18, -25), Vector2(18, -18), Vector2(7, -14), Vector2(-19, -17),
		Vector2(-27, -23), Vector2(-35, -34)], wool, INK, 2.1)
	_piece([Vector2(-34, -39), Vector2(-29, -48), Vector2(-19, -49), Vector2(-10, -43),
		Vector2(-11, -32), Vector2(-23, -27), Vector2(-35, -31)], mail, INK, 1.95)
	_line([Vector2(-32, -38), Vector2(-27, -45), Vector2(-20, -46), Vector2(-15, -42)], brass, 2.0)
	_piece([Vector2(-19, -40), Vector2(-11, -35), Vector2(7, -37), Vector2(16, -42),
		Vector2(16, -31), Vector2(10, -24), Vector2(-10, -22), Vector2(-20, -27)], mail, INK, 1.55)
	_line([Vector2(-16, -32), Vector2(-9, -29), Vector2(8, -32), Vector2(14, -36)], Color("#bdac91"), 1.7)
	_line([Vector2(-16, -21), Vector2(-1, -19), Vector2(13, -21)], brass, 2.0)
	_piece([Vector2(-10, -48), Vector2(-12, -56), Vector2(-7, -62), Vector2(5, -64), Vector2(12, -59),
		Vector2(14, -50), Vector2(10, -44), Vector2(9, -40), Vector2(-1, -39), Vector2(-7, -43)],
		skin, INK, 1.7)
	_piece([Vector2(-12, -54), Vector2(-14, -63), Vector2(-8, -68), Vector2(5, -69),
		Vector2(13, -64), Vector2(14, -55), Vector2(6, -55), Vector2(3, -47),
		Vector2(-1, -49), Vector2(-1, -55)], mail, INK, 1.8)
	_line([Vector2(-11, -61), Vector2(-5, -65), Vector2(6, -65), Vector2(11, -62)], brass, 1.4)
	_line([Vector2(7, -52), Vector2(11, -53)], INK, 1.5)
	_line([Vector2(3, -44), Vector2(9, -45)], INK, 1.3)
	_piece([Vector2(-34, -31), Vector2(-24, -32), Vector2(-19, -25), Vector2(-23, -17),
		Vector2(-34, -16), Vector2(-38, -23)], skin, INK, 1.75)
	_line([Vector2(-35, -23), Vector2(-30, -25), Vector2(-25, -24)], Color("#765344"), 1.45)
	_line([Vector2(13, -9), Vector2(32, -42)], INK, 6.4)
	_line([Vector2(13, -9), Vector2(32, -42)], Color("#b08258"), 3.1)
	_piece([Vector2(20, -54), Vector2(27, -57), Vector2(45, -49), Vector2(46, -43),
		Vector2(39, -31), Vector2(19, -38), Vector2(16, -44)], Color("#a8a299"), INK, 2.2)
	_piece([Vector2(36, -51), Vector2(45, -49), Vector2(46, -43), Vector2(39, -31), Vector2(31, -34)],
		Color("#706d67"), INK, 1.5)
	_line([Vector2(19, -45), Vector2(24, -53), Vector2(33, -51)], Color("#d3c2a1"), 1.55)
	_piece([Vector2(12, -40), Vector2(20, -39), Vector2(22, -33), Vector2(23, -29), Vector2(27, -29),
		Vector2(29, -24), Vector2(24, -19), Vector2(15, -20), Vector2(10, -28)], skin, INK, 1.8)
	_line([Vector2(20, -27), Vector2(23, -24), Vector2(27, -25)], Color("#765344"), 1.45)


func _village_troll() -> void:
	var skin := Color("#9aa970")
	var shade := Color("#727e56")
	var pale := Color("#c6c58c")
	var apron := Color("#b47648")
	# Soft shoulders, big bare toes, open palm and work apron: large but not armored.
	_piece([Vector2(-21, -24), Vector2(16, -26), Vector2(22, -19), Vector2(16, -9),
		Vector2(19, -5), Vector2(29, -5), Vector2(32, -1), Vector2(28, 2), Vector2(8, 2),
		Vector2(4, -3), Vector2(4, -12), Vector2(-7, -11), Vector2(-10, -3), Vector2(-13, 2),
		Vector2(-32, 2), Vector2(-35, -1), Vector2(-31, -6), Vector2(-24, -8)], shade, INK, 2.0)
	_line([Vector2(-29, -4), Vector2(-23, -4), Vector2(-20, -1)], pale, 1.5)
	_line([Vector2(24, -3), Vector2(25, 0), Vector2(28, -2), Vector2(29, 0)], pale, 1.35)
	_piece([Vector2(-17, -55), Vector2(-28, -52), Vector2(-36, -44), Vector2(-38, -32),
		Vector2(-37, -21), Vector2(-29, -14), Vector2(-24, -14), Vector2(-22, -23),
		Vector2(-16, -16), Vector2(5, -11), Vector2(18, -14), Vector2(24, -20), Vector2(24, -34),
		Vector2(19, -48), Vector2(10, -56), Vector2(-3, -59)], skin, INK, 2.1)
	_line([Vector2(-33, -43), Vector2(-28, -48), Vector2(-21, -50)], pale, 1.7)
	_line([Vector2(-30, -31), Vector2(-29, -23), Vector2(-27, -22)], shade, 2.0)
	_piece([Vector2(-21, -53), Vector2(-16, -55), Vector2(-8, -43), Vector2(6, -43),
		Vector2(10, -56), Vector2(15, -53), Vector2(13, -42), Vector2(19, -33), Vector2(23, -15),
		Vector2(18, -10), Vector2(9, -10), Vector2(6, -13), Vector2(-6, -10), Vector2(-20, -14),
		Vector2(-18, -32), Vector2(-13, -40)], apron, INK, 1.85)
	_line([Vector2(-19, -31), Vector2(-7, -29), Vector2(7, -30), Vector2(18, -32)], Color("#e0aa6d"), 1.75)
	_piece([Vector2(-14, -26), Vector2(1, -24), Vector2(1, -15), Vector2(-11, -16)],
		Color("#d7ae77"), Color("#6d4939"), 1.25)
	_line([Vector2(-12, -23), Vector2(-6, -22), Vector2(-2, -22)], Color("#f2d3a2"), 1.35)
	_piece([Vector2(-15, -65), Vector2(-11, -74), Vector2(-3, -79), Vector2(8, -78), Vector2(15, -73),
		Vector2(16, -66), Vector2(23, -62), Vector2(23, -57), Vector2(18, -54), Vector2(16, -48),
		Vector2(9, -45), Vector2(-2, -46), Vector2(-9, -51), Vector2(-15, -57), Vector2(-21, -59),
		Vector2(-22, -65), Vector2(-19, -68)], skin, INK, 2.0)
	_piece([Vector2(-15, -65), Vector2(-12, -74), Vector2(-5, -80), Vector2(4, -80),
		Vector2(11, -77), Vector2(14, -71), Vector2(8, -72), Vector2(3, -75), Vector2(-1, -72),
		Vector2(-7, -72), Vector2(-11, -64)], Color("#5e6049"), INK, 1.5)
	_line([Vector2(-17, -64), Vector2(-16, -61), Vector2(-12, -60)], shade, 1.25)
	_line([Vector2(-3, -66), Vector2(1, -68), Vector2(5, -67)], shade, 1.9)
	_ink_canvas.draw_circle(Vector2(3, -63), 1.6, INK, true, -1.0, true)
	_ink_canvas.draw_circle(Vector2(12, -64), 1.5, INK, true, -1.0, true)
	_piece([Vector2(8, -61), Vector2(14, -63), Vector2(20, -60), Vector2(19, -56), Vector2(11, -55),
		Vector2(7, -57)], Color("#ce9f71"), Color("#725f45"), 1.15)
	_line([Vector2(-1, -55), Vector2(2, -52), Vector2(7, -51), Vector2(13, -53)], INK, 1.6)
	_line([Vector2(1, -55), Vector2(4, -53), Vector2(8, -53)], Color("#eddeb1"), 1.4)
	_piece([Vector2(15, -43), Vector2(21, -42), Vector2(25, -35), Vector2(30, -37), Vector2(29, -42),
		Vector2(26, -46), Vector2(27, -50), Vector2(30, -50), Vector2(34, -45), Vector2(34, -52),
		Vector2(38, -53), Vector2(40, -49), Vector2(43, -50), Vector2(46, -47), Vector2(44, -38),
		Vector2(38, -32), Vector2(35, -27), Vector2(24, -23), Vector2(17, -27)], skin, INK, 1.8)
	_line([Vector2(32, -39), Vector2(35, -42), Vector2(40, -42)], pale, 1.7)
	_line([Vector2(37, -48), Vector2(37, -45), Vector2(40, -46), Vector2(40, -44)], shade, 1.3)


# Freehand paths are authored in tile-local coordinates. Each wash is a broad,
# transparent polygon; the boundary and interior marks carry different weights.
func _wash(p: Vector2, extent: Vector2, color: Color) -> void:
	var x := extent.x
	var y := extent.y
	_ink_canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, y * 0.35), p + Vector2(x * 0.19, 0),
		p + Vector2(x * 0.53, y * 0.15), p + Vector2(x * 0.90, y * 0.03), p + Vector2(x, y * 0.46),
		p + Vector2(x * 0.79, y * 0.76), p + Vector2(x * 0.43, y), p + Vector2(x * 0.13, y * 0.80)]), color)


func _piece(points: Array, fill: Color, outline := Color.TRANSPARENT, weight := 1.0) -> void:
	_ink_canvas.draw_colored_polygon(PackedVector2Array(points), fill)
	if outline.a > 0.0:
		var closed := PackedVector2Array(points)
		closed.append(closed[0])
		_ink_canvas.draw_polyline(closed, outline, weight, true)


func _line(points: Array, color: Color, weight: float) -> void:
	_ink_canvas.draw_polyline(PackedVector2Array(points), color, weight, true)
