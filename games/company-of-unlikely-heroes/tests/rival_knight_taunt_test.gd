extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/rival_knight_taunt_test.gd
const Catalog = preload("res://content/catalog.gd")
const Rules = preload("res://rules.gd")
var rules = Rules.new()


func _initialize() -> void:
	var failure := _check_targeting()
	if not failure.is_empty():
		push_error("FAIL: " + failure)
		quit(1)
		return
	print("PASS: Rival Knight pursues the Healer who taunted it")
	quit(0)


func _check_targeting() -> String:
	var state := Rules.open_mission(Catalog.read_default(), "mirror_company", ["bard", "healer", "wizard"])
	if state.is_empty():
		return "Mirror Company opens with the selected party"
	# Isolate the priority choice: both heroes are in push range, with the
	# Bard first in initiative. Suppress hero standing orders for this round.
	state.width = 12
	state.height = 12
	state.terrain = []
	state.obstacles = []
	state.orders = {}
	var positions := {"rival_knight": Vector2i(4, 4), "bard": Vector2i(3, 4),
		"healer": Vector2i(4, 3), "wizard": Vector2i(0, 0),
		"rival_wizard": Vector2i(10, 10), "rival_healer": Vector2i(11, 11)}
	var rival_id := ""
	for unit in state.units:
		if positions.has(unit.character_id):
			unit.position = positions[unit.character_id]
		if unit.character_id == "rival_knight":
			rival_id = unit.id
			unit.max_hp = 20
			unit.hp = unit.max_hp
	if rival_id.is_empty():
		return "Mirror Company includes a Rival Knight"
	var bonk: Dictionary = rules.preview(state, "healer", "healer_bonk", rival_id)
	if not bonk.get("valid", false) or not rules.has_status(bonk.result, rival_id, "taunt"):
		return "Bonk applies taunt to the Rival Knight"
	if _pushed_target(state, rival_id) != "bard":
		return "The equally near Bard is the Rival Knight's normal target"
	if _pushed_target(bonk.result, rival_id) != "healer":
		return "The Rival Knight pushes the equally near Healer who taunted it"
	return ""


func _pushed_target(state: Dictionary, rival_id: String) -> String:
	var plan: Dictionary = rules.preview_round(state)
	for event in plan.get("events", []):
		if event.get("type") == "push" and event.get("unit_id") == rival_id:
			return event.target_id
	return ""
