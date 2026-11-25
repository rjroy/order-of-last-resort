extends SceneTree
## Headless: checks the actual rows and marks used by the live board painter.

const AlchemyCases = preload("res://tests/smith_playback_alchemy_cases.gd")
const BorrowedCases = preload("res://tests/smith_playback_borrowed_cases.gd")
const SummonCases = preload("res://tests/smith_playback_performance_summon_cases.gd")
const TacticalCases = preload("res://tests/smith_playback_tactical_cases.gd")
const Driver = preload("res://tests/support/storybook_driver.gd")
const BridgeArt = preload("res://bridge_art.gd")
const Rules = preload("res://rules.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")

var _scene: Node
var _board: BridgeArt
var _driver: Driver
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _open_scene()
	var summon_cases := SummonCases.cases()
	var alchemy := AlchemyCases.cases()
	var dose := _case(alchemy, "alchemist_acid")
	await _test_dose(dose.duplicate(true))
	await _test_second_helping(dose.duplicate(true))
	await _test_replayed_fitted_dose(dose, "alchemist", "heal")
	var medicine := _case(alchemy, "alchemist_potion")
	await _test_replayed_fitted_dose(medicine.duplicate(true), "raider_two", "damage")
	await _test_bomber_projection(medicine)
	await _test_chorus(_case(summon_cases, "bard_take_the_stage"))
	await _test_status(_case(BorrowedCases.cases(), "borrowed_knight_healer_bonk"),
		"keep_your_head_down")
	await _test_status(_case(summon_cases, "inspiring_melody"), "inspired")
	await _test_queued_shield(_case(TacticalCases.cases(), "knight_shield_throw"))
	await _test_recall(_case(summon_cases, "summon_skeleton"))
	var play_dead := _case(summon_cases, "raise_dead")
	await _test_play_dead(play_dead)
	await _test_play_dead_bomber(play_dead)
	await _test_queued_raise(play_dead)
	await _test_two_zombie_lifetimes(play_dead)
	await _test_dosed_zombie_lifetime(play_dead)
	_test_audio_matching()
	await _finish("Smith committed board doses, HP, statuses, shield, undead lifecycles and sound routing")


func _open_scene() -> void:
	_scene = load("res://main.tscn").instantiate()
	_scene.configure_launch(PackedStringArray(["--mission=wrong_side_of_the_door"]))
	root.add_child(_scene)
	await process_frame
	# Assert routing below without leaving live audio streams behind in the
	# headless renderer. Change no saved option.
	(_scene.get("_sound_effects") as Node).set("volume", 0.0)
	var music := _scene.find_child("MusicPlayer", true, false) as AudioStreamPlayer
	music.stop()
	music.stream = null
	_driver = Driver.new(self, _scene)


func _finish(label: String) -> void:
	if is_instance_valid(_scene):
		_scene.free()
	await process_frame
	for failure in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("PASS: " + label)
	quit(int(not _failures.is_empty()))


func _case(cases: Array[Dictionary], id: String) -> Dictionary:
	for example in cases:
		if example.id == id:
			return example
	_check(false, "Missing scene fixture: " + id)
	return {}


func _commit(example: Dictionary) -> Dictionary:
	if example.get("state", {}).is_empty():
		_check(false, "Missing opening state: " + str(example.get("id")))
		return {}
	var state: Dictionary = example.state
	_scene.set("_opening_state", state.duplicate(true))
	_scene.set("_actor_id", "")
	_scene.call("_show_battle", state.duplicate(true))
	await process_frame
	await process_frame
	_board = _scene.get("_board")
	if not await _driver.select_actor(example.actor) or not await _driver.action(example.ability):
		_check(false, _driver.error)
		return {}
	if not str(example.target).is_empty() and not await _driver.target(example.target):
		_check(false, _driver.error)
		return {}
	_check(_board.committed_reaction_marks().is_empty()
		and not _board.committed_visuals_pending(), "Preview does not create committed ink")
	var plan: Dictionary = _scene.get("_plan")
	var button := _scene.find_child("Commit", true, false) as BaseButton
	if not is_instance_valid(button) or button.disabled:
		_check(false, "Commit unavailable for " + example.id)
		return {}
	button.pressed.emit()
	_board.set_process(false)
	_check(_scene.battle_snapshot() == plan.result, "Rule result publishes immediately at commit")
	return plan


func _test_dose(example: Dictionary) -> void:
	if example.is_empty():
		return
	example.state.orders.knight = "order_advance"
	var plan := await _commit(example)
	var event := _event(plan, "alchemy_reaction")
	if event.is_empty():
		return
	var id: String = event.target_id
	var opening := _lookup(example.state.units, id)
	var ending := _lookup(plan.result.units, id)
	_check(opening.position != ending.position, "Dose fixture moves the recipient after delivery")
	_check(_row(id).hp == opening.hp and _board.committed_reaction_marks().is_empty(),
		"Final HP and reaction seal do not show before the dose lands")
	var beat := _reach(example.effective, "impact")
	var actual := _effect(beat, "heal")
	var marks := _board.committed_reaction_marks()
	_check(not actual.is_empty() and _row(id).hp == actual.get("hp_after"),
		"Exact actual dose HP appears at impact")
	_check(marks.size() == 1 and marks[0].position == event.position and marks[0].target_id == id \
			and marks[0].reaction_id == event.reaction_id and marks[0].category == event.category,
		"One committed seal uses the chosen reaction and the impact tile, not the moved final tile")
	_check(_marks("heal").size() == 1 and _marks("heal")[0].target_id == id,
		"Converted primary heal produces one recipient flash")
	_tick(0.4)
	_check(_board.committed_reaction_marks().size() == 1, "Solid seal remains readable during its tail")
	_tick(2.0)
	_check(_board.committed_reaction_marks().is_empty() and _row(id).hp == ending.hp,
		"Seal expires without input and HP settles to the committed state")


func _test_chorus(example: Dictionary) -> void:
	var plan := await _commit(example)
	if plan.is_empty():
		return
	var heals: Array = plan.events.filter(func(event):
		return event.type == "heal" and event.get("unit_id") == "bard" and event.amount > 0)
	_check(heals.size() == 2, "Chorus fixture heals a soloist and one adjacent wounded ally")
	for heal in heals:
		_check(_row(heal.target_id).hp == _lookup(example.state.units, heal.target_id).hp,
			"Chorus patient retains opening HP before the song impact")
	_reach(example.effective, "impact")
	var actual: Array = _marks("heal").map(func(mark): return mark.target_id)
	var expected: Array = heals.map(func(event): return event.target_id)
	actual.sort()
	expected.sort()
	_check(actual == expected, "Chorus flashes exactly the actual patients, not the nearest enemy or full ally")
	for heal in heals:
		_check(_row(heal.target_id).hp == _lookup(plan.result.units, heal.target_id).hp,
			"Chorus patient gains only actually restored HP at the same impact")


func _test_second_helping(example: Dictionary) -> void:
	if example.is_empty():
		return
	for seed_value in range(1, 1000):
		if Reactions.draw(seed_value, false).id == "second_helping":
			_lookup(example.state.units, "alchemist").dose_rng_state = seed_value
			break
	var plan := await _commit(example)
	var reaction := _event(plan, "alchemy_reaction")
	if reaction.is_empty():
		return
	var id: String = reaction.target_id
	var boundary_index := -1
	for index in plan.events.size():
		if plan.events[index].type == "heal" and plan.events[index].get("target_id") == id \
				and "Second Helping" in plan.events[index].text:
			boundary_index = index
	if not _check(reaction.reaction_id == "second_helping" and boundary_index >= 0,
			"Second Helping fixture resolves two actual heal events in separate places"):
		return
	var primary := _effect(_reach(example.effective, "impact"), "heal")
	_check(not primary.is_empty() and _row(id).hp == primary.get("hp_after"),
		"Primary dose impact does not show its queued round-end Second Helping HP")
	var later := _reach_health_effect(boundary_index)
	_check(not later.is_empty() and later.get("hp_before") == primary.get("hp_after") \
			and _row(id).hp == later.get("hp_after"),
		"Second Helping updates displayed HP at its own boundary, not when visuals drain")
	_check(_board.committed_reaction_marks().size() == 1 and _marks("heal").size() <= 1,
		"Round-end HP observation does not duplicate the delivery seal or dose flash")


func _test_replayed_fitted_dose(example: Dictionary, recipient: String, polarity: String) -> void:
	if example.is_empty():
		return
	var opening: Dictionary = example.state
	_lookup(opening.units, "alchemist").upgrades = {"alchemist_keep_the_culture": 1}
	var rules := Rules.new()
	var staged := rules.choose_manual(opening, example.actor, example.ability, example.target)
	var stored := rules.commit_round(staged, rules.preview_round(staged))
	var bottle: Dictionary = _lookup(stored.units, "alchemist").get("bottled_reaction", {})
	if not _check(bottle.get("form") == example.effective and bottle.get("polarity") == polarity,
			"Repeat fixture actually bottled the fitted %s, not a hand-authored dose" % polarity):
		return
	stored.orders.blacksmith = "order_hold"
	var actor := _lookup(stored.units, "alchemist")
	var target := _lookup(stored.units, recipient)
	if polarity == "heal":
		target.hp = 1
	else:
		target.position = actor.position + Vector2i.UP
		target.hp = target.max_hp
	var result := await _commit({"id": "ordinary_repeat_fitted_" + polarity, "state": stored,
		"actor": "alchemist", "ability": "alchemist_repeat_batch", "target": recipient})
	if result.is_empty():
		return
	_check(_row(recipient).get("hp") == target.hp and _board.committed_reaction_marks().is_empty(),
		"Ordinary Repeat displays no fitted delivery before its impact")
	var beat := _reach("alchemist_repeat_batch", "impact")
	var actual := _effect(beat, polarity)
	var flashes := _marks("heal" if polarity == "heal" else "hit")
	_check(beat.get("branch") == "ordinary" and beat.get("dose", {}).get("delivery_form_id") == bottle.form \
		and not actual.is_empty() and actual.target_id == recipient and _row(recipient).hp == actual.hp_after,
		"Ordinary Repeat applies the stored fitted %s only to its new actual recipient at impact" % polarity)
	_check(flashes.size() == 1 and flashes[0].target_id == recipient,
		"Ordinary Repeat shows exactly the committed fitted %s flash" % polarity)
	var marks := _board.committed_reaction_marks()
	_check(marks.size() == 1 and marks[0].target_id == recipient and marks[0].reaction_id == bottle.id \
		and marks[0].category == bottle.category, "Ordinary Repeat preserves the exact stored reaction")


func _test_bomber_projection(example: Dictionary) -> void:
	if example.is_empty():
		return
	_lookup(example.state.units, example.target).merge({"character_id": "bomber", "hp": 1}, true)
	var ally := _lookup(example.state.units, "knight")
	ally.position = Vector2i(3, 3)
	ally.hp = ally.max_hp
	var plan := await _commit(example)
	if plan.is_empty():
		return
	var detonation_index := -1
	for index in plan.events.size():
		if plan.events[index].get("damage_cause") == "death_blast" \
				and plan.events[index].get("target_id") == ally.id:
			detonation_index = index
	if not _check(detonation_index >= 0, "Bitter Medicine really kills a Bomber next to a different ally"):
		return
	_check(_row(ally.id).get("hp") == ally.hp, "Bomber collateral does not leak from the final board")
	_reach(example.effective, "impact")
	_check(_row(ally.id).get("hp") == ally.hp, "Bitter Medicine hits its recipient before the Bomber blast")
	var actual := _reach_health_effect(detonation_index)
	_check(actual.get("hp_before") == ally.hp and _row(ally.id).get("hp") == actual.get("hp_after"),
		"Collateral updates displayed HP during the real detonation beat")
	_check(not _marks("hit").any(func(mark): return mark.target_id == ally.id),
		"HP projection does not add a second hit effect on top of the existing Bomber lifecycle")


func _test_queued_shield(example: Dictionary) -> void:
	if example.is_empty():
		return
	example.state.orders.knight = "order_advance"
	# Ensure the Knight has to land one step nearer before pickup.
	var rules := Rules.new()
	for unit: Dictionary in example.state.units:
		if rules.entity_profile(example.state, unit.id).team == "enemies" and unit.hp > 0:
			unit.position = Vector2i(6, 3)
	_lookup(example.state.units, example.target).position = Vector2i(5, 1)
	var first := await _commit(example)
	var drop := _event(first, "shield_drop")
	if drop.is_empty():
		return
	var second := _queue_round(first.result)
	var pickup := _event(second, "shield_retrieve")
	if pickup.is_empty():
		return
	var tile: Vector2i = drop.position
	_check(pickup.position == tile and not _lookup(second.result.units, "knight").has("shield_position") \
		and not _row("knight").shield_away and tile not in _board._presentation_shields(),
		"Final rules have no loose shield and the existing equipped shield is shown before Lend")
	_reach(example.effective, "impact")
	_check(_row("knight").shield_away and _board._presentation_shields().count(tile) == 1,
		"Lend impact adds the actual loose shield without an equipped duplicate")
	var land := _reach("move", "motion_land")
	_check(not _effect(land, "shield_retrieve").is_empty() and not _row("knight").shield_away \
		and tile not in _board._presentation_shields(),
		"Knight landing picks up the shield, clearing its ink and restoring the equipped pose")


func _test_status(example: Dictionary, status: String) -> void:
	var plan := await _commit(example)
	if plan.is_empty():
		return
	var grants: Array = plan.events.filter(func(event):
		return event.type == "status" and event.get("status_id") == status \
			and event.get("unit_id") == example.actor and not event.get("consumed", false))
	if not _check(grants.size() == 1, status + ": fixture has an actual single grant"):
		return
	var id: String = grants[0].target_id
	_check(not _row(id).get("tactical_statuses", {}).has(status), status + ": absent before grant")
	_reach(example.effective, "impact")
	_check(_row(id).get("tactical_statuses", {}).has(status), status + ": displayed at committed grant")
	_check(not _row(example.actor).get("guarded", false), status + ": not the reflecting aura")
	if plan.events.any(func(event): return event.type == "status_expired" and event.target_id == id \
			and event.status_id == status):
		var expiry := _reach("", "status")
		_check(not _effect(expiry, "status_expired").is_empty() \
			and not _row(id).get("tactical_statuses", {}).has(status),
			status + ": removed during the actual turn-boundary cue, not at round publication")
	_tick(4.0)
	_check(_row(id).get("tactical_statuses", {}).has(status) \
			== _lookup(plan.result.units, id).get("statuses", {}).has(status),
		status + ": settled mark matches the rules after expiration or persistence")


func _test_recall(example: Dictionary) -> void:
	var plan := await _commit(example)
	var event := _event(plan, "recall")
	if event.is_empty():
		return
	var id: String = event.target_id
	var opening := _lookup(example.state.units, id)
	var before := _row(id)
	_check(_board._presentation_cell(before) == event.from_position and before.hp == opening.hp,
		"Recall keeps the living skeleton on its original tile before the landing")
	_reach(example.effective, "motion_land")
	var after := _row(id)
	_check(_board._presentation_cell(after) == event.position and after.hp == opening.hp \
			and after.cast_key == before.cast_key and _marks("heal").is_empty(),
		"Recall moves the same skeleton at landing without a spawn or heal")


func _test_play_dead(example: Dictionary) -> void:
	var plan := await _commit(example)
	var event := _event(plan, "play_dead")
	if event.is_empty():
		return
	var prior := _row(event.summon_id)
	_check(not prior.is_empty() and prior.hp > 0 and _board._presentation_cell(prior) == event.position \
			and _row(event.target_id).is_empty(),
		"Play Dead keeps the standing zombie alone on its tile before handoff")
	_reach(example.effective, "handoff")
	var body := _row(event.target_id)
	_check(_row(event.summon_id).is_empty() and body.get("hp") == 0 and body.get("label") == "Corpse" \
			and body.get("cell") == event.position and body.get("prone") and body.get("play_dead_corpse") \
			and _marks("hit").is_empty(),
		"At handoff, only the original corpse occupies that cell, without a hit or combat-death caption")
	_tick(4.0)
	_scene.call("_refresh_board")
	var settled := _row(event.target_id)
	_check(settled.get("cell") == event.position and _row(event.summon_id).is_empty(),
		"The handoff leaves a single settled corpse")
	_check(BridgeArt._condition_caption(body, true).is_empty() \
		and BridgeArt._condition_caption(settled, true).is_empty(),
		"The returned corpse does not acquire a FALLEN caption after settling or refreshing")
	var ordinary := settled.duplicate()
	ordinary.erase("play_dead_corpse")
	_check(BridgeArt._condition_caption(ordinary, true) == "FALLEN" \
		and BridgeArt._condition_caption({"hp": 1}, true) == "DOWN",
		"Ordinary corpses and knocked-down living figures retain their condition captions")


func _test_play_dead_bomber(example: Dictionary) -> void:
	example = example.duplicate(true)
	if example.is_empty():
		return
	_lookup(example.state.units, "corpse").character_id = "bomber"
	var plan := await _commit(example)
	var event := _event(plan, "play_dead")
	if event.is_empty():
		return
	_reach(example.effective, "handoff")
	var body := _row(event.target_id)
	_check(body.get("cast_key") == "bomber" and body.get("inert_corpse") \
		and not plan.events.any(func(row): return row.type == "death_blast"),
		"Original Bomber takes the inert corpse path; no detonation is played as a defeat pose")


func _test_queued_raise(example: Dictionary) -> void:
	example = example.duplicate(true)
	for unit: Dictionary in example.get("state", {}).get("units", []):
		if unit.character_id == "zombie":
			unit.hp = 1
	var plan := await _commit(example)
	var dead := _event(plan, "play_dead")
	if dead.is_empty():
		return
	var forecast := _queue_raise(plan.result, example.actor, dead.target_id)
	var summon := _event(forecast, "summon")
	if summon.is_empty():
		return
	# The rules may reuse the retired instance ID. Distinguish the old injured
	# body from the freshly raised one by both occupancy and authored HP.
	_check(summon.hp > 1 and _row(dead.summon_id).get("hp") == 1 and _row(dead.target_id).is_empty(),
		"Queued Raise doesn't replace the injured zombie before the prior handoff")
	_reach(example.effective, "handoff")
	_check(_row(dead.target_id).get("cell") == dead.position and _row(summon.summon_id).is_empty(),
		"Play Dead still hands off to the original corpse even if a queued Raise will consume it")
	_reach("raise_dead", "impact")
	_check(_row(dead.target_id).is_empty() and _row(summon.summon_id).get("cell") == dead.position \
		and _row(summon.summon_id).get("hp") == summon.hp,
		"Raise removes that corpse and reveals the newly raised zombie only at its impact")


func _test_two_zombie_lifetimes(example: Dictionary) -> void:
	example = example.duplicate(true)
	if example.is_empty():
		return
	var other_corpse := _lookup(example.state.units, "enemy")
	var observer := other_corpse.merged({"id": "observer", "position": Vector2i(6, 4)}, true)
	other_corpse.hp = 0
	example.state.units.append(observer)
	var first := await _commit(example)
	var first_dead := _event(first, "play_dead")
	if first_dead.is_empty():
		return
	var raised := _queue_raise(first.result, example.actor, other_corpse.id)
	var summon := _event(raised, "summon")
	if summon.is_empty():
		return
	var second := _queue_raise(raised.result, example.actor, "")
	var second_dead := _event(second, "play_dead")
	if second_dead.is_empty():
		return
	var id: String = first_dead.summon_id
	_check(id == summon.summon_id and id == second_dead.summon_id \
			and first_dead.target_id != second_dead.target_id and first_dead.position != second_dead.position,
		"Two distinct corpses are exercised across a reused zombie instance ID")
	_check(_row(id).get("cell") == first_dead.position and _row(first_dead.target_id).is_empty() \
			and _row(second_dead.target_id).get("cell") == second_dead.position,
		"All three queued actions preserve the first zombie and the second original corpse before playback")
	_reach(example.effective, "handoff")
	_check(_row(id).is_empty() and _row(first_dead.target_id).get("cell") == first_dead.position \
			and _row(second_dead.target_id).get("cell") == second_dead.position,
		"The first handoff presents corpse A, not the second zombie lifetime")
	_reach("raise_dead", "impact")
	_check(_row(id).get("cell") == second_dead.position and not _row(first_dead.target_id).is_empty() \
			and _row(second_dead.target_id).is_empty(),
		"Raise occupies only corpse B's square with the second zombie")
	_reach(example.effective, "handoff")
	_check(_row(id).is_empty() and _row(first_dead.target_id).get("cell") == first_dead.position \
			and _row(second_dead.target_id).get("cell") == second_dead.position \
			and _marks("hit").is_empty(), "The second handoff presents corpse B with no zombie or death flash")
	_check(not (first.events + second.events).any(func(event): return event.type == "death_blast"),
		"Neither voluntary handoff triggers combat death")


func _test_dosed_zombie_lifetime(example: Dictionary) -> void:
	example = example.duplicate(true)
	if example.is_empty():
		return
	var opening: Dictionary = example.state
	var zombie: Dictionary = opening.units.filter(func(unit): return unit.character_id == "zombie")[0]
	var id: String = zombie.id
	zombie.hp = 1
	zombie.max_hp = 6
	_lookup(opening.units, "corpse").max_hp = 10
	var alchemist := _lookup(opening.units, "bard")
	alchemist.merge({"id": "alchemist", "character_id": "alchemist",
		"position": zombie.position + Vector2i.DOWN}, true)
	opening.units.erase(alchemist)
	opening.units.insert(opening.units.find(_lookup(opening.units, "necromancer")), alchemist)
	opening.party = ["blacksmith", "alchemist", "necromancer"]
	opening.orders.erase("bard")
	opening.orders.alchemist = "order_hold"
	for seed_value in range(1, 1000):
		if Reactions.draw(seed_value, false).category == "cosmetic":
			alchemist.dose_rng_state = seed_value
			break
	var dose := await _commit({"id": "injured_zombie_dose", "state": opening, "actor": "alchemist",
		"ability": "alchemist_potion", "target": id})
	if dose.is_empty():
		return
	var retired := _queue_raise(dose.result, "necromancer", "")
	var dead := _event(retired, "play_dead")
	if dead.is_empty():
		return
	var raised := _queue_raise(retired.result, "necromancer", dead.target_id)
	var summon := _event(raised, "summon")
	if summon.is_empty():
		return
	_check(id == dead.summon_id and id == summon.summon_id and summon.hp > 2,
		"Distinct max HP separates the two lives that reuse this zombie ID")
	_check(_row(id).get("hp") == 1 and _row(dead.target_id).is_empty(),
		"Before dose, the old zombie is injured and has no visible corpse duplicate")
	_reach("alchemist_potion", "impact")
	_check(_row(id).get("hp") == 2 and _row(dead.target_id).is_empty(),
		"Ordinary dose updates only the existing zombie and cannot reveal the later corpse")
	_reach("play_dead", "handoff")
	_check(_row(id).is_empty() and _row(dead.target_id).get("cell") == dead.position,
		"Play Dead removes the dosed life and its HP so only the original corpse is drawn")
	_reach("raise_dead", "impact")
	_check(_row(id).get("hp") == summon.hp and _row(id).get("cell") == dead.position \
		and _row(dead.target_id).is_empty(), "The later Raise draws only the new zombie at its own HP")


func _queue_raise(state: Dictionary, actor_id: String, target: String) -> Dictionary:
	return _queue_round(Rules.new().choose_manual(state, actor_id, "raise_dead", target))


func _queue_round(planned: Dictionary) -> Dictionary:
	_scene.set("_planned_state", planned)
	_scene.call("_refresh")
	var forecast: Dictionary = _scene.get("_plan")
	var button := _scene.find_child("Commit", true, false) as BaseButton
	if not _check(not button.disabled, "Next round can commit while the earlier cast is still queued"):
		return {}
	button.pressed.emit()
	_board.set_process(false)
	return forecast


func _test_audio_matching() -> void:
	var heard := []
	_board.set_performance_sound(func(beat: Dictionary) -> bool:
		heard.append("new:%s" % beat.cue_order)
		return beat.cue_order != 2)
	_board.sound_beat.connect(func(kind: String, id: String, _ability: String, _handler: String, _recipe: String):
		heard.append("%s:%s" % [kind, id]))
	_board._dispatch_playback_sound([
		{"kind": "step", "unit_id": "earlier", "ability_id": "move", "handler": "move",
			"recipe": "", "offset": 5.0, "cue_order": 0, "motion_order": 1},
		{"kind": "impact", "unit_id": "fallback", "ability_id": "a", "handler": "attack",
			"recipe": "", "offset": 5.0, "cue_order": 2},
		{"kind": "impact", "unit_id": "claimed", "ability_id": "a", "handler": "attack",
			"recipe": "", "offset": 5.0, "cue_order": 3},
		{"kind": "impact", "unit_id": "unrelated", "ability_id": "a", "handler": "attack",
			"recipe": "", "offset": 5.0, "cue_order": 4}], [
		{"kind": "impact", "offset": 5.0, "cue_order": 2},
		{"kind": "impact", "offset": 5.0, "cue_order": 3}])
	_check(heard == ["step:earlier", "new:2", "impact:fallback", "new:3", "impact:unrelated"],
		"New audio claims only its matched legacy beat, even when other beats share its frame")


func _reach(form: String, kind: String) -> Dictionary:
	var playback = _board.get("_playback")
	for _frame in 1000:
		if not _board.action_playback_pending():
			break
		_tick(0.005)
		for beat: Dictionary in playback.presentation_beats():
			if beat.get("form_id") == form and beat.kind == kind:
				return beat
	_check(false, "No committed %s beat for %s" % [kind, form])
	return {}


func _reach_health_effect(event_index: int) -> Dictionary:
	var playback = _board.get("_playback")
	for _frame in 1000:
		if not _board.action_playback_pending():
			break
		_tick(0.005)
		for beat: Dictionary in playback.presentation_beats():
			for effect: Dictionary in beat.effects:
				if effect.event_index == event_index and effect.has("hp_after"):
					return effect
	_check(false, "Expected an actual HP update at resolved event %d" % event_index)
	return {}


func _tick(delta: float) -> void:
	_board.call("_process", delta)
	_board.set_process(false)


func _marks(kind: String) -> Array:
	return _board.get("_recipient_marks").filter(func(mark): return mark.kind == kind)


func _row(id: String) -> Dictionary:
	return _lookup(_board._presentation_units(), id)


func _lookup(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.id == id:
			return row
	return {}


func _effect(beat: Dictionary, kind: String) -> Dictionary:
	for effect: Dictionary in beat.get("effects", []):
		if effect.kind == kind:
			return effect
	return {}


func _event(plan: Dictionary, kind: String) -> Dictionary:
	for event: Dictionary in plan.get("events", []):
		if event.type == kind:
			return event
	_check(false, "Missing resolved " + kind + " event")
	return {}


func _check(ok: bool, message: String) -> bool:
	if not ok:
		_failures.append("FAIL: " + message)
	return ok
