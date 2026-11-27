extends RefCounted
## Reward draws retain only a PRNG state, independent of the encounter's random choices.

const DEFAULT_WEIGHTS := {"common": 60, "uncommon": 28, "rare": 10, "legendary": 2}


static func starting_rng_state(seed_value: Variant) -> int:
	var rng := RandomNumberGenerator.new()
	if seed_value == null:
		rng.randomize()
	else:
		rng.seed = seed_value
	return rng.state


static func draw(defs: Dictionary, party: Array, upgrades_by_id: Dictionary, rng_state: int,
		kits: Dictionary = {}) -> Dictionary:
	var offers: Array = []
	var upgrades: Dictionary = defs.get("upgrades", {})
	if upgrades.is_empty():
		return {"offers": offers, "rng_state": rng_state}

	var rng := RandomNumberGenerator.new()
	rng.state = rng_state
	var weights: Dictionary = defs.get("reward_weights", DEFAULT_WEIGHTS)
	var ids := upgrades.keys()
	ids.sort()
	for hero_id in party:
		var owned: Dictionary = upgrades_by_id.get(hero_id, {})
		var kit: Dictionary = kits.get(hero_id, {})
		var abilities: Variant = _equipped_with_grants(upgrades, hero_id, owned, kit)
		var habits := _available_habits(defs, hero_id, kit)
		var eligible: Dictionary = {}
		for id in ids:
			var upgrade: Dictionary = upgrades[id]
			if not _eligible(upgrade, hero_id, int(owned.get(id, 0)), abilities, habits):
				continue
			if not eligible.has(upgrade.rarity):
				eligible[upgrade.rarity] = []
			eligible[upgrade.rarity].append(id)
		if eligible.is_empty():
			continue
		var tier := _draw_tier(rng, eligible, weights)
		var pool: Array = eligible[tier]
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		offers.append({"hero_id": hero_id, "upgrade_id": id})
	return {"offers": offers, "rng_state": rng.state}


static func eligible(defs: Dictionary, hero_id: String, upgrade_id: String, owned: Dictionary,
		kit: Dictionary = {}) -> bool:
	var upgrades: Dictionary = defs.get("upgrades", {})
	return _eligible(upgrades.get(upgrade_id, {}), hero_id, int(owned.get(upgrade_id, 0)),
		_equipped_with_grants(upgrades, hero_id, owned, kit), _available_habits(defs, hero_id, kit))


static func _eligible(upgrade: Dictionary, hero_id: String, count: int, abilities: Variant,
		habits: Dictionary) -> bool:
	if upgrade.get("hero_id") != hero_id or count >= int(upgrade.get("cap", 0)):
		return false
	if upgrade.has("requires_order") and not habits.has(upgrade.requires_order):
		return false
	if abilities == null:
		return true
	for id in upgrade.get("requires_abilities", []):
		if id not in abilities:
			return false
	var alternatives: Array = upgrade.get("requires_any_ability", [])
	return alternatives.is_empty() or alternatives.any(func(id: String) -> bool: return id in abilities)


static func _available_habits(defs: Dictionary, hero_id: String, kit: Dictionary) -> Dictionary:
	if not kit.is_empty():
		return kit.get("habits", {}) # Frozen kits include all compatible orders, not just the selected one.
	var hero: Dictionary = defs.get("characters", {}).get(hero_id, {})
	var defaults: Dictionary = defs.get("classes", {}).get(hero.get("class", ""), {})
	return hero.get("habits", defaults.get("habits", {}))


static func _equipped_with_grants(upgrades: Dictionary, hero_id: String, owned: Dictionary,
		kit: Dictionary) -> Variant:
	if kit.is_empty():
		return null # Unscoped outings keep their original ability eligibility.
	var abilities: Array = kit.abilities.duplicate()
	for id in owned:
		var grant: Dictionary = upgrades.get(id, {})
		if int(owned[id]) > 0 and grant.get("hero_id") == hero_id and grant.has("ability"):
			abilities.append(grant.ability)
	return abilities


static func _draw_tier(rng: RandomNumberGenerator, eligible: Dictionary, weights: Dictionary) -> String:
	var total := 0
	for tier in DEFAULT_WEIGHTS:
		if eligible.has(tier):
			total += int(weights[tier])
	var roll := rng.randi_range(1, total)
	for tier in DEFAULT_WEIGHTS:
		if eligible.has(tier):
			roll -= int(weights[tier])
			if roll <= 0:
				return tier
	return ""


static func max_hp_bonus(defs: Dictionary, hero_id: String, owned: Dictionary) -> int:
	var bonus := 0
	var upgrades: Dictionary = defs.get("upgrades", {})
	for id in owned:
		var upgrade: Dictionary = upgrades.get(id, {})
		if upgrade.get("hero_id") == hero_id and upgrade.get("effect") == "max_hp":
			bonus += int(upgrade.amount) * int(owned[id])
	return bonus
