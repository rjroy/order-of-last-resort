extends SceneTree

# Run: godot --headless --path games/company-of-unlikely-heroes --script res://tests/battle/sheep_corner_recovery_test.gd
const Catalog = preload("res://content/catalog.gd")
const Board = preload("res://rules/board.gd")
const Rules = preload("res://rules/rules.gd")

var rules := Rules.new()
var failures: Array[String] = []


func _initialize() -> void:
	_test_corner_recovery()
	for failure in failures:
		push_error("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: sheep corner recovery")
	quit(0 if failures.is_empty() else 1)


func _test_corner_recovery() -> void:
	var state := Rules.open_mission(Catalog.read_default(), "great_sheep_escape",
		["bard", "necromancer", "healer"])
	_check(not state.is_empty(), "The Great Sheep Escape opens for the corner recovery company")
	if state.is_empty():
		return
	# Recreate a cornered sheep at A1 without relying on a long route into the bad position.
	Board.entity(state, "sheep_one").position = Vector2i(0, 0)
	Board.entity(state, "sheep_two").position = Vector2i(5, 3)
	Board.entity(state, "sheep_three").position = Vector2i(6, 4)
	Board.entity(state, "bard").position = Vector2i(1, 2)
	Board.entity(state, "shepherd").position = Vector2i(6, 3)
	# Keep the other two heroes too far away to pressure the corner.
	Board.entity(state, "necromancer").position = Vector2i(0, 3)
	Board.entity(state, "healer").position = Vector2i(0, 4)
	var quiet := _commit(state)
	_check(Board.entity(quiet, "sheep_one").position == Vector2i(0, 0),
		"Unpressured cornered sheep does not move toward the pen on its own")

	# Bard steps to B2 to pressure A1. Both in-bounds neighbors are nearer to Bard.
	var moves := ["1,1", "", "2,1", "3,1", "4,1", "5,1"]
	for index in moves.size():
		var target: String = moves[index]
		if not target.is_empty():
			_check(rules.preview(state, "bard", "move", target).valid, "Bard's approach is an ordinary legal move")
			state = rules.choose_manual(state, "bard", "move", target)
		state = _commit(state)
		_check(Board.entity(state, "sheep_one").position == Vector2i(index + 1, 0),
			"Ordinary pressure drives the sheep from A1 along the north fence to column %d" % (index + 2))
	_check(state.outcome == "victory", "All three sheep can be penned after recovery from A1")


func _commit(state: Dictionary) -> Dictionary:
	var plan := rules.preview_round(state)
	_check(plan.valid, "Forecast is valid at round %d" % state.round)
	return rules.commit_round(state, plan)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
