extends SceneTree
## Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/presentation/smith_follow_through_playback_test.gd
## Real stock Bomber and cast manifest; no rendering or fabricated artwork.

const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules/rules.gd")
const Cues = preload("res://presentation/cast/cast_cues.gd")
const Sprites = preload("res://presentation/cast/cast_sprites.gd")
const Playback = preload("res://presentation/cast/cast_playback.gd")

var failures: Array[String] = []
var rules := Rules.new()


func _initialize() -> void:
	_test_surviving_smith()
	_test_chain_blast()
	_test_ordinary_defeat()
	_test_smith_killed_by_blast()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: Smith Follow Through playback timing")
	quit(0 if failures.is_empty() else 1)


func _opening(smith_hp: int, ordinary: bool = false) -> Dictionary:
	var state: Dictionary = Rules.open_mission(Catalog.read_default(), "explosive_situation",
		["blacksmith", "knight", "healer"])
	if state.is_empty():
		_check(false, "Stock explosive_situation opens")
		return {}
	state.obstacles = []
	_unit(state, "blacksmith").position = Vector2i(2, 1)
	_unit(state, "blacksmith").hp = smith_hp
	_unit(state, "blacksmith").upgrades = {"smith_follow_through": 1}
	_unit(state, "knight").position = Vector2i(0, 0)
	_unit(state, "healer").position = Vector2i(0, 3)
	_unit(state, "bomber_1").position = Vector2i(3, 1)
	_unit(state, "bomber_2").position = Vector2i(7, 1)
	_unit(state, "harpooner_3").position = Vector2i(7, 3)
	if ordinary:
		_unit(state, "bomber_1").character_id = "grunt"
		_unit(state, "bomber_1").hp = 2
		_unit(state, "bomber_1").max_hp = 2
	return state


func _action(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	var before := state.duplicate(true)
	var plan: Dictionary = rules.preview(state, "blacksmith", "blacksmith_hammer_time", "bomber_1")
	_check(plan.get("valid", false) and state == before, "Hammer preview is legal and pure")
	if not plan.get("valid", false):
		return {}
	_check(rules.apply_plan(state, plan) == plan.result and state == before,
		"Hammer commit reproduces the forecast")
	return plan


func _timeline(state: Dictionary, plan: Dictionary) -> Playback:
	var cues: Array = Cues.build(state, plan.result, plan.events, true)
	var art := Sprites.new()
	art.load_manifest()
	var playback := Playback.new()
	playback.enqueue(cues, art)
	return playback


func _test_surviving_smith() -> void:
	var state := _opening(8)
	var plan := _action(state)
	if plan.is_empty():
		return
	_check(_unit(state, "bomber_1").hp == 2
		and _unit(plan.result, "bomber_1").hp <= 0,
		"Stock two-HP Bomber dies to Hammer Time")
	_check(_unit(plan.result, "blacksmith").hp == 6
		and _unit(plan.result, "blacksmith").position == Vector2i(3, 1),
		"Surviving Smith takes the blast then follows onto the target tile")
	var blast_events: Array = plan.events.filter(func(event: Dictionary) -> bool:
		return event.get("type") == "damage" and event.get("damage_cause") == "death_blast" \
			and event.get("source_id") == "bomber_1" and event.get("target_id") == "blacksmith")
	_check(blast_events.size() == 1, "Rules resolve one Bomber blast hit on Smith")
	var timeline := _timeline(state, plan)
	var motions: Array = timeline.get("_motions").filter(
		func(motion: Dictionary) -> bool: return motion.get("unit_id") == "blacksmith")
	var blasts: Array = timeline.get("_entries").filter(func(entry: Playback.Entry) -> bool:
		return entry.cue.get("unit_id") == "bomber_1" and entry.cue.get("ordinary_role") == "defeat")
	_check(motions.size() == 1 and blasts.size() == 1,
		"Actual playback contains one Follow Through motion and one Bomber defeat")
	if motions.size() != 1 or blasts.size() != 1:
		return
	var motion: Dictionary = motions[0]
	var blast: Playback.Entry = blasts[0]
	var motion_start: float = -motion.elapsed_ms
	var blast_impact: float = blast.impact_ms - blast.elapsed_ms
	_check(motion.get("from") == Vector2i(2, 1) and motion.get("to") == Vector2i(3, 1),
		"Playback motion uses the actual Smith origin and defeated Bomber landing")
	_check(blast.cue.get("recipients", []).any(func(recipient: Dictionary) -> bool:
		return recipient.get("id") == "blacksmith" and recipient.get("cell") == Vector2i(2, 1) \
			and recipient.get("kind") == "hit"),
		"Bomber impact identifies Smith at the original tile")
	_check(motion_start >= blast_impact,
		"Follow Through starts after Bomber impact: step %.1f ms, blast %.1f ms" % [motion_start, blast_impact])


func _test_ordinary_defeat() -> void:
	var state := _opening(8, true)
	var plan := _action(state)
	if plan.is_empty():
		return
	_check(_unit(plan.result, "blacksmith").position == Vector2i(3, 1)
		and _unit(plan.result, "blacksmith").hp == 8, "Ordinary lethal Hammer follows without blast")
	var timeline := _timeline(state, plan)
	var motions: Array = timeline.get("_motions").filter(
		func(motion: Dictionary) -> bool: return motion.get("unit_id") == "blacksmith")
	var actions: Array = timeline.get("_entries").filter(func(entry: Playback.Entry) -> bool:
		return entry.cue.get("unit_id") == "blacksmith" and entry.cue.get("action_beat", false))
	_check(motions.size() == 1 and actions.size() == 1, "Ordinary Hammer has a scheduled action and step")
	if motions.size() == 1 and actions.size() == 1:
		var impact: float = actions[0].impact_ms - actions[0].elapsed_ms
		var start: float = -motions[0].elapsed_ms
		_check(start >= impact and start <= impact + Playback.BEAT_GAP_MS,
			"Ordinary Follow Through starts promptly after Hammer impact: %.1f vs %.1f ms" % [start, impact])


func _test_chain_blast() -> void:
	var state := _opening(8)
	if state.is_empty():
		return
	# Stock Bomber blast reaches the second Bomber but not the Smith; the
	# second detonation is a real descendant of the initial lethal Hammer.
	_unit(state, "bomber_2").position = Vector2i(4, 1)
	var plan := _action(state)
	if plan.is_empty():
		return
	_check(_unit(plan.result, "bomber_1").hp <= 0 and _unit(plan.result, "bomber_2").hp <= 0
		and _unit(plan.result, "blacksmith").hp == 6
		and _unit(plan.result, "blacksmith").position == Vector2i(3, 1),
		"First Bomber's blast defeats the second while Smith survives and follows")
	_check(plan.events.any(func(event: Dictionary) -> bool:
		return event.get("type") == "damage" and event.get("damage_cause") == "death_blast" \
			and event.get("source_id") == "bomber_1" and event.get("target_id") == "bomber_2"),
		"Second Bomber is actually defeated by the first Bomber's blast")
	var timeline := _timeline(state, plan)
	var motions: Array = timeline.get("_motions").filter(
		func(motion: Dictionary) -> bool: return motion.get("unit_id") == "blacksmith")
	var first: Array = timeline.get("_entries").filter(func(entry: Playback.Entry) -> bool:
		return entry.cue.get("unit_id") == "bomber_1" and entry.cue.get("ordinary_role") == "defeat")
	var second: Array = timeline.get("_entries").filter(func(entry: Playback.Entry) -> bool:
		return entry.cue.get("unit_id") == "bomber_2" and entry.cue.get("ordinary_role") == "defeat")
	_check(motions.size() == 1 and first.size() == 1 and second.size() == 1,
		"Chain playback schedules both real Bomber detonations and one Follow Through")
	if motions.size() != 1 or first.size() != 1 or second.size() != 1:
		return
	var first_impact: float = first[0].impact_ms - first[0].elapsed_ms
	var second_start: float = -second[0].elapsed_ms
	var second_impact: float = second[0].impact_ms - second[0].elapsed_ms
	var motion_start: float = -motions[0].elapsed_ms
	_check(is_equal_approx(second_start, first_impact),
		"Second Bomber detonation begins at its causing first blast impact")
	_check(motions[0].get("from") == Vector2i(2, 1) and motions[0].get("to") == Vector2i(3, 1),
		"Chain Follow Through preserves the original and landing tiles")
	# Only these two causally descended defeats constrain the step; other
	# unrelated future action entries do not form part of this comparison.
	_check(motion_start >= maxf(first_impact, second_impact),
		"Chain Follow Through starts after last Bomber impact: step %.1f ms, first %.1f ms, second %.1f ms" \
			% [motion_start, first_impact, second_impact])


func _test_smith_killed_by_blast() -> void:
	var state := _opening(2)
	var plan := _action(state)
	if plan.is_empty():
		return
	_check(_unit(plan.result, "blacksmith").hp <= 0
		and _unit(plan.result, "blacksmith").position == Vector2i(2, 1),
		"Lethal blast leaves the fallen Smith at the original tile")
	var timeline := _timeline(state, plan)
	_check(not timeline.get("_motions").any(func(motion: Dictionary) -> bool:
		return motion.get("unit_id") == "blacksmith"),
		"Playback never schedules Follow Through for the Smith killed by the blast")


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
