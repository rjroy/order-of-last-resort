extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/guild_full_catalog_test.gd
# The register is an integration contract; only specifically requested prices are pinned.
const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild/guild_progression.gd")
const Adventure = preload("res://expedition/adventure.gd")
const Commissions = preload("res://expedition/commissions.gd")
const Rules = preload("res://rules/rules.gd")
const Rewards = preload("res://expedition/rewards.gd")
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
	"healer_triage_order": ["healer", []],
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
	"order_knight_advance": ["knight", []],
	"order_healer_aggressive": ["healer", []],
	"order_wizard_pull_petition": ["wizard", []],
	"order_rogue_blame": ["rogue", []],
	"order_necro_raise": ["necromancer", []],
	"order_bard_sonnet": ["bard", []],
	"order_smith_pursue": ["blacksmith", []],
	"order_knight_rescue_petition": ["knight", ["knight_rescue_line"]],
	"order_knight_bonk_petition": ["knight", ["knight_learn_bonk"]],
	"order_wizard_sparks_petition": ["wizard", ["wizard_ring_sparks"]],
	"order_wizard_dodge_petition": ["wizard", ["wizard_learn_dodge"]],
	"order_rogue_potion_petition": ["rogue", ["rogue_learn_potion"]],
	"order_necro_melody_petition": ["necromancer", ["necro_learn_melody"]],
	"order_bard_push_petition": ["bard", ["bard_learn_push"]],
	"order_alchemist_paste_petition": ["alchemist", ["alchemist_etching_paste"]],
	"order_alchemist_pull_petition": ["alchemist", ["alchemist_learn_pull"]],
	"order_smith_bonk_petition": ["blacksmith", ["blacksmith_learn_bonk"]],
	"order_smith_acid_petition": ["blacksmith", ["blacksmith_learn_acid"]],
}

var failures: Array[String] = []
var defs: Dictionary
var rules := Rules.new()


func _initialize() -> void:
	defs = Catalog.read_default()
	defs.characters.harpooner.behavior = "hold"
	defs.characters.ferryman.behavior = "hold"
	_test_requested_healer_caster_contract()
	_test_register()
	_test_ability_order_coverage()
	_test_fallback_hold_preference()
	_test_practice_and_scoping()
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


func _test_requested_healer_caster_contract() -> void:
	var heal: Dictionary = defs.abilities.healer_heal
	var blast: Dictionary = defs.abilities.wizard_blast
	var pull: Dictionary = defs.abilities.wizard_pull
	_check(heal.params.amount == 2 and heal.targeting.get("range") == 3,
		"Stock Heal restores 2 HP at maximum range 3")
	_check(blast.params.damage == 3 and blast.targeting.get("range") == 4,
		"Stock Blast deals 3 HP at maximum range 4")
	_check(pull.params.recoil_damage == 1 and pull.params.status == "knockdown",
		"Stock Pull has one recoil damage and retains knockdown")
	_check(not defs.abilities.has("healer_field_dressing")
		and not defs.guild_progression.petitions.has("healer_field_dressing"),
		"Hero Field Dressing ability and petition are removed")
	_check(defs.abilities.has("frontier_heal")
		and defs.abilities.frontier_heal.handler == "enemy_heal",
		"Enemy Field Dressing remains available")
	var profile := _profile()
	profile.points = 6
	var row := _row(profile, "healer_triage_order")
	_check(row.get("cost") == 6 and row.get("can_buy", false)
		and row.get("prerequisites", []).is_empty(), "Triage costs 6 and has no prerequisite")
	var unlearned := Progression.default_loadout(defs, profile, "healer")
	unlearned.order_id = "order_healer_triage"
	_check(Progression.effective_kit(defs, profile, "healer", unlearned).is_empty(),
		"Triage is unavailable before its independent purchase")
	var bought := Progression.purchased_profile(defs, profile, "healer_triage_order")
	_check(not bought.has("error") and bought.get("points") == 0,
		"Triage can be purchased with exactly 6 points")
	if not bought.has("error"):
		var loadout := Progression.default_loadout(defs, bought, "healer")
		loadout.order_id = "order_healer_triage"
		_check(not Progression.effective_kit(defs, bought, "healer", loadout).is_empty(),
			"Purchased Triage is compatible with base Heal")
		_test_triage_rounds(bought, loadout)
	_check(defs.behaviors.guild_healer_triage.params.ability == "healer_heal",
		"Triage delegates base Heal")
	var legacy := _profile()
	legacy.purchased_ids = ["healer_field_dressing", "healer_triage_order"]
	legacy.preferred_loadouts.healer = {"slots": {"offense": "healer_bonk",
		"utility": "healer_field_dressing"}, "order_id": "order_healer_triage"}
	var restored := Progression.default_loadout(defs, legacy, "healer")
	_check(restored.get("slots", {}).get("utility") == "healer_heal"
		and restored.get("order_id") == "order_healer_triage",
		"Legacy preference replaces Field Dressing with Heal and preserves owned Triage")
	_check(legacy.points == 1000000 and legacy.purchased_ids == ["healer_field_dressing", "healer_triage_order"],
		"Resolving legacy preference does not refund or mutate purchases")
	legacy.purchased_ids = ["healer_field_dressing"]
	var unowned := Progression.default_loadout(defs, legacy, "healer")
	_check(unowned.get("slots", {}).get("utility") == "healer_heal"
		and unowned.get("order_id") != "order_healer_triage",
		"Legacy Field Dressing alone does not grant Triage")
	var custom := defs.duplicate(true)
	custom.abilities["healer_field_dressing"] = heal.duplicate(true)
	custom.abilities.healer_field_dressing.targeting.kind = "entity"
	custom.abilities.healer_field_dressing.targeting.erase("direct")
	custom.abilities.healer_field_dressing.params.erase("prefer_wounded_self")
	custom.abilities.healer_field_dressing.fitted_form = "unpick_the_stitch"
	custom.guild_progression.petitions["healer_field_dressing"] = {
		"label": "Field Dressing", "description": "Custom utility", "cost": 4,
		"grant": {"kind": "ability", "hero_id": "healer", "slot_id": "utility",
			"ability_id": "healer_field_dressing"}}
	custom.behaviors.guild_healer_triage.params.ability = "healer_field_dressing"
	legacy.purchased_ids = ["healer_field_dressing", "healer_triage_order"]
	_check(Progression.default_loadout(custom, legacy, "healer") == legacy.preferred_loadouts.healer,
		"Custom catalogs retaining Field Dressing keep the saved custom loadout")


func _test_triage_rounds(profile: Dictionary, loadout: Dictionary) -> void:
	var state := _battle(profile, "healer", loadout)
	if state.is_empty():
		_check(false, "Purchased Triage deploys with its stock kit")
		return
	_unit_at(state, "healer").hp = 18
	_unit_at(state, "patient").position = Vector2i(4, 3)
	_unit_at(state, "patient").hp = 16
	_unit_at(state, "enemy").position = Vector2i(10, 8)
	state.units.append(_unit("chosen", "wizard", Vector2i(6, 3), 10))
	state.units.append(_unit("outside", "knight", Vector2i(7, 3), 1))
	state.party = ["healer", "patient", "chosen", "outside"]
	state = rules.set_order(state, "healer", "order_healer_triage")
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview_round(state)
	var committed: Dictionary = rules.commit_round(state, plan)
	var healed_chosen := false
	for event in plan.get("events", []):
		if event.get("type") == "heal" and event.get("target_id") == "chosen":
			healed_chosen = true
	_check(plan.get("valid", false) and state == before and healed_chosen
		and committed == plan.get("result"),
		"Triage forecasts and commits a heal on the most injured in-range patient")
	_check(_unit_at(committed, "chosen").get("hp") == 12
		and _unit_at(committed, "healer").get("hp") == 18
		and _unit_at(committed, "patient").get("hp") == 16
		and _unit_at(committed, "outside").get("hp") == 1,
		"Triage heals 2 at range 3 rather than self, the nearer patient, or the more injured patient outside range")

	var healthy := before.duplicate(true)
	for unit in healthy.units:
		if unit.id in healthy.party:
			unit.hp = unit.max_hp
	_unit_at(healthy, "outside").hp = 1
	var wait_plan: Dictionary = rules.preview_round(healthy)
	var waited := false
	var used_heal := false
	for event in wait_plan.get("events", []):
		if event.get("unit_id") == "healer" and event.get("type") == "wait":
			waited = true
		var resolved: Dictionary = event.get("resolved_action", {})
		if resolved.get("unit_id") == "healer" and resolved.get("ability_id") == "healer_heal":
			used_heal = true
	var wait_result: Dictionary = rules.commit_round(healthy, wait_plan)
	_check(wait_plan.get("valid", false) and waited and not used_heal
		and wait_result == wait_plan.get("result"),
		"Triage actually waits without using Heal when all legal patients are healthy")

	# Me or You replaces normal Heal targeting and retains its own split scope.
	var legendary := before.duplicate(true)
	_unit_at(legendary, "healer").upgrades = {"healer_me_or_you": 1}
	legendary.party = ["healer", "outside", "patient"]
	var self_plan: Dictionary = rules.preview_round(legendary)
	var self_result: Dictionary = rules.commit_round(legendary, self_plan)
	_check(self_plan.get("valid", false) and self_result == self_plan.get("result")
		and _unit_at(self_result, "healer").get("hp") == 20
		and _unit_at(self_result, "patient").get("hp") == 16,
		"Purchased Triage invokes Me or You to heal wounded self instead of waiting")
	_unit_at(legendary, "healer").hp = 20
	var split_plan: Dictionary = rules.preview_round(legendary)
	var split_result: Dictionary = rules.commit_round(legendary, split_plan)
	_check(split_plan.get("valid", false) and split_result == split_plan.get("result")
		and _unit_at(split_result, "patient").get("hp") == 17
		and _unit_at(split_result, "outside").get("hp") == 2
		and _unit_at(split_result, "chosen").get("hp") == 10,
		"Purchased Triage invokes Me or You split across deployed party, including outside Heal range")


func _test_fallback_hold_preference() -> void:
	var original := defs
	defs = defs.duplicate(true)
	# Isolate the historical no-compatible-starter case. Stock Knight now has
	# a compatible move-only starter even after both abilities are replaced.
	defs.guild_progression.starting_habits.knight.erase("order_knight_advance_move")
	_exercise_fallback_hold_preference()
	defs = original


func _exercise_fallback_hold_preference() -> void:
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
	_check(table.size() == expected.size(), "Register matches the explicitly covered executable entries")
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
	_check(remaining.is_empty(), "All register purchases have a reachable plan; blocked: " + str(remaining))
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


func _test_ability_order_coverage() -> void:
	var table: Dictionary = defs.guild_progression.petitions
	for ability_id in table:
		var ability_spec: Dictionary = table[ability_id]
		var ability: Dictionary = ability_spec.get("grant", {})
		if ability.get("kind") != "ability" or ability_spec.get("teaser", false):
			continue
		var found := false
		for order_id in table:
			var spec: Dictionary = table[order_id]
			var grant: Dictionary = spec.get("grant", {})
			if spec.get("teaser", false) or grant.get("kind") != "order" \
					or grant.get("hero_id") != ability.get("hero_id") \
					or ability_id not in spec.get("prerequisites", []):
				continue
			var behavior: Dictionary = defs.behaviors.get(grant.get("behavior_id", ""), {})
			if ability.get("ability_id") not in Catalog.behavior_ability_ids(behavior):
				continue
			var profile := _profile()
			profile.recruited_ids = FOUNDERS + RECRUITS.values()
			profile.purchased_ids = [ability_id, order_id]
			var loadout := Progression.default_loadout(defs, profile, ability.hero_id)
			loadout.slots[ability.slot_id] = ability.ability_id
			loadout.order_id = grant.order_id
			if not Progression.effective_kit(defs, profile, ability.hero_id, loadout).is_empty():
				found = true
				break
		_check(found, ability_id + " has a separately purchased compatible order requiring that ability")


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
		if id == "rogue_learn_potion":
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
		["healer", "healer_triage_order", "", "healer_heal"],
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
