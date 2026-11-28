extends SceneTree
## Controlled presentation contract. No stock catalog or packaged atlas required.
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/road_cast_cues_test.gd

const Fixtures = preload("res://tests/fixtures/rules_catalog.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const Sprites = preload("res://presentation/cast/cast_sprites.gd")
const Playback = preload("res://presentation/cast/cast_playback.gd")

var defs: Dictionary = Fixtures.definitions()
var failures: Array[String] = []


func _initialize() -> void:
	_bind("lender", {"events": {"borrowed_armor": "lend_armor"}})
	_bind("friar", {"events": {"death_heal": "last_heal", "tactical_retreat": "retreat"},
		"defeat": "defeat"})
	_bind("bruiser", {"events": {"windup_strike": "delayed_heavy_strike"}})
	_bind("risen", {"events": {"corpse_bell_raised": "bell_rise"}})
	_bind("giant", {"actions": {"fixture_sweep": {"handler": "sweep", "clip": "sweep"}}})
	_bind("twin", {"events": {"health_damage_bonus": "resolve"},
		"actions": {"fixture_strike": {"handler": "attack", "clip": "close_strike"}},
		"defeat": "defeat"})
	defs.abilities["fixture_sweep"] = {"handler": "sweep"}
	defs.abilities["fixture_strike"] = {"handler": "attack"}
	_armor()
	_last_heal()
	_windup()
	_bell()
	_sweep()
	_twin()
	_retreat()
	_resolve_after_landing()
	_last_heal_after_boundary(true)
	_last_heal_after_boundary(false)
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: road cast event cues")
	quit(0 if failures.is_empty() else 1)


func _bind(id: String, presentation: Dictionary) -> void:
	defs.characters[id] = {"class": "enemy", "label": id, "cast_key": id,
		"cast_art_key": "unit", "cast_team": "enemies", "cast_presentation": presentation}


func _unit(id: String, character: String, cell: Vector2i, hp := 5) -> Dictionary:
	return {"id": id, "character_id": character, "position": cell,
		"hp": hp, "max_hp": 5, "statuses": {}}


func _state(units: Array) -> Dictionary:
	return {"catalog": {"defs": defs}, "units": units, "obstacles": [],
		"round": 1, "objective": {}}


func _clips(cues: Array, id: String, clip: String) -> Array:
	return cues.filter(func(cue): return cue.get("unit_id") == id and cue.get("clip") == clip)


func _armor() -> void:
	var before := _state([_unit("owner", "lender", Vector2i(2, 2)),
		_unit("ward", "harpooner", Vector2i(3, 2)), _unit("other", "lender", Vector2i(5, 2))])
	var grant := {"type": "borrowed_armor", "unit_id": "owner", "target_id": "ward"}
	var cues := Cues.build(before, before, [grant])
	var lends := _clips(cues, "owner", "lend_armor")
	_check(lends.size() == 1 and lends[0].get("target_cell") == Vector2i(3, 2),
		"Armor grant plays once for the lending owner, aimed at the borrower")
	_check(_clips(cues, "ward", "lend_armor").is_empty() and _clips(cues, "other", "lend_armor").is_empty(),
		"Neither borrower nor another lender performs the grant")
	var block := grant.duplicate()
	block["amount"] = 2
	_check(_clips(Cues.build(before, before, [block]), "owner", "lend_armor").is_empty(),
		"Armor blocking a hit is not another lending gesture")


func _last_heal() -> void:
	var before := _state([_unit("attacker", "healer", Vector2i(1, 2)),
		_unit("fallen", "friar", Vector2i(2, 2), 1),
		_unit("ally_a", "harpooner", Vector2i(3, 2), 2),
		_unit("ally_b", "harpooner", Vector2i(3, 3), 3)])
	var after := before.duplicate(true)
	after.units[1].hp = 0
	after.units[2].hp = 4
	after.units[3].hp = 4
	var damage := {"type": "damage", "source_id": "attacker", "target_id": "fallen", "amount": 1,
		"resolved_action": {"unit_id": "attacker", "ability_id": "healer_bonk",
			"source_cell": Vector2i(1, 2), "actor_cell": Vector2i(1, 2), "event_count": 3}}
	var heal_a := {"type": "heal", "unit_id": "fallen", "source_id": "fallen", "target_id": "ally_a", "amount": 2}
	var heal_b := {"type": "heal", "unit_id": "fallen", "source_id": "fallen", "target_id": "ally_b", "amount": 1}
	var cues := Cues.build(before, after, [damage, heal_a, heal_b], true)
	var falls := _clips(cues, "fallen", "last_heal")
	_check(falls.size() == 1 and _clips(cues, "fallen", "defeat").is_empty(),
		"Positive death heals select one alternate fall, not an additional defeat")
	if falls.size() == 1:
		var effects: Array = falls[0].get("performance", {}).get("effects", [])
		var targets := []
		for effect: Dictionary in effects:
			if effect.get("kind") == "heal" and effect.get("source_id") == "fallen":
				targets.append(effect.get("target_id"))
		_check(targets == ["ally_a", "ally_b"],
			"Both actual heals belong to the last-heal performance at its mark")
	var damage_only := damage.duplicate(true)
	damage_only.resolved_action.event_count = 1
	var no_heal := Cues.build(before, after, [damage_only], true)
	_check(_clips(no_heal, "fallen", "defeat").size() == 1 \
		and _clips(no_heal, "fallen", "last_heal").is_empty(),
		"Fall with no successful heal uses ordinary defeat")
	var zero := heal_a.duplicate()
	zero.amount = 0
	var damage_zero := damage.duplicate(true)
	damage_zero.resolved_action.event_count = 2
	_check(_clips(Cues.build(before, after, [damage_zero, zero], true), "fallen", "last_heal").is_empty(),
		"A zero heal does not select the alternate fall")


func _windup() -> void:
	var before := _state([_unit("crusher", "bruiser", Vector2i(2, 2))])
	var cell := Vector2i(4, 2)
	var strike := {"type": "windup_strike", "unit_id": "crusher", "position": cell}
	var hits := _clips(Cues.build(before, before, [strike]), "crusher", "delayed_heavy_strike")
	_check(hits.size() == 1 and hits[0].get("target_cell") == cell,
		"Actual windup strike aims at the stored tile even when empty")
	for kind in ["windup_mark", "windup_delayed"]:
		_check(_clips(Cues.build(before, before, [{"type": kind, "unit_id": "crusher", "position": cell}]),
			"crusher", "delayed_heavy_strike").is_empty(), "%s does not play the strike" % kind)
	var timed := before.duplicate(true)
	timed.catalog.defs.characters.bruiser.cast_presentation.events.windup_strike = {
		"clip": "delayed_heavy_strike", "impact_frame": 17}
	var timed_hits := _clips(Cues.build(timed, timed, [strike]), "crusher", "delayed_heavy_strike")
	_check(timed_hits.size() == 1 and timed_hits[0].get("impact_frame") == 17,
		"Object-form windup event passes its authored contact frame to the cue")


func _bell() -> void:
	var before := _state([_unit("corpse_bell_risen", "harpooner", Vector2i(1, 1), 0)])
	var after := before.duplicate(true)
	after.units.append(_unit("corpse_bell_risen_", "risen", Vector2i(4, 3)))
	var event := {"type": "corpse_bell_raised", "unit_id": "corpse_bell_risen_", "position": Vector2i(4, 3)}
	var rises := _clips(Cues.build(before, after, [event]), "corpse_bell_risen_", "bell_rise")
	_check(rises.size() == 1 and rises[0].get("source_cell") == Vector2i(4, 3),
		"Newly allocated bell soldier owns its rise at the event cell")
	for kind in ["corpse_bell_marked", "corpse_bell_blocked"]:
		_check(_clips(Cues.build(before, after, [{"type": kind, "position": Vector2i(4, 3)}]),
			"corpse_bell_risen_", "bell_rise").is_empty(), "%s is not a rise" % kind)


func _sweep() -> void:
	var before := _state([_unit("giant", "giant", Vector2i(2, 2)),
		_unit("first", "healer", Vector2i(3, 2)), _unit("second", "knight", Vector2i(2, 3))])
	var after := before.duplicate(true)
	after.units[1].hp = 4
	after.units[2].hp = 4
	var action := {"unit_id": "giant", "ability_id": "fixture_sweep", "source_cell": Vector2i(2, 2),
		"actor_cell": Vector2i(2, 2), "event_count": 3}
	var events := [{"type": "sweep", "unit_id": "giant", "resolved_action": action},
		{"type": "damage", "source_id": "giant", "target_id": "first", "amount": 1},
		{"type": "damage", "source_id": "giant", "target_id": "second", "amount": 1}]
	var swings := _clips(Cues.build(before, after, events), "giant", "sweep")
	_check(swings.size() == 1, "Actual sweep handler starts one Giant sweep")
	if swings.size() == 1:
		_check(swings[0].get("recipients", []) == [
			{"id": "first", "cell": Vector2i(3, 2), "kind": "hit"},
			{"id": "second", "cell": Vector2i(2, 3), "kind": "hit"}],
			"Sweep marks each actual damage recipient once")


func _twin() -> void:
	var before := _state([_unit("twin", "twin", Vector2i(2, 2)),
		_unit("other", "twin", Vector2i(5, 2)), _unit("target", "healer", Vector2i(3, 2))])
	var after := before.duplicate(true)
	after.units[2].hp = 4
	var action := {"unit_id": "twin", "ability_id": "fixture_strike", "source_cell": Vector2i(2, 2),
		"actor_cell": Vector2i(2, 2), "event_count": 2}
	var bonus := {"type": "health_damage_bonus", "unit_id": "twin", "amount": 1, "condition": "full",
		"resolved_action": action}
	var damage := {"type": "damage", "source_id": "twin", "target_id": "target", "amount": 1}
	var cues := Cues.build(before, after, [bonus, damage])
	var resolves := _clips(cues, "twin", "resolve")
	var attacks := _clips(cues, "twin", "close_strike")
	_check(resolves.size() == 1 and attacks.size() == 1 and cues.find(resolves[0]) < cues.find(attacks[0]),
		"Health bonus is a prelude to, not a replacement for, the melee action")
	if resolves.size() == 1:
		_check(resolves[0].get("recipients", []).is_empty(), "Resolve does not mark a hit")
	_check(_clips(cues, "other", "resolve").is_empty(), "Only the actual bonus owner plays Resolve")
	_check(_clips(Cues.build(before, before, [{"type": "damage", "source_id": "target",
		"target_id": "twin", "amount": 5}]), "twin", "resolve").is_empty(),
		"Death alone does not play Resolve")


func _retreat() -> void:
	var before := _state([_unit("friar", "friar", Vector2i(2, 2))])
	var after := before.duplicate(true)
	after.units[0].position = Vector2i(1, 2)
	var action := {"unit_id": "friar", "ability_id": "move", "source_cell": Vector2i(2, 2),
		"actor_cell": Vector2i(1, 2), "event_count": 1}
	var event := {"type": "move", "unit_id": "friar", "position": Vector2i(1, 2),
		"tactical_retreat": true, "resolved_action": action}
	_check(_clips(Cues.build(before, after, [event]), "friar", "retreat").size() == 1,
		"Actual tactical retreat plays the retreat take")
	event.erase("tactical_retreat")
	_check(_clips(Cues.build(before, after, [event]), "friar", "retreat").is_empty(),
		"Ordinary movement does not borrow the tactical retreat take")


func _test_clip() -> Sprites.Clip:
	var clip := Sprites.Clip.new()
	clip.frames.append_array([Rect2(0, 0, 1, 1), Rect2(1, 0, 1, 1)])
	clip.frame_ends.append_array([500.0, 1000.0])
	clip.source_frames.append_array([1, 11])
	clip.total_ms = 1000.0
	return clip


func _resolve_after_landing() -> void:
	_bind("pusher", {"actions": {"fixture_push": {"handler": "push", "clip": "shove"}}})
	defs.abilities["fixture_push"] = {"handler": "push"}
	var before := _state([_unit("pusher", "pusher", Vector2i(1, 2)),
		_unit("twin", "twin", Vector2i(2, 2)), _unit("target", "healer", Vector2i(4, 2))])
	var after := before.duplicate(true)
	after.units[1].position = Vector2i(3, 2)
	after.units[2].hp = 4
	var push := {"unit_id": "pusher", "ability_id": "fixture_push", "source_cell": Vector2i(1, 2),
		"actor_cell": Vector2i(1, 2), "event_count": 1}
	var attack := {"unit_id": "twin", "ability_id": "fixture_strike", "source_cell": Vector2i(3, 2),
		"actor_cell": Vector2i(3, 2), "event_count": 2}
	var events := [
		{"type": "push", "unit_id": "pusher", "target_id": "twin", "position": Vector2i(3, 2),
			"resolved_action": push},
		{"type": "health_damage_bonus", "unit_id": "twin", "amount": 1, "condition": "full",
			"resolved_action": attack},
		{"type": "damage", "source_id": "twin", "target_id": "target", "amount": 1}]
	var cues := Cues.build(before, after, events, true)
	_check(_clips(cues, "twin", "resolve").size() == 1 \
		and _clips(cues, "twin", "close_strike").size() == 1,
		"Displaced twin retains both its real bonus prelude and attack")
	var clip := _test_clip()
	var art := Sprites.new()
	art.set("_actors", {"pusher": {"shove": clip}, "twin": {"resolve": clip, "close_strike": clip}})
	var playback := Playback.new()
	playback.enqueue(cues, art)
	var motions: Array = playback.get("_motions").filter(
		func(motion): return motion.get("unit_id") == "twin")
	var resolves: Array = playback.get("_entries").filter(
		func(entry): return entry.cue.get("unit_id") == "twin" and entry.cue.get("clip") == "resolve")
	var strikes: Array = playback.get("_entries").filter(
		func(entry): return entry.cue.get("unit_id") == "twin" and entry.cue.get("clip") == "close_strike")
	_check(motions.size() == 1 and resolves.size() == 1 and strikes.size() == 1,
		"Playback schedules the displacement, Resolve and melee")
	if motions.size() != 1 or resolves.size() != 1 or strikes.size() != 1:
		return
	var motion: Dictionary = motions[0]
	var landing: float = motion.duration_ms - motion.elapsed_ms
	var resolve_start: float = -resolves[0].elapsed_ms
	var strike_start: float = -strikes[0].elapsed_ms
	_check(motion.from == Vector2i(2, 2) and motion.to == Vector2i(3, 2) and strike_start >= landing,
		"Horizontal displacement reaches its real destination before the main attack")
	_check(resolve_start >= landing,
		"Resolve begins after landing: start %.1f ms, landing %.1f ms" % [resolve_start, landing])


func _last_heal_after_boundary(round_end: bool) -> void:
	var label := "round-end" if round_end else "untagged"
	var before := _state([_unit("giant", "giant", Vector2i(1, 1)),
		_unit("target", "healer", Vector2i(2, 1)), _unit("fallen", "friar", Vector2i(5, 2), 1),
		_unit("ally", "harpooner", Vector2i(6, 2), 2)])
	var after := before.duplicate(true)
	after.units[1].hp = 4
	after.units[2].hp = 0
	after.units[3].hp = 4
	var action := {"unit_id": "giant", "ability_id": "fixture_sweep", "source_cell": Vector2i(1, 1),
		"actor_cell": Vector2i(1, 1), "event_count": 2}
	var events := [
		{"type": "sweep", "unit_id": "giant", "resolved_action": action},
		{"type": "damage", "source_id": "giant", "target_id": "target", "amount": 1},
		{"type": "damage", "source_id": "fallen", "target_id": "fallen", "amount": 1,
			"effect_timing": "round_end"},
		{"type": "heal", "unit_id": "fallen", "source_id": "fallen", "target_id": "ally", "amount": 2,
			"effect_timing": "round_end"}]
	if not round_end:
		events[2].erase("effect_timing")
		events[3].erase("effect_timing")
	var cues := Cues.build(before, after, events, true)
	_check(_clips(cues, "fallen", "last_heal").size() == 1 \
		and _clips(cues, "fallen", "defeat").is_empty(),
		"%s loose lethal HP loss with a successful death heal selects one alternate fall" % label)
	var clip := _test_clip()
	var art := Sprites.new()
	art.set("_actors", {"giant": {"sweep": clip}, "friar": {"last_heal": clip, "defeat": clip}})
	var playback := Playback.new()
	playback.enqueue(cues, art)
	var entries: Array = playback.get("_entries")
	var boundaries := entries.filter(func(entry):
		return entry.cue.get("presentation_boundary", false) \
			and entry.cue.get("performance", {}).get("effects", []).any(func(effect):
				return effect.get("kind") == "damage" and effect.get("target_id") == "fallen"))
	var falls := entries.filter(
		func(entry): return entry.cue.get("unit_id") == "fallen" and entry.cue.get("clip") == "last_heal")
	_check(boundaries.size() == 1 and falls.size() == 1,
		"%s playback retains the lethal HP boundary and one last-heal fall" % label)
	if boundaries.size() != 1 or falls.size() != 1:
		return
	var lethal_impact: float = boundaries[0].impact_ms - boundaries[0].elapsed_ms
	var fall_start: float = -falls[0].elapsed_ms
	_check(lethal_impact > 0.0, "Earlier action makes the %s lethal boundary nonzero" % label)
	_check(fall_start >= lethal_impact,
		"%s last heal starts at or after lethal HP impact: start %.1f ms, impact %.1f ms" \
			% [label, fall_start, lethal_impact])


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
