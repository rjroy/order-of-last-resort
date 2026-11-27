extends "res://tests/journeys/commission_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/guild_recruitment_focus_test.gd
# A graphical run with -- --capture-dir=<absolute existing directory> saves the focused states.
const Catalog = preload("res://content/catalog.gd")
const Profile = preload("res://guild/guild_profile.gd")
const PETITIONS := ["recruit_bard", "recruit_rogue", "recruit_necromancer", "recruit_alchemist",
	"teach_healer_blast", "healer_blast_order", "healer_triage_order",
	"knight_rescue_line", "order_knight_advance", "order_healer_aggressive", "wizard_learn_dodge"]


func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	if not _unlock_preparation():
		_cleanup()
		return
	await _launch_normal()
	await _key(KEY_ENTER)
	if scene.current_screen() != "guild":
		_check(false, "Keyboard accepts the focused commission")
		_cleanup()
		return
	var visible_recruits := scene.find_children("Recruit_*", "Button", true, false)
	_check(visible_recruits.size() == 7 and _node("Recruit_blacksmith") == null,
		"The fixture shows its seven purchased or founding heroes, not the unowned Smith")
	if not _check_focus("knight", "Recruit", "First row on entry"):
		_cleanup()
		return
	await _key(KEY_ENTER)
	_check_focus("knight", "Remove", "First row after recruitment")
	var scroll := _node("RecruitScroll") as ScrollContainer
	_check(scroll.scroll_vertical == 0, "Recruiting the first row does not move the list")
	await _key(KEY_ENTER)
	_check_focus("knight", "Recruit", "First row after removal")
	scroll = _node("RecruitScroll") as ScrollContainer
	_check(scroll.scroll_vertical == 0, "Removing the first row does not move the list")

	for step in visible_recruits.size():
		if viewport.gui_get_focus_owner() == _node("Recruit_rogue"):
			break
		await _key(KEY_TAB)
	if not _check_focus("rogue", "Recruit", "Tab reaches the lower recruit"):
		_cleanup()
		return
	await _key(KEY_ENTER)
	_check(scene.selected_recruits() == ["rogue"], "Enter adds the Daft Dodger to the company")
	_check_focus("rogue", "Remove", "After recruiting the Daft Dodger")
	await _capture("01-rogue-recruited")
	await _key(KEY_ENTER)
	_check(scene.selected_recruits().is_empty(), "Enter removes the same hero")
	_check_focus("rogue", "Recruit", "After removing the Daft Dodger")
	await _capture("02-rogue-removed")
	await _check_loadout_focus()
	_cleanup()


func _unlock_preparation() -> bool:
	var earning = load("res://tests/guild/guild_petitions_domain_test.gd").new()
	var profile := Profile.create(profile_path, GUILD_NAME, earning.SEED)
	if profile.has("error"):
		_check(false, "Create disposable guild: " + str(profile))
		earning.free()
		return false
	var fixture: Dictionary = earning._fixture()
	var defs := Catalog.read_default()
	# Four controlled commissions pay for the real petitions without editing the save.
	for index in 4:
		var run: Dictionary = earning._run_commission(fixture, profile, 10, 2)
		profile = Profile.settle_return(profile_path, profile, run, earning.SEED + 1)
		if not profile.has("error") and index < 3:
			profile = Profile.renew(profile_path, profile, earning.SEED)
		if profile.has("error"):
			break
	earning.free()
	if profile.has("error"):
		_check(false, "Settle the controlled outings: " + str(profile))
		return false
	for id in PETITIONS:
		profile = Profile.purchase(profile_path, profile, defs, id)
		if profile.has("error"):
			_check(false, "Purchase " + id + ": " + str(profile))
			return false
	return true


func _check_loadout_focus() -> void:
	for id in ["knight", "healer", "wizard"]:
		if not await _tab_to("Recruit_" + id):
			return
		await _key(KEY_ENTER)
	if not await _tab_to("EditHero_healer"):
		return
	await _key(KEY_ENTER)
	if not await _tab_to("Offense_wizard_blast"):
		return
	await _key(KEY_ENTER)
	_check_loadout_target("Order_order_support", "Selected", "Equipping Blast with Support")
	await _capture("03-blast-support-focused")
	_check(_saved_loadout("healer").get("slots", {}).get("offense") == "wizard_blast"
		and _saved_loadout("healer").get("order_id") == "order_support",
		"Blast is saved with the unchanged compatible Support order")
	var pursuit := _node("Order_order_aggressive") as Button
	_check(pursuit != null and pursuit.disabled and pursuit.text == "Requires Bonk",
		"Pursue and bonk stays incompatible with Blast")

	if not await _tab_to("Order_order_healer_triage"):
		return
	var triage := _node("Order_order_healer_triage") as Button
	var support := _node("Order_order_support") as Button
	var depart := _node("StartAdventure") as Button
	_check(triage != null and not triage.disabled and support != null and not support.disabled
		and depart != null and not depart.disabled
		and _saved_loadout("healer").get("slots", {}).get("utility") == "healer_heal",
		"Base Heal allows both Support and purchased Triage without blocking departure")
	await _capture("04-triage-focused")
	await _key(KEY_ENTER)
	var recruit_list := _node("RecruitList") as Button
	_check(recruit_list != null and recruit_list.has_focus() and not recruit_list.disabled,
		"Selecting Triage returns keyboard focus to the available recruits control")
	_check(_saved_loadout("healer").get("slots", {}).get("utility") == "healer_heal"
		and _saved_loadout("healer").get("order_id") == "order_healer_triage",
		"Choosing Triage saves it with base Heal")

	# A second utility choice makes the Caster's already-equipped Pull selectable.
	if not await _tab_to("EditHero_wizard"):
		return
	await _key(KEY_ENTER)
	if not await _tab_to("Utility_wizard_pull"):
		return
	var pull := _node("Utility_wizard_pull") as Button
	var wizard_scroll := _node("LoadoutScroll") as ScrollContainer
	if wizard_scroll == null or pull == null:
		return
	wizard_scroll.scroll_vertical = 43
	await process_frame
	await process_frame
	_check(_reachable(pull) and pull.has_focus(),
		"The equipped Pull starts in view at the test reading position")
	var previous := wizard_scroll.scroll_vertical
	await _key(KEY_ENTER)
	_check_loadout_target("Utility_wizard_pull", "Equipped", "Reactivating visible Pull")
	wizard_scroll = _node("LoadoutScroll") as ScrollContainer
	_check(wizard_scroll != null and previous > 0 and wizard_scroll.scroll_vertical == previous,
		"Reactivating an already-visible loadout control does not jump back to the top")

	if not await _tab_to("EditHero_knight"):
		return
	await _key(KEY_ENTER)
	var scroll := _node("LoadoutScroll") as ScrollContainer
	_check(scroll != null and scroll.scroll_vertical == 0, "Switching to the Knight opens a fresh loadout at the top")
	if not await _tab_to("Offense_knight_rescue_line"):
		return
	await _key(KEY_ENTER)
	_check_loadout_target("Order_order_guard", "Selected", "Equipping Rescue Line")
	var guard := _node("Order_order_guard") as Button
	depart = _node("StartAdventure") as Button
	_check(guard != null and not guard.disabled and depart != null and not depart.disabled
		and _saved_loadout("knight").get("slots", {}).get("offense") == "knight_rescue_line"
		and _saved_loadout("knight").get("slots", {}).get("utility") == "knight_aura",
		"Rescue Line keeps Guard and Aura and saves without blocking departure")
	await _capture("05-rescue-line-focused")


func _saved_loadout(hero: String) -> Dictionary:
	return Profile.load_profile(profile_path).get("preferred_loadouts", {}).get(hero, {})


func _check_loadout_target(node_name: String, caption: String, context: String) -> void:
	var action := _node(node_name) as Button
	var scroll := _node("LoadoutScroll") as ScrollContainer
	_check(action != null and action.has_focus() and not action.disabled and action.text == caption,
		"%s: focus remains on %s" % [context, node_name])
	if scroll == null or action == null:
		return
	var view := scroll.get_global_rect()
	var bounds := action.get_global_rect()
	_check(view.encloses(bounds), "%s: focused button y %.0f..%.0f is visible in y %.0f..%.0f (scroll %d)" %
		[context, bounds.position.y, bounds.end.y, view.position.y, view.end.y, scroll.scroll_vertical])


func _tab_to(node_name: String) -> bool:
	var action := _node(node_name) as Button
	if action == null or action.disabled:
		_check(false, node_name + " is available to the keyboard")
		return false
	for step in 36:
		if action.has_focus():
			_check(_reachable(action), node_name + " is visible before Enter")
			return true
		await _key(KEY_TAB)
	_check(false, "Tab could not reach " + node_name)
	return false


func _check_focus(hero: String, caption: String, context: String) -> bool:
	var scroll := _node("RecruitScroll") as ScrollContainer
	var action := _node("Recruit_" + hero) as Button
	var focused := action != null and action.text == caption and action.has_focus()
	_check(focused, context + ": focus remains on " + caption + " " + hero)
	if not focused or scroll == null:
		return false
	var view := scroll.get_global_rect()
	var button_rect := action.get_global_rect()
	var visible := view.encloses(button_rect)
	_check(visible, "%s: button y %.0f–%.0f is visible inside list y %.0f–%.0f (scroll %d)"
		% [context, button_rect.position.y, button_rect.end.y, view.position.y, view.end.y, scroll.scroll_vertical])
	return visible


func _key(code: int) -> void:
	for down in [true, false]:
		var input := InputEventKey.new()
		input.keycode = code
		input.pressed = down
		viewport.push_input(input, true)
		await process_frame
	for tick in 3:
		await process_frame
