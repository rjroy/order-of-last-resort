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
	if not offers.is_empty():
		var chosen: Dictionary = offers[0]
		var before_owned := int(run.upgrades_by_id.get(chosen.hero_id, {}).get(chosen.upgrade_id, 0))
		await _press("Reward_" + str(chosen.hero_id))
		run = scene.get("_run")
		_check(int(run.upgrades_by_id.get(chosen.hero_id, {}).get(chosen.upgrade_id, 0)) == before_owned + 1,
			"Choosing an offer grants exactly one copy")
		_check(run.phase != "reward", "One reward ends the choice")
		for id in caps:
			_check(defs.upgrades[id].cap == caps[id], "Presentation did not change cap for " + id)
	_cleanup()
