extends RefCounted

const Board = preload("res://rules/board.gd")
const Combat = preload("res://rules/combat.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")
const Statuses = preload("res://rules/statuses.gd")
const Support = preload("res://rules/support.gd")
const Upgrades = preload("res://rules/upgrades.gd")


## Snapshot the dose that actually performed, not a lookup of today's recipe values.
static func bottled_dose(actor: Dictionary) -> Dictionary:
	return actor.get("bottled_reaction", {}).duplicate(true)


static func resolved_dose(recipe: String, base: Dictionary, polarity: String,
		fitted_form := "", fitted_label := "") -> Dictionary:
	var amount: int = base.params.damage if base.handler == "acid" else base.params.amount
	# An ordinary custom recipe may have authored team or capability filters. A
	# fitted recipe replaces those filters with its own friendly/hostile policy.
	var ordinary := fitted_form.is_empty()
	var targeting: Dictionary = base.targeting.duplicate(true) if ordinary \
		else {"kind": "entity", "range": base.targeting.range}
	return {"recipe": recipe, "form": recipe if ordinary else fitted_form,
		"label": base.label if ordinary else fitted_label, "polarity": polarity,
		"amount": amount, "targeting": targeting, "source_handler": base.handler}


static func repeat_choices(state: Dictionary, actor: Dictionary) -> Array:
	return dose_choices(state, actor, actor.get("bottled_reaction", {}))


static func dose_choices(state: Dictionary, actor: Dictionary, dose: Dictionary) -> Array:
	var choices: Array = []
	if dose.is_empty():
		return choices
	for target in Board.occupants(state, dose.targeting):
		if target.id != dose.get("recipient", "") and _can_target(state, actor, target, dose.targeting.range,
				dose.polarity == "damage"):
			choices.append({"id": target.id, "position": target.position, "label": Board.display_name(state, target),
				"missing_hp": int(target.max_hp) - int(target.hp)})
	return choices


static func next_reaction(state: Dictionary, actor: Dictionary, handler: String) -> Dictionary:
	match handler:
		"repeat_batch":
			return _stored_reaction(actor.get("bottled_reaction", {}))
		"healing_potion", "acid":
			return Reactions.draw(actor.get("dose_rng_state", state.dose_seed), handler == "acid")
	return {}


static func _stored_reaction(dose: Dictionary) -> Dictionary:
	return {} if dose.is_empty() else {"id": dose.id, "category": dose.category}


static func dose_reaction(state: Dictionary, actor: Dictionary, dose: Dictionary) -> Dictionary:
	if dose.is_empty() or dose.source_handler == "plain_tonic":
		return {}
	if dose.has("recipient"):
		return _stored_reaction(dose)
	return next_reaction(state, actor, "acid" if dose.polarity == "damage" else "healing_potion")


static func reaction_forecast(state: Dictionary, actor: Dictionary, handler: String) -> Dictionary:
	return describe_reaction(next_reaction(state, actor, handler))


static func describe_reaction(reaction: Dictionary) -> Dictionary:
	if reaction.is_empty():
		return {}
	return {"reaction_id": reaction.id, "category": reaction.category,
		"label": Reactions.POOLS[reaction.category][reaction.id].label,
		"description": Reactions.description(reaction.id, reaction.category)}


static func can_target(state: Dictionary, actor: Dictionary, target: Dictionary, ability: Dictionary) -> bool:
	return _can_target(state, actor, target, int(ability.targeting.range), ability.handler == "acid")


static func _can_target(state: Dictionary, actor: Dictionary, target: Dictionary, reach: int, damaging: bool) -> bool:
	if not target.has("character_id") or not Board.alive(target) \
			or Board.distance(actor.position, target.position) > reach:
		return false
	if damaging:
		return Board.hostile(state, actor, target) and Board.capable(state, target, "damageable")
	# Doses can heal friendly civilians and summons without granting eligibility
	# for the Healer's ability, which uses a different target contract.
	return Board.allied(state, actor, target)


static func administer(state: Dictionary, actor: Dictionary, target: Dictionary, ability: Dictionary,
		id: String, events: Array, bonus := 0) -> void:
	var dose := bottled_dose(actor) if ability.handler == "repeat_batch" else resolved_dose(
		id, ability, "damage" if ability.handler == "acid" else "heal")
	administer_resolved(state, actor, target, dose, dose_reaction(state, actor, dose), bonus, events)


static func administer_resolved(state: Dictionary, actor: Dictionary, target: Dictionary, dose: Dictionary,
		reaction: Dictionary, bonus: int, events: Array) -> void:
	var amount := int(dose.amount) + bonus
	var first := events.size()
	var delivery := {"recipe_id": dose.recipe, "delivery_form_id": dose.form, "polarity": dose.polarity,
		"recipient_id": target.id, "cell": target.position, "amount": amount,
		"reach": int(dose.targeting.get("range", -1))}
	if dose.has("recipient"):
		actor.erase("bottled_reaction")
	elif not reaction.is_empty():
		actor["dose_rng_state"] = reaction.seed
		if Upgrades.amount(state, actor, "keep_the_culture") > 0:
			actor["bottled_reaction"] = dose.merged({"id": reaction.id, "category": reaction.category,
				"recipient": target.id, "amount": amount}, true).duplicate(true)
	var damaging: bool = dose.polarity == "damage"
	var retaliation := Combat.RetaliationBatch.new() if damaging else null
	var splash := Upgrades.amount(state, actor, "brittle_glass") if dose.source_handler == "acid" else 0
	var neighbors: Array = []
	if splash > 0:
		# Snapshot the original impact area before any defeat effects. Glass from
		# a healing dose only reaches living friends; damaging glass still hits either side.
		neighbors = Board.occupants(state, {"capabilities": ["damageable"]} if damaging else {}).filter(
			func(unit: Dictionary) -> bool: return Board.distance(target.position, unit.position) == 1 \
				and (damaging or Board.allied(state, actor, unit)))
	var name := Board.display_name(state, actor)
	var cause := "%s’s %s" % [name, dose.label]
	if damaging:
		Combat.hurt(state, actor, target, amount, cause, "", events, {}, retaliation)
		for neighbor in neighbors:
			Combat.hurt(state, actor, neighbor, splash, name + "’s Brittle Glass", "", events, {}, retaliation)
	else:
		Support.heal(state, actor, target, amount, events, cause)
		for neighbor in neighbors:
			Support.heal(state, actor, neighbor, splash, events, name + "’s Brittle Glass")
	if not reaction.is_empty():
		_react(state, actor, target, reaction, events)
	Combat.flush_retaliation(state, actor, events, retaliation)
	if damaging and dose.source_handler == "healing_potion" and Upgrades.amount(state, actor, "brittle_glass") > 0:
		Board.event(events, "perk_idle", "Brittle Glass: only Acid and Etching Paste recipes splash.",
			{"unit_id": actor.id, "upgrade_effect": "brittle_glass"})
	if events.size() > first:
		# The bottle may already be empty and the recipient may have moved or fallen.
		events[first]["dose_delivery"] = delivery


static func _react(state: Dictionary, actor: Dictionary, target: Dictionary, reaction: Dictionary, events: Array) -> void:
	var id: String = reaction.id
	var category: String = reaction.category
	var name := Board.display_name(state, target)
	var description := Reactions.description(id, category)
	var applied := false
	if category != "cosmetic":
		applied = Statuses.apply_alchemy(state, target, id, actor, events)
		if not applied:
			var reason := "resisted" if Board.alive(target) else "recipient fell"
			description = "%s — no status applied (%s)." % [Reactions.POOLS[category][id].label, reason]
	Board.event(events, "alchemy_reaction", "%s: %s (%s)" % [name, description, category], {"unit_id": actor.id,
		"target_id": target.id, "position": target.position, "reaction_id": id, "category": category,
		"label": Reactions.POOLS[category][id].label, "applied": applied})


static func finish_round(state: Dictionary, events: Array) -> void:
	# Snapshot who qualifies before any reaction changes HP or removes a neighbor.
	var first := events.size()
	var healing: Array = []
	var damage: Array = []
	for target in state.units:
		for id in Reactions.ROUND_END:
			var entry := Statuses.alchemy_status(target, id)
			if entry.is_empty():
				continue
			Statuses.clear_alchemy(target, id)
			if not Board.alive(target) or Statuses.knocked_down(state, target):
				continue
			var spec: Dictionary = Reactions.ROUND_END[id]
			if _meets_adjacency(state, target, spec.get("adjacency", "")):
				var effect := {"id": id, "target": target, "source_id": entry.source_id}
				if spec.heal:
					healing.append(effect)
				else:
					damage.append(effect)
	for effect in healing:
		var source := Board.entity(state, effect.source_id)
		Support.heal(state, source if not source.is_empty() else effect.target, effect.target, 1, events,
			Reactions.POOLS.beneficial[effect.id].label)
	for effect in damage:
		var source := Board.entity(state, effect.source_id)
		Combat.lose_hp(state, source if not source.is_empty() else effect.target, effect.target, 1,
			Reactions.POOLS.harmful[effect.id].label, events)
	for index in range(first, events.size()):
		events[index]["effect_timing"] = "round_end"


static func _meets_adjacency(state: Dictionary, target: Dictionary, relationship: String) -> bool:
	if relationship.is_empty():
		return true
	for neighbor in state.units:
		if Board.alive(neighbor) and Board.distance(target.position, neighbor.position) == 1:
			if relationship == "friendly" and Board.allied(state, target, neighbor):
				return true
			if relationship == "hostile" and Board.hostile(state, target, neighbor):
				return true
	return false
