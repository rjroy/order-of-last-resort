extends SceneTree
## Run with a graphical display from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/presentation/cast_sprite_art_test.gd
## The game must also run from a fresh checkout without an editor import.

const Board = preload("res://presentation/battle/bridge_art.gd")
const MANIFEST := "res://assets/cast/manifest.json"
const CELL := Vector2i.ZERO
const CELLS := {CELL: "bridge"}
const ROLES := ["knight", "healer", "wizard", "rogue", "necromancer", "bard", "skeleton", "zombie",
	"alchemist", "harpooner", "blacksmith"]
const ART_KEYS := {
	"knight": "knight", "healer": "healer", "wizard": "wizard",
	"rogue": "wizard", "necromancer": "wizard", "bard": "wizard",
	# Stock Mixologist keeps the legacy art key; cast_key selects her own sprite.
	"skeleton": "skeleton", "zombie": "zombie", "alchemist": "healer", "harpooner": "enemy",
	"blacksmith": "blacksmith",
}
const EXTRA_CLIPS := {
	"knight": ["guard", "shield_away"],
	"healer": ["ally_heal", "self_heal", "bonk"],
	"wizard": ["blast", "pull"],
	"rogue": ["retreat", "swap", "misdirect"],
	"bard": ["inspiring_melody", "healing_sonnet"],
	"necromancer": ["summon_skeleton", "raise_dead"],
	"skeleton": ["wave", "dont_go"],
	"zombie": ["say_hello", "offer_flower", "gift"],
	"alchemist": ["potion", "acid", "acid_flask"],
	"harpooner": ["pursue", "close_thrust", "ranged_cast", "hit", "defeat", "harpoon_projectile"],
	"blacksmith": ["pursue", "try_this", "hammer_time", "hit", "down", "recover", "defeat"],
}
const READY_ACTIONS := {
	"knight": "guard", "healer": "bonk", "wizard": "blast",
	"rogue": "misdirect", "alchemist": "potion",
	"zombie": "offer_flower",
	# Existing animated guild members and an opponent are controls.
	"bard": "inspiring_melody", "necromancer": "summon_skeleton", "harpooner": "close_thrust",
	"blacksmith": "hammer_time",
}

var board := Board.new()
var viewport := SubViewport.new()
var failures := 0
var atlas_sizes := {}


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Cast sprite art test needs a graphical renderer; omit --headless.")
		board.free()
		viewport.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	viewport.size = Vector2i(Board.TILE + Board.GUTTER * 2.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var preview := SubViewportContainer.new()
	preview.add_child(viewport)
	root.add_child(preview)

	_check_manifest()
	var empty := await _render("")
	var fallback := await _render("", {"art_key": "unmodeled_art"})
	var fallback_again := await _render("", {"art_key": "another_unmodeled_art"})
	_check(_difference(fallback, fallback_again) == 0,
		"Unknown art keys should continue to use the same fallback")
	var figures: Dictionary = {}
	for role in ROLES:
		var ready := await _render(role)
		figures[role] = ready
		_check(_difference(ready, empty) > 100, "%s should render a visible figure" % role)
		_check(_difference(ready, fallback) > 100, "%s should not render the fallback" % role)
		for other in figures:
			if other != role:
				_check(_difference(ready, figures[other]) > 100,
					"%s and %s should render distinctly" % [role, other])

		var facing_left := await _render(role, {"facing": -1})
		_check(_difference(ready, facing_left) > 30, "%s should respond to facing" % role)
		var prone := await _render(role, {"prone": true})
		_check(_difference(ready, prone) > 100, "%s should show prone state" % role)
		var fallen := await _render(role, {"prone": true, "hp": 0, "max_hp": 3})
		var down := await _render(role, {"prone": true, "hp": 1, "max_hp": 3})
		_check(_difference(fallen, down) > 10, "%s should distinguish fallen from down" % role)
		var guarded := await _render(role, {"guarded": true})
		_check(_difference(ready, guarded) > 10, "%s should show guarded state" % role)
		var selected := await _render(role, {}, {"selected": CELL})
		_check(_difference(ready, selected) > 10, "%s should show selection" % role)
		var labelled := await _render(role, {"label": "HERO"})
		_check(_difference(ready, labelled) > 20, "%s should show its label" % role)
		var healthy := await _render(role, {"hp": 3, "max_hp": 3})
		var injured := await _render(role, {"hp": 1, "max_hp": 3})
		_check(_difference(healthy, injured) > 10, "%s should show its health" % role)

	var shield_away := await _render("knight", {"shield_away": true})
	_check(_difference(figures["knight"], shield_away) > 10,
		"Knight must show when the shield is away")
	for role in READY_ACTIONS:
		await _check_live_ready(role, READY_ACTIONS[role])
	await _check_smith_lifecycle()
	if failures == 0:
		print("Cast sprite art test passed: distinct figures and tactical state remain visible.")
	quit(1 if failures else 0)


func _render(role: String, state: Dictionary = {}, overlay: Dictionary = {}) -> Image:
	var units: Array = []
	if not role.is_empty() or state.has("art_key"):
		var unit := {"id": "unit", "art_key": ART_KEYS.get(role, ""), "cell": CELL, "facing": 1}
		if not role.is_empty():
			unit["cast_key"] = role
		unit.merge(state, true)
		units.append(unit)
	board.set_render_state(CELLS, units, overlay)
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _check_smith_lifecycle() -> void:
	var cast = board.get("_cast")
	var clips: Dictionary = cast.get("_actors").get("blacksmith", {})
	if not clips.has("defeat") or not clips.has("ready"):
		_check(false, "Stock Smith's ready and defeat clips are required")
		return
	board.set_actual_draw_capture_enabled(true)
	for action: Array in [["hit", 5], ["down", 16], ["recover", 22]]:
		await _check_smith_reaction(action[0], action[1])
	board.clear_action_playback()
	var body := {"hp": 0, "max_hp": 0, "prone": true, "visual_defeat": true, "guild_knockdown_art": true}
	var authored := await _render("blacksmith", body)
	var authored_row: Dictionary = board.actual_draw_snapshot().get("actors", {}).get("unit", {})
	_check(authored_row.get("clip") == "defeat" \
		and authored_row.get("source_frame") == clips.defeat.source_frames.back(),
		"The Smith's actual fallen pixels use the retained terminal defeat drawing")
	var defeat = clips.defeat
	clips.erase("defeat")
	var missing_take := await _render("blacksmith", body)
	var fallback_row: Dictionary = board.actual_draw_snapshot().get("actors", {}).get("unit", {})
	_check(fallback_row.get("clip") == "ready" and fallback_row.get("atlas") == clips.ready.path \
		and fallback_row.get("turned_down", false), "Missing authored defeat uses the Smith's drawn prone Ready")
	var rotated_ready := await _render("blacksmith", body.merged({"visual_defeat": false}, true))
	var token := await _render("", body.merged({"art_key": "blacksmith"}, true))
	clips["defeat"] = defeat
	# Figure/corpse captions differ with the lifecycle flag. Compare the lower
	# part where both poses are drawn, excluding the top status caption.
	var crop := Rect2i(0, int(Board.GUTTER.y + 24), authored.get_width(), int(Board.TILE.y - 12))
	_check(_difference(missing_take.get_region(crop), rotated_ready.get_region(crop)) == 0,
		"Missing Smith defeat draws the same stock prone ready silhouette")
	_check(_difference(missing_take.get_region(crop), token.get_region(crop)) > 100,
		"Missing Smith defeat draws the ready sprite, not a generic token")
	_check(_difference(authored.get_region(crop), missing_take.get_region(crop)) > 100,
		"Authored defeat actually draws a different terminal pose")
	board.set_actual_draw_capture_enabled(false)


func _check_smith_reaction(key: String, source_frame: int) -> void:
	var clip = board.get("_cast").clip_for("blacksmith", key)
	if clip == null:
		return # Missing packaged art is reported by the inventory check.
	board.clear_action_playback()
	var state := {"hp": 1, "max_hp": 0, "guild_knockdown_art": true, "prone": key == "down"}
	var idle := await _render("blacksmith", state)
	var cue := {"unit_id": "unit", "cast_key": "blacksmith", "clip": key, "source_cell": CELL}
	if key in ["down", "recover"]:
		cue["hero_knockdown"] = key
	board.play_committed_actions([cue])
	board.set_process(false)
	board._process((clip.time_at_source_frame(source_frame) + 1.0) / 1000.0)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var drawn: Dictionary = board.actual_draw_snapshot().get("actors", {}).get("unit", {})
	var actual := viewport.get_texture().get_image()
	_check(drawn.get("clip") == key and drawn.get("atlas") == clip.path and drawn.get("source_frame") == source_frame,
		"Smith actually paints %s F%d, not merely a readable atlas" % [key, source_frame])
	_check(_difference(idle, actual) > 20, "%s is visible as a different Smith pose" % key)


func _check_live_ready(role: String, action: String) -> void:
	board.clear_action_playback()
	board.set("_ready_ms", 0.0)
	await _render(role)
	var ready = board.get("_cast").clip_for(role, "ready")
	if ready == null:
		_check(false, role + " needs a ready clip")
		return
	_check(ready.loop and ready.frames.size() > 1,
		role + " ready must loop through multiple frames")
	_check(board.is_processing(), role + " must process its live ready animation")
	board.set_process(false)
	if not ready.loop or ready.frames.size() < 2:
		return
	await _check_ready_cycles(role, ready)

	var before_action: Image
	if role == "zombie":
		before_action = await _ready_frame_zero()
	var cue := {"unit_id": "unit", "cast_key": role, "clip": action, "source_cell": CELL}
	if role == "zombie":
		cue["target_cell"] = Vector2i(1, 0)
	board.play_committed_actions([cue])
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.is_empty():
		_check(false, role + " action enters playback")
		return
	if role == "zombie":
		_check(active[0].gift != null, "Offer Flower releases the rock gift")
	board._process((active[0].duration_ms + 1.0) / 1000.0)
	_check(board.action_playback_snapshot().is_empty(), role + " action completes")
	_check(board.is_processing(), role + " resumes processing ready after its action")
	board.set_process(false)
	if role == "zombie":
		var returned := await _ready_frame_zero()
		_check(_difference(before_action, returned) == 0,
			"Zombie returns to its original rock-in-hand ready pose after Offer Flower")
	await _check_ready_cycles(role + " after action", ready)


func _ready_frame_zero() -> Image:
	board.set("_ready_ms", 0.0)
	board.get("_figures").queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _check_ready_cycles(label: String, ready) -> void:
	# Replay the same controlled clock samples rather than assuming every
	# identity completes a cycle in the manifest's unscaled duration.
	var first_cycle: Array[Image] = []
	for cycle in 2:
		board.set("_ready_ms", 0.0)
		board.get("_figures").queue_redraw()
		var elapsed := 0.0
		var first: Image
		var changed := false
		for index in ready.frames.size():
			var start: float = 0.0 if index == 0 else ready.frame_ends[index - 1]
			var sample: float = (start + ready.frame_ends[index]) * 0.5
			board._process((sample - elapsed) / 1000.0)
			board.set_process(false)
			elapsed = sample
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			if index == 0:
				first = image
			elif _difference(first, image) > 10:
				changed = true
			if cycle == 0:
				first_cycle.append(image)
			else:
				_check(_difference(first_cycle[index], image) == 0,
					label + " reproduces the same rendered frame at the same time")
		_check(changed, "%s visibly animates during ready sampling %d" % [label, cycle + 1])


func _check_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		_check(false, "Packaged cast manifest must exist without an import")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or not parsed.get("actors") is Dictionary:
		_check(false, "Cast manifest must contain actors")
		return
	var scale: Variant = parsed.get("display_scale")
	_check(_finite_number(scale) and float(scale) > 0.0,
		"Cast manifest must have a finite positive display scale")
	var actors: Dictionary = parsed.actors
	for role in ROLES:
		if not actors.get(role) is Dictionary or not actors[role].get("clips") is Dictionary:
			_check(false, "%s must have packaged clips" % role)
			continue
		var clips: Dictionary = actors[role].clips
		for clip_name in ["ready"] + EXTRA_CLIPS[role]:
			if not clips.get(clip_name) is Dictionary:
				_check(false, "%s must have a %s clip" % [role, clip_name])
				continue
			_check_clip(role, clip_name, clips[clip_name])


func _check_clip(role: String, name: String, clip: Dictionary) -> void:
	var context := "%s/%s" % [role, name]
	var path := str(clip.get("path", ""))
	if not path.begins_with("res://assets/") or not path.ends_with(".png") or not FileAccess.file_exists(path):
		_check(false, "%s must reference a packaged PNG, not local scratch or an import" % context)
		return
	if not atlas_sizes.has(path):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
			_check(false, "%s PNG must load directly from packaged bytes" % context)
			return
		atlas_sizes[path] = image.get_size()
	var image_size: Vector2i = atlas_sizes[path]
	var frames: Variant = clip.get("frames")
	var anchor: Variant = clip.get("anchor")
	_check(clip.get("loop") is bool, "%s must specify whether it loops" % context)
	if not frames is Array or frames.is_empty() or not anchor is Array or anchor.size() != 2:
		_check(false, "%s must have frames and a two-coordinate anchor" % context)
		return
	# The anchor is frame-local, but may be just outside a tightly cropped frame
	# (and the zombie gift uses the stone, rather than the actor's feet).
	_check(_finite_number(anchor[0]) and _finite_number(anchor[1]),
		"%s anchor coordinates must be finite numbers" % context)
	for frame in frames:
		if not frame is Dictionary or not frame.get("rect") is Array or frame.rect.size() != 4:
			_check(false, "%s frame must have a rectangle" % context)
			continue
		if not _integer_number(frame.rect[0]) or not _integer_number(frame.rect[1]) \
				or not _integer_number(frame.rect[2]) or not _integer_number(frame.rect[3]):
			_check(false, "%s frame rectangle coordinates must be integers" % context)
			continue
		var rect := Rect2i(int(frame.rect[0]), int(frame.rect[1]), int(frame.rect[2]), int(frame.rect[3]))
		_check(rect.position.x >= 0 and rect.position.y >= 0 and rect.size.x > 0 and rect.size.y > 0
			and rect.end.x <= image_size.x and rect.end.y <= image_size.y,
			"%s frame must lie within its PNG" % context)
		_check(_finite_number(frame.get("duration_ms")) and float(frame.duration_ms) > 0
			and _integer_number(frame.get("source_frame")),
			"%s frame must have duration and source frame" % context)


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _integer_number(value: Variant) -> bool:
	return _finite_number(value) and floor(float(value)) == float(value)


func _difference(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
