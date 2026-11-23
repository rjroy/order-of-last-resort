extends "res://tests/commission_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_recruitment_focus_test.gd
# A graphical run with -- --capture-dir=<absolute existing directory> saves both toggle states.
const Catalog = preload("res://content/catalog.gd")
const Profile = preload("res://guild_profile.gd")
const PETITIONS := ["recruit_bard", "recruit_rogue", "recruit_necromancer", "recruit_alchemist"]


func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	if not _unlock_roster():
		_cleanup()
		return
	await _launch_normal()
	await _key(KEY_ENTER)
	if scene.current_screen() != "guild":
		_check(false, "Keyboard accepts the focused commission")
		_cleanup()
		return
	var visible_recruits := scene.find_children("Recruit_*", "Button", true, false)
	_check(visible_recruits.size() == 7, "The fixture shows all seven available recruits")
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
	_cleanup()


func _unlock_roster() -> bool:
	var profile := Profile.create(profile_path, GUILD_NAME, BOARD_SEED)
	if profile.has("error"):
		_check(false, "Create disposable guild: " + str(profile))
		return false
	var earning = load("res://tests/guild_petitions_domain_test.gd").new()
	var fixture: Dictionary = earning._fixture()
	var defs := Catalog.read_default()
	# The earning driver starts from its own seed. Return to that seed between
	# two controlled victories to buy every recruit without editing a save.
	var first: Dictionary = earning._run_commission(fixture, profile, 10, 2)
	profile = Profile.settle_return(profile_path, profile, first, earning.SEED + 1)
	if not profile.has("error"):
		profile = Profile.renew(profile_path, profile, earning.SEED)
	if not profile.has("error"):
		var second: Dictionary = earning._run_commission(fixture, profile, 10, 2)
		profile = Profile.settle_return(profile_path, profile, second, earning.SEED + 1)
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
