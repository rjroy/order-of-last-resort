extends RefCounted
## Authored destinations and deterministic scouting. No combat or reward RNG is consumed here.

const Catalog = preload("res://content/catalog.gd")
const BOARD_LENGTHS := [5, 5, 10]


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
		traversed: Array, promised_kind: String, rng_state: int) -> Dictionary:
	var transit := _transit_by_kind(defs.mission_reports)
	var kinds := transit.keys()
	kinds.sort()
	var rng := RandomNumberGenerator.new()
	rng.state = rng_state

	var first_kind := promised_kind
	if first_kind.is_empty():
		first_kind = _choose_kind(transit, kinds, traversed, rng)
	var other_kinds := kinds.duplicate()
	other_kinds.erase(first_kind)
	var second_kind := _choose_kind(transit, other_kinds, traversed, rng)
	var reports: Array = []
	for kind in [first_kind, second_kind]:
		var id := _choose_mission(transit[kind], traversed, rng)
		var hint_kind: String
		var hint_text: String
		if penultimate:
			hint_kind = defs.mission_reports[destination_id].kind
			hint_text = "This route leads to %s, your destination." % defs.missions[destination_id].title
		else:
			hint_kind = _choose_kind(transit, kinds, traversed + [id], rng, true)
			hint_text = _pick(defs.mission_kinds[hint_kind].descriptors, rng)
		reports.append({"mission_id": id, "description": _pick(defs.mission_reports[id].descriptors, rng),
			"hint_kind": hint_kind, "hint_text": hint_text})
	# The promise is about a kind, not which side of the next fork it appears on.
	if rng.randi_range(0, 1) == 1:
		reports.reverse()
	return {"reports": reports, "rng_state": rng.state}


static func _choose_kind(transit: Dictionary, kinds: Array, traversed: Array,
		rng: RandomNumberGenerator, prefer_spare := false) -> String:
	var fresh: Array = []
	var spare: Array = []
	var without_immediate_repeat: Array = []
	var last: String = traversed.back() if not traversed.is_empty() else ""
	for kind in kinds:
		var ids: Array = transit[kind]
		var unplayed := _unplayed(ids, traversed).size()
		if unplayed > 0:
			fresh.append(kind)
		if unplayed > 1:
			spare.append(kind)
		if ids.size() > 1 or ids[0] != last:
			without_immediate_repeat.append(kind)
	# For a future promise, prefer kinds that won't run out if played once.
	if prefer_spare and not spare.is_empty():
		return _pick(spare, rng)
	if not fresh.is_empty():
		return _pick(fresh, rng)
	if not without_immediate_repeat.is_empty():
		return _pick(without_immediate_repeat, rng)
	return _pick(kinds, rng)


static func _choose_mission(ids: Array, traversed: Array, rng: RandomNumberGenerator) -> String:
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


static func _pick(choices: Array, rng: RandomNumberGenerator) -> String:
	return choices[rng.randi_range(0, choices.size() - 1)]


## The reports opt missions into the pool; standalone fixtures have no reports.
static func _transit_by_kind(reports: Dictionary) -> Dictionary:
	var transit: Dictionary = {}
	for id in reports:
		var report: Dictionary = reports[id]
		if report.has("destination_descriptors"):
			continue
		if not transit.has(report.kind):
			transit[report.kind] = []
		transit[report.kind].append(id)
	for ids in transit.values():
		ids.sort()
	return transit
