extends SceneTree
## Godot headless. Test-owned board placement, HP and presentation mappings.

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")
const Playback = preload("res://presentation/cast_playback.gd")
const Fixtures = preload("res://tests/fixtures/rules_catalog.gd")
var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
var rules := Rules.new()
var failures: Array[String] = []


func _initialize() -> void:
	_guard()
	_retaliation()
	_chain_defeat()
	_empowered_actions()
	_swap_and_reinforcement()
	_objectives()
	_validation()
	for message in failures:
		push_error("FAIL: " + message)
	if failures.is_empty():
		print("PASS: ordinary cast event ownership, dependencies and contextual holds")
	quit(0 if failures.is_empty() else 1)


func _bind(id: String, presentation: Dictionary) -> void:
	var actor: Dictionary = defs.characters[id]
	var profile := Catalog.profile(defs, id)
	actor.merge({"cast_key": "fixture_" + id, "cast_art_key": profile.art_key,
		"cast_team": profile.team, "cast_variant": profile.get("art_variant", ""),
		"cast_presentation": presentation}, true)


func _unit(id: String, role: String, x: int, y: int, hp := 9) -> Dictionary:
	return {"id": id, "character_id": role, "position": Vector2i(x, y),
		"hp": hp, "max_hp": 9, "statuses": {}}


func _state(units: Array) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.merge({"width": 10, "height": 10, "default_tile": "stone", "terrain": [], "units": units,
		"obstacles": [], "overrides": {}, "orders": {}}, true)
	return state


func _guard() -> void:
	_bind("shieldbearer", {"events": {"adjacent_guard": "fixture_protect"}})
	var state := _state([_unit("swinger", "healer", 2, 2), _unit("ward", "archer", 3, 2),
		_unit("protector", "shieldbearer", 3, 3), _unit("remote", "shieldbearer", 6, 6)])
	var plan: Dictionary = rules.preview(state, "swinger", "healer_bonk", "ward")
	_check(plan.valid, "Healer can attack protected archer")
	if not plan.valid:
		return
	var cues := Cues.build(state, plan.result, plan.events)
	var guard := _cue(cues, "protector", "adjacent_guard")
	_check(guard.get("clip") == "fixture_protect" and guard.get("source_cell") == Vector2i(3, 3) \
		and guard.get("target_cell") == Vector2i(3, 2) and guard.get("after_cue") == 0,
		"Only adjacent owner raises its guard at the initiating strike's impact")
	_check(_cue(cues, "ward", "adjacent_guard").is_empty() and _cue(cues, "remote", "adjacent_guard").is_empty(),
		"Neither the ward nor an unrelated placement provides the trait")


func _retaliation() -> void:
	_bind("duelist", {"events": {"retaliate": "fixture_reply"}, "hit": "fixture_hit"})
	_bind("healer", {"actions": {"healer_bonk": {"handler": "attack", "clip": "fixture_swing"}},
		"hit": "fixture_attacker_hit"})
	var state := _state([_unit("attacker", "healer", 2, 2), _unit("defender", "duelist", 3, 2)])
	var plan: Dictionary = rules.preview(state, "attacker", "healer_bonk", "defender")
	if not plan.valid:
		_check(false, "Real duelist takes a survivable hit")
		return
	var cues := Cues.build(state, plan.result, plan.events)
	var reply := _cue(cues, "defender", "retaliate")
	var hit := _cue(cues, "attacker", "hit")
	_check(reply.get("clip") == "fixture_reply" and reply.get("target_cell") == Vector2i(2, 2) \
		and reply.get("recipients") == [{"id": "attacker", "cell": Vector2i(2, 2), "kind": "hit"}] \
		and hit.get("after_cue", -1) == cues.find(reply),
		"Retaliation belongs to the defender; its damage is parented to the reply, not the original attack")


func _chain_defeat() -> void:
	_bind("bomber", {"defeat": "boom"})
	var state := _state([_unit("attacker", "healer", 2, 2), _unit("first", "bomber", 3, 2, 1),
		_unit("second", "bomber", 4, 2, 1)])
	var plan: Dictionary = rules.preview(state, "attacker", "healer_bonk", "first")
	if not plan.valid:
		_check(false, "Initiating attack is legal")
		return
	var cues := Cues.build(state, plan.result, plan.events)
	var first := _cue(cues, "first", "defeat")
	var second := _cue(cues, "second", "defeat")
	_check(first.get("clip") == "boom" and second.get("clip") == "boom" \
		and second.get("after_cue") == cues.find(first),
		"Each bomber plays defeat once; secondary bomber is scheduled from the first detonation")


func _empowered_actions() -> void:
	_bind("bandit_damage", {"actions": {"bandit_strike": {"handler": "attack", "clip": "ordinary",
		"bonus": {"stat": "damage", "clip": "stronger"}}}})
	_bind("bandit_swift", {"actions": {"move": {"handler": "move", "clip": "ordinary",
		"bonus": {"stat": "movement", "clip": "quicker"}}}})
	var state := _state([_unit("fierce", "bandit_damage", 2, 2),
		_unit("opponent", "healer", 3, 2), _unit("fallen", "bandit_guard", 8, 8, 0)])
	var strike: Dictionary = rules.preview(state, "fierce", "bandit_strike", "opponent")
	var fierce := _cue(Cues.build(state, strike.result, strike.events), "fierce", "action")
	_check(fierce.get("clip") == "stronger" and fierce.get("fallback_clip") == "ordinary",
		"Active fallen-ally damage trait chooses the stronger take")
	state.units.back().hp = 9
	strike = rules.preview(state, "fierce", "bandit_strike", "opponent")
	_check(_cue(Cues.build(state, strike.result, strike.events), "fierce", "action").get("clip") == "ordinary",
		"Living allies do not empower the attack")
	var art := Sprites.new()
	var clip := Sprites.Clip.new()
	clip.total_ms = 200
	art.set("_actors", {"fixture_bandit_damage": {"ordinary": clip}})
	var playback := Playback.new()
	playback.enqueue([fierce], art)
	_check(playback.snapshot().size() == 1 and playback.snapshot()[0].clip == "ordinary",
		"A missing stronger atlas take falls back to the normal action")
	state = _state([_unit("swift", "bandit_swift", 2, 2), _unit("fallen", "bandit_guard", 8, 8, 0)])
	for ix in [3, 4]:
		var move: Dictionary = rules.preview(state, "swift", "move", "%d,2" % ix)
		var cue := _cue(Cues.build(state, move.result, move.events), "swift", "action")
		_check(cue.get("clip") == ("ordinary" if ix == 3 else "quicker"),
			"Only using the bonus to take an actual second step plays the quicker take")


func _swap_and_reinforcement() -> void:
	_bind("trickster", {"actions": {"ogre_swap": {"handler": "swap_ally", "clip": "trade"}}})
	_bind("ogre", {"events": {"swapped": "moved_by_a_friend", "reserve_arrival": "enter"}})
	var state := _state([_unit("trick", "trickster", 2, 2), _unit("ogre", "ogre", 3, 2)])
	var plan: Dictionary = rules.preview(state, "trick", "ogre_swap")
	var cues := Cues.build(state, plan.result, plan.events)
	var moved := _cue(cues, "ogre", "swapped")
	_check(moved.get("source_cell") == Vector2i(3, 2) and moved.get("actor_cell") == Vector2i(2, 2) \
		and moved.get("after_cue", -1) == cues.find(_cue(cues, "trick", "action")),
		"Partner's swap reaction follows the owning action with both timeline positions")
	state = _state([_unit("hero", "healer", 0, 0)])
	state.objective = {"handler": "survive", "turns": 6, "reserve_round": 2, "subject": "hero",
		"reserves": [_unit("reserve", "ogre", 8, 8)]}
	plan = rules.preview_round(state)
	cues = Cues.build(state, plan.result, plan.events)
	var arrival := _cue(cues, "reserve", "reserve_arrival")
	_check(arrival.get("source_cell") == Vector2i(8, 8) and arrival.get("clip") == "enter",
		"A true reserve uses its entry cell, not an enclosing action's actor")
	state.units.append(_unit("blocker", "healer", 8, 8))
	plan = rules.preview_round(state)
	_check(_cue(Cues.build(state, plan.result, plan.events), "reserve", "reserve_arrival").is_empty(),
		"An occupied reserve entry does not play its arrival")


func _objectives() -> void:
	_bind("frontier_sheep", {"events": {"sheep_flee": "run", "sheep_entry": "settle"},
		"holds": {"sheep_penned": "held"}})
	_bind("frontier_wagon", {"events": {"wagon_advance": "roll", "wagon_stall": "stall"},
		"defeat": "fall", "holds": {"wagon_wreck": "wreck"}})
	var sheep := _unit("sheep", "frontier_sheep", 3, 2)
	var state := _state([_unit("hero", "healer", 2, 2), sheep])
	state.objective = {"handler": "herd_sheep", "subjects": ["sheep"],
		"pen": [Vector2i(4, 2), Vector2i(5, 2)]}
	var plan: Dictionary = rules.preview_round(state)
	var cues := Cues.build(state, plan.result, plan.events)
	_check(_cue(cues, "sheep", "sheep_flee").get("actor_cell") == Vector2i(4, 2) \
		and _cue(cues, "sheep", "sheep_entry").get("source_cell") == Vector2i(4, 2),
		"Actual flight and settling cues carry the crossing's source and destination")
	_check(not cues.any(func(cue): return cue.clip == "held"), "A pen pose is never a queued gesture")
	var after_sheep: Dictionary = plan.result.units[1]
	var presentation := Cues.presentation_for(plan.result, after_sheep)
	_check(Cues.held_clip_for(plan.result, after_sheep, presentation) == "held",
		"A living objective sheep inside the pen is held even without events")
	var other := after_sheep.duplicate()
	other.id = "not_subject"
	_check(Cues.held_clip_for(plan.result, other, presentation).is_empty(),
		"A non-subject inside the same pen does not acquire the hold")
	var wagon := _unit("supply", "frontier_wagon", 3, 2)
	state = _state([_unit("hero", "healer", 0, 0), wagon])
	state.objective = {"handler": "wagon", "subject": "supply", "destination": Vector2i(5, 2)}
	plan = rules.preview_round(state)
	var advance := _cue(Cues.build(state, plan.result, plan.events), "supply", "wagon_advance")
	_check(advance.get("clip") == "roll" and advance.get("actor_cell") == Vector2i(4, 2),
		"Real end-of-round wagon movement plays its take at the destination")
	state.units.append(_unit("blocker", "frontier_war_drummer", 3, 3))
	plan = rules.preview_round(state)
	var stalls := Cues.build(state, plan.result, plan.events).filter(
		func(cue): return cue.get("ordinary_role") == "wagon_stall")
	var stalled: Dictionary = stalls[0] if stalls.size() == 1 else {}
	_check(stalled.get("source_cell") == Vector2i(3, 2) and stalled.get("actor_cell") == Vector2i(3, 2),
		"Real wagon stall is stationary; the earlier normal idle is not a stall")
	state.units[2] = _unit("blocker", "frontier_wagon_raider", 3, 3)
	wagon.hp = 1
	plan = rules.preview(state, "blocker", "frontier_wagon_strike", "supply")
	_check(plan.valid, "Raider can destroy the wagon")
	var destroyed := _cue(Cues.build(state, plan.result, plan.events), "supply", "defeat")
	var wreck: Dictionary = plan.result.units[1]
	_check(destroyed.get("clip") == "fall" \
		and Cues.held_clip_for(plan.result, wreck, Cues.presentation_for(plan.result, wreck)) == "wreck",
		"Only the destroyed objective wagon has the wreck pose")


func _validation() -> void:
	_check(Catalog.validate(defs).is_empty(), "All test-authored event/hold/bonus bindings validate")
	for malformed in [{"events": {"arbitrary_event": "paint"}}, {"holds": {"wagon_wreck": "ready"}},
			{"actions": {"move": {"handler": "move", "clip": "walk",
				"bonus": {"stat": "damage", "clip": "bad"}}}}]:
		var copy := defs.duplicate(true)
		copy.characters.bandit_swift.cast_presentation = malformed
		_check(str(Catalog.validate(copy)).contains("cast_presentation"), "Reject invalid metadata: %s" % malformed)
		var owner := _unit("unchecked", "bandit_swift", 2, 2)
		_check(Cues.cast_key_for({"catalog": {"defs": copy}}, owner).is_empty(),
			"Runtime also falls back when catalog validation is bypassed")


func _cue(cues: Array, id: String, role: String) -> Dictionary:
	for cue: Dictionary in cues:
		if cue.get("unit_id") == id and cue.get("ordinary_role") == role:
			return cue
	return {}


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
