extends RefCounted

const Board = preload("res://rules/board.gd")
const Summons = preload("res://rules/summons.gd")
const Upgrades = preload("res://rules/upgrades.gd")


## Count potential occupants, not whether they can reach the circles from here.
static func has_enough_occupants(state: Dictionary, required: int) -> bool:
	var living := Board.occupants(state, {})
	var count := living.size()
	if count >= required:
		return true
	for hero in living:
		if Board.deployed_hero(state, hero) and not hero.has("summoner_id") \
				and not Board.capable(state, hero, "minion"):
			count += _summon_capacity(state, hero)
			if count >= required:
				return true
	return false


static func _summon_capacity(state: Dictionary, hero: Dictionary) -> int:
	var available: Dictionary = {}
	for id in Board.profile(state, hero).abilities:
		var ability := Upgrades.ability(state, hero, id)
		if ability.handler != "summon":
			continue
		var kind: String = ability.params.character
		if available.has(kind) or Summons.capped(state, hero, kind):
			continue
		if ability.targeting.kind == "cell" or _has_corpse(state, hero, ability.targeting):
			available[kind] = true
	return available.size()


static func _has_corpse(state: Dictionary, hero: Dictionary, filters: Dictionary) -> bool:
	# A corpse out of range or behind a moving character can still be raised later.
	for corpse in Board.corpses(state, filters):
		if Board.opponents(state, hero, corpse) and Board.passable(state, corpse.position):
			return true
	return false
