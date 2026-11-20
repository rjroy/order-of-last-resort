extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/catalog_test.gd
var failures: Array[String] = []
var catalog: Script
var rules: RefCounted


func _initialize() -> void:
	if not ResourceLoader.exists("res://content/catalog.gd"):
		failures.append("Missing res://content/catalog.gd")
	else:
		catalog = load("res://content/catalog.gd")
		rules = load("res://rules.gd").new()
		_test_validation()
		_test_executable_authoring()
		_test_handler_event_requirements()
		_test_malformed_status_handler_preserves_event_diagnostics()
		_test_world_isolation()
		_test_capability_opt_out()
		_test_reflect_capability_filter()
	if failures.is_empty():
		print("PASS: catalog boundaries")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fixture() -> Dictionary:
	var defs: Dictionary = catalog.call("read_default")
	# Own all geometry used in these tests; the rest is valid authored schema.
	defs["boards"]["bridge"]["width"] = 7
	defs["boards"]["bridge"]["height"] = 5
	defs["boards"]["bridge"]["default_tile"] = "stone"
	defs["boards"]["bridge"]["tiles"] = []
	defs["boards"]["bridge"]["locations"]["safe_bank"] = [6, 4]
	defs["encounters"]["crossing"]["placements"] = [
		{"id": "knight", "character": "knight", "at": [0, 0]},
		{"id": "civilian", "character": "ferryman", "at": [6, 3]},
		{"id": "fixture_crate", "object": "crate", "at": [1, 0]}
	]
	return defs


func _test_validation() -> void:
	var defs := _fixture()
	_check(catalog.call("validate", defs).is_empty(), "Controlled fixture must validate")
	var unknown := defs.duplicate(true)
	unknown["encounters"]["crossing"]["placements"][2]["object"] = "missing_object"
	_check(not catalog.call("validate", unknown).is_empty(), "Unknown object reference must be rejected")
	var duplicate := defs.duplicate(true)
	duplicate["encounters"]["crossing"]["placements"][2]["id"] = "knight"
	_check(not catalog.call("validate", duplicate).is_empty(), "Duplicate instance ID must be rejected")
	var illegal := defs.duplicate(true)
	illegal["encounters"]["crossing"]["placements"][2]["at"] = [7, 0]
	_check(not catalog.call("validate", illegal).is_empty(), "Out-of-bounds placement must be rejected")
	var bad_shore := defs.duplicate(true)
	bad_shore.boards.bridge.shore_cells = [[7, 0]]
	_check(not catalog.validate(bad_shore).is_empty(), "Out-of-bounds shore cell must be rejected")
	bad_shore.boards.bridge.shore_cells = [[1, 0], [1, 0]]
	_check(not catalog.validate(bad_shore).is_empty(), "Duplicate shore cells must be rejected")


func _test_executable_authoring() -> void:
	var defs: Dictionary = catalog.call("read_default")
	_check(not defs.is_empty(), "Default authored data must load")
	if defs.is_empty():
		return
	_check(catalog.call("validate", defs).is_empty(), "Unmodified authored data must validate")
	var untargeted_push := defs.duplicate(true)
	untargeted_push["abilities"]["knight_push"]["targeting"]["kind"] = "none"
	_check(not catalog.call("validate", untargeted_push).is_empty(),
		"Push cannot use no-target selection")
	var long_move := defs.duplicate(true)
	long_move["abilities"]["move"]["targeting"]["range"] = 2
	_check(not catalog.call("validate", long_move).is_empty(),
		"Move cannot advertise a range beyond the implemented one-cell step")
	var untargeted_behavior := defs.duplicate(true)
	untargeted_behavior["behaviors"]["guard"]["params"]["ability"] = "knight_push"
	_check(not catalog.call("validate", untargeted_behavior).is_empty(),
		"use_ability cannot select an ability requiring an explicit target")
	var heal_fixture := defs.duplicate(true)
	heal_fixture.abilities["test_heal"] = defs.abilities.healer_heal.duplicate(true)
	for value in [true, false]:
		heal_fixture.abilities.test_heal.params.prefer_wounded_self = value
		_check(catalog.validate(heal_fixture).is_empty(),
			"Automatic heal accepts boolean self-preference %s" % str(value))
	for value in ["true", 1, null]:
		heal_fixture.abilities.test_heal.params.prefer_wounded_self = value
		var errors: Array = catalog.validate(heal_fixture)
		_check("abilities.test_heal.params.prefer_wounded_self: expected a boolean" in errors,
			"Self-preference rejects non-boolean %s" % str(value))
	heal_fixture.abilities.test_heal.targeting.kind = "entity"
	for value in [true, false]:
		heal_fixture.abilities.test_heal.params.prefer_wounded_self = value
		var errors: Array = catalog.validate(heal_fixture)
		_check("abilities.test_heal.params.prefer_wounded_self: requires automatic heal targeting" in errors,
			"Explicit heal rejects self-preference %s" % str(value))
	heal_fixture.abilities.test_heal.params.erase("prefer_wounded_self")
	_check(catalog.validate(heal_fixture).is_empty(), "Explicit heal without self-preference validates")
	var other_handler := defs.duplicate(true)
	other_handler.abilities.knight_push.params["prefer_wounded_self"] = true
	_check("abilities.knight_push.params.prefer_wounded_self: requires automatic heal targeting" in catalog.validate(other_handler),
		"Non-heal abilities reject self-preference")


func _test_handler_event_requirements() -> void:
	var defs := _fixture()
	_check(catalog.validate(defs).is_empty(), "Handler event fixture starts valid")
	for event_id in ["swap", "misdirect_mark", "misdirect_redirect", "misdirect_missing"]:
		var missing := defs.duplicate(true)
		missing.events.erase(event_id)
		var errors: PackedStringArray = catalog.validate(missing)
		_check(not errors.is_empty(), "Catalog with active handler rejects missing event " + event_id)
		_check(event_id in " ".join(errors), "Missing event diagnostic identifies " + event_id)

	# Old or independently authored catalogs need not support unused handlers.
	var compatible := defs.duplicate(true)
	compatible.adventures.first_outing.roster.erase("rogue")
	compatible.characters.erase("rogue")
	compatible.abilities.erase("rogue_confusing_dodge")
	compatible.abilities.erase("rogue_wasnt_me")
	compatible.statuses.erase("misdirected")
	for event_id in ["swap", "misdirect_mark", "misdirect_redirect", "misdirect_missing"]:
		compatible.events.erase(event_id)
	var errors: PackedStringArray = catalog.validate(compatible)
	_check(errors.is_empty(), "Catalog without Rogue handlers does not require their events: " + str(errors))


func _test_malformed_status_handler_preserves_event_diagnostics() -> void:
	for invalid_handler in [7, {}]:
		var defs := _fixture()
		var broken: Dictionary = defs.statuses.misdirected.duplicate(true)
		broken.handler = invalid_handler
		# Put the malformed record first so the valid misdirect status still
		# needs to be visited after it in the conditional event scan.
		var statuses := {"broken_misdirect": broken}
		statuses.merge(defs.statuses)
		defs.statuses = statuses
		defs.events.erase("misdirect_redirect")
		defs.events.erase("misdirect_missing")
		var errors: PackedStringArray = catalog.validate(defs)
		var diagnostics := "\n".join(errors)
		_check("statuses.broken_misdirect.handler" in diagnostics,
			"Malformed status handler %s reports its own validation error" % str(invalid_handler))
		_check("events.misdirect_redirect" in diagnostics and "events.misdirect_missing" in diagnostics,
			"Malformed status handler %s does not hide either valid handler's missing-event error: %s"
			% [str(invalid_handler), diagnostics])


func _check_frozen(value: Variant, path: String) -> void:
	if value is Dictionary:
		_check(value.is_read_only(), path + " dictionary must be read-only")
		for key in value:
			_check_frozen(value[key], path + "." + str(key))
	elif value is Array:
		_check(value.is_read_only(), path + " array must be read-only")
		for index in range(value.size()):
			_check_frozen(value[index], path + "[%d]" % index)


func _test_world_isolation() -> void:
	var first_defs := _fixture()
	var second_defs := _fixture()
	first_defs["characters"]["knight"]["label"] = "First knight"
	second_defs["characters"]["knight"]["label"] = "Second knight"
	first_defs["characters"]["knight"]["max_hp"] = 17
	second_defs["characters"]["knight"]["max_hp"] = 23
	var first: Dictionary = catalog.call("build", first_defs, "ferryman")
	var second: Dictionary = catalog.call("build", second_defs, "ferryman")
	if first.is_empty() or second.is_empty():
		_check(false, "Both independently authored worlds must build")
		return
	var first_handle: Variant = first.get("catalog")
	var second_handle: Variant = second.get("catalog")
	if not first_handle is Object or not second_handle is Object:
		_check(false, "Both worlds must expose a catalog object")
		return
	var first_value: Variant = first_handle.get("defs")
	var second_value: Variant = second_handle.get("defs")
	if not first_value is Dictionary or not second_value is Dictionary:
		_check(false, "Both catalog objects must expose definitions dictionaries")
		return
	var first_catalog: Dictionary = first_value
	var second_catalog: Dictionary = second_value
	_check(not first_catalog.is_empty() and not second_catalog.is_empty(), "Worlds expose catalog definitions")
	if first_catalog.is_empty() or second_catalog.is_empty():
		return
	_check_frozen(first_catalog, "first.catalog.defs")
	_check_frozen(second_catalog, "second.catalog.defs")
	_check(_entity(first, "knight").get("max_hp") == 17, "First world uses its instance definition override")
	_check(_entity(second, "knight").get("max_hp") == 23, "Second world uses its instance definition override")
	first_defs["characters"]["knight"]["label"] = "Changed after build"
	first_defs["characters"]["knight"]["max_hp"] = 99
	first_defs["classes"]["knight"]["abilities"].append("fixture_change")
	_check(first_catalog["characters"]["knight"]["label"] == "First knight", "Built catalog does not alias injected dictionaries")
	_check("fixture_change" not in first_catalog["classes"]["knight"]["abilities"], "Built catalog does not alias injected nested arrays")
	_check(second_catalog["characters"]["knight"]["label"] == "Second knight", "Changing first input does not affect second world")
	_check(_entity(first, "knight").get("max_hp") == 17 and _entity(second, "knight").get("max_hp") == 23,
		"Changing input after construction does not alter either world")


func _entity(state: Dictionary, id: String) -> Dictionary:
	for item in state.get("units", []) + state.get("obstacles", []):
		if item.get("id", "") == id:
			return item
	return {}


func _offers(state: Dictionary, actor: String, ability: String, target: String) -> bool:
	for choice in rules.call("targets", state, actor, ability):
		if choice.get("id", "") == target:
			return true
	return false


func _test_capability_opt_out() -> void:
	var defs := _fixture()
	# Define both sides of the comparison, rather than inheriting live tuning.
	for capability in ["pushable", "blocks_movement", "damageable"]:
		defs["capabilities"][capability] = {"label": capability}
	defs["objects"]["crate"]["capabilities"] = ["pushable", "blocks_movement", "damageable"]
	defs["objects"]["passable_crate"] = defs["objects"]["crate"].duplicate(true)
	defs["objects"]["passable_crate"]["capabilities"] = []
	var solid: Dictionary = rules.call("new_game", defs, "ferryman")
	var passable_defs := defs.duplicate(true)
	passable_defs["encounters"]["crossing"]["placements"][2]["object"] = "passable_crate"
	var passable: Dictionary = rules.call("new_game", passable_defs, "ferryman")
	if solid.is_empty() or passable.is_empty():
		_check(false, "Capability comparison fixtures must build")
		return
	for entry in [[solid, true], [passable, false]]:
		var state: Dictionary = entry[0]
		var expected: bool = entry[1]
		var before := state.duplicate(true)
		var offered := _offers(state, "knight", "knight_push", "fixture_crate")
		var plan: Dictionary = rules.call("preview", state, "knight", "knight_push", "fixture_crate")
		_check(offered == expected, "Push picker must respect object pushable capability")
		_check(plan.get("valid", false) == expected, "Push preview must agree with picker and capability")
		_check(state == before, "Target selection and preview must not mutate the world")
	var move: Dictionary = rules.call("preview", passable, "knight", "move", "1,0")
	_check(_offers(passable, "knight", "move", "1,0"), "Move picker offers the passable object's cell")
	_check(move.get("valid", false), "Move preview permits entering a non-blocking object's cell")
	if move.get("valid", false):
		var moved: Dictionary = rules.call("apply_plan", passable, move)
		_check(_entity(moved, "knight").get("position") == Vector2i(1, 0), "Knight moves onto non-blocking object")
		_check(_entity(moved, "fixture_crate").get("position") == Vector2i(1, 0), "Passable object remains in place")
	var blocked: Dictionary = rules.call("preview", solid, "knight", "move", "1,0")
	_check(not _offers(solid, "knight", "move", "1,0") and not blocked.get("valid", false),
		"Blocking object excludes its cell from both picker and preview")


func _test_reflect_capability_filter() -> void:
	var defs := _fixture()
	defs["capabilities"]["reflection_target"] = {"label": "Reflection target"}
	var enemy_profile: Dictionary = catalog.call("profile", defs, "harpooner")
	var tagged_caps: Array = enemy_profile["capabilities"].duplicate()
	tagged_caps.append("reflection_target")
	defs["characters"]["tagged_enemy"] = {
		"class": "enemy", "label": "Tagged enemy", "capabilities": tagged_caps, "max_hp": 20
	}
	defs["characters"]["harpooner"]["max_hp"] = 20
	defs["abilities"]["enemy_attack"]["params"]["damage"] = 2
	defs["statuses"]["aura"]["params"]["range"] = 1
	defs["statuses"]["aura"]["params"]["teams"] = ["enemies"]
	defs["statuses"]["aura"]["params"]["objects"] = false
	defs["statuses"]["aura"]["params"]["capabilities"] = ["reflection_target"]
	defs["encounters"]["crossing"]["placements"] = [
		{"id": "knight", "character": "knight", "at": [2, 2]},
		{"id": "ward", "character": "healer", "at": [3, 2]},
		{"id": "near_enemy", "character": "harpooner", "at": [4, 2]},
		{"id": "tagged_enemy", "character": "tagged_enemy", "at": [1, 2]},
		{"id": "civilian", "character": "ferryman", "at": [6, 3]}
	]
	var errors: PackedStringArray = catalog.call("validate", defs)
	_check(errors.is_empty(), "Reflect capability filter fixture must validate: " + str(errors))
	if not errors.is_empty():
		return
	var state: Dictionary = rules.call("new_game", defs, "ferryman")
	if state.is_empty():
		_check(false, "Reflect capability filter world must build")
		return
	var aura: Dictionary = rules.call("preview", state, "knight", "knight_aura", "")
	_check(aura.get("valid", false), "Knight can raise the reflect aura")
	if not aura.get("valid", false):
		return
	var protected: Dictionary = rules.call("apply_plan", state, aura)
	var attack: Dictionary = rules.call("preview", protected, "near_enemy", "enemy_attack", "ward")
	_check(attack.get("valid", false), "Adjacent enemy can attack the protected ward")
	if not attack.get("valid", false):
		return
	var result: Dictionary = rules.call("apply_plan", protected, attack)
	_check(_entity(result, "ward").get("hp") == _entity(protected, "ward").get("hp"),
		"Reflection protects the ward")
	_check(_entity(result, "near_enemy").get("hp") == 20,
		"Reflection excludes the nearer enemy without the required capability")
	_check(_entity(result, "tagged_enemy").get("hp") == 18,
		"Reflection selects the eligible farther enemy with the required capability")
