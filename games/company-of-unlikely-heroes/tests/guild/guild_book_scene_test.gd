extends "res://tests/journeys/commission_scene_test.gd"

const DISPLAY_NAMES := {
	"bard": "Bad Bard", "wizard": "Enthusiastic Caster",
	"healer": "Unimpressed Healer", "rogue": "Daft Dodger",
	"knight": "Anxious Knight", "necromancer": "Friendly Crypter",
	"alchemist": "Mixologist"
}

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/guild_book_scene_test.gd
func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	# A valid v1 guild retains the original seven recruits after migration.
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		_check(false, "Create disposable legacy profile")
		_cleanup()
		return
	file.store_string('{"version":1,"name":"The Test Company","board_seed":"147258"}')
	file.close()
	await _launch_normal()
	for i in 3:
		var button := _node("Commission_%d" % i) as Control
		var card := _item_card(button, "CommissionCard_%d" % i)
		_check(card != null and not _textures_in(card).is_empty(),
			"Commission %d shows destination artwork" % i)
	await _press("Commission_0")
	var defs: Dictionary = scene.get("_definitions")
	var roster: Array = defs.commission_settings.recruitment_roster
	var legacy_roster := ["knight", "healer", "wizard", "alchemist", "rogue", "necromancer", "bard"]
	_check(roster == legacy_roster + ["blacksmith"],
		"Stock charter eligibility includes the seven legacy heroes and Hobby Smith")
	_check(_node("Recruit_blacksmith") == null, "Hobby Smith is absent from the legacy recruit controls")
	for id in legacy_roster:
		var button := _node("Recruit_" + str(id)) as Control
		_check(button != null and button.is_visible_in_tree(),
			"Legacy recruit %s has a visible control" % id)
		var entry := _item_card(button, "RecruitCard_" + id)
		_check(entry != null and not _textures_in(entry).is_empty(),
			"Recruit %s shows a portrait" % id)
		if entry != null:
			_check(DISPLAY_NAMES[id] in _text_in(entry),
				"Recruit %s shows its requested class name" % id)
	# Continue through the stock commission recruitment page.
	for id in PARTY:
		await _press("Recruit_" + id)
	var extra := _node("Recruit_wizard") as BaseButton
	_check(extra != null and extra.disabled, "Party size cap still disables unselected recruits")
	_check(scene.selected_recruits() == PARTY, "Portraits do not alter selected IDs or order")
	_test_report_plate_policy()
	await _press("StartAdventure")
	_check(scene.current_screen() == "routes", "Full company opens reports")
	if scene.current_screen() == "routes":
		var run: Dictionary = scene.get("_run")
		var before: Array = []
		var public_copy: Array[String] = []
		var art = load("res://presentation/book/guild_book_art.gd") if ResourceLoader.exists("res://presentation/book/guild_book_art.gd") else null
		var expected: Array = []
		for i in run.reports.size():
			var button := _node("Route_%d" % i) as Control
			var card := _item_card(button, "RouteCard_%d" % i)
			var textures := _textures_in(card) if card != null else []
			before.append(textures)
			public_copy.append(_text_in(card) if card != null else "")
			var sketch := _expected_report_sketch(defs, art, str(run.reports[i].mission_id))
			expected.append(sketch)
			if sketch != null:
				_check(sketch in textures, "Report %d shows its disclosed immediate sketch" % i)
		# Find two hidden RNG states that actually draw different continuations
		# under the same disclosed report, rather than merely assuming they do.
		var commissions = load("res://expedition/commissions.gd")
		var state_a: int = commissions.starting_rng_state(1)
		var state_b := state_a
		for report: Dictionary in run.reports:
			var traversed: Array = run.mission_ids.duplicate()
			traversed.append(report.mission_id)
			var future_a: Array = commissions.draw_reports(defs, run.destination_id, false,
				traversed, report.hint_kind, state_a).reports
			for seed_value in range(2, 100):
				var candidate: int = commissions.starting_rng_state(seed_value)
				var future_b: Array = commissions.draw_reports(defs, run.destination_id, false,
					traversed, report.hint_kind, candidate).reports
				if future_a.map(func(item): return item.mission_id) != future_b.map(func(item): return item.mission_id):
					state_b = candidate
					break
			if state_a != state_b:
				break
		_check(state_a != state_b, "Fixture identifies genuinely different hidden future missions")
		run.route_rng_state = state_a
		scene.call("_show_routes")
		await process_frame
		for i in before.size():
			var button := _node("Route_%d" % i) as Control
			var card := _item_card(button, "RouteCard_%d" % i)
			_check(card != null, "Report %d retains its card before hidden future changes" % i)
			if card != null:
				before[i] = _textures_in(card)
				if expected[i] != null:
					_check(expected[i] in before[i],
						"Report %d uses the disclosed sketch before hidden future changes" % i)
		run.route_rng_state = state_b
		scene.call("_show_routes")
		await process_frame
		for i in before.size():
			var button := _node("Route_%d" % i) as Control
			var card := _item_card(button, "RouteCard_%d" % i)
			_check(card != null, "Report %d retains its card after hidden future changes" % i)
			if card != null:
				var after := _textures_in(card)
				_check(after == before[i] and (expected[i] == null or expected[i] in after),
					"Report %d sketch does not disclose hidden continuation" % i)
				_check(_text_in(card) == public_copy[i]
					and str(run.reports[i].description) in public_copy[i]
					and str(run.reports[i].hint_text) in public_copy[i],
					"Report %d print is unchanged when the hidden continuation changes" % i)
	_check(not defs.is_empty(), "Stock catalog remains available")
	# Add the Smith to this disposable migrated profile, then exercise the actual
	# recruitment and loadout pages rather than only the artwork resolver.
	var store = load("res://guild/guild_profile.gd")
	var profile: Dictionary = store.load_profile(profile_path)
	profile.recruited_ids.append("blacksmith")
	profile.version = store.FORMAT_VERSION
	for field in ["board_seed", "board_generation", "points"]:
		profile[field] = str(profile[field])
	var smith_file := FileAccess.open(profile_path, FileAccess.WRITE)
	if smith_file == null:
		_check(false, "Write disposable Smith profile")
	else:
		smith_file.store_string(JSON.stringify(profile))
		smith_file.close()
		await _launch_normal()
		_check(scene.current_screen() == "commissions", "Smith fixture opens the commission board")
		await _press("Commission_0")
		var smith_card := _item_card(_node("Recruit_blacksmith") as Control, "RecruitCard_blacksmith")
		var smith_portrait: Texture2D = load("res://presentation/book/guild_book_art.gd").class_portrait("blacksmith")
		_check(smith_card != null and smith_portrait != null and smith_portrait in _textures_in(smith_card),
			"Recruited Hobby Smith shows the accepted portrait on the recruitment page")
		await _press("Recruit_blacksmith")
		await _press("EditHero_blacksmith")
		var loadout := _node("LoadoutHero")
		_check(loadout != null and smith_portrait in _textures_in(scene),
			"Hobby Smith loadout page shows the accepted portrait")
	_cleanup()


func _test_report_plate_policy() -> void:
	var art = load("res://presentation/book/guild_book_art.gd")
	var original_defs: Dictionary = scene.get("_definitions")
	var original_builtin: bool = scene.get("_uses_builtin_catalog")
	# Synthetic identities isolate the policy from the stock catalog and its
	# tuning. The two real IDs supply packaged sketches, not mission data.
	scene.set("_definitions", {"missions": {
		"harpoon_squad": {"encounter": "base_encounter"},
		"test_same_encounter": {"encounter": "base_encounter", "base_mission_id": "harpoon_squad"},
		"test_changed_encounter": {"encounter": "changed_encounter", "base_mission_id": "harpoon_squad"},
		"test_new_encounter": {"encounter": "changed_encounter"},
		"bridge_patrol": {"encounter": "changed_encounter", "base_mission_id": "harpoon_squad"},
	}})
	scene.set("_uses_builtin_catalog", true)
	var base_sketch: Texture2D = art.report("harpoon_squad")
	var exact_sketch: Texture2D = art.report("bridge_patrol")
	_check(base_sketch != null and exact_sketch != null and base_sketch != exact_sketch,
		"Policy fixture has two distinct packaged original sketches")
	_check(scene.call("_report_plate", "test_same_encounter") == base_sketch and base_sketch != null,
		"Same-encounter variant inherits its disclosed base sketch")
	_check(scene.call("_report_plate", "test_changed_encounter") == null,
		"Changed-encounter variant without exact art is text-only")
	_check(scene.call("_report_plate", "test_new_encounter") == null,
		"New encounter without exact art is text-only")
	_check(scene.call("_report_plate", "bridge_patrol") == exact_sketch and exact_sketch != null,
		"Exact variant sketch wins even when its encounter differs from the base")
	scene.set("_uses_builtin_catalog", false)
	_check(scene.call("_report_plate", "bridge_patrol") == null
		and scene.call("_report_plate", "test_same_encounter") == null,
		"Custom catalogs do not inherit stock report art")
	scene.set("_definitions", original_defs)
	scene.set("_uses_builtin_catalog", original_builtin)


func _expected_report_sketch(defs: Dictionary, art: Script, id: String) -> Texture2D:
	if art == null:
		return null
	var exact: Texture2D = art.call("report", id)
	if exact != null:
		return exact
	var mission: Dictionary = defs.get("missions", {}).get(id, {})
	var base := str(mission.get("base_mission_id", ""))
	var base_mission: Dictionary = defs.get("missions", {}).get(base, {})
	if not base.is_empty() and mission.get("encounter") == base_mission.get("encounter"):
		return art.call("report", base)
	return null


func _textures_in(node: Node) -> Array:
	var result: Array = []
	if node is TextureRect and node.is_visible_in_tree() and node.texture != null:
		var texture: Texture2D = node.texture
		while texture is AtlasTexture:
			texture = texture.atlas
		if texture != null:
			result.append(texture)
	for child in node.get_children():
		result.append_array(_textures_in(child))
	return result


func _item_card(button: Control, card_name: String) -> Control:
	if button == null:
		return null
	var named := _node(card_name) as Control
	if named != null and named.is_ancestor_of(button):
		return named
	var parent := button.get_parent()
	while parent != null and parent != scene:
		if parent is PanelContainer:
			return parent
		parent = parent.get_parent()
	return null


func _text_in(node: Node) -> String:
	var result := ""
	if node is Label or node is BaseButton:
		result = node.text + "\n"
	for child in node.get_children():
		result += _text_in(child)
	return result
