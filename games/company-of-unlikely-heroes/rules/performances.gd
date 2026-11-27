extends RefCounted

const Board = preload("res://rules/board.gd")
const Combat = preload("res://rules/combat.gd")
const Statuses = preload("res://rules/statuses.gd")
const Support = preload("res://rules/support.gd")
const Upgrades = preload("res://rules/upgrades.gd")


static func perform(state: Dictionary, actor: Dictionary, ability: Dictionary, ability_id: String,
		choice: Dictionary, events: Array, echoed := false, bonus := 0) -> bool:
	var name := Board.display_name(state, actor)
	var copy := {"actor": name, "ability": ability.label}
	var data := {"unit_id": actor.id, "ability_id": ability_id}
	var first_event := events.size()
	if choice.is_empty():
		Board.authored_event(state, events, "performance", "performance_dry", copy, data)
		if ability_id == "inspiring_melody":
			var amount := Upgrades.amount(state, actor, "buskers_hat")
			if amount > 0:
				Support.heal(state, actor, actor, amount, events)
	else:
		var listener := Board.entity(state, choice.id)
		var params: Dictionary = ability.params
		if params.has("status"):
			var application := Statuses.apply_result(state, listener, params.status, actor, events)
			if application == Statuses.Application.REJECTED:
				return false
			copy["target"] = choice.label
			data.merge({"target_id": listener.id, "target_label": choice.label})
			if application == Statuses.Application.APPLIED:
				data["status_id"] = params.status
				Board.authored_event(state, events, "performance", params.listener_event, copy, data)
			else:
				data["resisted_status_id"] = params.status
				Board.event(events, "performance", "%s performs %s. %s resists the knockdown." % [
					name, ability.label, choice.label], data)
		else:
			_sonnet(state, actor, ability, ability_id, listener, events, bonus)
		if choice.has("rng_seed"):
			state.rng_state = choice.rng_seed
	for index in range(first_event, events.size()):
		events[index]["ability_id"] = ability_id
		if echoed:
			events[index]["song_echo"] = true
	if echoed and first_event < events.size():
		events[first_event].text = "Echo of %s — %s" % [ability.label, events[first_event].text]
	return true


static func _sonnet(state: Dictionary, actor: Dictionary, ability: Dictionary, id: String,
		listener: Dictionary, events: Array, bonus: int) -> void:
	var recipients := [listener]
	if id == "bard_take_the_stage":
		for candidate in Board.occupants(state, ability.targeting):
			if candidate.id != listener.id and Board.opponents(state, actor, candidate) \
					and Board.distance(listener.position, candidate.position) == 1 \
					and Board.capable(state, candidate, "damageable"):
				recipients.append(candidate)
	var heckler := id in ["healing_sonnet", "bard_take_the_stage"] and Upgrades.amount(state, actor, "heckler") > 0
	var damage := int(ability.params.damage) + bonus
	var name := Board.display_name(state, actor)
	var retaliation := Combat.RetaliationBatch.new() if recipients.size() > 1 else null
	for recipient in recipients:
		var label := Board.display_name(state, recipient)
		var presentation := {"template": ability.params.listener_event, "copy": {"actor": name, "ability": ability.label},
			"data": {"unit_id": actor.id, "target_label": label}}
		if recipient.id != listener.id:
			presentation["text"] = "{target} also hears {ability} and takes {amount} damage."
		# A song affects its listeners directly; it isn't a redirectable attack.
		Combat.hurt(state, actor, recipient, damage, name, "", events, presentation, retaliation)
		if heckler and Board.alive(recipient):
			recipient.statuses["heckler"] = {"source_id": actor.id}
			Board.event(events, "status", "Heckler: %s will aim their next attack at %s if they can." % [label, name],
				{"unit_id": recipient.id, "target_id": actor.id, "status_id": "heckler"})
	Combat.flush_retaliation(state, actor, events, retaliation)
