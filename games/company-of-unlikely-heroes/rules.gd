extends RefCounted

const Alchemy = preload("res://rules/alchemy.gd")
const Catalog = preload("res://content/catalog.gd")
const Actions = preload("res://rules/actions.gd")
const Behaviors = preload("res://rules/behaviors.gd")
const Board = preload("res://rules/board.gd")
const FrontierObjectives = preload("res://rules/frontier_objectives.gd")
const Shield = preload("res://rules/shield.gd")
const Statuses = preload("res://rules/statuses.gd")
const Summons = preload("res://rules/summons.gd")
const Upgrades = preload("res://rules/upgrades.gd")


func new_game(definitions_input: Variant, mission_id: String) -> Dictionary:
	var authored: Variant = definitions_input if definitions_input != null else Catalog.read_default()
	if not authored is Dictionary:
		push_error("Company: definitions must be a Dictionary.")
		return {}
	if definitions_input == null and authored.is_empty():
		return {}
	return open_mission(authored, mission_id)


## With no party IDs, open an authored encounter without party slots.
static func open_mission(definitions_input: Dictionary, mission_id: String, party_ids: Array = [],
		fallback_dose_seed := 1) -> Dictionary:
	var state := Catalog.build(definitions_input, mission_id, party_ids, fallback_dose_seed)
	if not state.is_empty() and not party_ids.is_empty():
		state["party"] = party_ids.duplicate()
	return state


func definitions(state: Dictionary) -> Dictionary:
	return state.catalog.defs


func entity_profile(state: Dictionary, id: String) -> Dictionary:
	return Board.profile(state, Board.entity(state, id))


func display_name(state: Dictionary, id: String) -> String:
	var entity := Board.entity(state, id)
	return Board.display_name(state, entity) if not entity.is_empty() else id


static func coordinate(position: Vector2i) -> String:
	return Board.coordinate(position)


func ability_definition(state: Dictionary, id: String, unit_id := "") -> Dictionary:
	return Upgrades.ability(state, Board.entity(state, unit_id) if not unit_id.is_empty() else {}, id)


func shield_position(state: Dictionary, unit_id: String) -> Variant:
	return Shield.position(Board.entity(state, unit_id))


func nominated_target(state: Dictionary, unit_id: String) -> String:
	return Summons.nominated_target(state, Board.entity(state, unit_id)).get("id", "")


func mission_definition(state: Dictionary) -> Dictionary:
	return definitions(state).missions[state.mission_id]


## Live objective progress; elimination also exposes counts for existing UI.
func objective_progress(state: Dictionary) -> Dictionary:
	if state.objective.handler != "defeat_all":
		return FrontierObjectives.progress(state)
	var team: String = state.objective.team
	var alive := 0
	var total := 0
	for unit in state.units:
		if Board.team(state, unit) == team:
			total += 1
			if Board.alive(unit):
				alive += 1
	return {"alive": alive, "total": total}


func objective_markers(state: Dictionary) -> Dictionary:
	return FrontierObjectives.markers(state)


func tile_definition(state: Dictionary, position: Vector2i) -> Dictionary:
	return Board.tile(state, position)


func location(state: Dictionary, id: String) -> Variant:
	var at: Variant = definitions(state).boards[state.board_id].locations.get(id)
	return Vector2i(int(at[0]), int(at[1])) if at is Array else at


func deadline(state: Dictionary) -> int:
	return int(definitions(state).encounters[state.encounter_id].get("deadline", 0))


func has_capability(state: Dictionary, unit_id: String, capability: String) -> bool:
	return Board.capable(state, Board.entity(state, unit_id), capability)


func status(state: Dictionary, unit_id: String, status_id: String) -> Dictionary:
	return Board.entity(state, unit_id).get("statuses", {}).get(status_id, {}).duplicate()


func has_status(state: Dictionary, unit_id: String, status_id: String) -> bool:
	return not status(state, unit_id, status_id).is_empty()


func alchemy_status(state: Dictionary, unit_id: String, reaction_id: String) -> Dictionary:
	return Statuses.alchemy_status(Board.entity(state, unit_id), reaction_id).duplicate()


func has_status_handler(state: Dictionary, unit_id: String, handler: String) -> bool:
	if handler == "skip_action":
		return Statuses.has_skip(state, Board.entity(state, unit_id))
	return not Statuses.ids_with_handler(state, Board.entity(state, unit_id), handler).is_empty()


func status_labels(state: Dictionary, unit_id: String, active_handler := "") -> PackedStringArray:
	return Statuses.labels(state, Board.entity(state, unit_id), active_handler)


func knocked_down(state: Dictionary, unit_id: String) -> bool:
	return Statuses.knocked_down(state, Board.entity(state, unit_id))


func can_act(state: Dictionary, unit_id: String) -> bool:
	return state.outcome == "ongoing" and Actions.can_act(state, Board.entity(state, unit_id))


func summon_capped(state: Dictionary, unit_id: String, ability_id: String) -> bool:
	var actor := Board.entity(state, unit_id)
	var ability := Actions.owned_ability(state, actor, ability_id)
	return ability.get("handler") == "summon" and Actions.summon_capped(state, actor, ability)


func initiative(state: Dictionary) -> Array:
	return Board.turn_order(state).filter(Board.alive)


## Unoccupied corpse markers, one per cell; selection still lists every eligible corpse.
func corpse_markers(state: Dictionary) -> Dictionary:
	var corpses: Dictionary = {}
	for caster in state.units:
		if not Board.alive(caster) or not Board.capable(state, caster, "commandable"):
			continue
		for id in Board.profile(state, caster).abilities:
			var ability := ability_definition(state, id, caster.id)
			if ability.handler == "summon" and ability.targeting.kind == "entity":
				for corpse in Actions.raisable_corpses(state, caster, ability):
					if corpse.id != state.objective.get("subject") and Board.is_vacant(state, corpse.position):
						corpses[corpse.position] = corpse
	return corpses


func options(state: Dictionary, unit_id: String) -> Array:
	var result: Array = []
	var profile := entity_profile(state, unit_id)
	if "commandable" not in profile.get("capabilities", []):
		return result
	for id in profile.abilities:
		var ability := ability_definition(state, id, unit_id)
		result.append({"id": id, "label": ability.label, "kind": "action", "help": ability.help,
			"target_kind": ability.targeting.kind})
	for id in profile.habits:
		result.append({"id": id, "label": definitions(state).orders[id].label, "kind": "order"})
	return result


func set_order(state: Dictionary, unit_id: String, order_id: String) -> Dictionary:
	var result := state.duplicate(true)
	var profile := entity_profile(state, unit_id)
	if state.outcome == "ongoing" and "commandable" in profile.get("capabilities", []) and profile.habits.has(order_id):
		result.orders[unit_id] = order_id
	return result


func targets(state: Dictionary, unit_id: String, ability_id: String) -> Array:
	return Actions.targets(state, Board.entity(state, unit_id), ability_id) if state.outcome == "ongoing" else []


## `state` is the board at the start of the caster's turn, as for target selection.
func dose_forecast(state: Dictionary, unit_id: String, ability_id: String) -> Dictionary:
	var actor := Board.entity(state, unit_id)
	if state.outcome != "ongoing" or not Actions.can_act(state, actor):
		return {}
	return Alchemy.reaction_forecast(state, actor, Actions.owned_ability(state, actor, ability_id).get("handler", ""))


func preview(state: Dictionary, unit_id: String, ability_id: String, target_id := "") -> Dictionary:
	var result := state.duplicate(true)
	var events: Array = []
	var valid: bool = state.get("outcome") == "ongoing" and _execute_action(result, Board.entity(result, unit_id),
		{"ability_id": ability_id, "target_id": target_id}, events)
	return _plan("action", state, result, events, valid)


func _plan(kind: String, state: Dictionary, result: Dictionary, events: Array, valid: bool) -> Dictionary:
	return {"kind": kind, "valid": valid, "events": events, "result": result, "source": state.duplicate(true)}


func apply_plan(state: Dictionary, plan: Dictionary) -> Dictionary:
	var result: Variant = plan.get("result")
	if plan.get("valid", false) and plan.get("source") == state and result is Dictionary \
			and result.get("catalog") == state.get("catalog") and result.get("mission_id") == state.get("mission_id"):
		return result.duplicate(true)
	return state.duplicate(true)


func choose_manual(state: Dictionary, unit_id: String, ability_id: String, target_id := "") -> Dictionary:
	var result := state.duplicate(true)
	var actor := Board.entity(state, unit_id)
	var ability := Actions.owned_ability(state, actor, ability_id)
	if state.outcome != "ongoing" or not Board.alive(actor) or not Board.capable(state, actor, "commandable") \
			or ability.is_empty() or (ability.handler == "perform" and not Actions.accepts_target_argument(ability, target_id)):
		return result
	if not result.overrides.is_empty() and not result.overrides.has(unit_id):
		return result
	# Stored intent is checked on the board as this actor gets their turn.
	result.overrides[unit_id] = {"ability_id": ability_id, "target_id": target_id}
	return result


func clear_manual(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	if result.outcome == "ongoing":
		_reset_override(result)
	return result


func _reset_override(state: Dictionary) -> void:
	state.overrides.clear()


## The board as a commandable actor's turn starts, after earlier turns.
func state_before_action(state: Dictionary, unit_id: String) -> Dictionary:
	var result := state.duplicate(true)
	if result.outcome == "ongoing" and has_capability(state, unit_id, "commandable"):
		_resolve_turns(result, [], unit_id)
	return result


func preview_round(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	var events: Array = []
	if state.get("outcome") != "ongoing":
		return _plan("round", state, result, events, false)
	_resolve_turns(result, events)
	var gate_before_reactions := Board.pressure_gate_open(result)
	Alchemy.finish_round(result, events)
	FrontierObjectives.report_gate_change(result, {}, gate_before_reactions, events)
	FrontierObjectives.finish_round(result, events)
	var ending := _end_condition(result)
	if ending.is_empty():
		result.round += 1
		Statuses.expire_rounds(result)
		_reset_override(result)
		FrontierObjectives.prepare_next_round(result, events)
	else:
		if ending.get("collapse", false):
			_collapse(result)
		result.outcome = ending.outcome
		events.append(_mission_end_event(result, ending))
	return _plan("round", state, result, events, true)


func commit_round(state: Dictionary, plan: Dictionary) -> Dictionary:
	if plan.get("kind") != "round":
		return state.duplicate(true)
	var result := apply_plan(state, plan)
	if state.get("outcome") == "ongoing" and result.get("outcome") in ["victory", "defeat"] and state.has("party"):
		# Distinguish a committed adventure round from a forecast of the same board.
		if not _matches_board_outcome(result):
			return state.duplicate(true)
		result["_terminal_commit"] = true
	return result


func is_committed_terminal(state: Dictionary) -> bool:
	return state.get("_terminal_commit", false) == true and _matches_board_outcome(state)


func mission_result_text(state: Dictionary) -> String:
	var ending := _end_condition(state)
	if ending.get("outcome") != state.get("outcome"):
		return ""
	return _mission_end_event(state, ending).text


func _matches_board_outcome(state: Dictionary) -> bool:
	return state.get("outcome") in ["victory", "defeat"] \
		and _end_condition(state).get("outcome") == state.outcome


func _resolve_turns(state: Dictionary, events: Array, stop_before := "") -> void:
	for actor in Board.turn_order(state):
		Statuses.begin_turn(state, actor)
		if actor.id == stop_before:
			return
		if Board.alive(actor):
			_resolve_turn(state, actor, events)
			Statuses.expire(state, actor, "actor_turn_end")


func _resolve_turn(state: Dictionary, actor: Dictionary, events: Array) -> void:
	if Statuses.has_skip(state, actor):
		# Wagon and sheep move during the objective pass, not their initiative slot.
		# Keep this reaction pending until then, without deferring other statuses.
		Statuses.consume_skips(state, actor, events, FrontierObjectives.controls_movement(state, actor.id))
		return

	var name := Board.display_name(state, actor)
	var action := _intent(state, actor)
	if action.get("wait") == "shield_away":
		Board.event(events, "wait", "%s cannot guard until their shield is retrieved." % name, {"unit_id": actor.id})
	elif not action.has("ability_id"):
		Board.authored_event(state, events, "wait", action.get("wait", "hold"), {"actor": name}, {"unit_id": actor.id})
	elif not _execute_action(state, actor, action, events):
		Board.authored_event(state, events, "wait", "invalid", {"actor": name},
			{"unit_id": actor.id, "ability_id": action.ability_id})


func _execute_action(state: Dictionary, actor: Dictionary, action: Dictionary, events: Array) -> bool:
	var gate_was_open := Board.pressure_gate_open(state)
	var first := events.size()
	var origin: Variant = actor.get("position")
	var ability := Actions.owned_ability(state, actor, action.ability_id)
	var recipe: String = actor.get("bottled_reaction", {}).get("recipe", "") \
		if ability.get("handler") == "repeat_batch" else ""
	if not Actions.execute(state, actor, action, events):
		return false
	if first < events.size():
		# Effects name their own sources (e.g. a protector who absorbs the hit).
		# Preserve the actual actor and effect scope without adding a log event.
		events[first]["resolved_action"] = {"unit_id": actor.id, "ability_id": action.ability_id,
			"source_cell": origin, "actor_cell": actor.position, "event_count": events.size() - first}
		if not recipe.is_empty():
			events[first].resolved_action["recipe_id"] = recipe
	match state.objective.handler:
		"pressure_gate":
			FrontierObjectives.report_gate_change(state, actor, gate_was_open, events)
		"treasure_noise":
			if Board.deployed_hero(state, actor):
				var noise_ability := Actions.owned_ability(state, actor, action.ability_id)
				FrontierObjectives.add_noise(state, actor, noise_ability.handler, events)
	return true


func _intent(state: Dictionary, actor: Dictionary) -> Dictionary:
	var profile := Board.profile(state, actor)
	if "commandable" in profile.get("capabilities", []) and state.overrides.has(actor.id):
		return state.overrides[actor.id]
	var order: String = state.orders.get(actor.id, "")
	var behavior: String = profile.get("habits", {}).get(order, profile.get("behavior", ""))
	return Behaviors.decide(state, actor, behavior)


func _objective_met(state: Dictionary) -> bool:
	var objective: Dictionary = state.objective
	match objective.handler:
		"escort":
			var subject := Board.entity(state, objective.subject)
			return Board.alive(subject) and subject.position == objective.destination
		"leave_zone":
			var subject := Board.entity(state, objective.subject)
			return Board.alive(subject) and not Board.in_zone(state, objective.zone, subject.position)
		"defeat_all":
			return objective_progress(state).alive == 0
	return FrontierObjectives.met(state)


func _party_survives(state: Dictionary) -> bool:
	for actor in state.units:
		if Board.alive(actor) and Board.deployed_hero(state, actor):
			return true
	return false


## Resolve precedence from the final board without mutating it.
func _end_condition(state: Dictionary) -> Dictionary:
	var mission := mission_definition(state)
	for failure in mission.failures:
		if failure.handler == "party_wiped" and not _party_survives(state):
			return {"outcome": "defeat", "event": failure.event}
	var objective_failure := FrontierObjectives.failure(state)
	if not objective_failure.is_empty():
		if state.objective.handler == "wagon":
			for failure in mission.failures:
				if failure.handler == "subject_dead":
					return {"outcome": "defeat", "event": failure.event}
		return {"outcome": "defeat", "event": objective_failure}
	if _objective_met(state):
		return {"outcome": "victory", "event": mission.objective.victory_event}
	for failure in mission.failures:
		match failure.handler:
			"subject_dead":
				if not Board.alive(Board.entity(state, state.objective.subject)):
					return {"outcome": "defeat", "event": failure.event}
			"deadline":
				var due := deadline(state)
				if due > 0 and state.round >= due:
					return {"outcome": "defeat", "event": failure.event, "collapse": true}
	return {}


func _collapse(state: Dictionary) -> void:
	var tiles: Dictionary = definitions(state).tiles
	for tile in state.terrain:
		tile.type = tiles[tile.type].get("collapse_to", tile.type)
	state.default_tile = tiles[state.default_tile].get("collapse_to", state.default_tile)


func _mission_end_event(state: Dictionary, ending: Dictionary) -> Dictionary:
	var substitutions: Dictionary = {}
	var event := {"type": ending.outcome}
	if state.objective.handler in ["escort", "wagon"]:
		var subject := Board.entity(state, state.objective.subject)
		var name := Board.display_name(state, subject)
		var destination: Vector2i = state.objective.destination
		substitutions = {"subject": name.to_lower(), "subject_label": name,
			"destination": destination, "position": subject.get("position", destination),
			"hp": subject.get("hp", 0), "max_hp": subject.get("max_hp", 0)}
		event["target_id"] = state.objective.subject
		event["position"] = destination
	elif state.objective.handler == "leave_zone":
		var subject := Board.entity(state, state.objective.subject)
		var name := Board.display_name(state, subject)
		substitutions = {"subject": name.to_lower(), "subject_label": name, "zone": state.objective.zone,
			"position": subject.position, "hp": subject.hp, "max_hp": subject.max_hp}
		event.merge({"target_id": subject.id, "position": subject.position, "zone": state.objective.zone})
	event["text"] = Board.format_text(ending.event, substitutions)
	return event
