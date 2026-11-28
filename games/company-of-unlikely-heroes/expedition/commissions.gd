extends RefCounted
## Authored destinations and deterministic scouting. No combat or reward RNG is consumed here.

const Catalog = preload("res://content/catalog.gd")
const BOARD_LENGTHS := [5, 5, 10]
const ROAD_TIERS := [1, 1, 2, 2, 3, 4, 4, 5, 5]


static func board(defs: Dictionary, seed_value: int) -> Array:
	if not defs.has("mission_reports") or not Catalog.validate(defs).is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var destinations: Array = []
	for id in defs.mission_reports:
		if defs.mission_reports[id].has("destination_descriptors"):
			destinations.append(id)
	destinations.sort()
	var offers: Array = []
	for length in BOARD_LENGTHS:
		var index := rng.randi_range(0, destinations.size() - 1)
		var id: String = destinations.pop_at(index)
		var descriptions: Array = defs.mission_reports[id].destination_descriptors
		offers.append({"destination_id": id, "length": length,
			"description": _pick(descriptions, rng), "seed": rng.randi()})
	return offers


## Accept a structurally valid offer for this validated catalog.
static func valid_offer(defs: Dictionary, offer: Dictionary) -> bool:
	var id: Variant = offer.get("destination_id")
	var length: Variant = offer.get("length")
	if not id is String or not length is int or length not in BOARD_LENGTHS \
			or not offer.get("seed") is int or not offer.get("description") is String:
		return false
	var report: Dictionary = defs.get("mission_reports", {}).get(id, {})
	return offer.description in report.get("destination_descriptors", [])


static func starting_rng_state(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.state


## The catalog and offer have already been checked when a run is created.
static func draw_reports(defs: Dictionary, destination_id: String, penultimate: bool,
		traversed: Array, promised_kind: String, rng_state: int, position := -1) -> Dictionary:
	var tiered: bool = defs.get("commission_settings", {}).get("tiered", false) == true
	var tier := 0
	var next_tier := 0
	var bases: Dictionary = {}
	if tiered:
		if position == -1:
			position = traversed.size()
		if position != traversed.size() or position < 0 or position >= ROAD_TIERS.size() \
				or (position == ROAD_TIERS.size() - 1 and not penultimate) \
				or (penultimate and position not in [3, 8]) \
				or (position == 0 and not promised_kind.is_empty()) \
				or (position > 0 and promised_kind.is_empty()):
			return {"reports": [], "rng_state": rng_state}
		tier = ROAD_TIERS[position]
		if not penultimate:
			next_tier = ROAD_TIERS[position + 1]
		for id in defs.missions:
			bases[id] = defs.missions[id].get("base_mission_id", id)
	var transit := _transit_by_kind(defs.mission_reports, defs.missions, tier)
	var kinds := transit.keys()
	kinds.sort()
	var next_transit := _transit_by_kind(defs.mission_reports, defs.missions, next_tier) if tiered and not penultimate else transit
	var next_kinds := next_transit.keys()
	next_kinds.sort()
	if kinds.size() < 2 or (not promised_kind.is_empty() and not transit.has(promised_kind)) \
			or (not penultimate and next_kinds.size() < 2):
		return {"reports": [], "rng_state": rng_state}
	var rng := RandomNumberGenerator.new()
	rng.state = rng_state

	var first_kind := promised_kind
	if first_kind.is_empty():
		first_kind = _choose_kind(transit, kinds, traversed, rng, false, bases)
	var other_kinds := kinds.duplicate()
	other_kinds.erase(first_kind)
	var second_kind := _choose_kind(transit, other_kinds, traversed, rng, false, bases)
	var reports: Array = []
	for kind in [first_kind, second_kind]:
		var id := _choose_mission(transit[kind], traversed, rng, bases)
		var hint_kind: String
		var hint_text: String
		if penultimate:
			hint_kind = defs.mission_reports[destination_id].kind
			hint_text = "This route leads to %s, your destination." % defs.missions[destination_id].title
		else:
			hint_kind = _choose_kind(next_transit, next_kinds, traversed + [id], rng, true, bases)
			hint_text = _pick(defs.mission_kinds[hint_kind].descriptors, rng)
		reports.append({"mission_id": id, "description": _pick(defs.mission_reports[id].descriptors, rng),
			"hint_kind": hint_kind, "hint_text": hint_text})
	# The promise is about a kind, not which side of the next fork it appears on.
	if rng.randi_range(0, 1) == 1:
		reports.reverse()
	return {"reports": reports, "rng_state": rng.state}


static func _choose_kind(transit: Dictionary, kinds: Array, traversed: Array,
		rng: RandomNumberGenerator, prefer_spare := false, bases := {}) -> String:
	var fresh: Array = []
	var spare: Array = []
	var without_immediate_repeat: Array = []
	var last: String = _identity(traversed.back(), bases) if not traversed.is_empty() else ""
	var visited := _identities(traversed, bases)
	for kind in kinds:
		var ids: Array = transit[kind]
		var identities := _identities(ids, bases)
		var unplayed := _unplayed(identities, visited).size()
		if unplayed > 0:
			fresh.append(kind)
		if unplayed > 1:
			spare.append(kind)
		if identities.size() > 1 or identities[0] != last:
			without_immediate_repeat.append(kind)
	# For a future promise, prefer kinds that won't run out if played once.
	if prefer_spare and not spare.is_empty():
		return _pick(spare, rng)
	if not fresh.is_empty():
		return _pick(fresh, rng)
	if not without_immediate_repeat.is_empty():
		return _pick(without_immediate_repeat, rng)
	return _pick(kinds, rng)


static func _choose_mission(ids: Array, traversed: Array, rng: RandomNumberGenerator,
		bases := {}) -> String:
	if not bases.is_empty():
		var visited := _identities(traversed, bases)
		var fresh_bases := ids.filter(func(id): return _identity(id, bases) not in visited)
		if not fresh_bases.is_empty():
			return _pick(fresh_bases, rng)
		var last_base := _identity(traversed.back(), bases) if not traversed.is_empty() else ""
		var alternatives := ids.filter(func(id): return _identity(id, bases) != last_base)
		var eligible: Array = alternatives if not alternatives.is_empty() else ids
		var unplayed_ids := _unplayed(eligible, traversed)
		return _pick(unplayed_ids if not unplayed_ids.is_empty() else eligible, rng)
	var fresh := _unplayed(ids, traversed)
	if not fresh.is_empty():
		return _pick(fresh, rng)
	# Repeats keep every promised kind available, but never immediately replay
	# the same battle if another battle of that kind can fill the report.
	var last: String = traversed.back()
	var alternatives := ids.filter(func(id: String) -> bool: return id != last)
	return _pick(alternatives if not alternatives.is_empty() else ids, rng)


static func _unplayed(ids: Array, traversed: Array) -> Array:
	return ids.filter(func(id: String) -> bool: return id not in traversed)


static func _identity(id: String, bases: Dictionary) -> String:
	return str(bases.get(id, id))


static func _identities(ids: Array, bases: Dictionary) -> Array:
	var result: Array = []
	for id in ids:
		var identity := _identity(id, bases)
		if identity not in result:
			result.append(identity)
	return result


static func _pick(choices: Array, rng: RandomNumberGenerator) -> String:
	return choices[rng.randi_range(0, choices.size() - 1)]


## The reports opt missions into the pool; standalone fixtures have no reports.
static func _transit_by_kind(reports: Dictionary, missions: Dictionary, tier := 0) -> Dictionary:
	var transit: Dictionary = {}
	for id in reports:
		var report: Dictionary = reports[id]
		if report.has("destination_descriptors"):
			continue
		if tier != 0 and missions[id].get("tier") != tier:
			continue
		if not transit.has(report.kind):
			transit[report.kind] = []
		transit[report.kind].append(id)
	for ids in transit.values():
		ids.sort()
	return transit
