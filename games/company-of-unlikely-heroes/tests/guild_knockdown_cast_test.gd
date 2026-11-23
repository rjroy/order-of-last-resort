extends SceneTree
## Run with a graphical display:
## godot --path games/company-of-unlikely-heroes --script res://tests/guild_knockdown_cast_test.gd
## Uses real rule-produced damage, lost-turn recovery and authored cast playback.

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Statuses = preload("res://rules/statuses.gd")
const Board = preload("res://bridge_art.gd")
const CELL := Vector2i.ZERO
const CELLS := {CELL: "stone"}
const HEROES := ["knight", "healer", "wizard", "bard", "rogue", "necromancer", "alchemist"]

var rules := Rules.new()
var board := Board.new()
var view := SubViewport.new()
var failures: Array[String] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Guild knockdown cast test requires a graphical renderer.")
		board.free()
		view.free()
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	view.size = Vector2i(Board.TILE + Board.GUTTER * 2.0)
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	board.size = Vector2(view.size)
	view.add_child(board)
	var container := SubViewportContainer.new()
	container.add_child(view)
	root.add_child(container)
	for hero in HEROES:
		await _knockdown_recovery(hero, false)
	await _knockdown_recovery("knight", true)
	for hero in ["wizard", "alchemist"]:
		for facing in [-1, 1]:
			await _pull_recovery(hero, facing)
	for hero in ["rogue", "alchemist"]:
		_jelly_after_action(hero)
	_laughter_excluded()
	_custom_hero_excluded()
	await _custom_alchemist_recoil_cleanup()
	for message in failures:
		push_error("FAIL: " + message)
	if failures.is_empty():
		print("PASS: guild knockdown and recovery presentations")
	quit(0 if failures.is_empty() else 1)


func _fixture(hero: String, attack := "wizard") -> Dictionary:
	var defs: Dictionary = load("res://tests/fixtures/rules_catalog.gd").add_fixed_escort(Catalog.read_default())
	if hero == "alchemist":
		defs.classes.alchemist.abilities.append("wizard_pull")
	if hero == "rogue":
		defs.characters.rogue.abilities.append("alchemist_potion")
	defs.characters["custom_knight"] = defs.characters.knight.duplicate(true)
	defs.characters["custom_alchemist"] = defs.characters.alchemist.duplicate(true)
	defs.characters["attacking_fixture"] = defs.characters[attack].duplicate(true)
	defs.characters.attacking_fixture["team"] = "enemies"
	defs.characters.attacking_fixture["behavior"] = "hold"
	if attack == "bard":
		# Stock song targets the enemy faction; the hostile fixture targets heroes.
		defs.abilities.inspiring_melody.targeting.teams = ["heroes"]
	var state: Dictionary = rules.new_game(defs, "test_escort")
	state.width = 12
	state.height = 12
	state.default_tile = "stone"
	state.terrain = []
	state.obstacles = []
	state.units = [
		{"id": "attacker", "character_id": "attacking_fixture", "position": Vector2i(2, 3),
			"hp": 20, "max_hp": 20, "statuses": {}},
		{"id": "victim", "character_id": hero, "position": Vector2i(3, 3),
			"hp": 20, "max_hp": 20, "statuses": {}},
		{"id": "civilian", "character_id": "ferryman", "position": Vector2i(10, 10),
			"hp": 20, "max_hp": 20, "statuses": {}}]
	state.orders = {}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	return state


func _knockdown_recovery(hero: String, shield_away: bool) -> void:
	var label := hero + (" shield away" if shield_away else "")
	var before := _fixture(hero)
	if shield_away:
		_entity(before, "victim")["shield_position"] = Vector2i(9, 9)
	var hit: Dictionary = rules.preview(before, "attacker", "wizard_blast")
	if not hit.get("valid", false):
		_check(false, label + ": real nonlethal Blast resolves")
		return
	var down: Dictionary = rules.apply_plan(before, hit)
	_check(_entity(down, "victim").hp > 0 and rules.knocked_down(down, "victim") \
		and hit.events.any(func(event): return event.get("type") == "damage" \
			and event.get("target_id") == "victim" and event.get("status_id") == "knockdown"),
		label + ": committed Blast knocks down a living hero")
	var repeat: Dictionary = rules.preview(down, "attacker", "wizard_blast")
	if repeat.get("valid", false):
		var repeated: Dictionary = rules.apply_plan(down, repeat)
		_check(not Cues.build(down, repeated, repeat.events).any(func(cue): return \
			cue.get("unit_id") == "victim" and cue.get("hero_knockdown") == "down"),
			label + ": a later hit while already down does not replay the fall")
	else:
		_check(false, label + ": already-down hit control resolves")
	var lethal := before.duplicate(true)
	_entity(lethal, "victim").hp = 1
	var fatal: Dictionary = rules.preview(lethal, "attacker", "wizard_blast")
	if fatal.get("valid", false):
		var fallen: Dictionary = rules.apply_plan(lethal, fatal)
		_check(_entity(fallen, "victim").hp == 0 \
			and not Cues.build(lethal, fallen, fatal.events).any(func(cue): return \
				cue.get("unit_id") == "victim" and cue.has("hero_knockdown")),
			label + ": lethal hits do not use the living knockdown lifecycle")
	else:
		_check(false, label + ": lethal-hit control resolves")
	var recovery: Dictionary = rules.preview_round(down)
	_check(recovery.get("valid", false) and not rules.knocked_down(recovery.result, "victim") \
		and recovery.events.any(func(event): return event.get("type") == "recover" \
			and event.get("unit_id") == "victim" and "knockdown" in event.get("status_ids", [])),
		label + ": real lost turn consumes the knockdown")
	if not recovery.get("valid", false):
		return
	var recovered: Dictionary = rules.commit_round(down, recovery)
	_check(recovered == recovery.result, label + ": recovery commits its forecast")
	var fall := _cue(Cues.build(before, down, hit.events), hero, "down", label)
	var rise := _cue(Cues.build(down, recovered, recovery.events), hero, "recover", label)
	_check_same_round_order(down, recovered, recovery.events, hero, label)
	if fall.is_empty() or rise.is_empty():
		return
	await _render_lifecycle(hero, shield_away, fall, rise, label)
	if shield_away:
		await _shield_variant(fall, "down_unshielded", true)
		await _shield_variant(rise, "recover_unshielded", false)


func _check_same_round_order(down: Dictionary, recovered: Dictionary, recovery_events: Array,
		hero: String, label: String) -> void:
	var next_hit: Dictionary = rules.preview(recovered, "attacker", "wizard_blast")
	if not next_hit.get("valid", false):
		_check(false, label + ": later Blast fixture resolves")
		return
	var again: Dictionary = rules.apply_plan(recovered, next_hit)
	var recovered_events: Array = recovery_events.filter(func(event): return event.get("type") == "recover" \
		and event.get("unit_id") == "victim")
	var cues: Array = Cues.build(down, again, recovered_events + next_hit.events)
	var own := cues.filter(func(cue): return cue.get("unit_id") == "victim" and cue.get("cast_key") == hero \
		and cue.get("clip") in ["down", "recover"])
	_check(rules.knocked_down(again, "victim") and own.size() == 2 \
		and own[0].get("clip") == "recover" and own[1].get("clip") == "down",
		label + ": recovery then a new knockdown produces exactly one ordered rise and fall")


func _render_lifecycle(hero: String, shield_away: bool, fall: Dictionary, rise: Dictionary, label: String) -> void:
	board.clear_action_playback()
	var unit := {"id": "victim", "art_key": hero, "cast_key": hero, "cell": CELL,
		"facing": 1, "hp": 10, "max_hp": 10, "prone": true, "shield_away": shield_away,
		"guild_knockdown_art": true}
	board.set_render_state(CELLS, [unit])
	board.play_committed_actions([fall])
	board.set_process(false)
	var entries: Array = board.get("_playback").active()
	if entries.size() != 1:
		_check(false, label + ": fall plays its packaged actor-owned clip")
		return
	var entry = entries[0]
	var variant := "down_unshielded" if shield_away else "down"
	_check(board.get("_cast").clip_for(hero, variant) != null,
		label + ": equipment-appropriate " + variant + " clip is packaged")
	board._process((entry.clip.total_ms - 1.0) / 1000.0)
	board.set_process(false)
	var last := await _capture()
	board._process((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
	board.set_process(false)
	var held := await _capture()
	_check(_difference(last, held) == 0, label + ": final fall frame is held while knocked down")
	unit.prone = false
	board.set_render_state(CELLS, [unit])
	board.play_committed_actions([rise])
	board.set_process(false)
	entries = board.get("_playback").active()
	if entries.size() != 1:
		_check(false, label + ": recovery plays its packaged actor-owned clip")
		return
	entry = entries[0]
	var recover_variant := "recover_unshielded" if shield_away else "recover"
	_check(board.get("_cast").clip_for(hero, recover_variant) != null,
		label + ": equipment-appropriate " + recover_variant + " clip is packaged")
	var first := await _capture()
	_check(_figure_difference(held, first) == 0, label + ": recovery starts at the held fall pose")
	board._process((entry.duration_ms + 1.0) / 1000.0)
	board.set_process(false)
	var ready := await _capture()
	board.clear_action_playback()
	board.set_process(false)
	var ready_without_cue := await _capture()
	_check(_difference(ready, ready_without_cue) == 0 and board.action_playback_snapshot().is_empty(),
		label + ": completed recovery returns to the appropriate ready or shield-away hold")


func _pull_recovery(hero: String, facing: int) -> void:
	var state := _fixture(hero)
	var victim := _entity(state, "victim")
	victim.position = Vector2i(3, 3)
	_entity(state, "attacker").position = Vector2i(3 + 3 * facing, 3)
	var plan: Dictionary = rules.preview(state, "victim", "wizard_pull", "attacker")
	if not plan.get("valid", false):
		_check(false, hero + ": own Pull fixture resolves")
		return
	var down: Dictionary = rules.apply_plan(state, plan)
	_check(rules.knocked_down(down, "victim"), hero + ": own Pull really causes recoil knockdown")
	var cues: Array = Cues.build(state, down, plan.events)
	var own := cues.filter(func(cue): return cue.get("unit_id") == "victim" and cue.get("cast_key") == hero)
	_check(own.size() == 1 and own[0].get("clip") == "pull",
		hero + ": authored Pull fall is not followed by a duplicate ordinary down")
	var recovery: Dictionary = rules.preview_round(down)
	if not recovery.get("valid", false):
		_check(false, hero + ": Pull recoil recovery resolves")
		return
	var recovered: Dictionary = rules.commit_round(down, recovery)
	_check(recovered == recovery.result, hero + ": own Pull recovery commits")
	var rise := _cue(Cues.build(down, recovered, recovery.events), hero, "seated_recover", hero + " own Pull")
	var saved := down.duplicate(true)
	_entity(saved, "victim").statuses.knockdown["presentation_facing"] = float(facing)
	var saved_recovery: Dictionary = rules.preview_round(saved)
	if saved_recovery.get("valid", false):
		var saved_after: Dictionary = rules.commit_round(saved, saved_recovery)
		var saved_rise := _cue(Cues.build(saved, saved_after, saved_recovery.events),
			hero, "seated_recover", hero + " numeric save")
		_check(saved_rise.get("facing") == facing,
			hero + ": numeric save metadata preserves facing")
	else:
		_check(false, hero + ": numeric save recovery resolves")
	for cause in ["absent", "replaced"]:
		var changed := down.duplicate(true)
		var status: Dictionary = _entity(changed, "victim").statuses.get("knockdown", {})
		if status.is_empty():
			_check(false, hero + ": Pull supplies a knockdown status")
			continue
		if cause == "absent":
			status.erase("presentation_cause")
		else:
			status.presentation_cause = "another_cause"
		var fallback: Dictionary = rules.preview_round(changed)
		if not fallback.get("valid", false):
			_check(false, hero + ": " + cause + " cause recovery resolves")
			continue
		var fallback_after: Dictionary = rules.commit_round(changed, fallback)
		var fallback_cues: Array = Cues.build(changed, fallback_after, fallback.events)
		_cue(fallback_cues, hero, "recover", hero + " " + cause + " cause")
		_check(not fallback_cues.any(func(cue): return cue.get("unit_id") == "victim" \
			and cue.get("clip") == "seated_recover"),
			hero + ": " + cause + " provenance does not invent a seated recovery")
	if own.size() == 1 and own[0].get("clip") == "pull" and not rise.is_empty():
		for queued in [false, true]:
			for legacy in [false, true]:
				var recovery_cue := rise.duplicate(true)
				if legacy:
					recovery_cue.erase("facing")
				await _render_pull_recovery(hero, own[0], recovery_cue, facing, queued, legacy)
		await _recovery_before_queued_pull(hero, own[0], rise, facing)
		await _intervening_blast(hero, facing, down, own[0])


func _recovery_before_queued_pull(hero: String, pull: Dictionary, rise: Dictionary, facing: int) -> void:
	board.clear_action_playback()
	var unit := {"id": "victim", "art_key": hero, "cast_key": hero, "cell": CELL,
		"facing": 1, "hp": 10, "max_hp": 10, "prone": true, "guild_knockdown_art": true}
	board.set_render_state(CELLS, [unit])
	var blocker := {"unit_id": "victim", "cast_key": hero, "clip": "blast" if hero == "wizard" else "potion",
		"source_cell": CELL}
	board.play_committed_actions([blocker, pull])
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.size() != 1 or active[0].cue.clip != blocker.clip:
		_check(false, hero + ": earlier action holds Pull in the queue")
		return
	_check(not board.get("_pull_facing").has("victim"), hero + ": queued Pull has not established a held pose")
	var blocker_ms: float = active[0].duration_ms
	unit.prone = false
	board.set_render_state(CELLS, [unit])
	var legacy := rise.duplicate(true)
	legacy.erase("facing")
	board.play_committed_actions([legacy])
	board.set_process(false)
	board._process(blocker_ms / 1000.0)
	board.set_process(false)
	active = board.get("_playback").active()
	if active.size() != 1 or active[0].cue.clip != "pull":
		_check(false, hero + ": earlier action finishes before queued Pull")
		return
	var pull_entry = active[0]
	board._process((pull_entry.clip.total_ms - 1.0) / 1000.0)
	board.set_process(false)
	var last := await _capture()
	board._process((pull_entry.duration_ms - pull_entry.elapsed_ms) / 1000.0)
	board.set_process(false)
	active = board.get("_playback").active()
	if active.size() != 1 or active[0].cue.clip != "seated_recover":
		_check(false, hero + ": queued Pull is followed by seated recovery")
		return
	var first := await _capture()
	_check(active[0].facing == float(facing) and _figure_difference(last, first) == 0,
		"%s: recovery after a not-yet-active Pull preserves facing %d" % [hero, facing])
	board._process((active[0].duration_ms + 1.0) / 1000.0)
	board.set_process(false)
	unit.prone = true
	board.set_render_state(CELLS, [unit])
	board.set_process(false)
	_check(_figure_difference(await _capture(), last) > 30,
		hero + ": queued-Pull orientation does not leak into a later ordinary fall")


func _intervening_blast(hero: String, facing: int, down: Dictionary, pull: Dictionary) -> void:
	down = down.duplicate(true)
	_entity(down, "victim").statuses.knockdown["presentation_facing"] = float(facing)
	var hit: Dictionary = rules.preview(down, "attacker", "wizard_blast")
	if not hit.get("valid", false):
		_check(false, hero + ": Blast against the seated Pull victim resolves")
		return
	var hit_after: Dictionary = rules.apply_plan(down, hit)
	var actor := _entity(hit_after, "victim")
	_check(rules.knocked_down(hit_after, "victim") and actor.hp < _entity(down, "victim").hp \
		and actor.statuses.get("knockdown", {}).get("source_id") == "attacker" \
		and hit.events.any(func(event): return event.get("type") == "damage" \
			and event.get("target_id") == "victim" and event.get("status_id") == "knockdown"),
		hero + ": intervening Blast really replaces the already-down status without recovery")
	_check(not Cues.build(down, hit_after, hit.events).any(func(cue): return cue.get("unit_id") == "victim" \
		and cue.get("clip") == "down"), hero + ": no second fall plays while already seated")
	var recovery: Dictionary = rules.preview_round(hit_after)
	if not recovery.get("valid", false):
		_check(false, hero + ": recovery after repeated hit resolves")
		return
	var recovered: Dictionary = rules.commit_round(hit_after, recovery)
	var recovery_cues: Array = Cues.build(hit_after, recovered, recovery.events)
	var rise := _cue(recovery_cues, hero, "seated_recover", hero + " intervening Blast")
	if not rise.is_empty():
		await _render_pull_recovery(hero, pull, rise, facing, false, false)
	var next_hit: Dictionary = rules.preview(recovered, "attacker", "wizard_blast")
	if not next_hit.get("valid", false):
		_check(false, hero + ": later Blast after real recovery resolves")
		return
	var knocked_again: Dictionary = rules.apply_plan(recovered, next_hit)
	var recovery_events: Array = recovery.events.filter(func(event): return event.get("type") == "recover" \
		and event.get("unit_id") == "victim")
	var ordered: Array = Cues.build(hit_after, knocked_again, recovery_events + next_hit.events).filter(
		func(cue): return cue.get("unit_id") == "victim" and cue.get("cast_key") == hero \
			and cue.get("clip") in ["seated_recover", "recover", "down"])
	_check(ordered.size() == 2 and ordered[0].get("clip") == "seated_recover" \
		and ordered[1].get("clip") == "down", hero + ": genuine recovery then new fall keeps chronological poses")
	if ordered.size() == 2 and ordered[0].get("clip") == "seated_recover" and ordered[1].get("clip") == "down":
		await _render_recovery_then_new_fall(hero, facing, pull, recovery_cues, ordered[1])


func _render_recovery_then_new_fall(hero: String, facing: int, pull: Dictionary,
		recovery_cues: Array, fall: Dictionary) -> void:
	board.clear_action_playback()
	var unit := {"id": "victim", "art_key": hero, "cast_key": hero, "cell": CELL,
		"facing": 1, "hp": 10, "max_hp": 10, "prone": true, "guild_knockdown_art": true}
	board.set_render_state(CELLS, [unit])
	board.set_process(false)
	var ordinary_down := await _capture()
	board.play_committed_actions([pull] + recovery_cues + [fall])
	board.set_process(false)
	var active: Array = board.get("_playback").active().filter(func(entry): return \
		entry.cue.get("unit_id") == "victim")
	if active.size() != 1 or active[0].cue.get("clip") != "pull":
		_check(false, hero + ": same-batch sequence begins with the actual Pull")
		return
	board._process(active[0].duration_ms / 1000.0)
	board.set_process(false)
	active = board.get("_playback").active().filter(func(entry): return entry.cue.get("unit_id") == "victim")
	if active.size() != 1 or active[0].cue.get("clip") != "seated_recover":
		_check(false, hero + ": same-batch sequence next plays seated recovery")
		return
	_check(active[0].facing == float(facing), hero + ": same-batch seated recovery preserves Pull facing")
	board._process(active[0].duration_ms / 1000.0)
	board.set_process(false)
	active = board.get("_playback").active().filter(func(entry): return entry.cue.get("unit_id") == "victim")
	if active.size() != 1 or active[0].cue.get("clip") != "down":
		_check(false, hero + ": same-batch sequence next plays the later fall")
		return
	board._process((active[0].duration_ms + 1.0) / 1000.0)
	board.set_process(false)
	var final := await _capture()
	_check(not board.action_playback_snapshot().any(func(cue): return cue.get("unit_id") == "victim") \
		and _difference(final, ordinary_down) == 0,
		hero + ": same-batch recovery and new fall end at ordinary down, not stale seating")


func _shield_variant(canonical: Dictionary, variant: String, prone: bool) -> void:
	board.clear_action_playback()
	var unit := {"id": "victim", "art_key": "knight", "cast_key": "knight", "cell": CELL,
		"facing": 1, "hp": 10, "max_hp": 10, "prone": prone, "shield_away": true,
		"guild_knockdown_art": true}
	board.set_render_state(CELLS, [unit])
	board.play_committed_actions([canonical])
	board.set_process(false)
	var entries: Array = board.get("_playback").active()
	if entries.size() != 1 or board.get("_cast").clip_for("knight", variant) == null:
		_check(false, "Knight shield-away " + variant + " is playable")
		return
	var sample_ms: float = entries[0].clip.total_ms * 0.5
	board._process(sample_ms / 1000.0)
	board.set_process(false)
	var actual := await _capture()
	board.clear_action_playback()
	unit.shield_away = false
	unit.prone = false
	board.set_render_state(CELLS, [unit])
	var reference := canonical.duplicate(true)
	reference.clip = variant
	reference.shield_away = false
	board.play_committed_actions([reference])
	board.set_process(false)
	board._process(sample_ms / 1000.0)
	board.set_process(false)
	var expected := await _capture()
	_check(_figure_difference(actual, expected) == 0,
		"Knight shield-away state renders the authored " + variant + " gesture")


func _render_pull_recovery(hero: String, pull: Dictionary, rise: Dictionary, facing: int,
		queued: bool, legacy: bool) -> void:
	board.clear_action_playback()
	var label := "%s own Pull facing %d (%s, %s)" % [hero, facing,
		"queued" if queued else "held", "legacy" if legacy else "tagged"]
	var unit := {"id": "victim", "art_key": hero, "cast_key": hero, "cell": CELL,
		"facing": 1, "hp": 10, "max_hp": 10, "prone": true, "guild_knockdown_art": true}
	board.set_render_state(CELLS, [unit])
	board.play_committed_actions([pull])
	board.set_process(false)
	var entries: Array = board.get("_playback").active()
	if entries.size() != 1:
		_check(false, hero + ": own Pull plays")
		return
	var entry = entries[0]
	_check(entry.facing == float(facing), label + ": actual resolved Pull faces its target")
	board._process((entry.clip.total_ms - 1.0) / 1000.0)
	board.set_process(false)
	var last := await _capture()
	if queued:
		unit.prone = false
		board.set_render_state(CELLS, [unit])
		board.play_committed_actions([rise])
		board.set_process(false)
		board._process((entry.duration_ms - entry.elapsed_ms) / 1000.0)
		board.set_process(false)
	else:
		board._process((entry.duration_ms - entry.elapsed_ms + 1.0) / 1000.0)
		board.set_process(false)
		var held := await _capture()
		_check(_difference(last, held) == 0, label + ": own Pull holds its authored seated tail")
		unit.prone = false
		board.set_render_state(CELLS, [unit])
		board.play_committed_actions([rise])
	board.set_process(false)
	entries = board.get("_playback").active()
	if entries.size() != 1:
		_check(false, hero + ": own seated recovery plays")
		return
	entry = entries[0]
	var first := await _capture()
	_check(entry.facing == float(facing) and _figure_difference(last, first) == 0,
		label + ": seated recovery begins at the same oriented Pull tail")
	board._process((entry.duration_ms + 1.0) / 1000.0)
	board.set_process(false)
	var ready := await _capture()
	board.clear_action_playback()
	board.set_process(false)
	_check(_difference(ready, await _capture()) == 0,
		label + ": seated recovery finishes at ready")
	unit.prone = true
	board.set_render_state(CELLS, [unit])
	board.set_process(false)
	var later_down := await _capture()
	_check(_figure_difference(later_down, last) > 30,
		label + ": a later unrelated knockdown does not reuse stale Pull seating")


func _jelly_after_action(hero: String) -> void:
	var before := _fixture(hero)
	_entity(before, "victim").hp = 10
	_entity(before, "victim")["dose_rng_state"] = 25
	var plan: Dictionary = rules.preview(before, "victim", "alchemist_potion", "victim")
	if not plan.get("valid", false):
		_check(false, hero + ": self-potion fixture resolves")
		return
	var down: Dictionary = rules.apply_plan(before, plan)
	_check(rules.knocked_down(down, "victim") and plan.events.any(func(event): return \
		event.get("type") == "alchemy_reaction" and event.get("reaction_id") == "jelly_knees" \
			and event.get("applied", false)),
		hero + ": the self-potion actually causes Jelly Knees")
	var own := Cues.build(before, down, plan.events).filter(func(cue): return \
		cue.get("unit_id") == "victim" and cue.get("cast_key") == hero \
			and cue.get("clip") in ["potion", "down"])
	_check(own.size() == 2 and own[0].get("clip") == "potion" and own[1].get("clip") == "down",
		hero + ": own dose queues before exactly one ordinary fall")


func _custom_hero_excluded() -> void:
	var before := _fixture("knight")
	_entity(before, "victim").character_id = "custom_knight"
	var plan: Dictionary = rules.preview(before, "attacker", "wizard_blast")
	if not plan.get("valid", false):
		_check(false, "Custom hero identity fixture resolves")
		return
	var down: Dictionary = rules.apply_plan(before, plan)
	_check(rules.knocked_down(down, "victim") and Cues.guild_hero_key(down, _entity(down, "victim")).is_empty() \
		and not Cues.build(before, down, plan.events).any(func(cue): return \
			cue.get("unit_id") == "victim" and cue.get("hero_knockdown") == "down"),
		"A custom character sharing stock metadata is not assigned the stock hero lifecycle")


func _custom_alchemist_recoil_cleanup() -> void:
	var before := _fixture("alchemist")
	_entity(before, "victim").character_id = "custom_alchemist"
	_entity(before, "attacker").position = Vector2i(6, 3)
	var pull_plan: Dictionary = rules.preview(before, "victim", "wizard_pull", "attacker")
	if not pull_plan.get("valid", false):
		_check(false, "Custom alchemist Pull resolves")
		return
	var down: Dictionary = rules.apply_plan(before, pull_plan)
	var pull := _cue(Cues.build(before, down, pull_plan.events), "alchemist", "pull", "Custom alchemist")
	var recovery: Dictionary = rules.preview_round(down)
	if pull.is_empty() or not recovery.get("valid", false):
		_check(false, "Custom alchemist Pull recovery resolves")
		return
	var recovered: Dictionary = rules.commit_round(down, recovery)
	var hit: Dictionary = rules.preview(recovered, "attacker", "wizard_blast")
	if not hit.get("valid", false):
		_check(false, "Custom alchemist later Blast resolves")
		return
	var again: Dictionary = rules.apply_plan(recovered, hit)
	var recovery_events: Array = recovery.events.filter(func(event): return \
		event.get("type") == "recover" and event.get("unit_id") == "victim")
	var batch: Array = Cues.build(down, again, recovery_events + hit.events)
	_check(rules.knocked_down(down, "victim") and not rules.knocked_down(recovered, "victim") \
		and rules.knocked_down(again, "victim") and recovery_events.size() == 1 \
		and pull.get("pull_recoil_down", false),
		"Custom alchemist actually recoils, recovers, then suffers a new knockdown")
	_check(Cues.guild_hero_key(again, _entity(again, "victim")).is_empty() \
		and not batch.any(func(cue): return cue.get("unit_id") == "victim" \
			and cue.has("hero_knockdown")),
		"Custom alchemist remains excluded from stock guild knockdown art")
	_check(batch.any(func(cue): return cue.get("unit_id") == "victim" \
		and cue.get("control") == "clear_pull_recoil"),
		"Custom alchemist recovery clears legacy recoil provenance")

	board.clear_action_playback()
	var unit := {"id": "victim", "art_key": "alchemist", "cast_key": "alchemist", "cell": CELL,
		"facing": 1, "hp": 10, "max_hp": 10, "prone": true}
	board.set_render_state(CELLS, [unit])
	board.set_process(false)
	var ordinary_down := await _capture()
	board.play_committed_actions([pull])
	board.set_process(false)
	var active: Array = board.get("_playback").active()
	if active.size() != 1:
		_check(false, "Custom alchemist real Pull plays")
		return
	board._process((active[0].duration_ms + 1.0) / 1000.0)
	board.set_process(false)
	var seated := await _capture()
	_check(_difference(ordinary_down, seated) > 30, "Custom alchemist Pull has a distinct seated hold")
	board.clear_action_playback()
	board.play_committed_actions([{"unit_id": "victim", "cast_key": "alchemist",
		"clip": "potion", "source_cell": CELL}, pull])
	board.set_process(false)
	active = board.get("_playback").active()
	if active.size() != 1:
		_check(false, "Prior action queues custom alchemist Pull")
		return
	var blocking_ms: float = active[0].duration_ms
	board.play_committed_actions(batch)
	board.set_process(false)
	var queued := board.action_playback_snapshot().filter(func(cue): return \
		cue.get("unit_id") == "victim" and cue.get("clip") == "pull")
	_check(queued.size() == 1 and not queued[0].get("pull_recoil_down", false),
		"Custom recovery invalidates the pending old Pull without removing it")
	board._process((blocking_ms + 1.0) / 1000.0)
	board.set_process(false)
	active = board.get("_playback").active()
	if active.size() != 1 or active[0].cue.get("clip") != "pull":
		_check(false, "Custom alchemist old Pull still plays")
		return
	board._process((active[0].duration_ms + 1.0) / 1000.0)
	board.set_process(false)
	var final := await _capture()
	_check(_difference(final, ordinary_down) == 0 and _difference(final, seated) > 30,
		"Custom alchemist later unrelated knockdown holds ordinary down, not stale seating")


func _laughter_excluded() -> void:
	var state := _fixture("knight", "bard")
	var plan: Dictionary = {}
	for seed_value in range(1, 1000):
		state.rng_state = seed_value
		var candidate: Dictionary = rules.preview(state, "attacker", "inspiring_melody")
		if candidate.get("valid", false) and candidate.events.any(func(event): return \
				event.get("type") == "performance" and event.get("target_id") == "victim" \
				and event.has("status_id")):
			plan = candidate
			break
	if not plan.get("valid", false):
		_check(false, "Laughter control resolves")
		return
	var after: Dictionary = rules.apply_plan(state, plan)
	_check(plan.events.any(func(event): return event.get("type") == "performance" \
		and event.get("target_id") == "victim" and event.has("status_id")) \
		and Cues.guild_hero_key(after, _entity(after, "victim")) == "knight" \
		and Statuses.has_skip(after, _entity(after, "victim")) and not rules.knocked_down(after, "victim") \
		and not Cues.build(state, after, plan.events).any(
		func(cue): return cue.get("unit_id") == "victim" and cue.get("clip") in ["down", "recover"]),
		"Laughter does not produce knockdown presentation")
	var recovery: Dictionary = rules.preview_round(after)
	_check(not Cues.build(after, recovery.result, recovery.events).any(
		func(cue): return cue.get("unit_id") == "victim" and cue.get("clip") in ["down", "recover"]),
		"Laughter's lost turn does not produce a knockdown recovery")


func _cue(cues: Array, hero: String, clip: String, label: String) -> Dictionary:
	var matches := cues.filter(func(cue): return cue.get("unit_id") == "victim" \
		and cue.get("cast_key") == hero and cue.get("clip") == clip)
	_check(matches.size() == 1, label + ": exactly one " + hero + "." + clip + " cue")
	return matches[0] if matches.size() == 1 else {}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit in state.units:
		if unit.id == id:
			return unit
	return {}


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _figure_difference(a: Image, b: Image) -> int:
	var scale: float = board.get("_map_scale")
	var tile: Vector2 = board.get("_map_origin") + board.call("_tile_origin", CELL) * scale
	var caption := Rect2i(Vector2i(tile + Vector2(42, 0) * scale), Vector2i(52 * scale + 2, 25 * scale + 2))
	var first := a.duplicate()
	var second := b.duplicate()
	first.fill_rect(caption, Color.BLACK)
	second.fill_rect(caption, Color.BLACK)
	return _difference(first, second)


func _difference(a: Image, b: Image) -> int:
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				changed += 1
	return changed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
