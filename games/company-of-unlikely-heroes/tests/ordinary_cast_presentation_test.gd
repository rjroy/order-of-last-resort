extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/ordinary_cast_presentation_test.gd
## No atlas is required: these are rules-to-presentation contract checks.

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Fixtures = preload("res://tests/fixtures/rules_catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")
const Playback = preload("res://presentation/cast_playback.gd")
var failures: Array[String] = []
var rules := Rules.new()


func _initialize() -> void:
	_stock_rounds()
	_second_character()
	_legacy_reaction_exclusivity()
	_ferryman_ordinary_knockdown()
	_validation()
	if failures.is_empty():
		print("PASS: ordinary character cast presentation")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _stock_rounds() -> void:
	var state: Dictionary = Rules.open_mission(Catalog.read_default(), "goblin_mob",
		["knight", "healer", "wizard"])
	var jab_count := 0
	for unit in state.units:
		if unit.character_id == "goblin":
			_check(Cues.cast_key_for(state, unit) == "goblin", "Stock Goblin instance binds ready")
	for round_number in 6:
		if state.outcome != "ongoing":
			break
		var plan: Dictionary = rules.preview_round(state)
		var cues: Array = Cues.build(state, plan.result, plan.events)
		for event: Dictionary in plan.events:
			var action: Dictionary = event.get("resolved_action", {})
			if action.get("ability_id") == "goblin_jab":
				jab_count += 1
				_check(cues.any(func(cue): return cue.get("unit_id") == action.unit_id \
					and cue.get("cast_key") == "goblin" and cue.get("clip") == "jab" \
					and cue.get("source_cell") == action.source_cell \
					and cue.get("target_cell") is Vector2i and not str(cue.get("target_id", "")).is_empty() \
					and cue.get("impact_frame") == 8),
					"Round %d real Goblin jab binds its actor, action-time geometry and contact" % (round_number + 1))
		state = rules.commit_round(state, plan)
	_check(jab_count > 0, "Stock route actually resolves Goblin jabs")


func _second_character() -> void:
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
	defs.characters["fixture_scout"] = defs.characters.goblin.duplicate(true)
	var scout: Dictionary = defs.characters.fixture_scout
	scout["art_key"] = "fixture_scout_art"
	scout["cast_key"] = "fixture_scout"
	scout["cast_art_key"] = "fixture_scout_art"
	scout.cast_presentation = {"actions": {"move": {"handler": "move", "clip": "run"},
		"goblin_jab": {"handler": "attack", "clip": "poke"}}, "hit": "flinch", "defeat": "fall"}
	var state := _fixture(defs, 5)
	var actor: Dictionary = state.units[0]
	_check(Cues.cast_key_for(state, actor) == "fixture_scout", "Second authored actor binds without an actor branch")
	var move: Dictionary = rules.preview(state, "scout_instance", "move", "3,4")
	_check(move.get("valid", false), "Second actor has a real move")
	var move_cues: Array = Cues.build(state, move.result, move.events)
	_check(_has(move_cues, "scout_instance", "run"), "Second actor's real displacement plays its declared clip")
	var jab: Dictionary = rules.preview(state, "scout_instance", "goblin_jab", "healer")
	_check(jab.get("valid", false), "Second actor has a real attack")
	var jab_cues: Array = Cues.build(state, jab.result, jab.events)
	var attack := _cue(jab_cues, "scout_instance", "poke")
	_check(attack.get("target_id") == "healer" and attack.get("target_cell") == Vector2i(4, 3),
		"Second actor's attack aims at its resolved target position")
	_check(attack.get("ordinary_role") == "action", "Ordinary action carries semantic identity")
	_authored_impact(defs)
	var shared_clip := defs.duplicate(true)
	shared_clip.characters.fixture_scout.cast_presentation.actions.goblin_jab.clip = "guard"
	_check(Catalog.validate(shared_clip).is_empty(), "Ordinary attack may use the clip ID guard")
	var shared_state := _fixture(shared_clip, 5)
	var shared_attack: Dictionary = rules.preview(shared_state, "scout_instance", "goblin_jab", "healer")
	_check(shared_attack.get("valid", false), "Ordinary attack using guard clip resolves under real rules")
	if shared_attack.get("valid", false):
		var shared_cue := _cue(Cues.build(shared_state, shared_attack.result, shared_attack.events),
			"scout_instance", "guard")
		_check(shared_cue.get("target_id") == "healer" \
			and shared_cue.get("target_cell") == Vector2i(4, 3),
			"Ordinary attack clip named guard follows attack semantics, not legacy guard shape")
		_check(shared_cue.get("recipients", []).any(func(recipient):
			return recipient.get("id") == "healer" and recipient.get("kind") == "hit"),
			"Ordinary guard-named attack retains its actual hit recipient")
		var clip = Sprites.Clip.new()
		clip.frames.append_array([Rect2(0, 0, 1, 1), Rect2(1, 0, 1, 1)])
		clip.frame_ends.append_array([100.0, 200.0])
		clip.source_frames.append_array([1, 39])
		clip.total_ms = 200.0
		var art := Sprites.new()
		art.set("_actors", {"fixture_scout": {"guard": clip, "gift": clip}})
		var playback := Playback.new()
		playback.enqueue([shared_cue], art)
		var entries: Array = playback.get("_entries")
		_check(entries.size() == 1 and is_equal_approx(entries[0].impact_ms, 96.0),
			"Ordinary guard-named clip does not inherit legacy guard's source-frame timing")
		var gift: Dictionary = shared_cue.duplicate(true)
		gift.clip = "gift"
		playback.clear()
		playback.enqueue([gift], art)
		_check(playback.snapshot().size() == 1,
			"An ordinary action named gift is not discarded as a legacy detached prop")
	var unchanged: Array = move.events.duplicate(true)
	unchanged[0]["position"] = Vector2i(3, 3)
	_check(not _has(Cues.build(state, state, unchanged), "scout_instance", "run"),
		"A move event without displacement does not play movement")
	var damaged: Dictionary = rules.preview(state, "healer", "healer_bonk", "scout_instance")
	_check(damaged.get("valid", false), "Healer's real attack damages the second actor")
	var hit := _cue(Cues.build(state, damaged.result, damaged.events), "scout_instance", "flinch")
	_check(not hit.is_empty(),
		"Hit reaction works even when the recipient has no action")
	_check(hit.get("ordinary_role") == "hit", "Ordinary hit carries semantic identity")
	var dying := _fixture(defs, 1)
	var lethal: Dictionary = rules.preview(dying, "healer", "healer_bonk", "scout_instance")
	var defeat := _cue(Cues.build(dying, lethal.result, lethal.events), "scout_instance", "fall")
	_check(not defeat.is_empty(),
		"Lethal hit plays the declared defeat clip")
	_check(defeat.get("ordinary_role") == "defeat", "Ordinary defeat carries semantic identity")
	var reactions_only := defs.duplicate(true)
	reactions_only.characters.fixture_scout.cast_presentation = {"hit": "flinch", "defeat": "fall"}
	var idle := _fixture(reactions_only, 5)
	_check(Cues.cast_key_for(idle, idle.units[0]) == "fixture_scout",
		"Ready binding does not require any action mapping")
	var idle_hit: Dictionary = rules.preview(idle, "healer", "healer_bonk", "scout_instance")
	_check(_has(Cues.build(idle, idle_hit.result, idle_hit.events), "scout_instance", "flinch"),
		"Reactions work for a character with no declared actions")
	var mismatch := defs.duplicate(true)
	mismatch.characters.fixture_scout.art_variant = "custom_variant"
	var custom := _fixture(mismatch, 5)
	_check(Cues.cast_key_for(custom, custom.units[0]).is_empty(), "Custom art variant falls back")
	mismatch = defs.duplicate(true)
	mismatch.characters.fixture_scout.art_key = "other_art"
	custom = _fixture(mismatch, 5)
	_check(Cues.cast_key_for(custom, custom.units[0]).is_empty(), "Custom art key falls back")
	mismatch = defs.duplicate(true)
	mismatch.characters.fixture_scout.cast_team = "heroes"
	custom = _fixture(mismatch, 5)
	_check(Cues.cast_key_for(custom, custom.units[0]).is_empty(), "Changed team binding falls back")
	mismatch = defs.duplicate(true)
	mismatch.characters.fixture_scout.cast_presentation.actions.goblin_jab.handler = "move"
	custom = _fixture(mismatch, 5)
	var different: Dictionary = rules.preview(custom, "scout_instance", "goblin_jab", "healer")
	_check(not _has(Cues.build(custom, different.result, different.events), "scout_instance", "poke"),
		"Changed expected handler never borrows an attack clip")
	mismatch = defs.duplicate(true)
	mismatch.characters.fixture_scout.cast_presentation = {"actions": []}
	_check(Cues.cast_key_for({"catalog": {"defs": mismatch}}, actor).is_empty(),
		"Malformed presentation falls back even if validation was bypassed")


func _authored_impact(defs: Dictionary) -> void:
	var configured := defs.duplicate(true)
	configured.characters.fixture_scout.cast_presentation.actions.goblin_jab.impact_frame = 8
	configured.characters.healer.cast_presentation = {"hit": "ouch"}
	_check(Catalog.validate(configured).is_empty(), "Optional authored action impact frame validates")
	var state := _fixture(configured, 5)
	var plan: Dictionary = rules.preview(state, "scout_instance", "goblin_jab", "healer")
	_check(plan.get("valid", false), "Authored-impact fixture resolves a real attack")
	if not plan.get("valid", false):
		return
	var cues: Array = Cues.build(state, plan.result, plan.events)
	var action := _cue(cues, "scout_instance", "poke")
	var hit := _cue(cues, "healer", "ouch")
	_check(action.get("impact_frame") == 8, "Committed action carries its declared source-frame impact")
	_check(hit.get("after_cue") == cues.find(action), "Real damage reaction depends on the actual attack")
	var clip = Sprites.Clip.new()
	clip.frames.append_array([Rect2(0, 0, 1, 1), Rect2(1, 0, 1, 1), Rect2(2, 0, 1, 1)])
	clip.frame_ends.append_array([70.0, 130.0, 200.0])
	clip.source_frames.append_array([1, 8, 12])
	clip.total_ms = 200.0
	var art := Sprites.new()
	art.set("_actors", {"fixture_scout": {"poke": clip}, "healer": {"ouch": clip}})
	var playback := Playback.new()
	playback.enqueue(cues, art)
	var entries: Array = playback.get("_entries")
	_check(entries.size() == 2, "Action and victim reaction enter playback")
	if entries.size() == 2:
		_check(is_equal_approx(entries[0].impact_ms, 70.0), "Hit feedback uses source frame 8")
		_check(is_equal_approx(entries[1].elapsed_ms, -70.0), "Victim reaction begins at contact")
	var unsampled: Dictionary = action.duplicate(true)
	unsampled.impact_frame = 7
	playback.clear()
	playback.enqueue([unsampled], art)
	entries = playback.get("_entries")
	_check(entries.size() == 1 and is_equal_approx(entries[0].impact_ms, 96.0),
		"Unsampled source frame safely retains default ordinary timing")


func _fixture(defs: Dictionary, hp: int) -> Dictionary:
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		{"id": "scout_instance", "character_id": "fixture_scout", "position": Vector2i(3, 3),
			"hp": hp, "max_hp": 5, "statuses": {}},
		{"id": "healer", "character_id": "healer", "position": Vector2i(4, 3),
			"hp": 10, "max_hp": 10, "statuses": {}}]
	state.orders = {}
	state.overrides = {}
	return state


func _legacy_reaction_exclusivity() -> void:
	# Explicit character presentation owns this lifecycle, even when it reuses
	# an existing cast family. It must not also enqueue that family's old cues.
	for character in ["harpooner", "ferryman"]:
		for hp in [5, 1]:
			var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
			defs.characters[character]["cast_presentation"] = {
				"hit": "ordinary_hit", "defeat": "ordinary_defeat"}
			var state: Dictionary = rules.new_game(defs, "test_escort")
			state.width = 12
			state.height = 12
			state.default_tile = "stone"
			state.terrain = []
			state.obstacles = []
			var attacker := "healer" if character == "harpooner" else "harpooner"
			var ability := "healer_bonk" if character == "harpooner" else "enemy_harpoon"
			state.units = [
				{"id": "target", "character_id": character, "position": Vector2i(3, 3),
					"hp": hp, "max_hp": 5, "statuses": {}},
				{"id": "attacker", "character_id": attacker, "position": Vector2i(4, 3),
					"hp": 10, "max_hp": 10, "statuses": {}}]
			state.orders = {}
			state.overrides = {}
			var plan: Dictionary = rules.preview(state, "attacker", ability, "target")
			_check(plan.get("valid", false), "%s HP %d: real attack resolves" % [character, hp])
			if not plan.get("valid", false):
				continue
			_check(plan.events.any(func(event): return event.get("type") == "damage" \
				and event.get("target_id") == "target" and event.get("amount", 0) > 0),
				"%s HP %d: actual target takes damage" % [character, hp])
			var reactions: Array = Cues.build(state, plan.result, plan.events).filter(
				func(cue): return cue.get("unit_id") == "target")
			var expected := "ordinary_defeat" if hp == 1 else "ordinary_hit"
			_check(reactions.size() == 1 and reactions[0].get("clip") == expected,
				"%s HP %d: configured lifecycle is exclusive, got %s" % [character, hp, reactions])


func _ferryman_ordinary_knockdown() -> void:
	var defs: Dictionary = Fixtures.add_fixed_escort(Catalog.read_default())
	defs.characters.ferryman.cast_presentation = {"hit": "ordinary_hit", "defeat": "ordinary_defeat"}
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		{"id": "attacker", "character_id": "wizard", "position": Vector2i(3, 3),
			"hp": 10, "max_hp": 10, "statuses": {}},
		{"id": "civilian", "character_id": "ferryman", "position": Vector2i(4, 3),
			"hp": 10, "max_hp": 10, "statuses": {}}]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	var plan: Dictionary = rules.preview(state, "attacker", "wizard_blast")
	_check(plan.get("valid", false), "Ordinary Ferryman knockdown uses a real Wizard Blast")
	if not plan.get("valid", false):
		return
	_check(plan.events.any(func(event): return event.get("type") == "damage" \
		and event.get("target_id") == "civilian" and event.get("status_id") == "knockdown"),
		"Wizard Blast actually knocks the living Ferryman down")
	var reactions: Array = Cues.build(state, plan.result, plan.events).filter(
		func(cue): return cue.get("unit_id") == "civilian")
	_check(reactions.size() == 1 and reactions[0].get("clip") == "ordinary_hit",
		"Ordinary lifecycle excludes legacy down on knockdown: %s" % [reactions])
	if reactions.size() == 1:
		_check(not reactions[0].get("was_prone", true),
			"Real hit that causes knockdown records the pre-hit upright posture")
	var already_down: Dictionary = plan.result.duplicate(true)
	already_down.units.append({"id": "raider", "character_id": "harpooner", "position": Vector2i(5, 3),
		"hp": 10, "max_hp": 10, "statuses": {}})
	var repeat_hit: Dictionary = rules.preview(already_down, "raider", "enemy_harpoon", "civilian")
	_check(repeat_hit.get("valid", false), "Real Harpoon attack can hit the already-prone Ferryman")
	if repeat_hit.get("valid", false):
		var followup := _cue(Cues.build(already_down, repeat_hit.result, repeat_hit.events),
			"civilian", "ordinary_hit")
		_check(followup.get("was_prone", false),
			"Hit on an already-prone actor retains the pre-hit prone posture")
	var recovery: Dictionary = rules.preview_round(plan.result)
	_check(recovery.get("valid", false) and recovery.events.any(func(event):
		return event.get("type") == "recover" and event.get("unit_id") == "civilian"),
		"Following round actually recovers the Ferryman")
	_check(not Cues.build(plan.result, recovery.result, recovery.events).any(func(cue):
		return cue.get("unit_id") == "civilian" and cue.get("clip") == "recover"),
		"Ordinary lifecycle does not leak legacy recover")


func _validation() -> void:
	var defs: Dictionary = Catalog.read_default()
	_check(Catalog.validate(defs).is_empty(), "Stock presentation validates")
	for invalid in [{"actions": []}, {"hit": 7}, {"unexpected": true},
			{"actions": {"move": {"handler": "teleport", "clip": "run"}}},
			{"actions": {"move": {"handler": "move", "clip": "ready"}}},
			{"actions": {"move": {"handler": "move", "clip": "run", "impact_frame": 0}}},
			{"actions": {"move": {"handler": "move", "clip": "run", "impact_frame": 1.5}}}]:
		var candidate := defs.duplicate(true)
		candidate.characters.goblin.cast_presentation = invalid
		_check(str(Catalog.validate(candidate)).contains("cast_presentation"),
			"Malformed optional presentation is rejected: %s" % invalid)
	var no_mobile := defs.duplicate(true)
	no_mobile.characters.goblin.capabilities = ["damageable"]
	_check(str(Catalog.validate(no_mobile)).contains("requires the mobile capability"),
		"Movement presentation requires mobility")
	var no_damage := defs.duplicate(true)
	no_damage.characters.goblin.capabilities = ["mobile"]
	_check(str(Catalog.validate(no_damage)).contains("requires the damageable capability"),
		"Reaction presentation requires damageability")


func _cue(cues: Array, id: String, clip: String) -> Dictionary:
	for cue: Dictionary in cues:
		if cue.get("unit_id") == id and cue.get("clip") == clip:
			return cue
	return {}


func _has(cues: Array, id: String, clip: String) -> bool:
	return not _cue(cues, id, clip).is_empty()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
