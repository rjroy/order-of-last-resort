extends "res://tests/journeys/guild_first_paths_scene_test.gd"

# Headless: godot --headless --path games/company-of-unlikely-heroes --script res://tests/journeys/guild_petitions_walkthrough_test.gd
# Visual evidence: run with a graphical display and -- --capture-dir=/absolute/existing/directory
# Each path is funded by four real controlled road victories and a forfeit.

func _run() -> void:
	var expected_dir := OS.get_environment("TEST_EXPECTED_USER_DIR")
	if not expected_dir.is_empty() and (OS.get_user_data_dir().simplify_path() != expected_dir.simplify_path()
			or ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/") != expected_dir.simplify_path().trim_suffix("/")):
		printerr("Refusing fixture with unexpected user data directory: " + OS.get_user_data_dir())
		quit(1)
		return
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	var store = load("res://guild/guild_profile.gd")
	var adv = load("res://expedition/adventure.gd")
	for method in ["settle_return", "balance", "purchase"]:
		if not store.has_method(method):
			_check(false, "Walkthrough requires GuildProfile." + method)
			_cleanup()
			return
	if not adv.has_method("start_guild_commission") or not adv.has_method("receipt"):
		_check(false, "Walkthrough requires guild commission and receipt")
		_cleanup()
		return
	var fixture = load("res://tests/guild/guild_petitions_domain_test.gd").new()
	var defs: Dictionary = fixture._fixture()
	var paths: Array[String] = []
	for purchase_id in ["recruit_bard", "teach_healer_blast", "recruit_rogue", "knight_rescue_line"]:
		profile_path = "user://petition_walkthrough_%d_%d_%s.json" % [
			OS.get_process_id(), Time.get_ticks_usec(), purchase_id]
		paths.append(profile_path)
		var profile: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
		var run: Dictionary = fixture._run_commission(defs, profile, 4, 0)
		if run.is_empty():
			_check(false, purchase_id + ": controlled earning fixture completed: " + str(fixture.failures))
			continue
		var receipt: Dictionary = adv.receipt(run)
		_check(receipt.get("road_points") == 4 and receipt.get("destination_points") == 0
			and receipt.get("points") == 4, purchase_id + ": legitimate return earns four")
		store.settle_return(profile_path, profile, run, BOARD_SEED + 1)
		profile = store.load_profile(profile_path)
		if store.balance(profile) != 4:
			_check(false, purchase_id + ": return persisted four points")
			continue
		await _launch_normal()
		for board_size in [Vector2i(1280, 820), Vector2i(960, 615)]:
			viewport.size = board_size
			await _launch_normal()
			await _check_petitions_entry("funded")
			if purchase_id == "recruit_bard":
				await _check_register_reentry(board_size)
				await _check_full_petition_board(board_size)
		viewport.size = VIEWPORT_SIZE
		await _launch_normal()
		await _press("Petitions")
		await _capture(purchase_id + "_credited_petitions")
		await _click_petition(purchase_id)
		await _capture(purchase_id + "_petition_detail")
		var buy := _node("PurchasePetition_" + purchase_id) as BaseButton
		if buy == null or buy.disabled or not buy.is_visible_in_tree():
			_check(false, purchase_id + ": purchase button is visible and enabled")
			continue
		await _settlement_click(buy.get_global_rect().get_center())
		var bought: Dictionary = store.load_profile(profile_path)
		_check(store.balance(bought) == 0, purchase_id + ": GUI purchase spends four points")
		var owned_buy := _node("PurchasePetition_" + purchase_id) as BaseButton
		_check(owned_buy != null and owned_buy.disabled,
			purchase_id + ": purchased selection cannot be purchased twice")
		# Relaunch follows the ordinary commission entry instead of assuming a
		# private back-navigation or page-model implementation.
		await _launch_normal()
		await _press("Commission_0")
		if purchase_id == "recruit_bard":
			for id in ["knight", "bard", "wizard"]:
				await _press("Recruit_" + id)
			_check(scene.selected_recruits() == ["knight", "bard", "wizard"],
				"Bard is a selectable alternative within the three-hero party")
		elif purchase_id == "recruit_rogue":
			for id in ["knight", "rogue", "wizard"]:
				await _press("Recruit_" + id)
			_check(scene.selected_recruits() == ["knight", "rogue", "wizard"],
				"Purchased Rogue is selectable in the three-hero party")
			await _press("EditHero_rogue")
			var blame := _node("Order_order_pass_the_blame") as BaseButton
			_check(blame != null and not blame.disabled,
				"Recruited Rogue has the native Pass the Blame order")
		elif purchase_id == "knight_rescue_line":
			for id in FOUNDERS:
				await _press("Recruit_" + id)
			await _press("EditHero_knight")
			await _click_loadout("Utility_knight_rescue_line")
			var guard := _node("Order_order_guard") as BaseButton
			var advance := _node("Order_order_advance") as BaseButton
			_check(guard == null or guard.disabled,
				"Guard is incompatible with Rescue Line replacing the aura")
			_check(advance != null and not advance.disabled,
				"Advance remains compatible with Rescue Line")
			var order_focus := viewport.gui_get_focus_owner() as BaseButton
			_check(order_focus != null and str(order_focus.name).begins_with("Order_")
				and not order_focus.disabled and order_focus != guard,
				"Invalidating Guard moves keyboard focus to a compatible standing order")
			await _click_loadout("Order_order_advance")
		else:
			for id in FOUNDERS:
				await _press("Recruit_" + id)
			await _press("EditHero_healer")
			await _press("Offense_wizard_blast")
			await _press("Order_order_support")
			var pursuit := _node("Order_order_aggressive") as BaseButton
			_check(pursuit == null or not pursuit.is_visible_in_tree() or pursuit.disabled,
				"Bonk pursuit is unavailable while Blast is equipped")
			var automatic := _node("Order_order_blast") as BaseButton
			_check(automatic == null or not automatic.is_visible_in_tree() or automatic.disabled,
				"Teaching Blast does not grant Wizard automatic Blast")
		await _capture(purchase_id + "_recruitment")
		await _press("StartAdventure")
		if scene.current_screen() != "routes":
			_check(false, purchase_id + ": prepared party can depart")
			continue
		await _press("Route_1" if purchase_id == "knight_rescue_line" else "Route_0")
		if scene.current_screen() != "battle":
			_check(false, purchase_id + ": next mission deploys")
			continue
		var state: Dictionary = scene.battle_snapshot()
		var rules = load("res://rules/rules.gd").new()
		if purchase_id == "recruit_bard":
			_check("bard" in state.get("party", []) and state.get("party", []).size() == 3,
				"Unlocked Bard deploys in the three-person party")
			var bard: Dictionary = rules.entity_profile(state, "bard")
			_check("inspiring_melody" in bard.get("abilities", [])
				and "healing_sonnet" in bard.get("abilities", []),
				"Deployed Bard has both base songs")
		elif purchase_id == "recruit_rogue":
			_check("rogue" in state.get("party", []), "Purchased Rogue deploys")
			var rogue: Dictionary = rules.entity_profile(state, "rogue")
			_check(rogue.get("habits", {}).has("order_pass_the_blame"),
				"Deployed Rogue retains Pass the Blame")
		elif purchase_id == "knight_rescue_line":
			var knight: Dictionary = rules.entity_profile(state, "knight")
			_check("knight_rescue_line" in knight.get("abilities", []),
				"Equipped Rescue Line reaches the actual battle")
			await _command_rescue(state, rules)
		else:
			var healer: Dictionary = rules.entity_profile(state, "healer")
			var wizard: Dictionary = rules.entity_profile(state, "wizard")
			_check("wizard_blast" in healer.get("abilities", [])
				and "healer_bonk" not in healer.get("abilities", [])
				and "healer_heal" in healer.get("abilities", []),
				"Equipped Healer deploys Blast and Heal, not Bonk")
			_check("wizard_blast" in wizard.get("abilities", []), "Wizard retains Blast")
			await _command_blast(state)
		await _capture(purchase_id + "_mission")
	profile_path = "user://petition_walkthrough_%d_%d_song.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	paths.append(profile_path)
	await _check_purchased_song(store)
	fixture.free()
	for path in paths:
		for owned_path in [path, path + ".backup"]:
			if FileAccess.file_exists(owned_path):
				_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(owned_path)) == OK,
					"Remove disposable walkthrough profile file " + owned_path)
	_finish()


func _check_register_reentry(board_size: Vector2i) -> void:
	var context := "Register selection at %s" % board_size
	for tick in 3:
		await process_frame
	var initial := _selected_petition()
	_check(not initial.is_empty(), context + ": fresh register selects a petition")
	_check_selected_slip_visible(initial, context + ": fresh open")
	await _key_action("ui_end")
	for tick in 3:
		await process_frame
	var distant := _selected_petition()
	_check(not distant.is_empty() and distant != initial,
		context + ": keyboard End selects a distant petition")
	_check_selected_slip_visible(distant, context + ": after distant selection")
	var back := _node("BackToCommissions") as BaseButton
	if back == null or back.disabled:
		_check(false, context + ": back action is available")
		return
	await _settlement_click(back.get_global_rect().get_center())
	for tick in 3:
		await process_frame
	var entry := _node("Petitions") as BaseButton
	_check(entry != null and viewport.gui_get_focus_owner() == entry,
		context + ": returning to commissions focuses Guild petitions")
	if entry == null or entry.disabled:
		_check(false, context + ": petition entry remains available")
		return
	await _settlement_click(entry.get_global_rect().get_center())
	for tick in 3:
		await process_frame
	_check(_selected_petition() == distant, context + ": reopening retains the selected petition")
	_check_selected_slip_visible(distant, context + ": after reopening")


func _check_selected_slip_visible(selected: String, context: String) -> void:
	_check(_selected_slip_visible(selected),
		context + ": selected slip is fully inside the register clip without test scrolling")


func _selected_slip_visible(selected: String) -> bool:
	var scroll := _node("PetitionScroll") as ScrollContainer
	var slip := _node("PetitionSlip_" + selected.trim_prefix("Petition_")) as Control
	return (scroll != null and slip != null and slip.is_visible_in_tree()
		and slip.get_global_rect().has_area()
		and scroll.get_global_rect().grow(1.0).encloses(slip.get_global_rect()))


func _check_full_petition_board(board_size: Vector2i) -> void:
	var context := "Full petition board at %s" % board_size
	var scroll := _node("PetitionScroll") as ScrollContainer
	_check(scroll != null, context + ": register has a scroll container")
	if scroll == null:
		return
	var cards: Array[BaseButton] = []
	for node in scroll.find_children("Petition_*", "BaseButton", true, false):
		cards.append(node as BaseButton)
	_check(cards.size() == 29, context + ": all 29 catalog petitions are present")
	for id in ["recruit_bard", "recruit_rogue", "recruit_necromancer",
			"recruit_alchemist", "teach_healer_blast", "song_weaving",
			"recruit_blacksmith", "blacksmith_learn_bonk", "blacksmith_learn_acid"]:
		_check(_node("Petition_" + id) is BaseButton, context + ": card exists for " + id)
	if cards.is_empty():
		return
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
		context + ": the full register can scroll")
	for card in cards:
		scroll.ensure_control_visible(card)
		await process_frame
		_check(scroll.get_global_rect().grow(1.0).encloses(card.get_global_rect()),
			context + ": card can be scrolled into view: " + card.name)
	# A register may use one tab stop and arrow-key selection, or ordinary
	# focusable buttons. Exercise the actual keyboard without prescribing either.
	scroll.ensure_control_visible(cards[0])
	cards[0].grab_focus()
	await process_frame
	var initial_name := str(cards[0].name)
	var initial_focus := viewport.gui_get_focus_owner()
	var initial_focus_name := str(initial_focus.name) if initial_focus != null else ""
	var initial_selected := _selected_petition()
	for action in ["ui_down", "ui_focus_next"]:
		for down in [true, false]:
			var event := InputEventAction.new()
			event.action = action
			event.pressed = down
			viewport.push_input(event, true)
			await process_frame
		var focus := viewport.gui_get_focus_owner()
		if (focus != null and str(focus.name) != initial_focus_name) \
				or _selected_petition() != initial_selected:
			break
	var focus := viewport.gui_get_focus_owner()
	_check((focus != null and str(focus.name) != initial_focus_name) or _selected_petition() != initial_selected,
		context + ": keyboard can move from the first register entry")
	_check(_node(initial_name) != null, context + ": register remains available after keyboard navigation")
	scroll = _node("PetitionScroll") as ScrollContainer
	var song := _node("Petition_song_weaving") as BaseButton
	if scroll == null or song == null:
		_check(false, context + ": current register and Song Weaving remain available")
		return
	scroll.ensure_control_visible(song)
	await process_frame
	await _settlement_click(song.get_global_rect().get_center())
	var purchase := _node("PurchasePetition_song_weaving") as BaseButton
	_check(purchase != null and purchase.disabled,
		context + ": Song Weaving cannot be purchased before its prerequisite")
	var detail := ""
	var preview := _node("PetitionPreviewScroll")
	if preview != null:
		for label in preview.find_children("*", "Label", true, false):
			detail += " " + label.text
	if purchase != null:
		detail += " " + purchase.accessibility_description
	_check("bard" in detail.to_lower(),
		context + ": the locked prerequisite is readable")
	await _check_class_filter(context)


func _selected_petition() -> String:
	var scroll := _node("PetitionScroll") as ScrollContainer
	if scroll != null:
		for button: BaseButton in scroll.find_children("Petition_*", "BaseButton", true, false):
			if button.button_pressed:
				return str(button.name)
	return ""


func _check_class_filter(context: String) -> void:
	var filter := _node("PetitionHeroFilter") as OptionButton
	_check(filter != null, context + ": class filter is available")
	if filter == null:
		return
	var bard_index := -1
	var all_index := -1
	var heroes := {}
	for index in filter.item_count:
		var label := filter.get_item_text(index).to_lower()
		var metadata: Variant = filter.get_item_metadata(index)
		var hero := "" if metadata == null else str(metadata)
		if not hero.is_empty():
			heroes[hero] = true
		if "bard" in label:
			bard_index = index
		if "all" in label:
			all_index = index
	_check(heroes.size() == 8 and heroes.has("knight") and heroes.has("bard") \
		and heroes.has("rogue") and heroes.has("blacksmith"),
		context + ": filter offers all eight eligible guild heroes: " + str(heroes))
	_check(bard_index >= 0 and all_index >= 0, context + ": class filter offers Bard and All")
	if bard_index < 0 or all_index < 0:
		return
	await _choose_filter(filter, bard_index)
	_check(_node("Petition_song_weaving") != null and _node("Petition_knight_rescue_line") == null,
		context + ": Bard filter shows Song Weaving but excludes Knight training")
	filter = _node("PetitionHeroFilter") as OptionButton
	if filter == null:
		_check(false, context + ": filter remains available after changing class")
		return
	_check(viewport.gui_get_focus_owner() == filter, context + ": changing class retains keyboard focus on the filter")
	await _choose_filter(filter, all_index)
	_check(_node("Petition_song_weaving") != null and _node("Petition_knight_rescue_line") != null,
		context + ": All restores entries from both classes")


func _choose_filter(filter: OptionButton, index: int) -> void:
	# Exercise the control's real keyboard input, not its item_selected signal.
	filter.grab_focus()
	await process_frame
	await _key_action("ui_accept")
	var popup := filter.get_popup()
	for step in filter.item_count:
		var focused := popup.get_focused_item()
		if focused == index:
			break
		if focused < 0:
			_check(false, "Class filter popup has a focused item")
			return
		await _key_action("ui_down" if focused < index else "ui_up")
	if popup.get_focused_item() != index:
		_check(false, "Class filter keyboard reaches item %d" % index)
		return
	await _key_action("ui_accept")


func _key_action(action: String) -> void:
	for down in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = down
		viewport.push_input(event, true)
		await process_frame


func _check_purchased_song(store: Variant) -> void:
	# This scenario starts with a test-owned nine-point balance so both GUI
	# purchases fit in one profile; earning and receipt behavior is tested above.
	var profile: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	profile.points = 9
	profile = store._write_profile(profile_path, profile)
	if profile.has("error"):
		_check(false, "Create funded Song Weaving fixture: " + str(profile))
		return
	await _launch_normal()
	await _press("Petitions")
	for id in ["recruit_bard", "song_weaving"]:
		await _click_petition(id)
		var buy := _node("PurchasePetition_" + id) as BaseButton
		if buy == null or buy.disabled:
			_check(false, id + ": funded prerequisite path offers a purchase")
			return
		await _settlement_click(buy.get_global_rect().get_center())
		var updated: Dictionary = store.load_profile(profile_path)
		_check(id in updated.get("purchased_ids", []), id + ": GUI purchase persists")
	var song := _node("PurchasePetition_song_weaving") as BaseButton
	_check(song != null and song.disabled, "Purchased Song Weaving remains selected and owned")
	await _launch_normal()
	await _press("Petitions")
	await _click_petition("song_weaving")
	song = _node("PurchasePetition_song_weaving") as BaseButton
	_check(song != null and song.disabled, "Purchased Song Weaving remains a selectable owned card after reload")
	var scroll := _node("PetitionScroll") as ScrollContainer
	if scroll != null:
		_check(scroll.find_children("Petition_*", "BaseButton", true, false).size() == 29,
			"Owned Song Weaving remains in the complete register")


func _click_petition(id: String) -> void:
	var scroll := _node("PetitionScroll") as ScrollContainer
	var card := _node("Petition_" + id) as BaseButton
	if scroll == null or card == null or card.disabled:
		_check(false, id + ": petition card is actionable")
		return
	scroll.ensure_control_visible(card)
	await process_frame
	_check(scroll.get_global_rect().has_point(card.get_global_rect().get_center()),
		id + ": click point is inside the register clip after scrolling")
	await _settlement_click(card.get_global_rect().get_center())
	var selected := _selected_petition() == "Petition_" + id and _node("PurchasePetition_" + id) != null
	_check(selected, id + ": clicking selects its detail")
	if not selected:
		return
	# Wait for the rebuilt register's own layout and scroll, not another test scroll.
	for tick in 3:
		await process_frame
	_check_selected_slip_visible("Petition_" + id, id + ": after clicking")


func _click_loadout(name: String) -> void:
	var scroll := _node("LoadoutScroll") as ScrollContainer
	var button := _node(name) as BaseButton
	if scroll == null or button == null or button.disabled:
		_check(false, name + ": loadout action exists and is enabled")
		return
	scroll.ensure_control_visible(button)
	await process_frame
	await _settlement_click(button.get_global_rect().get_center())


func _command_rescue(state: Dictionary, rules: Variant) -> void:
	if state.get("mission_id") != "last_one_standing":
		_check(false, "Rescue Line fixture deploys last_one_standing")
		return
	var driver = load("res://tests/support/storybook_driver.gd").new(self, scene)
	if not await driver.command("knight", "move", "1,0"):
		_check(false, "Could not stage Knight's setup movement through battle controls: " + driver.error)
		return
	if not await _commit_battle_command("Rescue Line setup movement"):
		return
	if scene.current_screen() != "battle":
		_check(false, "Battle remains active after Rescue Line setup")
		return
	var actual: Dictionary = scene.battle_snapshot()
	var rescue := _rescue_forecast(actual, rules)
	if rescue.is_empty():
		_check(false, "Committed setup creates a legal Rescue Line target")
		return
	_check(rescue.target == "healer" and rescue.target_before == Vector2i(1, 2)
		and rescue.target_after == Vector2i(1, 1) and rescue.knight_before == Vector2i(1, 0),
		"Setup places Knight at (1,0) to pull Healer from (1,2) to (1,1)")
	if not await driver.command("knight", "knight_rescue_line", rescue.target):
		_check(false, "Could not stage Rescue Line through battle controls: " + driver.error)
		return
	if not await _commit_battle_command("Rescue Line"):
		return
	var result: Dictionary = scene.battle_snapshot()
	var target := _battle_unit(result, rescue.target)
	var knight := _battle_unit(result, "knight")
	_check(target.get("position") == rescue.target_after and rescue.target_after != rescue.target_before,
		"Committed Rescue Line moves the chosen ally one tile toward the Knight")
	_check(knight.get("position") == rescue.knight_before and knight.get("hp") == rescue.knight_hp,
		"Committed Rescue Line leaves the Knight in place without recoil damage")


func _rescue_forecast(state: Dictionary, rules: Variant) -> Dictionary:
	var context: Dictionary = rules.state_before_action(state, "knight")
	if not rules.can_act(context, "knight"):
		return {}
	var knight := _battle_unit(context, "knight")
	for target: Dictionary in rules.targets(context, "knight", "knight_rescue_line"):
		var before := _battle_unit(context, str(target.id))
		if before.is_empty() or str(target.id) != "healer":
			continue
		var action: Dictionary = rules.preview(context, "knight", "knight_rescue_line", str(target.id))
		if not action.get("valid", false):
			continue
		var moved := _battle_unit(action.result, str(target.id))
		var actor_after := _battle_unit(action.result, "knight")
		var start_position: Vector2i = before.get("position", Vector2i(-100, -100))
		var end_position: Vector2i = moved.get("position", start_position)
		var origin: Vector2i = knight.get("position", Vector2i(-100, -100))
		if absi(start_position.x - origin.x) + absi(start_position.y - origin.y) != 2 \
				or absi(end_position.x - origin.x) + absi(end_position.y - origin.y) != 1 \
				or actor_after.get("position") != origin or actor_after.get("hp") != knight.get("hp"):
			continue
		var draft: Dictionary = rules.choose_manual(state, "knight", "knight_rescue_line", str(target.id))
		var round_plan: Dictionary = rules.preview_round(draft)
		var final_target := _battle_unit(round_plan.get("result", {}), str(target.id))
		var final_knight := _battle_unit(round_plan.get("result", {}), "knight")
		if round_plan.get("valid", false) and final_target.get("position") == end_position \
				and final_knight.get("position") == origin and final_knight.get("hp") == knight.get("hp"):
			return {"target": str(target.id), "target_before": start_position, "target_after": end_position,
				"knight_before": origin, "knight_hp": knight.get("hp")}
	return {}


func _battle_unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.get("units", []):
		if unit.get("id") == id:
			return unit
	return {}


func _commit_battle_command(description: String) -> bool:
	var plan: Dictionary = scene.get("_plan")
	var commit := _node("Commit") as BaseButton
	if not plan.get("valid", false) or commit == null or commit.disabled or not commit.is_visible_in_tree():
		_check(false, description + ": a legal forecast can be committed")
		return false
	await _settlement_click(commit.get_global_rect().get_center())
	return true


func _command_blast(state: Dictionary) -> void:
	var board := _node("BridgeBoard") as Control
	var position := Vector2i(-1, -1)
	for unit in state.get("units", []):
		if unit.id == "healer":
			position = unit.position
	if board == null or position == Vector2i(-1, -1):
		_check(false, "Healer is visible for direct Blast")
		return
	await _settlement_click(board.get_global_transform_with_canvas() * board.cell_center(position))
	var page: Node = scene.get("_storybook_page")
	page.emit_signal("action_selected", "wizard_blast")
	await process_frame
	var staged: Dictionary = scene.get("_planned_state")
	_check(staged.get("overrides", {}).get("healer", {}).get("ability_id") == "wizard_blast",
		"Player can stage the actual shared Blast as Healer")
	var plan: Dictionary = scene.get("_plan")
	_check(plan.get("valid", false), "Healer Blast has a legal forecast")
	var commit := _node("Commit") as BaseButton
	if commit == null or commit.disabled or not commit.is_visible_in_tree():
		_check(false, "Player can commit the Healer Blast")
		return
	await _settlement_click(commit.get_global_rect().get_center())
	_check(scene.current_screen() in ["battle", "debrief", "result"], "Healer Blast commits in combat")
