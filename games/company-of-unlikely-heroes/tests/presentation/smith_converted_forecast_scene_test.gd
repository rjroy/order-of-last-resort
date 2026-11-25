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
	if not await _action("Acid", "Buffer Solution"):
		return
	var ids: Array = (scene.get("_targets") as Array).map(func(c: Dictionary): return c.id)
	_check("healer" in ids and "alchemist" in ids and "test_raider" not in ids,
		"Buffer picker offers friendly recipients, not the Acid foe")
	var locked := "Locked dose · %s · %s" % [str(expected.category).capitalize(), str(expected.description)]
	_check(_visible_text_contains(locked), "Visible locked-dose metadata shows exact Buffer reaction: " + locked)
	_check(scene.battle_snapshot() == state and sounds.is_empty(),
		"Opening and reading Buffer aim are silent and leave battle and RNG unchanged")
	if not await driver.target("healer"):
		_check(false, "Select Buffer recipient: " + driver.error)
		return
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
	if not await driver.select_actor("necromancer") or not await _action("Summon Skeleton", "Recall Skeleton"):
		_check(false, "Full-cap Crypter offers enabled Recall in the real picker")
		return
	var choices: Array = (scene.get("_targets") as Array).map(func(c: Dictionary): return c.id)
	_check("3,1" in choices, "Recall offers an open neighboring landing despite the full slot")
	if not await driver.target("3,1"):
		_check(false, "Select Recall landing: " + driver.error)
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
	if not await driver.select_actor("wizard") or not await _action("Blast", "ordinary"):
		_check(false, "No-patient picker explicitly offers ordinary Blast fallback")
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


func _action(source_label: String, required_label: String) -> bool:
	var menu := scene.find_child("Actions", true, false) as MenuButton
	if menu != null and menu.is_visible_in_tree() and not menu.disabled:
		var popup := menu.get_popup()
		for index in popup.item_count:
			var text := popup.get_item_text(index)
			if text.begins_with(source_label):
				_check(required_label.to_lower() in text.to_lower(),
					"Picker identifies %s form: %s" % [required_label, text])
				if not popup.is_item_disabled(index):
					popup.id_pressed.emit(popup.get_item_id(index))
					await process_frame
					return true
	_check(false, "Enabled %s action is present" % source_label)
	return false


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
