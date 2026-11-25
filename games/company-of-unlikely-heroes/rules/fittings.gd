extends RefCounted
## A fitting belongs to the wearer, not the Smith's turn or current health.

const Board = preload("res://rules/board.gd")
const AlchemyForms = preload("res://rules/fitted_alchemy.gd")
const Catalog = preload("res://content/catalog.gd")
const PerformanceForms = preload("res://rules/fitted_performances.gd")
const SummonForms = preload("res://rules/fitted_summons.gd")
const TacticalForms = preload("res://rules/fitted_tactical.gd")
const FittingState = preload("res://rules/fitting_state.gd")
const Movement = preload("res://rules/movement.gd")
const Shield = preload("res://rules/shield.gd")
const Statuses = preload("res://rules/statuses.gd")
const Upgrades = preload("res://rules/upgrades.gd")
const QUICK_RELEASE := "smith_quick_release"


static func eligible(state: Dictionary, smith: Dictionary, wearer: Dictionary) -> bool:
	return Board.alive(wearer) and wearer.id != smith.id and Board.deployed_hero(state, wearer) \
		and Board.team(state, wearer) == "heroes" and not wearer.has("summoner_id") \
		and not Board.capable(state, wearer, "minion")


static func fit(state: Dictionary, smith: Dictionary, wearer: Dictionary, events: Array) -> void:
	var existing: Array = state.units.filter(func(hero: Dictionary) -> bool:
		return FittingState.source(hero) == smith.id)
	var capacity := 2 if Upgrades.amount(state, smith, "double_shift") > 0 else 1
	var rivets := Upgrades.amount(state, smith, "reinforced_rivets")
	FittingState.apply(wearer, smith.id, rivets)
	var text := "%s uses Try This to fit %s." % [Board.display_name(state, smith), Board.display_name(state, wearer)]
	var data := {"unit_id": smith.id, "target_id": wearer.id, "status_id": "fitted"}
	if existing.size() >= capacity:
		# A custom party can have more candidates than fittings; break ties in deployment order.
		var former: Dictionary = existing[0]
		FittingState.clear(former)
		text += " %s loses the fitting." % Board.display_name(state, former)
		data["replaced_target_id"] = former.id
	if rivets > 0:
		text += " Reinforced Rivets can absorb up to %d damage from their next hit." % rivets
	Board.event(events, "fit", text, data)


static func can_release(state: Dictionary, wearer: Dictionary) -> bool:
	var smith_id := FittingState.source(wearer)
	if smith_id.is_empty():
		return false
	var smith := Board.entity(state, smith_id)
	return not smith.is_empty() and eligible(state, smith, wearer) \
		and Upgrades.amount(state, smith, "quick_release") > 0


static func release(state: Dictionary, wearer: Dictionary, events: Array) -> void:
	var smith_id := FittingState.source(wearer)
	FittingState.clear(wearer)
	Board.event(events, "fitted_release", "Quick Release: %s removes their fitting." % Board.display_name(state, wearer),
		{"unit_id": wearer.id, "source_id": smith_id, "status_id": "fitted", "consumed": true})


static func report_pending(state: Dictionary, events: Array) -> void:
	for hero in state.units:
		var smith_id := FittingState.source(hero)
		if not smith_id.is_empty():
			Board.event(events, "fitted_pending", "%s stays Fitted (by %s)." % [
				Board.display_name(state, hero), Board.display_name(state, Board.entity(state, smith_id))],
				{"unit_id": hero.id, "source_id": smith_id, "status_id": "fitted"})
		if Board.alive(hero) and Statuses.inspired(hero):
			Board.event(events, "inspired_pending", "%s stays Inspired for their next performed ability." % [
				Board.display_name(state, hero)], {"unit_id": hero.id, "status_id": Statuses.INSPIRED})


static func clear_mission(state: Dictionary) -> void:
	for unit in state.units:
		FittingState.clear(unit)
		Statuses.clear_fitting_effects(unit)


## Return the registered form even when unavailable so callers can explain why the base branch wins.
static func alternate(state: Dictionary, actor: Dictionary, source_id: String, base: Dictionary) -> Dictionary:
	if FittingState.source(actor).is_empty():
		return {}
	match base.get("fitted_form"):
		"fitted_pull":
			return _pull_form(state, actor)
		"clear_the_floor":
			return _clear_floor_form(state, actor, base)
	var adapter := _adapter(base.fitted_form)
	return adapter.describe(state, actor, source_id, base) if adapter != null else {}


static func _adapter(id: String) -> GDScript:
	var registration: Array = Catalog.FITTED_FORMS.get(id, [])
	if registration.is_empty():
		return null
	match registration[1]:
		"alchemy":
			return AlchemyForms
		"performances":
			return PerformanceForms
		"summons":
			return SummonForms
		"tactical":
			return TacticalForms
	return null


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
		"targeting": {"kind": "entity"}, "choices": choices, "unavailable_reason": "no open pull",
		"primary": "steady"}


static func _clear_floor_form(state: Dictionary, actor: Dictionary, base: Dictionary) -> Dictionary:
	var form := {"id": "clear_the_floor", "label": "Clear the Floor",
		"help": "Shove everyone and movable obstacles in Guard's reach one open step away. No damage or reflection.",
		"targeting": {"kind": "none"}, "choices": [], "unavailable_reason": "shield away",
		"primary": "steady"}
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


static func consume(state: Dictionary, actor: Dictionary, base_id: String, base: Dictionary,
		form: Dictionary, choice: Dictionary, events: Array) -> void:
	var smith := FittingState.source(actor)
	FittingState.clear(actor)
	var data := {"unit_id": actor.id, "source_id": smith, "status_id": "fitted",
		"source_ability_id": base_id, "ability_id": form.id, "consumed": true}
	if not choice.id.is_empty():
		data["target_id"] = choice.id
	Board.event(events, "fitted_conversion", "%s: %s → %s (Fitted spent)." % [
		Board.display_name(state, actor), base.label, form.label], data)


static func apply(state: Dictionary, actor: Dictionary, source_id: String, base: Dictionary,
		form: Dictionary, choice: Dictionary, bonus: int, events: Array) -> void:
	match form.id:
		"fitted_pull":
			_displace(state, actor, choice, form.label, "pull", events)
		"clear_the_floor":
			for recipient in choice.recipients:
				_displace(state, actor, recipient, form.label, "push", events)
		_:
			_adapter(form.id).apply(state, actor, source_id, base, form, choice, bonus, events)


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
