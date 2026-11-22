extends RefCounted
## Presentation copy and art for guild petitions. Eligibility comes from GuildProfile.

const Art = preload("res://presentation/guild_book_art.gd")

const PRESENTATION := {
	"recruit_bard": {
		"plate_id": "bard", "preview_title": "The Bad Bard",
		"short_title": "Recruit the Bad Bard", "short_summary": "A new hero to choose",
		"details": ["Starts with Inspiring Melody and Healing Sonnet.",
			"Choose him for one of your three party places."],
		"note": "Party and loadouts stay unchanged.",
		"buy_label": "Recruit Bad Bard · %d points",
	},
	"teach_healer_blast": {
		"plate_id": "healer_blast", "preview_title": "Blast training",
		"short_title": "Teach the Healer: Blast", "short_summary": "Blast can replace Bonk",
		"details": ["Hits the nearest damageable target, even an ally or obstacle.",
			"At recruitment, equip Blast instead of Bonk."],
		"note": "The Healer keeps Bonk until you switch their offense.",
		"buy_label": "Teach Blast · %d points",
	},
}


static func rows(definitions: Dictionary, petitions: Array) -> Array:
	var result: Array = []
	for petition in petitions:
		var id := str(petition.id)
		var owned := bool(petition.owned)
		var purchasable := bool(petition.purchasable)
		var can_buy := bool(petition.can_buy)
		var missing: Array = petition.get("missing_prerequisites", [])
		var note := ""
		if not missing.is_empty():
			var names := PackedStringArray()
			var specs: Dictionary = definitions.get("guild_progression", {}).get("petitions", {})
			for prerequisite in missing:
				names.append(str(specs.get(prerequisite, {}).get("label", prerequisite)))
			note = "Requires: " + ", ".join(names)
		elif bool(petition.get("recipient_locked", false)):
			note = "Recruit the hero before purchasing this petition."
		elif purchasable and not owned and not can_buy:
			note = "Not enough guild points."
		elif not purchasable:
			note = "Not available yet."
		var status_text := "Purchased" if owned else ("Available" if can_buy else note)
		var display: Dictionary = PRESENTATION.get(id, {})
		var display_note := str(display.get("note", ""))
		if not display_note.is_empty():
			note = (note + "\n" if not note.is_empty() else "") + display_note
		var plate_id := str(display.get("plate_id", ""))
		var hero_id := str(petition.get("hero_id", ""))
		var portrait_id := str(definitions.get("characters", {}).get(hero_id, {}).get("guild_portrait", ""))
		var buy_label := str(display.get("buy_label", "Purchase · %d points")) % int(petition.cost)
		result.append({
			"id": id, "title": str(petition.label), "summary": str(petition.description),
			"short_title": str(display.get("short_title", petition.label)),
			"short_summary": str(display.get("short_summary", petition.description)),
			"cost": int(petition.cost), "status": "owned" if owned else ("available" if can_buy else "locked"),
			"status_text": status_text,
			"preview_title": str(display.get("preview_title", petition.label)),
			"portrait": Art.class_portrait(portrait_id),
			"plate": Art.petition(plate_id) if not plate_id.is_empty() else null,
			"plate_id": plate_id,
			"details": display.get("details", [str(petition.description)]), "note": note,
			"buy_label": "Purchased" if owned else buy_label,
			"owned": owned, "purchased": owned, "purchasable": purchasable, "can_buy": can_buy,
		})
	return result
