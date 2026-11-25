extends "res://tests/support/scene_fixture.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/journeys/commission_finale_scene_test.gd
# Every fixture encounter has one adjacent, one-HP opponent. Battles are still
# won through the normal command editor and committed round, not state edits.
const PARTY := ["healer", "knight", "bard"]
const BOARD_SEED := 147258
const TERMINAL_EVENT := "The last opponent yielded. "
var fixture_path := "user://commission_finale_catalog_%d.json" % OS.get_process_id()
var profile_path := "user://commission_finale_profile_%d.json" % OS.get_process_id()


func _run() -> void:
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default().duplicate(true)
	var mission: Dictionary = defs.missions.shield_wall.duplicate(true)
	mission.encounter = "finale_test_encounter"
	defs.encounters.finale_test_encounter = {
		"board": "frontier_field", "party_slots": [[1, 1], [1, 2], [1, 3]],
		"placements": [{"id": "grunt_1", "character": "grunt", "at": [2, 2]}]
	}
	defs.characters.grunt.max_hp = 1
	defs.mission_reports = {}
	defs.mission_kinds = {}
	for kind_index in 4:
		var kind := "finale_kind_%d" % kind_index
		defs.mission_kinds[kind] = {"label": kind, "descriptors": ["Hint " + kind]}
		for index in 3:
			var id := "finale_transit_%d_%d" % [kind_index, index]
			defs.missions[id] = mission.duplicate(true)
			defs.missions[id].title = id
			defs.mission_reports[id] = {"kind": kind, "descriptors": ["Report " + id]}
	for index in 8:
		var id := "finale_destination_%d" % index
		defs.missions[id] = mission.duplicate(true)
		defs.missions[id].title = "Destination %d: " % index + "The far wall beyond the lantern road. ".repeat(87)
		defs.missions[id].objective.victory_event = TERMINAL_EVENT.repeat(85)
		defs.mission_reports[id] = {
			"kind": "finale_kind_%d" % (index % 4),
			"descriptors": ["Report " + id], "destination_descriptors": ["Contract " + id]
		}
	var errors: PackedStringArray = catalog.validate(defs)
	_check(errors.is_empty(), "Fixture catalog validates: " + str(errors))
	if not errors.is_empty():
		_cleanup()
		return
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Fixture catalog can be written")
		_cleanup()
		return
	file.store_string(JSON.stringify(defs))
	file.close()
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	container.scale = Vector2(0.5, 0.5)
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	for offer_index in [0, 2]:
		await _journey(defs, offer_index)
	_cleanup()


func _journey(defs: Dictionary, offer_index: int) -> void:
	var store = load("res://guild/guild_profile.gd")
	store.create(profile_path, "Finale Test", BOARD_SEED)
	var previous: Dictionary = store.load_profile(profile_path)
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(fixture_path)]))
	scene.configure_profile_path(profile_path)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if scene.current_screen() != "commissions":
		_check(false, "Fixture launches commission board")
		return
	await _press("Commission_%d" % offer_index)
	for id in PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	var run: Dictionary = scene.get("_run")
	var length := int(run.get("mission_count", 0))
	var destination := str(run.get("destination_id", ""))
	var label := "%d-mission journey" % length
	_check(length == (5 if offer_index == 0 else 10), label + ": selected length")
	if not defs.missions.has(destination):
		_check(false, label + ": destination is known")
		return
	var title := str(defs.missions[destination].title)
	for step in length:
		if step < length - 1:
			if scene.current_screen() != "routes":
				_check(false, label + ": transit %d shows route cards" % step)
				return
			run = scene.get("_run")
			if step == length - 2:
				for index in 2:
					var card := _node("Route_%d" % index) as BaseButton
					_check(card != null and card.is_visible_in_tree()
						and _card_text(card.get_parent()).to_lower().contains(title.to_lower()),
						label + ": penultimate card %d names destination" % index)
			await _press("Route_0")
		if scene.current_screen() != "battle":
			_check(false, label + ": stage %d starts battle, got %s" % [step, scene.current_screen()])
			return
		if step == length - 1:
			_check(scene.battle_snapshot().get("mission_id") == destination,
				label + ": final battle is the known destination")
			_check(_node("Route_0") == null and _node("Route_1") == null,
				label + ": no final fake fork")
		await _play_battle(str(scene.battle_snapshot().get("mission_id", "")))
		if step == length - 1:
			_check(scene.current_screen() == "result", label + ": destination victory reaches result")
			if scene.current_screen() != "result":
				return
			var outcome := _node("RunOutcome")
			_check(outcome != null and outcome.get_meta("outcome", "") == "victory",
				label + ": result is victory")
			run = scene.get("_run")
			_check(run.get("reward_offers", []).is_empty(), label + ": no completion payout")
			_check(_node("Reward_" + PARTY[0]) == null, label + ": no completion reward UI")
			for frame in 3:
				await process_frame
			var heading := _node("ResultMissionTitle") as Label
			_check(heading != null and heading.text == title and heading.accessibility_name == title
				and heading.tooltip_text == title and heading.get_visible_line_count() <= 2 and _reachable(heading),
				label + ": a long authored title stays bounded with full accessible text")
			var copy := _node("ResultMissionText") as Label
			var scroll := _node("ResultDetailsScroll") as ScrollContainer
			_check(copy != null and copy.text == TERMINAL_EVENT.repeat(85)
				and scroll != null and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
				label + ": complete authored ending remains scrollable")
			_check(_node("ReceiptRoad") == null and _node("ResultMissionArt") == null,
				label + ": custom ending does not claim a stock payout or borrow stock mission art")
			var leave := _node("ReturnToGuild") as Button
			_check(_reachable(leave) and leave.has_focus(), label + ": long title and ending keep focused return on screen")
			if leave == null or not leave.has_focus():
				return
			for pressed in [true, false]:
				var key := InputEventKey.new()
				key.keycode = KEY_ENTER
				key.pressed = pressed
				viewport.push_input(key, true)
				await process_frame
			_check(scene.current_screen() == "commissions", label + ": return opens commissions, not fixed guild")
			var returned: Dictionary = store.load_profile(profile_path)
			_check(returned.get("points", -1) == 0
				and returned.get("board_generation", -1) == previous.get("board_generation", -1) + 1
				and returned.get("last_receipt", {}).is_empty(),
				label + ": custom return advances the board without credit or receipt")
			return
		if scene.current_screen() != "debrief":
			_check(false, label + ": stage %d victory opens debrief" % step)
			return
		var selected := false
		for id in PARTY:
			var reward := _node("Reward_" + id) as BaseButton
			if reward != null and reward.is_visible_in_tree() and not reward.disabled:
				await _press(str(reward.name))
				selected = true
				break
		if not selected:
			_check(false, label + ": upgrade is available")
			return
		_check(scene.current_screen() == "debrief", label + ": upgrade selection keeps the debrief open")
		if step == length - 2:
			var next := _node("DebriefNextMission") as Label
			_check(next != null and next.text == "Next: " + title and _reachable(next),
				label + ": claimed debrief shows the known destination before leaving")
		else:
			_check(_node("DebriefNextMission") == null, label + ": claimed debrief before a fork shows no next mission")
		await _press("ContinueAdventure")
		if step == length - 2:
			_check(scene.current_screen() == "battle", label + ": final continuation goes directly to destination")


func _card_text(card: Node) -> String:
	var text := ""
	for node in card.find_children("*", "", true, false):
		if (node is Label or node is RichTextLabel or node is BaseButton) and node.is_visible_in_tree():
			text += str(node.text) + "\n"
	return text


func _cleanup() -> void:
	for path in [fixture_path, profile_path]:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
				"Removed test-owned file " + path)
	_finish()
