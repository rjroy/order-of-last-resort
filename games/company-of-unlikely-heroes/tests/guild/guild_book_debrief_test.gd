extends "res://tests/guild/guild_book_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild/guild_book_debrief_test.gd
# Reach a real stock reward rather than manufacturing a debrief state.
func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The inherited battle driver's real first-round click targets the viewport
	# through a half-scale container, as in its original scene fixture.
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	container.scale = Vector2(0.5, 0.5)
	container.add_child(viewport)
	root.add_child(container)
	var store = load("res://guild/guild_profile.gd")
	var created: Dictionary = store.create(profile_path, GUILD_NAME, BOARD_SEED)
	if created.has("error"):
		_check(false, "Create disposable profile: " + str(created))
		_cleanup()
		return
	await _launch_normal()
	await _press("Commission_0")
	for id in FOUNDER_PARTY:
		await _press("Recruit_" + id)
	await _press("StartAdventure")
	var run: Dictionary = scene.get("_run")
	var reports: Array = run.get("reports", [])
	if scene.current_screen() != "routes" or reports.is_empty():
		_check(false, "Founding company opens route reports before the stock battle")
		_cleanup()
		return
	var mission: String = reports[0].get("mission_id", "")
	if mission.is_empty():
		_check(false, "First stock route identifies its mission")
		_cleanup()
		return
	# The stock seed-13 draw previously put a long reward below the clip edge.
	run.reward_rng_state = load("res://expedition/rewards.gd").starting_rng_state(13)
	await _press("Route_0")
	if scene.current_screen() != "battle":
		_check(false, "First stock route opens its battle")
		_cleanup()
		return
	await _play_battle(mission)
	if scene.current_screen() != "debrief":
		_check(false, "Stock battle reaches a reward debrief")
		_cleanup()
		return
	run = scene.get("_run")
	var defs: Dictionary = scene.get("_definitions")
	var art = load("res://presentation/book/guild_book_art.gd") if ResourceLoader.exists("res://presentation/book/guild_book_art.gd") else null
	var offers: Array = run.reward_offers.duplicate(true)
	_check(run.phase == "reward" and not offers.is_empty(), "Victory offers rewards")
	_check_carry_identity("PendingCarryScroll", run, defs, true)
	# A legacy/custom character with only a label must not gain a stock subtitle.
	var legacy_defs := defs.duplicate(true)
	legacy_defs.characters.knight.erase("epithet")
	legacy_defs.characters.knight.erase("guild_portrait")
	scene.set("_definitions", legacy_defs)
	scene.call("_show_debrief")
	await process_frame
	_check_carry_identity("PendingCarryScroll", run, legacy_defs, false)
	scene.set("_definitions", defs)
	scene.call("_show_debrief")
	await process_frame
	# Reuse the real debrief with controlled stock offers to exercise all seven
	# illustrations without depending on a particular random reward draw.
	var smith_ids := ["smith_leather_apron", "smith_heavier_hammer", "smith_follow_through",
		"smith_reinforced_rivets", "smith_fine_adjustment", "smith_quick_release", "smith_double_shift"]
	for id in smith_ids:
		run.reward_offers = [{"hero_id": "blacksmith", "upgrade_id": id}]
		scene.call("_show_debrief")
		await process_frame
		var smith_card := _item_card(_node("Reward_blacksmith") as Control, "RewardCard_blacksmith")
		var expected: Texture2D = art.upgrade(id)
		_check(smith_card != null and expected != null and expected in _textures_in(smith_card),
			"Stock debrief displays the correct Hobby Smith illustration for " + id)
	run.reward_offers = offers.duplicate(true)
	scene.call("_show_debrief")
	await process_frame
	var reward_scroll := _node("RewardScroll") as ScrollContainer
	var caps := {}
	var upgrade_textures := {}
	for offer in offers:
		var hero_id: String = offer.hero_id
		var upgrade_id: String = offer.upgrade_id
		var upgrade: Dictionary = defs.upgrades[upgrade_id]
		var owned := int(run.upgrades_by_id.get(hero_id, {}).get(upgrade_id, 0))
		caps[upgrade_id] = upgrade.cap
		var button := _node("Reward_" + hero_id) as BaseButton
		var card := _item_card(button, "RewardCard_" + hero_id)
		if card == null:
			_check(false, "Reward for %s has its own card" % hero_id)
			continue
		var textures := _textures_in(card)
		var portrait_id: String = defs.characters[hero_id].get("guild_portrait", "")
		var portrait: Texture2D = art.call("class_portrait", portrait_id) if art != null else null
		var illustration: Texture2D = art.call("upgrade", upgrade_id) if art != null else null
		_check(portrait != null and portrait in textures, "Offer %s shows the recipient portrait" % upgrade_id)
		_check(illustration != null and illustration in textures, "Offer %s shows its own upgrade illustration" % upgrade_id)
		upgrade_textures[upgrade_id] = illustration
		_check(button != null and not button.disabled and owned < int(upgrade.cap),
			"Offer %s remains available under its cap" % upgrade_id)
		_check(reward_scroll != null and button != null
			and reward_scroll.get_global_rect().grow(1.0).encloses(button.get_global_rect()),
			"Seed-13 offer %s action is fully visible without scrolling its description" % upgrade_id)
		var text := _text_in(card)
		_check("%d of %d" % [owned, upgrade.cap] in text,
			"Offer %s shows current count and cap" % upgrade_id)
		_check(upgrade.label in text and str(upgrade.rarity).capitalize() in text,
			"Offer %s identifies its effect and rarity" % upgrade_id)
	for first in upgrade_textures:
		for second in upgrade_textures:
			if first != second:
				_check(upgrade_textures[first] != null and upgrade_textures[second] != null \
					and upgrade_textures[first] != upgrade_textures[second],
					"Different offered upgrades use distinct illustrations")
	var continuation := _node("ContinueAdventure") as BaseButton
	_check(continuation != null and continuation.disabled, "A single reward is required before continuing")
	if continuation != null:
		continuation.pressed.emit()
		await process_frame
		_check(scene.current_screen() == "debrief" and scene.get("_run") == run,
			"Continuation cannot bypass a pending choice")
	if not offers.is_empty():
		var chosen: Dictionary = offers[0]
		var before_owned := int(run.upgrades_by_id.get(chosen.hero_id, {}).get(chosen.upgrade_id, 0))
		var comparison := _node("Reward_" + str(offers.back().hero_id)) as BaseButton
		var claim := _node("Reward_" + str(chosen.hero_id)) as BaseButton
		if comparison == null or claim == null:
			_check(false, "The compared and claimed offer actions exist")
			_cleanup()
			return
		comparison.grab_focus()
		await process_frame
		_check(comparison.has_focus() and scene.get("_run") == run and run.chosen_reward.is_empty(),
			"Keyboard focus compares an offer without claiming it")
		claim.grab_focus()
		for down in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER
			key.pressed = down
			viewport.push_input(key, true)
			await process_frame
		run = scene.get("_run")
		_check(int(run.upgrades_by_id.get(chosen.hero_id, {}).get(chosen.upgrade_id, 0)) == before_owned + 1,
			"Choosing an offer grants exactly one copy")
		_check(run.phase != "reward", "One reward ends the choice")
		_check_carry_identity("SettledCarryScroll", run, defs, true)
		var claimed := _node("RewardCard_" + str(chosen.hero_id))
		_check(claimed != null and defs.upgrades[chosen.upgrade_id].label in _text_in(claimed)
			and "Awarded for this outing" in _text_in(claimed),
			"The settled page identifies the actual claimed upgrade")
		for offer in offers:
			_check(_node("Reward_" + str(offer.hero_id)) == null, "A settled page has no claim actions")
		continuation = _node("ContinueAdventure") as BaseButton
		_check(continuation != null and continuation.has_focus() and not continuation.disabled,
			"Claiming enables and focuses continuation")
		for id in caps:
			_check(defs.upgrades[id].cap == caps[id], "Presentation did not change cap for " + id)
	_cleanup()


func _check_carry_identity(scroll_name: String, run: Dictionary, defs: Dictionary, has_epithet: bool) -> void:
	var scroll := _node(scroll_name) as ScrollContainer
	if scroll == null:
		_check(false, scroll_name + " exists")
		return
	var words := _text_in(scroll)
	var adventure = load("res://expedition/adventure.gd")
	for id in run.party:
		var before: Dictionary = run.last_result.heroes_by_id[id]
		var after: Dictionary = run.carry_by_id[id]
		var hp := "%d/%d HP → %d/%d HP" % [before.hp, before.max_hp,
			adventure.next_mission_hp(run, id), adventure.next_mission_max_hp(run, id)]
		var order: Dictionary = defs.orders.get(after.order, {})
		_check(hp in words and str(order.get("label", "None")) in words,
			scroll_name + " retains HP and order for " + str(id))
		if adventure.next_mission_hp(run, id) < adventure.next_mission_max_hp(run, id):
			_check("Wounded" in words, scroll_name + " retains the wounded indication")
		if before.hp <= 0 and after.hp > 0:
			_check("Back on their feet" in words, scroll_name + " retains fallen-hero recovery")
		elif before.knocked_down:
			_check("Recovered from knockdown" in words, scroll_name + " retains knockdown recovery")
	var name_label: Label
	var epithet_label: Label
	for label: Label in scroll.find_children("*", "Label", true, false):
		if label.text == "Edwin":
			name_label = label
		elif label.text == "Anxious Knight":
			epithet_label = label
	_check(name_label != null and name_label.is_visible_in_tree(),
		scroll_name + " presents the personal name as a separate identity heading")
	if name_label != null:
		var font := name_label.get_theme_font("font")
		if font is SystemFont:
			_check(font.font_weight >= 700, scroll_name + " emphasizes the personal name in bold")
	if has_epithet:
		_check(name_label != null and epithet_label != null and epithet_label.is_visible_in_tree()
			and epithet_label.get_global_rect().position.y >= name_label.get_global_rect().end.y,
			scroll_name + " shows the epithet as a subtitle beneath the name")
	else:
		_check(epithet_label == null and "Anxious Knight" not in words,
			scroll_name + " keeps a label-only legacy character free of invented subtitles")
