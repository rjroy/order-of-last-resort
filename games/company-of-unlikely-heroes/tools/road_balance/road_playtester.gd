extends RefCounted
## A deterministic, one-command-per-round rules client, not a game-playing AI.

const Board = preload("res://rules/board.gd")


func run_case(rules, initial_state: Dictionary, policy: String, round_limit: int) -> Dictionary:
	if policy not in ["wizard_first", "forecast_first"]:
		return {"error": "Unknown policy: " + policy}
	if round_limit < 1:
		return {"error": "round_limit must be positive"}
	if not initial_state.has("catalog") or not initial_state.has("units") or not initial_state.has("outcome"):
		return {"error": "Opening is not a built rules state"}
	if not initial_state.get("overrides", {}).is_empty():
		return {"error": "Opening must not contain a staged direct command"}
	var state := initial_state.duplicate(true)
	var heroes: Array = []
	for unit in state.units:
		if rules.has_capability(state, unit.id, "commandable"):
			heroes.append(unit.id)
	var rounds: Array = []
	var enemy_actions: Array = []
	var damage_dealt := 0
	var damage_received := 0
	for turn in round_limit:
		if state.outcome != "ongoing":
			break
		var standing: Dictionary = rules.preview_round(state)
		if not standing.valid:
			return {"error": "Invalid standing forecast at round %d" % (turn + 1)}
		var best := {"draft": {}, "plan": standing, "score": _score(state, standing.result, heroes)}
		var wizard_best := {}
		for hero in heroes:
			var before: Dictionary = rules.state_before_action(state, hero)
			for option in rules.options(before, hero):
				if option.kind != "action":
					continue
				var targets: Array = [""]
				if option.target_kind != "none":
					targets = []
					for target in rules.targets(before, hero, option.id):
						targets.append(str(target.id))
					# Automatic abilities may accept an empty target.
					targets.append("")
				for target in targets:
					if not rules.preview(before, hero, option.id, target, true).valid:
						continue
					var selected: Dictionary = rules.choose_manual(state, hero, option.id, target)
					if not selected.overrides.has(hero):
						continue
					var plan: Dictionary = rules.preview_round(selected)
					if not plan.valid:
						continue
					var candidate := {"draft": {"unit_id": hero, "ability_id": option.id, "target_id": target},
						"plan": plan, "score": _score(state, plan.result, heroes)}
					if candidate.score > best.score:
						best = candidate
					if option.id == "wizard_blast" and _enemy_target(before, target):
						if wizard_best.is_empty() or candidate.score > wizard_best.score:
							wizard_best = candidate
		if policy == "wizard_first" and not wizard_best.is_empty() and wizard_best.score >= best.score - 100:
			best = wizard_best
		var chosen: Dictionary = best.plan
		var enemies := _enemy_ids(state, chosen.result)
		var acted := {}
		for event in chosen.events:
			if event.get("type") == "damage" and event.get("target_is_character", false):
				if event.get("target_team") == "enemies":
					damage_dealt += int(event.get("hp_lost", 0))
				elif event.get("target_team") == "heroes":
					damage_received += int(event.get("hp_lost", 0))
			var action: Dictionary = event.get("resolved_action", {})
			var actor: String = action.get("unit_id", "")
			if actor in enemies:
				acted[actor] = true
			if event.get("type") in ["windup_mark", "windup_strike"] and event.get("unit_id") in enemies:
				acted[event.unit_id] = true
		enemy_actions.append(acted.size())
		rounds.append({"draft": best.draft, "events": chosen.events,
			"standing_events": standing.events, "decision_score": best.score,
			"standing_decision_score": _score(state, standing.result, heroes)})
		var selected_state: Dictionary = state if best.draft.is_empty() else rules.choose_manual(
			state, best.draft.unit_id, best.draft.ability_id, best.draft.target_id)
		state = rules.commit_round(selected_state, chosen)
	var carry := {}
	var ending := {}
	var fallen: Array = []
	for id in heroes:
		var unit: Dictionary = Board.entity(state, id)
		var hp := maxi(0, int(unit.get("hp", 0)))
		ending[id] = hp
		carry[id] = maxi(1, hp)
		if int(unit.get("hp", 0)) <= 0:
			fallen.append(id)
	var metrics := {"ending_hp": ending, "fallen_heroes": fallen,
		"enemy_actions_by_round": enemy_actions, "damage_dealt": damage_dealt,
		"damage_received": damage_received}
	if state.outcome == "victory":
		metrics["carryover_hp"] = carry
	return {"status": "round_limit" if state.outcome == "ongoing" else state.outcome,
		"rounds": rounds, "metrics": metrics}


func _enemy_ids(before: Dictionary, after: Dictionary) -> Array:
	var ids: Array = []
	for state in [before, after]:
		for unit in state.units:
			if Board.team(state, unit) == "enemies" and unit.id not in ids:
				ids.append(unit.id)
	return ids


func _enemy_target(state: Dictionary, id: String) -> bool:
	var target: Dictionary = Board.entity(state, id)
	return not target.is_empty() and Board.team(state, target) == "enemies" \
		and int(target.get("hp", 0)) > 0


func _score(before: Dictionary, after: Dictionary, heroes: Array) -> float:
	var enemies := _enemy_ids(before, after)
	var value := 0.0
	for id in heroes:
		var old: Dictionary = Board.entity(before, id)
		var unit: Dictionary = Board.entity(after, id)
		value += (int(unit.get("hp", 0)) - int(old.get("hp", 0))) * 8.0
		if int(old.get("hp", 0)) > 0 and int(unit.get("hp", 0)) <= 0:
			value -= 25.0
	for id in enemies:
		var old: Dictionary = Board.entity(before, id)
		var unit: Dictionary = Board.entity(after, id)
		value += (maxi(0, int(old.get("hp", 0))) - maxi(0, int(unit.get("hp", 0)))) * 5.0
		if int(old.get("hp", 0)) > 0 and int(unit.get("hp", 0)) <= 0:
			value += 8.0
	# Small progress preference breaks otherwise inert ties without overriding damage.
	for id in heroes:
		var hero: Dictionary = Board.entity(after, id)
		if int(hero.get("hp", 0)) <= 0:
			continue
		var nearest := 100
		for enemy_id in enemies:
			var enemy: Dictionary = Board.entity(after, enemy_id)
			if int(enemy.get("hp", 0)) > 0:
				nearest = mini(nearest, Board.distance(hero.position, enemy.position))
		if nearest < 100:
			value -= nearest * 0.01
	if after.outcome == "victory":
		value += 100.0
	elif after.outcome == "defeat":
		value -= 100.0
	return value
