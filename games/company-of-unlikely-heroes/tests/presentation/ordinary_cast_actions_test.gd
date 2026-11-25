extends SceneTree
## Real rule handlers on controlled boards; no installed NPC atlas or cast metadata required.

const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const Fixtures = preload("res://tests/fixtures/rules_catalog.gd")

var rules := Rules.new()
var failures: Array[String] = []


func _initialize() -> void:
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
	_configure(defs, "hookhand", "hook_pull", "hook")
	_configure(defs, "rival_knight", "knight_push", "push")
	_configure(defs, "rival_wizard", "rival_blast", "blast")
	_configure(defs, "rival_healer", "frontier_heal", "enemy_heal")
	_configure(defs, "trickster", "ogre_swap", "swap_ally")
	_configure(defs, "frontier_war_drummer", "frontier_war_drum", "perform")
	_configure(defs, "frontier_shepherd", "frontier_shepherd_wave", "attack")
	_check(Catalog.validate(defs).is_empty(), "All six ordinary handlers validate in their effective kits")
	_case(defs, "hookhand", "hook_pull", "healer", Vector2i(4, 2), "shift", Vector2i(3, 2), "target")
	_case(defs, "rival_knight", "knight_push", "healer", Vector2i(3, 2), "shift", Vector2i(4, 2), "target")
	_case(defs, "rival_knight", "knight_push", "healer", Vector2i(3, 2), "hit", Vector2i(3, 2),
		"target", [_actor("wall", "knight", Vector2i(4, 2))])
	_case(defs, "rival_wizard", "rival_blast", "healer", Vector2i(3, 2), "hit", Vector2i(3, 2))
	_case(defs, "rival_healer", "frontier_heal", "ogre", Vector2i(3, 2), "heal", Vector2i(3, 2))
	_case(defs, "trickster", "ogre_swap", "ogre", Vector2i(3, 2), "shift", Vector2i(2, 2))
	_case(defs, "frontier_war_drummer", "frontier_war_drum", "healer", Vector2i(4, 2), "hit", Vector2i(4, 2))
	_resisted_shift(defs, "hookhand", "hook_pull", Vector2i(4, 2))
	_resisted_shift(defs, "rival_knight", "knight_push", Vector2i(3, 2))
	_harmless_wave(defs)
	_recover(defs)
	_authored_alchemist_pull(defs)
	defs.characters.hookhand.cast_presentation.actions.hook_pull.handler = "attack"
	var state := _state(defs, "hookhand", "healer", Vector2i(4, 2))
	var plan: Dictionary = rules.preview(state, "caster", "hook_pull", "target")
	_check(plan.valid and Cues.build(state, plan.result, plan.events).is_empty(),
		"Catalog handler mismatch does not use a stale cast, even though the rules still pull")
	for message in failures:
		push_error(message)
	if failures.is_empty():
		print("PASS: ordinary cast NPC action families on controlled boards")
	quit(0 if failures.is_empty() else 1)


func _authored_alchemist_pull(defs: Dictionary) -> void:
	var local := defs.duplicate(true)
	local.classes.alchemist.abilities.append("hook_pull")
	local.characters.alchemist["cast_presentation"] = {"actions": {
		"hook_pull": {"handler": "hook", "clip": "pull"}}}
	var state := _state(local, "alchemist", "healer", Vector2i(4, 2))
	var plan: Dictionary = rules.preview(state, "caster", "hook_pull", "target")
	if not plan.get("valid", false):
		_check(false, "Authored Alchemist hook fixture resolves")
		return
	var cues := Cues.build(state, plan.result, plan.events)
	_check(cues.size() == 1 and cues[0].get("ordinary_presentation", false) \
		and cues[0].get("clip") == "pull",
		"An ordinary data-authored Alchemist pull retains its declared clip")


func _configure(defs: Dictionary, id: String, ability: String, handler: String) -> void:
	var actor: Dictionary = defs.characters[id]
	var profile := Catalog.profile(defs, id)
	actor["cast_key"] = "fixture_" + id
	actor["cast_team"] = profile.team
	actor["cast_art_key"] = profile.art_key
	actor["cast_variant"] = profile.get("art_variant", "")
	actor["cast_presentation"] = {"actions": {ability: {"handler": handler, "clip": "fixture_take"}}}


func _state(defs: Dictionary, caster: String, target: String, at: Vector2i) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 8
	state.height = 8
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [_actor("caster", caster, Vector2i(2, 2)), _actor("target", target, at)]
	state.overrides = {}
	state.orders = {}
	return state


func _actor(id: String, character: String, at: Vector2i) -> Dictionary:
	return {"id": id, "character_id": character, "position": at, "hp": 5, "max_hp": 10, "statuses": {}}


func _recover(defs: Dictionary) -> void:
	defs.characters.hookhand.cast_presentation["events"] = {"recover": "get_up"}
	var state := _state(defs, "wizard", "hookhand", Vector2i(3, 2))
	var down: Dictionary = rules.preview(state, "caster", "wizard_blast")
	_check(down.valid and rules.knocked_down(down.result, "target"), "Real Wizard Blast knocks Hookhand down")
	if not down.valid:
		return
	_check(not Cues.build(state, down.result, down.events).any(func(cue): return cue.clip == "get_up"),
		"Being knocked down is not recovery")
	var plan: Dictionary = rules.preview_round(down.result)
	var recovered := Cues.build(down.result, plan.result, plan.events).filter(
		func(cue): return cue.get("ordinary_role") == "recover")
	_check(recovered.size() == 1 and recovered[0].unit_id == "target" and recovered[0].clip == "get_up" \
		and recovered[0].source_cell == Vector2i(3, 2) and not rules.knocked_down(plan.result, "target"),
		"Only the owner of a real knockdown recovery gets its authored cue")


func _resisted_shift(defs: Dictionary, caster: String, ability: String, at: Vector2i) -> void:
	var state := _state(defs, caster, "healer", at)
	state.units[1]["alchemy_statuses"] = {"cork_soles": {"expires_after_round": state.round}}
	var plan: Dictionary = rules.preview(state, "caster", ability, "target")
	_check(plan.valid and plan.events.size() == 1, "%s consumed Cork Soles without moving or damaging" % ability)
	if not plan.valid or plan.events.size() != 1:
		return
	var resisted: Dictionary = plan.events[0]
	_check(resisted.type == "status" and resisted.reaction_id == "cork_soles" \
		and resisted.unit_id == "target" and resisted.target_id == "target" \
		and resisted.resisted_target_id == "target" and resisted.resolved_action.unit_id == "caster" \
		and plan.result.units[1].position == at,
		"%s preserves actual resistance ownership and the intended target" % ability)
	var cues := Cues.build(state, plan.result, plan.events)
	_check(cues.size() == 1 and cues[0].unit_id == "caster" and cues[0].target_id == "target" \
		and cues[0].target_cell == at and cues[0].recipients.is_empty(),
		"%s still aims at the selected target, with no shift or hit" % ability)


func _harmless_wave(defs: Dictionary) -> void:
	var cell := Vector2i(3, 2)
	var state := _state(defs, "frontier_shepherd", "frontier_sheep", cell)
	var plan: Dictionary = rules.preview(state, "caster", "frontier_shepherd_wave", "target")
	_check(plan.valid and plan.events.any(func(event: Dictionary) -> bool:
		return event.type == "damage" and event.get("target_id") == "target" and event.get("amount") == 0),
		"Real Sheep Wave reports the selected target but deals zero damage")
	var cues := Cues.build(state, plan.result, plan.events)
	_check(cues.size() == 1 and cues[0].clip == "fixture_take" and cues[0].target_id == "target" \
		and cues[0].target_cell == cell and cues[0].recipients.is_empty(),
		"Harmless Wave plays and aims at the sheep without a hit/flash recipient")


func _case(defs: Dictionary, caster: String, ability: String, target: String, at: Vector2i,
		kind: String, recipient_cell: Vector2i, explicit := "", extras := []) -> void:
	var state := _state(defs, caster, target, at)
	state.units.append_array(extras)
	var plan: Dictionary = rules.preview(state, "caster", ability, explicit)
	_check(plan.valid, "%s resolves a real legal action" % ability)
	if not plan.valid:
		return
	var cues := Cues.build(state, plan.result, plan.events)
	var matching := cues.filter(func(cue): return cue.get("unit_id") == "caster")
	_check(matching.size() == 1, "%s produces exactly one owned cue: %s" % [ability, cues])
	if matching.size() != 1:
		return
	var cue: Dictionary = matching[0]
	_check(cue.clip == "fixture_take" and cue.ordinary_role == "action" \
		and cue.source_cell == Vector2i(2, 2) and cue.get("target_cell") == at and cue.target_id == "target",
		"%s aims from the caster's source at the action-time recipient" % ability)
	_check(cue.recipients == [{"id": "target", "cell": recipient_cell, "kind": kind}],
		"%s marks only the actual recipient at the right position: %s" % [ability, cue])


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
