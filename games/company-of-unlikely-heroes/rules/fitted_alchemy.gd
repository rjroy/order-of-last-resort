extends RefCounted
## Fitted recipes share the ordinary dose, splash and bottle lifecycle.

const Alchemy = preload("res://rules/alchemy.gd")
const Board = preload("res://rules/board.gd")

const DOSE_FORMS := {
	"buffer_solution": {"label": "Buffer Solution", "polarity": "heal"},
	"bitter_medicine": {"label": "Bitter Medicine", "polarity": "damage"},
	"sealing_paste": {"label": "Sealing Paste", "polarity": "heal"},
	"plain_solvent": {"label": "Plain Solvent", "polarity": "damage"},
}


static func describe(state: Dictionary, actor: Dictionary, source_id: String, base: Dictionary) -> Dictionary:
	var id: String = base.fitted_form
	var dose: Dictionary
	var label: String
	if id == "counterbatch":
		label = "Counterbatch"
		dose = Alchemy.bottled_dose(actor)
		if not dose.is_empty():
			dose.form = id
			dose.label = label
			dose.polarity = "heal" if dose.polarity == "damage" else "damage"
			dose.targeting = {"kind": "entity", "range": dose.targeting.range}
	else:
		var recipe: Dictionary = DOSE_FORMS.get(id, {})
		if recipe.is_empty():
			return {}
		label = recipe.label
		dose = Alchemy.resolved_dose(source_id, base, recipe.polarity, id, label)

	var reaction := Alchemy.dose_reaction(state, actor, dose)
	var choices := Alchemy.dose_choices(state, actor, dose)
	var reason := "no legal recipient"
	if id == "counterbatch":
		reason = "bottle empty" if dose.is_empty() else "no different legal recipient for the inverted dose"
	var form := {"id": id, "label": label, "help": _help(dose),
		"targeting": dose.get("targeting", {"kind": "entity"}), "choices": choices,
		"unavailable_reason": reason, "primary": "amount", "dose": dose, "reaction": reaction,
		"reaction_forecast": Alchemy.describe_reaction(reaction)}
	if id == "buffer_solution":
		form["standing_policy"] = "most_injured"
	return form


static func _help(dose: Dictionary) -> String:
	if dose.is_empty():
		return "Invert the bottled dose and give its exact reaction to a different legal recipient."
	var pulse := "Deal %d damage to a hostile character" if dose.polarity == "damage" \
		else "Heal a friendly character (including yourself) for %d HP"
	var help := (pulse % int(dose.amount)) + (" within %d tile(s)." % int(dose.targeting.range))
	if dose.has("recipient"):
		return help + " Choose a different recipient. The original reaction is unchanged; empties the bottle."
	if dose.source_handler == "plain_tonic":
		return help + " No reaction or bottle."
	return help + " The dose applies the forecast reaction using %s odds." % [
		"Acid" if dose.polarity == "damage" else "Potion"]


static func apply(state: Dictionary, actor: Dictionary, _source_id: String, _base: Dictionary,
		form: Dictionary, choice: Dictionary, bonus: int, events: Array) -> void:
	var target := Board.entity(state, choice.id)
	Alchemy.administer_resolved(state, actor, target, form.dose, form.reaction, bonus, events)
