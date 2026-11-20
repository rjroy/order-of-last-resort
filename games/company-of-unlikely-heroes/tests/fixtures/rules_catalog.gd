extends RefCounted
## Self-contained definitions for the rules unit tests, not game tuning.


static func definitions() -> Dictionary:
	var capabilities := {}
	for id in ["blocks_movement", "mobile", "pushable", "pullable", "damageable",
			"healable", "protectable", "tauntable", "commandable", "recoverable"]:
		capabilities[id] = {"label": id}
	var events := {}
	for id in ["move", "damage", "knockdown_suffix", "reflect_absorb", "reflect_redirect",
			"push", "collision_suffix", "aura", "taunt", "heal", "heal_full", "blast_suffix",
			"pull", "recoil_source", "cannot_advance", "recover", "hold", "invalid",
			"watches", "gain_status"]:
		events[id] = {"text": id}
	var common := ["blocks_movement", "mobile", "pushable", "pullable", "damageable", "protectable", "recoverable"]
	var heroes := common + ["healable", "commandable"]
	var enemies := common + ["tauntable"]
	return {
		"missions": {"fixture": {
			"title": "Unit fixture", "encounter": "fixture",
			"objective": {"handler": "escort", "subject": "civilian", "destination": "exit",
				"text": "Escort", "victory_text": "Victory", "defeat_text": "Defeat", "victory_event": "Victory"},
			"failures": [{"handler": "subject_dead", "event": "Subject lost"},
				{"handler": "deadline", "event": "Deadline"}]
		}},
		"encounters": {"fixture": {"board": "fixture", "deadline": 10, "placements": [
			{"id": "knight", "character": "knight", "at": [1, 1]},
			{"id": "healer", "character": "healer", "at": [0, 2]},
			{"id": "wizard", "character": "wizard", "at": [4, 2]},
			{"id": "harpooner", "character": "harpooner", "at": [5, 1]},
			{"id": "civilian", "character": "ferryman", "at": [1, 2]}
		]}},
		"boards": {"fixture": {"width": 12, "height": 12, "default_tile": "stone",
			"tiles": [], "locations": {"exit": [9, 9]}}},
		"tiles": {"stone": {"label": "Open", "art_key": "open", "passable": true}},
		"capabilities": capabilities,
		"classes": {
			"knight": _profile("heroes", heroes, ["move", "knight_push", "knight_aura"], {}),
			"healer": _profile("heroes", heroes, ["move", "healer_bonk", "healer_heal"], {}),
			"wizard": _profile("heroes", heroes, ["move", "wizard_blast", "wizard_pull"], {}),
			"enemy": _profile("enemies", enemies, ["move", "enemy_attack", "enemy_harpoon"], {}, "threat"),
			"civilian": _profile("civilian", common, ["move"], {}, "escort")
		},
		"characters": {
			"knight": {"class": "knight", "label": "Knight"},
			"healer": {"class": "healer", "label": "Healer"},
			"wizard": {"class": "wizard", "label": "Wizard"},
			"harpooner": {"class": "enemy", "label": "Enemy"},
			"ferryman": {"class": "civilian", "label": "Civilian"}
		},
		"objects": {"crate": {"label": "Crate", "art_key": "crate", "max_hp": 10,
			"capabilities": ["blocks_movement", "pushable", "damageable"]}},
		"abilities": {
			"move": _ability("move", {}, {"kind": "cell", "range": 1}),
			"knight_push": _ability("push", {"collision_damage": 2},
				{"kind": "entity", "range": 1, "objects": true, "capabilities": ["pushable"]}),
			"knight_aura": _ability("apply_status", {"status": "aura"}, {"kind": "none"}),
			"healer_bonk": _ability("bonk", {"damage": 2, "status": "taunt"},
				{"kind": "entity", "range": 1, "teams": ["enemies"], "objects": true, "capabilities": ["damageable"]}),
			"healer_heal": _ability("heal", {"amount": 3},
				{"kind": "automatic", "teams": ["heroes"], "capabilities": ["healable"]}),
			"wizard_blast": _ability("blast", {"damage": 4, "status": "knockdown"},
				{"kind": "automatic", "objects": true, "capabilities": ["damageable"]}),
			"wizard_pull": _ability("pull", {"recoil_damage": 2, "status": "knockdown"},
				{"kind": "entity", "capabilities": ["pullable"]}),
			"enemy_attack": _ability("attack", {"damage": 2}, {"kind": "entity", "range": 1}),
			"enemy_harpoon": _ability("attack", {"damage": 2}, {"kind": "entity", "range": 2})
		},
		"orders": {},
		"behaviors": {
			"threat": {"handler": "threat", "params": {"ability": "enemy_harpoon",
				"move_ability": "move", "pursue_range": 5, "fallback_teams": ["heroes", "civilian"],
				"taunt_status": "taunt"}},
			"escort": {"handler": "escort", "params": {"move_ability": "move"}}
		},
		"statuses": {
			"aura": {"label": "Aura", "handler": "reflect", "expiry": "actor_turn_start",
				"params": {"range": 1, "teams": ["enemies"], "objects": true}},
			"knockdown": {"label": "Down", "handler": "skip_action", "expiry": "consume_action", "params": {}},
			"taunt": {"label": "Taunt", "handler": "retarget", "expiry": "actor_turn_end",
				"params": {"teams": ["heroes"]}}
		},
		"events": events,
		"presentation": {}
	}


static func _profile(team: String, capabilities: Array, abilities: Array, habits: Dictionary,
		behavior := "") -> Dictionary:
	var profile := {"team": team, "art_key": "unit", "max_hp": 10,
		"capabilities": capabilities, "abilities": abilities, "habits": habits}
	if not behavior.is_empty():
		profile["behavior"] = behavior
	return profile


static func _ability(handler: String, params: Dictionary, targeting: Dictionary) -> Dictionary:
	return {"label": handler, "help": handler, "handler": handler, "params": params, "targeting": targeting}
