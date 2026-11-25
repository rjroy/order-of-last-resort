extends RefCounted
## Fitted song effects. Selection and token consumption belong to the action resolver.

const Board = preload("res://rules/board.gd")
const Statuses = preload("res://rules/statuses.gd")
const Support = preload("res://rules/support.gd")
const Upgrades = preload("res://rules/upgrades.gd")


static func describe(state: Dictionary, actor: Dictionary, _source_id: String, base: Dictionary) -> Dictionary:
	var label := ""
	var help := ""
	var form_id: String = base.get("fitted_form", "")
	var is_melody := form_id == "inspiring_melody_in_tune"
	match form_id:
		"healing_sonnet_in_tune":
			label = "Healing Sonnet, in tune"
			help = "Heal a random wounded hero."
		"company_chorus":
			label = "Company Chorus"
			help = "Heal a random wounded hero and adjacent wounded heroes."
		"inspiring_melody_in_tune":
			label = "Inspiring Melody, in tune"
			help = "Inspire a random hero who is not already Inspired."
		_:
			return {}
	var choices: Array = []
	for hero in state.units:
		if not Board.alive(hero) or not Board.deployed_hero(state, hero) \
				or Board.team(state, hero) != "heroes" or hero.has("summoner_id") \
				or Board.capable(state, hero, "minion"):
			continue
		# The actor's current token is consumed before this song grants a new one.
		if is_melody:
			if hero.id != actor.id and Statuses.inspired(hero):
				continue
		elif hero.hp >= hero.max_hp:
			continue
		choices.append({"id": hero.id, "position": hero.position, "label": Board.display_name(state, hero)})
	if not is_melody and Upgrades.amount(state, actor, "front_row_seats") > 0 and choices.size() > 2:
		var health := choices.map(func(choice: Dictionary) -> int: return Board.entity(state, choice.id).hp)
		health.sort()
		choices = choices.filter(func(choice: Dictionary) -> bool: return Board.entity(state, choice.id).hp <= health[1])
	return {"id": base.fitted_form, "label": label, "help": help,
		"targeting": {"kind": "automatic"}, "choices": choices,
		"unavailable_reason": "no eligible hero", "primary": "steady" if is_melody else "amount",
		"selection": "random"}


static func apply(state: Dictionary, actor: Dictionary, _source_id: String, base: Dictionary,
		form: Dictionary, choice: Dictionary, bonus: int, events: Array) -> void:
	if form.get("id", "") not in ["healing_sonnet_in_tune", "inspiring_melody_in_tune", "company_chorus"]:
		return
	var listener := Board.entity(state, choice.id)
	# The resolver selects once using the ordinary encounter stream; apply that draw once.
	state.rng_state = choice.rng_seed
	if form.id == "inspiring_melody_in_tune":
		Statuses.grant_inspiration(state, actor, listener, events)
		return
	var amount := int(base.params.damage) + bonus
	Support.heal(state, actor, listener, amount, events, form.label)
	if form.id == "company_chorus":
		for hero in state.units:
			if hero.id == listener.id or not Board.alive(hero) or not Board.deployed_hero(state, hero) \
					or Board.team(state, hero) != "heroes" or hero.has("summoner_id") \
					or Board.capable(state, hero, "minion") or hero.hp >= hero.max_hp:
				continue
			if Board.distance(listener.position, hero.position) == 1:
				Support.heal(state, actor, hero, amount, events, form.label)
