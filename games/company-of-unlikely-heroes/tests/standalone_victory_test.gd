extends "res://tests/support/scene_fixture.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/standalone_victory_test.gd
# Replay each recipe independently, with a fresh company.
const ROUTES_PATH := "res://tests/standalone_victory_routes.json"
const REQUIRED_MISSIONS := [
	"shield_wall", "explosive_situation", "unfortunate_healer", "duelists", "last_one_standing",
	"wrong_side_of_the_door", "cowardly_captain", "bridge_is_out", "last_wagon",
	"great_sheep_escape", "odd_couple", "dont_wake_the_giant", "hold_the_line",
	"unfortunate_ritual", "mirror_company"
]


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES_PATH))
	if not parsed is Dictionary:
		_check(false, "Route file must contain a mission-keyed object")
		_finish()
		return
	var routes: Dictionary = parsed
	_check(routes.size() == REQUIRED_MISSIONS.size(), "Route file contains exactly the required missions")
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	for id in REQUIRED_MISSIONS:
		if not routes.has(id):
			_check(false, "Route file contains " + id)
			continue
		var route: Dictionary = routes[id]
		var party: Array = route.get("party", [])
		if party.size() != 3:
			_check(false, id + ": standalone route needs a party")
			continue
		await _launch(PackedStringArray(["--mission=" + id, "--party=" + ",".join(party)]))
		if scene.current_screen() != "battle":
			_check(false, id + ": standalone launch opens battle")
			continue
		var opening: Dictionary = scene.battle_snapshot()
		_check(opening.get("mission_id") == id and opening.get("party") == party,
			id + ": selected mission and party deploy")
		if await _play_route(id, route):
			_check(scene.get("_state").get("outcome") == "victory", id + ": route wins")
	_finish()


func _play_route(id: String, route: Dictionary) -> bool:
	var rounds: Array = route.get("rounds", [])
	if rounds.is_empty():
		_check(false, id + ": winning rounds are not populated")
		return false
	for step_index in rounds.size():
		var step: Variant = rounds[step_index]
		if scene.current_screen() != "battle" or not step is Dictionary:
			_check(false, id + ": route has an extra or malformed round")
			return false
		var command: Dictionary = step.get("command", {})
		var context := "%s route_round=%d battle_round=%s actor=%s ability=%s target=%s" % [
			id, step_index + 1, scene.battle_snapshot().get("round", "?"),
			command.get("actor", ""), command.get("ability", ""), command.get("target", "")]
		for actor in step.get("orders", {}):
			if not await driver.order(str(actor), str(step.orders[actor])):
				_check(false, context + " " + driver.error)
				return false
		var before: Dictionary = scene.get("_state").duplicate(true)
		if not command.is_empty():
			if not await driver.command(str(command.get("actor", "")), str(command.get("ability", "")), str(command.get("target", ""))):
				_check(false, context + " " + driver.error)
				return false
		var plan: Dictionary = scene.get("_plan")
		if not plan.get("valid", false) or not _same_state(scene.get("_state"), before):
			_check(false, id + ": forecast must be valid and leave committed state unchanged")
			return false
		var forecast: Dictionary = plan.get("result", {}).duplicate(true)
		var commit := _node("Commit") as BaseButton
		if commit == null or commit.disabled or not commit.is_visible_in_tree():
			_check(false, id + ": forecast must enable Commit")
			return false
		await _press("Commit")
		if not _same_state(scene.get("_state"), forecast):
			_check(false, id + ": committed round must match forecast")
			return false
		if forecast.get("outcome") == "victory":
			_check(scene.get("_state").get("_terminal_commit", false),
				id + ": victory must be committed, not merely forecast")
			_check(step_index == rounds.size() - 1, id + ": route must end on its winning round")
			return true
		if forecast.get("outcome") != "ongoing":
			_check(false, id + ": route ended without victory")
			return false
	_check(false, id + ": route ended before victory")
	return false


func _same_state(left: Dictionary, right: Dictionary) -> bool:
	if not left.has("catalog") or not right.has("catalog"):
		return false
	var left_content: Dictionary = left.catalog.defs
	var right_content: Dictionary = right.catalog.defs
	var left_state := left.duplicate()
	var right_state := right.duplicate()
	left_state.erase("catalog")
	right_state.erase("catalog")
	# Commits add this marker only after the predicted terminal round.
	left_state.erase("_terminal_commit")
	right_state.erase("_terminal_commit")
	return left_content == right_content and left_state == right_state


func _finish() -> void:
	if failures.is_empty():
		print("PASS: standalone mission victories")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
