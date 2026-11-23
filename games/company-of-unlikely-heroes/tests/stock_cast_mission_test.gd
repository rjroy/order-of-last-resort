extends SceneTree
## Graphical stock-cast regression. See stock_cast_mission_test.md.
const Cases = preload("res://tests/support/stock_cast_cases.gd")
const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Driver = preload("res://tests/support/storybook_driver.gd")
const Triggers = preload("res://tests/support/stock_cast_triggers.gd")
const CastCues = preload("res://presentation/cast_cues.gd")
const BridgeBoard = preload("res://bridge_art.gd")

var output := ""
var mission := ""
var actor := ""
var failures: Array[String] = []
var scene: Node
var viewport: SubViewport
var known_ids := {}
var sampled := {}
var checked_ready_ids := {}
var observed := {}
var observed_units := {}
var events_only := false
var inventory := false
var all_integrated := false
var variant := ""
var cases := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	cases = Cases.load_cases()
	if DisplayServer.get_name() == "headless":
		_finish("A graphical renderer is required.")
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty():
			output = arg.trim_prefix("--output=").simplify_path()
		elif arg.begins_with("--mission=") and mission.is_empty():
			mission = arg.trim_prefix("--mission=")
		elif arg.begins_with("--actor=") and actor.is_empty():
			actor = arg.trim_prefix("--actor=")
		elif arg == "--events-only" and not events_only:
			events_only = true
		elif arg == "--inventory" and not inventory:
			inventory = true
		elif arg == "--all-integrated" and not all_integrated:
			all_integrated = true
		elif arg.begins_with("--variant=") and variant.is_empty():
			variant = arg.trim_prefix("--variant=")
		else:
			_finish("Use --mission=<id> --actor=<character_id> --output=<empty directory>.")
			return
	if all_integrated and (not inventory or events_only):
		_finish("--all-integrated requires --inventory and cannot use --events-only.")
		return
	if inventory and (not actor.is_empty() or not variant.is_empty()):
		_finish("Inventory selects a mission, not an actor or variant.")
		return
	if not inventory and not cases.get(mission, {}).has(actor):
		_finish("No registered route for mission %s and character %s." % [mission, actor])
		return
	if not _prepare_output():
		_finish("Output must be a new or empty directory under .lore/local, without symlinks.")
		return
	var defs: Dictionary = Catalog.read_default()
	if not defs.get("missions", {}).has(mission) or (not inventory and not defs.get("characters", {}).has(actor)):
		_finish("Case refers to missing stock mission or character.")
		return
	var case: Dictionary = {} if inventory else cases[mission][actor].duplicate(true)
	if not variant.is_empty():
		if not case.get("variants", {}).has(variant):
			_finish("Unknown variant " + variant)
			return
		case.merge(case.variants[variant], true)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 820)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://main.tscn").instantiate()
	var default_party: Array = defs.missions[mission].get("default_party", [])
	if inventory and default_party.is_empty():
		default_party = ["knight", "healer", "wizard"].slice(0,
			defs.encounters[defs.missions[mission].encounter].get("party_slots", []).size())
	var route: Dictionary = case
	if case.has("fixed_route"):
		var routes: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixed_outing_routes.json"))
		if not routes is Dictionary or not routes.has(case.fixed_route):
			_finish("Missing fixed outing route.")
			return
		route = routes[case.fixed_route]
	var party: Array = case.get("party", route.get("party", default_party))
	# Standalone launches use their real default party. Missions without one need
	# the main scene's battle entry with an explicitly selected stock party.
	var has_default: bool = not defs.missions[mission].get("default_party", []).is_empty()
	var launch_mission := mission if has_default else "goblin_mob"
	scene.configure_launch(PackedStringArray(["--storybook", "--mission=" + launch_mission]))
	scene.configure_profile_path(output.path_join("unused-profile.json"))
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if not has_default:
		if party.is_empty():
			_finish("This mission requires an explicit stock party in its case or route.")
			return
		var opening: Dictionary = Rules.open_mission(defs, mission, party)
		if opening.is_empty():
			_finish("Stock mission and party could not be opened.")
			return
		scene.set("_opening_state", opening.duplicate(true))
		scene.call("_show_battle", opening)
		await process_frame
	elif party != default_party:
		_finish("Standalone case party must match the normal main-scene launch.")
		return
	if scene.current_screen() != "battle":
		_finish("Stock battle did not open.")
		return
	var opening: Dictionary = scene.battle_snapshot()
	_check(opening.get("mission_id") == mission and opening.get("party") == party,
		"Opening mission and party match stock launch")
	var board := scene.find_child("BridgeBoard", true, false)
	if board == null:
		_finish("Battle board unavailable.")
		return
	if inventory:
		await _inventory_check(defs, opening, board)
		_finish("")
		return
	_enumerate(opening)
	_check(known_ids.size() >= int(case.get("minimum_opening", 1)),
		"Opening contains at least %d %s figures; found %s" % [case.get("minimum_opening", 1), actor, known_ids.keys()])
	if known_ids.is_empty() or events_only:
		await _capture("opening.png")
	else:
		await _ready(board, case, "opening")
	var driver = Driver.new(self, scene)
	var rounds: Array = route.get("rounds", []).duplicate(true)
	if route.has("route_ref"):
		var shared: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/support/stock_cast_routes.json"))
		if not shared is Dictionary or not shared.has(route.route_ref):
			_finish("Unknown shared route " + str(route.route_ref))
			return
		rounds = shared[route.route_ref]
	elif rounds.is_empty():
		for round_number in int(route.get("automatic_rounds", 0)):
			rounds.append({})
	for index in rounds.size():
		if scene.current_screen() != "battle":
			break
		_enumerate(scene.battle_snapshot())
		var newly_visible := false
		for unit: Dictionary in board.get("_units"):
			if known_ids.has(unit.get("id")) and not checked_ready_ids.has(unit.get("id")):
				newly_visible = true
		if newly_visible and not events_only:
			await _ready(board, case, "round-%02d" % (index + 1))
		var step: Dictionary = rounds[index]
		for hero in step.get("orders", {}):
			if not await driver.order(str(hero), str(step.orders[hero])):
				_finish("Round %d order: %s" % [index + 1, driver.error])
				return
		var command: Dictionary = step.get("command", {})
		if not command.is_empty() and not await driver.command(str(command.get("actor", "")),
				str(command.get("ability", "")), str(command.get("target", ""))):
			_finish("Round %d command: %s" % [index + 1, driver.error])
			return
		var before: Dictionary = scene.battle_snapshot()
		var plan: Dictionary = scene.get("_plan").duplicate(true)
		if not plan.get("valid", false):
			_finish("Round %d has invalid forecast." % (index + 1))
			return
		_enumerate(plan.get("result", {}))
		var button := scene.find_child("Commit", true, false) as BaseButton
		if button == null or button.disabled or not button.is_visible_in_tree():
			_finish("Round %d cannot commit." % (index + 1))
			return
		button.pressed.emit()
		var committed: Dictionary = scene.get("_state").duplicate(true)
		committed.erase("_terminal_commit")
		_check(committed == plan.get("result"), "Committed state matches the forecast")
		await process_frame
		if scene.current_screen() != "battle":
			var overlay := scene.find_child("TerminalCastReplay", true, false)
			if overlay != null:
				for child in overlay.find_children("*", "", true, false):
					if child.has_method("action_playback_snapshot"):
						board = child
						break
			await _capture("round-%02d-terminal.png" % (index + 1))
		board.set_process(false)
		var matches := []
		var holds := {}
		var group_action := {}
		var group_remaining := 0
		var positions := {}
		for entity: Dictionary in before.get("units", []) + before.get("obstacles", []):
			positions[entity.id] = entity.position
		var events: Array = plan.get("events", [])
		for event_index in events.size():
			var event: Dictionary = events[event_index]
			if event.has("resolved_action"):
				group_action = event.resolved_action
				group_remaining = int(group_action.get("event_count", 1))
			for trigger: Dictionary in case.triggers:
				var id := Triggers.event_actor(trigger, event)
				if known_ids.has(id) and Triggers.matches(trigger, event, before, committed,
						group_action if group_remaining > 0 else {}, positions,
						events.slice(event_index + 1), events.slice(0, event_index)):
					if trigger.has("hold"):
						holds[id] = trigger.hold
					var identity := str(trigger.id) + ":" + id
					if trigger.get("once_per_unit", false) and observed_units.has(identity):
						continue
					observed[trigger.id] = true
					observed_units[identity] = true
					var match_record := {"id": id, "trigger": trigger.id, "clip": trigger.get("clip", "")}
					if match_record not in matches:
						matches.append(match_record)
						print("EVENT round=%d character=%s unit=%s trigger=%s clip=%s" % [
							index + 1, actor, id, trigger.id, trigger.get("clip", "(state only)")])
			Triggers.trace(event, positions)
			group_remaining -= 1
		if not matches.is_empty():
			await _capture("round-%02d-committed-event.png" % (index + 1))
		if not events_only:
			var cues: Array = board.call("action_playback_snapshot")
			for trigger: Dictionary in case.triggers:
				if trigger.has("hold") and trigger.get("clip") != trigger.hold:
					_check(not cues.any(func(cue): return known_ids.has(cue.get("unit_id")) \
						and cue.get("cast_key") == case.get("cast_key") \
						and cue.get("clip") == trigger.hold),
						"Persistent hold %s is not enqueued as an action" % trigger.hold)
			if not matches.is_empty():
				for match_record in matches:
					if match_record.clip.is_empty():
						continue
					_check(cues.any(func(cue): return cue.get("unit_id") == match_record.id \
						and cue.get("cast_key") == case.get("cast_key") \
						and cue.get("clip") == match_record.clip),
						"Committed %s for %s has authored %s cue" % [
							match_record.trigger, match_record.id, match_record.clip])
		if not events_only:
			await _sample_queue(board, index + 1)
		board.call("_process", 30.0)
		board.set_process(false)
		if not events_only:
			_check((board.call("action_playback_snapshot") as Array).is_empty(), "Playback drains before held-pose checks")
			for id in holds:
				await _check_held_figure(board, id, str(holds[id]), index + 1)
	for trigger: Dictionary in case.triggers:
		_check(observed.has(trigger.id), "Stock route committed trigger " + str(trigger.id))
		if not events_only and trigger.has("clip"):
			_check(sampled.has(trigger.clip), "Committed trigger produced queued " + str(trigger.clip) + " clip")
	if not events_only:
		_check(not checked_ready_ids.is_empty(), "At least one requested figure reached a ready checkpoint")
	_check(not FileAccess.file_exists(output.path_join("unused-profile.json")), "No profile was written")
	_finish("")


func _inventory_check(defs: Dictionary, opening: Dictionary, board: Node) -> void:
	var encounter: Dictionary = defs.encounters[defs.missions[mission].encounter]
	var reserve_ids: Array = defs.missions[mission].objective.get("reserve_placements", [])
	var figure_map: Dictionary = board.get("_units_by_id")
	var roles := {}
	await _capture("inventory-opening.png")
	for placement: Dictionary in encounter.placements:
		var id := str(placement.id)
		var is_reserve := id in reserve_ids
		var entities: Array = opening.get("objective", {}).get("reserves", []) if is_reserve \
			else opening.get("units", []) + opening.get("obstacles", [])
		var found := {}
		for entity: Dictionary in entities:
			if entity.get("id") == id:
				found = entity
				break
		var expected_position := Vector2i(int(placement.at[0]), int(placement.at[1]))
		_check(not found.is_empty() and found.get("position") == expected_position,
			"Inventory %s is present at its stock position (reserve=%s)" % [id, is_reserve])
		if placement.has("character"):
			var role := str(placement.character)
			_check(found.get("character_id") == role, "Inventory %s retains character ID %s" % [id, role])
			_check(not figure_map.has(id) if is_reserve else figure_map.has(id),
				"Inventory %s has correct opening board visibility" % id)
			if not is_reserve and figure_map.has(id):
				_check(figure_map[id].get("cell") == expected_position, "Inventory %s is drawn at stock cell" % id)
				if not roles.has(role):
					roles[role] = []
				roles[role].append(id)
			if all_integrated:
				var key := _cast_key_for_role(role)
				_check(not key.is_empty() and not found.is_empty() \
					and CastCues.cast_key_for(opening, found) == key,
					"Inventory %s / %s has integrated stock cast key %s" % [id, role, key])
		else:
			_check(found.get("object_id") == placement.get("object"), "Inventory %s retains object ID" % id)
			var obstacles: Array = board.get("_overlay").get("obstacles", [])
			_check(obstacles.any(func(obstacle): return obstacle.get("id") == id \
				and obstacle.get("position") == expected_position),
				"Inventory object %s appears on the stock board" % id)
		print("INVENTORY mission=%s id=%s role=%s reserve=%s position=%s" % [
			mission, id, placement.get("character", placement.get("object", "")), is_reserve, expected_position])
	if all_integrated:
		for role in roles:
			known_ids.clear()
			for id in roles[role]:
				known_ids[id] = true
			await _ready(board, {"cast_key": _cast_key_for_role(role)}, "inventory-" + role)


func _cast_key_for_role(role: String) -> String:
	for mission_cases in cases.values():
		if mission_cases.has(role):
			return str(mission_cases[role].get("cast_key", ""))
	return role if role in ["harpooner", "ferryman"] else ""


func _enumerate(state: Dictionary) -> void:
	for unit: Dictionary in state.get("units", []):
		if unit.get("character_id") == actor:
			if not known_ids.has(unit.id):
				print("FIGURE character=%s id=%s position=%s" % [actor, unit.id, unit.get("position")])
			known_ids[unit.id] = true


func _ready(board: Node, case: Dictionary, label: String) -> void:
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	await _capture(label + "-ready.png")
	var authored := viewport.get_texture().get_image()
	var cells: Dictionary = board.get("_cells").duplicate(true)
	var units: Array = board.get("_units").duplicate(true)
	var overlay: Dictionary = board.get("_overlay").duplicate(true)
	var fallback: Array = units.duplicate(true)
	var visible := 0
	for unit: Dictionary in fallback:
		if known_ids.has(unit.get("id")):
			visible += 1
			checked_ready_ids[unit.id] = true
			_check(unit.get("cast_key") == case.get("cast_key"), "Figure %s has authored cast binding" % unit.id)
			unit.erase("cast_key")
	_check(visible > 0, "Requested character is present on the rendered board")
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
	_check(changed > 100, "Requested character's visible ready art differs from placeholder")
	board.call("set_render_state", cells, units, overlay)
	board.set_process(false)


func _check_held_figure(board: Node, id: String, hold: String, round_number: int) -> void:
	var figure: Dictionary = board.get("_units_by_id").get(id, {})
	_check(figure.get("cast_hold") == hold, "Committed figure %s holds %s" % [id, hold])
	if figure.get("cast_hold") != hold:
		return
	var cast = board.get("_cast")
	_check(cast != null and cast.clip_for(str(figure.get("cast_key", "")), hold) != null,
		"Committed figure %s has an authored %s atlas clip" % [id, hold])
	if cast == null or cast.clip_for(str(figure.get("cast_key", "")), hold) == null:
		return
	# Compare the live, normally rendered hold with the same board at ready.
	# Force Ready for this subject in the comparison only. Removing the hold
	# would still draw the defeat fallback when wreck and defeat share a clip.
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var held_image := viewport.get_texture().get_image()
	await _capture("round-%02d-%s-%s-held.png" % [round_number, id, hold])
	var cells: Dictionary = board.get("_cells").duplicate(true)
	var units: Array = board.get("_units").duplicate(true)
	var overlay: Dictionary = board.get("_overlay").duplicate(true)
	var ready_units: Array = units.duplicate(true)
	for unit: Dictionary in ready_units:
		if unit.get("id") == id:
			unit["cast_hold"] = "ready"
	board.call("set_render_state", cells, ready_units, overlay)
	board.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	var ready_image := viewport.get_texture().get_image()
	var changed := 0
	var local_origin: Vector2 = board.get("_map_origin") \
		+ board.call("_tile_origin", figure.cell) * float(board.get("_map_scale"))
	var transform: Transform2D = board.get_global_transform_with_canvas()
	var cell_rect := Rect2(transform * local_origin,
		transform.basis_xform(BridgeBoard.TILE * float(board.get("_map_scale")))).abs()
	var pixels := Rect2i(cell_rect).intersection(Rect2i(0, 0, held_image.get_width(), held_image.get_height()))
	for y in range(pixels.position.y, pixels.end.y):
		for x in range(pixels.position.x, pixels.end.x):
			var delta := held_image.get_pixel(x, y) - ready_image.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 4.0 / 255.0:
				changed += 1
	_check(changed > 100, "Live %s held atlas pose for %s visibly differs from its ready pose" % [hold, id])
	board.call("set_render_state", cells, units, overlay)
	board.set_process(false)


func _sample_queue(board: Node, round_number: int) -> void:
	board.set_process(false)
	var cues: Array = board.call("action_playback_snapshot")
	var playback = board.get("_playback")
	for cue: Dictionary in cues:
		if not known_ids.has(cue.get("unit_id")):
			continue
		var clip := str(cue.get("clip", ""))
		var entry = null
		for candidate in playback.get("_entries"):
			if candidate.cue == cue:
				entry = candidate
				break
		if entry == null:
			continue
		board.call("_process", maxf(0.0, -entry.elapsed_ms) / 1000.0 + 0.001)
		if entry.clip != null:
			board.call("_process", maxf(0.0, entry.clip.total_ms * 0.5 - entry.elapsed_ms) / 1000.0)
		board.set_process(false)
		sampled[clip] = true
		print("CUE round=%d unit=%s clip=%s" % [round_number, cue.unit_id, clip])
		await _capture("round-%02d-%s-%s.png" % [round_number, cue.unit_id, clip])
		await _sample_case_detail(board, round_number, entry)


func _sample_case_detail(_board: Node, _round_number: int, _entry: Variant) -> void:
	pass


func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png(output.path_join(name)) == OK, "Saved " + name)


func _prepare_output() -> bool:
	var local := ProjectSettings.globalize_path("res://../../.lore/local").simplify_path()
	if not output.is_absolute_path() or not output.begins_with(local + "/"):
		return false
	var path := local
	for part in output.trim_prefix(local + "/").split("/"):
		path = path.path_join(part)
		var parent := DirAccess.open(path.get_base_dir())
		if parent != null and parent.is_link(path.get_file()):
			return false
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		return false
	var dir := DirAccess.open(output)
	return dir != null and dir.get_files().is_empty() and dir.get_directories().is_empty()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(error: String) -> void:
	if not error.is_empty():
		failures.append(error)
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("%s: %s / %s; captures in %s" % [
			"EVENT FIXTURE PASS (cast unchecked)" if events_only else "PASS", mission, actor, output])
	quit(0 if failures.is_empty() else 1)
