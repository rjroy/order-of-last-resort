extends RefCounted
## Fitted Crypter actions. The caller owns fitting and Inspiration consumption.

const Board = preload("res://rules/board.gd")
const Movement = preload("res://rules/movement.gd")
const Shield = preload("res://rules/shield.gd")
const Summons = preload("res://rules/summons.gd")


static func describe(state: Dictionary, actor: Dictionary, _source_id: String, base: Dictionary) -> Dictionary:
	match base.get("fitted_form", ""):
		"recall_skeleton":
			var choices: Array = []
			if not Summons.owned_living(state, actor, "skeleton").is_empty():
				for direction in Board.DIRECTIONS:
					var position: Vector2i = actor.position + direction
					if Board.is_vacant(state, position):
						choices.append({"id": Board.cell_id(position), "position": position,
							"label": Board.coordinate(position)})
			return {"id": base.fitted_form, "label": "Recall Skeleton",
				"help": "Bring your living skeleton to a vacant neighboring tile without changing it.",
				"targeting": {"kind": "cell"}, "choices": choices,
				"unavailable_reason": "no living skeleton or vacant neighboring tile", "primary": "steady"}
		"play_dead":
			var zombie := Summons.owned_living(state, actor, "zombie")
			var corpse := Board.entity(state, zombie.get("raised_from_id", "")) if not zombie.is_empty() else {}
			var choices: Array = [{"id": "", "zombie_id": zombie.id, "corpse_id": corpse.id}] \
				if not corpse.is_empty() and not Board.alive(corpse) else []
			return {"id": base.fitted_form, "label": "Play Dead",
				"help": "Return your zombie to its original enemy corpse without a combat death.",
				"targeting": {"kind": "none"}, "choices": choices,
				"unavailable_reason": "no living zombie with an original corpse", "primary": "steady"}
		"dinner_bell":
			var candidates: Array = []
			for target in Board.occupants(state, {}):
				if target.id == actor.id or Board.distance(actor.position, target.position) <= 1:
					continue
				var direction := Board.dominant_step(target.position, actor.position)
				var destination: Vector2i = target.position + direction
				if Board.can_enter(state, destination):
					candidates.append({"id": target.id, "position": target.position,
						"destination": destination, "direction": direction})
			var nearest := Board.nearest(actor, candidates)
			var choices: Array = [] if nearest.is_empty() else [{"id": "", "target_id": nearest.id,
				"destination": nearest.destination, "direction": nearest.direction}]
			return {"id": base.fitted_form, "label": "Dinner Bell",
				"help": "Draw the nearest other character with an open step one tile closer.",
				"targeting": {"kind": "automatic"}, "choices": choices,
				"unavailable_reason": "no character with an open step", "primary": "steady", "selection": "first"}
		"stay_close_to_that_one":
			var choices: Array = []
			for hero in state.units:
				if Board.alive(hero) and Board.deployed_hero(state, hero) \
						and Board.team(state, hero) == "heroes" and not hero.has("summoner_id") \
						and not Board.capable(state, hero, "minion"):
					choices.append({"id": hero.id, "position": hero.position,
						"label": Board.display_name(state, hero)})
			return {"id": base.fitted_form, "label": "Stay Close to That One",
				"help": "Your undead approach this hero and stop adjacent, while still greeting normally.",
				"targeting": {"kind": "entity"}, "choices": choices,
				"unavailable_reason": "no living hero", "primary": "steady"}
	return {}


static func apply(state: Dictionary, actor: Dictionary, _source_id: String, _base: Dictionary,
		form: Dictionary, choice: Dictionary, _bonus: int, events: Array) -> void:
	match form.id:
		"recall_skeleton":
			var skeleton := Summons.owned_living(state, actor, "skeleton")
			if skeleton.is_empty():
				return
			var origin: Vector2i = skeleton.position
			skeleton.position = choice.position
			Board.event(events, "recall", "Recall Skeleton: %s returns from %s to %s." % [
				Board.display_name(state, skeleton), Board.coordinate(origin), Board.coordinate(skeleton.position)],
				{"unit_id": actor.id, "target_id": skeleton.id, "from_position": origin, "position": skeleton.position})
			Shield.retrieve(state, skeleton, events)
		"play_dead":
			var zombie := Board.entity(state, choice.zombie_id)
			var corpse := Board.entity(state, choice.corpse_id)
			if zombie.is_empty() or corpse.is_empty():
				return
			var position: Vector2i = zombie.position
			# Invalidate captured initiative references before removing the retired minion.
			zombie.hp = 0
			state.units.erase(zombie)
			corpse.position = position
			corpse.erase("corpse_consumed")
			Board.event(events, "play_dead", "Play Dead: %s leaves %s at %s." % [
				Board.display_name(state, zombie), Board.display_name(state, corpse), Board.coordinate(position)],
				{"unit_id": actor.id, "target_id": corpse.id, "summon_id": zombie.id, "position": position})
		"dinner_bell":
			var target := Board.entity(state, choice.target_id)
			if target.is_empty() or not Board.can_enter(state, choice.destination) \
					or Movement.blocks_forced(state, target, events):
				return
			var origin: Vector2i = target.position
			target.position = Movement.forced_destination(state, target, choice.destination, choice.direction, events)
			Board.event(events, "pull", "Dinner Bell: %s moves from %s to %s." % [
				Board.display_name(state, target), Board.coordinate(origin), Board.coordinate(target.position)],
				{"unit_id": actor.id, "target_id": target.id, "from_position": origin, "position": target.position})
			Shield.retrieve(state, target, events)
		"stay_close_to_that_one":
			Summons.rally(state, actor, Board.entity(state, choice.id), events)
