extends "res://tests/guild_book_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_book_debrief_test.gd
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
	var store = load("res://guild_profile.gd")
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
	run.reward_rng_state = load("res://rewards.gd").starting_rng_state(13)
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
	var art = load("res://presentation/guild_book_art.gd") if ResourceLoader.exists("res://presentation/guild_book_art.gd") else null
	var offers: Array = run.reward_offers.duplicate(true)
	_check(run.phase == "reward" and not offers.is_empty(), "Victory offers rewards")
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
