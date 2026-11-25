extends SceneTree

## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_alchemy_conversions_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")
var rules := Rules.new()
var defs: Dictionary
var failures: Array[String] = []


func _initialize() -> void:
	defs = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(Catalog.read_default())
	# Own the relevant amounts, ranges, and habits, independent of stock tuning.
	defs.abilities.alchemist_acid.params.damage = 1
	defs.abilities.alchemist_acid.targeting.range = 3
	defs.abilities.alchemist_potion.params.amount = 1
	defs.abilities.alchemist_potion.targeting.range = 1
	defs.abilities.alchemist_etching_paste.params.damage = 2
	defs.abilities.alchemist_etching_paste.targeting.range = 1
	defs.characters.harpooner.behavior = "hold"
	for hero in ["alchemist", "rogue"]:
		defs.characters[hero].abilities = Catalog.profile(defs, hero).abilities.duplicate()
		for ability in ["alchemist_potion", "alchemist_acid", "alchemist_etching_paste"]:
			if ability not in defs.characters[hero].abilities:
				defs.characters[hero].abilities.append(ability)
	_test_direct()
	_test_conversion_draw_pools()
	_test_splash()
	_test_standing()
	_test_bottles()
	_test_ordinary_bottle_counter()
	_test_borrowed()
	if failures.is_empty():
		print("PASS: smith alchemy conversions")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _unit(id: String, character: String, pos: Vector2i, hp := 10) -> Dictionary:
	return {"id": id, "character_id": character, "position": pos, "hp": hp,
		"max_hp": 20, "statuses": {}}


func _state() -> Dictionary:
	var s: Dictionary = rules.new_game(defs, "test_escort")
	s.width = 12
	s.height = 12
	s.terrain = []
	s.obstacles = []
	s.units = [_unit("smith", "blacksmith", Vector2i(0, 0)),
		_unit("alchemist", "alchemist", Vector2i(4, 4)),
		_unit("ally", "knight", Vector2i(7, 4)),
		_unit("neighbor", "wizard", Vector2i(7, 5)),
		_unit("enemy", "harpooner", Vector2i(5, 4)),
		_unit("other", "harpooner", Vector2i(4, 6)),
		_unit("civilian", "ferryman", Vector2i(11, 11))]
	s.party = ["smith", "alchemist", "ally", "neighbor"]
	s.orders = {"smith": "order_hold", "alchemist": "order_hold",
		"ally": "order_hold", "neighbor": "order_hold"}
	s.overrides = {}
	s.dose_seed = 12345
	s.rng_state = 12345
	s.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(0, 11)}
	_entity(s, "alchemist").fitted_by = "smith"
	return s


func _entity(s: Dictionary, id: String) -> Dictionary:
	for u: Dictionary in s.get("units", []):
		if u.id == id:
			return u
	return {}


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _reaction(plan: Dictionary) -> Dictionary:
	for event: Dictionary in plan.get("events", []):
		if event.get("type") == "alchemy_reaction":
			return event
	return {}


func _act(s: Dictionary, actor: String, ability: String, target: String, label: String) -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview(s, actor, ability, target)
	_check(s == before and plan == rules.preview(s, actor, ability, target), label + ": pure repeatable preview")
	_check(plan.get("valid", false), label + ": legal")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.apply_plan(s, plan)
	_check(s == before and result == plan.get("result"), label + ": commit equals preview")
	return {"plan": plan, "result": result}


func _round(s: Dictionary, label: String) -> Dictionary:
	var before := s.duplicate(true)
	var plan: Dictionary = rules.preview_round(s)
	_check(s == before and plan == rules.preview_round(s), label + ": pure repeatable forecast")
	_check(plan.get("valid", false), label + ": legal round")
	if not plan.get("valid", false):
		return {}
	var result: Dictionary = rules.commit_round(s, plan)
	_check(s == before and result == plan.get("result"), label + ": commit equals forecast")
	return {"plan": plan, "result": result}


func _cosmetic_seed() -> int:
	for seed_value in range(1, 10000):
		if Reactions.draw(seed_value, false).category == "cosmetic" \
				and Reactions.draw(seed_value, true).category == "cosmetic":
			return seed_value
	return 12345


func _harmful_potion_seed() -> int:
	for seed_value in range(1, 10000):
		var draw: Dictionary = Reactions.draw(seed_value, false)
		if draw.id == "thin_skinned" and draw.category == "harmful":
			return seed_value
	return 12345


func _test_conversion_draw_pools() -> void:
	# Select an input where the two real pools disagree, so using the source
	# handler's pool cannot accidentally satisfy the converted-form assertion.
	var seed_value := -1
	for candidate in range(1, 10000):
		var potion: Dictionary = Reactions.draw(candidate, false)
		var acid: Dictionary = Reactions.draw(candidate, true)
		if potion.category != "cosmetic" and acid.category != "cosmetic" \
				and potion.category != acid.category:
			seed_value = candidate
			break
	_check(seed_value >= 0, "Controlled seed distinguishes non-cosmetic Potion and Acid draws")
	if seed_value < 0:
		return
	for sample in [
		["alchemist_acid", "ally", false, "Buffer"],
		["alchemist_etching_paste", "ally", false, "Sealing Paste"],
		["alchemist_potion", "enemy", true, "Bitter"],
	]:
		var s := _state()
		s.dose_seed = seed_value
		_entity(s, "ally").position = Vector2i(4, 5)
		var expected: Dictionary = Reactions.draw(seed_value, sample[2])
		var wrong: Dictionary = Reactions.draw(seed_value, not sample[2])
		var dose := _act(s, "alchemist", sample[0], sample[1], sample[3] + " discriminating draw")
		if dose.is_empty():
			continue
		var reaction := _reaction(dose.plan)
		_check(reaction.get("reaction_id") == expected.id and reaction.get("category") == expected.category
			and reaction.get("category") != wrong.category,
			sample[3] + " uses the declared reaction pool, not the source recipe's pool")
		_check(_entity(dose.result, "alchemist").get("dose_rng_state") == expected.seed,
			sample[3] + " advances the dose RNG exactly once")
		var count := 0
		for event: Dictionary in dose.plan.get("events", []):
			if event.get("type") == "alchemy_reaction":
				count += 1
		_check(count == 1, sample[3] + " forecasts exactly one reaction")


func _test_direct() -> void:
	var s := _state()
	s.dose_seed = _cosmetic_seed()
	_entity(s, "alchemist").upgrades = {"alchemist_concentrate": 2, "alchemist_stronger_dose": 2,
		"alchemist_long_ladle": 1, "alchemist_spare_vial": 1}
	var a := _act(s, "alchemist", "alchemist_acid", "ally", "Buffer at Acid reach")
	if not a.is_empty():
		_check(_entity(a.result, "ally").hp == 13, "Buffer heals effective Acid damage")
		_check(not _entity(a.result, "alchemist").has("fitted_by"), "Buffer consumes fitting")
		_check(_reaction(a.plan).get("reaction_id") == Reactions.draw(s.dose_seed, false).id,
			"Buffer draws from potion pool")
	_entity(s, "ally").hp = 19
	var capped := _act(s, "alchemist", "alchemist_acid", "ally", "Buffer capped primary pulse")
	if not capped.is_empty():
		var pulse := 0
		for event: Dictionary in capped.plan.get("events", []):
			if event.get("type") == "heal" and event.get("target_id") == "ally":
				pulse += int(event.get("amount", 0))
		_check(_entity(capped.result, "ally").hp == 20 and pulse == 1,
			"Buffer primary pulse reports actual capped healing")
	s = _state()
	s.dose_seed = _cosmetic_seed()
	_entity(s, "alchemist").upgrades = {"alchemist_stronger_dose": 2, "alchemist_long_ladle": 1}
	var b := _act(s, "alchemist", "alchemist_potion", "other", "Bitter at upgraded Potion reach")
	if not b.is_empty():
		_check(_entity(b.result, "other").hp == 7, "Bitter deals effective Potion amount")
		_check(_reaction(b.plan).get("reaction_id") == Reactions.draw(s.dose_seed, true).id,
			"Bitter draws from Acid pool")
	s = _state()
	s.dose_seed = _cosmetic_seed()
	_entity(s, "ally").position = Vector2i(4, 5)
	_entity(s, "alchemist").upgrades = {"alchemist_concentrate": 2}
	var c := _act(s, "alchemist", "alchemist_etching_paste", "ally", "Sealing Paste")
	if not c.is_empty():
		_check(_entity(c.result, "ally").hp == 12, "Sealing heals two, unaffected by Concentrate")
		_check(_reaction(c.plan).get("reaction_id") == Reactions.draw(s.dose_seed, false).id,
			"Sealing draws from potion pool")
	s = _state()
	_entity(s, "alchemist").upgrades = {"alchemist_spare_vial": 1, "alchemist_keep_the_culture": 1,
		"alchemist_stronger_dose": 2, "alchemist_concentrate": 2}
	var d := _act(s, "alchemist", "alchemist_plain_tonic", "enemy", "Plain Solvent")
	if not d.is_empty():
		_check(_entity(d.result, "enemy").hp == 9 and _reaction(d.plan).is_empty()
			and not _entity(d.result, "alchemist").has("bottled_reaction"),
			"Solvent damages one without reaction or bottle")


func _test_splash() -> void:
	for recipe in ["alchemist_acid", "alchemist_etching_paste", "alchemist_potion"]:
		var s := _state()
		s.dose_seed = _cosmetic_seed()
		_entity(s, "alchemist").upgrades = {"alchemist_brittle_glass": 1}
		if recipe == "alchemist_potion":
			_entity(s, "alchemist").upgrades["alchemist_long_ladle"] = 1
		_entity(s, "ally").position = Vector2i(4, 5)
		_entity(s, "neighbor").position = Vector2i(5, 5)
		_entity(s, "neighbor").hp = 19
		_entity(s, "enemy").position = Vector2i(3, 5)
		_entity(s, "other").position = Vector2i(9, 9)
		s.units.append(_unit("full", "wizard", Vector2i(4, 6), 20))
		var target := "enemy" if recipe == "alchemist_potion" else "ally"
		var dose := _act(s, "alchemist", recipe, target, recipe + " splash")
		if dose.is_empty():
			continue
		var reactions := 0
		for event: Dictionary in dose.plan.get("events", []):
			if event.get("type") == "alchemy_reaction":
				reactions += 1
		_check(reactions == 1 and _reaction(dose.plan).get("target_id") == target,
			recipe + " has exactly one primary reaction")
		if recipe != "alchemist_potion":
			_check(_entity(dose.result, "neighbor").hp == 20 and _entity(dose.result, "enemy").hp == 10,
				recipe + " splash heals adjacent friend, not hostile, and caps at max HP")
			_check(_entity(dose.result, "full").hp == 20,
				recipe + " splash does not heal beyond full HP")
		else:
			_check(_entity(dose.result, "ally").hp == 10, "Bitter has no Brittle Glass splash")


func _test_standing() -> void:
	var s := _state()
	s.dose_seed = _cosmetic_seed()
	_entity(s, "ally").hp = 4
	_entity(s, "neighbor").position = Vector2i(5, 5)
	s.orders.alchemist = "order_throw_samples"
	var a := _round(s, "Throw Samples Buffer")
	if not a.is_empty():
		_check(_reaction(a.plan).get("target_id") == "ally" and _entity(a.result, "ally").hp == 5,
			"Throw Samples selects most wounded reachable friend")
	s = _state()
	s.dose_seed = _cosmetic_seed()
	s.orders.alchemist = "order_make_rounds"
	var b := _round(s, "Make Rounds Bitter")
	if not b.is_empty():
		_check(_reaction(b.plan).get("target_id") == "enemy" and _entity(b.result, "enemy").hp == 9,
			"Make Rounds selects nearest legal hostile")


func _test_bottles() -> void:
	var s := _state()
	s.dose_seed = _harmful_potion_seed()
	_entity(s, "neighbor").position = Vector2i(6, 4)
	_entity(s, "alchemist").upgrades = {"alchemist_keep_the_culture": 1, "alchemist_concentrate": 2}
	var first := _act(s, "alchemist", "alchemist_acid", "ally", "Bottle converted Acid")
	if first.is_empty():
		return
	var saved: Dictionary = _entity(first.result, "alchemist").get("bottled_reaction", {})
	_check(saved.get("recipe") == "alchemist_acid" and saved.get("recipient") == "ally"
		and saved.get("id") == _reaction(first.plan).get("reaction_id")
		and saved.get("category") == _reaction(first.plan).get("category"),
		"Bottle records source recipe, recipient, exact reaction and category")
	var ordinary := _act(first.result, "alchemist", "alchemist_repeat_batch", "neighbor", "Ordinary repeat converted Acid")
	if not ordinary.is_empty():
		_check(_entity(ordinary.result, "neighbor").hp == 13
			and _reaction(ordinary.plan).get("reaction_id") == saved.get("id")
			and _reaction(ordinary.plan).get("category") == saved.get("category")
			and not _entity(ordinary.result, "alchemist").has("bottled_reaction"),
			"Ordinary Repeat preserves converted healing and exact reaction, then empties")
	var fitted: Dictionary = first.result.duplicate(true)
	_entity(fitted, "alchemist").fitted_by = "smith"
	var counter := _act(fitted, "alchemist", "alchemist_repeat_batch", "other", "Counterbatch")
	if not counter.is_empty():
		_check(_entity(counter.result, "other").hp == 7
			and _reaction(counter.plan).get("reaction_id") == saved.get("id")
			and _reaction(counter.plan).get("category") == saved.get("category")
			and not _entity(counter.result, "alchemist").has("bottled_reaction"),
			"Counterbatch inverts at Acid reach and magnitude with exact reaction, no recursive bottle")
	var fallback: Dictionary = fitted.duplicate(true)
	_entity(fallback, "enemy").position = Vector2i(10, 10)
	_entity(fallback, "other").position = Vector2i(10, 9)
	var f := _act(fallback, "alchemist", "alchemist_repeat_batch", "neighbor", "Counterbatch ordinary fallback")
	if not f.is_empty():
		_check(_entity(f.result, "neighbor").hp == 13
			and _entity(f.result, "alchemist").get("fitted_by") == "smith"
			and not _entity(f.result, "alchemist").has("bottled_reaction"),
			"No counter-recipient uses ordinary stored form, empties bottle and retains fitting")
	var empty := _state()
	_entity(empty, "alchemist").upgrades = {"alchemist_keep_the_culture": 1}
	_check(not rules.preview(empty, "alchemist", "alchemist_repeat_batch", "enemy").get("valid", false)
		and _entity(empty, "alchemist").get("fitted_by") == "smith",
		"Empty Counterbatch cannot spend fitting")


func _test_borrowed() -> void:
	var s := _state()
	s.dose_seed = _cosmetic_seed()
	_entity(s, "alchemist").character_id = "rogue"
	var dose := _act(s, "alchemist", "alchemist_potion", "enemy", "Dodger borrowed Potion")
	if not dose.is_empty():
		_check(_entity(dose.result, "enemy").hp == 9
			and not _entity(dose.result, "alchemist").has("fitted_by"),
			"Borrowed Potion converts by ability ID, not Mixologist identity")


func _test_ordinary_bottle_counter() -> void:
	# Acquire an ordinary Acid bottle through the real path, independently of
	# whether converted-dose acquisition has been implemented yet.
	var s := _state()
	s.dose_seed = _cosmetic_seed()
	_entity(s, "alchemist").erase("fitted_by")
	_entity(s, "alchemist").upgrades = {"alchemist_keep_the_culture": 1, "alchemist_concentrate": 2}
	var original := _act(s, "alchemist", "alchemist_acid", "enemy", "Ordinary Acid bottle setup")
	if original.is_empty():
		return
	var filled: Dictionary = original.result
	var reaction := _reaction(original.plan)
	_entity(filled, "alchemist").fitted_by = "smith"
	var counter := _act(filled, "alchemist", "alchemist_repeat_batch", "ally", "Ordinary Acid Counterbatch")
	if not counter.is_empty():
		_check(_entity(counter.result, "ally").hp == 13
			and _reaction(counter.plan).get("reaction_id") == reaction.get("reaction_id")
			and _reaction(counter.plan).get("category") == reaction.get("category")
			and not _entity(counter.result, "alchemist").has("bottled_reaction"),
			"Counterbatch heals at stored Acid reach and amount with exact reaction and no refill")
