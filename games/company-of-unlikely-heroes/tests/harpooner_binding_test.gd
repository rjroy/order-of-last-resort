extends SceneTree
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/harpooner_binding_test.gd

const Rules = preload("res://rules.gd")
const Catalog = preload("res://content/catalog.gd")
const Cues = preload("res://presentation/cast_cues.gd")
const Sprites = preload("res://presentation/cast_sprites.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var defs: Dictionary = Catalog.read_default()
	var art := Sprites.new()
	art.load_manifest()
	for clip in ["ready", "pursue", "close_thrust", "ranged_cast", "hit", "defeat", "harpoon_projectile"]:
		var item = art.clip_for("harpooner", clip)
		_check(item != null, "Harpooner has packaged " + clip)
		if item != null:
			_check(Sprites.load_texture(item.path) != null, clip + " loads without an editor import")
	var close = art.clip_for("harpooner", "close_thrust")
	var ranged = art.clip_for("harpooner", "ranged_cast")
	if close != null:
		_check(8 in close.source_frames, "Close thrust includes contact F8")
	if ranged != null:
		_check(11 in ranged.source_frames and ranged.release_clip == "harpoon_projectile"
			and is_equal_approx(ranged.release_ms, ranged.time_at_source_frame(11)),
			"Ranged cast releases the detached harpoon at F11")

	var placements := 0
	for mission in ["bridge_patrol", "company_rescue", "harpoon_squad", "explosive_situation"]:
		var state: Dictionary = Rules.open_mission(defs, mission, ["knight", "healer", "wizard"])
		_check(not state.is_empty(), mission + " opens with the stock party")
		for unit: Dictionary in state.get("units", []):
			if unit.get("character_id") != "harpooner":
				continue
			placements += 1
			_check(Cues.cast_key_for(state, unit) == "harpooner",
				"%s runtime instance %s binds Harpooner art" % [mission, unit.id])
	_check(placements >= 4, "Stock missions contain Harpooner placements")

	# A custom character which happens to share the old fallback art is not a
	# stock Harpooner, and changing the stock character's visual identity must
	# not silently install the authored sprite either.
	var custom := defs.duplicate(true)
	custom.characters["custom_spearman"] = custom.characters.harpooner.duplicate(true)
	custom.characters.custom_spearman.erase("cast_key")
	custom.characters.custom_spearman.erase("cast_art_key")
	var altered: Dictionary = Rules.open_mission(custom, "company_rescue", ["knight", "healer", "wizard"])
	var actor: Dictionary = {}
	for unit: Dictionary in altered.units:
		if unit.id == "harpooner":
			actor = unit
			break
	if actor.is_empty():
		_check(false, "Stock rescue Harpooner exists")
	else:
		actor.character_id = "custom_spearman"
		_check(Cues.cast_key_for(altered, actor).is_empty(), "Custom fallback does not inherit the sprite")
		_check(_custom_binding(defs, "art_key", "custom_art").is_empty(),
			"Customized art does not inherit stock sprite")
		_check(_custom_binding(defs, "art_variant", "custom_spear").is_empty(),
			"Customized variant does not inherit stock sprite")
	if failures.is_empty():
		print("PASS: Harpooner asset bindings")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _custom_binding(defs: Dictionary, field: String, value: String) -> String:
	var custom := defs.duplicate(true)
	custom.characters.harpooner[field] = value
	var state: Dictionary = Rules.open_mission(custom, "company_rescue", ["knight", "healer", "wizard"])
	for unit in state.units:
		if unit.id == "harpooner":
			return Cues.cast_key_for(state, unit)
	return "missing"
