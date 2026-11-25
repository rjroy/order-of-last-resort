extends RefCounted

const Board = preload("res://rules/board.gd")
const Upgrades = preload("res://rules/upgrades.gd")


static func owner(state: Dictionary, minion: Dictionary) -> Dictionary:
	var id: String = minion.get("summoner_id", "")
	return {} if id.is_empty() else Board.entity(state, id)


static func nominated_target(state: Dictionary, actor: Dictionary) -> Dictionary:
	var summoner := owner(state, actor) if actor.has("summoner_id") else actor
	var id: String = summoner.get("nominated_target_id", "")
	var target := {} if id.is_empty() else Board.entity(state, id)
	return target if Board.alive(target) else {}


static func nominate(state: Dictionary, actor: Dictionary, target: Dictionary, events: Array) -> void:
	actor.erase("rally_target_id")
	actor["nominated_target_id"] = target.id
	Board.event(events, "nominate", "%s sends both undead to greet %s." % [
		Board.display_name(state, actor), Board.display_name(state, target)],
		{"unit_id": actor.id, "target_id": target.id})


static func rally_target(state: Dictionary, minion: Dictionary) -> Dictionary:
	var summoner := owner(state, minion) if minion.has("summoner_id") else minion
	var id: String = summoner.get("rally_target_id", "")
	var target := {} if id.is_empty() else Board.entity(state, id)
	return target if Board.alive(target) else {}


static func rally(state: Dictionary, actor: Dictionary, target: Dictionary, events: Array) -> void:
	actor.erase("nominated_target_id")
	actor["rally_target_id"] = target.id
	Board.event(events, "rally", "%s asks both undead to stay close to %s." % [
		Board.display_name(state, actor), Board.display_name(state, target)],
		{"unit_id": actor.id, "target_id": target.id})


static func owned_living(state: Dictionary, actor: Dictionary, character: String) -> Dictionary:
	for unit in state.units:
		if unit.get("summoner_id") == actor.id and unit.character_id == character and Board.alive(unit):
			return unit
	return {}


static func capped(state: Dictionary, actor: Dictionary, character: String) -> bool:
	return not owned_living(state, actor, character).is_empty()


@warning_ignore("integer_division")
static func starting_hp(state: Dictionary, summoner: Dictionary, character: String, corpse: Dictionary = {},
		bonus: int = 0) -> int:
	if not corpse.is_empty():
		return (int(corpse.max_hp) + 1) / 2 + (
			Upgrades.amount(state, summoner, "good_soil") if character == "zombie" else 0) + bonus
	var profile := Board.profile(state, {"character_id": character})
	return int(profile.max_hp) + (Upgrades.amount(state, summoner, "spare_ribs") if character == "skeleton" else 0) + bonus


static func _spawn(state: Dictionary, summoner: Dictionary, character: String, position: Vector2i,
		hp: int, priority: int) -> Dictionary:
	var base_id := "%s_%s" % [summoner.id, character]
	var id := base_id
	var index := 2
	var reserves: Array = state.objective.get("reserves", [])
	while not Board.entity(state, id).is_empty() or reserves.any(func(unit: Dictionary) -> bool: return unit.id == id):
		id = "%s_%d" % [base_id, index]
		index += 1
	var minion := {"id": id, "character_id": character, "position": position,
		"hp": hp, "max_hp": hp, "statuses": {}, "summoner_id": summoner.id, "summon_priority": priority}
	state.units.append(minion)
	return minion


static func summon(state: Dictionary, actor: Dictionary, ability: Dictionary, position: Vector2i,
		corpse: Dictionary, events: Array, bonus: int = 0) -> void:
	var character: String = ability.params.character
	var hp := starting_hp(state, actor, character, corpse, bonus)
	var minion := _spawn(state, actor, character, position, hp, int(ability.params.priority))
	var raising := not corpse.is_empty()
	var data := {"unit_id": actor.id, "summon_id": minion.id, "position": position, "hp": hp}
	var copy := {"actor": Board.display_name(state, actor), "minion": Board.profile(state, minion).label,
		"position": position, "hp": hp}
	if raising:
		minion["raised_from_id"] = corpse.id
		corpse["corpse_consumed"] = true
		data["target_id"] = corpse.id
		data["corpse_id"] = corpse.id
		copy["corpse"] = Board.display_name(state, corpse)
	Board.authored_event(state, events, "summon", "raise" if raising else "summon", copy, data)


static func on_fall(state: Dictionary, fallen: Dictionary, events: Array) -> void:
	for unit in state.units:
		if unit.get("nominated_target_id") == fallen.id:
			unit.erase("nominated_target_id")
		if unit.get("rally_target_id") == fallen.id:
			unit.erase("rally_target_id")
	if fallen.get("character_id") != "zombie" or not fallen.has("raised_from_id"):
		return
	var summoner := owner(state, fallen)
	if summoner.is_empty() or summoner.get("wake_reception_used", false) \
			or Upgrades.amount(state, summoner, "wake_reception") == 0 or capped(state, summoner, "skeleton") \
			or not Board.is_vacant(state, fallen.position):
		return
	var ability: Dictionary = state.catalog.defs.abilities.summon_skeleton
	var hp := starting_hp(state, summoner, "skeleton")
	var skeleton := _spawn(state, summoner, "skeleton", fallen.position, hp, int(ability.params.priority))
	summoner["wake_reception_used"] = true
	Board.event(events, "summon", "Wake Reception: %s falls, and a %d HP skeleton stands in its place at %s." % [
		Board.display_name(state, fallen), hp, Board.coordinate(fallen.position)],
		{"unit_id": summoner.id, "target_id": fallen.id, "summon_id": skeleton.id,
			"position": fallen.position, "hp": hp})
