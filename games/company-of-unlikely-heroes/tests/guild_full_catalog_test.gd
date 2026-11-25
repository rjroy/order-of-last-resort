extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_full_catalog_test.gd
# The register is an integration contract; prices are deliberately not pinned.
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild_progression.gd")
const Adventure = preload("res://adventure.gd")
const Commissions = preload("res://commissions.gd")
const Rules = preload("res://rules.gd")
const Rewards = preload("res://rewards.gd")
const FOUNDERS := ["knight", "healer", "wizard"]
const RECRUITS := {"recruit_bard": "bard", "recruit_rogue": "rogue",
	"recruit_necromancer": "necromancer", "recruit_alchemist": "alchemist",
	"recruit_blacksmith": "blacksmith"}
# recipient and explicit cumulative prerequisites; recruitment of the recipient
# is checked independently even for entries with no explicit prerequisite.
const TRAINING := {
	"knight_rescue_line": ["knight", []],
	"knight_escort_order": ["knight", []],
	"knight_learn_bonk": ["knight", []],
	"teach_healer_blast": ["healer", []],
	"healer_blast_order": ["healer", ["teach_healer_blast"]],
	"healer_field_dressing": ["healer", []],
	"healer_triage_order": ["healer", ["healer_field_dressing"]],
	"wizard_ring_sparks": ["wizard", []],
	"wizard_stand_back": ["wizard", []],
	"wizard_learn_dodge": ["wizard", ["recruit_rogue"]],
	"song_weaving": ["bard", ["recruit_bard"]],
	"bard_learn_push": ["bard", []],
	"bard_follow_company": ["bard", []],
	"rogue_tripwire": ["rogue", []],
	"rogue_tripwire_order": ["rogue", ["rogue_tripwire"]],
	"rogue_learn_potion": ["rogue", ["recruit_alchemist"]],
	"necro_grave_bell": ["necromancer", []],
	"necro_bell_order": ["necromancer", ["necro_grave_bell"]],
	"necro_learn_melody": ["necromancer", ["recruit_bard"]],
	"alchemist_throw_samples": ["alchemist", []],
	"alchemist_etching_paste": ["alchemist", []],
	"alchemist_learn_pull": ["alchemist", []],
	"blacksmith_learn_bonk": ["blacksmith", ["recruit_blacksmith"]],
	"blacksmith_learn_acid": ["blacksmith", ["recruit_blacksmith", "recruit_alchemist"]],
}

var failures: Array[String] = []
var defs: Dictionary
var rules := Rules.new()


func _initialize() -> void:
	defs = Catalog.read_default()
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	_test_register()
	_test_fallback_hold_preference()
	_test_practice_and_scoping()
	_test_teaching_is_not_a_habit()
	_test_scoped_actions()
	_test_tripwire_next_movement()
	_test_paste_culture()
	if failures.is_empty():
		print("PASS: full guild petition register")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _profile() -> Dictionary:
	return {"guild_id": "full-catalog-test", "board_seed": 147258, "board_generation": 0,
		"points": 1000000, "purchased_ids": [], "preferred_loadouts": {},
		"recruited_ids": FOUNDERS.duplicate()}


func _row(profile: Dictionary, id: String) -> Dictionary:
	for row in Progression.petitions(defs, profile):
		if row.get("id") == id:
			return row
	return {}


func _test_fallback_hold_preference() -> void:
	var profile := _profile()
	var wizard_before := Progression.default_loadout(defs, profile, "wizard")
	var wizard_orders := Progression.order_options(defs, profile, "wizard", wizard_before)
	for id in ["knight_learn_bonk", "knight_rescue_line"]:
		var bought := Progression.purchased_profile(defs, profile, id)
		if bought.has("error"):
			_check(false, "Fallback fixture purchases " + id)
			return
		profile = bought
	var native := Progression.default_loadout(defs, profile, "knight")
	var normal_orders := Progression.order_options(defs, profile, "knight", native)
	var selection := native.duplicate(true)
	selection.slots.offense = "healer_bonk"
	selection.slots.utility = "knight_rescue_line"
	selection.order_id = "order_hold"
	var fallback_offered := false
	for row in Progression.order_options(defs, profile, "knight", selection):
		if row.get("id") == "order_hold" and row.get("compatible", false):
			fallback_offered = true
	_check(fallback_offered and not Progression.effective_kit(defs, profile, "knight", selection).is_empty(),
		"Fresh Bonk and Rescue Line selection offers a usable fallback Hold")
	if not fallback_offered:
		return
	# Snapshot the same preference save_loadouts would persist, then buy a new
	# compatible standing order without touching the saved selection.
	profile.preferred_loadouts["knight"] = selection.duplicate(true)
	_check(Progression.default_loadout(defs, profile, "knight") == selection,
		"Fallback Hold preference is valid before buying Stay Close")
	var purchased := Progression.purchased_profile(defs, profile, "knight_escort_order")
	if purchased.has("error"):
		_check(false, "Fallback fixture purchases Stay Close")
		return
	_check(purchased.preferred_loadouts.get("knight") == selection,
		"Stay Close purchase preserves the stored preference")
	var after := Progression.default_loadout(defs, purchased, "knight")
	_check(after == selection, "Stay Close must not silently reset saved Bonk, Rescue Line or Hold")
	_check(not Progression.effective_kit(defs, purchased, "knight", selection).is_empty(),
		"Saved fallback Hold remains a valid equipped kit after Stay Close")
	var stay_close_offered := false
	for row in Progression.order_options(defs, purchased, "knight", selection):
		if row.get("id") == "order_knight_escort" and row.get("compatible", false):
			stay_close_offered = true
	_check(stay_close_offered, "Stay Close is independently available for the saved abilities")
	var normal_after := Progression.order_options(defs, purchased, "knight", native)
	for row in normal_orders:
		_check(row in normal_after, "Purchasing Stay Close preserves each existing native-kit order offer")
	_check(Progression.default_loadout(defs, purchased, "wizard") == wizard_before
		and Progression.order_options(defs, purchased, "wizard", wizard_before) == wizard_orders,
		"Knight purchase does not change the Wizard default or normal order offers")


func _test_register() -> void:
	var table: Dictionary = defs.get("guild_progression", {}).get("petitions", {})
	var expected := RECRUITS.keys() + TRAINING.keys()
	_check(table.size() == 29, "Register contains exactly 29 executable entries")
	for example in [["recruit_blacksmith", 5, "recruit", ""],
			["blacksmith_learn_bonk", 4, "ability", "healer_bonk"],
			["blacksmith_learn_acid", 5, "ability", "alchemist_acid"]]:
		var spec: Dictionary = table.get(example[0], {})
		var grant: Dictionary = spec.get("grant", {})
		_check(spec.get("cost") == example[1] and grant.get("kind") == example[2] \
			and grant.get("hero_id") == "blacksmith" \
			and (example[3] == "" or (grant.get("slot_id") == "offense" and grant.get("ability_id") == example[3])),
			example[0] + " has the expected Smith grant and cost")
	for id in expected:
		_check(table.has(id), "Register contains " + id)
		if not table.has(id):
			continue
		var spec: Dictionary = table[id]
		_check(not spec.get("teaser", false) and not spec.get("grant", {}).is_empty(),
			id + " is executable, not a teaser")
		var hero: String = RECRUITS[id] if RECRUITS.has(id) else TRAINING[id][0]
		_check(spec.get("grant", {}).get("hero_id") == hero, id + " grants the intended recipient")
		if RECRUITS.has(id):
			_check(spec.get("grant", {}).get("kind") == "recruit", id + " recruits its recipient")

	var fresh := _profile()
	for id in RECRUITS:
		var hero: String = RECRUITS[id]
		_check(hero not in Progression.roster(defs, fresh), hero + " starts locked")
		_check(Progression.default_loadout(defs, fresh, hero).is_empty(), hero + " has no scoped kit before recruitment")
	for id in TRAINING:
		if not table.has(id):
			continue
		var recipient: String = TRAINING[id][0]
		if recipient not in FOUNDERS:
			var missing_recipient := _profile()
			# Satisfy all explicit dependencies without recruiting the recipient.
			missing_recipient.purchased_ids = TRAINING[id][1].duplicate()
			var row := _row(missing_recipient, id)
			_check(row.get("recipient_locked", false) and not row.get("can_buy", false),
				id + " requires its recipient even with prerequisite IDs present")
		for dependency in TRAINING[id][1]:
			var missing := _profile()
			missing.recruited_ids = FOUNDERS + RECRUITS.values()
			missing.purchased_ids = TRAINING[id][1].duplicate()
			missing.purchased_ids.erase(dependency)
			# Recruit prerequisites are owned by roster, not purchased IDs.
			if RECRUITS.has(dependency):
				missing.recruited_ids.erase(RECRUITS[dependency])
			var row := _row(missing, id)
			_check(not row.get("can_buy", false) and dependency in row.get("missing_prerequisites", []),
				id + " requires " + dependency)

	# Purchase in a topological order determined by the domain itself, not by
	# prices or table ordering. A dead end is a failure, not a skipped test.
	var profile := fresh
	var remaining := expected.duplicate()
	while not remaining.is_empty():
		var advanced := false
		for id in remaining.duplicate():
			if not _row(profile, id).get("can_buy", false):
				continue
			var before := profile.duplicate(true)
			var bought := Progression.purchased_profile(defs, profile, id)
			_check(not bought.has("error") and id in bought.get("purchased_ids", []),
				id + " can be purchased")
			if bought.has("error"):
				continue
			_check(before == profile, id + " does not mutate its input")
			_check(Progression.purchased_profile(defs, bought, id).has("error"),
				id + " cannot be purchased twice")
			profile = bought
			remaining.erase(id)
			advanced = true
		if not advanced:
			break
	_check(remaining.is_empty(), "All 29 purchases have a reachable plan; blocked: " + str(remaining))
	if not remaining.is_empty():
		return
	_check(Progression.roster(defs, profile).size() == 8, "Completed register owns all eight eligible heroes")
	for hero in FOUNDERS + RECRUITS.values():
		var loadout := Progression.default_loadout(defs, profile, hero)
		_check(not loadout.is_empty() and not Progression.effective_kit(defs, profile, hero, loadout).is_empty(),
			hero + " retains a valid default kit after all purchases")
		var slots := Progression.slot_options(defs, profile, hero)
		for slot in slots:
			for ability in slots[slot]:
				var alternative := loadout.duplicate(true)
				alternative.slots[slot] = ability
				var compatible := false
				for order in Progression.order_options(defs, profile, hero, alternative):
					if order.get("compatible", false):
						alternative.order_id = order.id
						compatible = not Progression.effective_kit(defs, profile, hero, alternative).is_empty()
						if compatible:
							break
				_check(compatible, hero + " can equip " + ability + " with a legal order")


func _test_practice_and_scoping() -> void:
	var profile := _profile()
	var board := Commissions.board(defs, profile.board_seed)
	if board.is_empty():
		_check(false, "Commission board exists")
		return
	for hero in RECRUITS.values():
		var party := [hero, "knight", "healer"]
		_check(Adventure.start_guild_commission(defs, board[0], party, profile, {}, 444).is_empty(),
			hero + " cannot deploy in a fresh scoped guild")
		var practice := Adventure.start_commission(defs, board[0], party, 444)
		_check(not practice.is_empty(), hero + " remains available in unscoped commissions")
	# Starting an outing snapshots the kit; changing the separate profile later
	# must not grant a learned ability in an already active run.
	var run := Adventure.start_guild_commission(defs, board[0], FOUNDERS, profile, {}, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		_check(false, "Scoped outing starts")
		return
	var bought := Progression.purchased_profile(defs, profile, "teach_healer_blast")
	_check(not bought.has("error"), "Fixture can buy Blast after outing starts")
	run = Adventure.choose_route(run, run.reports[0].mission_id)
	run = Adventure.begin_mission(run)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		_check(false, "Scoped outing deploys")
		return
	var healer: Dictionary = rules.entity_profile(state, "healer")
	_check("wizard_blast" not in healer.get("abilities", []),
		"Purchases made after departure do not unlock actions midrun")


func _test_teaching_is_not_a_habit() -> void:
	for example in [
		["knight", "knight_learn_bonk", "order_aggressive", []],
		["healer", "teach_healer_blast", "order_blast", []],
		["wizard", "wizard_learn_dodge", "order_retreat", ["recruit_rogue"]],
		["bard", "bard_learn_push", "order_advance", ["recruit_bard"]],
		["rogue", "rogue_learn_potion", "order_make_rounds", ["recruit_rogue", "recruit_alchemist"]],
		["necromancer", "necro_learn_melody", "order_inspiring_melody", ["recruit_necromancer", "recruit_bard"]],
		["alchemist", "alchemist_learn_pull", "order_blast", ["recruit_alchemist"]],
	]:
		var profile := _profile()
		for dependency in example[3]:
			var recruited := Progression.purchased_profile(defs, profile, dependency)
			if recruited.has("error"):
				profile = {}
				break
			profile = recruited
		if profile.is_empty():
			_check(false, example[1] + " donor and recipient can be recruited")
			continue
		var trained := Progression.purchased_profile(defs, profile, example[1])
		if trained.has("error"):
			_check(false, example[1] + " can be taught")
			continue
		var loadout := _action_loadout(trained, example[0], example[1])
		var state := _battle(trained, example[0], loadout)
		if state.is_empty():
			_check(false, example[1] + " deploys")
			continue
		_check(not rules.entity_profile(state, example[0]).get("habits", {}).has(example[2]),
			example[1] + " does not confer donor order " + example[2])


func _battle(profile: Dictionary, hero: String, loadout: Dictionary) -> Dictionary:
	var party := [hero]
	for founder in FOUNDERS:
		if founder != hero and party.size() < 3:
			party.append(founder)
	var board := Commissions.board(defs, profile.board_seed)
	if board.is_empty():
		return {}
	var loadouts := {}
	loadouts[hero] = loadout
	var run := Adventure.start_guild_commission(defs, board[0], party, profile, loadouts, 444)
	if run.get("phase") != "route" or run.get("reports", []).is_empty():
		return {}
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		return {}
	return _battlefield(state, hero)


func _battlefield(state: Dictionary, hero: String) -> Dictionary:
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		_unit(hero, hero, Vector2i(3, 3), 20),
		_unit("patient", "healer" if hero != "healer" else "knight", Vector2i(3, 5), 10),
		_unit("enemy", "harpooner", Vector2i(4, 3), 20),
		_unit("civilian", "ferryman", Vector2i(10, 10), 20),
	]
	state.party = [hero, "patient"]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	state.rng_state = 12345
	return state


func _unit(id: String, character: String, pos: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos,
		"hp": hp, "max_hp": 20, "statuses": {}, "upgrades": {}}


func _unit_at(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _action_loadout(profile: Dictionary, hero: String, petition: String) -> Dictionary:
	var spec: Dictionary = defs.get("guild_progression", {}).get("petitions", {}).get(petition, {})
	var grant: Dictionary = spec.get("grant", {})
	var loadout := Progression.default_loadout(defs, profile, hero)
	if loadout.is_empty() or grant.get("kind") != "ability":
		return {}
	loadout.slots[grant.get("slot_id", "")] = grant.get("ability_id", "")
	for order in Progression.order_options(defs, profile, hero, loadout):
		if order.get("compatible", false):
			loadout.order_id = order.id
			return loadout
	return {}


func _test_scoped_actions() -> void:
	var profile := _profile()
	var pending := RECRUITS.keys() + TRAINING.keys()
	while not pending.is_empty():
		var progressed := false
		for id in pending.duplicate():
			if _row(profile, id).get("can_buy", false):
				var next := Progression.purchased_profile(defs, profile, id)
				if not next.has("error"):
					profile = next
					pending.erase(id)
					progressed = true
		if not progressed:
			break
	if not pending.is_empty():
		_check(false, "Battle fixtures need complete purchase plan: " + str(pending))
		return
	for example in [
		["knight", "knight_rescue_line", "patient"],
		["healer", "healer_field_dressing", "patient"],
		["wizard", "wizard_ring_sparks", ""],
		["rogue", "rogue_tripwire", ""],
		["necromancer", "necro_grave_bell", ""],
		["alchemist", "alchemist_etching_paste", "enemy"],
		["knight", "knight_learn_bonk", "enemy"],
		["healer", "teach_healer_blast", ""],
		["wizard", "wizard_learn_dodge", ""],
		["bard", "bard_learn_push", "enemy"],
		["rogue", "rogue_learn_potion", "patient"],
		["necromancer", "necro_learn_melody", ""],
		["alchemist", "alchemist_learn_pull", "enemy"],
	]:
		var hero: String = example[0]
		var id: String = example[1]
		var loadout := _action_loadout(profile, hero, id)
		var state := _battle(profile, hero, loadout)
		if state.is_empty():
			_check(false, id + " deploys with its purchased action equipped")
			continue
		if id == "healer_field_dressing" or id == "rogue_learn_potion":
			_unit_at(state, "patient").position = Vector2i(3, 4)
		var ability: String = defs.guild_progression.petitions[id].grant.ability_id
		var plan: Dictionary = rules.preview(state, hero, ability, example[2])
		_check(plan.get("valid", false), id + " executes as an actual scoped action")
		if plan.get("valid", false):
			_check(not plan.get("events", []).is_empty() and plan.result != state,
				id + " produces a battle effect")
			_check(rules.apply_plan(state, plan) == plan.result, id + " commits its forecast")
		if id == "knight_rescue_line" and plan.get("valid", false):
			_check(_unit_at(plan.result, "patient").position == Vector2i(3, 4), "Rescue Line pulls the ally one tile")
		if id == "healer_field_dressing" and plan.get("valid", false):
			_check(_unit_at(plan.result, "patient").hp == 12, "Field Dressing heals the chosen ally by two")
		if id == "wizard_ring_sparks" and plan.get("valid", false):
			_check(_unit_at(plan.result, "enemy").hp == 18, "Ring of Sparks damages an adjacent enemy")
		if id == "alchemist_etching_paste" and plan.get("valid", false):
			_check(_unit_at(plan.result, "enemy").hp == 18, "Etching Paste deals two initial damage")
	_test_scoped_orders(profile)


func _test_scoped_orders(profile: Dictionary) -> void:
	# Ability-specific orders must be equipped as well as learned. Movement
	# orders have no associated ability petition and use the native kit.
	for example in [
		["knight", "knight_escort_order", "", "move"],
		["healer", "healer_blast_order", "teach_healer_blast", "wizard_blast"],
		["healer", "healer_triage_order", "healer_field_dressing", "healer_field_dressing"],
		["wizard", "wizard_stand_back", "", "move"],
		["bard", "bard_follow_company", "", "move"],
		["rogue", "rogue_tripwire_order", "rogue_tripwire", "rogue_tripwire"],
		["necromancer", "necro_bell_order", "necro_grave_bell", "necro_grave_bell"],
		["alchemist", "alchemist_throw_samples", "", "alchemist_acid"],
	]:
		var hero: String = example[0]
		var petition: String = example[1]
		var grant: Dictionary = defs.guild_progression.petitions.get(petition, {}).get("grant", {})
		var loadout: Dictionary = Progression.default_loadout(defs, profile, hero) if example[2] == "" \
			else _action_loadout(profile, hero, example[2])
		if grant.get("kind") != "order" or loadout.is_empty():
			_check(false, petition + " supplies an equippable order")
			continue
		loadout.order_id = grant.get("order_id", "")
		var state := _battle(profile, hero, loadout)
		if state.is_empty():
			_check(false, petition + " deploys with its order")
			continue
		if petition == "healer_triage_order":
			_unit_at(state, "patient").position = Vector2i(3, 4)
		state = rules.set_order(state, hero, loadout.order_id)
		var plan: Dictionary = rules.preview_round(state)
		var used := false
		for event in plan.get("events", []):
			var resolved: Dictionary = event.get("resolved_action", {})
			if resolved.get("unit_id") == hero and resolved.get("ability_id") == example[3] \
					and (example[3] != "move" or event.get("type") == "move"):
				used = true
		_check(plan.get("valid", false) and used, petition + " actually delegates " + str(example[3])
			+ "; orders=" + str(state.orders) + "; units=" + str(state.units)
			+ "; events=" + str(plan.get("events", [])))
		if plan.get("valid", false):
			_check(rules.commit_round(state, plan) == plan.result, petition + " commits its forecast")


func _test_tripwire_next_movement() -> void:
	var profile := _profile()
	for id in ["recruit_rogue", "rogue_tripwire"]:
		profile = Progression.purchased_profile(defs, profile, id)
		if profile.has("error"):
			_check(false, "Tripwire fixture purchases " + id)
			return
	# Give the test opponent direct commands without changing its enemy team.
	var original := defs
	defs = defs.duplicate(true)
	defs.classes.enemy.capabilities.append("commandable")
	var loadout := _action_loadout(profile, "rogue", "rogue_tripwire")
	var state := _battle(profile, "rogue", loadout)
	defs = original
	if state.is_empty():
		_check(false, "Tripwire fixture deploys")
		return
	_unit_at(state, "patient").character_id = "knight"
	_unit_at(state, "patient").position = Vector2i(4, 4)
	var mark: Dictionary = rules.preview(state, "rogue", "rogue_tripwire")
	_check(mark.get("valid", false), "Tripwire marks the real opposing actor")
	if not mark.get("valid", false):
		return
	state = rules.apply_plan(state, mark)
	_check(rules.has_status(state, "enemy", "tripwire_tangled"), "Tripwire status is applied")
	# Push is forced displacement, not a voluntary action by its recipient.
	var pushed_plan: Dictionary = rules.preview(state, "patient", "knight_push", "enemy")
	_check(pushed_plan.get("valid", false), "Tripwire permits a forced push")
	if pushed_plan.get("valid", false):
		var pushed: Dictionary = rules.apply_plan(state, pushed_plan)
		_check(_unit_at(pushed, "enemy").position == Vector2i(4, 2)
			and rules.has_status(pushed, "enemy", "tripwire_tangled"),
			"Forced displacement neither blocks nor spends Tripwire")
	# The enemy attacks instead of moving during its first marked activation.
	state = rules.choose_manual(state, "enemy", "enemy_attack", "rogue")
	var attack_round: Dictionary = rules.preview_round(state)
	var attacked: Dictionary = rules.commit_round(state, attack_round)
	_check(attack_round.get("valid", false) and _unit_at(attacked, "rogue").hp < _unit_at(state, "rogue").hp,
		"Marked opponent takes a real attack activation")
	_check(rules.has_status(attacked, "enemy", "tripwire_tangled"),
		"Tripwire survives a marked activation that does not move")
	# A chosen Move is an attempted activation even when the mark blocks it.
	var moving := rules.choose_manual(attacked, "enemy", "move", "5,3")
	var blocked: Dictionary = rules.preview_round(moving)
	var blocked_state: Dictionary = rules.commit_round(moving, blocked)
	_check(blocked.get("valid", false) and _unit_at(blocked_state, "enemy").position == Vector2i(4, 3),
		"Tripwire blocks the next voluntary Move")
	_check(not rules.has_status(blocked_state, "enemy", "tripwire_tangled"),
		"Blocked voluntary Move spends Tripwire once")
	var retry := rules.choose_manual(blocked_state, "enemy", "move", "5,3")
	var resumed: Dictionary = rules.preview_round(retry)
	var resumed_state: Dictionary = rules.commit_round(retry, resumed)
	_check(resumed.get("valid", false) and _unit_at(resumed_state, "enemy").position == Vector2i(5, 3),
		"A later voluntary Move succeeds")


func _test_paste_culture() -> void:
	var profile := _profile()
	for id in ["recruit_alchemist", "alchemist_etching_paste", "alchemist_learn_pull"]:
		profile = Progression.purchased_profile(defs, profile, id)
		if profile.has("error"):
			_check(false, "Culture fixture purchases " + id)
			return
	var loadout := _action_loadout(profile, "alchemist", "alchemist_etching_paste")
	if loadout.is_empty():
		_check(false, "Culture fixture equips Etching Paste")
		return
	loadout.slots.utility = "wizard_pull"
	for order in Progression.order_options(defs, profile, "alchemist", loadout):
		if order.get("compatible", false):
			loadout.order_id = order.id
			break
	var kit := Progression.effective_kit(defs, profile, "alchemist", loadout)
	_check(not kit.is_empty() and "alchemist_etching_paste" in kit.get("abilities", [])
		and "wizard_pull" in kit.get("abilities", []) and "alchemist_acid" not in kit.get("abilities", [])
		and "alchemist_potion" not in kit.get("abilities", []), "Culture fixture has Paste and Pull only")
	if kit.is_empty():
		return
	var reward := "alchemist_keep_the_culture"
	_check(Rewards.eligible(defs, "alchemist", reward, {}, kit),
		"Keep the Culture is eligible for equipped Etching Paste without base bottles")
	var board := Commissions.board(defs, profile.board_seed)
	if board.is_empty():
		_check(false, "Culture fixture commission board exists")
		return
	var run := Adventure.start_guild_commission(defs, board[0], ["alchemist", "knight", "healer"],
		profile, {"alchemist": loadout}, 444)
	if run.get("phase") != "route":
		_check(false, "Culture fixture starts scoped commission")
		return
	# A controlled offer isolates selection and its eligibility recheck from rarity RNG.
	run.phase = "reward"
	run.reward_offers = [{"hero_id": "alchemist", "upgrade_id": reward}]
	run = Adventure.choose_reward(run, "alchemist", reward)
	_check(run.get("upgrades_by_id", {}).get("alchemist", {}).get(reward, 0) == 1,
		"Scoped commission accepts the offered Culture reward")
	if run.get("upgrades_by_id", {}).get("alchemist", {}).get(reward, 0) != 1:
		return
	if run.get("phase") == "route":
		if run.get("reports", []).is_empty():
			_check(false, "Culture fixture offers the next route")
			return
		run = Adventure.choose_route(run, run.reports[0].mission_id)
	run = Adventure.begin_mission(run)
	var state: Dictionary = run.get("mission", {})
	if state.is_empty():
		_check(false, "Culture reward deploys on the next mission")
		return
	var deployed_upgrades: Dictionary = _unit_at(state, "alchemist").get("upgrades", {}).duplicate(true)
	_check(deployed_upgrades.get(reward, 0) == 1, "Chosen Culture reward reaches the deployed Mixologist")
	state = _battlefield(state, "alchemist")
	_unit_at(state, "alchemist").upgrades = deployed_upgrades
	state.units.append(_unit("enemy_b", "harpooner", Vector2i(3, 4), 20))
	var seed_value := -1
	for candidate in range(1, 2000):
		_unit_at(state, "alchemist")["dose_rng_state"] = candidate
		if rules.dose_forecast(state, "alchemist", "alchemist_etching_paste").get("reaction_id") == "repeating_lunch":
			seed_value = candidate
			break
	_check(seed_value >= 0, "Fixture finds a deterministic refreshable reaction")
	if seed_value < 0:
		return
	var first: Dictionary = rules.preview(state, "alchemist", "alchemist_etching_paste", "enemy")
	_check(first.get("valid", false), "Culture records first Paste")
	if not first.get("valid", false):
		return
	state = rules.apply_plan(state, first)
	_check(_unit_at(state, "alchemist").get("bottled_reaction", {}).get("recipe") == "alchemist_etching_paste",
		"Culture stores exact Paste recipe, not base Acid")
	_unit_at(state, "alchemist").dose_rng_state = seed_value
	var second: Dictionary = rules.preview(state, "alchemist", "alchemist_etching_paste", "enemy_b")
	if not second.get("valid", false):
		_check(false, "Culture can record a second Paste")
		return
	state = rules.apply_plan(state, second)
	var hp: int = _unit_at(state, "enemy").hp
	var repeat: Dictionary = rules.preview(state, "alchemist", "alchemist_repeat_batch", "enemy")
	_check(repeat.get("valid", false), "Repeat Batch can refresh the first recipient")
	if not repeat.get("valid", false):
		return
	var result: Dictionary = rules.apply_plan(state, repeat)
	_check(_unit_at(result, "enemy").hp == hp - 2,
		"Repeated Paste deals exactly its two damage, without extra refresh damage")
	_check(not _unit_at(result, "alchemist").has("bottled_reaction"),
		"Repeat Batch spends the stored Paste once")
	var again: Dictionary = rules.preview(result, "alchemist", "alchemist_repeat_batch", "enemy_b")
	_check(not again.get("valid", false), "Spent Culture cannot repeat again")
