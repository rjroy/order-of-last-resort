extends SceneTree

# Run with: godot --headless --path games/company-of-unlikely-heroes --script res://tests/expedition/rescues_test.gd
# Each round has optional "orders": [{unit, order}] and
# "action": {unit, ability, target}. Empty rounds use standing orders.
const PULL_RESCUE: Array = [
	{"action": {"unit": "wizard", "ability": "wizard_pull", "target": "civilian"}},
	{}, {}, {}
]
const NO_PULL_RESCUE: Array = [
	{"action": {"unit": "wizard", "ability": "wizard_blast", "target": "crate"}},
	{"action": {"unit": "wizard", "ability": "wizard_blast", "target": "crate"}},
	{"action": {"unit": "wizard", "ability": "wizard_blast", "target": "harpooner"}},
	{"action": {"unit": "wizard", "ability": "wizard_blast", "target": "harpooner"}},
	{"action": {"unit": "wizard", "ability": "move", "target": "4,3"}},
	{}, {}, {}, {}
]
const LOSS: Array = [{}, {}, {}, {}, {}, {}, {}, {}, {}, {}]

var failures: Array[String] = []
var rules: RefCounted


func _initialize() -> void:
	if not ResourceLoader.exists("res://rules/rules.gd"):
		_fail("Awaiting rules.gd and its actual new_game map; rescue routes cannot yet be pinned")
	else:
		var script = load("res://rules/rules.gd")
		if script == null or not script.can_instantiate():
			_fail("rules.gd cannot be instantiated")
		else:
			rules = script.new()
			_run()
	if failures.is_empty():
		print("PASS: reproducible hybrid rescues and loss")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _fail(message: String) -> void:
	failures.append(message)


func _run() -> void:
	for method in ["new_game", "options", "targets", "set_order", "choose_manual", "preview", "preview_round", "commit_round"]:
		if not rules.has_method(method):
			_fail("Missing gameplay API method: " + method)
	for method in rules.get_method_list():
		if method.name == "new_game" and method.args.size() != 2:
			_fail("new_game must accept definitions and mission_id, without a mode")
	if not failures.is_empty():
		return
	# These routes exercise a test-owned wizard starting position on the rescue board.
	var defs: Dictionary = preload("res://content/catalog.gd").read_default()
	defs.encounters.company_crossing.party_slots[2] = [4, 2]
	var party := ["knight", "healer", "wizard"]
	var initial = rules.call("open_mission", defs, "company_rescue", party)
	if not initial is Dictionary:
		_fail("new_game must return a state Dictionary")
		return
	if initial.get("outcome", "") != "ongoing":
		_fail("A new hybrid game must start ongoing")
		return
	_check_wizard_orders(initial)
	_play("pull rescue", initial, PULL_RESCUE, "victory", true)
	_play("no-pull rescue", initial, NO_PULL_RESCUE, "victory", false)
	_play("loss", initial, LOSS, "defeat", false)
	var restart = rules.call("open_mission", defs, "company_rescue", party)
	if _mutable_facts(restart) != _mutable_facts(initial):
		_fail("Restart must reproduce the clean initial state, including orders and overrides")


func _check_wizard_orders(state: Dictionary) -> void:
	var order_ids: Array = []
	for option in rules.call("options", state, "wizard"):
		if option.get("kind") == "order":
			order_ids.append(option.get("id"))
	order_ids.sort()
	if order_ids != ["order_blast", "order_cautious"]:
		_fail("Stock wizard must offer exactly Hold and Blast standing orders, got %s" % [order_ids])
	for order_id in ["order_cautious", "order_blast"]:
		if not _has_option(state, "wizard", order_id, "order") \
				or rules.call("set_order", state, "wizard", order_id).get("orders", {}).get("wizard") != order_id:
			_fail("Stock wizard must be able to select %s" % order_id)
	var rejected: Dictionary = rules.call("set_order", state, "wizard", "order_rescue")
	if rejected.get("orders") != state.get("orders"):
		_fail("Stock wizard must reject the retired ferry standing order")


func _play(name: String, initial: Dictionary, route: Array, outcome: String, require_pull: bool) -> void:
	if route.is_empty():
		_fail("%s route not yet pinned against the actual opening map" % name)
		return
	var state := initial.duplicate(true)
	var pulled_civilian := false
	var used_pull := false
	var start_snapshot := initial.duplicate(true)
	for step in route:
		if state.get("outcome", "") != "ongoing":
			_fail("%s route continues after the encounter ends" % name)
			return
		for order in step.get("orders", []):
			var unit_id: String = order.get("unit", "")
			var order_id: String = order.get("order", "")
			if not _has_option(state, unit_id, order_id, "order"):
				_fail("%s uses an unavailable standing order" % name)
				return
			var updated = rules.call("set_order", state, unit_id, order_id)
			if not updated is Dictionary or updated.get("orders", {}).get(unit_id, "") != order_id:
				_fail("%s could not set a standing order" % name)
				return
			state = updated
		var action: Dictionary = step.get("action", {})
		if not action.is_empty():
			var unit_id: String = action.get("unit", "")
			var ability: String = action.get("ability", "")
			var target: String = action.get("target", "")
			if not _has_option(state, unit_id, ability, "action"):
				_fail("%s uses an unavailable action" % name)
				return
			if not target.is_empty() and not _has_target(state, unit_id, ability, target):
				_fail("%s uses an unavailable target" % name)
				return
			if ability == "wizard_pull":
				used_pull = true
			var selected = rules.call("choose_manual", state, unit_id, ability, target)
			if not selected is Dictionary or selected == state:
				_fail("%s manual action was not installed" % name)
				return
			state = selected
		var before := state.duplicate(true)
		var expected_pull := false
		if action.get("ability", "") == "wizard_pull":
			var target_id: String = action.get("target", "")
			var wizard_before := _unit(before, action.get("unit", ""))
			var pull = rules.call("preview", before, action.get("unit", ""), "wizard_pull", target_id)
			expected_pull = pull is Dictionary and pull.get("valid", false) \
				and target_id == before.objective.subject \
				and _unit(pull.get("result", {}), target_id).get("position") == wizard_before.get("position")
		var plan = rules.call("preview_round", state)
		if state != before:
			_fail("%s round preview mutated state" % name)
			return
		if not plan is Dictionary or not plan.get("valid", false) or not plan.get("result") is Dictionary:
			_fail("%s round preview is invalid" % name)
			return
		var committed = rules.call("commit_round", state, plan)
		if not _matches_preview(committed, plan):
			_fail("%s commit differs from its preview" % name)
			return
		if expected_pull:
			# The civilian may move again after the pull, before the round ends.
			for event in plan.get("events", []):
				if event.get("type", "") == "pull" and event.get("target_id", "") == action.get("target", "") \
						and event.get("unit_id", "") == action.get("unit", "") \
						and event.get("position") == _unit(before, action.get("unit", "")).get("position"):
					pulled_civilian = true
		if committed.get("outcome", "") != "ongoing":
			var event_found := false
			for event in plan.get("events", []):
				if event.get("type", "") == committed.get("outcome", ""):
					event_found = true
			if not event_found:
				_fail("%s terminal outcome missing from preview events" % name)
		state = committed
	if initial != start_snapshot:
		_fail("%s mutated the shared initial state" % name)
	if state.get("outcome", "") != outcome:
		_fail("%s did not produce real %s" % [name, outcome])
	if state.get("round", -1) != route.size():
		_fail("%s did not end on its expected round" % name)
	if outcome == "victory" and not _civilian_at_exit(state):
		_fail("%s victory did not transport a civilian to the exit" % name)
	if require_pull and not pulled_civilian:
		_fail("%s did not successfully pull a civilian to the wizard's former cell" % name)
	if name == "no-pull rescue" and used_pull:
		_fail("No-pull rescue must not use wizard pull")


func _has_option(state: Dictionary, unit_id: String, id: String, kind: String) -> bool:
	var options = rules.call("options", state, unit_id)
	if options is Array:
		for option in options:
			if option is Dictionary and option.get("id", "") == id and option.get("kind", "") == kind and not str(option.get("label", "")).is_empty():
				return true
	return false


func _has_target(state: Dictionary, unit_id: String, ability: String, id: String) -> bool:
	var targets = rules.call("targets", state, unit_id, ability)
	if targets is Array:
		for target in targets:
			if target is Dictionary and target.get("id", "") == id and not str(target.get("label", "")).is_empty():
				return true
	return false


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit in state.get("units", []):
		if unit.get("id", "") == id:
			return unit
	return {}


func _civilian_at_exit(state: Dictionary) -> bool:
	return _unit(state, state.objective.subject).get("position") == state.objective.destination


func _mutable_facts(state: Dictionary) -> Dictionary:
	var facts := {}
	for key in ["width", "height", "units", "terrain", "obstacles", "objective",
			"round", "mode", "orders", "overrides", "outcome"]:
		facts[key] = state.get(key)
	return facts


func _matches_preview(committed: Dictionary, plan: Dictionary) -> bool:
	var gameplay := committed.duplicate(true)
	gameplay.erase("_terminal_commit")
	return gameplay == plan.get("result")
