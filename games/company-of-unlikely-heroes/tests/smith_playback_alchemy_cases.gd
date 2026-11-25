extends SceneTree
## Native Mixologist inputs for the local battle playback driver.
## Self-check: godot --headless --path games/company-of-unlikely-heroes --script res://tests/smith_playback_alchemy_cases.gd

const Catalog = preload("res://content/catalog.gd")
const Progression = preload("res://guild_progression.gd")
const Rules = preload("res://rules.gd")
const Reactions = preload("res://rules/alchemy_reactions.gd")


static func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.id == id:
			return unit
	return {}


static func _opening(paste: bool = false) -> Dictionary:
	var defs: Dictionary = Catalog.read_default()
	var state: Dictionary = Rules.open_mission(defs, "bridge_patrol",
		["blacksmith", "alchemist", "knight"], 12345)
	if state.is_empty():
		return {}
	if paste:
		var loadout := Progression.playtest_kit(defs, "alchemist", {"offense": "alchemist_etching_paste"})
		if loadout.has("error"):
			return {}
		state["_guild"] = Catalog.FrozenCatalog.new({"kits": {"alchemist": loadout.kit}})
	state.orders.blacksmith = "order_try_this"
	state.orders.alchemist = "order_hold"
	state.orders.knight = "order_hold"
	_unit(state, "blacksmith").position = Vector2i(1, 2)
	_unit(state, "alchemist").position = Vector2i(2, 2)
	_unit(state, "knight").position = Vector2i(2, 3)
	_unit(state, "knight").hp = 2
	_unit(state, "raider_one").position = Vector2i(3, 2)
	_unit(state, "raider_two").position = Vector2i(5, 3)
	# Cosmetic reactions keep the battlefield legible without hiding the real draw.
	for seed_value in range(1, 10000):
		if Reactions.draw(seed_value, false).category == "cosmetic" \
				and Reactions.draw(seed_value, true).category == "cosmetic":
			_unit(state, "alchemist").dose_rng_state = seed_value
			break
	return state


static func _case(id: String, state: Dictionary, target: String, effective: String) -> Dictionary:
	return {"id": id, "state": state, "actor": "alchemist", "ability": id,
		"target": target, "effective": effective}


static func cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var buffer := _opening()
	var bitter := _opening()
	var paste := _opening(true)
	var solvent := _opening()
	var counter := _opening()
	if buffer.is_empty() or bitter.is_empty() or paste.is_empty() or solvent.is_empty() or counter.is_empty():
		return result
	_unit(solvent, "alchemist").upgrades = {"alchemist_spare_vial": 1}
	_unit(counter, "alchemist").upgrades = {"alchemist_keep_the_culture": 1}
	# The bottle comes from an ordinary actual Acid use, before the Smith fits.
	var rules := Rules.new()
	var dose: Dictionary = rules.preview(counter, "alchemist", "alchemist_acid", "raider_one")
	if not dose.get("valid", false):
		return result
	counter = rules.apply_plan(counter, dose)
	if _unit(counter, "alchemist").get("bottled_reaction", {}).is_empty():
		return result
	result.append(_case("alchemist_acid", buffer, "knight", "buffer_solution"))
	result.append(_case("alchemist_potion", bitter, "raider_one", "bitter_medicine"))
	result.append(_case("alchemist_etching_paste", paste, "knight", "sealing_paste"))
	result.append(_case("alchemist_plain_tonic", solvent, "raider_one", "plain_solvent"))
	result.append(_case("alchemist_repeat_batch", counter, "knight", "counterbatch"))
	return result


func _initialize() -> void:
	var failures: Array[String] = []
	var samples := cases()
	if samples.size() != 5:
		failures.append("Five native cases are constructed, including a real Acid bottle")
	var rules := Rules.new()
	for sample: Dictionary in samples:
		var state: Dictionary = sample.state
		var label: String = sample.id
		if _unit(state, sample.actor).has("fitted_by"):
			failures.append(label + ": wearer starts without a fitting")
		var selected: Dictionary = rules.choose_manual(state, sample.actor, sample.ability, sample.target)
		var before := selected.duplicate(true)
		var forecast: Dictionary = rules.preview_round(selected)
		if not forecast.get("valid", false) or selected != before or forecast != rules.preview_round(selected):
			failures.append(label + ": forecast is valid, pure and deterministic")
			continue
		var fits: Array = forecast.events.filter(func(event: Dictionary) -> bool:
			return event.get("type") == "fit" and event.get("target_id") == sample.actor)
		var conversions: Array = forecast.events.filter(func(event: Dictionary) -> bool:
			return event.get("type") == "fitted_conversion" and event.get("unit_id") == sample.actor \
				and event.get("source_ability_id") == sample.ability and event.get("ability_id") == sample.effective)
		if fits.size() != 1 or conversions.size() != 1 \
				or forecast.events.find(fits[0]) >= forecast.events.find(conversions[0]):
			failures.append(label + ": standing Smith fits before the expected conversion")
		if rules.commit_round(selected, forecast) != forecast.result:
			failures.append(label + ": committed round matches forecast")
	if failures.is_empty():
		print("PASS: native Mixologist playback cases")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
