extends SceneTree
## Read-only stock rules route probe. No assets, presentation, or modified catalog.
## godot --headless --path games/company-of-unlikely-heroes --script res://tests/support/harpooner_route_probe.gd

const Rules = preload("res://rules/rules.gd")
const Catalog = preload("res://content/catalog.gd")
var rules := Rules.new()


func _initialize() -> void:
	var initial: Dictionary = Rules.open_mission(Catalog.read_default(), "company_rescue",
		["knight", "healer", "wizard"])
	var frontier := [{"state": initial, "route": []}]
	var found := {}
	for depth in 8:
		var next := []
		var visited := {}
		for node in frontier:
			var state: Dictionary = node.state
			var choices: Array = [{"actor": "", "ability": "", "target": ""}]
			for actor in ["knight", "healer", "wizard"]:
				var action_state: Dictionary = rules.state_before_action(state, actor)
				for option in rules.options(state, actor):
					if option.kind != "action":
						continue
					if option.target_kind == "none":
						choices.append({"actor": actor, "ability": option.id, "target": ""})
					else:
						for target in rules.targets(action_state, actor, option.id):
							choices.append({"actor": actor, "ability": option.id, "target": str(target.id)})
			for choice in choices:
				var selected: Dictionary = state if choice.actor.is_empty() else rules.choose_manual(
					state, choice.actor, choice.ability, choice.target)
				var plan: Dictionary = rules.preview_round(selected)
				if not plan.valid:
					continue
				var route: Array = node.route + [choice]
				var positions := {}
				for entity in state.units + state.obstacles:
					positions[entity.id] = entity.position
				for event in plan.events:
					var action: Dictionary = event.get("resolved_action", {})
					if action.get("unit_id") == "harpooner" and action.get("ability_id") == "move" and not found.has("move"):
						found["move"] = true
						print("MOVE route=", route, " event=", event)
					if action.get("unit_id") == "harpooner" and action.get("ability_id") == "enemy_harpoon":
						var target_id := str(event.get("ward_id", event.get("target_id", "")))
						if positions.has(target_id):
							var source: Vector2i = action.source_cell
							var position: Vector2i = positions[target_id]
							var distance := absi(source.x - position.x) + absi(source.y - position.y)
							if not found.has(distance):
								found[distance] = true
								print("DISTANCE ", distance, " route=", route, " event=", event)
					if event.get("type") == "damage" and event.get("target_id") == "harpooner":
						var hp := int(_unit(plan.result, "harpooner").get("hp", -1))
						var key := "defeat" if hp <= 0 else "hit"
						if not found.has(key):
							found[key] = true
							print(key.to_upper(), " route=", route, " event=", event, " hp=", hp)
					match event.type:
						"move":
							positions[event.unit_id] = event.position
						"push", "repel", "pull":
							positions[event.target_id] = event.position
							if event.has("recoil_position"):
								positions[event.unit_id] = event.recoil_position
						"swap":
							positions[event.unit_id] = event.position
							positions[event.target_id] = event.target_position
				if plan.result.outcome == "ongoing":
					var key := str(plan.result.units) + str(plan.result.orders)
					if not visited.has(key):
						visited[key] = true
						next.append({"state": plan.result, "route": route})
		print("depth=", depth + 1, " states=", next.size())
		if found.has(1) and found.has(2) and found.has("hit") and found.has("defeat") and found.has("move"):
			break
		next.sort_custom(func(a, b): return int(_unit(a.state, "harpooner").get("hp", 100)) \
			< int(_unit(b.state, "harpooner").get("hp", 100)))
		frontier = next.slice(0, 500)
	quit()


func _unit(state: Dictionary, id: String) -> Dictionary:
	for unit: Dictionary in state.units:
		if unit.id == id:
			return unit
	return {}
