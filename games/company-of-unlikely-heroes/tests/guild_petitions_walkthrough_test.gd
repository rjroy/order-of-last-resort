extends "res://tests/guild_first_paths_scene_test.gd"

# Headless: godot --headless --path games/company-of-unlikely-heroes --script res://tests/guild_petitions_walkthrough_test.gd
# Visual evidence: run with a graphical display and -- --capture-dir=/absolute/existing/directory
# Each path is funded by four real controlled road victories and a forfeit.

func _run() -> void:
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var store = load("res://guild_profile.gd")
	var adv = load("res://adventure.gd")
	for method in ["settle_return", "balance", "purchase"]:
		if not store.has_method(method):
			_check(false, "Walkthrough requires GuildProfile." + method)
			_cleanup()
			return
	if not adv.has_method("start_guild_commission") or not adv.has_method("receipt"):
		_check(false, "Walkthrough requires guild commission and receipt")
		_cleanup()
		return
	var fixture = load("res://tests/guild_petitions_domain_test.gd").new()
	var defs: Dictionary = fixture._fixture()
	var paths: Array[String] = []
	for purchase_id in ["recruit_bard", "teach_healer_blast"]:
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
		await _press("Petitions")
		await _capture(purchase_id + "_credited_petitions")
		await _press("Petition_" + purchase_id)
		await _capture(purchase_id + "_petition_detail")
		await _press("PurchasePetition_" + purchase_id)
		var bought: Dictionary = store.load_profile(profile_path)
		_check(store.balance(bought) == 0, purchase_id + ": GUI purchase spends four points")
		# Relaunch follows the ordinary commission entry instead of assuming a
		# private back-navigation or page-model implementation.
		await _launch_normal()
		await _press("Commission_0")
		if purchase_id == "recruit_bard":
			for id in ["knight", "bard", "wizard"]:
				await _press("Recruit_" + id)
			_check(scene.selected_recruits() == ["knight", "bard", "wizard"],
				"Bard is a selectable alternative within the three-hero party")
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
		await _press("Route_0")
		if scene.current_screen() != "battle":
			_check(false, purchase_id + ": next mission deploys")
			continue
		var state: Dictionary = scene.battle_snapshot()
		var rules = load("res://rules.gd").new()
		if purchase_id == "recruit_bard":
			_check("bard" in state.get("party", []) and state.get("party", []).size() == 3,
				"Unlocked Bard deploys in the three-person party")
			var bard: Dictionary = rules.entity_profile(state, "bard")
			_check("inspiring_melody" in bard.get("abilities", [])
				and "healing_sonnet" in bard.get("abilities", []),
				"Deployed Bard has both base songs")
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
	fixture.free()
	for path in paths:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
				"Remove disposable walkthrough profile")
	_finish()


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
