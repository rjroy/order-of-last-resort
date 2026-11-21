extends RefCounted

const Board = preload("res://rules/board.gd")
const Shield = preload("res://rules/shield.gd")
const Statuses = preload("res://rules/statuses.gd")
const Summons = preload("res://rules/summons.gd")
const Upgrades = preload("res://rules/upgrades.gd")


static func toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta := to - from
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


static func attack(state: Dictionary, source: Dictionary, intended: Dictionary, damage: int,
		strike: Dictionary, events: Array) -> void:
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
	var amount := hurt(state, source, target, damage, strike.source_name, status_id, events)
	if id == "knight_shield_throw":
		Shield.dropped(state, source, impact, events)
	elif id == "wizard_blast" and amount >= 0:
		_blast_aftereffects(state, source, target, impact, amount, events)


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


## Damage itself does not redirect or generate another attack. Non-attack damage
## (songs, recoil, Wave and the secondary bolt) shares the on-hit and fall lifecycle.
## Returns -1 if nothing was hit, otherwise the resolved damage (before HP clamps).
static func hurt(state: Dictionary, source: Dictionary, target: Dictionary, damage: int,
		source_name: String, status_id: String, events: Array, presentation: Dictionary = {}) -> int:
	if not Board.alive(target) or not Board.capable(state, target, "damageable"):
		return -1
	var amount := Statuses.hit_amount(state, target, damage, events)
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
	return amount
