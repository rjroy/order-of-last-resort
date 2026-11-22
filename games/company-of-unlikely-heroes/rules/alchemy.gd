extends RefCounted

const Board = preload("res://rules/board.gd")
const Combat = preload("res://rules/combat.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")
const Statuses = preload("res://rules/statuses.gd")
const Support = preload("res://rules/support.gd")
const Upgrades = preload("res://rules/upgrades.gd")


static func bottled_recipe(state: Dictionary, actor: Dictionary) -> Dictionary:
	return Upgrades.ability(state, actor, actor.get("bottled_reaction", {}).get("recipe", ""))


static func next_reaction(state: Dictionary, actor: Dictionary, handler: String) -> Dictionary:
	match handler:
		"repeat_batch":
			return actor.get("bottled_reaction", {})
		"healing_potion", "acid":
			return Reactions.draw(actor.get("dose_rng_state", state.dose_seed), handler == "acid")
	return {}


static func reaction_forecast(state: Dictionary, actor: Dictionary, handler: String) -> Dictionary:
	var reaction := next_reaction(state, actor, handler)
	if reaction.is_empty():
		return {}
	return {"reaction_id": reaction.id, "category": reaction.category,
		"label": Reactions.POOLS[reaction.category][reaction.id].label,
		"description": Reactions.description(reaction.id, reaction.category)}


static func can_target(state: Dictionary, actor: Dictionary, target: Dictionary, ability: Dictionary) -> bool:
	if not target.has("character_id") or not Board.alive(target):
		return false
	if Board.distance(actor.position, target.position) > int(ability.targeting.range):
		return false
	if ability.handler == "acid":
		return Board.hostile(state, actor, target) and Board.capable(state, target, "damageable")
	# Doses can heal friendly civilians and summons without granting eligibility
	# for the Healer's ability, which uses a different target contract.
	return Board.allied(state, actor, target)


static func administer(state: Dictionary, actor: Dictionary, target: Dictionary, ability: Dictionary,
		id: String, events: Array) -> void:
	if ability.handler == "plain_tonic":
		_healing_dose(state, actor, target, ability, events)
		return
	var reaction := next_reaction(state, actor, ability.handler)
	if ability.handler == "repeat_batch":
		ability = bottled_recipe(state, actor)
		actor.erase("bottled_reaction")
	else:
		actor["dose_rng_state"] = reaction.seed
		if Upgrades.amount(state, actor, "keep_the_culture") > 0:
			actor["bottled_reaction"] = {"id": reaction.id, "category": reaction.category, "recipe": id,
				"recipient": target.id}
	var retaliation: Combat.RetaliationBatch = null
	if ability.handler == "acid":
		retaliation = Combat.RetaliationBatch.new()
		_acid(state, actor, target, ability, events, retaliation)
	else:
		_healing_dose(state, actor, target, ability, events)
	_react(state, actor, target, reaction, events)
	Combat.flush_retaliation(state, actor, events, retaliation)


static func _healing_dose(state: Dictionary, actor: Dictionary, target: Dictionary,
		ability: Dictionary, events: Array) -> void:
	Support.heal(state, actor, target, int(ability.params.amount), events,
		"%s’s %s" % [Board.display_name(state, actor), ability.label])


static func _acid(state: Dictionary, actor: Dictionary, target: Dictionary, ability: Dictionary, events: Array,
		retaliation: Combat.RetaliationBatch) -> void:
	var name := Board.display_name(state, actor)
	var splash := Upgrades.amount(state, actor, "brittle_glass")
	var neighbors: Array = []
	if splash > 0:
		neighbors = Board.occupants(state, {"capabilities": ["damageable"]}).filter(func(unit: Dictionary) -> bool:
			return Board.distance(target.position, unit.position) == 1)
	Combat.hurt(state, actor, target, int(ability.params.damage), "%s’s %s" % [name, ability.label],
		"", events, {}, retaliation)
	for neighbor in neighbors:
		Combat.hurt(state, actor, neighbor, splash, name + "’s Brittle Glass", "", events, {}, retaliation)


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
