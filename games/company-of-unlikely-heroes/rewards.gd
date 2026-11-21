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


static func draw(defs: Dictionary, party: Array, upgrades_by_id: Dictionary, rng_state: int) -> Dictionary:
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
		var eligible: Dictionary = {}
		for id in ids:
			var upgrade: Dictionary = upgrades[id]
			if upgrade.hero_id != hero_id or int(owned.get(id, 0)) >= int(upgrade.cap):
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
