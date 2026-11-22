extends RefCounted
## The expedition owns deployment and what persists between missions. Rules owns rounds and outcomes.

const Catalog = preload("res://content/catalog.gd")
const Commissions = preload("res://commissions.gd")
const EncounterRandom = preload("res://rules/encounter_random.gd")
const Progression = preload("res://guild_progression.gd")
const Rewards = preload("res://rewards.gd")
const Rules = preload("res://rules.gd")
const DESTINATION_POINTS := 5


static func start_adventure(definitions: Dictionary, adventure_id: String, picks: Array,
		reward_seed: Variant = null) -> Dictionary:
	if (reward_seed != null and not reward_seed is int) or not Catalog.validate(definitions).is_empty():
		return {}
	var entry: Dictionary = definitions.get("adventures", {}).get(adventure_id, {})
	if not _valid_picks(entry, picks):
		return {}
	var outing_seed: int = randi() if reward_seed == null else reward_seed
	var run := _new_run(definitions, adventure_id, picks, outing_seed, outing_seed)
	run.mission_ids = entry.missions.duplicate()
	return run


static func start_commission(definitions: Dictionary, offer: Dictionary, picks: Array,
		reward_seed: Variant = null) -> Dictionary:
	if (reward_seed != null and not reward_seed is int) or not Catalog.validate(definitions).is_empty() \
			or not Commissions.valid_offer(definitions, offer):
		return {}
	var roster_adventure: String = definitions.commission_settings.roster_adventure
	var entry: Dictionary = definitions.adventures[roster_adventure]
	if not _valid_picks(entry, picks):
		return {}
	return _new_commission(definitions, offer, picks, reward_seed)


## Only the normal stock guild opts in. Test catalogs can exercise the same
## contract explicitly without attaching their external launch to a guild.
static func start_guild_commission(definitions: Dictionary, offer: Dictionary, picks: Array,
		profile: Dictionary, loadouts: Dictionary, reward_seed: Variant = null) -> Dictionary:
	var guild_id: Variant = profile.get("guild_id")
	var board_seed: Variant = profile.get("board_seed")
	var board_generation: Variant = profile.get("board_generation")
	if not guild_id is String or guild_id.is_empty() or not board_seed is int \
			or not board_generation is int or board_generation < 0 \
			or (reward_seed != null and not reward_seed is int) \
			or offer not in Commissions.board(definitions, board_seed) \
			or not Catalog.validate_guild_progression(definitions).is_empty():
		return {}
	var roster_adventure: String = definitions.commission_settings.roster_adventure
	if not _valid_picks(definitions.adventures[roster_adventure], picks):
		return {}
	var kits: Dictionary = {}
	for hero_id in loadouts:
		if hero_id not in picks:
			return {}
	for hero_id in picks:
		var loadout: Variant = loadouts[hero_id] if loadouts.has(hero_id) \
			else Progression.default_loadout(definitions, profile, hero_id)
		if not loadout is Dictionary:
			return {}
		var kit := Progression.effective_kit(definitions, profile, hero_id, loadout)
		if kit.is_empty():
			return {}
		kits[hero_id] = kit
	var run := _new_commission(definitions, offer, picks, reward_seed)
	run["_guild"] = Catalog.FrozenCatalog.new({"guild_id": guild_id, "board_seed": board_seed,
		"board_generation": board_generation, "kits": kits})
	return run


static func _new_commission(definitions: Dictionary, offer: Dictionary, picks: Array,
		reward_seed: Variant) -> Dictionary:
	var roster_adventure: String = definitions.commission_settings.roster_adventure
	var outing_seed: int = offer.seed if reward_seed == null else reward_seed
	var run := _new_run(definitions, roster_adventure, picks, outing_seed, reward_seed)
	run["destination_id"] = offer.destination_id
	run["mission_count"] = offer.length
	run["route_rng_state"] = Commissions.starting_rng_state(offer.seed)
	run["reports"] = []
	run["scout_note"] = ""
	_prepare_next_mission(run)
	return run


## Road wins are the number of advanced expedition positions. An expedition
## advances only on committed road victories, even when a mission ID repeats.
static func receipt(run: Dictionary) -> Dictionary:
	var guild := _guild_data(run)
	if guild.is_empty():
		return {}
	var destination := "not_reached"
	if run.get("phase") == "finished" and run.mission.get("mission_id") == run.destination_id:
		destination = "forfeit" if Rules.new().is_forfeit(run.mission) else run.outcome
	return accounting(guild.board_seed, guild.board_generation, run.mission_index, destination)


static func accounting(board_seed: int, board_generation: int, road_wins: int, destination: String) -> Dictionary:
	var destination_points := DESTINATION_POINTS if destination == "victory" else 0
	return {"board_seed": board_seed, "board_generation": board_generation, "road_wins": road_wins,
		"road_points": road_wins, "destination_outcome": destination, "destination_points": destination_points,
		"points": road_wins + destination_points}


static func settlement_receipt(run: Dictionary, profile: Dictionary) -> Dictionary:
	var guild := _guild_data(run)
	var mission: Variant = run.get("mission")
	if guild.is_empty() or run.get("phase") != "finished" \
			or not is_same(guild.guild_id, profile.get("guild_id")) \
			or not is_same(guild.board_seed, profile.get("board_seed")) \
			or not is_same(guild.board_generation, profile.get("board_generation")) \
			or not mission is Dictionary or mission.get("_guild") != run.get("_guild") \
			or not Rules.new().is_committed_terminal(mission):
		return {}
	return receipt(run)


static func _guild_data(run: Dictionary) -> Dictionary:
	var guild: Variant = run.get("_guild")
	return guild.defs if guild is Catalog.FrozenCatalog else {}


static func choose_route(run: Dictionary, mission_id: String) -> Dictionary:
	if run.get("phase") != "route":
		return run
	for report in run.reports:
		if report.mission_id != mission_id:
			continue
		var result := run.duplicate(true)
		result.carry_by_id = run.carry_by_id
		result.last_result = run.last_result
		result.mission_ids.append(mission_id)
		result["promised_kind"] = report.hint_kind
		result.scout_note = report.hint_text
		result.reports = []
		result.phase = "ready"
		return result
	return run


static func mission_count(run: Dictionary) -> int:
	return int(run.get("mission_count", run.get("mission_ids", []).size()))


static func _valid_picks(entry: Dictionary, picks: Array) -> bool:
	if entry.is_empty() or picks.size() != int(entry.party_size):
		return false
	var seen: Dictionary = {}
	for id in picks:
		if not id is String or not id in entry.roster or seen.has(id):
			return false
		seen[id] = true
	return true


static func _new_run(definitions: Dictionary, adventure_id: String, picks: Array,
		outing_seed: int, reward_seed: Variant) -> Dictionary:
	var catalog := Catalog.FrozenCatalog.new(definitions)
	return {"catalog": catalog, "adventure_id": adventure_id, "phase": "ready",
		"mission_ids": [], "mission_index": 0, "party": picks.duplicate(),
		"mission": {}, "outcome": "ongoing", "carry_by_id": _empty_observation(),
		"last_result": _empty_observation(), "upgrades_by_id": {}, "reward_offers": [], "chosen_reward": {},
		"outing_seed": outing_seed, "reward_rng_state": Rewards.starting_rng_state(reward_seed)}


static func next_mission_max_hp(run: Dictionary, hero_id: String) -> int:
	if hero_id not in run.get("party", []):
		return 0
	var defs: Dictionary = run.catalog.defs
	return int(Catalog.profile(defs, hero_id).max_hp) \
		+ Rewards.max_hp_bonus(defs, hero_id, run.upgrades_by_id.get(hero_id, {}))


static func next_mission_hp(run: Dictionary, hero_id: String) -> int:
	var maximum := next_mission_max_hp(run, hero_id)
	var carry: Dictionary = run.get("carry_by_id", {}).get(hero_id, {})
	if maximum == 0 or carry.is_empty():
		return maximum
	# Fill only new maximum HP; the carried maximum excludes the newly chosen reward.
	return mini(maximum, carry.hp + maxi(0, maximum - carry.max_hp))


static func begin_mission(run: Dictionary) -> Dictionary:
	if run.get("phase") != "ready":
		return run
	var mission_id: String = run.mission_ids[run.mission_index]
	var dose_seed := EncounterRandom.mission_dose_seed(run.outing_seed, run.mission_index, mission_id)
	var mission := Rules.open_mission(run.catalog.defs, mission_id, run.party, dose_seed)
	if mission.is_empty():
		return run
	var guild := _guild_data(run)
	if not guild.is_empty():
		# The same immutable opening kit applies to previews, commits and every
		# subsequent deployment. Temporary upgrades still live on the units.
		mission["_guild"] = run._guild
	for member in mission.units:
		if member.id not in run.party:
			continue
		var owned: Dictionary = run.upgrades_by_id.get(member.id, {})
		member["upgrades"] = owned.duplicate()
		member.max_hp = next_mission_max_hp(run, member.id)
		member.hp = next_mission_hp(run, member.id)
		var carry: Dictionary = run.carry_by_id.get(member.id, {})
		var order: String = carry.get("order", "")
		if order.is_empty() and not guild.is_empty():
			order = guild.kits[member.id].default_order
		if not order.is_empty():
			mission.orders[member.id] = order
	# All positions, statuses and per-round commands come from the fresh opening.
	var result := run.duplicate(true)
	# During active play run.mission is the deployed opening; live rounds are Rules snapshots.
	result.mission = mission
	result.phase = "mission"
	result.last_result = _empty_observation()
	result.chosen_reward = {}
	if result.has("destination_id") and mission.mission_id == result.destination_id:
		result.scout_note = ""
	# Deep duplication of a Godot Dictionary does not preserve its read-only flag.
	result.carry_by_id = run.carry_by_id
	return result


static func settle_mission(run: Dictionary, committed: Dictionary) -> Dictionary:
	if run.get("phase") != "mission" or not _is_active_result(run, committed):
		return run
	var result := run.duplicate(true)
	result.carry_by_id = run.carry_by_id
	result.last_result = _summarize_mission(run.party, committed)
	if committed.outcome == "victory" and run.mission_index + 1 < mission_count(run):
		result.carry_by_id = _carry_company(run, committed)
		result.mission_index += 1
		result.mission = {}
		var draw := Rewards.draw(run.catalog.defs, run.party, run.upgrades_by_id, run.reward_rng_state,
			_guild_data(run).get("kits", {}))
		result.reward_offers = draw.offers
		result.reward_rng_state = draw.rng_state
		if draw.offers.is_empty():
			_prepare_next_mission(result)
		else:
			result.phase = "reward"
	else:
		result.mission = committed.duplicate(true)
		result.outcome = committed.outcome
		result.phase = "finished"
	return result


static func choose_reward(run: Dictionary, hero_id: String, upgrade_id: String) -> Dictionary:
	if run.get("phase") != "reward" or hero_id not in run.party:
		return run
	if not run.reward_offers.has({"hero_id": hero_id, "upgrade_id": upgrade_id}):
		return run
	var owned: Dictionary = run.upgrades_by_id.get(hero_id, {})
	var kit: Dictionary = _guild_data(run).get("kits", {}).get(hero_id, {})
	if not Rewards.eligible(run.catalog.defs, hero_id, upgrade_id, owned, kit):
		return run
	var result := run.duplicate(true)
	result.carry_by_id = run.carry_by_id
	result.last_result = run.last_result
	if not result.upgrades_by_id.has(hero_id):
		result.upgrades_by_id[hero_id] = {}
	result.upgrades_by_id[hero_id][upgrade_id] = int(owned.get(upgrade_id, 0)) + 1
	result.reward_offers = []
	result.chosen_reward = {"hero_id": hero_id, "upgrade_id": upgrade_id}
	_prepare_next_mission(result)
	return result


static func _prepare_next_mission(run: Dictionary) -> void:
	if not run.has("destination_id"):
		run.phase = "ready"
		return
	var remaining := mission_count(run) - int(run.mission_index)
	if remaining == 1:
		run.mission_ids.append(run.destination_id)
		run.erase("promised_kind")
		run.phase = "ready"
		return
	var draw := Commissions.draw_reports(run.catalog.defs, run.destination_id, remaining == 2,
		run.mission_ids, run.get("promised_kind", ""), run.route_rng_state)
	run.reports = draw.reports
	run.route_rng_state = draw.rng_state
	run.erase("promised_kind")
	run.phase = "route"


static func return_to_guild(run: Dictionary) -> Dictionary:
	if run.get("phase") != "finished":
		return run
	return {"catalog": run.catalog, "adventure_id": run.adventure_id, "phase": "guild",
		"mission_ids": [] if run.has("destination_id") else run.mission_ids.duplicate(),
		"mission_index": 0, "party": [],
		"mission": {}, "outcome": "ongoing", "carry_by_id": _empty_observation(),
		"last_result": _empty_observation(), "upgrades_by_id": {}, "reward_offers": [], "chosen_reward": {}}


static func _is_active_result(run: Dictionary, committed: Dictionary) -> bool:
	return committed.get("catalog") == run.mission.catalog \
		and committed.get("mission_id") == run.mission.mission_id \
		and committed.get("party") == run.party \
		and Rules.new().is_committed_terminal(committed)


static func _carry_company(run: Dictionary, committed: Dictionary) -> Dictionary:
	var rules := Rules.new()
	var carry: Dictionary = {}
	for member in committed.units:
		if member.id not in run.party:
			continue
		var profile := rules.entity_profile(committed, member.id)
		var order: String = committed.orders.get(member.id, "")
		if not profile.get("habits", {}).has(order):
			order = profile.get("default_order", "")
		var hp: int = member.hp if member.hp > 0 else mini(1, member.max_hp)
		var personal := {"hp": hp, "max_hp": member.max_hp, "order": order}
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
