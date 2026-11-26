extends "res://tests/support/scene_fixture.gd"

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/smith_converted_forecast_scene_test.gd
## This checks control metadata and forecast behavior, not visual legibility.
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
var rules := Rules.new()
var sounds: Array = []


func _run() -> void:
	root.size = VIEWPORT_SIZE
	viewport.size = VIEWPORT_SIZE
	root.add_child(viewport)
	await _launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	var service := scene.find_child("SoundEffects", true, false)
	if service == null or not service.has_signal("sound_requested"):
		_check(false, "Battle exposes sound dispatch")
		_finish()
		return
	service.sound_requested.connect(_sound_requested)
	await _buffer()
	await _recall()
	await _ordinary_blast()
	_finish()


func _opening(party: Array, slots: Array) -> Dictionary:
	var defs: Dictionary = Catalog.read_default().duplicate(true)
	defs.characters.test_raider = defs.characters.grunt.duplicate(true)
	defs.characters.test_raider.behavior = "hold"
	defs.characters.skeleton.behavior = "hold"
	var habits: Dictionary = Catalog.profile(defs, str(party[2])).habits.duplicate()
	habits.order_hold = "hold"
	defs.characters[party[2]].habits = habits
	defs.characters[party[2]].default_order = "order_hold"
	defs.encounters.smith_conversion_fixture = {"board": "road", "seed": 7,
		"party_slots": slots,
		"placements": [{"id": "test_raider", "character": "test_raider", "at": [6, 3]}]}
	defs.missions.smith_conversion_fixture = defs.missions.shield_wall.duplicate(true)
	defs.missions.smith_conversion_fixture.encounter = "smith_conversion_fixture"
	defs.missions.smith_conversion_fixture.erase("default_party")
	var state: Dictionary = Rules.open_mission(defs, "smith_conversion_fixture", party)
	_check(not state.is_empty(), "Test-owned conversion battle opens")
	return state


func _mount(state: Dictionary) -> void:
	scene.set("_opening_state", state.duplicate(true))
	# Remove the previous fixture's selected hero before replacing its battle.
	scene.set("_actor_id", "")
	scene.call("_show_battle", state)
	await process_frame
	await process_frame
	sounds.clear()


func _buffer() -> void:
	var state := _opening(["blacksmith", "alchemist", "healer"], [[1, 1], [2, 1], [3, 1]])
	if state.is_empty():
		return
	_unit(state, "healer").hp -= 2
	# Select a seed where the potion and acid pools really differ, so checking
	# the displayed locked reaction distinguishes the two recipes.
	var found := false
	var expected := {}
	for seed_value in range(1, 1000):
		state.dose_seed = seed_value
		var context: Dictionary = rules.state_before_action(state, "alchemist")
		var converted: Dictionary = rules.dose_forecast(context, "alchemist", "alchemist_acid")
		var ordinary: Dictionary = rules.dose_forecast(state, "alchemist", "alchemist_acid")
		if not converted.is_empty() and converted.get("category") == "beneficial" \
				and converted.get("reaction_id") != ordinary.get("reaction_id"):
			found = true
			expected = converted
			break
	_check(found, "Fixture distinguishes potion-odds Buffer reaction from Acid reaction")
	if not found:
		return
	await _mount(state)
	if not await driver.select_actor("alchemist"):
		_check(false, "Select Mixologist: " + driver.error)
		return
	var buffer_label := _command_label(state, "alchemist", "alchemist_acid")
	_check(buffer_label.to_lower().contains("buffer"),
		"The command label identifies the converted Buffer form: " + buffer_label)
	_check(_marks_contain(state, "healer") and _marks_contain(state, "alchemist")
		and not _marks_contain(state, "test_raider"),
		"Selection marks the friendly Buffer recipients, not the Acid foe")
	var locked := "Locked dose · %s · %s" % [str(expected.category).capitalize(), str(expected.description)]
	_check(_visible_text_contains(locked), "Visible locked-dose metadata shows exact Buffer reaction: " + locked)
	_check(scene.battle_snapshot() == state and sounds.is_empty(),
		"Selecting and reading the Buffer dose are silent and leave battle and RNG unchanged")
	# The wounded ally sits on a cell shared by the potion and the converted
	# Buffer; the floating choices must name the converted form per target.
	var board := _node("BridgeBoard") as Control
	var healer_cell: Vector2i = _unit(state, "healer").position
	await driver._click(board.get_global_transform_with_canvas() * board.cell_center(healer_cell))
	var choice_rows: Array = scene.get("_storybook_page").get("_target_rows")
	var offered_buffer := ""
	for row: Dictionary in choice_rows:
		if str(row.get("id")) == "alchemist_acid::healer":
			offered_buffer = str(row.get("label", ""))
	_check(choice_rows.size() == 2 and offered_buffer.to_lower().contains("buffer"),
		"The floating choices name the converted Buffer recipient: " + offered_buffer)
	if offered_buffer.is_empty() or not await driver._press_choice_button("alchemist_acid", "healer"):
		_check(false, "Select the Buffer recipient: " + driver.error)
		return
	var staged_buffer: Dictionary = scene.get("_planned_state").get("overrides", {}).get("alchemist", {})
	_check(staged_buffer.get("ability_id") == "alchemist_acid" and staged_buffer.get("target_id") == "healer",
		"Choosing the Buffer button stages the converted Acid on the recipient")
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(_fitted_before_action(plan, "alchemist"), "Earlier standing Smith fits Mixologist before Buffer")
	var reactions: Array = plan.get("events", []).filter(func(e: Dictionary):
		return e.get("type") == "alchemy_reaction" and e.get("target_id") == "healer")
	_check(reactions.size() == 1 and reactions[0].get("reaction_id") == expected.get("reaction_id"),
		"Forecast applies the same locked Buffer reaction to the selected friendly recipient")
	_check(_unit(plan.get("result", {}), "healer").hp > _unit(state, "healer").hp,
		"Forecasted Buffer heals the injured friendly recipient")
	_check(scene.battle_snapshot() == state and sounds.is_empty(), "Staging Buffer is silent and immutable")
	await _press("Commit")
	_check(scene.battle_snapshot() == plan.get("result"), "Buffer commit equals its forecast")


func _recall() -> void:
	var state := _opening(["blacksmith", "necromancer", "healer"], [[1, 1], [2, 1], [0, 3]])
	if state.is_empty():
		return
	var summon: Dictionary = rules.preview(state, "necromancer", "summon_skeleton", "3,1")
	if not summon.get("valid", false):
		_check(false, "Recall fixture can first create its existing skeleton")
		return
	state = rules.apply_plan(state, summon)
	var existing: Array = state.units.filter(func(u: Dictionary): return u.get("character_id") == "skeleton")
	if existing.size() != 1:
		_check(false, "Recall starts with a full living skeleton slot")
		return
	var id: String = existing[0].id
	existing[0].position = Vector2i(5, 3)
	_check(rules.targets(state, "necromancer", "summon_skeleton").is_empty(),
		"Unfitted full-cap Crypter cannot summon a second skeleton")
	await _mount(state)
	if not await driver.select_actor("necromancer"):
		_check(false, "Full-cap Crypter can be selected: " + driver.error)
		return
	var recall_label := _command_label(state, "necromancer", "summon_skeleton")
	_check(recall_label.to_lower().contains("recall"),
		"The command label identifies the converted Recall form: " + recall_label)
	_check(Vector2i(3, 1) in _marked_cells(),
		"Recall marks an open neighboring landing despite the full slot")
	if not await driver.command("necromancer", "summon_skeleton", "3,1"):
		_check(false, "Full-cap Crypter stages enabled Recall from the board: " + driver.error)
		return
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(_fitted_before_action(plan, "necromancer"), "Earlier standing Smith fits Crypter before Recall")
	_check(_unit(plan.get("result", {}), id).get("position") == Vector2i(3, 1),
		"Forecast recalls the existing skeleton to the selected tile")
	_check(scene.battle_snapshot() == state and sounds.is_empty(), "Recall preview is silent and immutable")
	await _press("Commit")
	_check(scene.battle_snapshot() == plan.get("result"), "Recall commit equals forecast")


func _ordinary_blast() -> void:
	var state := _opening(["blacksmith", "wizard", "healer"], [[1, 1], [2, 1], [0, 3]])
	if state.is_empty():
		return
	await _mount(state)
	if not await driver.select_actor("wizard"):
		_check(false, "Caster can be selected: " + driver.error)
		return
	var blast_label := _footer_label("wizard_blast")
	_check(blast_label.to_lower().contains("blast") and blast_label.to_lower().contains("ordinary"),
		"The automatic footer button names the ordinary Blast fallback: " + blast_label)
	if not await driver.command("wizard", "wizard_blast", ""):
		_check(false, "No-patient footer button stages the ordinary Blast fallback: " + driver.error)
		return
	var plan: Dictionary = (scene.get("_plan") as Dictionary).duplicate(true)
	_check(_fitted_before_action(plan, "wizard"), "Earlier standing Smith fits Caster before Blast fallback")
	_check(plan.get("events", []).any(func(e: Dictionary):
		return e.get("type") == "fitted_fallback" and e.get("unit_id") == "wizard"),
		"Forecast explicitly records the ordinary fitted fallback")
	var damage: Array = plan.get("events", []).filter(func(e: Dictionary):
		return e.get("type") == "damage" and e.get("source_id") == "wizard")
	_check(damage.size() == 1, "Ordinary Blast forecasts its actual damage victim")
	if damage.size() == 1:
		await _press("ForecastDetails")
		_check(_visible_text_contains(str(damage[0].get("text", ""))),
			"Visible forecast names the actual ordinary Blast damage and victim")
		_check(_unit(plan.get("result", {}), str(damage[0].get("target_id", ""))).get("hp", 0)
			< _unit(state, str(damage[0].get("target_id", ""))).get("hp", 0),
			"Forecast actually damages the named victim rather than healing")
	_check(scene.battle_snapshot() == state and sounds.is_empty(), "Fallback forecast is silent and immutable")
	await _press("Commit")
	_check(scene.battle_snapshot() == plan.get("result"), "Fallback commit equals forecast")


## The label the real controls derive their text from: the form the actor
## will actually use as their own turn starts.
func _command_label(state: Dictionary, actor: String, ability: String) -> String:
	var context: Dictionary = rules.state_before_action(state, actor)
	return str(rules.command_ability(context, actor, ability).get("label", ""))


## The automatic footer button's actual label from the rendered rows.
func _footer_label(ability: String) -> String:
	var rows: Array = scene.get("_storybook_page").get("_automatic_action_rows")
	for row: Dictionary in rows:
		if str(row.get("id")) == ability:
			return str(row.get("label", ""))
	return ""


func _marked_cells() -> Array:
	var board := _node("BridgeBoard") as Control
	if board == null:
		return []
	return (board.get("_overlay") as Dictionary).get("targets", [])


func _marks_contain(state: Dictionary, id: String) -> bool:
	var unit := _unit(state, id)
	if unit.is_empty():
		return false
	return unit.get("position") in _marked_cells()


func _visible_text_contains(text: String) -> bool:
	if text.is_empty():
		return false
	for node in scene.find_children("*", "Control", true, false):
		if node.is_visible_in_tree() and ((node is Label and text in node.text) or text in node.tooltip_text):
			return true
	return false


func _fitted_before_action(plan: Dictionary, actor: String) -> bool:
	var events: Array = plan.get("events", [])
	var fit := -1
	var action := -1
	for index in events.size():
		var event: Dictionary = events[index]
		if event.get("type") == "fit" and event.get("unit_id") == "blacksmith" and event.get("target_id") == actor:
			fit = index
		if event.get("resolved_action", {}).get("unit_id") == actor:
			action = index
	return fit >= 0 and action > fit


func _sound_requested(kind: String, unit_id: String, ability_id: String, cue_id: String, gain: float) -> void:
	sounds.append([kind, unit_id, ability_id, cue_id, gain])


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}
