extends RefCounted
## Validate the drill against the ordinary round preview, not clicks alone.

enum Step { ORDER, MOVE, FORECAST_MOVE, FORECAST_BLAST, COMPLETE }

const CASTER := "wizard"
const BLAST_ORDER := "order_blast"

var forecast_open := false
var _reviewed := ""


func allows_order(state: Dictionary, hero: String) -> bool:
	return state.round == 1 and hero == CASTER


func allows_action(state: Dictionary, hero: String, ability: String) -> bool:
	return allows_order(state, hero) and ability == "move" and state.orders.get(CASTER) == BLAST_ORDER


func step(state: Dictionary, plan: Dictionary, aiming: bool) -> Step:
	if state.outcome != "ongoing":
		return Step.COMPLETE
	if state.round > 1:
		return Step.FORECAST_BLAST
	if state.orders.get(CASTER) != BLAST_ORDER:
		return Step.ORDER
	if aiming or _forecast_key(plan).is_empty():
		return Step.MOVE
	return Step.FORECAST_MOVE


func forecast_visibility_changed(opened: bool, plan: Dictionary, editing: bool) -> void:
	forecast_open = opened
	if opened and not editing:
		_reviewed = _forecast_key(plan)


func preview_changed(plan: Dictionary) -> void:
	if _reviewed != _forecast_key(plan):
		_reviewed = ""


func can_commit() -> bool:
	return not _reviewed.is_empty()


func _forecast_key(plan: Dictionary) -> String:
	if not plan.get("valid", false):
		return ""
	var source: Dictionary = plan.source
	if source.orders.get(CASTER) != BLAST_ORDER:
		return ""
	if source.round == 1:
		var move: Dictionary = source.overrides.get(CASTER, {})
		if move.get("ability_id") == "move" and plan.events.any(func(event: Dictionary) -> bool:
			return event.type == "move" and event.get("unit_id") == CASTER \
				and event.get("ability_id") == "move"):
			return "move:" + str(move.target_id)
	elif source.round == 2 and source.overrides.is_empty() and plan.events.any(func(event: Dictionary) -> bool:
		return event.type == "damage" and event.get("source_id") == CASTER \
			and event.get("ability_id") == "wizard_blast" and event.get("target_id") == "practice_archer" \
			and int(event.get("amount", 0)) > 0):
		return "blast"
	return ""
