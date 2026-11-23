extends "res://tests/guild_book_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_book_custom_content_test.gd
# Launch an external catalog with colliding IDs but different authored content.
func _run() -> void:
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	container.scale = Vector2(0.5, 0.5)
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	var catalog = load("res://content/catalog.gd")
	var defs: Dictionary = catalog.read_default()
	defs.classes.wizard["guild_portrait"] = "rogue"
	defs.characters["test_custom"] = defs.characters.rogue.duplicate(true)
	defs.characters.test_custom.erase("guild_portrait")
	defs.characters.test_custom.label = "Edda"
	defs.characters["test_namesake"] = defs.characters.test_custom.duplicate(true)
	defs.characters.test_namesake.label = "Bad Bard"
	defs.characters["test_opted_in"] = defs.characters.test_custom.duplicate(true)
	defs.characters.test_opted_in["guild_portrait"] = "rogue"
	var roster_id: String = defs.commission_settings.roster_adventure
	defs.adventures[roster_id].roster.append_array(["test_custom", "test_namesake", "test_opted_in"])
	for id in defs.missions:
		defs.missions[id].title = "Custom mission " + id
	for id in defs.upgrades:
		defs.upgrades[id].label = "Custom upgrade " + id
	# External authored prose is deliberately much longer than stock copy.
	var long_description := "The scout describes a winding road and a remarkable landmark. ".repeat(30).strip_edges()
	for report in defs.mission_reports.values():
		report.descriptors = [long_description]
		if report.has("destination_descriptors"):
			report.destination_descriptors = [long_description]
	for kind in defs.mission_kinds.values():
		kind.descriptors = [long_description]
	var errors: PackedStringArray = catalog.validate(defs)
	if not errors.is_empty():
		_check(false, "Custom catalog fixture validates: " + str(errors))
		_cleanup()
		return
	var fixture := "user://guild_book_custom_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	if file == null:
		_check(false, "Custom catalog fixture can be written")
		_cleanup()
		return
	file.store_string(JSON.stringify(defs))
	file.close()
	var store = load("res://guild_profile.gd")
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Disposable guild can be created: " + str(created))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
		_cleanup()
		return
	scene = load("res://main.tscn").instantiate()
	scene.configure_launch(PackedStringArray(["--content=" + ProjectSettings.globalize_path(fixture)]))
	scene.configure_profile_path(profile_path)
	viewport.add_child(scene)
	await process_frame
	await process_frame
	_check(scene.current_screen() == "commissions", "External catalog opens the normal commission board")
	for i in 3:
		_check_long_copy("CommissionDetails_%d" % i, "Commission_%d" % i, long_description)
	for i in 3:
		var card := _item_card(_node("Commission_%d" % i) as Control, "CommissionCard_%d" % i)
		_check(card != null and _textures_in(card).is_empty(),
			"External destination %d does not inherit stock art from a colliding ID" % i)
	await _press("Commission_0")
	_check(scene.current_screen() == "guild", "External commission opens custom recruitment")
	for id in ["test_custom", "test_namesake"]:
		var custom := _item_card(_node("Recruit_" + id) as Control, "RecruitCard_" + id)
		_check(custom != null, "Custom recruit %s is visible" % id)
		if custom == null:
			continue
		_check(defs.characters[id].label in _text_in(custom), "Custom proper name remains visible")
		_check(_textures_in(custom).is_empty(),
			"Names and inherited base-class portrait do not select stock artwork")
		_check("Daft Dodger" not in _text_in(custom) and "Enthusiastic Caster" not in _text_in(custom),
			"Base-class portrait does not assign a class subtitle")
	var opted := _item_card(_node("Recruit_test_opted_in") as Control, "RecruitCard_test_opted_in")
	_check(opted != null, "Explicitly identified custom recruit is visible")
	if opted != null:
		var portrait: Texture2D = load("res://presentation/guild_book_art.gd").class_portrait("rogue")
		_check("Edda" in _text_in(opted) and "Daft Dodger" in _text_in(opted),
			"Explicit identity adds a class subtitle without replacing the proper name")
		_check(portrait != null and portrait in _textures_in(opted),
			"Explicit identity selects the declared class portrait")
	for id in PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	var run: Dictionary = scene.get("_run")
	if scene.current_screen() == "routes":
		await process_frame
		for i in run.reports.size():
			_check_long_copy("RouteDetails_%d" % i, "Route_%d" % i, long_description)
			var card := _item_card(_node("Route_%d" % i) as Control, "RouteCard_%d" % i)
			_check(card != null and _textures_in(card).is_empty(),
				"External immediate mission %d does not inherit stock report art by ID" % i)
		var mission: String = run.reports[0].mission_id
		await _press("Route_0")
		await _play_battle(mission)
		if scene.current_screen() == "debrief":
			run = scene.get("_run")
			_check(not run.reward_offers.is_empty(), "Custom catalog reaches real reward offers")
			var art = load("res://presentation/guild_book_art.gd")
			for offer in run.reward_offers:
				var card := _item_card(_node("Reward_" + str(offer.hero_id)) as Control,
					"RewardCard_" + str(offer.hero_id))
				var stock_image: Texture2D = art.upgrade(str(offer.upgrade_id))
				_check(card != null and stock_image != null and stock_image not in _textures_in(card),
					"External upgrade %s does not inherit stock art by ID" % offer.upgrade_id)
		else:
			_check(false, "Custom catalog battle reaches reward debrief")
	else:
		_check(false, "Custom catalog recruitment opens routes")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture)) == OK,
		"Custom catalog fixture is removed")
	_cleanup()


func _check_long_copy(scroll_name: String, button_name: String, description: String) -> void:
	var scroll := _node(scroll_name) as ScrollContainer
	var button := _node(button_name) as BaseButton
	_check(button != null and not button.disabled and _reachable(button),
		button_name + " remains fully reachable at 1280x820 with long copy")
	if scroll == null:
		_check(false, scroll_name + " exists for long authored copy")
		return
	_check(description in _text_in(scroll), scroll_name + " contains the complete authored description")
	var bar := scroll.get_v_scroll_bar()
	_check(bar.max_value > bar.page + 1.0, scroll_name + " overflows into a scrollable region")
	scroll.scroll_vertical = int(bar.max_value)
	_check(scroll.scroll_vertical > 0, scroll_name + " can scroll to later copy")
	scroll.scroll_vertical = 0
