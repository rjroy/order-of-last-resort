extends "res://tests/village_outing_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/fixed_outing_victory_test.gd
# See fixed_outing_victory_test.md for the route format and deterministic reward seed.
const ROUTES_PATH := "res://tests/fixed_outing_routes.json"
const REQUIRED_MISSIONS := [
	"explosive_situation", "bridge_is_out", "last_wagon",
	"duelists", "great_sheep_escape", "odd_couple"
]


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES_PATH))
	if not parsed is Dictionary:
		_check(false, "Route file must contain a mission-keyed object")
		_finish()
		return
	var routes: Dictionary = parsed
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default()
	var outings: Dictionary = {}
	var seen: Array = []
	for adventure_id in defs.get("adventures", {}):
		var missions: Array = defs.adventures[adventure_id].get("missions", [])
		var matches := 0
		for mission in missions:
			if mission in REQUIRED_MISSIONS:
				matches += 1
				seen.append(mission)
		if matches > 0:
			_check(matches == 3 and missions.size() == 3,
				str(adventure_id) + " contains exactly three new missions")
			outings[adventure_id] = missions
	_check(outings.size() == 2, "Catalog declares two new outings")
	for id in REQUIRED_MISSIONS:
		_check(seen.count(id) == 1, id + " occurs in exactly one new outing")
		_check(routes.has(id), "Route file contains " + id)
	for id in routes:
		_check(id in REQUIRED_MISSIONS, "Unexpected route " + str(id))
	if not failures.is_empty():
		_finish()
		return

	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	for adventure_id in outings:
		await _exercise_outing(str(adventure_id), outings[adventure_id], routes)
	_finish()


func _exercise_outing(adventure_id: String, missions: Array, routes: Dictionary) -> void:
	print("OUTING %s: begin %s" % [adventure_id, missions])
	var first: Dictionary = routes[missions[0]]
	var party: Array = first.get("party", [])
	if party.size() != 3 or party[0] == party[1] or party[0] == party[2] or party[1] == party[2]:
		_check(false, adventure_id + ": first mission route needs three distinct party members in deployment order")
		return
	await _launch(PackedStringArray())
	if scene.current_screen() != "guild":
		_check(false, adventure_id + ": normal launch must open guild")
		return
	if not await _select_id(_node("AdventureSelect") as OptionButton, adventure_id):
		return
	# Recruit in reverse and explicitly reorder through the guild controls.
	for i in range(party.size() - 1, -1, -1):
		await _press("Recruit_" + str(party[i]))
	await _press("PartyEarlier_" + str(party[0]))
	await _press("PartyEarlier_" + str(party[0]))
	await _press("PartyEarlier_" + str(party[1]))
	if scene.selected_recruits() != party:
		_check(false, adventure_id + ": guild must select and order " + str(party))
		return
	await _press("StartAdventure")
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = 12345
	var outing: Dictionary = scene.get("_run")
	outing.reward_rng_state = reward_rng.state
	for index in missions.size():
		var id := str(missions[index])
		print("MISSION %s / %s: begin" % [adventure_id, id])
		var route: Dictionary = routes[id]
		if scene.current_screen() != "battle":
			_check(false, id + ": expected battle, got " + scene.current_screen())
			return
		var opening: Dictionary = scene.battle_snapshot()
		if opening.get("mission_id") != id or opening.get("party") != party:
			_check(false, id + ": deployed mission and party must match catalog order and guild selection")
			return
		if not await _play_route(adventure_id, id, route):
			print("MISSION %s / %s: route failed" % [adventure_id, id])
			return
		var expected := "result" if index == missions.size() - 1 else "debrief"
		if scene.current_screen() != expected:
			_check(false, id + ": victory must reach " + expected + ", got " + scene.current_screen())
			return
		if expected == "debrief":
			var hero := str(route.get("reward", ""))
			if hero not in party:
				_check(false, id + ": route must name a party member for its reward")
				return
			var reward := _node("Reward_" + hero) as BaseButton
			if reward == null or reward.disabled or not reward.is_visible_in_tree():
				_check(false, id + ": recorded reward is not offered to " + hero)
				return
			await _press("Reward_" + hero)
			await _press("ContinueAdventure")
			print("MISSION %s / %s: victory, reward=%s" % [adventure_id, id, hero])
		else:
			var outcome := _node("RunOutcome")
			_check(outcome != null and outcome.get_meta("outcome", "") == "victory",
				adventure_id + ": final result is victory")
			await _press("ReturnToGuild")
			_check(scene.current_screen() == "guild" and scene.selected_recruits().is_empty(),
				adventure_id + ": victory returns to a reset guild")
			print("OUTING %s: completed; screen=%s" % [adventure_id, scene.current_screen()])


func _play_route(adventure_id: String, id: String, route: Dictionary) -> bool:
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
		var context := "%s / %s route_round=%d battle_round=%s actor=%s ability=%s target=%s" % [
			adventure_id, id, step_index + 1, scene.battle_snapshot().get("round", "?"),
			command.get("actor", ""), command.get("ability", ""), command.get("target", "")]
		for actor in step.get("orders", {}):
			var picker: OptionButton
			for candidate in scene.find_children("*", "OptionButton", true, false):
				if candidate.get_meta("actor_id", "") == actor:
					picker = candidate
					break
			if not await _select_route_id(picker, str(step.orders[actor]), context + " order_actor=" + str(actor)):
				return false
		var before: Dictionary = scene.get("_state").duplicate(true)
		if not command.is_empty():
			if not await _select_route_id(_node("ActorSelect") as OptionButton, str(command.get("actor", "")), context):
				return false
			if not await _select_route_id(_node("AbilitySelect") as OptionButton, str(command.get("ability", "")), context):
				return false
			if command.has("target") and not await _select_route_id(_node("TargetSelect") as OptionButton, str(command.target), context):
				return false
			await _press("Preview")
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
	return true


func _select_route_id(picker: OptionButton, id: String, context: String) -> bool:
	if await _select_id(picker, id):
		return true
	var name := str(picker.name) if picker != null else "<missing>"
	_check(false, "%s picker=%s requested=%s available=%s" % [context, name, id, _choice_ids(picker)])
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
	# Adventure commits add this marker only after the predicted terminal round.
	left_state.erase("_terminal_commit")
	right_state.erase("_terminal_commit")
	return left_content == right_content and left_state == right_state
