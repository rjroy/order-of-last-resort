extends "res://tests/commission_scene_test.gd"

const DISPLAY_NAMES := {
	"bard": "Bad Bard", "wizard": "Enthusiastic Caster",
	"healer": "Unimpressed Healer", "rogue": "Daft Dodger",
	"knight": "Anxious Knight", "necromancer": "Friendly Crypter",
	"alchemist": "Mixologist"
}

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_book_scene_test.gd
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
	_check(roster.size() == 7 and "blacksmith" not in roster,
		"Artwork does not add Hobby Smith to the seven-person roster")
	_check(_node("Recruit_blacksmith") == null, "Hobby Smith is absent from the legacy recruit controls")
	for id in roster:
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
	await _press("StartAdventure")
	_check(scene.current_screen() == "routes", "Full company opens reports")
	if scene.current_screen() == "routes":
		var run: Dictionary = scene.get("_run")
		var before: Array = []
		var public_copy: Array[String] = []
		var art = load("res://presentation/guild_book_art.gd") if ResourceLoader.exists("res://presentation/guild_book_art.gd") else null
		var expected: Array = []
		for i in run.reports.size():
			var button := _node("Route_%d" % i) as Control
			var card := _item_card(button, "RouteCard_%d" % i)
			var textures := _textures_in(card) if card != null else []
			before.append(textures)
			public_copy.append(_text_in(card) if card != null else "")
			var sketch: Texture2D = art.call("report", str(run.reports[i].mission_id)) if art != null else null
			expected.append(sketch)
			_check(sketch != null and sketch in textures,
				"Report %d shows the sketch for its disclosed immediate mission" % i)
		if expected.size() == 2 and run.reports[0].mission_id != run.reports[1].mission_id:
			_check(expected[0] != null and expected[1] != null and expected[0] != expected[1],
				"Distinct immediate missions have distinct report textures")
		# Find two hidden RNG states that actually draw different continuations
		# under the same disclosed report, rather than merely assuming they do.
		var commissions = load("res://commissions.gd")
		var report: Dictionary = run.reports[0]
		var traversed: Array = run.mission_ids.duplicate()
		traversed.append(report.mission_id)
		var state_a: int = commissions.starting_rng_state(1)
		var future_a: Array = commissions.draw_reports(defs, run.destination_id, false,
			traversed, report.hint_kind, state_a).reports
		var state_b := state_a
		for seed_value in range(2, 100):
			var candidate: int = commissions.starting_rng_state(seed_value)
			var future_b: Array = commissions.draw_reports(defs, run.destination_id, false,
				traversed, report.hint_kind, candidate).reports
			if future_a.map(func(item): return item.mission_id) != future_b.map(func(item): return item.mission_id):
				state_b = candidate
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
				_check(expected[i] != null and expected[i] in before[i],
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
				_check(expected[i] != null and expected[i] in after and after == before[i],
					"Report %d sketch does not disclose hidden continuation" % i)
				_check(_text_in(card) == public_copy[i]
					and str(run.reports[i].description) in public_copy[i]
					and str(run.reports[i].hint_text) in public_copy[i],
					"Report %d print is unchanged when the hidden continuation changes" % i)
	_check(not defs.is_empty(), "Stock catalog remains available")
	_cleanup()


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
