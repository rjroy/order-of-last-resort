extends SceneTree
## From the repository root, use a fresh output directory:
## godot --path games/company-of-unlikely-heroes --script res://tests/journeys/ferryman_rescue_scene_test.gd -- --output="$PWD/.lore/local/ferryman-rescue"
## Uses the unmodified standalone stock catalog, not an adventure profile.

const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Sprites = preload("res://presentation/cast/cast_sprites.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const ROUTE := [
	["healer", "move", "0,3"], [], ["knight", "move", "2,1"],
	["knight", "knight_push", "crate"], ["wizard", "move", "1,1"],
	["wizard", "wizard_pull", "harpooner"], [], ["wizard", "wizard_blast", ""], []
]

var scene: Node
var viewport: SubViewport
var output := ""
var failures: Array[String] = []
var saw_travel := false
var saw_victory := false
var ready_art := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_finish("A graphical renderer is required.")
		return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--output=") or not output.is_empty():
			_finish("Supply exactly one --output=<absolute directory>.")
			return
		output = arg.trim_prefix("--output=").simplify_path()
	var local := ProjectSettings.globalize_path("res://../../.lore/local").simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/"):
		_finish("Output must be under .lore/local.")
		return
	var path := local
	for part in output.trim_prefix(local + "/").split("/"):
		path = path.path_join(part)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_finish("Output must not contain symbolic links.")
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_finish("Cannot create output directory.")
		return
	var dir := DirAccess.open(output)
	if dir == null or not dir.get_files().is_empty() or not dir.get_directories().is_empty():
		_finish("Output directory must be empty.")
		return

	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--storybook", "--mission=goblin_mob"]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	var opening: Dictionary = Rules.open_mission(Catalog.read_default(), "company_rescue",
		["knight", "healer", "wizard"])
	_check(opening.objective.subject == "civilian", "Stock rescue objective names the civilian")
	_check(_unit(opening, "civilian").get("character_id") == "ferryman", "Subject is the stock Ferryman")
	_check(_unit(opening, "harpooner").get("character_id") == "harpooner", "Stock Harpooner is present")
	var subject := _unit(opening, "civilian")
	_check(Cues.cast_key_for(opening, subject) == "ferryman", "Stock subject has Ferryman cast data identity")
	_check(Cues.cast_key_for(opening, subject, {"team": "civilian", "art_key": "another_actor"}).is_empty(),
		"An unrelated custom art identity cannot inherit Ferryman art")
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	await process_frame
	var board := scene.find_child("BridgeBoard", true, false)
	if board == null:
		_finish("Stock rescue board did not open.")
		return
	board.set_process(false)
	for identity in [["civilian", "ferryman"], ["harpooner", "harpooner"]]:
		var figure: Dictionary = board.get("_units_by_id").get(identity[0], {})
		var bound: bool = figure.get("cast_key") == identity[1]
		_check(bound, identity[0] + " uses authored cast identity at opening")
		var art = Sprites.new()
		art.load_manifest()
		var ready = art.clip_for(identity[1], "ready")
		var loaded: bool = ready != null and Sprites.load_texture(ready.path) != null if ready != null else false
		_check(loaded, identity[0] + " has loadable ready art, not a placeholder")
		ready_art = ready_art and bound and loaded
	_check(board.call("action_playback_snapshot").is_empty(), "Opening forecast plays no action")
	if ready_art:
		await _capture("00-ready.png")

	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	for i in ROUTE.size():
		if scene.current_screen() != "battle":
			_check(false, "Route ended before round %d" % (i + 1))
			break
		var command: Array = ROUTE[i]
		if not command.is_empty() and not await driver.command(command[0], command[1], command[2]):
			_check(false, "Round %d command unavailable: %s" % [i + 1, driver.error])
			break
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		var before: Dictionary = scene.battle_snapshot()
		if not plan.get("valid", false):
			_check(false, "Round %d forecast is valid" % (i + 1))
			break
		_check(board.call("action_playback_snapshot").is_empty(), "Forecast never starts playback")
		var movement := false
		var victory := false
		var damage := 0
		for event: Dictionary in plan.events:
			if event.get("type") == "move" and event.get("unit_id") == "civilian":
				movement = true
			if event.get("type") == "victory" and event.get("target_id") == "civilian":
				victory = true
				_check(event.get("position") == opening.objective.destination,
					"Victory event names the actual safe bank")
			if event.get("target_id") == "civilian" and event.get("type") == "damage":
				damage += int(event.get("amount", 0))
		if victory:
			var unrelated: Array = plan.events.duplicate(true)
			for event: Dictionary in unrelated:
				if event.get("type") == "victory":
					event["target_id"] = "harpooner"
			_check(not _has_cue(Cues.build(before, plan.result, unrelated), "safe_bank"),
				"A victory naming another target cannot trigger Ferryman relief")
			unrelated = plan.events.duplicate(true)
			for event: Dictionary in unrelated:
				if event.get("type") == "victory":
					event["position"] = Vector2i(-1, -1)
			_check(not _has_cue(Cues.build(before, plan.result, unrelated), "safe_bank"),
				"A victory at another destination cannot trigger Ferryman relief")
		var button := scene.find_child("Commit", true, false) as BaseButton
		if button == null or button.disabled or not button.is_visible_in_tree():
			_check(false, "Round %d can be committed" % (i + 1))
			break
		button.pressed.emit()
		var committed: Dictionary = scene.battle_snapshot().duplicate(true)
		committed.erase("_terminal_commit")
		_check(committed == plan.result, "Commit agrees with its forecast")
		await process_frame
		if scene.current_screen() != "battle":
			var overlay := scene.find_child("TerminalCastReplay", true, false)
			if overlay != null:
				for child in overlay.find_children("*", "", true, false):
					if child.has_method("action_playback_snapshot"):
						board = child
						break
		board.set_process(false)
		var cues: Array = board.call("action_playback_snapshot")
		if damage > 0:
			var reaction := "down" if _unit(plan.result, "civilian").get("hp", 0) <= 0 else "flinch"
			_check(_has_cue(cues, reaction), "Actual civilian damage plays " + reaction)
			if ready_art and _has_cue(cues, reaction):
				await _capture_clip(board, reaction, "%02d-%s.png" % [i + 1, reaction])
		if movement:
			saw_travel = true
			_check(_has_cue(cues, "travel"), "Committed civilian movement plays travel")
			if ready_art and _has_cue(cues, "travel"):
				await _capture_clip(board, "travel", "%02d-travel.png" % (i + 1))
		if victory:
			saw_victory = true
			_check(plan.result.outcome == "victory", "Named victory commits a win")
			_check(_unit(plan.result, "civilian").get("position") == opening.objective.destination,
				"Victorious Ferryman actually reaches destination")
			_check(_has_cue(cues, "safe_bank"), "Terminal named victory plays safe_bank")
			if ready_art and _has_cue(cues, "safe_bank"):
				await _capture_clip(board, "safe_bank", "%02d-safe-bank.png" % (i + 1))
		board.call("_process", 30.0)
		board.set_process(false)
		_check(board.call("action_playback_snapshot").is_empty(), "Committed playback finishes")
		if scene.current_screen() != "battle":
			break
	_check(saw_travel, "Stock route actually moves the Ferryman")
	_check(saw_victory, "Stock route actually wins by rescuing the Ferryman")
	_check(not FileAccess.file_exists(output.path_join("unused-profile.json")), "No profile was written")
	_finish("")


func _capture_clip(board: Node, clip: String, name: String) -> void:
	var playback = board.get("_playback")
	for entry in playback.get("_entries"):
		if entry.cue.get("unit_id") == "civilian" and entry.cue.get("clip") == clip:
			board.call("_process", maxf(0.0, -entry.elapsed_ms + entry.clip.total_ms * 0.48) / 1000.0)
			board.set_process(false)
			break
	await _capture(name)


func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png(output.path_join(name)) == OK, "Saved " + name)


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _has_cue(cues: Array, clip: String) -> bool:
	return cues.any(func(cue): return cue.get("unit_id") == "civilian" \
		and cue.get("cast_key") == "ferryman" and cue.get("clip") == clip)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(error: String) -> void:
	if not error.is_empty():
		failures.append(error)
	if failures.is_empty():
		print("PASS: stock Ferryman rescue; captures in " + output)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
