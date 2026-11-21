extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/adventure_test.gd
# Integration tests use the authored adventure, not test-owned combat tuning.
var failures: Array[String] = []
var adventure: Script
var catalog: Script
var rules: RefCounted
var defs: Dictionary
var route_hostile_attack := false


func _initialize() -> void:
	if not ResourceLoader.exists("res://adventure.gd"):
		failures.append("Missing adventure.gd")
	else:
		adventure = load("res://adventure.gd")
		catalog = load("res://content/catalog.gd")
		rules = load("res://rules.gd").new()
		defs = catalog.read_default()
		_test_selection()
		_test_deployment_and_override()
		_test_pressure()
		_test_invalid_transitions()
		_test_controlled_carry_and_reset()
		_test_authored_patrol_route()
		_test_authored_defeat()
	if failures.is_empty():
		print("PASS: adventure integration")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _start(picks: Array) -> Dictionary:
	return adventure.call("start_adventure", defs, "first_outing", picks)


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _test_selection() -> void:
	for picks in [[], ["knight", "healer"], ["knight", "healer", "wizard", "alchemist"],
			["knight", "knight", "wizard"], ["knight", "healer", "missing"]]:
		_check(_start(picks).is_empty(), "Reject invalid company: %s" % [picks])
	var before := defs.duplicate(true)
	var run := _start(["alchemist", "wizard", "knight"])
	_check(defs == before, "Selection does not mutate definitions")
	_check(run.get("phase") == "ready", "Valid company is ready")
	_check(run.get("party") == ["alchemist", "wizard", "knight"],
		"Company preserves the order in which heroes were picked")
	_check(run.get("mission_ids") == ["bridge_patrol", "company_rescue"], "Mission sequence is ordered")
	_check(run.get("mission", {}).is_empty(), "Ready company is not yet deployed")
	_check(_start(["knight", "healer", "wizard"]).get("phase") == "ready",
		"A second distinct legal company can embark")


func _test_deployment_and_override() -> void:
	for picks in [["wizard", "knight", "alchemist"], ["knight", "healer", "wizard"], ["rogue", "healer", "wizard"], ["necromancer", "healer", "wizard"]]:
		var ready := _start(picks)
		if ready.is_empty():
			_check(false, "Legal company starts before deployment")
			continue
		var before := ready.duplicate(true)
		var run: Dictionary = adventure.call("begin_mission", ready)
		_check(ready == before, "Deployment does not mutate ready run")
		_check(run.get("phase") == "mission", "Deployment enters mission phase")
		var state: Dictionary = run.get("mission", {})
		if state.is_empty():
			_check(false, "Deployment produces a playable mission")
			continue
		var party: Array = picks
		for i in range(3):
			_check(state.units[i].id == party[i], "Units act in chosen company order")
			var slot: Array = defs.encounters[state.encounter_id].party_slots[i]
			_check(state.units[i].position == Vector2i(slot[0], slot[1]),
				"Deployment position follows the same order as actions")
		var forecast: Dictionary = rules.preview_round(state)
		var acted: Array = []
		for event in forecast.get("events", []):
			var actor: String = event.get("unit_id", "")
			if actor in party and actor not in acted:
				acted.append(actor)
		_check(acted == party, "Forecast resolves each hero in chosen order")
		var first: String = party[0]
		var second: String = party[1]
		var ability: String = rules.entity_profile(state, first).abilities[0]
		var second_ability: String = rules.entity_profile(state, second).abilities[0]
		var chosen: Dictionary = rules.choose_manual(state, first, ability, "")
		_check(chosen.get("overrides", {}) == {first: {"ability_id": ability, "target_id": ""}},
			"Hybrid reserves the chosen override")
		var abilities: Array = rules.entity_profile(state, first).abilities
		if abilities.size() > 1:
			var edited: Dictionary = rules.choose_manual(chosen, first, abilities[1], "")
			_check(edited.get("overrides", {}) == {first: {"ability_id": abilities[1], "target_id": ""}},
				"Reserved actor can edit its override without consuming another slot")
		var rejected: Dictionary = rules.choose_manual(chosen, second, second_ability, "")
		_check(rejected == chosen, "Cannot reserve a second actor")
		if not rules.has_method("clear_manual"):
			_check(false, "Rules exposes clear_manual for reassignment")
			continue
		var cleared: Dictionary = rules.call("clear_manual", chosen)
		_check(cleared.get("overrides", {}).is_empty(),
			"Clearing releases the override")
		var reassigned: Dictionary = rules.choose_manual(cleared, second, second_ability, "")
		_check(reassigned.get("overrides", {}) == {second: {"ability_id": second_ability, "target_id": ""}},
			"Released override can be reassigned")
		_check(chosen.get("overrides", {}).has(first), "Reassignment does not mutate prior snapshot")


func _test_pressure() -> void:
	var ready := _start(["knight", "healer", "wizard"])
	if ready.is_empty():
		return
	var run: Dictionary = adventure.call("begin_mission", ready)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		return
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(state == before, "Combat forecast does not mutate the board")
	_check(plan.get("valid", false), "Opening combat forecast is valid")
	var committed: Dictionary = rules.commit_round(state, plan)
	_check(_matches_preview(committed, plan), "Combat commit agrees with forecast")
	var threatened := false
	for event in plan.get("events", []):
		if event.get("type") in ["damage", "move"] and not _entity(state, event.get("unit_id", "")).is_empty():
			var profile: Dictionary = rules.entity_profile(state, event.get("unit_id", ""))
			if profile.get("team") == "enemies":
				threatened = true
	_check(threatened, "Enemies actively move or attack in opening combat")


func _test_invalid_transitions() -> void:
	var ready := _start(["wizard", "healer", "knight"])
	if ready.is_empty():
		return
	var run: Dictionary = adventure.call("begin_mission", ready)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		return
	_check(adventure.call("begin_mission", run) == run, "Cannot deploy over an active mission")
	_check(adventure.call("settle_mission", run, state) == run, "An ongoing mission cannot settle")
	var mistagged := state.duplicate(true)
	mistagged.outcome = "victory"
	mistagged["_terminal_commit"] = true
	_check(adventure.call("settle_mission", run, mistagged) == run,
		"An outcome tag and boolean marker are not a committed victory")
	var forecast: Dictionary = rules.preview_round(state)
	_check(adventure.call("settle_mission", run, forecast.get("result", {})) == run,
		"A forecast is not a committed terminal result")
	_check(adventure.call("return_to_guild", run) == run, "Active adventure cannot be reset as finished")


## Controlled transition fixture: stage terminal boards, then use real round
## commits. The authored-route test must independently play both missions.
func _test_controlled_carry_and_reset() -> void:
	var picks := ["wizard", "healer", "knight"]
	var ready := _start(picks)
	if ready.is_empty():
		_check(false, "Controlled transition company starts")
		return
	var run: Dictionary = adventure.call("begin_mission", ready)
	var state: Dictionary = run.get("mission", {}).duplicate(true)
	if state.is_empty():
		_check(false, "Controlled transition mission deploys")
		return
	for unit in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			unit.hp = 0
	var down := _entity(state, picks[0])
	var injured := _entity(state, picks[1])
	down.hp = 0
	down.statuses = {"knockdown": {"source_id": picks[2]}}
	injured.hp = 3
	injured.statuses = {"knockdown": {"source_id": picks[2]}}
	var plan: Dictionary = rules.preview_round(state)
	var terminal: Dictionary = rules.commit_round(state, plan)
	_check(terminal.get("outcome") == "victory", "Controlled first mission commits victory")
	_check(_entity(terminal, picks[0]).get("hp") == 0, "Controlled fixture contains a downed hero")
	_check(not _entity(terminal, picks[0]).get("statuses", {}).is_empty(),
		"Controlled fixture carries a transient status into the victory")
	_check(_entity(terminal, picks[1]).get("hp") == 3, "Controlled fixture contains a wounded survivor")
	var settled: Dictionary = adventure.call("settle_mission", run, terminal)
	_check(settled.get("phase") == "ready" and settled.get("mission_index") == 1,
		"First victory advances exactly once")
	if settled.get("phase") != "ready":
		return
	_check(settled.get("party") == picks and settled.get("mission", {}).is_empty(),
		"Between missions preserves pick order and clears the old board")
	var debrief: Dictionary = settled.get("last_result", {})
	_check(debrief.get("mission_id") == "bridge_patrol" and debrief.get("outcome") == "victory"
		and not str(debrief.get("text", "")).is_empty(),
		"Debrief retains mission identity, outcome and text without the previous board")
	var debrief_heroes: Dictionary = debrief.get("heroes_by_id", {})
	_check(debrief_heroes.get(picks[0], {}).get("hp") == 0
		and debrief_heroes.get(picks[1], {}).get("hp") == 3,
		"Debrief records pre-recovery HP, not revived carry HP")
	for id in picks:
		var hero: Dictionary = debrief_heroes.get(id, {})
		_check(hero.get("max_hp") == _entity(terminal, id).get("max_hp")
			and not str(hero.get("label", "")).is_empty() and hero.has("knocked_down"),
			"Debrief records maximum HP, label and knockdown state for " + id)
	_check(settled.get("carry_by_id", {}).get(picks[0], {}).get("hp") == 1,
		"Downed hero revives with exactly one HP")
	_check(settled.get("carry_by_id", {}).get(picks[1], {}).get("hp") == 3,
		"Wounded survivor carries exact HP")
	for id in picks:
		_check(settled.get("carry_by_id", {}).get(id, {}).get("order") == terminal.get("orders", {}).get(id),
			"Standing order carries for " + id)
	var second: Dictionary = adventure.call("begin_mission", settled)
	var next: Dictionary = second.get("mission", {})
	_check(second.get("last_result", {}).is_empty(), "Active departure clears previous debrief")
	if next.is_empty():
		_check(false, "Second mission deploys")
		return
	for index in range(picks.size()):
		var id: String = picks[index]
		_check(next.units[index].id == id, "Next mission preserves chosen turn order")
		_check(_entity(next, id).get("statuses", {}).is_empty(), "Next mission clears transient status for " + id)
		_check(_entity(next, id).get("hp") == settled.carry_by_id[id].hp,
			"Next mission deploys carried HP for " + id)
	_check(adventure.call("settle_mission", second, terminal) == second,
		"Cannot reuse a previous mission's terminal result")
	var last := next.duplicate(true)
	for unit in last.units:
		if rules.entity_profile(last, unit.id).get("team") == "enemies":
			unit.hp = 0
	_entity(last, last.objective.subject).position = last.objective.destination
	var final_plan: Dictionary = rules.preview_round(last)
	var final_state: Dictionary = rules.commit_round(last, final_plan)
	_check(final_state.get("outcome") == "victory", "Controlled final mission commits victory")
	var finished: Dictionary = adventure.call("settle_mission", second, final_state)
	_check(finished.get("phase") == "finished" and finished.get("outcome") == "victory",
		"Final victory finishes adventure")
	_check(adventure.call("begin_mission", finished) == finished, "Finished adventure cannot repeat a mission")
	_check_reset(finished, picks, "Victory")

	var failure_run: Dictionary = adventure.call("begin_mission", _start(picks))
	var failure_state: Dictionary = failure_run.get("mission", {}).duplicate(true)
	if failure_state.is_empty():
		_check(false, "Failure fixture deploys")
		return
	for id in picks:
		_entity(failure_state, id).hp = 0
	var failure_plan: Dictionary = rules.preview_round(failure_state)
	var defeated: Dictionary = rules.commit_round(failure_state, failure_plan)
	_check(defeated.get("outcome") == "defeat", "Controlled party wipe commits defeat")
	var failed: Dictionary = adventure.call("settle_mission", failure_run, defeated)
	_check(failed.get("phase") == "finished" and failed.get("outcome") == "defeat",
		"First mission defeat finishes adventure")
	_check_reset(failed, picks, "Defeat")


func _test_authored_patrol_route() -> void:
	var routes := [
		{
			"party": ["knight", "healer", "wizard"],
			"patrol": [
				{"orders": [{"unit": "wizard", "order": "order_blast"}]}, {},
				{"action": {"unit": "wizard", "ability": "wizard_pull", "target": "raider_two"}}
			],
			"rescue": [{}, {}, {}, {}, {}]
		},
		{
			"party": ["wizard", "alchemist", "knight"],
			"patrol": [
				{"action": {"unit": "knight", "ability": "knight_push", "target": "alchemist"}},
				{"orders": [{"unit": "wizard", "order": "order_blast"}],
					"action": {"unit": "knight", "ability": "knight_push", "target": "alchemist"}},
				{}
			],
			"rescue": [
				{"action": {"unit": "wizard", "ability": "move", "target": "1,0"}},
				{"action": {"unit": "alchemist", "ability": "alchemist_splash"}}, {}, {}, {}, {}
			]
		},
		{
			"party": ["healer", "knight", "alchemist"],
			"patrol": [
				{"orders": [{"unit": "alchemist", "order": "order_blast"}]}, {}, {}, {}
			],
			"rescue": [{"action": {"unit": "healer", "ability": "move", "target": "2,1"}}, {}, {}, {}, {}, {}]
		},
		{
			"party": ["wizard", "healer", "alchemist"],
			"patrol": [
				{"orders": [{"unit": "healer", "order": "order_aggressive"}],
					"action": {"unit": "wizard", "ability": "wizard_pull", "target": "raider_one"}},
				{}, {"action": {"unit": "wizard", "ability": "wizard_blast"}}
			],
			"rescue": [
				{"action": {"unit": "healer", "ability": "move", "target": "0,3"}},
				{"orders": [{"unit": "wizard", "order": "order_blast"}]},
				{"orders": [{"unit": "healer", "order": "order_support"}]}, {}, {}, {}
			]
		}
	]
	for fixture in routes:
		var picks: Array = fixture.party
		var label := "Authored route %s" % [picks]
		var run: Dictionary = adventure.call("begin_mission", _start(picks))
		if run.get("phase") != "mission":
			_check(false, label + ": patrol deploys")
			continue
		var terminal := _play_route(run, fixture.patrol, "victory", label + " patrol")
		if terminal.get("outcome") != "victory":
			continue
		_check(route_hostile_attack, label + ": patrol victory survives an actual hostile attack")
		var ready: Dictionary = adventure.call("settle_mission", run, terminal)
		_check(ready.get("phase") == "ready" and ready.get("mission_index") == 1,
			label + ": patrol opens the second mission")
		if ready.get("phase") != "ready":
			continue
		for id in picks:
			var hero := _entity(terminal, id)
			_check(ready.carry_by_id[id].hp == maxi(1, hero.hp), label + ": carries actual HP for " + id)
		for id in picks:
			_check(ready.carry_by_id[id].order == terminal.orders[id],
				label + ": carries standing order for " + id)
		var second: Dictionary = adventure.call("begin_mission", ready)
		_check(second.get("mission", {}).get("mission_id") == "company_rescue",
			label + ": patrol advances to rescue")
		for index in range(picks.size()):
			_check(second.mission.units[index].id == picks[index], label + ": rescue retains selected order")
		var rescued := _play_route(second, fixture.rescue, "victory", label + " rescue")
		if rescued.get("outcome") != "victory":
			continue
		_check(_entity(rescued, rescued.objective.subject).get("position") == rescued.objective.destination,
			label + ": escort actually reaches its destination")
		var finished: Dictionary = adventure.call("settle_mission", second, rescued)
		_check(finished.get("phase") == "finished" and finished.get("outcome") == "victory",
			label + ": both real mission victories finish the adventure")
		_check_reset(finished, picks, label + " victory")


func _test_authored_defeat() -> void:
	var picks := ["knight", "healer", "wizard"]
	var first: Dictionary = adventure.call("begin_mission", _start(picks))
	if first.get("phase") != "mission":
		_check(false, "Authored defeat route deploys patrol")
		return
	var patrol := _play_route(first, [
		{"orders": [{"unit": "wizard", "order": "order_blast"}]}, {},
		{"action": {"unit": "wizard", "ability": "wizard_pull", "target": "raider_two"}}
	], "victory", "Authored defeat route patrol")
	if patrol.get("outcome") != "victory":
		return
	var ready: Dictionary = adventure.call("settle_mission", first, patrol)
	var second: Dictionary = adventure.call("begin_mission", ready)
	var state: Dictionary = second.get("mission", {}).duplicate(true)
	if state.is_empty():
		_check(false, "Authored defeat route deploys rescue")
		return
	state = rules.set_order(state, "wizard", "order_cautious")
	_check(state.orders.get("wizard") == "order_cautious", "Defeat route sets a legal cautious order")
	for round_index in range(20):
		if state.get("outcome") != "ongoing":
			break
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview_round(state)
		_check(state == before and plan.get("valid", false), "Defeat route previews without mutation")
		if not plan.get("valid", false):
			return
		state = rules.commit_round(state, plan)
		_check(_matches_preview(state, plan), "Defeat route commits forecast gameplay")
	_check(state.get("outcome") == "defeat", "Actual rescue produces defeat")
	if state.get("outcome") != "defeat":
		return
	var finished: Dictionary = adventure.call("settle_mission", second, state)
	_check(finished.get("phase") == "finished" and finished.get("outcome") == "defeat",
		"Actual rescue defeat ends adventure")
	_check_reset(finished, picks, "Authored defeat")


## Route entries contain optional orders [{unit, order}] and optional
## action {unit, ability, target}; each entry commits exactly one round.
## A route is deliberately not considered successful merely because it ends.
func _play_route(run: Dictionary, route: Array, expected: String, label: String) -> Dictionary:
	var state: Dictionary = run.get("mission", {}).duplicate(true)
	route_hostile_attack = false
	for step in route:
		if state.get("outcome") != "ongoing":
			_check(false, label + ": route continues after the mission ended")
			return {}
		for order in step.get("orders", []):
			var changed: Dictionary = rules.set_order(state, order.unit, order.order)
			_check(changed.get("orders", {}).get(order.unit) == order.order,
				label + ": standing order was accepted")
			state = changed
		var action: Dictionary = step.get("action", {})
		if not action.is_empty():
			var actor: String = action.get("unit", "")
			var ability: String = action.get("ability", "")
			var target: String = action.get("target", "")
			var chosen: Dictionary = rules.choose_manual(state, actor, ability, target)
			_check(chosen.get("overrides", {}).get(actor, {}) == {"ability_id": ability, "target_id": target},
				label + ": manual action was accepted")
			state = chosen
			var turn_state: Dictionary = rules.state_before_action(state, actor)
			var action_preview: Dictionary = rules.preview(turn_state, actor, ability, target)
			_check(action_preview.get("valid", false), label + ": action is legal at the actor's turn")
		var before := state.duplicate(true)
		var plan: Dictionary = rules.preview_round(state)
		_check(state == before and plan.get("valid", false), label + ": valid non-mutating forecast")
		if not plan.get("valid", false):
			return {}
		for event in plan.get("events", []):
			if event.get("type") == "damage":
				var source: String = event.get("source_id", "")
				if not _entity(state, source).is_empty() and rules.entity_profile(state, source).get("team") == "enemies":
					route_hostile_attack = true
		state = rules.commit_round(state, plan)
		_check(_matches_preview(state, plan), label + ": commit matches every forecast gameplay field")
	_check(state.get("outcome") == expected, label + ": route produces " + expected)
	return state


func _check_reset(finished: Dictionary, picks: Array, label: String) -> void:
	var guild: Dictionary = adventure.call("return_to_guild", finished)
	_check(guild.get("phase") == "guild", label + ": returns to guild")
	_check(guild.get("party", []).is_empty() and guild.get("mission", {}).is_empty(),
		label + ": guild clears company and mission")
	_check(guild.get("last_result", {}).is_empty() and guild.get("carry_by_id", {}).is_empty(),
		label + ": guild clears prior result and carried health")
	_check(guild.get("outcome") == "ongoing", label + ": guild clears outcome")
	var fresh := _start(picks)
	_check(fresh.get("phase") == "ready" and fresh.get("mission_index") == 0,
		label + ": fresh departure begins at first mission")
	_check(fresh.get("party") == picks and fresh.get("mission", {}).is_empty(),
		label + ": fresh departure keeps only newly picked company")


func _matches_preview(committed: Dictionary, plan: Dictionary) -> bool:
	var gameplay := committed.duplicate(true)
	gameplay.erase("_terminal_commit")
	return gameplay == plan.get("result")
