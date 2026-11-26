extends RefCounted
## Presentation copy and art for guild petitions. Eligibility comes from GuildProfile.

const Art = preload("res://presentation/book/guild_book_art.gd")

const PRESENTATION := {
	"recruit_bard": {
		"plate_id": "bard", "preview_title": "The Bad Bard",
		"short_title": "Recruit the Bad Bard", "short_summary": "A new hero to choose",
		"details": ["Starts with Inspiring Melody and Healing Sonnet.",
			"Choose him for one of your three party places."],
		"note": "Party and loadouts stay unchanged.",
		"buy_label": "Recruit Bad Bard",
	},
	"teach_healer_blast": {
		"plate_id": "healer_blast", "preview_title": "Blast training",
		"short_title": "Teach the Healer: Blast", "short_summary": "Blast can replace Bonk",
		"details": ["Hits the nearest damageable target, even an ally or obstacle.",
			"At recruitment, equip Blast instead of Bonk."],
		"note": "The Healer keeps Bonk until you switch their offense.",
		"buy_label": "Teach Blast",
	},
}


static func rows(definitions: Dictionary, petitions: Array) -> Array:
	var result: Array = []
	var characters: Dictionary = definitions.get("characters", {})
	var specs: Dictionary = definitions.get("guild_progression", {}).get("petitions", {})
	for petition in petitions:
		var id := str(petition.id)
		var owned := bool(petition.owned)
		var purchasable := bool(petition.purchasable)
		var can_buy := bool(petition.can_buy)
		var hero_id := str(petition.get("hero_id", ""))
		var recipient := str(petition.get("recipient_label", ""))
		var grant: Dictionary = specs.get(id, {}).get("grant", {})
		var kind := str(petition.get("grant_kind", ""))
		var requirements := PackedStringArray(petition.get("missing_prerequisite_labels", []))
		var requirement := ""
		if not owned and not requirements.is_empty():
			requirement = "Requires: " + ", ".join(requirements)
		elif not owned and bool(petition.get("recipient_locked", false)):
			requirement = "Recruit %s first." % recipient
		var status := "available"
		if owned:
			status = "owned"
		elif not purchasable:
			status = "teaser"
		elif not requirement.is_empty():
			status = "locked"
		elif not can_buy:
			status = "unaffordable"
		var display: Dictionary = PRESENTATION.get(id, {})
		var portrait_id := str(characters.get(hero_id, {}).get("guild_portrait", ""))
		result.append({
			"id": id, "title": str(petition.label), "summary": str(petition.description),
			"short_title": str(display.get("short_title", petition.label)),
			"short_summary": str(display.get("short_summary", _grant_label(kind, grant))),
			"cost": int(petition.cost), "status": status, "requirement": requirement,
			"preview_title": str(display.get("preview_title", petition.label)),
			"portrait": Art.class_portrait(portrait_id),
			"details": display.get("details", _details(str(petition.description), kind, grant)),
			"note": str(display.get("note", _purchase_note(kind))),
			"buy_label": str(display.get("buy_label", "Purchase")),
			"hero_id": hero_id, "recipient_label": recipient, "grant_kind": kind,
			"owned": owned, "purchasable": purchasable, "can_buy": can_buy,
		})
	return result


## The register leads with heroes the guild has already recruited, then reads
## each tier alphabetically by the player-visible name.
static func ordered_hero_options(options: Array, recruited_ids: Array) -> Array:
	var ordered := options.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_recruited := str(a.get("id", "")) in recruited_ids
		var b_recruited := str(b.get("id", "")) in recruited_ids
		if a_recruited != b_recruited:
			return a_recruited
		return str(a.get("label", "")).to_lower() < str(b.get("label", "")).to_lower())
	return ordered


## Rows in register order: hero sections follow `options`, each hero keeps its
## authored row order, and rows for heroes missing from `options` go last.
static func ordered_rows(rows: Array, options: Array) -> Array:
	var hero_ids: Array[String] = []
	for option: Dictionary in options:
		hero_ids.append(str(option.id))
	var ordered: Array = []
	for hero_id in hero_ids:
		for row: Dictionary in rows:
			if str(row.get("hero_id", "")) == hero_id:
				ordered.append(row)
	for row: Dictionary in rows:
		if str(row.get("hero_id", "")) not in hero_ids:
			ordered.append(row)
	return ordered


static func action_plate(id: String) -> Texture2D:
	# Most plates use the petition ID; the two original crops predate that convention.
	var display: Dictionary = PRESENTATION.get(id, {})
	if display.has("plate_id"):
		return Art.petition(str(display.plate_id))
	# Explicit aliases belong only to their petitions, not to IDs matching their filenames.
	for entry: Dictionary in PRESENTATION.values():
		if entry.get("plate_id", "") == id:
			return null
	return Art.petition(id)


static func _grant_label(kind: String, grant: Dictionary) -> String:
	match kind:
		"recruit":
			return "A new hero to choose"
		"ability":
			return "Utility option" if grant.get("slot_id", "") == "utility" else "Offense option"
		"order":
			return "Starting order option"
	return ""


static func _details(description: String, kind: String, grant: Dictionary) -> Array:
	var details := [description]
	match kind:
		"recruit":
			details.append("Choose this hero for one of your three party places.")
		"ability":
			var slot := "Utility" if grant.get("slot_id", "") == "utility" else "Offense"
			details.append("Equip it under %s in Edit loadout." % slot)
		"order":
			details.append("Choose it under Starting order in Edit loadout when its required abilities are equipped.")
	return details


static func _purchase_note(kind: String) -> String:
	if kind == "recruit":
		return "Party and loadouts stay unchanged."
	if kind == "ability" or kind == "order":
		return "Your current loadout stays unchanged."
	return ""
