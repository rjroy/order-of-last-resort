extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/content_test.gd
var failures: Array[String] = []
var rules: RefCounted
var catalog: Script


func _initialize() -> void:
	if not ResourceLoader.exists("res://content/catalog.gd"):
		failures.append("Missing res://content/catalog.gd")
	elif not ResourceLoader.exists("res://rules.gd"):
		failures.append("Missing res://rules.gd")
	else:
		catalog = load("res://content/catalog.gd")
		rules = load("res://rules.gd").new()
		_test_instances()
		_test_escort()
		_test_authored_deadline()
		_test_adventure_content()
	if failures.is_empty():
		print("PASS: authored content variations")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _entity(state: Dictionary, id: String) -> Dictionary:
	for item in state.get("units", []) + state.get("obstacles", []):
		if item.get("id", "") == id:
			return item
	return {}


func _has_option(state: Dictionary, actor: String, id: String) -> bool:
	for option in rules.call("options", state, actor):
		if option.get("id", "") == id:
			return true
	return false


func _check_restart(restarted: Dictionary, before: Dictionary, message: String) -> void:
	var restarted_state := restarted.duplicate()
	var before_state := before.duplicate()
	var restarted_catalog = restarted_state.get("catalog")
	var before_catalog = before_state.get("catalog")
	restarted_state.erase("catalog")
	before_state.erase("catalog")
	_check(restarted_state == before_state, message)
	_check(restarted_catalog != null and before_catalog != null, message + ": catalogs must exist")
	if restarted_catalog != null and before_catalog != null:
		_check(restarted_catalog.defs == before_catalog.defs, message + ": catalog definitions differ")


func _test_instances() -> void:
	var untouched: Dictionary = catalog.call("read_default")
	var definitions: Dictionary = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(untouched.duplicate(true))
	var placements: Array = definitions["encounters"]["test_escort"]["placements"]
	# Fixture-owned positions ensure the new crate is the blast's nearest target.
	var wizard_profile: Dictionary = catalog.call("profile", definitions, "wizard")
	definitions["characters"]["blast_knight"] = {
		"class": "knight", "label": "Blast knight", "abilities": ["move", "wizard_blast"],
		"habits": {"order_blast": wizard_profile["habits"]["order_blast"]},
		"default_order": "order_blast"
	}
	definitions["abilities"]["wizard_blast"]["params"]["damage"] = 1
	placements.append({"id": "second_knight", "character": "blast_knight", "at": [6, 4]})
	placements.append({"id": "second_crate", "object": "crate", "at": [5, 4]})
	var authored := definitions.duplicate(true)
	var initial: Dictionary = rules.call("new_game", definitions, "test_escort")
	if initial.is_empty():
		failures.append("Instance fixture failed to build")
		return
	_check(definitions == authored, "new_game must not mutate authoring data")
	var second := _entity(initial, "second_knight")
	var crate := _entity(initial, "second_crate")
	var original_crate := _entity(initial, "crate")
	_check(rules.entity_profile(initial, "second_knight").get("class") == "knight", "Second instance uses knight definition")
	_check(not second.has("class") and not second.has("team"), "Unit profile fields are not duplicated in mutable state")
	_check(second.get("position") == Vector2i(6, 4), "Second knight uses its own placement")
	_check(crate.get("position") == Vector2i(5, 4), "Second crate uses its own placement")
	_check(not crate.is_empty() and not original_crate.is_empty(), "Both crate instances exist")
	_check(_has_option(initial, "second_knight", "wizard_blast"), "Override gives the second knight wizard blast")
	_check(not _has_option(initial, "second_knight", "knight_push"), "Override removes knight push from the second knight")
	_check(_has_option(initial, "knight", "knight_push"), "Original knight keeps its own kit")
	var before := initial.duplicate(true)
	var plan: Dictionary = rules.call("preview", initial, "second_knight", "wizard_blast", "")
	_check(initial == before, "Ability preview must not mutate input")
	_check(plan.get("valid", false), "Second knight can use its authored blast")
	if plan.get("valid", false):
		var after: Dictionary = rules.call("apply_plan", initial, plan)
		_check(initial == before, "Applying an ability plan must not mutate input")
		_check(_entity(after, "second_crate").get("hp", 0) == crate.get("hp", 0) - 1, "Blast uses authored damage")
		_check(_entity(after, "crate") == original_crate, "Blast leaves original crate unchanged")
	var round_plan: Dictionary = rules.call("preview_round", initial)
	_check(initial == before, "Standing round preview must not mutate input")
	_check(round_plan.get("valid", false), "Standing round preview is valid")
	if round_plan.get("valid", false):
		var committed: Dictionary = rules.call("commit_round", initial, round_plan)
		_check(_matches_preview(committed, round_plan), "Standing round commits its preview")
		_check(_entity(committed, "second_crate").get("hp", 0) == crate.get("hp", 0) - 1,
			"Second knight follows its personal blast habit")
		_check(_entity(committed, "crate") == original_crate, "Personal habit leaves other crate unchanged")
	var restarted: Dictionary = rules.call("new_game", definitions, "test_escort")
	_check_restart(restarted, before, "Restart restores authored instance positions and health")
	_check(definitions == authored, "Play and restart must not mutate authoring data")
	_check(catalog.call("read_default") == untouched, "A modified catalog does not alter fresh defaults")


func _test_escort() -> void:
	var definitions: Dictionary = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(catalog.call("read_default"))
	definitions["boards"]["bridge"]["locations"]["safe_bank"] = [6, 4]
	definitions["missions"]["test_escort"]["objective"]["subject"] = "passenger"
	definitions["encounters"]["test_escort"]["placements"] = [
		{"id": "knight", "character": "knight", "at": [0, 0]},
		{"id": "other_ferryman", "character": "ferryman", "at": [6, 3]},
		{"id": "passenger", "character": "ferryman", "at": [5, 4]},
		{"id": "harpooner", "character": "harpooner", "at": [4, 4]}
	]
	var initial: Dictionary = rules.call("new_game", definitions, "test_escort")
	if initial.is_empty():
		failures.append("Escort fixture failed to build")
		return
	var before := initial.duplicate(true)
	_check(initial.objective.destination == Vector2i(6, 4), "Named destination resolves at its authored location")
	_check(not _entity(initial, "passenger").is_empty(), "Renamed escort instance exists")
	var plan: Dictionary = rules.call("preview_round", initial)
	_check(initial == before, "Escort round preview must not mutate input")
	_check(plan.get("valid", false), "Escort round preview is valid")
	if not plan.get("valid", false):
		return
	var committed: Dictionary = rules.call("commit_round", initial, plan)
	_check(initial == before, "Escort commit must not mutate input")
	_check(_matches_preview(committed, plan), "Escort commit matches preview")
	_check(_entity(committed, "passenger").get("hp", 0) < _entity(initial, "passenger").get("hp", 0),
		"Threat NPC targets the renamed objective subject")
	_check(_entity(committed, "passenger").get("position") == Vector2i(6, 4),
		"Escort NPC moves toward the relocated destination")
	_check(_entity(committed, "other_ferryman").get("position") == Vector2i(6, 3),
		"Other escort instance does not move to or block the objective destination")
	_check(committed.get("outcome", "") == "victory",
		"Renamed subject reaching relocated destination wins")
	_check(rules.call("commit_round", initial, plan) == committed, "Committing the same escort preview is deterministic")
	_check_restart(rules.call("new_game", definitions, "test_escort"), before,
		"Restart restores the renamed objective and relocated destination")


func _test_authored_deadline() -> void:
	var definitions: Dictionary = preload("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(catalog.read_default())
	definitions.encounters.test_escort.deadline = 1
	var state: Dictionary = rules.new_game(definitions, "test_escort")
	_check(not state.has("bridge_deadline") and not state.has("exit") \
		and not state.has("victory") and not state.has("defeat"), "Opening has no duplicate authorities")
	_check(rules.deadline(state) == 1, "Deadline comes from authored encounter")
	var plan: Dictionary = rules.preview_round(state)
	var result: Dictionary = rules.commit_round(state, plan)
	_check(result.outcome == "defeat" and result.round == 1, "Authored first-round deadline causes defeat")
	_check(not result.has("victory") and not result.has("defeat"), "Outcome remains the only result authority")


func _test_adventure_content() -> void:
	var definitions: Dictionary = catalog.read_default()
	var adventure: Dictionary = definitions.get("adventures", {}).get("first_outing", {})
	_check(not adventure.is_empty(), "First outing is authored")
	if adventure.is_empty():
		return
	_check(adventure.get("roster", []) == ["knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard"],
		"First outing offers the seven named heroes")
	_check(adventure.get("party_size") == 3, "First outing requires exactly three heroes")
	_check(adventure.get("missions", []) == ["bridge_patrol", "company_rescue"],
		"First outing has the two ordered missions")
	var missions: Dictionary = definitions.get("missions", {})
	var patrol: Dictionary = missions.get("bridge_patrol", {})
	var rescue: Dictionary = missions.get("company_rescue", {})
	_check(patrol.get("objective", {}).get("handler") == "defeat_all",
		"Patrol victory requires eliminating all enemies")
	_check(rescue.get("objective", {}).get("handler") == "escort",
		"Second mission retains its escort objective")
	var failures_found := false
	for failure in patrol.get("failures", []):
		if failure.get("handler") == "party_wiped":
			failures_found = true
		_check(failure.get("handler") != "deadline", "Patrol is untimed")
	_check(failures_found, "Patrol defeat requires the party to be wiped")
	for mission in [patrol, rescue]:
		var encounter: Dictionary = definitions.get("encounters", {}).get(mission.get("encounter", ""), {})
		_check(encounter.get("party_slots", []).size() == 3,
			"Adventure encounter provides three ordered party slots")


func _matches_preview(committed: Dictionary, plan: Dictionary) -> bool:
	var gameplay := committed.duplicate(true)
	gameplay.erase("_terminal_commit")
	return gameplay == plan.get("result")
