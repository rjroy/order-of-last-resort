extends SceneTree
## Graphical regression and capture from the repository root:
## godot --path games/company-of-unlikely-heroes --script res://tests/harpooner_rescue_scene_test.gd -- --output="$PWD/.lore/local/harpooner-rescue"
## Use a new empty directory. This uses the real main scene and stock rules.

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const SIZE := Vector2i(1280, 820)

var scene: Node
var viewport: SubViewport
var output := ""
var failures: Array[String] = []
var seen := {}
var facts := {}


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
		_finish("Output must be a directory under .lore/local.")
		return
	var path := local
	for part in output.trim_prefix(local + "/").split("/"):
		path = path.path_join(part)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			_finish("Output path must not contain symbolic links.")
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_finish("Cannot create output directory.")
		return
	var dir := DirAccess.open(output)
	if dir == null or not dir.get_files().is_empty() or not dir.get_directories().is_empty():
		_finish("Output directory must be empty.")
		return

	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--storybook", "--mission=goblin_mob"]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	await _route("close", [
		["knight", "move", "2,1"], ["wizard", "move", "1,1"],
		["wizard", "wizard_pull", "harpooner"], ["knight", "knight_push", "harpooner"]])
	await _route("pursue", [
		["knight", "move", "2,1"], ["knight", "knight_push", "crate"]])
	await _route("ranged", [
		["wizard", "move", "0,0"], ["wizard", "move", "1,0"],
		["wizard", "wizard_pull", "harpooner"], ["knight", "knight_push", "harpooner"],
		["knight", "knight_push", "harpooner"], ["knight", "knight_push", "harpooner"]])
	for fact in ["move", "close", "ranged", "hit", "defeat"]:
		_check(facts.has(fact), "Stock rules route resolves " + fact)
	for clip in ["pursue", "close_thrust", "ranged_cast", "hit", "defeat"]:
		_check(seen.has(clip), "Stock committed routes exercise " + clip)
	_check(not FileAccess.file_exists(output.path_join("unused-profile.json")), "No profile was written")
	_finish("")


func _route(label: String, commands: Array) -> void:
	var opening: Dictionary = Rules.open_mission(Catalog.read_default(), "company_rescue",
		["knight", "healer", "wizard"])
	scene.set("_opening_state", opening.duplicate(true))
	scene.call("_show_battle", opening)
	await process_frame
	var board := scene.find_child("BridgeBoard", true, false)
	if board == null:
		_check(false, "Stock rescue battle did not open")
		return
	var figure: Dictionary = board.get("_units_by_id").get("harpooner", {})
	_check(figure.get("cast_key") == "harpooner", "Runtime Harpooner uses authored art")
	await _check_ready_is_not_placeholder(board, label)
	await _capture(label + "-00-ready.png")
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	for round_number in range(1, commands.size() + 1):
		if scene.current_screen() != "battle":
			_check(false, label + " ended before the route was complete")
			break
		var before: Dictionary = scene.battle_snapshot()
		var command: Array = commands[round_number - 1]
		if not await driver.command(command[0], command[1], command[2]):
			_check(false, "%s round %d command unavailable: %s" % [label, round_number, driver.error])
			break
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		_check(plan.get("valid", false), "Round %d has a valid forecast" % round_number)
		if not plan.get("valid", false):
			break
		var expected := _observe_rules(label, round_number, before, plan)
		_check(board.call("action_playback_snapshot").is_empty(), "Forecast does not play clips")
		var button := scene.find_child("Commit", true, false) as BaseButton
		if button == null or button.disabled:
			_check(false, "Round %d can be committed" % round_number)
			break
		button.pressed.emit()
		_check(scene.battle_snapshot() == plan.get("result"), "Commit matches the stock forecast")
		await process_frame
		if scene.current_screen() != "battle":
			var overlay := scene.find_child("TerminalCastReplay", true, false)
			if overlay != null:
				for child in overlay.find_children("*", "", true, false):
					if child.has_method("action_playback_snapshot"):
						board = child
						break
		var cues: Array = board.call("action_playback_snapshot")
		board.set_process(false)
		for clip in expected:
			_check(cues.any(func(cue): return cue.get("unit_id") == "harpooner" \
				and cue.get("cast_key") == "harpooner" and cue.get("clip") == clip),
				"%s round %d committed %s plays its own cue" % [label, round_number, clip])
		for cue: Dictionary in cues:
			if cue.get("unit_id") != "harpooner":
				continue
			var clip := str(cue.get("clip", ""))
			seen[clip] = true
			_check(cue.get("cast_key") == "harpooner", "Cue belongs to the authored Harpooner")
			if clip in ["close_thrust", "ranged_cast"]:
				var source: Variant = cue.get("source_cell")
				var target: Variant = cue.get("target_cell")
				_check(source is Vector2i and target is Vector2i, clip + " records real action geometry")
				if source is Vector2i and target is Vector2i:
					var distance: int = absi(source.x - target.x) + absi(source.y - target.y)
					_check(distance == (1 if clip == "close_thrust" else 2),
						clip + " matches actual target distance")
					if expected.has(clip):
						_check(target == expected[clip], clip + " aims at the actual attack target")
					if clip == "ranged_cast" and plan.events.any(func(event): return event.get("type") == "reflect" \
							and event.get("ability_id") == "enemy_harpoon"):
						_check(cue.get("recipients", []).any(func(recipient):
							return recipient.get("kind") == "guard" and recipient.get("cell") == target),
							"Reflected harpoon marks the ward at projectile impact")
				_check(plan.events.any(func(event):
					return event.get("resolved_action", {}).get("unit_id") == "harpooner" \
						and event.get("resolved_action", {}).get("ability_id") == "enemy_harpoon"),
					clip + " comes from a committed stock harpoon attack")
			# Seek through the real queued timeline to the matching action;
			# sample the authored contact/release rather than its first frame.
			var playback = board.get("_playback")
			var entry = null
			for candidate in playback.active():
				if candidate.cue == cue:
					entry = candidate
					break
			if entry == null:
				# Actions of the same actor are sequential.
				var entries: Array = playback.get("_entries")
				for candidate in entries:
					if candidate.cue == cue:
						board.call("_process", maxf(0.0, -candidate.elapsed_ms) / 1000.0 + 0.001)
						entry = candidate
						break
			if entry != null:
				var frames := {"close_thrust": 8, "ranged_cast": 11, "pursue": 9, "hit": 4, "defeat": 12}
				var frame: int = frames.get(clip, -1)
				if frame >= 0:
					var at_ms: float = entry.clip.time_at_source_frame(frame)
					board.call("_process", maxf(0.0, at_ms - entry.elapsed_ms) / 1000.0 + 0.001)
					if clip == "ranged_cast":
						_check(entry.gift != null, "Ranged release has a detached projectile")
				board.set_process(false)
				await _capture("%s-%02d-%s.png" % [label, round_number, clip])
				if clip == "ranged_cast" and entry.gift != null:
					board.call("_process", 0.15)
					board.set_process(false)
					_check(entry.gift_from is Vector2 and entry.gift_to is Vector2
						and entry.flight_progress() > 0.0 and entry.flight_progress() < 1.0,
						"Released harpoon flies from the actor toward the actual target")
					await _capture("%s-%02d-flight.png" % [label, round_number])
		# Advance the actual board timeline to completion without sleeping, then
		# inspect the next forecast and capture its returned-to-rest state.
		board.call("_process", 30.0)
		board.set_process(false)
		_check((board.call("action_playback_snapshot") as Array).is_empty(), "Committed playback finishes")
		await _capture("%s-%02d-rest.png" % [label, round_number])
		if scene.current_screen() != "battle":
			break
		_check(scene.battle_snapshot() != before, "Committed round advances the battle")


func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png(output.path_join(name)) == OK,
		"Saved " + name)


func _check_ready_is_not_placeholder(board: Node, label: String) -> void:
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var authored := viewport.get_texture().get_image()
	var cells: Dictionary = board.get("_cells").duplicate(true)
	var units: Array = board.get("_units").duplicate(true)
	var overlay: Dictionary = board.get("_overlay").duplicate(true)
	var fallback: Array = units.duplicate(true)
	for unit: Dictionary in fallback:
		if unit.get("id") == "harpooner":
			unit.erase("cast_key")
	_check(fallback.size() == units.size(), label + ": comparison preserves all board occupants")
	for index in units.size():
		if units[index].get("id") != "harpooner":
			_check(fallback[index] == units[index], label + ": comparison preserves other actors and geometry")
		else:
			var restored: Dictionary = fallback[index].duplicate(true)
			restored["cast_key"] = units[index].get("cast_key")
			_check(restored == units[index], label + ": only the Harpooner's cast binding changes")
	board.call("set_render_state", cells, fallback, overlay)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var placeholder := viewport.get_texture().get_image()
	var changed := 0
	for y in authored.get_height():
		for x in authored.get_width():
			var delta := authored.get_pixel(x, y) - placeholder.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				changed += 1
	_check(changed > 100, label + ": authored ready visibly differs from the fallback figure")
	board.call("set_render_state", cells, units, overlay)
	board.set_process(false)


func _observe_rules(label: String, round_number: int, before: Dictionary, plan: Dictionary) -> Dictionary:
	var positions := {}
	var expected := {}
	for entity in before.units + before.obstacles:
		positions[entity.id] = entity.position
	for event: Dictionary in plan.events:
		var action: Dictionary = event.get("resolved_action", {})
		if action.get("unit_id") == "harpooner":
			if action.get("ability_id") == "move":
				facts["move"] = true
				expected["pursue"] = event.position
			elif action.get("ability_id") == "enemy_harpoon":
				var target := str(event.get("ward_id", event.get("target_id", "")))
				if positions.has(target):
					var source: Vector2i = action.source_cell
					var destination: Vector2i = positions[target]
					var distance := absi(source.x - destination.x) + absi(source.y - destination.y)
					if distance in [1, 2]:
						var kind := "close" if distance == 1 else "ranged"
						facts[kind] = true
						expected["close_thrust" if distance == 1 else "ranged_cast"] = destination
						print("%s round %d: stock %s attack %s -> %s at distance %d" % [
							label, round_number, kind, source, destination, distance])
		if event.get("type") == "damage" and event.get("target_id") == "harpooner" and event.get("amount", 0) > 0:
			var hp := -1
			for unit in plan.result.units:
				if unit.id == "harpooner":
					hp = int(unit.hp)
			var kind := "defeat" if hp <= 0 else "hit"
			facts[kind] = true
			expected[kind] = positions.get("harpooner")
			print("%s round %d: stock %s, resulting HP %d" % [label, round_number, kind, hp])
		match event.type:
			"move":
				positions[event.unit_id] = event.position
			"push", "repel", "pull":
				positions[event.target_id] = event.position
				if event.has("recoil_position"):
					positions[event.unit_id] = event.recoil_position
			"swap":
				positions[event.unit_id] = event.position
				positions[event.target_id] = event.target_position
	return expected


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(error: String) -> void:
	if not error.is_empty():
		failures.append(error)
	if failures.is_empty():
		print("PASS: stock rescue Harpooner; captures in " + output)
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
