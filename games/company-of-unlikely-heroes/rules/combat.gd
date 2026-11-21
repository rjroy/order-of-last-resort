extends RefCounted

const Board = preload("res://rules/board.gd")
const Frontier = preload("res://rules/frontier_combat.gd")
const Shield = preload("res://rules/shield.gd")
const Statuses = preload("res://rules/statuses.gd")
const Summons = preload("res://rules/summons.gd")
const Upgrades = preload("res://rules/upgrades.gd")


# Only retaliation waits for the end of a multi-target action. Redirection,
# mitigation, falls and blast chains still resolve as each hit lands.
class RetaliationBatch:
	# Preserve hit order and allow one response per defender, even if
	# redirection sends more than one original hit to the same Duelist.
	var defenders := {}


static func toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta := to - from
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


static func attack(state: Dictionary, source: Dictionary, intended: Dictionary, damage: int,
		strike: Dictionary, events: Array, retaliation: RetaliationBatch = null) -> void:
	var target := intended
	var id: String = strike.get("ability_id", "")
	if id == "knight_shield_throw":
		for active in Statuses.ids_with_handler(state, source, "reflect"):
			source.statuses.erase(active)
	# Body Double intercepts attacks aimed at the Rogue; a misled attacker
	# selects a different victim before the attack reaches either of them.
	if strike.get("misdirect", true):
		var redirection := Statuses.misdirect_attack(state, source, target, events)
		target = redirection.target
		damage += int(redirection.bonus)
	target = Statuses.double_recipient(state, target, events)
	if strike.has("surround_bonus"):
		damage += _surround_bonus(state, source, target, strike.surround_bonus, events)
	damage = Frontier.attack_damage(state, source, damage, events)
	var reflection := Statuses.reflect_attack(state, target, events)
	damage += int(reflection.bonus)
	target = reflection.target
	var impact: Vector2i = intended.position if target.is_empty() else target.position
	var status_id: String = strike.get("status", "")
	if id == "wizard_blast":
		if target.has("object_id"):
			damage += Upgrades.amount(state, source, "demolition_practice")
		if not target.is_empty() and Board.team(state, target) == Board.team(state, source) \
				and Upgrades.amount(state, source, "duck") > 0 and Statuses.is_knockdown(state, status_id):
			status_id = ""
	var amount := _hurt_and_chain(state, source, target, damage, strike.source_name, status_id, events, {})
	if id == "knight_shield_throw":
		Shield.dropped(state, source, impact, events)
	elif id == "wizard_blast" and amount >= 0:
		_blast_aftereffects(state, source, target, impact, amount, events)
	_after_damage(state, source, target, amount, events, retaliation)


static func _surround_bonus(state: Dictionary, actor: Dictionary, target: Dictionary,
		spec: Dictionary, events: Array) -> int:
	var team := Board.team(state, actor)
	for ally in state.units:
		if ally.id == actor.id or ally.id == target.id or ally.character_id != spec.character \
				or not Board.alive(ally) or Board.team(state, ally) != team \
				or Board.distance(ally.position, target.position) != 1:
			continue
		var damage: int = spec.damage
		Board.authored_event(state, events, "surround", "surround_bonus",
			{"actor": Board.display_name(state, actor), "target": Board.display_name(state, target), "amount": damage},
			{"unit_id": actor.id, "target_id": target.id, "ally_id": ally.id, "amount": damage})
		return damage
	return 0


static func _blast_aftereffects(state: Dictionary, wizard: Dictionary, primary: Dictionary, impact: Vector2i,
		damage: int, events: Array) -> void:
	if Upgrades.amount(state, wizard, "parting_gift") > 0 and Board.alive(primary):
		var destination := impact + toward(wizard.position, impact)
		if Board.is_vacant(state, destination):
			primary.position = destination
			Board.event(events, "push", "Parting Gift pushes %s to %s." % [
				Board.display_name(state, primary), Board.coordinate(destination)],
				{"unit_id": wizard.id, "target_id": primary.id, "position": destination})
			Shield.retrieve(state, primary, events)
	if Upgrades.amount(state, wizard, "conductive_personality") == 0:
		return
	var candidates := Board.occupants(state, {"objects": true, "capabilities": ["damageable"]})
	var recipient := Board.nearest({"id": primary.id, "position": impact}, candidates)
	if not recipient.is_empty():
		hurt(state, wizard, recipient, ceili(damage * 0.5), "Conductive Personality's bolt", "", events)


## Direct damage doesn't redirect. Non-attack damage (songs, recoil, Wave and
## the secondary bolt) shares the on-hit, fall and retaliation lifecycle.
## Returns -1 if nothing was hit, otherwise the resolved damage (before HP clamps).
static func hurt(state: Dictionary, source: Dictionary, target: Dictionary, damage: int,
		source_name: String, status_id: String, events: Array, presentation: Dictionary = {},
		retaliation: RetaliationBatch = null) -> int:
	var amount := _hurt_and_chain(state, source, target, damage, source_name, status_id, events, presentation)
	_after_damage(state, source, target, amount, events, retaliation)
	return amount


static func _after_damage(state: Dictionary, attacker: Dictionary, defender: Dictionary, damage: int,
		events: Array, retaliation: RetaliationBatch) -> void:
	if damage <= 0:
		return
	if retaliation == null:
		_retaliate(state, attacker, defender, events)
	else:
		retaliation.defenders[defender.id] = defender


static func flush_retaliation(state: Dictionary, attacker: Dictionary, events: Array, batch: RetaliationBatch) -> void:
	if batch == null:
		return
	for defender in batch.defenders.values():
		if not Board.alive(attacker):
			break
		_retaliate(state, attacker, defender, events)
	batch.defenders.clear()


static func _retaliate(state: Dictionary, attacker: Dictionary, defender: Dictionary, events: Array) -> void:
	if not Board.alive(defender) or not Board.alive(attacker) \
			or defender.id == attacker.id or not Board.capable(state, attacker, "damageable"):
		return
	var distance := Board.distance(defender.position, attacker.position)
	for trait_spec in Frontier.traits(state, defender, "retaliate"):
		var reach := int(trait_spec.range)
		if distance == 0 or distance > reach or not Board.alive(attacker):
			continue
		var name := Board.display_name(state, defender)
		var amount := int(trait_spec.damage)
		Board.event(events, "retaliate", "%s retaliates against %s for %d damage." % [
			name, Board.display_name(state, attacker), amount],
			{"unit_id": defender.id, "source_id": defender.id, "target_id": attacker.id,
				"amount": amount, "range": reach})
		_hurt_and_chain(state, defender, attacker, amount, name + "’s retaliation", "", events, {})


static func _hurt_and_chain(state: Dictionary, source: Dictionary, target: Dictionary, damage: int,
		source_name: String, status_id: String, events: Array, presentation: Dictionary) -> int:
	var blasts: Array[Dictionary] = []
	var amount := _apply_hit(state, source, target, damage, source_name, status_id, events, presentation, blasts)
	# Finish one blast before processing the next. Only a living-to-fallen
	# transition queues a blast, so the chain can't detonate a body twice.
	var index := 0
	while index < blasts.size():
		var blast := blasts[index]
		var bomber: Dictionary = blast.source
		var name := Board.display_name(state, bomber)
		var area := "adjacent characters" if blast.range == 1 else "characters within %d tiles" % blast.range
		Board.event(events, "death_blast", "%s explodes at %s: %d damage to %s." % [
			name, Board.coordinate(blast.position), blast.damage, area],
			{"unit_id": bomber.id, "source_id": bomber.id, "position": blast.position,
				"amount": blast.damage, "range": blast.range})
		for victim in Board.occupants(state, {"capabilities": ["damageable"]}):
			var distance := Board.distance(blast.position, victim.position)
			if distance > 0 and distance <= blast.range:
				_apply_hit(state, bomber, victim, blast.damage, name + "’s explosion", "", events, {}, blasts)
		index += 1
	return amount


static func _apply_hit(state: Dictionary, source: Dictionary, target: Dictionary, damage: int,
		source_name: String, status_id: String, events: Array, presentation: Dictionary, blasts: Array[Dictionary]) -> int:
	if not Board.alive(target) or not Board.capable(state, target, "damageable"):
		return -1
	# Redirect first in attack(); resolve consumable statuses and then passive
	# protection against the final recipient. No mitigation can restore HP.
	var amount := Frontier.reduce_damage(state, target, Statuses.hit_amount(state, target, damage, events), events)
	target.hp = maxi(0, target.hp - amount)
	var applied := not status_id.is_empty() and Statuses.apply(state, target, status_id, source)
	var handler = Statuses.definition(state, status_id).get("handler", "") if applied else ""
	var suffix := Board.text(state, "knockdown_suffix") if applied and Statuses.is_knockdown(state, status_id) else ""
	var target_name := Board.display_name(state, target)
	var data := {"source_id": source.id, "target_id": target.id, "amount": amount}
	if applied:
		data["status_id"] = status_id
	var copy := {"source": source_name, "amount": amount, "target": target_name, "effect": suffix}
	if not presentation.is_empty():
		data.merge(presentation.data)
		copy.merge(presentation.copy)
	if presentation.has("text"):
		Board.event(events, "damage", Board.format_text(presentation.text, copy), data)
	else:
		Board.authored_event(state, events, "damage", presentation.get("template", "damage"), copy, data)
	if handler == "retarget":
		Board.authored_event(state, events, "taunt", "taunt",
			{"actor": Board.display_name(state, source), "target": target_name},
			{"source_id": source.id, "target_id": target.id, "status_id": status_id})
	if not Board.alive(target):
		Summons.on_fall(state, target, events)
		if target.has("character_id"):
			Frontier.announce_ally_death(state, target, events)
			for trait_spec in Frontier.traits(state, target, "death_blast"):
				blasts.append({"source": target, "position": target.position,
					"damage": int(trait_spec.damage), "range": int(trait_spec.range)})
	return amount
