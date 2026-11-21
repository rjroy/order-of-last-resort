extends RefCounted
## The expedition owns deployment and what persists between missions. Rules owns rounds and outcomes.

const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")


static func start_adventure(definitions: Dictionary, adventure_id: String, picks: Array) -> Dictionary:
	if not Catalog.validate(definitions).is_empty():
		return {}
	var entry: Dictionary = definitions.get("adventures", {}).get(adventure_id, {})
	if entry.is_empty() or picks.size() != int(entry.party_size):
		return {}
	var seen: Dictionary = {}
	for id in picks:
		if not id is String or id not in entry.roster or seen.has(id):
			return {}
		seen[id] = true
	var catalog := Catalog.FrozenCatalog.new(definitions)
	return {"catalog": catalog, "adventure_id": adventure_id, "phase": "ready",
		"mission_ids": entry.missions.duplicate(), "mission_index": 0, "party": picks.duplicate(),
		"mission": {}, "outcome": "ongoing", "carry_by_id": _empty_observation(),
		"last_result": _empty_observation()}


static func begin_mission(run: Dictionary) -> Dictionary:
	if run.get("phase") != "ready":
		return run
	var mission := Rules.open_mission(run.catalog.defs, run.mission_ids[run.mission_index], run.party)
	if mission.is_empty():
		return run
	for member in mission.units:
		var carry: Dictionary = run.carry_by_id.get(member.id, {})
		if carry.is_empty():
			continue
		member.hp = carry.hp
		if not carry.order.is_empty():
			mission.orders[member.id] = carry.order
	# All positions, statuses and per-round commands come from the fresh opening.
	var result := run.duplicate(true)
	# During active play run.mission is the deployed opening; live rounds are Rules snapshots.
	result.mission = mission
	result.phase = "mission"
	result.last_result = _empty_observation()
	# Deep duplication of a Godot Dictionary does not preserve its read-only flag.
	result.carry_by_id = run.carry_by_id
	return result


static func settle_mission(run: Dictionary, committed: Dictionary) -> Dictionary:
	if run.get("phase") != "mission" or not _is_active_result(run, committed):
		return run
	var result := run.duplicate(true)
	result.carry_by_id = run.carry_by_id
	result.last_result = _summarize_mission(run.party, committed)
	if committed.outcome == "victory" and run.mission_index + 1 < run.mission_ids.size():
		result.carry_by_id = _carry_company(run, committed)
		result.mission_index += 1
		result.mission = {}
		result.phase = "ready"
	else:
		result.mission = committed.duplicate(true)
		result.outcome = committed.outcome
		result.phase = "finished"
	return result


static func return_to_guild(run: Dictionary) -> Dictionary:
	if run.get("phase") != "finished":
		return run
	return {"catalog": run.catalog, "adventure_id": run.adventure_id, "phase": "guild",
		"mission_ids": run.mission_ids.duplicate(), "mission_index": 0, "party": [],
		"mission": {}, "outcome": "ongoing", "carry_by_id": _empty_observation(),
		"last_result": _empty_observation()}


static func _is_active_result(run: Dictionary, committed: Dictionary) -> bool:
	return committed.get("catalog") == run.mission.catalog \
		and committed.get("mission_id") == run.mission.mission_id \
		and committed.get("party") == run.party \
		and Rules.new().is_committed_terminal(committed)


static func _carry_company(run: Dictionary, committed: Dictionary) -> Dictionary:
	var carry: Dictionary = {}
	for member in committed.units:
		if member.id not in run.party:
			continue
		var profile := Catalog.profile(run.catalog.defs, member.character_id)
		var order: String = committed.orders.get(member.id, "")
		if not profile.get("habits", {}).has(order):
			order = profile.get("default_order", "")
		var hp: int = member.hp if member.hp > 0 else mini(1, member.max_hp)
		var personal := {"hp": hp, "order": order}
		personal.make_read_only()
		carry[member.id] = personal
	carry.make_read_only()
	return carry


static func _summarize_mission(party: Array, committed: Dictionary) -> Dictionary:
	var rules := Rules.new()
	var heroes: Dictionary = {}
	for member in committed.units:
		if member.id in party:
			var report := {"hp": member.hp, "max_hp": member.max_hp,
				"label": rules.display_name(committed, member.id),
				"knocked_down": rules.knocked_down(committed, member.id)}
			report.make_read_only()
			heroes[member.id] = report
	heroes.make_read_only()
	var summary := {"mission_id": committed.mission_id, "outcome": committed.outcome,
		"text": rules.mission_result_text(committed), "heroes_by_id": heroes}
	summary.make_read_only()
	return summary


static func _empty_observation() -> Dictionary:
	var result: Dictionary = {}
	result.make_read_only()
	return result
