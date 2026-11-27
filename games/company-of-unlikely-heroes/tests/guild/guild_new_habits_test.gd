extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/guild_new_habits_test.gd
# A test-owned profile buys real petitions; prices are deliberately not asserted.
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")
var rules = preload("res://rules/rules.gd").new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = Catalog.read_default()
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	_test_orders()
	_test_song_weaving()
	if failures.is_empty():
		print("PASS: guild habits and Song Weaving")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _profile() -> Dictionary:
	return {"guild_id": "habit-test", "board_seed": 147258, "board_generation": 0,
		"points": 1000000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": ["knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard"]}


func _buy(profile: Dictionary, id: String) -> Dictionary:
	var bought: Dictionary = Progression.purchased_profile(defs, profile, id)
	_check(not bought.has("error") and id in bought.get("purchased_ids", []),
		"Petition can actually be purchased: " + id)
	return {} if bought.has("error") else bought


func _order_petition(hero: String, order: String) -> String:
	for id in defs.get("guild_progression", {}).get("petitions", {}):
		var grant: Dictionary = defs.guild_progression.petitions[id].get("grant", {})
		if grant.get("hero_id") == hero and grant.get("kind") == "order" and grant.get("order_id") == order:
			return id
	_check(false, hero + " has a purchasable petition for " + order)
	return ""


func _order_ids(profile: Dictionary, hero: String) -> Array:
	var loadout: Dictionary = Progression.default_loadout(defs, profile, hero)
	var ids := []
	for row in Progression.order_options(defs, profile, hero, loadout):
		if row.get("compatible", false):
			ids.append(row.get("id"))
	return ids


func _raw_deployed(profile: Dictionary, hero: String, picks := [], loadouts := {}) -> Dictionary:
	var board: Array = Commissions.board(defs, profile.board_seed)
	if board.is_empty():
		_check(false, "Commission board exists")
		return {}
	var party: Array = [hero, "knight", "healer"] if picks.is_empty() else picks
	var run: Dictionary = Adventure.start_guild_commission(defs, board[0], party, profile, loadouts, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, "Guild commission starts for " + hero)
		return {}
	run = Adventure.choose_route(run, run.reports[0].mission_id)
	run = Adventure.begin_mission(run)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		_check(false, "Guild commission deploys " + hero)
	return state


func _deployed(profile: Dictionary, hero: String, picks := [], loadouts := {}) -> Dictionary:
	var state := _raw_deployed(profile, hero, picks, loadouts)
	if state.is_empty():
		return {}
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [_unit(hero, hero, Vector2i(3, 3)),
		_unit("enemy_a", "harpooner", Vector2i(7, 7)),
		_unit("enemy_b", "harpooner", Vector2i(8, 7)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	state.party = [hero]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	state.rng_state = 12345
	return state


func _unit(id: String, character: String, pos: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": 20, "max_hp": 20, "statuses": {}, "upgrades": {}}


func _find(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _round(state: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	_check(plan.get("valid", false) and state == before and plan == rules.preview_round(state),
		label + ": forecast is valid, deterministic and does not mutate RNG or state")
	if not plan.get("valid", false):
		return {}
	_check(rules.commit_round(state, plan) == plan.get("result") and state == before,
		label + ": commit matches preview without mutating input")
	return plan


func _events(plan: Dictionary, ability: String) -> Array:
	var found := []
	for event in plan.get("events", []):
		if event.get("ability_id") == ability:
			found.append(event)
	return found


func _song_effects(plan: Dictionary, song: String, actor: String, echo := false) -> Array:
	var melody := song == "inspiring_melody"
	var kind := "performance" if melody else "damage"
	return _events(plan, song).filter(func(event: Dictionary) -> bool:
		return event.get("unit_id") == actor and event.get("type") == kind \
			and bool(event.get("song_echo", false)) == echo and not str(event.get("target_id", "")).is_empty() \
			and (not melody or event.get("status_id") == "laughter"))


func _heard_song(plan: Dictionary, song: String, actor: String, listener: String) -> bool:
	return _song_effects(plan, song, actor).any(func(event: Dictionary) -> bool:
		return event.get("target_id") == listener)


func _dry_performance(plan: Dictionary, ability: String, echo: bool) -> bool:
	for event in _events(plan, ability):
		if event.get("type") == "performance" and bool(event.get("song_echo", false)) == echo \
				and "no eligible listener" in str(event.get("text", "")).to_lower() \
				and str(event.get("target_id", "")).is_empty():
			return true
	return false


func _test_orders() -> void:
	var profile := _profile()
	_check("alchemist_acid" in Catalog.profile(defs, "alchemist").abilities,
		"Mixologist retains direct Acid")
	_check("order_throw_samples" in Catalog.profile(defs, "alchemist").habits,
		"Practice retains Throw Samples")
	for pair in [["rogue", "order_pass_the_blame"], ["necromancer", "order_make_a_friend"],
			["alchemist", "order_throw_samples"]]:
		var hero: String = pair[0]
		var order: String = pair[1]
		_check(hero in Progression.roster(defs, profile), "Existing roster access remains for " + hero)
		var equipped_profile := profile
		if hero in ["rogue", "necromancer"]:
			var unrecruited := profile.duplicate(true)
			unrecruited.recruited_ids.erase(hero)
			equipped_profile = _buy(unrecruited, "recruit_" + hero)
			if equipped_profile.is_empty():
				continue
			if hero == "rogue":
				_check(order not in _order_ids(equipped_profile, hero), order + " is not free on recruitment")
				equipped_profile = _buy(equipped_profile, _order_petition(hero, order))
				if equipped_profile.is_empty():
					continue
		else:
			_check(order not in _order_ids(profile, hero), order + " is not free in commissions")
			var petition := _order_petition(hero, order)
			if petition.is_empty():
				continue
			equipped_profile = _buy(profile, petition)
			if equipped_profile.is_empty():
				continue
		_check(order in _order_ids(equipped_profile, hero), order + " is available to recruited hero")
		var state := _deployed(equipped_profile, hero)
		if state.is_empty():
			continue
		_check(order in _ids(rules.options(state, hero)), order + " reaches deployed battle options")
		if hero == "rogue":
			_test_blame(state, order)
		elif hero == "necromancer":
			_test_friend(state, order)
		else:
			_check("alchemist_acid" in _ids(rules.options(state, hero)), "Purchased Mixologist retains direct Acid")
			_find(state, "enemy_a").position = Vector2i(5, 3)
			state = rules.set_order(state, hero, order)
			var plan := _round(state, "Throw Samples")
			if not plan.is_empty():
				_check(not _events(plan, "alchemist_acid").is_empty(),
					"Purchased Throw Samples autonomously uses base Acid")


func _ids(options: Array) -> Array:
	var result := []
	for option in options:
		result.append(option.get("id", ""))
	return result


func _test_blame(state: Dictionary, order: String) -> void:
	_find(state, "enemy_a").position = Vector2i(4, 3)
	_find(state, "enemy_b").position = Vector2i(5, 3)
	state = rules.set_order(state, "rogue", order)
	var first := _round(state, "Pass the Blame nearest")
	if first.is_empty():
		return
	_check(rules.has_status_handler(first.result, "enemy_a", "misdirect"),
		"Pass the Blame marks nearest legal enemy")
	var second := _round(first.result, "Pass the Blame excludes marked")
	if not second.is_empty():
		_check(rules.has_status_handler(second.result, "enemy_b", "misdirect"),
			"Pass the Blame selects another legal enemy rather than re-marking")
		var third := _round(second.result, "Pass the Blame no target")
		if not third.is_empty():
			_check(_events(third, "rogue_wasnt_me").is_empty(), "Pass the Blame holds when none is eligible")
	# Initiative follows the unit array, so reversing it changes the winner.
	var tied := state.duplicate(true)
	_find(tied, "enemy_b").position = Vector2i(3, 4)
	var a := _round(tied, "Pass the Blame tie")
	tied.units.reverse()
	var b := _round(tied, "Pass the Blame reversed tie")
	if not a.is_empty() and not b.is_empty():
		_check(rules.has_status_handler(a.result, "enemy_a", "misdirect")
			and rules.has_status_handler(b.result, "enemy_b", "misdirect"),
			"Equal-distance marks follow initiative order")


func _test_friend(state: Dictionary, order: String) -> void:
	_find(state, "enemy_a").position = Vector2i(8, 3)
	_find(state, "enemy_b").hp = 0
	state = rules.set_order(state, "necromancer", order)
	var first := _round(state, "Make a Friend")
	if first.is_empty():
		return
	var skeletons := []
	for unit in first.result.units:
		if unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0:
			skeletons.append(unit)
	_check(skeletons.size() == 1, "Make a Friend summons exactly one living skeleton")
	if skeletons.size() != 1:
		return
	_check(skeletons[0].position == Vector2i(4, 3), "Skeleton uses open adjacent square nearest opponent")
	var second := _round(first.result, "Make a Friend with existing skeleton")
	if not second.is_empty():
		var count := 0
		for unit in second.result.units:
			if unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0:
				count += 1
		_check(count == 1 and _events(second, "summon_skeleton").is_empty(),
			"Make a Friend holds while a skeleton lives")
	var no_enemy := state.duplicate(true)
	_find(no_enemy, "enemy_a").hp = 0
	var dry := _round(no_enemy, "Make a Friend without opponent")
	if not dry.is_empty():
		_check(_events(dry, "summon_skeleton").is_empty(), "Make a Friend holds without a living opponent")
	var blocked := state.duplicate(true)
	for pos in [Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 2), Vector2i(3, 4)]:
		blocked.obstacles.append({"id": str(pos), "object_id": "crate", "position": pos,
			"hp": 10, "max_hp": 10, "statuses": {}})
	var stuck := _round(blocked, "Make a Friend without open square")
	if not stuck.is_empty():
		_check(_events(stuck, "summon_skeleton").is_empty(), "Make a Friend holds with no legal square")
	var tie := state.duplicate(true)
	_find(tie, "enemy_a").position = Vector2i(8, 8)
	var tie_first := _round(tie, "Make a Friend tied squares")
	var tie_second := _round(tie, "Make a Friend tied squares repeat")
	if not tie_first.is_empty() and not tie_second.is_empty():
		var positions := []
		for plan in [tie_first, tie_second]:
			for unit in plan.result.units:
				if unit.get("character_id") == "skeleton" and unit.get("hp", 0) > 0:
					positions.append(unit.position)
		_check(positions.size() == 2 and positions[0] == positions[1],
			"Equal-distance legal summon squares have a stable tie break")


func _song_round(state: Dictionary, song: String, direct: bool, target := "") -> Dictionary:
	var selected: Dictionary = rules.choose_manual(state, "bard", song, target) if direct \
		else rules.set_order(state, "bard", "order_" + song)
	return _round(selected, ("Direct " if direct else "Standing ") + song)


func _song_sequence(profile: Dictionary, purchased: bool, direct: bool) -> void:
	var state := _deployed(profile, "bard")
	if state.is_empty():
		return
	for index in range(3):
		var song := "healing_sonnet" if index == 1 else "inspiring_melody"
		# The former seed-12345 route chose enemy_a for all three live songs.
		# With Weaving, Melody's round-two echo reaches enemy_b instead.
		var target := "enemy_a" if direct else ""
		var plan := _song_round(state, song, direct, target)
		if plan.is_empty():
			return
		var live := _song_effects(plan, song, "bard")
		var other := "inspiring_melody" if index == 1 else "healing_sonnet"
		var echoes := _song_effects(plan, other, "bard", true)
		_check(live.size() == 1, "Live %s reaches a listener in sequence round %d" % [song, index + 1])
		if not target.is_empty():
			_check(live.size() == 1 and live[0].get("target_id") == target,
				"Direct %s reaches the chosen listener %s in round %d" % [song, target, index + 1])
		_check(echoes.size() == 1 if purchased and index > 0 else _events(plan, other).is_empty(),
			"Only a purchased alternate echoes the immediately previous song")
		if not echoes.is_empty() and not live.is_empty():
			_check(plan.events.find(live[0]) < plan.events.find(echoes[0]), "Live song resolves before echo")
		var damage := _enemy_hp(state) - _enemy_hp(plan.result)
		_check(damage == (1 if index == 1 or (purchased and index == 2) else 0),
			"Sequence applies Sonnet exactly once when live or echoed")
		state = plan.result
	# A repeated melody must not echo the previous echoed sonnet.
	# enemy_a is still immune after round three, so the old draw reached enemy_b.
	var repeated := _song_round(state, "inspiring_melody", direct, "enemy_b" if direct else "")
	if not repeated.is_empty():
		if direct:
			_check(_heard_song(repeated, "inspiring_melody", "bard", "enemy_b"),
				"Repeated Direct Melody reaches the other listener while enemy_a is immune")
		_check(_events(repeated, "healing_sonnet").is_empty(), "Same song and echoed song do not re-prime weaving")
		_check(_enemy_hp(repeated.result) == _enemy_hp(state),
			"Repeating Melody causes no echoed Sonnet damage")


func _enemy_hp(state: Dictionary) -> int:
	return int(_find(state, "enemy_a").get("hp", 0)) + int(_find(state, "enemy_b").get("hp", 0))


func _test_song_weaving() -> void:
	var profile := _buy(_profile(), _order_petition("bard", "order_healing_sonnet"))
	if profile.is_empty():
		return
	for direct in [false, true]:
		_song_sequence(profile, false, direct)
	var purchased := _buy(profile, "song_weaving")
	if purchased.is_empty():
		return
	for direct in [false, true]:
		_song_sequence(purchased, true, direct)
	_test_song_noise_and_reset(purchased)
	_test_song_actor_isolation(purchased)
	var state := _deployed(purchased, "bard")
	if state.is_empty():
		return
	var first := _song_round(state, "inspiring_melody", false)
	if first.is_empty():
		return
	state = rules.choose_manual(first.result, "bard", "move", "3,2")
	var gap := _round(state, "Skipped song round")
	if gap.is_empty():
		return
	var after := _song_round(gap.result, "healing_sonnet", false)
	if not after.is_empty():
		_check(_events(after, "inspiring_melody").is_empty(), "A gap breaks Song Weaving")
	state = _deployed(purchased, "bard")
	if state.is_empty():
		return
	first = _song_round(state, "inspiring_melody", false)
	if first.is_empty():
		return
	state = rules.set_order(first.result, "bard", "order_healing_sonnet")
	_find(state, "bard").statuses = {"knockdown": {"source_id": "enemy_a"}}
	var skipped := _round(state, "Knocked down Bard skips song")
	if not skipped.is_empty():
		_check(_events(skipped, "healing_sonnet").is_empty(), "Knockdown skips the live song")
		after = _song_round(skipped.result, "healing_sonnet", false)
		if not after.is_empty():
			_check(_events(after, "inspiring_melody").is_empty(), "A skipped activation breaks weaving")
	# One listener becomes immune after Melody. An echoed Melody must not
	# bypass that immunity when Sonnet is performed in the following round.
	state = _deployed(purchased, "bard")
	if state.is_empty():
		return
	_find(state, "enemy_b").hp = 0
	first = _song_round(state, "inspiring_melody", false)
	if first.is_empty():
		return
	after = _song_round(first.result, "healing_sonnet", false)
	if not after.is_empty():
		_check(_dry_performance(after, "inspiring_melody", true),
			"Immune listener produces an identifiable dry Melody echo")
		for event in _events(after, "inspiring_melody"):
			_check(event.get("target_id", "") != "enemy_a",
				"Echoed Melody respects the listener's immunity")
		_check(_find(after.result, "enemy_a").hp == 19,
			"Live Sonnet still hits the immune listener")
	# An echo without an eligible listener cannot spend RNG or acquire one.
	state = _deployed(purchased, "bard")
	if state.is_empty():
		return
	first = _song_round(state, "inspiring_melody", false)
	if first.is_empty():
		return
	state = first.result
	_find(state, "enemy_a").hp = 0
	_find(state, "enemy_b").hp = 0
	var rng_before: int = state.rng_state
	after = _song_round(state, "healing_sonnet", false)
	if not after.is_empty():
		_check(after.result.rng_state == rng_before, "Songs with no eligible listener do not draw RNG")
		_check(_dry_performance(after, "healing_sonnet", false)
			and _dry_performance(after, "inspiring_melody", true),
			"Both live Sonnet and echoed Melody report no eligible listener, with echo metadata")
		for event in _events(after, "inspiring_melody"):
			_check(str(event.get("target_id", "")).is_empty(), "Dry echo names no ineligible listener")


func _test_song_noise_and_reset(profile: Dictionary) -> void:
	var state := _deployed(profile, "bard")
	if state.is_empty():
		return
	state.objective = {"handler": "treasure_noise", "treasure": Vector2i(11, 11),
		"noise": 0, "threshold": 100}
	var first := _song_round(state, "inspiring_melody", false)
	if first.is_empty():
		return
	var second := _song_round(first.result, "healing_sonnet", false)
	if second.is_empty():
		return
	var first_noise: int = first.result.objective.noise
	var second_noise: int = second.result.objective.noise - first_noise
	_check(first_noise > 0 and second_noise == first_noise,
		"An echoed song produces no extra objective noise beyond the live song")
	var resolved := 0
	for event in second.events:
		if event.get("resolved_action", {}).get("unit_id") == "bard":
			resolved += 1
	_check(resolved == 1, "Echo is part of one resolved action, not a second objective action")

	# Start another real guild deployment after priming the previous battle.
	var fresh := _raw_deployed(profile, "bard")
	if fresh.is_empty():
		return
	var opening := _song_round(fresh, "healing_sonnet", false)
	if not opening.is_empty():
		_check(not _events(opening, "healing_sonnet").is_empty()
			and _events(opening, "inspiring_melody").is_empty(),
			"Fresh unmodified mission performs Sonnet without echoing the previous battle")
	# A standalone battle must not inherit a guild perk or its song history.
	var standalone_defs: Dictionary = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(defs)
	var standalone: Dictionary = rules.new_game(standalone_defs, "test_escort")
	if standalone.is_empty():
		_check(false, "Standalone practice opens")
		return
	standalone.width = 12
	standalone.height = 12
	standalone.default_tile = "stone"
	standalone.terrain = []
	standalone.obstacles = []
	standalone.units = [_unit("bard", "bard", Vector2i(3, 3)),
		_unit("enemy_a", "harpooner", Vector2i(7, 7)),
		_unit("enemy_b", "harpooner", Vector2i(8, 7)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	standalone.party = ["bard"]
	standalone.orders = {}
	standalone.overrides = {}
	standalone.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	standalone.rng_state = 12345
	first = _song_round(standalone, "inspiring_melody", false)
	if not first.is_empty():
		second = _song_round(first.result, "healing_sonnet", false)
		if not second.is_empty():
			_check(_events(second, "inspiring_melody").is_empty()
				and _enemy_hp(first.result) - _enemy_hp(second.result) == 1,
				"Standalone consecutive songs do not inherit guild weaving")


func _test_song_actor_isolation(profile: Dictionary) -> void:
	var trained := _buy(profile, "necro_learn_melody")
	if trained.is_empty():
		return
	var loadout: Dictionary = Progression.default_loadout(defs, trained, "necromancer")
	if not loadout.get("slots", {}).has("utility"):
		_check(false, "Crypter has a utility slot for learned Melody")
		return
	loadout.slots.utility = "inspiring_melody"
	var state := _deployed(trained, "bard", ["bard", "necromancer", "knight"], {"necromancer": loadout})
	if state.is_empty():
		return
	state.units.insert(1, _unit("necromancer", "necromancer", Vector2i(2, 3)))
	state.party = ["bard", "necromancer"]
	state.orders.erase("bard")
	state = rules.choose_manual(state, "necromancer", "inspiring_melody", "enemy_a")
	var first := _round(state, "Nonwoven Crypter sings first")
	if first.is_empty():
		return
	_check(_heard_song(first, "inspiring_melody", "necromancer", "enemy_a"),
		"Crypter's first Direct Melody makes the chosen listener laugh")
	state = rules.set_order(first.result, "bard", "order_healing_sonnet")
	var second := _round(state, "Bard sings after Crypter")
	if second.is_empty():
		return
	_check(_events(second, "inspiring_melody").is_empty()
		and _heard_song(second, "healing_sonnet", "bard", "enemy_a")
		and _enemy_hp(first.result) - _enemy_hp(second.result) == 1,
		"Crypter's previous song does not prime Bard's weaving")
	state = second.result
	state.orders.erase("bard")
	# The first listener's immunity has expired, and the original third draw chose it again.
	state = rules.choose_manual(state, "necromancer", "inspiring_melody", "enemy_a")
	var third := _round(state, "Crypter sings after Bard")
	if not third.is_empty():
		_check(_heard_song(third, "inspiring_melody", "necromancer", "enemy_a"),
			"Crypter's second Direct Melody makes the chosen listener laugh")
		_check(_events(third, "healing_sonnet").is_empty()
			and _enemy_hp(third.result) == _enemy_hp(second.result),
			"Bard's previous song does not grant weaving to Crypter")
