extends RefCounted


## Reward counts belong to the deployed unit, never to its shared character definition.
static func amount(state: Dictionary, unit: Dictionary, effect: String) -> int:
	var total := 0
	for upgrade in _learned(state, unit):
		var spec: Dictionary = upgrade.spec
		if spec.effect == effect:
			total += int(spec.amount) * int(upgrade.count)
	return total


static func _learned(state: Dictionary, unit: Dictionary) -> Array:
	var result: Array = []
	var counts: Dictionary = unit.get("upgrades", {})
	var table: Dictionary = state.catalog.defs.get("upgrades", {})
	for id in counts:
		var spec: Dictionary = table.get(id, {})
		if counts[id] > 0 and not spec.is_empty() and spec.hero_id == unit.get("character_id"):
			result.append({"spec": spec, "count": counts[id]})
	return result


static func with_grants(state: Dictionary, actor: Dictionary, base: Dictionary) -> Dictionary:
	var profile := base
	var copied := false
	for upgrade in _learned(state, actor):
		var spec: Dictionary = upgrade.spec
		if not spec.has("ability"):
			continue
		if not copied:
			profile = base.duplicate(true)
			copied = true
		if spec.ability not in profile.abilities:
			profile.abilities.append(spec.ability)
		if spec.has("order"):
			profile.habits[spec.order] = spec.behavior
	return profile


static func ability(state: Dictionary, actor: Dictionary, id: String) -> Dictionary:
	var base: Dictionary = state.catalog.defs.abilities.get(id, {})
	if base.is_empty():
		return {}
	var params: Dictionary = base.get("params", {})
	var mods: Dictionary = {}
	var damage_ability: String = params.get("damage_ability", "")
	var referenced: Dictionary = state.catalog.defs.abilities.get(damage_ability, {})
	var reference_params: Dictionary = referenced.get("params", {})
	var reach := 0
	match id:
		"knight_shield_throw":
			mods = {"damage": amount(state, actor, "shield_damage")}
		"healer_bonk":
			mods = {"damage": amount(state, actor, "bonk_damage")}
			reach = amount(state, actor, "long_staff")
		"healer_heal":
			mods = {"amount": amount(state, actor, "heal_amount")}
		"wizard_blast":
			mods = {"damage": amount(state, actor, "blast_damage")}
		"wizard_pull":
			mods = {"recoil_damage": -amount(state, actor, "padded_landing")}
		"healing_sonnet", "bard_take_the_stage":
			mods = {"damage": amount(state, actor, "sonnet_damage")}
		"offer_flower":
			var owner := _summoner(state, actor)
			mods = {"damage": amount(state, owner, "heavy_bouquet")}
			reach = amount(state, owner, "long_stemmed")
		"alchemist_potion":
			mods = {"amount": amount(state, actor, "stronger_dose")}
			reach = amount(state, actor, "long_ladle")
		"alchemist_acid":
			mods = {"damage": amount(state, actor, "concentrate")}
		"blacksmith_hammer_time":
			mods = {"damage": amount(state, actor, "hammer_damage")}
	for key in mods.keys():
		if mods[key] == 0 or (not params.has(key) and not (key == "damage" and reference_params.has("damage"))):
			mods.erase(key)
	if not base.get("targeting", {}).has("range"):
		reach = 0
	if not reference_params.has("damage") and reach == 0 and mods.is_empty():
		return base
	var result := base.duplicate(true)
	if reference_params.has("damage"):
		result.params["damage"] = int(reference_params.damage)
	for key in mods:
		result.params[key] = maxi(0, int(result.params[key]) + mods[key])
	if reach > 0:
		result.targeting.range = int(base.targeting.range) + reach
	if id == "alchemist_potion":
		result.help = "Restore %d HP to yourself or a friendly character within %d tile(s), then apply the forecast reaction." % [
			int(result.params.amount), int(result.targeting.range)]
	elif id == "alchemist_acid":
		result.help = "Deal %d damage to a hostile character within %d tiles, then apply the forecast reaction." % [
			int(result.params.damage), int(result.targeting.range)]
	elif id == "blacksmith_hammer_time":
		result.help = "Deal %d damage to an adjacent opponent or damageable obstacle. Does not shove or taunt." % [
			int(result.params.damage)]
	return result


static func _summoner(state: Dictionary, actor: Dictionary) -> Dictionary:
	var owner_id: String = actor.get("summoner_id", "")
	for unit in state.units:
		if unit.id == owner_id:
			return unit
	return {}
