extends RefCounted

const Board = preload("res://rules/board.gd")
const FittingState = preload("res://rules/fitting_state.gd")
const Frontier = preload("res://rules/frontier_combat.gd")
const Movement = preload("res://rules/movement.gd")
const Shield = preload("res://rules/shield.gd")
const ShieldWall = preload("res://rules/shield_wall.gd")
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
	return Board.dominant_step(from, to)


## Returns whether the primary hit defeated its intended target, not a redirected victim.
static func attack(state: Dictionary, source: Dictionary, intended: Dictionary, damage: int,
		strike: Dictionary, events: Array, retaliation: RetaliationBatch = null) -> bool:
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
	var reflection := Statuses.reflect_attack(state, target, damage, events)
	var hit := {"target": target, "damage": damage}
	if reflection.is_empty():
		return _strike_hit(state, source, intended, hit, strike, events, retaliation)

	var reflected := {"target": reflection.target, "damage": reflection.damage,
		"reflect_origin": target.position}
	if reflection.overflow == 0:
		return _strike_hit(state, source, intended, reflected, strike, events, retaliation)

	hit.damage = reflection.overflow
	if reflection.target.is_empty():
		return _strike_hit(state, source, intended, hit, strike, events, retaliation)
	# A split hit's ward keeps the status and Blast/Throw effects. The other
	# recipient resolves damage and falls immediately, but retaliation waits for both.
	reflected["damage_only"] = true
	var batch := retaliation if retaliation != null else RetaliationBatch.new()
	var defeated_reflected := _strike_hit(state, source, intended, reflected, strike, events, batch)
	var defeated_ward := _strike_hit(state, source, intended, hit, strike, events, batch)
	if retaliation == null:
		flush_retaliation(state, source, events, batch)
	return defeated_reflected or defeated_ward


static func _strike_hit(state: Dictionary, source: Dictionary, intended: Dictionary, hit: Dictionary,
		strike: Dictionary, events: Array, retaliation: RetaliationBatch) -> bool:
	var target: Dictionary = hit.target
	var damage: int = hit.damage
	var id: String = strike.get("ability_id", "")
	var has_effects: bool = not hit.get("damage_only", false)
	# Boosts from a fitting or Inspiration are not part of the aura's budget.
	# They stay with the ward's hit, if any, rather than following reflection.
	var primary_bonus := 0 if hit.has("reflect_origin") else int(strike.get("primary_bonus", 0))
	var impact: Vector2i = strike.get("impact_position", intended.position)
	if not target.is_empty() and (target.id != intended.id or not strike.has("impact_position")):
		impact = target.position
		if target.has("footprint_offsets"):
			var origin: Vector2i = hit.get("reflect_origin", source.position)
			impact = ShieldWall.attack_contact(origin, target).position
	var status_id: String = strike.get("status", "") if has_effects else ""
	if id == "wizard_blast":
		if target.has("object_id"):
			damage += Upgrades.amount(state, source, "demolition_practice")
		if not target.is_empty() and Board.team(state, target) == Board.team(state, source) \
				and Upgrades.amount(state, source, "duck") > 0 and Statuses.is_knockdown(state, status_id):
			status_id = ""
	# The bolt uses the damage this hit would have dealt without its primary-only
	# improvement. Track both through the same defenses, consuming them only once.
	var unimproved := {"amount": damage} if id == "wizard_blast" and primary_bonus > 0 \
		and Upgrades.amount(state, source, "conductive_personality") > 0 else {}
	var presentation := {"data": {"impact_position": impact}, "copy": {}} \
		if target.has("footprint_offsets") else {}
	var amount := _hurt_and_chain(state, source, target, damage + primary_bonus, strike.source_name,
		status_id, events, presentation, unimproved)
	var defeated_intended: bool = amount > 0 and target.id == intended.id and not Board.alive(target)
	if has_effects and id == "knight_shield_throw":
		Shield.dropped(state, source, impact, events)
	elif has_effects and id == "wizard_blast" and amount >= 0:
		_blast_aftereffects(state, source, target, impact, unimproved.get("amount", amount), events, retaliation)
	_after_damage(state, source, target, amount, events, retaliation)
	return defeated_intended


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
		damage: int, events: Array, retaliation: RetaliationBatch) -> void:
	if Upgrades.amount(state, wizard, "parting_gift") > 0 and Board.alive(primary) \
			and not primary.has("footprint_offsets"):
		var direction := toward(wizard.position, impact)
		var destination := impact + direction
		if Board.is_vacant(state, destination) and not Movement.blocks_forced(state, primary, events):
			destination = Movement.forced_destination(state, primary, destination, direction, events)
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
		var presentation := {}
		if recipient.has("footprint_offsets"):
			presentation = {"data": {"impact_position": ShieldWall.attack_contact(impact, recipient).position}, "copy": {}}
		hurt(state, wizard, recipient, ceili(damage * 0.5), "Conductive Personality's bolt", "", events,
			presentation, retaliation)


## Direct damage doesn't redirect. Non-attack damage (songs, recoil, Wave and
## the secondary bolt) shares the on-hit, fall and retaliation lifecycle.
## Returns -1 if nothing was hit, otherwise the resolved damage (before HP clamps).
static func hurt(state: Dictionary, source: Dictionary, target: Dictionary, damage: int,
		source_name: String, status_id: String, events: Array, presentation: Dictionary = {},
		retaliation: RetaliationBatch = null) -> int:
	var amount := _hurt_and_chain(state, source, target, damage, source_name, status_id, events, presentation)
	_after_damage(state, source, target, amount, events, retaliation)
	return amount


## HP loss is not a hit: no mitigation, on-hit modifiers, or retaliation.
static func lose_hp(state: Dictionary, source: Dictionary, target: Dictionary, amount: int,
		cause: String, events: Array) -> void:
	_hurt_and_chain(state, source, target, amount, cause, "", events, {"hp_loss": true,
		"data": {}, "copy": {}, "text": "{source}: {target} loses {amount} HP."})


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
		_hurt_and_chain(state, defender, attacker, amount, name + "’s retaliation", "", events,
			{"data": {"damage_cause": "retaliate"}, "copy": {}})


static func _hurt_and_chain(state: Dictionary, source: Dictionary, target: Dictionary, damage: int,
		source_name: String, status_id: String, events: Array, presentation: Dictionary,
		unimproved: Dictionary = {}) -> int:
	var blasts: Array[Dictionary] = []
	var amount := _apply_hit(state, source, target, damage, source_name, status_id, events,
		presentation, blasts, unimproved)
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
				_apply_hit(state, bomber, victim, blast.damage, name + "’s explosion", "", events,
					{"data": {"damage_cause": "death_blast"}, "copy": {}}, blasts)
		index += 1
	return amount


static func _apply_hit(state: Dictionary, source: Dictionary, target: Dictionary, damage: int,
		source_name: String, status_id: String, events: Array, presentation: Dictionary,
		blasts: Array[Dictionary], unimproved: Dictionary = {}) -> int:
	var hp_loss: bool = presentation.get("hp_loss", false)
	if not Board.alive(target) or (not hp_loss and not Board.capable(state, target, "damageable")):
		return -1
	# Redirect first in attack(); resolve existing bonuses and passive armor
	# before the Alchemist's damage modifiers, Padding, and last-chance survival.
	var amount := damage
	if not hp_loss:
		amount = Statuses.hit_amount(state, target, amount, events, unimproved)
		amount = Frontier.reduce_damage(state, target, amount, events, unimproved)
		amount = Statuses.alchemy_hit_amount(state, source, target, amount, events, unimproved)
		amount = Statuses.absorb_padding(state, target, amount, events, unimproved)
		if amount > 0 and target.has("borrowed_armor"):
			var lender := Board.entity(state, target.borrowed_armor)
			target.erase("borrowed_armor")
			if Board.alive(lender):
				Board.event(events, "borrowed_armor", "%s's borrowed armor blocks the hit." % Board.display_name(state, target),
					{"unit_id": lender.id, "target_id": target.id, "amount": amount})
				amount = 0
				if not unimproved.is_empty():
					unimproved.amount = 0
		amount = Statuses.alchemy_lethal_save(state, target, amount, events, unimproved)
	var previous_hp: int = target.hp
	target.hp = maxi(0, target.hp - amount)
	if amount > 0 and source.get("id", "") != target.id and source.has("character_id") \
			and not Frontier.traits(state, target, "last_damager_pursuit").is_empty():
		target["last_damager_id"] = source.id
	var applied := not status_id.is_empty() and Statuses.apply(state, target, status_id, source, events)
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
	data["hp_lost"] = previous_hp - int(target.hp)
	data["target_team"] = Board.team(state, target)
	data["target_is_character"] = target.has("character_id")
	if presentation.has("text"):
		Board.event(events, "damage", Board.format_text(presentation.text, copy), data)
	else:
		Board.authored_event(state, events, "damage", presentation.get("template", "damage"), copy, data)
	if handler == "retarget":
		Board.authored_event(state, events, "taunt", "taunt",
			{"actor": Board.display_name(state, source), "target": target_name},
			{"source_id": source.id, "target_id": target.id, "status_id": status_id})
	if not Board.alive(target):
		FittingState.clear(target)
		Statuses.clear_fitting_effects(target)
		Summons.on_fall(state, target, events)
		if target.has("character_id"):
			Frontier.mark_corpse_bell(state, target, events)
			Frontier.announce_ally_death(state, target, events)
			Frontier.heal_on_death(state, target, events)
			for trait_spec in Frontier.traits(state, target, "death_blast"):
				blasts.append({"source": target, "position": target.position,
					"damage": int(trait_spec.damage), "range": int(trait_spec.range)})
	return amount
