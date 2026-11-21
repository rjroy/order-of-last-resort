extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/reward_catalog_dependencies_test.gd
# These fixtures isolate the dependency introduced by each optional reward.
var catalog: Script = load("res://content/catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var defs: Dictionary = catalog.read_default()
	if defs.is_empty():
		_check(false, "Default catalog loads")
	else:
		_test_dependencies(defs)
	if failures.is_empty():
		print("PASS: reward catalog dependencies")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _reward(hero: String, effect: String) -> Dictionary:
	return {"hero_id": hero, "effect": effect, "rarity": "rare", "cap": 1,
		"amount": 1, "label": "Fixture reward", "description": "Fixture effect."}


func _expect_dependency(defs: Dictionary, paths: Array, label: String) -> void:
	var errors: PackedStringArray = catalog.validate(defs)
	var diagnostic := "\n".join(errors)
	var matched := false
	for path in paths:
		if path in diagnostic:
			matched = true
	_check(matched, label + ": expected a field-specific diagnostic at %s, got %s" % [paths, diagnostic])
	# The same otherwise valid catalog is accepted without optional rewards.
	var without := defs.duplicate(true)
	without.erase("upgrades")
	var legacy_errors: PackedStringArray = catalog.validate(without)
	_check(legacy_errors.is_empty(), label + ": no-upgrades catalog retains prior semantics: " + str(legacy_errors))


func _test_dependencies(source: Dictionary) -> void:
	var wake := source.duplicate(true)
	wake.upgrades = {"fixture_wake": _reward("necromancer", "wake_reception")}
	wake.characters.necromancer.abilities.erase("summon_skeleton")
	wake.abilities.erase("summon_skeleton")
	_expect_dependency(wake,
		["upgrades.fixture_wake.effect", "upgrades.fixture_wake.hero_id", "abilities.summon_skeleton"],
		"Wake Reception requires the skeleton summon definition")

	var staff := source.duplicate(true)
	staff.upgrades = {"fixture_staff": _reward("healer", "long_staff")}
	staff.abilities.healer_bonk.targeting.erase("range")
	_expect_dependency(staff,
		["upgrades.fixture_staff.effect", "upgrades.fixture_staff.hero_id", "abilities.healer_bonk.targeting.range"],
		"Long Staff requires finite Bonk range")

	var shield := source.duplicate(true)
	var reward := _reward("knight", "shield_throw")
	reward["ability"] = "knight_shield_throw"
	shield.upgrades = {"fixture_shield": reward}
	shield.abilities.knight_shield_throw.targeting.erase("range")
	_expect_dependency(shield,
		["upgrades.fixture_shield.ability", "abilities.knight_shield_throw.targeting.range"],
		"Shield Throw requires a finite granted ability range")

	var wrong_kit := source.duplicate(true)
	wrong_kit.upgrades = {"fixture_wrong_kit": _reward("alchemist", "long_staff")}
	_expect_dependency(wrong_kit,
		["upgrades.fixture_wrong_kit.hero_id", "upgrades.fixture_wrong_kit.effect"],
		"Long Staff requires the recipient to have Bonk")
