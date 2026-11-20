extends RefCounted

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT]
const ACTIONS := {
	"knight": [["knight_push", "Push"], ["knight_aura", "Reflecting aura"]],
	"healer": [["healer_bonk", "Bonk and taunt"], ["healer_heal", "Heal nearest ally"]],
	"wizard": [["wizard_blast", "Blast nearest"], ["wizard_pull", "Pull and recoil"]]
}
const ORDERS := {
	"knight": [["order_guard", "Guard"], ["order_advance", "Advance"]],
	"healer": [["order_support", "Support"], ["order_aggressive", "Pursue and bonk"]],
	"wizard": [["order_cautious", "Hold position"], ["order_blast", "Blast nearest"],
		["order_rescue", "Pull civilian toward ferry"]]
}


func _unit(id: String, team: String, role: String, pos: Vector2i, health: int) -> Dictionary:
	return {"id": id, "team": team, "class": role, "position": pos,
		"hp": health, "max_hp": health, "knocked_down": false, "taunted_by": ""}


func new_game(mode: String) -> Dictionary:
	if mode not in ["hybrid", "direct", "standing"]:
		mode = "hybrid"
	var terrain: Array = []
	for y in range(5):
		if y != 2:
			terrain.append({"position": Vector2i(3, y), "type": "gap"})
	terrain.append({"position": Vector2i(3, 2), "type": "bridge"})
	return {"width": 7, "height": 5, "units": [
		_unit("knight", "heroes", "knight", Vector2i(1, 1), 8),
		_unit("healer", "heroes", "healer", Vector2i(0, 2), 7),
		_unit("wizard", "heroes", "wizard", Vector2i(4, 2), 6),
		_unit("harpooner", "enemies", "enemy", Vector2i(5, 1), 6),
		_unit("civilian", "civilian", "civilian", Vector2i(1, 2), 5)],
		"terrain": terrain, "obstacles": [{"id": "crate", "position": Vector2i(2, 2), "hp": 4, "max_hp": 4}],
		"exit": Vector2i(6, 2), "round": 1, "bridge_deadline": 10,
		"mode": mode, "manual_remaining": _budget(mode), "orders": {
			"knight": "order_guard", "healer": "order_support", "wizard": "order_cautious"},
		"overrides": {}, "victory": false, "defeat": false, "outcome": "ongoing"}


func _budget(mode: String) -> int:
	return {"hybrid": 1, "direct": 3, "standing": 0}.get(mode, 0)


func _find(state: Dictionary, id: String) -> Dictionary:
	for entity in state.get("units", []) + state.get("obstacles", []):
		if entity.get("id", "") == id:
			return entity
	return {}


func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _alive(entity: Dictionary) -> bool:
	return not entity.is_empty() and entity.get("hp", 0) > 0


func _free(state: Dictionary, pos: Vector2i, ignore: String = "") -> bool:
	if state.has("width") and (pos.x < 0 or pos.y < 0 or pos.x >= state.width or pos.y >= state.height):
		return false
	for tile in state.get("terrain", []):
		if tile.position == pos and tile.type in ["gap", "collapsed"]:
			return false
	for entity in state.get("units", []) + state.get("obstacles", []):
		if entity.get("id", "") != ignore and _alive(entity) and entity.position == pos:
			return false
	return true


func _event(events: Array, type: String, text: String, data: Dictionary = {}) -> void:
	var entry := data.duplicate(true)
	entry["type"] = type
	entry["text"] = text
	events.append(entry)


func options(state: Dictionary, unit_id: String) -> Array:
	var unit := _find(state, unit_id)
	var result: Array = []
	if unit.get("team", "") != "heroes":
		return result
	result.append({"id": "move", "label": "Move one tile", "kind": "action"})
	for choice in ACTIONS.get(unit.get("class", ""), []):
		result.append({"id": choice[0], "label": choice[1], "kind": "action"})
	for choice in ORDERS.get(unit.get("class", ""), []):
		result.append({"id": choice[0], "label": choice[1], "kind": "order"})
	return result


func set_order(state: Dictionary, unit_id: String, order_id: String) -> Dictionary:
	var result := state.duplicate(true)
	for choice in options(state, unit_id):
		if choice.id == order_id and choice.kind == "order":
			result.get_or_add("orders", {})[unit_id] = order_id
			break
	return result


func targets(state: Dictionary, unit_id: String, ability_id: String) -> Array:
	var actor := _find(state, unit_id)
	var result: Array = []
	if not _alive(actor):
		return result
	if ability_id == "move":
		for direction in DIRECTIONS:
			var pos: Vector2i = actor.position + direction
			if _free(state, pos):
				result.append({"id": "%d,%d" % [pos.x, pos.y], "label": "Move to %d,%d" % [pos.x, pos.y], "position": pos})
	elif ability_id in ["knight_push", "healer_bonk", "wizard_pull"]:
		var candidates: Array = state.get("units", []).duplicate()
		if ability_id != "wizard_pull":
			candidates.append_array(state.get("obstacles", []))
		for target in candidates:
			if target.id == unit_id or not _alive(target):
				continue
			if ability_id == "healer_bonk" and target.get("team", "") != "enemies" and target not in state.get("obstacles", []):
				continue
			if ability_id != "wizard_pull" and _distance(actor.position, target.position) != 1:
				continue
			if ability_id == "wizard_pull" and not _pull_free(state, actor, target):
				continue
			result.append({"id": target.id, "label": str(target.id), "position": target.position})
	return result


func _pull_step(actor: Dictionary, target: Dictionary) -> Vector2i:
	var delta: Vector2i = target.position - actor.position
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		return Vector2i(-signi(delta.x), 0)
	return Vector2i(0, -signi(delta.y))


func _pull_free(state: Dictionary, actor: Dictionary, target: Dictionary) -> bool:
	return actor.position != target.position and _free(state, actor.position + _pull_step(actor, target), actor.id)


func _nearest(state: Dictionary, actor: Dictionary, candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 2147483647
	for candidate in candidates:
		if candidate.get("id", "") == actor.get("id", "") or not _alive(candidate):
			continue
		var distance := _distance(actor.position, candidate.position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _damage(state: Dictionary, target: Dictionary, amount: int, events: Array, source: String, knockdown: bool = false) -> void:
	if not _alive(target):
		return
	target.hp = maxi(0, target.hp - amount)
	if knockdown and target.has("knocked_down"):
		target.knocked_down = true
	_event(events, "damage", "%s deals %d damage to %s%s." % [source, amount, target.id, " and knocks them down" if knockdown and target.has("knocked_down") else ""], {"target_id": target.id, "amount": amount})


func _attack_recipient(state: Dictionary, ward: Dictionary, events: Array) -> Dictionary:
	if not _alive(ward) or ward not in state.get("units", []):
		return ward
	for protector in state.get("units", []):
		if not protector.get("aura", false) or not _alive(protector) or _distance(protector.position, ward.position) > 1:
			continue
		var candidates: Array = []
		for unit in state.get("units", []):
			if unit.get("team", "") == "enemies":
				candidates.append(unit)
		candidates.append_array(state.get("obstacles", []))
		var recipient := _nearest(state, ward, candidates)
		if recipient.is_empty():
			_event(events, "reflect", "%s's aura absorbs the attack on %s; no redirect target remains." % [protector.id, ward.id], {"ward_id": ward.id})
		else:
			_event(events, "reflect", "%s's aura redirects the attack on %s to %s." % [protector.id, ward.id, recipient.id], {"ward_id": ward.id, "target_id": recipient.id})
		return recipient
	return ward


func preview(state: Dictionary, unit_id: String, ability_id: String, target_id: String = "") -> Dictionary:
	var result := state.duplicate(true)
	var events: Array = []
	var actor := _find(result, unit_id)
	var target := _find(result, target_id)
	var valid := _alive(actor)
	if not valid:
		return {"valid": false, "events": events, "result": result}
	var role: String = actor.get("class", "")
	match ability_id:
		"move":
			valid = false
			for choice in targets(result, unit_id, ability_id):
				if choice.id == target_id:
					actor.position = choice.position
					valid = true
					_event(events, "move", "%s moves to %s." % [unit_id, str(actor.position)], {"unit_id": unit_id, "position": actor.position})
					break
		"knight_push":
			valid = role == "knight" and _alive(target) and target_id != unit_id and _distance(actor.position, target.position) == 1
			if valid:
				var destination: Vector2i = target.position + (target.position - actor.position)
				if _free(result, destination):
					target.position = destination
					_event(events, "push", "%s pushes %s to %s." % [unit_id, target_id, str(destination)])
				else:
					_damage(result, _attack_recipient(result, target, events), 2, events, unit_id + "'s collision")
		"knight_aura":
			valid = role == "knight"
			if valid:
				actor["aura"] = true
				_event(events, "aura", "%s raises an aura (range 1) that redirects incoming damage and attack effects; movement and recoil are unaffected." % unit_id)
		"healer_bonk":
			valid = role == "healer" and _alive(target) and (target.get("team", "") == "enemies" or target in result.get("obstacles", [])) and _distance(actor.position, target.position) == 1
			if valid:
				var recipient := _attack_recipient(result, target, events)
				_damage(result, recipient, 2, events, unit_id)
				if _alive(recipient) and recipient.get("team", "") == "enemies":
					recipient.taunted_by = unit_id
					_event(events, "taunt", "%s taunts %s." % [unit_id, recipient.id])
		"healer_heal":
			valid = role == "healer"
			var allies: Array = []
			for unit in result.get("units", []):
				if unit.team == "heroes" and unit.id != unit_id:
					allies.append(unit)
			target = _nearest(result, actor, allies)
			valid = valid and not target.is_empty()
			if valid:
				var amount: int = mini(3, target.max_hp - target.hp)
				target.hp += amount
				_event(events, "heal", "%s heals %s for %d." % [unit_id, target.id, amount])
		"wizard_blast":
			valid = role == "wizard"
			target = _nearest(result, actor, result.get("units", []) + result.get("obstacles", []))
			valid = valid and not target.is_empty()
			if valid:
				_damage(result, _attack_recipient(result, target, events), 4, events, unit_id + "'s blast", true)
		"wizard_pull":
			valid = role == "wizard" and _alive(target) and target_id != unit_id and target.has("team") and _pull_free(result, actor, target)
			if valid:
				var old: Vector2i = actor.position
				actor.position = old + _pull_step(actor, target)
				target.position = old
				_event(events, "pull", "%s pulls %s to %s and recoils to %s." % [unit_id, target_id, str(old), str(actor.position)])
				_damage(result, actor, 2, events, "Recoil", true)
		"enemy_attack", "enemy_harpoon":
			var reach := 1 if ability_id == "enemy_attack" else 2
			valid = actor.get("team", "") == "enemies" and _alive(target) and target_id != unit_id and _distance(actor.position, target.position) >= 1 and _distance(actor.position, target.position) <= reach
			if valid:
				_damage(result, _attack_recipient(result, target, events), 2, events, unit_id + "'s harpoon" if ability_id == "enemy_harpoon" else unit_id)
		_:
			valid = false
	return {"valid": valid, "events": events, "result": result}


func apply_plan(state: Dictionary, plan: Dictionary) -> Dictionary:
	if plan.get("valid", false) and plan.get("result") is Dictionary:
		return plan.result.duplicate(true)
	return state.duplicate(true)


func choose_manual(state: Dictionary, unit_id: String, ability_id: String, target_id: String = "") -> Dictionary:
	var result := state.duplicate(true)
	var allowed := false
	for choice in options(state, unit_id):
		if choice.id == ability_id and choice.kind == "action":
			allowed = true
	if not allowed or state.get("outcome", "ongoing") != "ongoing":
		return result
	var overrides: Dictionary = result.get_or_add("overrides", {})
	if not overrides.has(unit_id):
		if result.get("manual_remaining", 0) <= 0:
			return result
		result.manual_remaining -= 1
	overrides[unit_id] = {"ability_id": ability_id, "target_id": target_id}
	return result


func advance_round(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result["round"] = result.get("round", 1) + 1
	result["manual_remaining"] = _budget(result.get("mode", "hybrid"))
	result["overrides"] = {}
	return result


# Breadth-first search visits neighbors in a fixed order and permits a goal occupied
# by the unit being pursued. Unbounded fixture states use a finite search window.
func _step_toward(state: Dictionary, start: Vector2i, goal: Vector2i, adjacent: bool = false) -> Vector2i:
	var queue: Array = [start]
	var previous := {start: start}
	var found := start
	var index := 0
	var min_x: int = mini(start.x, goal.x) - 8
	var max_x: int = maxi(start.x, goal.x) + 8
	var min_y: int = mini(start.y, goal.y) - 8
	var max_y: int = maxi(start.y, goal.y) + 8
	while index < queue.size():
		var current: Vector2i = queue[index]
		index += 1
		if (adjacent and _distance(current, goal) <= 1) or (not adjacent and current == goal):
			found = current
			break
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if previous.has(next) or next.x < min_x or next.x > max_x or next.y < min_y or next.y > max_y:
				continue
			if not _free(state, next):
				continue
			previous[next] = current
			queue.append(next)
	if found == start:
		return start
	while previous[found] != start:
		found = previous[found]
	return found


func _move_toward(state: Dictionary, unit: Dictionary, goal: Vector2i, events: Array, adjacent: bool = false) -> void:
	var destination := _step_toward(state, unit.position, goal, adjacent)
	if destination != unit.position:
		unit.position = destination
		_event(events, "move", "%s moves to %s." % [unit.id, str(destination)], {"unit_id": unit.id, "position": destination})
	else:
		_event(events, "wait", "%s cannot advance." % unit.id)


func _standing_action(state: Dictionary, unit: Dictionary, order: String) -> Dictionary:
	var enemies: Array = []
	for other in state.get("units", []):
		if other.team == "enemies":
			enemies.append(other)
	var enemy := _nearest(state, unit, enemies)
	match order:
		"order_guard":
			return {"ability_id": "knight_aura"}
		"order_advance":
			if not enemy.is_empty() and _distance(unit.position, enemy.position) == 1:
				return {"ability_id": "knight_push", "target_id": enemy.id}
		"order_support":
			return {"ability_id": "healer_heal"}
		"order_aggressive":
			if not enemy.is_empty() and _distance(unit.position, enemy.position) == 1:
				return {"ability_id": "healer_bonk", "target_id": enemy.id}
		"order_blast":
			return {"ability_id": "wizard_blast"}
		"order_rescue":
			for civilian in state.get("units", []):
				if civilian.get("team", "") != "civilian" or not _alive(civilian):
					continue
				if _distance(unit.position, state.get("exit", Vector2i.ZERO)) < _distance(civilian.position, state.get("exit", Vector2i.ZERO)) and _pull_free(state, unit, civilian):
					return {"ability_id": "wizard_pull", "target_id": civilian.id}
	if order in ["order_advance", "order_aggressive"] and not enemy.is_empty():
		var step := _step_toward(state, unit.position, enemy.position, true)
		if step != unit.position:
			return {"ability_id": "move", "target_id": "%d,%d" % [step.x, step.y]}
	return {}


## The board as a hero's turn starts, with earlier heroes' actions resolved.
func state_before_action(state: Dictionary, unit_id: String) -> Dictionary:
	if _find(state, unit_id).get("team", "") != "heroes":
		return state.duplicate(true)
	return _resolve_heroes(state, [], unit_id)


func _resolve_heroes(state: Dictionary, events: Array, stop_before := "") -> Dictionary:
	var result := state.duplicate(true)
	if state.get("outcome", "ongoing") != "ongoing":
		return result
	for original in state.get("units", []):
		var unit := _find(result, original.id)
		if unit.get("team", "") != "heroes":
			continue
		if _alive(unit):
			unit.erase("aura")
		if unit.id == stop_before:
			break
		if not _alive(unit):
			continue
		if unit.get("knocked_down", false):
			unit.knocked_down = false
			_event(events, "recover", "%s gets up and loses this action." % unit.id)
			continue
		var order = result.get("overrides", {}).get(unit.id, result.get("orders", {}).get(unit.id, ""))
		var action: Dictionary = order if order is Dictionary else _standing_action(result, unit, str(order))
		if action.is_empty():
			_event(events, "wait", "%s holds position." % unit.id)
			continue
		var plan := preview(result, unit.id, action.get("ability_id", ""), action.get("target_id", ""))
		if plan.valid:
			result = plan.result
			events.append_array(plan.events)
		else:
			_event(events, "wait", "%s's action is no longer valid." % unit.id)
	return result


func preview_round(state: Dictionary) -> Dictionary:
	var events: Array = []
	var result := _resolve_heroes(state, events)
	if state.get("outcome", "ongoing") != "ongoing":
		return {"valid": false, "events": events, "result": result}
	for original in state.get("units", []):
		var enemy := _find(result, original.id)
		if enemy.get("team", "") != "enemies" or not _alive(enemy):
			continue
		if enemy.get("knocked_down", false):
			enemy.knocked_down = false
			_event(events, "recover", "%s gets up and loses this action." % enemy.id)
			continue
		var target := _find(result, enemy.get("taunted_by", ""))
		if not _alive(target) or target.get("team", "") != "heroes":
			enemy.taunted_by = ""
			var candidates: Array = []
			for candidate in result.get("units", []):
				if candidate.team in ["heroes", "civilian"]:
					candidates.append(candidate)
			# Threat prioritizes the civilian unless taunted.
			target = _find(result, "civilian")
			if not _alive(target):
				target = _nearest(result, enemy, candidates)
		if target.is_empty():
			continue
		if _distance(enemy.position, target.position) <= 2:
			var plan := preview(result, enemy.id, "enemy_harpoon", target.id)
			if plan.valid:
				result = plan.result
				events.append_array(plan.events)
		elif _distance(enemy.position, target.position) <= 5:
			_move_toward(result, enemy, target.position, events, true)
		else:
			_event(events, "wait", "%s watches for a closer target." % enemy.id)
		enemy = _find(result, original.id)
		enemy.taunted_by = ""
	for original in state.get("units", []):
		var civilian := _find(result, original.id)
		if civilian.get("team", "") != "civilian" or not _alive(civilian):
			continue
		if civilian.get("knocked_down", false):
			civilian.knocked_down = false
			_event(events, "recover", "%s gets up and loses this action." % civilian.id)
		else:
			_move_toward(result, civilian, result.get("exit", Vector2i.ZERO), events)
		if civilian.position == result.get("exit", Vector2i.ZERO):
			result["victory"] = true
			result["outcome"] = "victory"
			_event(events, "victory", "The civilian reaches the ferry!")
			break
	if not result.get("victory", false):
		var civilian_alive := false
		for unit in result.get("units", []):
			if unit.team == "civilian" and _alive(unit):
				civilian_alive = true
		if not civilian_alive or (result.has("bridge_deadline") and result.get("round", 1) >= result.bridge_deadline):
			result["defeat"] = true
			result["outcome"] = "defeat"
			if civilian_alive:
				for tile in result.get("terrain", []):
					if tile.get("type", "") == "bridge":
						tile.type = "collapsed"
			_event(events, "defeat", "The civilian falls." if not civilian_alive else "The ferry departs as the bridge fails.")
	if result.get("outcome", "ongoing") == "ongoing":
		result = advance_round(result)
	return {"valid": true, "events": events, "result": result}


func commit_round(state: Dictionary, plan: Dictionary) -> Dictionary:
	return apply_plan(state, plan)
