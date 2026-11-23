extends "res://tests/commission_scene_test.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/commission_board_layout_test.gd
# Use a graphical display and -- --capture-dir=<absolute existing directory> to review these states.
const Profile = preload("res://guild_profile.gd")
const Adventure = preload("res://adventure.gd")
const Commissions = preload("res://commissions.gd")
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
const REVIEW_SEED := 677
const LONG_NAME := "The Very Unlikely Company of the Last Lantern and the Watch at the Northern Gate"
const REFRESH_WARNING := "The board wasn’t refreshed. These commissions are from the current saved guild."


func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var defs := Catalog.read_default()
	var settled := _earn_receipt(defs)
	if settled.has("error") or settled.get("points", 0) != 1:
		_check(false, "Fixture earns and settles a road victory: " + str(settled))
		_cleanup()
		return
	await _launch_normal()
	if scene.current_screen() != "commissions":
		_check(false, "The settled profile opens the board")
		_cleanup()
		return
	var offers := Commissions.board(defs, REVIEW_SEED)
	var summary: String = scene.call("_receipt_summary", settled.last_receipt)
	for failed_refresh in [false, true]:
		# Exercise the combined presentation state without manufacturing an I/O error.
		if failed_refresh:
			scene.call("_open_commission_hub", true)
		for tick in 4:
			await process_frame
		var context := "Long guild and receipt" + (" with failed refresh" if failed_refresh else "")
		_check_layout(context, offers, summary, failed_refresh)
		await _capture("02-commissions-long-name-receipt" + ("-warning" if failed_refresh else ""))
	_check(Profile.load_profile(profile_path) == settled, "Showing the warning does not replace the board or receipt")
	await _check_stock_return_copy(defs, settled, summary)
	_cleanup()


func _earn_receipt(defs: Dictionary) -> Dictionary:
	var profile := Profile.create(profile_path, LONG_NAME, BOARD_SEED)
	if profile.has("error"):
		return profile
	var rules := Rules.new()
	var board := Commissions.board(defs, BOARD_SEED)
	var run := Adventure.start_guild_commission(defs, board[0], FOUNDER_PARTY, profile, {}, 12345)
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	# Controlled road victory, then a real forfeit and settlement on a fresh board.
	var state: Dictionary = run.mission
	for unit in state.units:
		if rules.entity_profile(state, unit.id).get("team") == "enemies":
			unit.hp = 0
	run = Adventure.settle_mission(run, rules.commit_round(state, rules.preview_round(state)))
	if run.get("phase") != "reward":
		return {"error": "Controlled road victory did not reach its reward."}
	var reward: Dictionary = run.reward_offers[0]
	run = Adventure.choose_reward(run, reward.hero_id, reward.upgrade_id)
	run = Adventure.begin_mission(Adventure.choose_route(run, run.reports[0].mission_id))
	run = Adventure.settle_mission(run, rules.forfeit(run.mission))
	return Profile.settle_return(profile_path, profile, run, REVIEW_SEED)


func _check_stock_return_copy(defs: Dictionary, profile: Dictionary, summary: String) -> void:
	# Cover every authored destination description without pinning a seed list
	# to today's catalog contents. Reduce the search to boards that add coverage.
	var remaining := {}
	for id in defs.mission_reports:
		for copy in defs.mission_reports[id].get("destination_descriptors", []):
			remaining[[id, copy]] = true
	var sampled := 0
	for seed in 256:
		var offers := Commissions.board(defs, seed)
		var previous := remaining.size()
		for offer in offers:
			remaining.erase([offer.destination_id, offer.description])
		if remaining.size() == previous:
			continue
		var fixture := profile.duplicate(true)
		fixture.board_seed = seed
		for guild_name in [GUILD_NAME, LONG_NAME]:
			fixture.name = guild_name
			scene.set("_guild_profile", fixture)
			for failed_refresh in [false, true]:
				scene.call("_show_commissions", failed_refresh)
				for tick in 4:
					await process_frame
				var context := "Seed %d, %d-character name, warning %s" % [seed, guild_name.length(), failed_refresh]
				_check_layout(context, offers, summary, failed_refresh, guild_name)
		sampled += 1
		if remaining.is_empty():
			break
	_check(remaining.is_empty(), "Stock return fixture covers every authored destination description")
	print("Checked stock return descriptions on %d boards with short and long names, with and without the warning." % sampled)


func _check_layout(context: String, offers: Array, summary: String, failed_refresh: bool,
		guild_name := LONG_NAME) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))
	var book := _node("CommissionsScreen") as Control
	_check(book.get_global_rect().is_equal_approx(bounds),
		"%s: binding fits %s, got %s" % [context, bounds.size, book.size])
	var visible := _visible_text()
	_check(guild_name in visible and summary in visible and "Guild points: 1" in visible,
		context + ": guild identity, earned receipt, and current balance remain present")
	_check((REFRESH_WARNING in visible) == failed_refresh, context + ": notice reflects the refresh result")
	var petitions := _node("Petitions") as Button
	_check(petitions != null and not petitions.disabled and bounds.encloses(petitions.get_global_rect()),
		context + ": Guild petitions remains reachable")
	for index in offers.size():
		var copy := _node("CommissionText_%d" % index) as Label
		var details := _node("CommissionDetails_%d" % index) as ScrollContainer
		var action := _node("Commission_%d" % index) as Button
		if copy == null or details == null or action == null:
			_check(false, "%s: posting %d exposes its text, scroll region, and action" % [context, index])
			continue
		var clipped := copy.get_global_rect().end.y - details.get_global_rect().end.y
		_check(copy.text == offers[index].description and clipped <= 0.5 and bounds.encloses(copy.get_global_rect()),
			"%s: posting %d shows the whole description at rest (%.1f px clipped)" % [context, index, maxf(0, clipped)])
		_check(not action.disabled and bounds.encloses(action.get_global_rect()),
			"%s: posting %d action remains fully reachable" % [context, index])
