extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/smith_inspiration_lifecycle_test.gd
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")
const Rules = preload("res://rules/rules.gd")
var rules := Rules.new()
var defs: Dictionary
var base: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = Catalog.read_default().duplicate(true)
	defs.characters.harpooner.behavior = "hold"
	defs.characters.duelist.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	defs.abilities.healing_sonnet.params.damage = 1
	defs.abilities.enemy_attack.params.damage = 2
	var profile := {"guild_id": "inspiration-test", "board_seed": 147258,
		"board_generation": 0, "points": 100000, "purchased_ids": [],
		"preferred_loadouts": {}, "recruited_ids": ["knight", "healer", "wizard"]}
	for id in ["recruit_bard", "recruit_necromancer", "recruit_blacksmith", "song_weaving", "necro_learn_melody"]:
		profile = Progression.purchased_profile(defs, profile, id)
		if profile.has("error"):
			_check(false, "Purchases " + id + ": " + str(profile))
			_finish()
			return
	var loadout: Dictionary = Progression.default_loadout(defs, profile, "necromancer")
	var grant: Dictionary = defs.guild_progression.petitions.necro_learn_melody.grant
	loadout.slots[grant.slot_id] = grant.ability_id
	var compatible := false
	for order: Dictionary in Progression.order_options(defs, profile, "necromancer", loadout):
		if order.get("compatible", false):
			loadout.order_id = order.id
			compatible = true
			break
	_check(compatible and not Progression.effective_kit(defs, profile, "necromancer", loadout).is_empty(),
		"Purchased Crypter Melody can actually be equipped")
	var board := Commissions.board(defs, profile.board_seed)
	if board.is_empty():
		_check(false, "Commission board opens; catalog errors: " + str(Catalog.validate(defs)))
		_finish()
		return
	var run := Adventure.start_guild_commission(defs, board[0],
		["bard", "necromancer", "blacksmith"], profile, {"necromancer": loadout}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, "Purchased company starts commission")
		_finish()
		return
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	base = run.get("mission", {})
	if base.is_empty():
		_check(false, "Purchased company enters battle")
		_finish()
		return
	_test_borrowed()
	_test_numeric_and_fallback()
	_test_move_and_skip()
	_test_nonnumeric()
	_test_fine_adjustment()
	_test_self_inspiration()
	_test_woven_echo()
	_test_echo_riposte_boundary()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PASS: smith inspiration lifecycle")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _unit(id: String, character: String, at: Vector2i, hp := 20) -> Dictionary:
	return {"id": id, "character_id": character, "position": at,
		"hp": hp, "max_hp": 20, "statuses": {}, "upgrades": {}}


func _entity(s: Dictionary, id: String) -> Dictionary:
	for u: Dictionary in s.get("units", []):
		if u.get("id") == id:
			return u
	return {}


func _state(actor := "bard") -> Dictionary:
	var s := base.duplicate(true)
	s.width = 12
	s.height = 12
	s.default_tile = "stone"
	s.terrain = []
	s.obstacles = []
	s.units = [_unit(actor, actor, Vector2i(3, 3)),
		_unit("blacksmith", "blacksmith", Vector2i(1, 1), 0),
		_unit("enemy", "harpooner", Vector2i(4, 3)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	# A dead Smith's existing fitting persists. The sole living deployed hero
	# is consequently the only possible Melody recipient.
	s.party = [actor, "blacksmith"]
	s.orders = {actor: "order_hold", "blacksmith": "order_hold"}
	s.overrides = {}
	s.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	s.rng_state = 12345
	return s


func _act(s: Dictionary, actor: String, ability: String, target := "") -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview(s, actor, ability, target)
	_check(s == before and plan == rules.preview(s, actor, ability, target),
		ability + " preview is pure and repeatable")
	_check(plan.get("valid", false), ability + " is legal: " + target)
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.apply_plan(s, plan)
	_check(s == before and result == plan.get("result"), ability + " commits its forecast")
	return result


func _round(s: Dictionary, label: String) -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview_round(s)
	_check(plan.get("valid", false) and s == before and plan == rules.preview_round(s),
		label + " has repeatable pure forecast")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.commit_round(s, plan)
	_check(result == plan.get("result") and s == before, label + " commits its forecast")
	return result


func _inspire(actor := "bard") -> Dictionary:
	var s := _state(actor)
	_entity(s, actor).fitted_by = "blacksmith"
	return _act(s, actor, "inspiring_melody")


func _test_borrowed() -> void:
	var s := _inspire("necromancer")
	if s.is_empty():
		return
	_check(_entity(s, "enemy").statuses.is_empty()
		and not _entity(s, "necromancer").has("fitted_by"),
		"Purchased equipped Crypter Melody inspires a hero rather than laughing at enemy")
	s = _act(s, "necromancer", "summon_skeleton", "3,4")
	if s.is_empty():
		return
	var skeletons: Array = s.units.filter(func(u: Dictionary):
		return u.get("character_id") == "skeleton" and u.get("hp", 0) > 0)
	_check(skeletons.size() == 1 and skeletons[0].hp == 2 and skeletons[0].max_hp == 2,
		"Borrowed Melody's actual Crypter recipient boosts next newly summoned skeleton")


func _test_numeric_and_fallback() -> void:
	var s := _inspire()
	if s.is_empty():
		return
	# Full-health company cannot use healing alternate. Ordinary Sonnet spends
	# Inspiration but leaves the fitting.
	_entity(s, "bard").fitted_by = "blacksmith"
	s = _act(s, "bard", "healing_sonnet")
	if s.is_empty():
		return
	_check(_entity(s, "enemy").hp == 18 and _entity(s, "bard").get("fitted_by") == "blacksmith",
		"Inspired ordinary fallback deals two and retains fitting")
	s = _act(s, "bard", "healing_sonnet")
	if not s.is_empty():
		_check(_entity(s, "enemy").hp == 17, "Fallback consumes Inspiration only once")


func _test_move_and_skip() -> void:
	var s := _inspire()
	if s.is_empty():
		return
	s = _act(s, "bard", "move", "3,4")
	if s.is_empty():
		return
	# Hold is a real activation, not an ability. The token must survive it.
	s = _round(s, "Inspired Hold")
	if s.is_empty():
		return
	s = _act(s, "bard", "healing_sonnet")
	if not s.is_empty():
		_check(_entity(s, "enemy").hp == 18, "Move and Hold retain Inspiration for the next performance")
	# Knockdown skips an activation. After the skipped round, a song spends it.
	s = _inspire()
	if s.is_empty():
		return
	_entity(s, "bard").statuses["knockdown"] = {"source_id": "enemy"}
	s.orders.bard = "order_healing_sonnet"
	s = _round(s, "Inspired skipped activation")
	if s.is_empty():
		return
	_check(_entity(s, "enemy").hp == 20, "Knockdown really skips the ordered Sonnet")
	s = _act(s, "bard", "healing_sonnet")
	if not s.is_empty():
		_check(_entity(s, "enemy").hp == 18, "Skipped activation retains Inspiration")


func _test_nonnumeric() -> void:
	var s := _inspire()
	if s.is_empty():
		return
	# A dry or effective ordinary Melody is still a performed nonnumeric action.
	s = _act(s, "bard", "inspiring_melody")
	if s.is_empty():
		return
	# Ordinary Melody may incapacitate the controlled attacker. Remove only
	# that status so the subsequent hit measures the singer's protection.
	_entity(s, "enemy").statuses.clear()
	var hp: int = _entity(s, "bard").hp
	s = _act(s, "enemy", "enemy_attack", "bard")
	if not s.is_empty():
		_check(_entity(s, "bard").hp == hp - 1,
			"Inspired ordinary nonnumeric Melody grants one-hit Steady Hands")


func _test_fine_adjustment() -> void:
	var s := _inspire()
	if s.is_empty():
		return
	_entity(s, "bard").hp = 10
	_entity(s, "bard").fitted_by = "blacksmith"
	_entity(s, "blacksmith").upgrades = {"smith_fine_adjustment": 1}
	s = _act(s, "bard", "healing_sonnet")
	if not s.is_empty():
		_check(_entity(s, "bard").hp == 12,
			"Inspired fitted Sonnet with Fine Adjustment heals base plus one, not plus two")
		_check(not _entity(s, "bard").has("fitted_by"), "Fitted numeric performance spends fitting")


func _test_self_inspiration() -> void:
	var s := _inspire()
	if s.is_empty():
		return
	_entity(s, "bard").fitted_by = "blacksmith"
	_entity(s, "blacksmith").upgrades = {"smith_fine_adjustment": 1}
	s = _act(s, "bard", "inspiring_melody")
	if s.is_empty():
		return
	_entity(s, "enemy").statuses.clear()
	var hp: int = _entity(s, "bard").hp
	s = _act(s, "enemy", "enemy_attack", "bard")
	if s.is_empty():
		return
	_check(_entity(s, "bard").hp == hp - 1,
		"Inspired fitted nonnumeric Melody and Fine Adjustment grant only one Steady Hands")
	s = _act(s, "bard", "healing_sonnet")
	if not s.is_empty():
		_check(_entity(s, "enemy").hp == 18,
			"Spending Inspired before fitted Melody permits the singer to receive one fresh token")


func _test_woven_echo() -> void:
	var s := _state()
	s.orders.bard = "order_healing_sonnet"
	s = _round(s, "First woven Sonnet")
	if s.is_empty():
		return
	_entity(s, "bard").fitted_by = "blacksmith"
	s.orders.bard = "order_inspiring_melody"
	s = _round(s, "Fitted Melody and ordinary woven Sonnet")
	if s.is_empty():
		return
	_check(_entity(s, "enemy").hp == 18,
		"Woven previous Sonnet echoes as ordinary unboosted damage, not a fitted or inspired song")
	s.orders.bard = "order_hold"
	s = _act(s, "bard", "healing_sonnet")
	if not s.is_empty():
		_check(_entity(s, "enemy").hp == 16,
			"Echo did not spend or recursively duplicate the newly granted Inspiration")


func _test_echo_riposte_boundary() -> void:
	# Each case performs a real round-one Sonnet, not an injected weaving
	# history. Crypter produces Inspiration afterward without singing as Bard.
	for example in [
		{"label": "unimproved ordinary", "inspired": false, "fitted": false, "fine": false},
		{"label": "Inspired ordinary", "inspired": true, "fitted": false, "fine": false},
		{"label": "Inspired fitted", "inspired": true, "fitted": true, "fine": false},
		{"label": "Fine Adjustment fitted", "inspired": false, "fitted": true, "fine": true},
	]:
		var label: String = example.label
		var s := _state()
		_entity(s, "enemy").character_id = "duelist"
		s.orders.bard = "order_healing_sonnet"
		s = _round(s, label + " first Sonnet")
		if s.is_empty():
			continue
		_check(s.round == 2 and _entity(s, "enemy").hp == 19,
			label + ": round one really performs the previous Sonnet")
		if example.inspired:
			# First make Crypter ineligible for a duplicate token, then let
			# their purchased fitted Melody choose Bard as the sole candidate.
			s.units.append(_unit("necromancer", "necromancer", Vector2i(8, 8)))
			s.party = ["necromancer", "blacksmith"]
			_entity(s, "necromancer").fitted_by = "blacksmith"
			s = _act(s, "necromancer", "inspiring_melody")
			if s.is_empty():
				continue
			s.party = ["bard", "necromancer", "blacksmith"]
			_entity(s, "necromancer").fitted_by = "blacksmith"
			s = _act(s, "necromancer", "inspiring_melody")
			if s.is_empty():
				continue
			_check(_entity(s, "bard").statuses.has("inspired"),
				label + ": Crypter actually inspires Bard")
		# Keep the control's death nonterminal so commit and forecast have the
		# same ordinary round shape instead of terminal-commit bookkeeping.
		s.units.append(_unit("knight", "knight", Vector2i(0, 9)))
		s.party.append("knight")
		s.orders.knight = "order_hold"
		_entity(s, "bard").hp = 1
		if example.fitted:
			_entity(s, "bard").fitted_by = "blacksmith"
		if example.fine:
			_entity(s, "blacksmith").upgrades = {"smith_fine_adjustment": 1}
		s.orders.bard = "order_inspiring_melody"
		var before := s.duplicate(true)
		var plan: Dictionary = rules.preview_round(s)
		_check(plan.get("valid", false) and s == before and plan == rules.preview_round(s),
			label + ": round-two preview is valid, pure and repeatable")
		if not plan.get("valid", false):
			continue
		_check(rules.commit_round(s, plan) == plan.get("result") and s == before,
			label + ": round-two commit matches preview")
		var events: Array = plan.events
		var live := events.find_custom(func(e: Dictionary):
			return (e.get("unit_id") == "bard" and not e.get("song_echo", false)
				and (e.get("ability_id") == "inspiring_melody"
					or e.get("source_ability_id") == "inspiring_melody")
				and e.get("type") in ["performance", "status"]))
		var echo := events.find_custom(func(e: Dictionary):
			return (e.get("type") == "damage" and e.get("song_echo", false)
				and e.get("ability_id") == "healing_sonnet" and e.get("target_id") == "enemy"))
		var riposte := events.find_custom(func(e: Dictionary):
			return (e.get("type") == "retaliate" and e.get("unit_id") == "enemy"
				and e.get("target_id") == "bard"))
		var steady := events.find_custom(func(e: Dictionary):
			return (e.get("type") == "status" and e.get("status_id") == "steady_hands"
				and e.get("unit_id") == "bard"))
		_check(live >= 0 and echo > live and riposte > echo,
			label + ": live Melody precedes ordinary Sonnet echo and Duelist riposte")
		_check(echo >= 0 and events[echo].get("amount") == 1
			and _entity(plan.result, "enemy").hp == 18,
			label + ": echo deals ordinary unboosted one damage")
		if example.inspired or example.fine:
			_check(steady > live and steady < echo,
				label + ": Steady Hands is granted after live Melody and before echo")
			_check(_entity(plan.result, "bard").hp == 1,
				label + ": one-HP Bard survives the one-damage riposte")
		else:
			_check(steady < 0 and _entity(plan.result, "bard").hp == 0,
				label + ": control has no protection and falls to the riposte")
