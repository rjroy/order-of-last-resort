extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_committed_playback_test.gd
## Actual committed rules -> cast adapter -> scheduler. No pixels or audition.

const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
const Fixture = preload("res://tests/fixtures/rules_catalog.gd")
const Progression = preload("res://guild_progression.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")
const Playback = preload("res://presentation/cast_playback.gd")

var _rules := Rules.new()
var _art := Sprites.new()
var _defs: Dictionary
var _failures: Array[String] = []


func _initialize() -> void:
	_defs = Fixture.add_fixed_escort(Catalog.read_default().duplicate(true))
	_defs.characters.harpooner.behavior = "hold"
	_defs.characters.ferryman.behavior = "hold"
	_defs.characters.skeleton.behavior = "hold"
	_defs.abilities.wizard_blast.params.damage = 4
	_art.load_manifest()
	_borrowed_and_fallback()
	_cover_and_echo()
	_status_boundaries()
	_cover_survives_silent_hold()
	_queued_recovery_tail()
	_doses()
	_ordinary_replays()
	_hp_projections()
	_jump_timing()
	_authored_jump_and_claim()
	_resisted_displacement()
	_lifecycle()
	_shield_drop_and_retrieve()
	_smith_sound_boundary()
	_smith_primary_markers()
	_loaded_smith_atlas()
	for message in _failures:
		push_error("FAIL: " + message)
	if _failures.is_empty():
		print("PASS: Smith committed playback facts and timeline")
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures.append(message)
	return condition


func _unit(id: String, character: String, at: Vector2i, hp := 20) -> Dictionary:
	return {"id": id, "character_id": character, "position": at,
		"hp": hp, "max_hp": 20, "statuses": {}, "upgrades": {}}


func _entity(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.units:
		if unit.id == id:
			return unit
	return {}


func _state(wearer: String) -> Dictionary:
	var state := _rules.new_game(_defs, "test_escort")
	state.width = 12
	state.height = 12
	state.terrain = []
	state.obstacles = []
	state.default_tile = "stone"
	var hero := _unit("wearer", wearer, Vector2i(5, 5))
	hero["fitted_by"] = "smith"
	state.units = [_unit("smith", "blacksmith", Vector2i(4, 6)), hero,
		_unit("patient", "knight", Vector2i(5, 4)),
		_unit("enemy", "harpooner", Vector2i(7, 5)),
		_unit("civilian", "ferryman", Vector2i(10, 10))]
	state.party = ["smith", "wearer", "patient"]
	state.orders = {"smith": "order_hold", "wearer": "order_hold", "patient": "order_hold"}
	state.overrides = {}
	state.objective = {"handler": "escort", "subject": "civilian", "destination": Vector2i(11, 11)}
	state.rng_state = 12345
	state.dose_seed = 29
	return state


func _commit(state: Dictionary, actor: String, ability: String, target := "") -> Dictionary:
	var before := state.duplicate(true)
	var plan := _rules.preview(state, actor, ability, target)
	if not _check(plan.get("valid", false), "Legal fixture: " + ability + " / " + target):
		return {}
	var timeline := Playback.new()
	_check(timeline.advance(30.0).is_empty() and timeline.presentation_beats().is_empty()
		and state == before, ability + ": forecast leaves state and timeline untouched")
	var result := _rules.apply_plan(state, plan)
	_check(result == plan.result, ability + ": commit matches forecast")
	var cues := Cues.build(state, result, plan.events, true)
	return {"state": result, "cues": cues}


func _cue(data: Dictionary, form: String) -> Dictionary:
	for cue: Dictionary in data.get("cues", []):
		if cue.get("performance", {}).get("form_id") == form:
			return cue
	_check(false, "Missing committed cue for " + form)
	return {}


func _find_beat(beats: Array, form: String, kind := "impact") -> Dictionary:
	for beat: Dictionary in beats:
		if beat.kind == kind and beat.form_id == form:
			return beat
	_check(false, "Missing %s beat for %s" % [kind, form])
	return {}


func _effect(beat: Dictionary, kind: String, target := "") -> Dictionary:
	for effect: Dictionary in beat.get("effects", []):
		if effect.kind == kind and (target.is_empty() or effect.target_id == target):
			return effect
	_check(false, "Missing %s effect on %s" % [kind, target])
	return {}


func _timeline(data: Dictionary) -> Playback:
	var timeline := Playback.new()
	timeline.enqueue(data.get("cues", []), _art)
	return timeline


func _entry(timeline: Playback, form: String) -> Playback.Entry:
	for entry: Playback.Entry in timeline.get("_entries"):
		if entry.cue.get("performance", {}).get("form_id") == form:
			return entry
	_check(false, "Missing scheduled performer entry for " + form)
	return null


## Test-owned samples cover scheduler boundaries even while sheets stage.
## Prefer each actual installed clip when available; no pixels are asserted.
func _timed_media(specs: Array) -> Sprites:
	var actors: Dictionary = _art.get("_actors").duplicate(true)
	var ready := _art.clip_for("knight", "ready")
	for spec: Array in specs:
		var role: String = spec[0]
		var key: String = spec[1]
		if _art.clip_for(role, key) != null:
			continue
		var clip := Sprites.Clip.new()
		clip.path = ready.path
		var frames: Array = spec[2]
		clip.source_frames.assign(frames)
		for i in frames.size():
			var exclusive: int = frames[i + 1] if i + 1 < frames.size() else spec[3]
			clip.frame_ends.append((exclusive - 1) * 1000.0 / 24.0)
			clip.frames.append(ready.frames[0])
		clip.total_ms = clip.frame_ends.back()
		if not actors.has(role):
			actors[role] = {}
		actors[role][key] = clip
	var result := Sprites.new()
	result.set("_actors", actors)
	return result


func _borrowed_and_fallback() -> void:
	var state := _state("healer")
	var loadout := Progression.playtest_kit(_defs, "healer", {"offense": "wizard_blast"})
	if not _check(loadout.has("kit"), "Healer Blast is a legal borrowed loadout"):
		return
	state["_guild"] = Catalog.FrozenCatalog.new({"kits": {"wearer": loadout.kit}})
	_entity(state, "patient").hp = 18
	var converted := _commit(state, "wearer", "wizard_blast")
	var cue := _cue(converted, "mending_blast")
	var use: Dictionary = cue.get("performance", {})
	_check(use.get("actor_id") == "wearer" and use.get("cast_key") == "healer"
		and use.get("source_ability_id") == "wizard_blast" and use.get("branch") == "converted"
		and cue.get("clip") == "", "Borrowed conversion identifies the actual learner, never donor art")
	var timeline := _timeline(converted)
	var entries: Array = timeline.get("_entries")
	_check(entries.size() == 1 and entries[0].clip == _art.clip_for("healer", "blast")
		and not entries[0].cue.get("silent_action", false), "Scheduler actually loads the Healer's outward clip")
	var no_art := Playback.new()
	no_art.enqueue(converted.get("cues", []), Sprites.new())
	_check(no_art.snapshot().size() == 1 and no_art.snapshot()[0].get("silent_action", false),
		"No compatible art leaves only the semantic beat")
	_check(timeline.advance(2000.0).is_empty(), "Converted Mending Blast never plays ordinary Blast audio")
	var hit := _find_beat(timeline.presentation_beats(), "mending_blast")
	var heal := _effect(hit, "heal", "patient")
	_check(heal.get("cell") == Vector2i(5, 4) and heal.get("amount") == 2 \
		and heal.get("hp_before") == 18 and heal.get("hp_after") == 20, "Heal uses actual capped amount, HP and cell")
	_entity(state, "patient").hp = 20
	_entity(state, "wearer").hp = 16
	var inward := _timeline(_commit(state, "wearer", "wizard_blast"))
	entries = inward.get("_entries")
	_check(entries.size() == 1 and entries[0].clip == _art.clip_for("healer", "self_heal")
		and entries[0].cue.performance.get("aim", {}).get("id") == "wearer",
		"Self-targeted borrowed Mending Blast loads the Healer's actual inward clip")
	_entity(state, "wearer").hp = 20
	var fallback := _commit(state, "wearer", "wizard_blast")
	cue = _cue(fallback, "wizard_blast")
	use = cue.get("performance", {})
	_check(use.get("branch") == "fallback" and cue.get("clip") == "blast" and cue.get("cast_key") == "healer",
		"Ordinary fallback keeps the wearer's stock clip")
	_check(_effect(use, "damage", "patient").get("amount") == 4, "Fallback records real friendly-fire victim")


func _cover_and_echo() -> void:
	var state := _state("healer")
	_entity(state, "wearer").statuses["inspired"] = {"source_id": "smith"}
	var cover := _cue(_commit(state, "wearer", "healer_bonk", "patient"), "keep_your_head_down")
	var protection := _effect(cover.get("performance", {}), "status", "patient")
	_check(protection.get("status_id") == "keep_your_head_down" and int(protection.get("amount", 0)) > 0,
		"Cover is a grant on the patient, not a damage effect")
	_check(_effect(cover.get("performance", {}), "primary_improvement", "wearer").get("consumed") == true,
		"Consumed Inspiration names the wearer rather than the protected patient")
	state = _state("bard")
	state["_guild"] = Catalog.FrozenCatalog.new({"kits": {"wearer": {"guild_techniques": ["song_weaving"]}}})
	_entity(state, "wearer")["last_base_song"] = {"ability_id": "healing_sonnet", "round": state.round - 1}
	state.round += 1
	_entity(state, "wearer").last_base_song.round = state.round - 1
	var data := _commit(state, "wearer", "inspiring_melody")
	var timeline := _timeline(data)
	timeline.advance(5000.0)
	var beats := timeline.presentation_beats()
	var live := _find_beat(beats, "inspiring_melody_in_tune")
	var status := _effect(live, "status")
	var echo := _find_beat(beats, "healing_sonnet")
	_check(status.get("status_id") == "inspired" and status.get("target_id") in state.party,
		"Inspiration goes to the actual friendly recipient")
	_check(echo.get("branch") == "echo" and echo.get("source_ability_id") == "healing_sonnet"
		and float(echo.get("offset", 0.0)) > float(live.get("offset", 0.0))
		and _effect(echo, "damage", "enemy").get("cell") == Vector2i(7, 5),
		"Ordinary echo follows the friendly performance and carries only its own effects")


func _status_boundaries() -> void:
	for skipped in [false, true]:
		var state := _state("healer")
		var patient := _entity(state, "patient")
		patient.statuses["keep_your_head_down"] = {"source_id": "wearer", "amount": 3}
		patient.statuses["steady_hands"] = {"source_id": "patient", "amount": 1}
		if skipped:
			patient.statuses["knockdown"] = {"source_id": "enemy"}
		state = _rules.choose_manual(state, "patient", "move", "5,3")
		var plan := _rules.preview_round(state)
		var committed := _rules.commit_round(state, plan)
		_check(plan.get("valid", false) and committed == plan.result, "Expiry round commits the same preview")
		var start := -1
		var end := -1
		var action := -1
		for index in plan.events.size():
			var event: Dictionary = plan.events[index]
			if event.get("unit_id") != "patient":
				continue
			if event.type == "status_expired":
				_check(not event.has("resolved_action"), "Expiry stays outside action groups")
				if event.timing == "actor_turn_start":
					start = index
				else:
					end = index
			elif event.type == ("recover" if skipped else "move"):
				action = index
				if not skipped:
					_check(event.get("resolved_action", {}).get("event_count") == 1, "Expiry does not extend Move span")
		_check(start >= 0 and start < action and action < end, "Expiry brackets ordinary / skipped activation")
		_check(_entity(committed, "patient").statuses.is_empty(), "Cover and Steady Hands have actually expired")
		var timeline := _timeline({"cues": Cues.build(state, committed, plan.events, true)})
		var audio := timeline.advance(5000.0)
		var effects := timeline.presentation_beats().filter(func(beat: Dictionary): return beat.kind == "status")
		_check(effects.size() == 2 and effects[0].effects[0].timing == "actor_turn_start"
			and effects[1].effects[0].timing == "actor_turn_end"
			and effects[1].effects[0].cell == (Vector2i(5, 4) if skipped else Vector2i(5, 3))
			and audio.all(func(beat): return beat.kind == "step"), "Expiry is a silent timed status boundary")
	var state := _state("healer")
	_entity(state, "enemy").position = Vector2i(5, 3)
	_entity(state, "patient").statuses["keep_your_head_down"] = {"source_id": "wearer", "amount": 100}
	var hit := _cue(_commit(state, "enemy", "enemy_attack", "patient"), "enemy_attack")
	_check(_effect(hit.get("performance", {}), "status", "patient").get("consumed") == true,
		"A different actor's attack reports the ward it actually spent")


func _cover_survives_silent_hold() -> void:
	var state := _state("healer")
	var quiet := _rules.preview_round(state)
	_check(Cues.build(state, quiet.result, quiet.events, true).is_empty(),
		"An otherwise quiet round creates no artificial Hold beats")
	state = _rules.choose_manual(state, "wearer", "healer_bonk", "patient")
	var plan := _rules.preview_round(state)
	var end := _rules.commit_round(state, plan)
	_check(plan.events.any(func(event): return event.type == "wait" and event.unit_id == "patient")
		and not _entity(end, "patient").statuses.has("keep_your_head_down"),
		"Actual patient Holds and expires Cover during the same resolved round")
	var timeline := _timeline({"cues": Cues.build(state, end, plan.events, true)})
	var entry := _entry(timeline, "keep_your_head_down")
	if entry == null:
		return
	timeline.advance(entry.impact_ms - entry.elapsed_ms + 1.0)
	var grant := _find_beat(timeline.presentation_beats(), "keep_your_head_down")
	_check(_effect(grant, "status", "patient").get("status_id") == "keep_your_head_down",
		"Cover is applied at the actual protection impact")
	_check(timeline.advance(200.0).is_empty() and timeline.presentation_beats().is_empty(),
		"Quiet Hold expiry cannot erase fresh Cover on the grant frame")
	_check(timeline.advance(40.0).is_empty(), "Expiry does not emit an action sound")
	var expiry := _find_beat(timeline.presentation_beats(), "", "status")
	_check(_effect(expiry, "status_expired", "patient").get("timing") == "actor_turn_end",
		"The later silent boundary is still the patient's own turn-end expiry")


func _queued_recovery_tail() -> void:
	var state := _state("healer")
	state.party = ["smith", "patient", "wearer"]
	var kit := Progression.playtest_kit(_defs, "knight", {"offense": "healer_bonk"})
	if not _check(kit.has("kit"), "Cover source can borrow a Bonk"):
		return
	state["_guild"] = Catalog.FrozenCatalog.new({"kits": {"patient": kit.kit}})
	_entity(state, "wearer").erase("fitted_by")
	_entity(state, "wearer").hp = 10
	_entity(state, "patient")["fitted_by"] = "smith"
	var cover := _commit(state, "patient", "healer_bonk", "wearer")
	if cover.is_empty():
		return
	var first := _commit_round(cover.state, "wearer", "healer_heal")
	var timeline := _timeline(cover)
	timeline.enqueue(first.cues, _art)
	timeline.advance(16.0)
	var next := _commit_round(first.state, "wearer", "healer_heal")
	timeline.enqueue(next.cues, _art)
	var heals: Array = timeline.get("_entries").filter(func(entry: Playback.Entry):
		return entry.cue.get("performance", {}).get("form_id") == "healer_heal")
	_check(heals.size() == 2 and -heals[1].elapsed_ms >= heals[0].duration_ms - heals[0].elapsed_ms,
		"Queued second Heal waits for same actor's actual recovery, not its earlier expiry boundary")


func _commit_round(state: Dictionary, actor: String, ability: String, target := "") -> Dictionary:
	var planned := _rules.choose_manual(state, actor, ability, target)
	var plan := _rules.preview_round(planned)
	var result := _rules.commit_round(planned, plan)
	_check(plan.get("valid", false) and result == plan.result, "Round commits the same ordered events")
	return {"state": result, "cues": Cues.build(state, result, plan.events, true)}


func _doses() -> void:
	for inverted in ["damage", "heal"]:
		var state := _state("alchemist")
		var actor := _entity(state, "wearer")
		actor.upgrades = {"alchemist_keep_the_culture": 1}
		_entity(state, "patient").hp = 18
		if inverted == "heal":
			actor.erase("fitted_by")
		var first := _commit(state, "wearer", "alchemist_acid", "patient" if inverted == "damage" else "enemy")
		if first.is_empty():
			continue
		state = first.state
		actor = _entity(state, "wearer")
		var bottled: Dictionary = actor.get("bottled_reaction", {}).duplicate()
		actor["fitted_by"] = "smith"
		var target := "enemy" if inverted == "damage" else "patient"
		var data := _commit(state, "wearer", "alchemist_repeat_batch", target)
		var timeline := _timeline(data)
		timeline.advance(5000.0)
		var beat := _find_beat(timeline.presentation_beats(), "counterbatch")
		var dose: Dictionary = beat.get("dose", {})
		var reaction := _effect(beat, "alchemy_reaction", target)
		_check(dose.get("polarity") == inverted and dose.get("recipe_id") == "alchemist_acid"
			and dose.get("recipient_id") == target and dose.get("amount") == bottled.get("amount")
			and reaction.get("reaction_id") == bottled.get("id")
			and reaction.get("category") == bottled.get("category") and reaction.get("cell") == dose.get("cell"),
			"Counterbatch %s uses actual polarity, recipient and unmodified recorded reaction" % inverted)
		_check(not _effect(beat, inverted, target).is_empty(), "Counterbatch has the resolved pulse at impact")


func _hp_projections() -> void:
	var state := _state("alchemist")
	_entity(state, "patient").hp = 14
	for seed_value in range(1, 1000):
		if Reactions.draw(seed_value, false).id == "second_helping":
			state.dose_seed = seed_value
			break
	_check(Reactions.draw(state.dose_seed, false).id == "second_helping", "Test seed draws Second Helping")
	var first := _commit_round(state, "wearer", "alchemist_acid", "patient")
	var next := _commit_round(first.state, "wearer", "alchemist_potion", "patient")
	var timeline := _timeline(first)
	timeline.advance(16.0)
	timeline.enqueue(next.cues, _art)
	timeline.advance(5000.0)
	var beats := timeline.presentation_beats()
	var conversion := _find_beat(beats, "buffer_solution")
	var boundary := _find_beat(beats, "", "projection")
	var followup := _find_beat(beats, "alchemist_potion")
	var buffer := _effect(conversion, "heal", "patient")
	var helping := _effect(boundary, "heal", "patient")
	var potion := _effect(followup, "heal", "patient")
	_check(boundary.get("branch") == "boundary" and helping.get("amount") == 1
		and helping.get("hp_before") == buffer.get("hp_after")
		and helping.get("hp_after") == potion.get("hp_before")
		and conversion.offset < boundary.offset and boundary.offset < followup.offset,
		"Second Helping updates midway, then the queued round starts from the healed HP")

	state = _state("healer")
	_entity(state, "enemy").merge({"character_id": "bomber", "position": Vector2i(4, 7), "hp": 1}, true)
	_entity(state, "wearer").position = Vector2i(5, 7)
	timeline = _timeline(_commit(state, "smith", "blacksmith_hammer_time", "enemy"))
	var audio := timeline.advance(5000.0)
	beats = timeline.presentation_beats()
	var detonation := _find_beat(beats, "", "projection")
	var collateral := _effect(detonation, "damage", "wearer")
	_check(detonation.get("branch") == "reaction" and collateral.get("source_id") == "enemy"
		and collateral.get("hp_before") == 20 and int(collateral.get("hp_after", 20)) < 20
		and detonation.offset > _find_beat(beats, "blacksmith_hammer_time").offset
		and _audio_count(audio, "blacksmith_hammer_time", "attack") == 1,
		"Bomber collateral updates another hero at its reaction beat without replaying Hammer Time")


func _ordinary_replays() -> void:
	# A genuinely performed dose fills the bottle every time; do not inject
	# a hand-built bottle or infer the replay from the source recipe alone.
	var hostile := "hostile_dose" if _art.clip_for("alchemist", "hostile_dose") != null else ""
	var cases := [
		{"recipe": "alchemist_acid", "bottled": "buffer_solution", "heal": true, "fit": true, "clip": "potion"},
		{"recipe": "alchemist_acid", "bottled": "buffer_solution", "heal": true, "fit": true,
			"fallback": true, "clip": "potion"},
		{"recipe": "alchemist_potion", "bottled": "bitter_medicine", "heal": false, "fit": true, "clip": hostile},
		{"recipe": "alchemist_acid", "bottled": "alchemist_acid", "heal": false, "fit": false, "clip": "acid"},
		{"recipe": "alchemist_potion", "bottled": "alchemist_potion", "heal": true, "fit": false, "clip": "potion"},
	]
	for sample: Dictionary in cases:
		var state := _state("alchemist")
		var actor := _entity(state, "wearer")
		actor.upgrades = {"alchemist_keep_the_culture": 1}
		actor.hp = 14
		_entity(state, "patient").hp = 14
		_entity(state, "enemy").position = Vector2i(6, 5)
		state.units.append(_unit("other", "harpooner", Vector2i(5, 6)))
		if not sample.fit:
			actor.erase("fitted_by")
		for seed_value in range(1, 1000):
			if Reactions.draw(seed_value, not sample.heal).category == "cosmetic":
				state.dose_seed = seed_value
				break
		var bottled := _commit(state, "wearer", sample.recipe, "patient" if sample.heal else "enemy")
		if bottled.is_empty():
			continue
		state = bottled.state
		actor = _entity(state, "wearer")
		var saved: Dictionary = actor.get("bottled_reaction", {}).duplicate()
		var saved_draw: Variant = actor.get("dose_rng_state")
		_check(saved.get("form") == sample.bottled, "Actual bottle remembers " + str(sample.bottled))
		if sample.get("fallback", false):
			actor["fitted_by"] = "smith"
			_entity(state, "enemy").position = Vector2i(9, 5)
			_entity(state, "other").position = Vector2i(9, 6)
		var next_target := "wearer" if sample.heal else "other"
		var replay := _commit(state, "wearer", "alchemist_repeat_batch", next_target)
		if replay.is_empty():
			continue
		var timeline := _timeline(replay)
		var entries: Array = timeline.get("_entries")
		var performer := entries.filter(func(entry: Playback.Entry): return entry.cue.unit_id == "wearer")
		if not sample.heal and performer.size() == 1:
			var flinches := entries.filter(func(entry: Playback.Entry):
				return entry.cue.unit_id == next_target and entry.cue.clip == "hit")
			var primary: Playback.Entry = performer[0]
			_check(flinches.size() == 1 and is_equal_approx(
				-flinches[0].elapsed_ms, primary.impact_ms - primary.elapsed_ms),
				"Damaging replay keeps the true recipient's flinch at impact")
		var audio := timeline.advance(5000.0)
		var beat := _find_beat(timeline.presentation_beats(), "alchemist_repeat_batch")
		var strike := _effect(beat, "heal" if sample.heal else "damage", next_target)
		var reaction := _effect(beat, "alchemy_reaction", next_target)
		_check(not strike.is_empty() and beat.get("fitted_dose_replay", false) == sample.fit
			and beat.get("branch") == ("fallback" if sample.get("fallback", false) else "ordinary")
			and beat.get("dose", {}).get("delivery_form_id") == sample.bottled
			and beat.dose.reach == saved.targeting.range
			and reaction.get("reaction_id") == saved.get("id") and reaction.get("category") == saved.get("category")
			and _entity(replay.state, "wearer").get("dose_rng_state") == saved_draw
			and _entity(replay.state, "wearer").get("fitted_by", "") == ("smith" if sample.get("fallback", false) else ""),
			"Ordinary replay preserves delivery, recipient, reaction, RNG and unspent fitting: " + str(sample.bottled))
		if _check(performer.size() == 1 and performer[0].cue.clip == sample.clip,
				"Replay %s/%s uses only %s, got %s" % [sample.bottled, beat.get("branch"),
					sample.clip, performer.map(func(entry): return entry.cue.get("clip"))]):
			if sample.fit:
				_check(audio.is_empty() and performer[0].cue.recipients.is_empty()
					and (sample.clip != "" or performer[0].cue.get("silent_action", false)),
					"Fitted-bottle replay cannot also dispatch legacy clip feedback or audio")
			else:
				_check(_audio_count(audio, "alchemist_repeat_batch", "repeat_batch") == 1
					and performer[0].clip == _art.clip_for("alchemist", sample.clip),
					"Ordinary stock bottles retain ordinary playback")


func _jump_timing() -> void:
	var state := _state("rogue")
	_entity(state, "enemy").position = Vector2i(9, 5)
	var data := _commit(state, "wearer", "rogue_confusing_dodge")
	var cue := _cue(data, "clear_jump")
	if cue.is_empty():
		return
	# Test-owned timing only. No shipped or candidate art is being evaluated.
	var timing := Sprites.Clip.new()
	timing.source_frames.assign([1, 4, 8])
	timing.frame_ends.assign([100.0, 300.0, 400.0])
	timing.total_ms = 400.0
	var fixtures := Sprites.new()
	fixtures.set("_actors", {"rogue": {"test_timing_only": timing}})
	cue.merge({"clip": "test_timing_only", "takeoff_frame": 4, "impact_frame": 8}, true)
	var timeline := Playback.new()
	timeline.enqueue(data.cues, fixtures)
	timeline.advance(99.0)
	_check(timeline.actor_cell("wearer", Vector2i.ZERO) == Vector2i(5, 5)
		and timeline.movement_fraction("wearer") == 0.0 and timeline.movement_source("enemy") == null
		and timeline.presentation_beats().is_empty(), "Clear Jump holds planted and never moves the locator")
	timeline.advance(101.0)
	_check(is_equal_approx(timeline.movement_fraction("wearer"), 0.5), "Travel starts on the authored takeoff")
	var lift := _find_beat(timeline.presentation_beats(), "clear_jump", "takeoff")
	_check(lift.get("effects", []) == [] and lift.get("performance_effects", []).size() == 1,
		"Takeoff exposes full resolved facts without dispatching the landing effect")
	_check(timeline.advance(100.0).is_empty(), "A jump doesn't dispatch an ordinary step or swap sound")
	var beats := timeline.presentation_beats()
	var landing := _find_beat(beats, "clear_jump", "motion_land")
	var move := _effect(landing, "move", "wearer")
	_check(landing.get("motion_mode") == "jump" and move.get("to") == Vector2i(8, 5),
		"Clear Jump lands the wearer at the actual tile")
	_check(landing.get("cue_order") == lift.get("cue_order") and landing.has("motion_order"),
		"Takeoff and landing share cue identity, with a separate motion identity")
	timeline.advance(1000.0)
	_check(timeline.presentation_beats().is_empty() and not timeline.pending(), "Impact and landing are once-only")


func _resisted_displacement() -> void:
	var state := _state("knight")
	_entity(state, "enemy")["alchemy_statuses"] = {"cork_soles": {"expires_after_round": 3}}
	var timeline := _timeline(_commit(state, "wearer", "knight_push", "enemy"))
	timeline.advance(5000.0)
	var beats := timeline.presentation_beats()
	var impact := _find_beat(beats, "fitted_pull")
	_check(_effect(impact, "status", "enemy").get("resisted") == true \
		and beats.all(func(beat): return beat.kind != "motion_land"), "Resisted Pull records the resistance, not a false shift")


func _authored_jump_and_claim() -> void:
	var art := _timed_media([["rogue", "clear_jump", [1, 7, 12, 17, 24], 28],
		["wizard", "clear_jump", [1, 8, 12, 17, 24], 29],
		["rogue", "it_was_me", [1, 10, 16, 19, 28], 36]])
	for spec in [["rogue", 7], ["wizard", 8]]:
		var state := _state(spec[0])
		_entity(state, "enemy").position = Vector2i(9, 5)
		if spec[0] == "wizard":
			var kit := Progression.playtest_kit(_defs, "wizard", {"utility": "rogue_confusing_dodge"})
			if not _check(kit.has("kit"), "Wizard equips his actual borrowed Dodge"):
				continue
			state["_guild"] = Catalog.FrozenCatalog.new({"kits": {"wearer": kit.kit}})
		var data := _commit(state, "wearer", "rogue_confusing_dodge")
		var timeline := Playback.new()
		timeline.enqueue(data.get("cues", []), art)
		var cast := _entry(timeline, "clear_jump")
		if not _check(cast != null and cast.clip == art.clip_for(spec[0], "clear_jump"),
				"Clear Jump plays the actual wearer's loaded clip"):
			continue
		var takeoff := cast.clip.time_at_source_frame(spec[1])
		var landing := cast.clip.time_at_source_frame(17)
		timeline.advance(takeoff - 1.0)
		_check(timeline.movement_fraction("wearer") == 0.0 and timeline.presentation_beats().is_empty()
			and timeline.movement_source("enemy") == null, "Jump waits for launch; locator never moves")
		timeline.advance(2.0)
		var launch := _find_beat(timeline.presentation_beats(), "clear_jump", "takeoff")
		_check(is_equal_approx(launch.get("offset", -1.0), 1.0), "Wearer-specific launch marker crosses once")
		timeline.advance(landing - takeoff)
		var arrival := _find_beat(timeline.presentation_beats(), "clear_jump", "motion_land")
		_check(is_equal_approx(arrival.get("offset", 0.0) + 1.0, landing - takeoff)
			and _effect(arrival, "move", "wearer").get("to") == Vector2i(8, 5),
			"F17 lands only the jumper at the real cell")
	var state := _state("rogue")
	_entity(state, "enemy").position = Vector2i(6, 5)
	var claimed := _commit(state, "wearer", "rogue_wasnt_me", "enemy")
	var timeline := Playback.new()
	timeline.enqueue(claimed.get("cues", []), art)
	var cast := _entry(timeline, "it_was_me")
	if not _check(cast != null and cast.clip == art.clip_for("rogue", "it_was_me"), "Dodger uses his own bonk and claim"):
		return
	_check(timeline.advance(5000.0).is_empty(), "It Was Me never also dispatches ordinary Misdirect audio")
	var beats := timeline.presentation_beats()
	var hit := _find_beat(beats, "it_was_me")
	var claim := _find_beat(beats, "it_was_me", "claim")
	_check(is_equal_approx(hit.get("offset", -1.0), cast.clip.time_at_source_frame(10))
		and is_equal_approx(claim.get("offset", -1.0), cast.clip.time_at_source_frame(19))
		and not _effect(hit, "damage", "enemy").is_empty() and claim.get("effects", []) == []
		and claim.get("cue_order") == hit.get("cue_order") and beats.size() == 2,
		"Bonk at F10 deals once; the F19 claim has no second rules effect")


func _lifecycle() -> void:
	var art := _timed_media([["necromancer", "recall", [1, 9, 17, 27], 28],
		["skeleton", "recall_tuck", [1, 5, 9, 13, 17], 18],
		["necromancer", "hush", [1, 6, 11, 17, 23, 29, 35], 36],
		["zombie", "play_dead", [1, 5, 10, 13, 15, 18, 21, 26], 27]])
	var state := _state("necromancer")
	_entity(state, "wearer").erase("fitted_by")
	var made := _commit(state, "wearer", "summon_skeleton", "6,5")
	if made.is_empty():
		return
	state = made.state
	_check(not _effect(_cue(made, "summon_skeleton").get("performance", {}), "summon").has("corpse_id"),
		"Ordinary summon does not claim to consume a corpse")
	var summons: Array = state.units.filter(func(unit): return unit.character_id == "skeleton")
	if not _check(summons.size() == 1, "Exactly one original skeleton"):
		return
	var skeleton: Dictionary = summons[0]
	skeleton.position = Vector2i(9, 5)
	_entity(state, "wearer")["fitted_by"] = "smith"
	var recall := _commit(state, "wearer", "summon_skeleton", "6,5")
	var timeline := Playback.new()
	timeline.enqueue(recall.get("cues", []), art)
	var cast := _entry(timeline, "recall_skeleton")
	if not _check(cast != null and cast.companion != null, "Recall binds both wearer and actual Skeleton"):
		return
	var cut_at := cast.impact_ms - cast.elapsed_ms
	timeline.advance(cut_at - 1.0)
	_check(timeline.actor_cell(skeleton.id, Vector2i(6, 5)) == Vector2i(9, 5)
		and timeline.movement_fraction(skeleton.id) == 0.0 and cast.companion not in timeline.active(),
		"Recall holds at the old tile without duplicating the Skeleton before the cut")
	_check(timeline.advance(2.0).is_empty(), "Recall adds no ordinary summon or companion audio")
	var cut := _find_beat(timeline.presentation_beats(), "recall_skeleton", "motion_land")
	_check(cut.get("motion_mode") == "cut" and _effect(cut, "recall", skeleton.id).get("cast_key") == "skeleton"
		and timeline.actor_cell(skeleton.id, Vector2i.ZERO) == Vector2i(6, 5), "Recall cuts the same Skeleton to its landing")
	_check(cast.companion in timeline.active() and cast.companion.clip == art.clip_for("skeleton", "recall_tuck")
		and cast.companion.cue.unit_id == skeleton.id and cast.companion.cue.actor_cell == Vector2i(6, 5)
		and cast.companion.cue.companion_for == cast.order and is_equal_approx(cast.companion.elapsed_ms, 1.0),
		"Actual Skeleton tuck begins exactly on the F17 cut, on the same ID")
	_check(timeline.companion_for(cut.cue_order) == cast.companion,
		"Crossed Recall landing order looks up the matched child entry")

	var later_state: Dictionary = recall.state
	_entity(later_state, "wearer")["fitted_by"] = "smith"
	_entity(later_state, skeleton.id).statuses["knockdown"] = {"source_id": "enemy"}
	var later := _commit(later_state, "wearer", "summon_skeleton", "5,6")
	timeline.enqueue(later.get("cues", []), art)
	var recalls: Array = timeline.get("_entries").filter(func(entry: Playback.Entry):
		return entry.cue.get("performance", {}).get("form_id") == "recall_skeleton")
	if _check(recalls.size() == 2 and recalls[1].companion != null
			and _rules.knocked_down(later.state, skeleton.id), "An already-prone Skeleton can legally be recalled again"):
		var successor: Playback.Entry = recalls[1]
		var original_child := cast.companion
		var later_child := successor.companion
		_check(timeline.companion_for(cast.order) == original_child
			and timeline.companion_for(successor.order) == later_child and later_child != original_child
			and later_child.cue.unit_id == original_child.cue.unit_id and later_child.cue.actor_cell == Vector2i(5, 6),
			"Rapid Recall of the same Skeleton keeps distinct companion handles by parent order")
		var caster_end := cast.duration_ms - cast.elapsed_ms
		var child_end := original_child.duration_ms - original_child.elapsed_ms
		if caster_end + 1.0 < child_end:
			timeline.advance(caster_end + 1.0)
			_check(cast not in timeline.active() and timeline.companion_for(cast.order) == original_child,
				"Lookup finds the continuing child after the caster's own clip drains")
		timeline.advance(original_child.duration_ms - original_child.elapsed_ms + 1.0)
		_check(timeline.companion_for(cast.order) == null and timeline.companion_for(successor.order) == later_child,
			"A drained companion never resolves to a later use of the same instance")

	var orphaned_media := Sprites.new()
	orphaned_media.set("_actors", {"necromancer": {"recall": art.clip_for("necromancer", "recall")}})
	var orphaned := Playback.new()
	orphaned.enqueue(recall.get("cues", []), orphaned_media)
	var unsupplied := _entry(orphaned, "recall_skeleton")
	_check(unsupplied != null and unsupplied.companion == null and unsupplied.cue.get("silent_action", false),
		"Partial sheet doesn't play an owner-only Recall as the complete pairing")

	state = _state("necromancer")
	state.units.append(_unit("corpse", "bomber", Vector2i(6, 5), 0))
	_entity(state, "wearer").erase("fitted_by")
	var raised := _commit(state, "wearer", "raise_dead", "corpse")
	if raised.is_empty():
		return
	state = raised.state
	var zombies: Array = state.units.filter(func(unit): return unit.character_id == "zombie")
	if not _check(zombies.size() == 1, "Exactly one raised zombie"):
		return
	_entity(state, "wearer")["fitted_by"] = "smith"
	var data := _commit(state, "wearer", "raise_dead")
	var hush := _cue(data, "play_dead")
	if hush.is_empty():
		return
	timeline = Playback.new()
	timeline.enqueue(data.get("cues", []), art)
	cast = _entry(timeline, "play_dead")
	if not _check(cast != null and cast.companion != null, "Play Dead loads both the Crypter and Zombie takes"):
		return
	var zombie := cast.companion
	var terminal := zombie.clip.source_frames.find(26)
	var lowering := cast.clip.time_at_source_frame(6)
	var halt := lowering + zombie.clip.frame_ends[terminal]
	_check(zombie.cue.unit_id == zombies[0].id and zombie.cue.actor_cell == Vector2i(6, 5)
		and is_equal_approx(-zombie.elapsed_ms, lowering) and is_equal_approx(cast.handoff_ms, halt),
		"Actual Zombie starts on Hush F6, and handoff waits the entire authored F26 hold")
	var observed := cast.impact_ms + 1.0
	timeline.advance(observed)
	var early := _find_beat(timeline.presentation_beats(), "play_dead")
	_check(early.get("effects", []) == [] and early.get("performance_effects", []).size() == 1,
		"Play Dead impact discloses the pending handoff without emitting pseudo-death or an early corpse")
	var re_raise := _commit(data.state, "wearer", "raise_dead", "corpse")
	timeline.enqueue(re_raise.get("cues", []), _art)
	timeline.advance(halt - observed - 1.0)
	_check(zombie in timeline.active() and zombie.clip.frame_index(zombie.elapsed_ms) == terminal
		and timeline.presentation_beats().is_empty(), "Zombie F26 is still visible just before handoff")
	_check(timeline.advance(2.0).is_empty() and zombie not in timeline.active(),
		"At the handoff, the Zombie stops drawing without a separate impact or sound")
	var handoff := _find_beat(timeline.presentation_beats(), "play_dead", "handoff")
	var swap := _effect(handoff, "play_dead", "corpse")
	_check(swap.get("retired_id") == zombies[0].id and swap.get("retired_cast_key") == "zombie"
		and swap.get("corpse_cast_key") == "bomber" and swap.get("cell") == Vector2i(6, 5),
		"Handoff carries the retired Zombie and original corpse identities, not a blast clip")
	timeline.advance(5000.0)
	var raise_beat := _find_beat(timeline.presentation_beats(), "raise_dead")
	var new_zombie := _effect(raise_beat, "summon")
	_check(new_zombie.get("corpse_id") == "corpse" and raise_beat.get("cue_order") != handoff.get("cue_order"),
		"Queued ordinary Raise consumes the restored corpse only at its own impact")


func _smith_sound_boundary() -> void:
	var state := _state("knight")
	_entity(state, "wearer").erase("fitted_by")
	var fit := _commit(state, "smith", "blacksmith_try_this", "wearer")
	var fit_timeline := _timeline(fit)
	var fit_audio := fit_timeline.advance(5000.0)
	_check(_audio_count(fit_audio, "blacksmith_try_this", "fit") == 1, "Try This emits exactly one fit impact")
	_entity(state, "enemy").position = Vector2i(4, 7)
	_entity(state, "enemy").hp = 1
	var hammer := _timeline(_commit(state, "smith", "blacksmith_hammer_time", "enemy"))
	_check(_audio_count(hammer.advance(5000.0), "blacksmith_hammer_time", "attack") == 1,
		"Hammer Time emits exactly one attack impact")
	var lethal := _effect(_find_beat(hammer.presentation_beats(), "blacksmith_hammer_time"), "damage", "enemy")
	_check(lethal.get("hp_before") == 1 and lethal.get("hp_after") == 0, "Lethal overkill clamps visual HP to zero")
	_entity(state, "smith").upgrades = {"smith_quick_release": 1}
	_entity(state, "wearer")["fitted_by"] = "smith"
	var release := _timeline(_commit(state, "wearer", "smith_quick_release", "6,5"))
	var sounds := release.advance(5000.0)
	var beats := release.presentation_beats()
	var first := _find_beat(beats, "smith_quick_release")
	var second := _find_beat(beats, "smith_quick_release", "motion_land")
	_check(_audio_count(sounds, "smith_quick_release", "quick_release") == 1
		and sounds.any(func(beat): return beat.kind == "step" and beat.ability_id == "move")
		and float(first.get("offset", 0.0)) < float(second.get("offset", 0.0)),
		"Quick Release emits one release, then a separate normal footfall")
	_check(not _effect(first, "fitted_release", "wearer").is_empty(), "Quick Release names the actual wearer")
	_check(sounds.any(func(beat):
		return beat.kind == "impact" and beat.cue_order == first.cue_order and beat.offset == first.offset),
		"Legacy and normalized impacts have exact same-frame deduplication identity")


func _shield_drop_and_retrieve() -> void:
	var art := _timed_media([["knight", "lend_a_shield", [1, 13, 17, 18, 24, 32], 33],
		["knight", "lend_a_shield_prop", [18], 19]])
	var lend := art.clip_for("knight", "lend_a_shield")
	if _art.clip_for("knight", "lend_a_shield") == null:
		lend.release_clip = "lend_a_shield_prop"
		lend.release_ms = lend.time_at_source_frame(18)
		lend.release_offset = Vector2(23, -40)
	var state := _state("knight")
	_entity(state, "wearer").upgrades = {"knight_shield_throw": 1}
	_entity(state, "wearer").position = Vector2i(5, 4)
	_entity(state, "patient").position = Vector2i(5, 2)
	var drop := _commit(state, "wearer", "knight_shield_throw", "patient")
	if drop.is_empty():
		return
	var pickup := _commit(drop.state, "wearer", "move", "5,3")
	if pickup.is_empty():
		return
	_check(not _entity(pickup.state, "wearer").has("shield_position"), "Final rules state has already retrieved shield")
	var timeline := Playback.new()
	timeline.enqueue(drop.cues, art)
	var throw := _entry(timeline, "lend_a_shield")
	if not _check(throw != null and throw.clip == lend and throw.is_shield_throw()
			and throw.gift == art.clip_for("knight", "lend_a_shield_prop"), "Lend loads its distinct detached shield"):
		return
	_check(is_equal_approx(lend.release_ms, lend.time_at_source_frame(18))
		and is_equal_approx(throw.impact_ms, lend.release_ms + Playback.GIFT_FLIGHT_MS)
		and throw.cue.shield_drop_cell == Vector2i(5, 2), "Lend flies to the real cell starting at F18")
	timeline.advance(lend.release_ms + 1.0)
	_check(throw.flight_progress() > 0.0 and throw.flight_progress() < 1.0
		and timeline.shield_in_transit(Vector2i(5, 2)) and timeline.presentation_beats().is_empty(),
		"Released shield is in flight before cover and tile placement")
	timeline.enqueue(pickup.cues, _art)
	timeline.advance(5000.0)
	var beats := timeline.presentation_beats()
	var offer := _find_beat(beats, "lend_a_shield")
	var landing := _find_beat(beats, "move", "motion_land")
	var given := _effect(offer, "shield_drop", "patient")
	var collected := _effect(landing, "shield_retrieve", "wearer")
	_check(given.get("cell") == Vector2i(5, 2) and collected.get("cell") == given.get("cell")
		and collected.get("recipient_cell") == Vector2i(5, 3)
		and collected.get("source_id") == "wearer" and offer.offset < landing.offset,
		"Queued shield appears at actual drop and retrieves on owner landing, not final-state refresh")


func _audio_count(beats: Array, ability: String, handler: String) -> int:
	return beats.filter(func(beat):
		return beat.kind == "impact" and beat.ability_id == ability and beat.handler == handler).size()


func _smith_primary_markers() -> void:
	var fixtures := Sprites.new()
	# Test the proposed samples without loading unapproved Smith art. A stock
	# atlas path supplies a resolvable drawing solely for the compatibility gate.
	var ready := _art.clip_for("knight", "ready")
	var atlas := {}
	for spec in [["try_this", [1, 13], [500.0, 700.0]], ["hammer_time", [1, 17], [667.0, 900.0]],
			["pursue", [1, 13, 28], [500.0, 1125.0, 1167.0]]]:
		var clip := Sprites.Clip.new()
		clip.path = ready.path
		clip.source_frames.assign(spec[1])
		clip.frame_ends.assign(spec[2])
		for unused in clip.source_frames:
			clip.frames.append(ready.frames[0])
		clip.total_ms = clip.frame_ends.back()
		atlas[spec[0]] = clip
	fixtures.set("_actors", {"blacksmith": atlas})
	var state := _state("knight")
	_entity(state, "wearer").erase("fitted_by")
	_entity(state, "enemy").position = Vector2i(4, 7)
	for spec in [["blacksmith_try_this", "wearer", "try_this", 500.0],
			["blacksmith_hammer_time", "enemy", "hammer_time", 667.0], ["move", "4,5", "pursue", 1125.0]]:
		var data := _commit(state, "smith", spec[0], spec[1])
		var timeline := Playback.new()
		timeline.enqueue(data.get("cues", []), fixtures)
		var entries: Array = timeline.get("_entries")
		if not _check(entries.size() == 1 and entries[0].clip == atlas[spec[2]]
				and not entries[0].cue.get("silent_action", false), "Smith performs only the loaded own take"):
			continue
		var audio := timeline.advance(3000.0)
		var beat := _find_beat(timeline.presentation_beats(), spec[0])
		_check(beat.get("offset") == spec[3], "Smith beat follows the loaded source frame")
		if spec[0] == "move":
			_check(audio.size() == 2 and audio[0].offset == 500.0 and audio[1].offset == 1125.0
				and audio[0].motion_order == audio[1].motion_order,
				"Two authored foot plants belong to exactly one board move")
		else:
			_check(audio.size() == 1 and audio[0].offset == spec[3], "Native impact audio follows source frame")


func _loaded_smith_atlas() -> void:
	var ready := _art.clip_for("blacksmith", "ready")
	if not _check(ready != null, "The installed Smith Ready take loads"):
		return
	var texture := Sprites.load_texture(ready.path)
	_check(texture != null and texture.get_width() > 0 and texture.get_height() > 0,
		"The installed Smith sprite sheet decodes with a nonempty size")
	var state := _state("knight")
	_entity(state, "wearer").erase("fitted_by")
	_entity(state, "enemy").position = Vector2i(4, 7)
	for spec in [["blacksmith_try_this", "wearer", "try_this", 13],
			["blacksmith_hammer_time", "enemy", "hammer_time", 17], ["move", "4,5", "pursue", 28],
			["healer_bonk", "enemy", "bonk", 15], ["alchemist_acid", "enemy", "acid", 18]]:
		var clip := _art.clip_for("blacksmith", spec[2])
		if spec[0] in ["healer_bonk", "alchemist_acid"]:
			var kit := Progression.playtest_kit(_defs, "blacksmith", {"offense": spec[0]})
			if not _check(kit.has("kit"), "Smith can really equip the borrowed offense"):
				continue
			state["_guild"] = Catalog.FrozenCatalog.new({"kits": {"smith": kit.kit}})
		var timeline := _timeline(_commit(state, "smith", spec[0], spec[1]))
		var entries: Array = timeline.get("_entries")
		if not _check(clip != null and entries.size() >= 1 and entries[0].clip == clip
				and entries[0].cue.cast_key == "blacksmith" and not entries[0].cue.get("silent_action", false),
				"Runtime loads Smith's installed atlas clip: " + str(spec[2])):
			continue
		var authored := clip.time_at_source_frame(spec[3])
		if spec[2] == "acid":
			_check(entries[0].gift == _art.clip_for("blacksmith", "acid_flask")
				and is_equal_approx(authored, clip.release_ms)
				and is_equal_approx(entries[0].impact_ms, authored + Playback.GIFT_FLIGHT_MS),
				"Smith's detached flask departs on F18 and the dose impacts on arrival")
		else:
			_check(is_equal_approx(entries[0].impact_ms, authored), "Loaded Smith sample supplies native timing")

	state = _state("wizard")
	_entity(state, "enemy").position = Vector2i(4, 7)
	_loaded_smith_reaction(_commit(state, "enemy", "enemy_attack", "smith"), "hit")
	_entity(state, "smith").hp = 1
	_loaded_smith_reaction(_commit(state, "enemy", "enemy_attack", "smith"), "defeat")
	_entity(state, "smith").hp = 20
	_entity(state, "smith").position = Vector2i(6, 5)
	_entity(state, "enemy").position = Vector2i(9, 5)
	_entity(state, "patient").position = Vector2i(2, 2)
	_entity(state, "wearer").erase("fitted_by")
	var fallen := _commit(state, "wearer", "wizard_blast")
	if fallen.is_empty():
		return
	_loaded_smith_reaction(fallen, "down")
	var plan := _rules.preview_round(fallen.state)
	var result := _rules.commit_round(fallen.state, plan)
	_loaded_smith_reaction({"cues": Cues.build(fallen.state, result, plan.events, true)}, "recover")
	print("Verified installed Smith native, equipped Bonk/Acid and lifecycle clips")


func _loaded_smith_reaction(data: Dictionary, key: String) -> void:
	var timeline := _timeline(data)
	var clip := _art.clip_for("blacksmith", key)
	var entries: Array = timeline.get("_entries").filter(func(entry: Playback.Entry):
		return entry.cue.get("unit_id") == "smith" and entry.cue.get("clip") == key)
	_check(entries.size() == 1 and clip != null and entries[0].clip == clip,
		"Real incoming effect schedules Smith's own " + key)
