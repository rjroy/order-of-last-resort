extends RefCounted
## A fitting belongs to the wearer, not the Smith's turn or current health.

const Board = preload("res://rules/board.gd")
const Movement = preload("res://rules/movement.gd")
const Shield = preload("res://rules/shield.gd")
const Statuses = preload("res://rules/statuses.gd")


static func source(wearer: Dictionary) -> String:
	return wearer.get("fitted_by", "") if Board.alive(wearer) else ""


static func clear(wearer: Dictionary) -> void:
	wearer.erase("fitted_by")


static func eligible(state: Dictionary, smith: Dictionary, wearer: Dictionary) -> bool:
	return Board.alive(wearer) and wearer.id != smith.id and Board.deployed_hero(state, wearer) \
		and Board.team(state, wearer) == "heroes" and not wearer.has("summoner_id") \
		and not Board.capable(state, wearer, "minion")


static func fit(state: Dictionary, smith: Dictionary, wearer: Dictionary, events: Array) -> void:
	var former := ""
	for hero in state.units:
		if source(hero) == smith.id:
			former = hero.id
			clear(hero)
			break
	wearer["fitted_by"] = smith.id
	var text := "%s uses Try This to fit %s." % [Board.display_name(state, smith), Board.display_name(state, wearer)]
	var data := {"unit_id": smith.id, "target_id": wearer.id, "status_id": "fitted"}
	if not former.is_empty():
		var old_name := Board.display_name(state, Board.entity(state, former))
		text += " %s loses the fitting." % old_name
		data["replaced_target_id"] = former
	Board.event(events, "fit", text, data)


static func report_pending(state: Dictionary, events: Array) -> void:
	for hero in state.units:
		var smith_id := source(hero)
		if not smith_id.is_empty():
			Board.event(events, "fitted_pending", "%s stays Fitted (by %s)." % [
				Board.display_name(state, hero), Board.display_name(state, Board.entity(state, smith_id))],
				{"unit_id": hero.id, "source_id": smith_id, "status_id": "fitted"})


static func clear_mission(state: Dictionary) -> void:
	for unit in state.units:
		clear(unit)


## Return the registered form even when unavailable so callers can explain why the base branch wins.
static func alternate(state: Dictionary, actor: Dictionary, base: Dictionary) -> Dictionary:
	if source(actor).is_empty():
		return {}
	match base.get("fitted_form"):
		"fitted_pull":
			return _pull_form(state, actor)
		"clear_the_floor":
			return _clear_floor_form(state, actor, base)
	return {}


static func _pull_form(state: Dictionary, actor: Dictionary) -> Dictionary:
	var choices: Array = []
	for target in Board.occupants(state, {"objects": true}):
		var distance := Board.distance(actor.position, target.position)
		if distance < 2 or distance > 3:
			continue
		var movable: bool = Board.capable(state, target, "pullable") \
			or (target.has("object_id") and Board.capable(state, target, "pushable"))
		if not movable or (not target.has("object_id") and not Board.allied(state, actor, target) \
				and not Board.opponents(state, actor, target)):
			continue
		var direction := Board.dominant_step(target.position, actor.position)
		var destination: Vector2i = target.position + direction
		if Board.can_enter(state, destination):
			choices.append({"id": target.id, "label": Board.display_name(state, target), "position": target.position,
				"destination": destination, "direction": direction})
	return {"id": "fitted_pull", "label": "Pull",
		"help": "Draw a character or movable obstacle two or three tiles away one open step closer. No recoil or collision damage.",
		"targeting": {"kind": "entity"}, "choices": choices, "unavailable_reason": "no open pull"}


static func _clear_floor_form(state: Dictionary, actor: Dictionary, base: Dictionary) -> Dictionary:
	var form := {"id": "clear_the_floor", "label": "Clear the Floor",
		"help": "Shove everyone and movable obstacles in Guard's reach one open step away. No damage or reflection.",
		"targeting": {"kind": "none"}, "choices": [], "unavailable_reason": "shield away"}
	if actor.has("shield_position"):
		return form
	var radius := Statuses.guard_range(state, actor, Statuses.definition(state, base.params.status))
	var snapshot: Array = []
	var has_landing := false
	for target in Board.occupants(state, {"objects": true, "capabilities": ["pushable"]}):
		var distance := Board.distance(actor.position, target.position)
		if target.id == actor.id or distance == 0 or distance > radius:
			continue
		var direction := Board.dominant_step(actor.position, target.position)
		var destination: Vector2i = target.position + direction
		snapshot.append({"id": target.id, "direction": direction, "destination": destination,
			"distance": distance, "encounter_index": snapshot.size()})
		has_landing = has_landing or Board.can_enter(state, destination)
	form["unavailable_reason"] = "no open shove"
	if has_landing:
		snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.encounter_index < b.encounter_index if a.distance == b.distance else a.distance > b.distance)
		form.choices.append({"id": "", "recipients": snapshot})
	return form


static func perform(state: Dictionary, actor: Dictionary, base_id: String, base: Dictionary,
		form: Dictionary, choice: Dictionary, events: Array) -> void:
	var smith := source(actor)
	clear(actor)
	Board.event(events, "fitted_conversion", "%s: %s → %s (Fitted spent)." % [
		Board.display_name(state, actor), base.label, form.label],
		{"unit_id": actor.id, "source_id": smith, "status_id": "fitted",
			"source_ability_id": base_id, "ability_id": form.id, "consumed": true})
	match form.id:
		"fitted_pull":
			_displace(state, actor, choice, form.label, "pull", events)
		"clear_the_floor":
			for recipient in choice.recipients:
				_displace(state, actor, recipient, form.label, "push", events)


static func _displace(state: Dictionary, actor: Dictionary, choice: Dictionary, label: String,
		event_type: String, events: Array) -> void:
	var target := Board.entity(state, choice.id)
	if not Board.can_enter(state, choice.destination) or Movement.blocks_forced(state, target, events):
		return
	var origin: Vector2i = target.position
	target.position = Movement.forced_destination(state, target, choice.destination, choice.direction, events)
	Board.event(events, event_type, "%s: %s %s from %s to %s." % [label,
		"pull" if event_type == "pull" else "push", Board.display_name(state, target),
		Board.coordinate(origin), Board.coordinate(target.position)],
		{"unit_id": actor.id, "target_id": target.id, "from_position": origin, "position": target.position})
	Shield.retrieve(state, target, events)
