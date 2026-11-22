extends RefCounted
## The roll belongs to the dose, not to the target or the shared encounter RNG.

const EncounterRandom = preload("res://rules/encounter_random.gd")
const POOLS := {
	"beneficial": {
		"emergency_crust": {"label": "Emergency Crust", "description": "Absorbs 1 damage from the next hit."},
		"second_helping": {"label": "Second Helping", "description": "Heals 1 HP at this round's end if still standing."},
		"cork_soles": {"label": "Cork Soles", "description": "Blocks the next forced move."},
		"stiff_upper_lip": {"label": "Stiff Upper Lip", "description": "Blocks the next knockdown."},
		"pocket_paramedic": {"label": "Pocket Paramedic", "description": "The next lethal hit leaves this character at 1 HP."},
		"good_company": {"label": "Good Company", "description": "Heals 1 HP at this round's end if standing beside a friend."},
		"duck": {"label": "Duck!", "description": "Reduces the next hit from more than one tile away by 1."},
		"medicinal_aftertaste": {"label": "Medicinal Aftertaste", "description": "The next heal restores 1 extra HP."},
	},
	"harmful": {
		"thin_skinned": {"label": "Thin-Skinned", "description": "The next hit deals 1 extra damage."},
		"repeating_lunch": {"label": "Repeating Lunch", "description": "Loses 1 HP at this round's end if still standing."},
		"ball_bearings": {"label": "Ball Bearings", "description": "The next forced move goes 1 extra tile if clear."},
		"jelly_knees": {"label": "Jelly Knees", "description": "Knocked down now; spends the next turn getting up."},
		"no_refills": {"label": "No Refills", "description": "The next heal restores 1 less HP."},
		"stage_fright": {"label": "Stage Fright", "description": "Loses 1 HP at this round's end if standing beside a foe."},
		"handle_with_care": {"label": "Handle With Care", "description": "The next hit from an adjacent source deals 1 extra damage."},
		"boot_toffee": {"label": "Boot Toffee", "description": "Blocks the next voluntary move."},
	},
	"cosmetic": {
		"upward_rain": {"label": "Upward Rain", "description": "A tiny rainstorm falls up."},
		"cork_moon": {"label": "Cork Moon", "description": "A cork circles their head like a tiny moon."},
		"fine_bubbles": {"label": "FINE Bubbles", "description": "Bubbles spell FINE, then pop one by one."},
		"spectral_napkin": {"label": "Spectral Napkin", "description": "A ghostly napkin unfolds with a flourish."},
	},
}
const ROUND_END := {
	"second_helping": {"heal": true},
	"good_company": {"heal": true, "adjacency": "friendly"},
	"repeating_lunch": {"heal": false},
	"stage_fright": {"heal": false, "adjacency": "hostile"},
}


static func draw(seed_value: int, is_acid: bool) -> Dictionary:
	var bucket := EncounterRandom.uniform_draw(seed_value, 100)
	var category := "cosmetic"
	if bucket.index < 90:
		category = "beneficial" if (bucket.index < 70) != is_acid else "harmful"
	var ids: Array = POOLS[category].keys()
	var choice := EncounterRandom.uniform_draw(bucket.seed, ids.size())
	return {"id": ids[choice.index], "category": category, "seed": choice.seed}


static func description(id: String, category: String) -> String:
	var spec: Dictionary = POOLS[category][id]
	var expiry := ""
	if category != "cosmetic" and id != "jelly_knees" and not ROUND_END.has(id):
		expiry = " Expires at the end of the next round if unused."
	elif category == "cosmetic":
		expiry = " No gameplay effect."
	return "%s — %s%s" % [spec.label, spec.description, expiry]
