extends RefCounted

const Catalog = preload("res://content/catalog.gd")
const Actions = preload("res://rules/actions.gd")
const Behaviors = preload("res://rules/behaviors.gd")
const Board = preload("res://rules/board.gd")
const Statuses = preload("res://rules/statuses.gd")

func new_game(mode: String, definitions_input: Variant = null, mission_id := "ferryman") -> Dictionary:
	var authored: Variant = definitions_input if definitions_input != null else Catalog.read_default()
	if not authored is Dictionary:
		push_error("Company: definitions must be a Dictionary.")
		return {}
	if definitions_input == null and authored.is_empty():
		return {}
	return start_in_mode(Catalog.build(authored, mission_id), mode)


## Start from a pristine authored opening; share its catalog but not mutable state.
func start_in_mode(opening: Dictionary, mode: String) -> Dictionary:
	if opening.is_empty():
		return {}
	var state := opening.duplicate(true)
	state["mode"] = mode if mode in ["hybrid", "direct", "standing"] else "hybrid"
	state["manual_remaining"] = _budget(state)
	return state


func _budget(state: Dictionary) -> int:
	match state.mode:
		"hybrid":
			return 1
		"direct":
			var living := 0
			for actor in state.units:
				if Board.alive(actor) and Board.capable(state, actor, "commandable"):
					living += 1
			return living
	return 0


func definitions(state: Dictionary) -> Dictionary:
	return state.catalog.defs


func entity_profile(state: Dictionary, id: String) -> Dictionary:
	return Board.profile(state, Board.entity(state, id))


func display_name(state: Dictionary, id: String) -> String:
	var entity := Board.entity(state, id)
	return Board.display_name(state, entity) if not entity.is_empty() else id


static func coordinate(position: Vector2i) -> String:
	return Board.coordinate(position)


func ability_definition(state: Dictionary, id: String) -> Dictionary:
	return definitions(state).abilities.get(id, {})


func mission_definition(state: Dictionary) -> Dictionary:
	return definitions(state).missions[state.mission_id]


func tile_definition(state: Dictionary, position: Vector2i) -> Dictionary:
	return Board.tile(state, position)


func location(state: Dictionary, id: String) -> Variant:
	var at: Variant = definitions(state).boards[state.board_id].locations.get(id)
	return Vector2i(int(at[0]), int(at[1])) if at is Array else at


func deadline(state: Dictionary) -> int:
	return int(definitions(state).encounters[state.encounter_id].deadline)


func has_capability(state: Dictionary, unit_id: String, capability: String) -> bool:
	return Board.capable(state, Board.entity(state, unit_id), capability)


func status(state: Dictionary, unit_id: String, status_id: String) -> Dictionary:
	return Board.entity(state, unit_id).get("statuses", {}).get(status_id, {}).duplicate()


func has_status(state: Dictionary, unit_id: String, status_id: String) -> bool:
	return not status(state, unit_id, status_id).is_empty()


func has_status_handler(state: Dictionary, unit_id: String, handler: String) -> bool:
	return not Statuses.ids_with_handler(state, Board.entity(state, unit_id), handler).is_empty()


func can_act(state: Dictionary, unit_id: String) -> bool:
	return state.outcome == "ongoing" and Actions.can_act(state, Board.entity(state, unit_id))


func options(state: Dictionary, unit_id: String) -> Array:
	var result: Array = []
	var profile := entity_profile(state, unit_id)
	if "commandable" not in profile.get("capabilities", []):
		return result
	for id in profile.abilities:
		var ability := ability_definition(state, id)
		result.append({"id": id, "label": ability.label, "kind": "action", "help": ability.help,
			"target_kind": ability.targeting.kind})
	for id in profile.habits:
		result.append({"id": id, "label": definitions(state).orders[id].label, "kind": "order"})
	return result


func set_order(state: Dictionary, unit_id: String, order_id: String) -> Dictionary:
	var result := state.duplicate(true)
	var profile := entity_profile(state, unit_id)
	if "commandable" in profile.get("capabilities", []) and profile.habits.has(order_id):
		result.orders[unit_id] = order_id
	return result


func targets(state: Dictionary, unit_id: String, ability_id: String) -> Array:
	return Actions.targets(state, Board.entity(state, unit_id), ability_id) if state.outcome == "ongoing" else []


func preview(state: Dictionary, unit_id: String, ability_id: String, target_id := "") -> Dictionary:
	var result := state.duplicate(true)
	var events: Array = []
	var valid: bool = state.get("outcome") == "ongoing" and Actions.execute(result, Board.entity(result, unit_id),
		{"ability_id": ability_id, "target_id": target_id}, events)
	return _plan(state, result, events, valid)


func _plan(state: Dictionary, result: Dictionary, events: Array, valid: bool) -> Dictionary:
	return {"valid": valid, "events": events, "result": result, "source": state.duplicate(true)}


func apply_plan(state: Dictionary, plan: Dictionary) -> Dictionary:
	var result: Variant = plan.get("result")
	if plan.get("valid", false) and plan.get("source") == state and result is Dictionary \
			and result.get("catalog") == state.get("catalog") and result.get("mission_id") == state.get("mission_id"):
		return result.duplicate(true)
	return state.duplicate(true)


func choose_manual(state: Dictionary, unit_id: String, ability_id: String, target_id := "") -> Dictionary:
	var result := state.duplicate(true)
	var actor := Board.entity(state, unit_id)
	if state.outcome != "ongoing" or not Board.alive(actor) or not Board.capable(state, actor, "commandable") \
			or Actions.owned_ability(state, actor, ability_id).is_empty():
		return result
	if not result.overrides.has(unit_id):
		if result.manual_remaining <= 0:
			return result
		result.manual_remaining -= 1
	# Stored intent is checked on the board as this actor gets their turn.
	result.overrides[unit_id] = {"ability_id": ability_id, "target_id": target_id}
	return result


func _begin_next_round(state: Dictionary) -> void:
	state.round += 1
	state.manual_remaining = _budget(state)
	state.overrides.clear()


func advance_round(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	_begin_next_round(result)
	return result


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
		return _plan(state, result, events, false)
	_resolve_turns(result, events)
	if not _check_objective(result, events):
		_check_failures(result, events)
	if result.outcome == "ongoing":
		_begin_next_round(result)
	return _plan(state, result, events, true)


func commit_round(state: Dictionary, plan: Dictionary) -> Dictionary:
	return apply_plan(state, plan)


func _resolve_turns(state: Dictionary, events: Array, stop_before := "") -> void:
	for actor in state.units:
		if Board.alive(actor):
			Statuses.expire(state, actor, "actor_turn_start")
		if actor.id == stop_before:
			return
		if Board.alive(actor):
			_resolve_turn(state, actor, events)
			Statuses.expire(state, actor, "actor_turn_end")


func _resolve_turn(state: Dictionary, actor: Dictionary, events: Array) -> void:
	var name := Board.display_name(state, actor)
	if not Actions.can_act(state, actor):
		var consumed := Statuses.ids_with_handler(state, actor, "skip_action")
		Statuses.expire(state, actor, "consume_action")
		Board.authored_event(state, events, "recover", "recover", {"actor": name},
			{"unit_id": actor.id, "status_ids": consumed})
		return

	var action := _intent(state, actor)
	if not action.has("ability_id"):
		Board.authored_event(state, events, "wait", action.get("wait", "hold"), {"actor": name}, {"unit_id": actor.id})
	elif not Actions.execute(state, actor, action, events):
		Board.authored_event(state, events, "wait", "invalid", {"actor": name},
			{"unit_id": actor.id, "ability_id": action.ability_id})


func _intent(state: Dictionary, actor: Dictionary) -> Dictionary:
	var profile := Board.profile(state, actor)
	if "commandable" in profile.get("capabilities", []) and state.overrides.has(actor.id):
		return state.overrides[actor.id]
	var order: String = state.orders.get(actor.id, "")
	var behavior: String = profile.get("habits", {}).get(order, profile.get("behavior", ""))
	return Behaviors.decide(state, actor, behavior)


func _check_objective(state: Dictionary, events: Array) -> bool:
	var objective: Dictionary = state.objective
	if objective.handler != "escort":
		return false
	var subject := Board.entity(state, objective.subject)
	if not Board.alive(subject) or subject.position != objective.destination:
		return false
	var spec: Dictionary = mission_definition(state).objective
	state["outcome"] = "victory"
	_mission_event(state, events, "victory", spec.victory_event)
	return true


func _check_failures(state: Dictionary, events: Array) -> void:
	for failure in mission_definition(state).failures:
		match failure.handler:
			"subject_dead":
				if Board.alive(Board.entity(state, state.objective.subject)):
					continue
			"deadline":
				if deadline(state) == 0 or state.round < deadline(state):
					continue
				_collapse(state)
			_:
				continue
		state["outcome"] = "defeat"
		_mission_event(state, events, "defeat", failure.event)
		return


func _collapse(state: Dictionary) -> void:
	var tiles: Dictionary = definitions(state).tiles
	for tile in state.terrain:
		tile.type = tiles[tile.type].get("collapse_to", tile.type)
	state.default_tile = tiles[state.default_tile].get("collapse_to", state.default_tile)


func _mission_event(state: Dictionary, events: Array, type: String, template: String) -> void:
	var subject := Board.entity(state, state.objective.subject)
	var name := Board.display_name(state, subject)
	var destination: Vector2i = state.objective.destination
	var text := Board.format_text(template, {"subject": name.to_lower(), "subject_label": name,
		"destination": destination, "position": subject.get("position", destination), "hp": subject.get("hp", 0),
		"max_hp": subject.get("max_hp", 0)})
	Board.event(events, type, text, {"target_id": state.objective.subject, "position": destination})
