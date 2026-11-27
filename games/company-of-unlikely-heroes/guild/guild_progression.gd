extends RefCounted
## Resolves owned roster, petitions, and expedition kits from the optional authored guild tables.

const Catalog = preload("res://content/catalog.gd")
const HOLD_ORDER := "order_hold"
const HOLD_BEHAVIOR := "hold"


static func roster(defs: Dictionary, profile: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var authored: Array = defs.get("commission_settings", {}).get("recruitment_roster", [])
	for id in authored:
		if id in profile.get("recruited_ids", []) and _kits(defs).has(id):
			result.append(id)
	return result


static func petitions(defs: Dictionary, profile: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var table := _petitions(defs)
	for id in table:
		var spec: Dictionary = table[id]
		var grant: Dictionary = spec.get("grant", {})
		var cost := int(spec.get("cost", 0))
		var purchasable: bool = not spec.get("teaser", false)
		var owned := _owns_petition(profile, table, id)
		var missing: Array[String] = []
		for dependency in spec.get("prerequisites", []):
			if not _owns_petition(profile, table, dependency):
				missing.append(dependency)
		var recipient: String = grant.get("hero_id", "")
		var missing_labels: Array[String] = []
		for dependency in missing:
			missing_labels.append(str(table[dependency].label))
		var dependency_labels: Array[String] = []
		for dependency in spec.get("prerequisites", []):
			dependency_labels.append(str(table[dependency].label))
		var recipient_locked: bool = not grant.is_empty() and grant.kind != "recruit" \
			and recipient not in profile.get("recruited_ids", [])
		var affordable: bool = profile.get("points", 0) >= cost
		rows.append({"id": id, "label": spec.label, "description": spec.description, "cost": cost,
			"owned": owned, "purchasable": purchasable, "affordable": affordable,
			"can_buy": purchasable and not owned and not recipient_locked and missing.is_empty() and affordable,
			"missing_prerequisites": missing, "missing_prerequisite_labels": missing_labels,
			"prerequisites": spec.get("prerequisites", []).duplicate(), "prerequisite_labels": dependency_labels,
			"recipient_locked": recipient_locked, "hero_id": recipient,
			"recipient_label": Catalog.profile(defs, recipient).get("label", recipient),
			"grant_kind": grant.get("kind", "")})
	return rows


static func purchased_profile(defs: Dictionary, profile: Dictionary, petition_id: String) -> Dictionary:
	for row in petitions(defs, profile):
		if row.id != petition_id:
			continue
		if not row.can_buy:
			return {"error": "This petition cannot be approved."}
		var result := profile.duplicate(true)
		result.points -= row.cost
		result.purchased_ids.append(petition_id)
		var grant: Dictionary = _petitions(defs)[petition_id].grant
		if grant.kind == "recruit":
			result.recruited_ids.append(grant.hero_id)
		return result
	return {"error": "Unknown guild petition."}


static func _owns_petition(profile: Dictionary, table: Dictionary, id: String) -> bool:
	var spec: Dictionary = table.get(id, {})
	if spec.is_empty() or spec.get("teaser", false):
		return false
	var grant: Dictionary = spec.get("grant", {})
	if grant.get("kind") == "recruit":
		# A legacy guild already owns the recruitment benefit without paying for it.
		return grant.hero_id in profile.get("recruited_ids", [])
	return id in profile.get("purchased_ids", [])


static func slot_options(defs: Dictionary, profile: Dictionary, hero_id: String,
		playtest := false) -> Dictionary:
	if (not playtest and hero_id not in roster(defs, profile)) or not _kits(defs).has(hero_id):
		return {}
	var slots: Dictionary = _kits(defs)[hero_id]
	var result: Dictionary = {}
	for slot_id in slots:
		var choices: Array[String] = [slots[slot_id]]
		result[slot_id] = choices
	for grant in _owned_grants(defs, profile, hero_id):
		if grant.kind == "ability" and grant.ability_id not in result[grant.slot_id]:
			result[grant.slot_id].append(grant.ability_id)
	return result


static func default_loadout(defs: Dictionary, profile: Dictionary, hero_id: String,
		playtest := false, legacy_precedence := true) -> Dictionary:
	var choices := slot_options(defs, profile, hero_id, playtest)
	if choices.is_empty():
		return {}
	var preference: Dictionary = profile.get("preferred_loadouts", {}).get(hero_id, {})
	if not effective_kit(defs, profile, hero_id, preference, playtest, legacy_precedence).is_empty():
		return preference.duplicate(true)
	# Retire only the stock ability. A custom catalog that still defines it
	# retains its own slot and preference semantics.
	if hero_id == "healer" and not defs.get("abilities", {}).has("healer_field_dressing") \
			and not _petitions(defs).has("healer_field_dressing") \
			and preference.get("slots", {}) is Dictionary \
			and preference.get("slots", {}).get("utility") == "healer_field_dressing":
		var recovered := preference.duplicate(true)
		recovered.slots.utility = "healer_heal"
		if not effective_kit(defs, profile, hero_id, recovered, playtest, legacy_precedence).is_empty():
			return recovered
	var slots: Dictionary = {}
	var saved_slots: Variant = preference.get("slots", {})
	for slot_id in choices:
		var saved: Variant = saved_slots.get(slot_id) if saved_slots is Dictionary else null
		slots[slot_id] = saved if saved is String and saved in choices[slot_id] else choices[slot_id][0]
	if _equipped_abilities(defs, profile, hero_id, {"slots": slots}, playtest).is_empty():
		for slot_id in choices:
			slots[slot_id] = choices[slot_id][0]
	var loadout := {"slots": slots, "order_id": Catalog.profile(defs, hero_id).get("default_order", "")}
	var orders := order_options(defs, profile, hero_id, loadout, playtest, legacy_precedence)
	var authored_starters: Dictionary = defs.get("guild_progression", {}).get("starting_habits", {})
	var authored_defaults: Dictionary = defs.get("guild_progression", {}).get("starting_defaults", {})
	if not playtest and authored_starters.has(hero_id):
		for order in orders:
			if order.id == authored_defaults.get(hero_id, "") and order.compatible:
				loadout.order_id = order.id
				return loadout
		for order in orders:
			if order.id in authored_starters[hero_id] and order.compatible:
				loadout.order_id = order.id
				return loadout
	for order in orders:
		if order.id == loadout.order_id and order.compatible:
			return loadout
	for order in orders:
		if order.compatible:
			loadout.order_id = order.id
			return loadout
	return {}


## Resolve explicit standalone choices against the same slot and order rules as
## guild appointments, without a guild roster, purchases, or passive grants.
static func playtest_kit(defs: Dictionary, hero_id: String, fields: Dictionary,
		legacy_precedence := true) -> Dictionary:
	var profile := {"recruited_ids": [], "purchased_ids": [], "preferred_loadouts": {}}
	for petition_id in _petitions(defs):
		var spec: Dictionary = _petitions(defs)[petition_id]
		if not spec.get("teaser", false) and spec.get("grant", {}).get("kind") in ["ability", "order"]:
			profile.purchased_ids.append(petition_id)
	var loadout := default_loadout(defs, profile, hero_id, true, legacy_precedence)
	if loadout.is_empty():
		if not _kits(defs).has(hero_id):
			return {"error": "Hero '%s' has no configurable catalog kit." % hero_id}
		loadout = {"slots": _kits(defs)[hero_id].duplicate(), "order_id": ""}
	for field in fields:
		if field == "order":
			loadout.order_id = fields[field]
		elif not loadout.slots.has(field):
			return {"error": "Hero '%s' has no '%s' loadout slot." % [hero_id, field]}
		else:
			loadout.slots[field] = fields[field]
	var kit := effective_kit(defs, profile, hero_id, loadout, true, legacy_precedence)
	if kit.is_empty():
		var choices := slot_options(defs, profile, hero_id, true)
		for slot in loadout.slots:
			if loadout.slots[slot] not in choices[slot]:
				return {"error": "Hero '%s': ability '%s' is invalid for slot '%s'. Available IDs: %s." % [
					hero_id, loadout.slots[slot], slot, ", ".join(choices[slot])]}
		var orders := order_options(defs, profile, hero_id, loadout, true, legacy_precedence)
		if orders.is_empty():
			if not _equipped_abilities(defs, profile, hero_id, loadout, true).is_empty():
				return {"error": "Hero '%s': order '%s' cannot be selected; no orders are available for this kit." % [
					hero_id, loadout.order_id]}
			return {"error": "Hero '%s': equipped slot abilities %s conflict or duplicate an existing ability; choose distinct abilities. Available slot IDs: %s." % [
				hero_id, str(loadout.slots), str(choices)]}
		var available: Array[String] = []
		var selected := {}
		for row in orders:
			if row.compatible:
				available.append(row.id)
			if row.id == loadout.order_id:
				selected = row
		var alternatives := ", ".join(available) if not available.is_empty() else "(none)"
		if selected.is_empty():
			return {"error": "Hero '%s': unknown or unavailable order '%s'. Compatible order IDs: %s." % [
				hero_id, loadout.order_id, alternatives]}
		return {"error": "Hero '%s': order '%s' is incompatible; missing equipped abilities: %s. Compatible order IDs: %s." % [
			hero_id, loadout.order_id, ", ".join(selected.missing_abilities), alternatives]}
	return {"kit": kit}


static func order_options(defs: Dictionary, profile: Dictionary, hero_id: String,
		loadout: Dictionary, playtest := false, legacy_precedence := true) -> Array[Dictionary]:
	var abilities := _equipped_abilities(defs, profile, hero_id, loadout, playtest)
	return _order_rows(defs, profile, hero_id, abilities, loadout.slots, playtest, legacy_precedence) if not abilities.is_empty() else []


static func effective_kit(defs: Dictionary, profile: Dictionary, hero_id: String, loadout: Dictionary,
		playtest := false, legacy_precedence := true) -> Dictionary:
	if loadout.size() != 2 or not loadout.get("order_id") is String:
		return {}
	var abilities := _equipped_abilities(defs, profile, hero_id, loadout, playtest)
	if abilities.is_empty():
		return {}
	var habits: Dictionary = {}
	for row in _order_rows(defs, profile, hero_id, abilities, loadout.slots, playtest, legacy_precedence):
		if row.compatible:
			habits[row.id] = row.behavior_id
	if not habits.has(loadout.order_id):
		return {}
	var techniques: Array[String] = []
	for grant in _owned_grants(defs, profile, hero_id):
		if grant.kind == "effect" and grant.effect_id not in techniques:
			techniques.append(grant.effect_id)
	return {"abilities": abilities, "habits": habits, "default_order": loadout.order_id,
		"equipped_slots": loadout.slots.duplicate(),
		"guild_techniques": techniques}


static func valid_loadouts(defs: Dictionary, profile: Dictionary, loadouts: Dictionary) -> bool:
	for hero_id in loadouts:
		if not hero_id is String or not loadouts[hero_id] is Dictionary \
				or effective_kit(defs, profile, hero_id, loadouts[hero_id]).is_empty():
			return false
	return true


static func _equipped_abilities(defs: Dictionary, profile: Dictionary, hero_id: String,
		loadout: Dictionary, playtest := false) -> Array[String]:
	var choices := slot_options(defs, profile, hero_id, playtest)
	var slots: Variant = loadout.get("slots")
	if choices.is_empty() or not slots is Dictionary or slots.size() != choices.size():
		return []
	var base_slots: Dictionary = _kits(defs)[hero_id]
	var equipped: Array[String] = []
	# Keep authored action order (including unslotted Move); substitute slot choices in place.
	for ability in Catalog.profile(defs, hero_id).abilities:
		var slot_id: Variant = base_slots.find_key(ability)
		var id: Variant = ability if slot_id == null else slots.get(slot_id)
		if not id is String or (slot_id != null and id not in choices[slot_id]) or id in equipped:
			return []
		equipped.append(id)
	return equipped


static func _starting_habits(defs: Dictionary, hero_id: String) -> Dictionary:
	var starting: Dictionary = defs.get("guild_progression", {}).get("starting_habits", {})
	return starting.get(hero_id, Catalog.profile(defs, hero_id).get("habits", {}))


static func _order_rows(defs: Dictionary, profile: Dictionary, hero_id: String,
		abilities: Array[String], slots: Dictionary, playtest := false,
		legacy_precedence := true) -> Array[Dictionary]:
	var starting := _starting_habits(defs, hero_id)
	var legacy: Dictionary = Catalog.profile(defs, hero_id).get("habits", {}) if playtest else {}
	var habits := starting.duplicate()
	for grant in _owned_grants(defs, profile, hero_id):
		if grant.kind == "order":
			habits[grant.order_id] = grant.behavior_id
	# Stock standalone keeps its original habits; external guild definitions
	# take precedence over raw character habits on matching IDs.
	habits.merge(legacy, legacy_precedence)
	var rows: Array[Dictionary] = []
	var any_compatible := false
	var legacy_compatible := false
	for id in habits:
		var behavior_id: String = habits[id]
		var behavior: Dictionary = defs.behaviors[behavior_id]
		var missing := Catalog.behavior_ability_ids(behavior)
		var params: Dictionary = behavior.get("params", {})
		var slot: String = params.get("ability_slot", "")
		if not slot.is_empty():
			var base: String = _kits(defs).get(hero_id, {}).get(slot, "")
			if base == params.get("ability", ""):
				var index: int = Catalog.profile(defs, hero_id).abilities.find(base)
				if index >= 0 and index < abilities.size():
					var equipped: String = abilities[index]
					var targeting: Dictionary = defs.abilities[equipped].get("targeting", {})
					var teams: Array = targeting.get("teams", [])
					if targeting.get("kind") == "entity" and (teams.is_empty() or params.get("team") in teams):
						missing.erase(base)
		for ability in abilities:
			missing.erase(ability)
		var compatible := missing.is_empty()
		any_compatible = any_compatible or compatible
		legacy_compatible = legacy_compatible or (legacy.has(id) and compatible)
		rows.append({"id": id, "label": defs.orders[id].label, "behavior_id": behavior_id,
			"compatible": compatible, "missing_abilities": missing})
	# Retain a previously saved fallback only for its exact equipped slots.
	var preference: Variant = profile.get("preferred_loadouts", {}).get(hero_id, {})
	var saved_hold: bool = not playtest and preference is Dictionary and preference.size() == 2 \
		and preference.get("order_id") == HOLD_ORDER and preference.get("slots") == slots
	var legacy_fallback := playtest and not legacy_compatible
	if (not any_compatible or saved_hold or legacy_fallback) and not habits.has(HOLD_ORDER) \
			and defs.orders.has(HOLD_ORDER) and defs.behaviors.has(HOLD_BEHAVIOR):
		rows.append({"id": HOLD_ORDER, "label": defs.orders[HOLD_ORDER].label, "behavior_id": HOLD_BEHAVIOR,
			"compatible": true, "missing_abilities": []})
	return rows


static func _owned_grants(defs: Dictionary, profile: Dictionary, hero_id: String) -> Array[Dictionary]:
	var grants: Array[Dictionary] = []
	var table := _petitions(defs)
	for id in table:
		var grant: Dictionary = table[id].get("grant", {})
		if grant.get("hero_id") == hero_id and _owns_petition(profile, table, id):
			grants.append(grant)
	return grants


static func _kits(defs: Dictionary) -> Dictionary:
	return defs.get("guild_progression", {}).get("kits", {})


static func _petitions(defs: Dictionary) -> Dictionary:
	return defs.get("guild_progression", {}).get("petitions", {})
