extends "res://tests/support/scene_fixture.gd"

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/journeys/village_outing_scene_test.gd
# In a graphical session, -- --capture-dir=/absolute/directory saves opening boards.
# The bounded policy uses the scene's command editor and forecast.
const MISSIONS := ["goblin_mob", "harpoon_squad", "unwelcome_guest"]
const PARTY := ["healer", "knight", "bard"]


func _run() -> void:
	var container := SubViewportContainer.new()
	container.size = VIEWPORT_SIZE
	# Keep the complete native-resolution fixture inside small desktop windows.
	# Captures come directly from the unscaled SubViewport texture.
	container.scale = Vector2(0.5, 0.5)
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	root.add_child(container)
	for id in MISSIONS:
		await _launch(PackedStringArray(["--mission=" + id]))
		_check(scene.current_screen() == "battle", id + " launches directly into battle")
		if scene.current_screen() == "battle":
			var opening: Dictionary = scene.battle_snapshot()
			_check(opening.get("mission_id") == id, id + " launches the requested mission")
			_check(opening.get("party", []).size() == 3, id + " has an authored three-hero party")
			await _capture(id + "_direct")
			await _check_battle_controls(id, opening.get("party", []))
		await _launch(PackedStringArray(["--mission=" + id, "--party=" + ",".join(PARTY)]))
		if scene.current_screen() != "battle":
			_check(false, id + " launches the policy company")
			continue
		_check(scene.battle_snapshot().get("party") == PARTY, id + " deploys the policy company in order")
		await _play_battle(id)
		var terminal: Dictionary = scene.battle_snapshot()
		_check(terminal.get("mission_id") == id, id + " victory is on the requested mission")
		_check(terminal.get("outcome") == "victory" and terminal.get("_terminal_commit", false),
			id + " reaches a committed standalone victory")
	_finish()


func _check_battle_controls(id: String, party: Array) -> void:
	_check(_reachable(_node("Commit") as Control), id + " Commit is fully reachable at 1280x820")
	_check(_reachable(_node("StandingOrders") as Control), id + " standing orders are fully reachable at 1280x820")
	await _press("StandingOrders")
	for actor in party:
		_check(_reachable(_node(str(actor).to_pascal_case() + "Order") as Control),
			id + " standing order for " + str(actor) + " is fully reachable at 1280x820")
	await _press("StandingOrders")
