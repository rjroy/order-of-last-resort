extends SceneTree
## Development-only bounded beam search. It is not a test or a runtime dependency.
##
## Create one JSON config per outing, outside the repository if desired:
## {"adventure":"AUTHORED_ID","party":["healer","knight","bard"],
##  "orders":{"knight":"order_cautious"},"rewards":["knight","bard"],
##  "beam":12,"depth":15,"abilities":[]}
## Then run independently, using a different config/output per process:
## godot --headless --path games/company-of-unlikely-heroes \
##   --script res://tools/fixed_outing_route_search.gd -- --config=/absolute/path/config.json
##
## The output is a mission-keyed JSON object compatible with fixed_outing_routes.json.
## Search one outing at a time; choose its authored ID from content. The optional
## abilities array restricts commands by ability ID (standing orders still act).
## Orders are applied at each mission opening and recorded only when changed.
## `rewards` names the hero to select at each intermediate debrief, in order.
## The search greedily accepts the first winning path per mission, not an outing-
## wide optimum. If a later mission fails, try a different party, orders, rewards,
## ability subset, beam, or depth. Failure is not proof that no route exists.
## Copy output only after reviewing it and running the real-scene regression.

const Rules = preload("res://rules.gd")
const Adventure = preload("res://adventure.gd")
const Catalog = preload("res://content/catalog.gd")
const Board = preload("res://rules/board.gd")
const REWARD_SEED := 12345

var rules := Rules.new()
var allowed_abilities: Array = []
var width := 12
var depth := 15
var forecast_count := 0
var exit_distances := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--config="):
			config_path = arg.trim_prefix("--config=")
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		_fail("Provide --config=/absolute/path/to/config.json")
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not config is Dictionary:
		_fail("Config must be a JSON object")
		return
	var party: Array = config.get("party", [])
	var orders: Dictionary = config.get("orders", {})
	var rewards: Array = config.get("rewards", [])
	allowed_abilities = config.get("abilities", [])
	width = int(config.get("beam", 12))
	depth = int(config.get("depth", 15))
	if width < 1 or depth < 1:
		_fail("beam and depth must be positive")
		return
	var defs: Dictionary = Catalog.read_default()
	var run: Dictionary = Adventure.start_adventure(defs, str(config.get("adventure", "")), party, REWARD_SEED)
	if run.is_empty():
		_fail("Invalid adventure or party; use the IDs and roster declared in the catalog")
		return
	if rewards.size() != run.mission_ids.size() - 1:
		_fail("Specify one reward hero for each intermediate debrief")
		return
	var output := {}
	for index in run.mission_ids.size():
		run = Adventure.begin_mission(run)
		if run.phase != "mission":
			_fail("Could not begin mission %d" % index)
			return
		var state: Dictionary = run.mission
		var initial_orders := {}
		for actor in orders:
			if actor not in party or not rules.entity_profile(state, actor).get("habits", {}).has(orders[actor]):
				_fail("Invalid standing order %s for %s" % [orders[actor], actor])
				return
			if state.orders.get(actor) != orders[actor]:
				state = rules.set_order(state, actor, orders[actor])
				initial_orders[actor] = orders[actor]
		var id: String = state.mission_id
		print("Searching %s (objective %s)..." % [id, state.objective.handler])
		var result := _search(state)
		if result.is_empty():
			_fail("%s: no route in bounded search (%d round forecasts total)" % [id, forecast_count])
			return
		var rounds: Array = result.rounds
		if not initial_orders.is_empty():
			rounds[0]["orders"] = initial_orders
		var entry := {"rounds": rounds}
		if index == 0:
			entry["party"] = party
		run = Adventure.settle_mission(run, result.state)
		if index < rewards.size():
			if run.phase != "reward":
				_fail("%s: no selectable reward debrief (phase %s)" % [id, run.phase])
				return
			var hero := str(rewards[index])
			var chosen := {}
			for offer in run.reward_offers:
				if offer.hero_id == hero:
					chosen = offer
					break
			if chosen.is_empty():
				_fail("%s: reward for %s not offered; offers: %s" % [id, hero, run.reward_offers])
				return
			entry["reward"] = hero
			run = Adventure.choose_reward(run, hero, chosen.upgrade_id)
			if run.phase != "ready":
				_fail("%s: reward could not be selected" % id)
				return
		elif run.phase != "finished" or run.outcome != "victory":
			_fail("%s: final victory did not settle" % id)
			return
		output[id] = entry
	print("Candidate routes (%d round forecasts; verify in real scene):" % forecast_count)
	print(JSON.stringify(output, "\t"))
	quit(0)


func _search(opening: Dictionary) -> Dictionary:
	_prepare_distances(opening)
	var frontier: Array = [{"state": opening, "parent": {}, "step": {}}]
	for _round in depth:
		var next: Array = []
		var next_signatures := {}
		for node in frontier:
			var state: Dictionary = node.state
			for step in _commands(state):
				var planned: Dictionary = state
				if step.has("command"):
					var cmd: Dictionary = step.command
					planned = rules.choose_manual(state, cmd.actor, cmd.ability, cmd.get("target", ""))
				var plan: Dictionary = rules.preview_round(planned)
				forecast_count += 1
				if not plan.valid:
					continue
				# A forecast already contains the complete next snapshot. Only the
				# terminal winner needs a real commit for adventure settlement.
				var predicted: Dictionary = plan.result
				if predicted.outcome == "defeat":
					continue
				if predicted.outcome == "victory":
					var committed: Dictionary = rules.commit_round(planned, plan)
					if committed.get("_terminal_commit", false):
						return {"state": committed, "rounds": _path(node, step)}
					continue
				var score := _score(predicted)
				# Keep only the best `width` snapshots, with first-seen tie order.
				# Do not mark discarded candidates visited: that can prune a later
				# equivalent candidate which actually belongs in the beam.
				if next.size() == width and score <= next.back().score:
					continue
				var signature := _signature(predicted)
				if next_signatures.has(signature):
					continue
				var insert_at := 0
				while insert_at < next.size() and next[insert_at].score >= score:
					insert_at += 1
				next.insert(insert_at, {"state": predicted, "parent": node, "step": step,
					"score": score, "signature": signature})
				next_signatures[signature] = true
				if next.size() > width:
					var removed: Dictionary = next.pop_back()
					next_signatures.erase(removed.signature)
		print("  depth %d: retained %d states, %d forecasts" % [_round + 1, next.size(), forecast_count])
		frontier = next
		if frontier.is_empty():
			break
	return {}


func _path(parent: Dictionary, last_step: Dictionary) -> Array:
	var path: Array = [last_step]
	while not parent.parent.is_empty():
		path.append(parent.step)
		parent = parent.parent
	path.reverse()
	return path


func _prepare_distances(state: Dictionary) -> void:
	exit_distances.clear()
	if state.objective.handler != "leave_zone":
		return
	var exits: Array[Vector2i] = []
	for x in state.width:
		for y in state.height:
			var pos := Vector2i(x, y)
			if not Board.in_zone(state, state.objective.zone, pos):
				exits.append(pos)
	for x in state.width:
		for y in state.height:
			var pos := Vector2i(x, y)
			var nearest := 1000
			for exit in exits:
				nearest = mini(nearest, Board.distance(pos, exit))
			exit_distances[pos] = nearest


func _commands(state: Dictionary) -> Array:
	# Standing-only is always available. Resolve earlier turns once per actor,
	# as the real scene does, before listing targets and validating each action.
	var result: Array = [{}]
	for actor in state.party:
		var turn: Dictionary = rules.state_before_action(state, actor)
		if not rules.can_act(turn, actor):
			continue
		for option in rules.options(state, actor):
			if option.kind != "action" or (not allowed_abilities.is_empty() and option.id not in allowed_abilities):
				continue
			var targets: Array = []
			if option.target_kind in ["cell", "entity"]:
				for choice in rules.targets(turn, actor, option.id):
					targets.append(choice.id)
			else:
				targets.append("")
			for target in targets:
				if not rules.preview(turn, actor, option.id, target).valid:
					continue
				var command := {"actor": actor, "ability": option.id}
				if not str(target).is_empty():
					command["target"] = target
				result.append({"command": command})
	return result


func _signature(state: Dictionary) -> String:
	var snapshot := state.duplicate()
	snapshot.erase("catalog")
	# Round and RNG are deliberately retained: deadlines and random actions matter.
	return var_to_str(snapshot)


func _score(state: Dictionary) -> float:
	var score := 0.0
	var enemies: Array = []
	var heroes: Array = []
	var characters: Array = []
	for unit in state.units:
		if unit.get("hp", 0) <= 0:
			if unit.id in state.party:
				score -= 50.0
			continue
		if unit.has("character_id"):
			characters.append(unit)
		if unit.id in state.party:
			heroes.append(unit)
			score += float(unit.hp) * 3.0
		elif Board.team(state, unit) == state.objective.get("team", "enemies"):
			enemies.append(unit)
	var objective: Dictionary = state.objective
	if objective.handler == "defeat_all":
		for enemy in enemies:
			score -= 20.0 + float(enemy.hp) * 6.0
		for hero in heroes:
			if enemies.is_empty():
				continue
			var nearest := 1000
			for enemy in enemies:
				nearest = mini(nearest, Board.distance(hero.position, enemy.position))
			score -= float(nearest) * 0.5
	elif objective.handler in ["escort", "leave_zone", "wagon"]:
		var subject := Board.entity(state, objective.subject)
		if not subject.is_empty():
			score += float(subject.get("hp", 0)) * 5.0
			if objective.handler == "leave_zone":
				score -= 8.0 * int(exit_distances.get(subject.position, 1000))
			else:
				score -= 8.0 * Board.distance(subject.position, objective.destination)
				if objective.handler == "wagon":
					for enemy in enemies:
						var distance := Board.distance(enemy.position, subject.position)
						if distance == 1:
							score -= 16.0
						elif distance == 2:
							score -= 3.0
	elif objective.handler == "ritual":
		score += 40.0 * int(objective.get("held_turns", 0))
		for circle in objective.circles:
			var nearest := 1000
			for character in characters:
				nearest = mini(nearest, Board.distance(character.position, circle))
			if nearest == 0:
				score += 20.0
			elif nearest < 1000:
				score -= 3.0 * nearest
	elif objective.handler == "herd_sheep":
		for id in objective.subjects:
			var sheep := Board.entity(state, id)
			if sheep.is_empty() or sheep.get("hp", 0) <= 0:
				score -= 100.0
				continue
			var nearest := _distance_to_cells(sheep.position, objective.pen)
			score += 25.0 if nearest == 0 else -5.0 * nearest
	elif objective.handler == "pressure_gate":
		var plate_distance := 1000
		for character in characters:
			plate_distance = mini(plate_distance, Board.distance(character.position, objective.plate))
		if plate_distance == 0:
			score += 18.0
		elif plate_distance < 1000:
			score -= 3.0 * plate_distance
		score -= 6.0 * _nearest_hero(heroes, objective.exit)
	elif objective.handler == "collapsing_bridge":
		score -= 7.0 * _nearest_hero(heroes, objective.exit)
		for hero in heroes:
			for collapse in objective.collapses:
				if hero.position in collapse.cells and int(collapse.round) >= state.round:
					score -= 30.0 if int(collapse.round) == state.round else 6.0
	elif objective.handler == "treasure_noise":
		score -= 7.0 * _nearest_hero(heroes, objective.treasure)
		score -= 12.0 * int(objective.get("noise", 0))
	elif objective.handler == "survive":
		score += 5.0 * mini(int(state.round), int(objective.turns))
	return score


func _distance_to_cells(position: Vector2i, cells: Array) -> int:
	var nearest := 1000
	for cell in cells:
		nearest = mini(nearest, Board.distance(position, cell))
	return nearest


func _nearest_hero(heroes: Array, position: Vector2i) -> int:
	var nearest := 1000
	for hero in heroes:
		nearest = mini(nearest, Board.distance(hero.position, position))
	return nearest


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
